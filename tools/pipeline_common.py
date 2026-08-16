"""Model-agnostic pieces of the 3D generation pipelines.

Everything here is shared between the SF3D adapter (tools/generate_3d.py,
Apple Silicon) and the TRELLIS.2 adapter (tools/generate_3d_trellis.py,
CUDA cloud): catalogue access, image download, the true-scale conversion,
and the registry contract. The adapters own everything model-specific —
device selection, inference, and export.

Deliberately does NOT import torch: the SF3D adapter must set MPS
environment variables before torch loads, so the first torch import has to
stay in the adapter, after its os.environ calls.
"""

from __future__ import annotations

import json
import os
import re
import sys
import time
from io import BytesIO
from pathlib import Path

import requests
from PIL import Image

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CATALOG = REPO_ROOT / "Catalog_Fin" / "catalog.json"
DEFAULT_OUT_DIR = REPO_ROOT / "Assets" / "3D_Models"
DEFAULT_REGISTRY = REPO_ROOT / "Catalog_Fin" / "3D_Catalog_new.json"

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


def product_dimensions(record: dict) -> tuple[float, float, float] | None:
    """(width, height, depth) in cm, or None when the record can't be trusted.

    Axis naming follows `Catalog_Fin/furn_catalog/units.py`: `width_cm` is
    side-to-side, `height_cm` floor-to-top, and `length_cm` front-to-back —
    the retailer's "depth" under the solver's naming. Mixing the last two up
    silently rotates every item 90 degrees, so the mapping is spelled out
    rather than inferred.
    """
    spatial = record.get("spatial_attributes")
    if not isinstance(spatial, dict):
        return None
    try:
        width = float(spatial["width_cm"])
        height = float(spatial["height_cm"])
        depth = float(spatial["length_cm"])
    except (KeyError, TypeError, ValueError):
        return None
    # Same 1-400cm plausibility gate the catalogue schema applies; a mesh
    # scaled to a mis-parsed number is worse than no mesh.
    if not all(1.0 <= axis <= 400.0 for axis in (width, height, depth)):
        return None
    return width, height, depth


def slugify(text: str, max_len: int = 60) -> str:
    slug = re.sub(r"[^a-z0-9]+", "_", text.lower()).strip("_")
    return slug[:max_len].rstrip("_") or "product"


def mesh_filename(record: dict) -> str:
    # Mirrors the catalog's own asset convention:
    # kivik_3_seat_sofa_s79482824.usdz  ->  kivik_3_seat_sofa_s79482824.glb
    # The id itself is slugged too — it lands in a filename.
    return f"{slugify(str(record.get('product_name') or ''))}_{slugify(product_id(record))}.glb"


def image_url_candidates(url: str, upscale: bool) -> list[str]:
    """URLs to try for one product image, largest first.

    IKEA's CDN serves the same asset at several sizes behind an `f=` query
    parameter, and the catalogue keeps whatever size the search API returned —
    often a thumbnail. Anything below the model's own input resolution is
    detail the reconstruction can never recover. The original URL stays in
    the list as a fallback, so a CDN that rejects the parameter costs nothing
    but one wasted request.
    """
    if not upscale or "ikea.com" not in url or "f=" in url:
        return [url]
    joiner = "&" if "?" in url else "?"
    return [f"{url}{joiner}f=xl", url]


# --------------------------------------------------------------------------
# Image download

class _Unretryable(Exception):
    """A fetch problem that retrying cannot fix."""


def fetch_one(url: str, session: requests.Session) -> Image.Image:
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


def fetch_image(candidates: list[str], session: requests.Session) -> Image.Image:
    """First candidate that downloads; the last failure is what gets reported."""
    last_error: Exception | None = None
    for url in candidates:
        try:
            return fetch_one(url, session)
        except Exception as exc:  # noqa: BLE001 — fall through to the next size
            last_error = exc
    raise RuntimeError(str(last_error))


# --------------------------------------------------------------------------
# True-scale conversion

#: Tolerances copied from `tools/generate_furniture_glb.py:self_check`, so a
#: mesh from these pipelines satisfies the same contract as a synthesised one.
SCALE_TOLERANCE_CM = 1.0
FLOOR_TOLERANCE_M = 0.005

