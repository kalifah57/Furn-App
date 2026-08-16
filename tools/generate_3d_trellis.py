#!/usr/bin/env python3
"""Cloud 3D pipeline: catalog.json -> TRELLIS.2 (4B) -> GLB assets + registry.

The CUDA counterpart of tools/generate_3d.py, built for a rented GPU box
(A100-class, Ubuntu). Same catalogue in, same registry contract out, same
true-scale conversion — only the model differs: Microsoft's TRELLIS.2-4B,
run at maximum quality (1536 cascade, 4K PBR textures, remeshing on).
Defaults favour fidelity over speed everywhere; see tools/README_TRELLIS.md
for the instance setup.

Licence posture (the reason this file exists in this shape): TRELLIS.2 code
and weights are MIT, but its stock GLB export imports nvdiffrast — NVIDIA
Source Code License, research/evaluation only. This adapter installs the
MIT-licensed rasteriser from tools/trellis_mit_rasterizer.py BEFORE anything
imports o_voxel, so the commercial asset path never touches nvdiffrast. Pass
--allow-nvdiffrast to use the NVIDIA library instead (research/evaluation
runs only — do not ship those assets).

Outputs (identical contract to the SF3D adapter)
    Assets/3D_Models/<slug>_<id>.glb      one textured mesh per product
    Catalog_Fin/3D_Catalog_new.json       [{internal_id, store_id, local_3d_path}]
    Catalog_Fin/3D_Catalog_failures.json  written only when something failed

Usage (on the GPU instance, venv active)
    python tools/trellis_mit_rasterizer.py --self-test   # once, before a batch
    python tools/generate_3d_trellis.py --limit 1        # smoke test
    python tools/generate_3d_trellis.py                  # full catalogue
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

# Must precede torch import: lets the allocator grow segments instead of
# fragmenting — TRELLIS.2's own example sets exactly this.
os.environ.setdefault("PYTORCH_CUDA_ALLOC_CONF", "expandable_segments:True")

import requests  # noqa: E402
import torch  # noqa: E402
from tqdm import tqdm  # noqa: E402

from pipeline_common import (  # noqa: E402
    DEFAULT_CATALOG,
    DEFAULT_OUT_DIR,
    DEFAULT_REGISTRY,
    DISTORTION_REPORT_THRESHOLD,
    atomic_write_json,
    fetch_image,
    image_url_candidates,
    load_catalog,
    mesh_filename,
    product_dimensions,
    product_id,
    product_image_url,
    rebuild_registry,
    scale_mesh_to_catalog,
)

DEFAULT_TRELLIS_DIR = Path(__file__).resolve().parent.parent / "vendor" / "TRELLIS.2"
PRETRAINED_MODEL = "microsoft/TRELLIS.2-4B"

# TRELLIS.2 downscales any input so its long side is at most 1024px
# (preprocess_image), so that is the useful ceiling for source images.
COND_SIZE = 1024


def import_trellis(trellis_dir: Path, allow_nvdiffrast: bool):
    """Put the TRELLIS.2 checkout on sys.path and import it nvdiffrast-free.

    Order matters: the MIT rasteriser must be registered before o_voxel is
    imported anywhere, because o_voxel/__init__.py imports postprocess, which
    does `import nvdiffrast.torch` at module level.
    """
    if not (trellis_dir / "trellis2" / "pipelines").is_dir():
        sys.exit(
            f"TRELLIS.2 source not found at {trellis_dir}.\n"
            "Clone it first:\n"
            f"    git clone --recursive https://github.com/microsoft/TRELLIS.2 {trellis_dir}\n"
            "then follow tools/README_TRELLIS.md."
        )
    sys.path.insert(0, str(trellis_dir))

    if allow_nvdiffrast:
        try:
            import nvdiffrast.torch  # noqa: F401
            print(
                "NOTE: using NVIDIA nvdiffrast (research/evaluation licence). "
                "Assets from this run must not be used commercially."
            )
        except ImportError:
            sys.exit(
                "--allow-nvdiffrast was passed but nvdiffrast is not installed."
            )
    else:
        import trellis_mit_rasterizer

        if not trellis_mit_rasterizer.install():
            sys.exit(
                "nvdiffrast was already imported before the MIT rasteriser "
                "could be installed — import order bug, please report."
            )
        print("Texture bake: MIT rasteriser (nvdiffrast-free).")

    try:
        import o_voxel
        from trellis2.pipelines import Trellis2ImageTo3DPipeline
    except ImportError as exc:
        sys.exit(
            f"Found the TRELLIS.2 checkout at {trellis_dir} but importing it "
            f"failed:\n    {exc}\n"
            "Dependencies are probably missing — follow tools/README_TRELLIS.md "
            "(torch cu124 wheel, requirements-trellis.txt, then the CuMesh / "
            "FlexGEMM / o-voxel extension builds)."
        )
    return o_voxel, Trellis2ImageTo3DPipeline


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("--catalog", type=Path, default=DEFAULT_CATALOG)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUT_DIR)
    parser.add_argument("--registry", type=Path, default=DEFAULT_REGISTRY)
    parser.add_argument(
        "--trellis-dir",
        type=Path,
        default=Path(os.environ.get("TRELLIS2_DIR", DEFAULT_TRELLIS_DIR)),
        help="Path to the TRELLIS.2 checkout (env: TRELLIS2_DIR).",
    )
    parser.add_argument("--limit", type=int, default=0, help="Process only the first N products.")
    parser.add_argument("--only", default="", help="Process a single product id (e.g. s79482824).")
    parser.add_argument("--force", action="store_true", help="Regenerate meshes that already exist.")
    parser.add_argument(
        "--pipeline-type",
        choices=("512", "1024", "1024_cascade", "1536_cascade"),
        default="1536_cascade",
        help="TRELLIS.2 resolution path. 1536_cascade is the highest fidelity.",
    )
    parser.add_argument(
        "--steps",
        type=int,
        default=0,
        help=(
            "Override sampler steps for all three stages (sparse structure, "
            "shape, texture). 0 keeps the pipeline's tuned defaults."
        ),
    )
    parser.add_argument(
        "--guidance",
        type=float,
        default=0.0,
        help="Override guidance strength for all three stages. 0 keeps defaults.",
    )
    parser.add_argument("--seed", type=int, default=42, help="Sampling seed (per run, not per product).")
    parser.add_argument(
        "--max-tokens",
        type=int,
        default=49152,
        help="Token budget for the cascade stages (TRELLIS.2 default 49152).",
    )
    parser.add_argument(
        "--texture-size",
        type=int,
        default=4096,
        help="Baked PBR texture atlas size (TRELLIS.2's own example uses 4096).",
    )
    parser.add_argument(
        "--decimation-target",
        type=int,
        default=1_000_000,
        help="Vertex budget after decimation; 1M matches TRELLIS.2's example.",
    )
    parser.add_argument(
        "--no-remesh",
        action="store_true",
        help="Skip the remeshing pass in GLB export (faster, worse topology).",
    )
    parser.add_argument(
        "--low-vram",
        action="store_true",
        help="Offload the background-removal model between products.",
    )
    parser.add_argument(
        "--allow-nvdiffrast",
        action="store_true",
        help=(
            "Use NVIDIA nvdiffrast for the texture bake instead of the MIT "
            "rasteriser. Research/evaluation only — assets generated this way "
            "must not be used commercially."
        ),
    )
    parser.add_argument(
        "--no-scale",
        action="store_true",
        help="Emit the raw normalised mesh (NOT AR-placeable).",
    )
    parser.add_argument(
        "--no-image-upscale",
        action="store_true",
        help="Download image_url exactly as catalogued.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    if not torch.cuda.is_available():
        sys.exit(
            "No CUDA device available. TRELLIS.2-4B requires an NVIDIA GPU "
            "(>=24GB VRAM; verified on A100/H100). For Apple Silicon, use "
            "tools/generate_3d.py (SF3D) instead."
        )
    gpu = torch.cuda.get_device_properties(0)
    vram_gb = gpu.total_memory / (1024**3)
    print(f"GPU: {gpu.name} ({vram_gb:.0f} GB)")
    if vram_gb < 23:
        print(
            "WARNING: TRELLIS.2 is verified on >=24GB GPUs; this run may OOM. "
            "Consider --pipeline-type 1024 and --texture-size 2048."
        )

    full_catalog = load_catalog(args.catalog)
    catalog = full_catalog
    if args.only:
        catalog = [r for r in catalog if product_id(r) == args.only]
        if not catalog:
            sys.exit(f"No product with id {args.only!r} in {args.catalog}")
    if args.limit > 0:
        catalog = catalog[: args.limit]

    o_voxel, Trellis2ImageTo3DPipeline = import_trellis(
        args.trellis_dir, args.allow_nvdiffrast
    )
    import trimesh  # after sys.path setup; a hard dep of the export path

    print(f"Loading {PRETRAINED_MODEL} (first run downloads ~10GB from Hugging Face)...")
    pipeline = Trellis2ImageTo3DPipeline.from_pretrained(PRETRAINED_MODEL)
    pipeline.cuda()
    if args.low_vram:
        # Attribute consulted by preprocess_image to shuttle the rembg model
        # on and off the GPU around each call.
        pipeline.low_vram = True

    sampler_params: dict = {}
    if args.steps > 0:
        sampler_params["steps"] = args.steps
    if args.guidance > 0:
        sampler_params["guidance_strength"] = args.guidance

    http = requests.Session()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    args.registry.parent.mkdir(parents=True, exist_ok=True)

    print(
        f"Quality: pipeline={args.pipeline_type}, texture={args.texture_size}px, "
        f"decimation_target={args.decimation_target}, remesh={not args.no_remesh}"
        + (f", steps={args.steps}" if args.steps else "")
    )
    print("Scaling: " + ("OFF (normalised meshes)" if args.no_scale else "catalogue dimensions, floor at y=0"))

    generated, skipped, failures = 0, 0, []
    low_res: list[str] = []
    stretched: list[str] = []
    progress = tqdm(catalog, unit="product", desc="TRELLIS.2")
    for record in progress:
        store_id = product_id(record)
        name = str(record.get("product_name") or "?")
        progress.set_postfix_str(f"{store_id} {name[:32]}")

        if not store_id:
            failures.append({"store_id": "", "product_name": name, "error": "record has no id"})
            continue

        out_path = args.output_dir / mesh_filename(record)
        if out_path.is_file() and out_path.stat().st_size > 0 and not args.force:
            skipped += 1
            continue

        image_url = product_image_url(record)
        if not image_url:
            failures.append({"store_id": store_id, "product_name": name, "error": "no image_url"})
            continue

        dimensions = None
        if not args.no_scale:
            dimensions = product_dimensions(record)
            if dimensions is None:
                failures.append(
                    {
                        "store_id": store_id,
                        "product_name": name,
                        "error": (
                            "no usable spatial_attributes to scale to "
                            "(need plausible width_cm/height_cm/length_cm; "
                            "use --no-scale to emit a normalised mesh anyway)"
                        ),
                    }
                )
                continue

        try:
            image = fetch_image(
                image_url_candidates(image_url, not args.no_image_upscale), http
            )
            if min(image.width, image.height) < COND_SIZE:
                low_res.append(f"{store_id} ({image.width}x{image.height}px)")
        except Exception as exc:  # noqa: BLE001
            failures.append(
                {"store_id": store_id, "product_name": name, "error": f"image: {exc}"}
            )
            continue

        try:
            # pipeline.run handles preprocessing itself: our fully-opaque RGBA
            # is treated as background-present, routed through BiRefNet
            # matting, cropped, and recentred.
            with torch.no_grad():
                mesh = pipeline.run(
                    image,
                    seed=args.seed,
                    sparse_structure_sampler_params=sampler_params,
                    shape_slat_sampler_params=sampler_params,
                    tex_slat_sampler_params=sampler_params,
                    pipeline_type=args.pipeline_type,
                    max_num_tokens=args.max_tokens,
                )[0]

            # nvdiffrast's rasteriser (and our shim's face-id float channel)
            # can address at most 2^24 triangles; TRELLIS.2's example applies
            # the same guard.
            mesh.simplify(16_777_216)

            glb = o_voxel.postprocess.to_glb(
                vertices=mesh.vertices,
                faces=mesh.faces,
                attr_volume=mesh.attrs,
                coords=mesh.coords,
                attr_layout=mesh.layout,
                voxel_size=mesh.voxel_size,
                aabb=[[-0.5, -0.5, -0.5], [0.5, 0.5, 0.5]],
                decimation_target=args.decimation_target,
                texture_size=args.texture_size,
                remesh=not args.no_remesh,
                remesh_band=1,
                remesh_project=0,
                verbose=False,
            )
            if glb is None or getattr(glb, "is_empty", False) or len(glb.vertices) == 0:
                raise RuntimeError("TRELLIS.2 reconstructed no surface (empty mesh)")

            if dimensions is not None:
                width_cm, height_cm, depth_cm = dimensions
                report = scale_mesh_to_catalog(glb, width_cm, height_cm, depth_cm)
                if report["distortion"] >= DISTORTION_REPORT_THRESHOLD:
                    stretched.append(
                        f"{store_id} ({report['distortion']:.2f}x, {report['orientation']})"
                    )
                # The turn/stretch invalidates the baked vertex normals
                # (non-uniform scale needs inverse-transpose normals), so hand
                # trimesh a normal-free copy and let the exporter recompute.
                glb = trimesh.Trimesh(
                    vertices=glb.vertices,
                    faces=glb.faces,
                    visual=glb.visual,
                    process=False,
                )

            # Atomic export: temp name keeps .glb so trimesh infers the format.
            # No webp textures — iOS Quick Look does not read them, and these
            # assets exist to be placed in AR.
            tmp_path = out_path.with_name(out_path.stem + ".tmp.glb")
            glb.export(str(tmp_path))
            if not tmp_path.is_file() or tmp_path.stat().st_size == 0:
                raise RuntimeError("exported .glb is missing or empty")
            os.replace(tmp_path, out_path)
            generated += 1
        except Exception as exc:  # noqa: BLE001
            out_path.with_name(out_path.stem + ".tmp.glb").unlink(missing_ok=True)
            failures.append(
                {"store_id": store_id, "product_name": name, "error": f"inference: {exc}"}
            )
        finally:
            torch.cuda.empty_cache()

    registered = rebuild_registry(full_catalog, args.output_dir, args.registry)

    print(
        f"\nDone: {generated} generated, {skipped} already existed, "
        f"{len(failures)} failed, {registered} in registry."
    )
    print(f"Registry: {args.registry}")
    if low_res:
        print(
            f"{len(low_res)} image(s) below the model's {COND_SIZE}px input size "
            f"— reconstruction quality is capped for these:"
        )
        for entry in low_res[:5]:
            print(f"  - {entry}")
        if len(low_res) > 5:
            print(f"  ... and {len(low_res) - 5} more")
    if stretched:
        print(
            f"{len(stretched)} mesh(es) needed uneven correction to reach their "
            f"catalogued size — worth checking those measurements:"
        )
        for entry in stretched[:5]:
            print(f"  - {entry}")
        if len(stretched) > 5:
            print(f"  ... and {len(stretched) - 5} more")
    failures_path = args.registry.parent / "3D_Catalog_failures.json"
    if failures:
        atomic_write_json(failures_path, failures)
        print(f"Failures written to {failures_path}:")
        for failure in failures[:10]:
            print(f"  - {failure['store_id']}: {failure['error']}")
        if len(failures) > 10:
            print(f"  ... and {len(failures) - 10} more")
    else:
        failures_path.unlink(missing_ok=True)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
