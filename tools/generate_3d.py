#!/usr/bin/env python3
"""Local 3D pipeline: catalog.json -> Stable Fast 3D -> GLB assets + registry.

Turns every product in ``Catalog_Fin/catalog.json`` into a textured 3D mesh
using Stability AI's Stable Fast 3D (SF3D), running entirely on the local
machine. On an Apple Silicon Mac the model runs on the GPU via the ``mps``
backend; ``cpu`` is used only when MPS is genuinely unavailable. CUDA is
deliberately never selected.

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
import json
import os
import re
import sys
import time
from contextlib import nullcontext
from io import BytesIO
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
from PIL import Image  # noqa: E402
from tqdm import tqdm  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CATALOG = REPO_ROOT / "Catalog_Fin" / "catalog.json"
DEFAULT_OUT_DIR = REPO_ROOT / "Assets" / "3D_Models"
DEFAULT_REGISTRY = REPO_ROOT / "Catalog_Fin" / "3D_Catalog_new.json"
DEFAULT_SF3D_DIR = REPO_ROOT / "vendor" / "stable-fast-3d"

PRETRAINED_MODEL = "stabilityai/stable-fast-3d"

# IKEA's CDN serves images to browsers; the default python-requests UA gets
# 403s often enough that a browser UA is the difference between a run and a
# failure report.
HTTP_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
    ),
    "Accept": "image/avif,image/webp,image/png,image/jpeg,*/*;q=0.8",
}
HTTP_TIMEOUT = 30
HTTP_RETRIES = 3


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
# Catalog access

def load_catalog(path: Path) -> list[dict]:
    if not path.is_file():
        sys.exit(
            f"Catalog not found: {path}\n"
            "Generate it first:\n"
            "    cd Catalog_Fin && python -m furn_catalog --limit 50 --out catalog.json"
        )
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    if isinstance(data, dict):  # tolerate a wrapped {"products": [...]} shape
        for value in data.values():
            if isinstance(value, list):
                data = value
                break
    if not isinstance(data, list) or not data:
        sys.exit(f"Catalog at {path} is empty or not a JSON array of products.")
    return data


def product_id(record: dict) -> str:
    return str(record.get("id") or record.get("store_id") or "").strip()


def product_image_url(record: dict) -> str:
    # The published contract nests it under "urls"; accept a flat layout too.
    urls = record.get("urls")
    if isinstance(urls, dict) and urls.get("image_url"):
        return str(urls["image_url"])
    return str(record.get("image_url") or "")


def slugify(text: str, max_len: int = 60) -> str:
    slug = re.sub(r"[^a-z0-9]+", "_", text.lower()).strip("_")
    return slug[:max_len].rstrip("_") or "product"


def mesh_filename(record: dict) -> str:
    # Mirrors the catalog's own asset convention:
    # kivik_3_seat_sofa_s79482824.usdz  ->  kivik_3_seat_sofa_s79482824.glb
    # The id itself is slugged too — it lands in a filename.
    return f"{slugify(str(record.get('product_name') or ''))}_{slugify(product_id(record))}.glb"


# --------------------------------------------------------------------------
# Image download

def fetch_image(url: str, session: requests.Session) -> Image.Image:
    last_error: Exception | None = None
    for attempt in range(1, HTTP_RETRIES + 1):
        try:
            response = session.get(url, headers=HTTP_HEADERS, timeout=HTTP_TIMEOUT)
            response.raise_for_status()
            image = Image.open(BytesIO(response.content))
            image.load()
            if image.width < 64 or image.height < 64:
                # Not retryable — the CDN will serve the same pixels again.
                raise _Unretryable(
                    f"image is {image.width}x{image.height}px — too small to reconstruct"
                )
            return image.convert("RGBA")
        except _Unretryable as exc:
            raise RuntimeError(f"download failed: {exc}") from exc
        except requests.HTTPError as exc:
            last_error = exc
            status = getattr(getattr(exc, "response", None), "status_code", 0)
            if 400 <= status < 500 and status != 429:
                break  # a dead link now is a dead link in four seconds too
            if attempt < HTTP_RETRIES:
                time.sleep(2**attempt)  # 2s, 4s
        except Exception as exc:  # noqa: BLE001 — timeouts, resets, broken images
            last_error = exc
            if attempt < HTTP_RETRIES:
                time.sleep(2**attempt)
    raise RuntimeError(f"download failed: {last_error}")


class _Unretryable(Exception):
    """A fetch problem that retrying cannot fix."""


# --------------------------------------------------------------------------
# Registry

def atomic_write_json(path: Path, payload) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, path)


def rebuild_registry(catalog: list[dict], out_dir: Path, registry_path: Path) -> int:
    """Write the registry from what is actually on disk.

    Rebuilt in full every time (rather than appended per-product) so that
    `internal_id` is a function of catalog order alone: re-running after a
    partial failure, or with --force, can never renumber existing entries
    differently than a clean run would.
    """
    entries = []
    for record in catalog:
        store_id = product_id(record)
        if not store_id:
            continue
        mesh_path = out_dir / mesh_filename(record)
        if mesh_path.is_file() and mesh_path.stat().st_size > 0:
            try:  # repo-root-relative for the default layout ...
                local_path = mesh_path.relative_to(REPO_ROOT).as_posix()
            except ValueError:  # ... absolute when --output-dir points elsewhere
                local_path = mesh_path.as_posix()
            entries.append(
                {
                    "internal_id": len(entries) + 1,
                    "store_id": store_id,
                    "local_3d_path": local_path,
                }
            )
    atomic_write_json(registry_path, entries)
    return len(entries)


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

    generated, skipped, failures = 0, 0, []
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

        try:
            image = fetch_image(image_url, http)
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
                    vertex_count=-1,
                )

            # SF3D never returns None — a failed reconstruction comes back as
            # an EMPTY trimesh, which would export to a valid-but-useless .glb
            # and silently enter the registry. Catch it here instead.
            if mesh is None or getattr(mesh, "is_empty", False):
                raise RuntimeError("SF3D reconstructed no surface (empty mesh)")
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