#: Above this ratio between the largest and smallest axis correction, the
#: model's proportions and the catalogue's disagree enough to be worth
#: reporting. The mesh is still emitted — the catalogue dimension is
#: authoritative for AR — but a systematic offender usually means a bad
#: measurement upstream.
DISTORTION_REPORT_THRESHOLD = 1.25


def scale_mesh_to_catalog(
    mesh, width_cm: float, height_cm: float, depth_cm: float
) -> dict:
    """Resize a normalised, Y-up mesh to real dimensions and floor it at y=0.

    Both SF3D and TRELLIS.2 reconstruct into a normalised unit region and
    orient the result Y-up. The app needs metres with the floor at y=0 and
    the footprint centred on the origin, so the mesh is stretched onto the
    catalogue's own box.

    The output always ends up as x=width, y=height, z=depth, because that is
    what the app's viewer and the PlacementSolver both assume. Which of the
    mesh's own horizontal axes currently holds the wide side depends on the
    camera angle of the source photo, so the mesh is turned a quarter turn
    when that lands the long side on the wrong axis. Choosing by which
    assignment needs the least stretching, rather than by sorting extents,
    is what keeps beds right — a 90x200cm bed frame is deeper than it is wide,
    so "the bigger number is the width" is false exactly when it matters.

    The quarter turn is a real rotation about Y, `(x, y, z) -> (z, y, -x)`,
    not a swap of the two axes: swapping is a reflection, and a reflected mesh
    renders inside out.
    """
    vertices = [tuple(float(axis) for axis in vertex) for vertex in mesh.vertices]
    if not vertices:
        raise RuntimeError("mesh has no vertices")

    lo = [min(vertex[i] for vertex in vertices) for i in range(3)]
    hi = [max(vertex[i] for vertex in vertices) for i in range(3)]
    extent = [hi[i] - lo[i] for i in range(3)]
    if min(extent) <= 1e-9:
        raise RuntimeError(f"mesh is flat on one axis (extent {extent})")

    target = [width_cm / 100.0, height_cm / 100.0, depth_cm / 100.0]

    best = None
    for turn, orientation in ((False, "as reconstructed"), (True, "turned 90deg")):
        # After the turn, the mesh's z extent is what fills the x axis.
        horizontal = (extent[2], extent[0]) if turn else (extent[0], extent[2])
        factors = [
            target[0] / horizontal[0],
            target[1] / extent[1],
            target[2] / horizontal[1],
        ]
        distortion = max(factors) / min(factors)
        if best is None or distortion < best[0]:
            best = (distortion, orientation, turn, factors)
    distortion, orientation, turn, factors = best

    # Turn first (so the long side lands on x), then move to the origin,
    # stretch onto the catalogue's box, and centre the footprint while
    # leaving y resting on zero.
    half_x, half_z = target[0] / 2.0, target[2] / 2.0
    placed = []
    for vertex in vertices:
        if turn:
            x, y, z = vertex[2] - lo[2], vertex[1], -(vertex[0] - hi[0])
        else:
            x, y, z = vertex[0] - lo[0], vertex[1], vertex[2] - lo[2]
        placed.append(
            (
                x * factors[0] - half_x,
                (y - lo[1]) * factors[1],
                z * factors[2] - half_z,
            )
        )
    mesh.vertices = placed

    # Verify against the geometry that was actually written, not the maths
    # that was meant to produce it.
    final = [tuple(float(axis) for axis in vertex) for vertex in mesh.vertices]
    final_lo = [min(vertex[i] for vertex in final) for i in range(3)]
    final_hi = [max(vertex[i] for vertex in final) for i in range(3)]
    got_cm = [round((final_hi[i] - final_lo[i]) * 100.0, 2) for i in range(3)]
    want_cm = [round(axis * 100.0, 2) for axis in target]
    for got, want in zip(got_cm, want_cm):
        if abs(got - want) > SCALE_TOLERANCE_CM:
            raise RuntimeError(f"scale self-check failed: {got_cm}cm vs {want_cm}cm")
    if abs(final_lo[1]) > FLOOR_TOLERANCE_M:
        raise RuntimeError(f"floor not at y=0 (y_min={final_lo[1]:.4f}m)")

    return {"orientation": orientation, "distortion": distortion, "size_cm": got_cm}


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
