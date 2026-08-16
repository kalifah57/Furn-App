#!/usr/bin/env python3
"""Local 3D pipeline: catalog.json -> Stable Fast 3D -> GLB assets + registry.

Turns every product in ``Catalog_Fin/catalog.json`` into a textured 3D mesh
using Stability AI's Stable Fast 3D (SF3D), running entirely on the local
machine. On an Apple Silicon Mac the model runs on the GPU via the ``mps``
backend; ``cpu`` is used only when MPS is genuinely unavailable. CUDA is
deliberately never selected. (For the CUDA/TRELLIS.2 pipeline, see
tools/generate_3d_trellis.py.)

Meshes are emitted true-scale: SF3D reconstructs into a normalised +/-1 unit
cube, so each mesh is rescaled to the catalogue's own `spatial_attributes` in
metres and seated with its floor at y=0. That is the contract
`tools/generate_furniture_glb.py` self-checks and `<model-viewer
ar-scale="fixed">` needs to place an item at real size; a normalised mesh
looks fine in a viewer and appears at the wrong size in AR. Pass `--no-scale`
to emit SF3D's raw normalised output instead.

Outputs
    Assets/3D_Models/<slug>_<id>.glb      one textured mesh per product
    Catalog_Fin/3D_Catalog_new.json       the registry the app consumes:
                                          [{internal_id, store_id, local_3d_path}]
    Catalog_Fin/3D_Catalog_failures.json  written only when something failed,
                                          so a partial run is visible, not silent

Prerequisites (see tools/README_3D.md for the full walkthrough)
    1. The SF3D source tree cloned locally (it is not on PyPI):
           git clone https://github.com/Stability-AI/stable-fast-3d vendor/stable-fast-3d
       and its dependencies installed (tools/requirements-3d.txt).
    2. Access to the gated Hugging Face repo `stabilityai/stable-fast-3d`
       (accept the license on the model page, then `huggingface-cli login`).
    3. A generated Catalog_Fin/catalog.json (python -m furn_catalog ...).

Usage
    PYTORCH_ENABLE_MPS_FALLBACK=1 python tools/generate_3d.py
    python tools/generate_3d.py --limit 5            # smoke-test on 5 products
    python tools/generate_3d.py --force              # regenerate existing meshes
    python tools/generate_3d.py --texture-resolution 2048

The run is resumable: products whose .glb already exists are skipped, and the
registry is rebuilt in full every run. `internal_id`s are deterministic for a
given set of meshes on disk (catalog order among existing files) — but when a
previously-failed product is recovered on a later run, entries after it shift
down by one. Treat `store_id`, not `internal_id`, as the durable key.
"""

from __future__ import annotations

import argparse
import os
import sys
from contextlib import nullcontext
from pathlib import Path

# --------------------------------------------------------------------------
# Environment knobs that must be set BEFORE torch is imported.
#
# PYTORCH_ENABLE_MPS_FALLBACK lets the MPS backend hand individual ops that
# Metal does not implement back to the CPU instead of aborting the run —
# SF3D touches a couple of these. Read once at torch import, hence here.
os.environ.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")

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

DEFAULT_SF3D_DIR = Path(__file__).resolve().parent.parent / "vendor" / "stable-fast-3d"

PRETRAINED_MODEL = "stabilityai/stable-fast-3d"


# --------------------------------------------------------------------------
# Device selection — MPS first, CPU as the only fallback. Never CUDA.

def select_device() -> str:
    if os.environ.get("SF3D_USE_CPU", "0") == "1":
        print("SF3D_USE_CPU=1 is set — using the CPU backend as requested.")
        return "cpu"
    if torch.backends.mps.is_available():
        return "mps"
    if torch.backends.mps.is_built():
        print(
            "WARNING: torch was built with MPS but no Metal device is "
            "available; falling back to CPU (this will be slow)."
        )
    else:
        print(
            "WARNING: this torch build has no MPS support; falling back to "
            "CPU. Install an arm64 torch wheel (see tools/requirements-3d.txt)."
        )
    # SF3D's internals consult their own sf3d.utils.get_device() (e.g. for the
    # autocast guard inside generate_mesh). Setting this keeps that in
    # agreement with the device the model was actually moved to.
    os.environ["SF3D_USE_CPU"] = "1"
    return "cpu"


# --------------------------------------------------------------------------
# SF3D import — the repo is not a PyPI package, so it is vendored as a
# checkout and put on sys.path here.

def import_sf3d(sf3d_dir: Path):
    if not (sf3d_dir / "sf3d" / "system.py").is_file():
        sys.exit(
            f"SF3D source not found at {sf3d_dir}.\n"
            "Clone it first:\n"
            f"    git clone https://github.com/Stability-AI/stable-fast-3d {sf3d_dir}\n"
            "then install its dependencies (see tools/README_3D.md)."
        )
    sys.path.insert(0, str(sf3d_dir))
    try:
        from sf3d.system import SF3D
        from sf3d.utils import remove_background, resize_foreground
    except ImportError as exc:
        sys.exit(
            f"Found the SF3D checkout at {sf3d_dir} but importing it failed:\n"
            f"    {exc}\n"
            "Its dependencies are probably missing — run:\n"
            "    pip install -r tools/requirements-3d.txt\n"
            f"    pip install --no-build-isolation {sf3d_dir}/texture_baker {sf3d_dir}/uv_unwrapper"
        )
    return SF3D, remove_background, resize_foreground


# --------------------------------------------------------------------------
# Main

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("--catalog", type=Path, default=DEFAULT_CATALOG)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUT_DIR)
    parser.add_argument("--registry", type=Path, default=DEFAULT_REGISTRY)
    parser.add_argument(
        "--sf3d-dir",
        type=Path,
        default=Path(os.environ.get("SF3D_DIR", DEFAULT_SF3D_DIR)),
        help="Path to the stable-fast-3d checkout (env: SF3D_DIR).",
    )
    parser.add_argument("--limit", type=int, default=0, help="Process only the first N products.")
    parser.add_argument("--only", default="", help="Process a single product id (e.g. s79482824).")
    parser.add_argument("--force", action="store_true", help="Regenerate meshes that already exist.")
    parser.add_argument(
        "--texture-resolution",
        type=int,
        default=1024,
        help="Baked texture size in px (SF3D default 1024; 2048 is slower/heavier).",
    )
    parser.add_argument(
        "--remesh",
        choices=("none", "triangle", "quad"),
        default="none",
        help="SF3D remeshing mode. 'none' is fastest and fine for AR viewing.",
    )
    parser.add_argument(
        "--foreground-ratio",
        type=float,
        default=0.85,
        help="How much of the frame the product fills after background removal.",
    )
    parser.add_argument(
        "--target-vertex-count",
        type=int,
        default=-1,
        help="Reduce the mesh to roughly N vertices (-1 = no reduction). Needs --remesh.",
    )
    parser.add_argument(
        "--no-scale",
        action="store_true",
        help=(
            "Emit SF3D's raw normalised mesh instead of resizing it to the "
            "catalogue's real dimensions. The result is NOT AR-placeable."
        ),
    )
    parser.add_argument(
        "--no-image-upscale",
        action="store_true",
        help="Download image_url exactly as catalogued, without asking the CDN for a larger size.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    # The registry is always rebuilt from the FULL catalog, so a --limit or
    # --only run can never clobber entries for products it didn't touch.
    full_catalog = load_catalog(args.catalog)
    catalog = full_catalog
    if args.only:
        catalog = [r for r in catalog if product_id(r) == args.only]
        if not catalog:
            sys.exit(f"No product with id {args.only!r} in {args.catalog}")
    if args.limit > 0:
        catalog = catalog[: args.limit]

    SF3D, remove_background, resize_foreground = import_sf3d(args.sf3d_dir)

    device = select_device()
    print(f"Device: {device}")
    print(f"Loading {PRETRAINED_MODEL} (first run downloads the weights from Hugging Face)...")
    try:
        model = SF3D.from_pretrained(
            PRETRAINED_MODEL,
            config_name="config.yaml",
            weight_name="model.safetensors",
        )
    except Exception as exc:  # noqa: BLE001
        message = str(exc)
        if "401" in message or "403" in message or "gated" in message.lower():
            sys.exit(
                "Hugging Face refused access to the gated model "
                f"{PRETRAINED_MODEL}.\n"
                "1. Open https://huggingface.co/stabilityai/stable-fast-3d and "
                "accept the license.\n"
                "2. Run `huggingface-cli login` with a token that has read access.\n"
                f"(original error: {message})"
            )
        raise
    model.to(device)
    model.eval()

    import rembg  # resolvable by now: import_sf3d() already pulled it in via sf3d.utils

    rembg_session = rembg.new_session()
    http = requests.Session()

    args.output_dir.mkdir(parents=True, exist_ok=True)
    args.registry.parent.mkdir(parents=True, exist_ok=True)

    # SF3D squares every input to this before reconstructing, so anything
    # smaller is detail the mesh can never recover.
    cond_size = getattr(getattr(model, "cfg", None), "cond_image_size", 0) or 0
    if cond_size:
        print(f"Model input size: {cond_size}x{cond_size}px")
    print("Scaling: " + ("OFF (normalised meshes)" if args.no_scale else "catalogue dimensions, floor at y=0"))

    generated, skipped, failures = 0, 0, []
    low_res: list[str] = []
    stretched: list[str] = []
    progress = tqdm(catalog, unit="product", desc="SF3D")
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

        # Resolved before the download so a product with unusable dimensions
        # costs nothing — the expensive inference would only be thrown away.
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
            if cond_size and min(image.width, image.height) < cond_size:
                low_res.append(f"{store_id} ({image.width}x{image.height}px)")
        except Exception as exc:  # noqa: BLE001
            failures.append(
                {"store_id": store_id, "product_name": name, "error": f"image: {exc}"}
            )
            continue

        try:
            image = remove_background(image, rembg_session)
            image = resize_foreground(image, args.foreground_ratio)

            # run.py only autocasts on CUDA; on MPS/CPU bf16 autocast is
            # unsupported-or-slower, so mirror that exactly.
            autocast = (
                torch.autocast(device_type=device, dtype=torch.bfloat16)
                if "cuda" in device
                else nullcontext()
            )
            with torch.no_grad(), autocast:
                mesh, _global_dict = model.run_image(
                    [image],
                    bake_resolution=args.texture_resolution,
                    remesh=args.remesh,
                    vertex_count=args.target_vertex_count,
                )

            # SF3D never returns None — a failed reconstruction comes back as
            # an EMPTY trimesh, which would export to a valid-but-useless .glb
            # and silently enter the registry. Catch it here instead.
            if mesh is None or getattr(mesh, "is_empty", False):
                raise RuntimeError("SF3D reconstructed no surface (empty mesh)")

            if dimensions is not None:
                width_cm, height_cm, depth_cm = dimensions
                report = scale_mesh_to_catalog(mesh, width_cm, height_cm, depth_cm)
                if report["distortion"] >= DISTORTION_REPORT_THRESHOLD:
                    stretched.append(
                        f"{store_id} ({report['distortion']:.2f}x, {report['orientation']})"
                    )
            # Export to a temp file and swap in atomically, so a crash can
            # never leave a truncated .glb — and a failed --force regeneration
            # never destroys the previous good mesh. The temp name keeps the
            # .glb extension because trimesh infers the format from it.
            tmp_path = out_path.with_name(out_path.stem + ".tmp.glb")
            mesh.export(str(tmp_path), include_normals=True)
            if not tmp_path.is_file() or tmp_path.stat().st_size == 0:
                raise RuntimeError("exported .glb is missing or empty")
            os.replace(tmp_path, out_path)
            generated += 1
        except Exception as exc:  # noqa: BLE001
            out_path.with_name(out_path.stem + ".tmp.glb").unlink(missing_ok=True)
            failures.append(
                {"store_id": store_id, "product_name": name, "error": f"inference: {exc}"}
            )
            if device == "mps":
                torch.mps.empty_cache()
            continue

    registered = rebuild_registry(full_catalog, args.output_dir, args.registry)

    print(
        f"\nDone: {generated} generated, {skipped} already existed, "
        f"{len(failures)} failed, {registered} in registry."
    )
    print(f"Registry: {args.registry}")
    if low_res:
        print(
            f"{len(low_res)} image(s) smaller than the model's {cond_size}px input "
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
        # A clean run must not leave last run's failure report lying around.
        failures_path.unlink(missing_ok=True)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
