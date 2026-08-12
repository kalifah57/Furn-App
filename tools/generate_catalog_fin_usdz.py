#!/usr/bin/env python3
"""
Catalog_Fin (IKEA KSA extraction) -> internal IDs + true-scale USDZ +
3D_Catalog.json registry (pure stdlib, no dependencies).

Same pipeline as tools/generate_3d_catalog.py, adapted to the Catalog_Fin
schema: records carry a store `id` (retained untouched), nested `urls`
(`3d_model_url` already names the CDN path each asset will live at),
`spatial_attributes` (length=depth, width, height in cm) and
`aesthetic_features` (colour names, material, style).

1. Inject a stable integer `internal_id` (1..N, file order) into every record
   of Catalog_Fin/catalog.json. Existing ids survive reruns; deletions leave
   permanent gaps by design (registry keys are never reused).

2. Generate one .usdz per product into Catalog_Fin/models/usdz/, named after
   the record's `3d_model_url` basename so the files can be uploaded to the
   CDN as-is and the catalog URLs become real without renaming. Geometry is
   the repo's true-scale category silhouettes (plus a chair silhouette this
   dataset needs), authored in metres, floor at y=0, coloured from the
   record's primary_colors. The source images cannot be fetched from this
   sandbox and no photogrammetry runs here: spatial attributes + colours are
   the reference, exactly like the shipped web/models pipeline.

3. Write Catalog_Fin/3D_Catalog.json mapping each internal_id to its
   generated asset (path, format, CDN target, sha256, size, dims).

Every package is verified from raw disk bytes (zip alignment, stored
entries, bbox equal to the record's W x H x D within 1cm, floor at y=0).
A product that fails verification is rolled back completely — no file, no
registry entry, exit 1 — because a wrong-scale model is worse than none:
this pipeline exists to judge scale. Physically impossible source rows
(e.g. a 1.2cm-wide dining set) are therefore surfaced, not papered over.

Usage:  python3 tools/generate_catalog_fin_usdz.py [--check]
        --check  verify without writing (ids, packages byte-fresh, registry)
Output: Catalog_Fin/catalog.json, Catalog_Fin/models/usdz/*.usdz,
        Catalog_Fin/3D_Catalog.json
"""

import hashlib
import json
import os
import sys
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generate_catalog_glb import (  # noqa: E402
    darker, shape_bed, shape_sofa, shape_storage, shape_table,
)
from generate_furniture_glb import box, frustum, mat_wood, merge  # noqa: E402
from generate_3d_catalog import (  # noqa: E402
    self_check_usdz, usda_for, write_usdz,
)

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
FIN_DIR = os.path.join(ROOT, "Catalog_Fin")
CATALOG = os.path.join(FIN_DIR, "catalog.json")
REGISTRY = os.path.join(FIN_DIR, "3D_Catalog.json")
OUT_DIR = os.path.join(FIN_DIR, "models", "usdz")
URL_PREFIX = "models/usdz/"  # registry paths, relative to Catalog_Fin/

# This dataset's colour vocabulary -> the generator palette's tags.
COLOR_MAP = {
    "white": "white", "black": "black", "grey": "gray", "gray": "gray",
    "dark grey": "gray", "ash": "gray", "chrome": "silver",
    "beige": "beige", "dark beige": "beige", "brown": "brown",
    "black-brown": "walnut", "dark brown": "walnut", "walnut brown": "walnut",
    "oak": "oak", "white-stained oak": "oak", "natural pine": "natural",
    "blue": "blue", "turquoise": "blue", "red": "red",
}

# Category -> silhouette. side_table covers bedside cabinets (MALM chests,
# VIKHAMMER) — the repo's own nightstand uses the storage silhouette too.
CATEGORY_SHAPES = {
    "armchair": "sofa", "sofa": "sofa", "bed": "bed", "chair": "chair",
    "dresser": "storage", "wardrobe": "storage", "tv_unit": "storage",
    "bookcase": "storage", "shelving": "storage", "side_table": "storage",
    "dining_table": "table", "coffee_table": "table", "desk": "table",
}


def shape_chair(W, D, H, c):
    """Seat slab + full-width backrest + 4 tapered legs, bbox = W x H x D."""
    seat_t = 0.045
    seat_y = min(0.45, H * 0.58)
    back_t = min(0.05, D * 0.15)
    inset = min(0.05, min(W, D) * 0.12)
    seat = merge([box(0, seat_y - seat_t / 2, 0, W, seat_t, D)])
    back = merge([box(0, (H + seat_y) / 2, -(D / 2 - back_t / 2),
                      W, H - seat_y, back_t)])
    legs = merge([
        frustum(sx * (W / 2 - inset), 0.0, sz * (D / 2 - inset),
                0.020, 0.016, seat_y - seat_t)
        for sx in (1, -1) for sz in (1, -1)
    ])
    return ([seat, back, legs],
            [mat_wood(c, roughness=0.85), mat_wood(c, roughness=0.85),
             mat_wood(darker(c, 0.6))])


SHAPES = {"sofa": shape_sofa, "bed": shape_bed, "storage": shape_storage,
          "table": shape_table, "chair": shape_chair}

PALETTE_HEX = {  # mirrors generate_catalog_glb.PALETTE via COLOR_MAP tags
    "white": "#EDEAE4", "black": "#2B2B2E", "gray": "#8C8C90",
    "beige": "#D9C9AE", "brown": "#6B4A2F", "blue": "#3E5C7E",
    "red": "#8E3B36", "silver": "#B8BCC0", "walnut": "#5A3E28",
    "oak": "#B08A5A", "natural": "#C6A87C",
}


def slug_of(p):
    url = (p.get("urls") or {}).get("3d_model_url", "")
    base = os.path.basename(url)
    if base.endswith(".usdz"):
        return base[:-5]
    return "product_%s" % p["id"]


def colour_of_fin(p):
    for name in (p.get("aesthetic_features") or {}).get("primary_colors", []):
        tag = COLOR_MAP.get(name.strip().lower())
        if tag:
            return PALETTE_HEX[tag]
    return "#8A7A66"


def shim_for(p):
    """Normalise a Catalog_Fin record to what usda_for/self_check expect:
    x = width_cm, z = length_cm (depth), y = height_cm."""
    sp = p["spatial_attributes"]
    return {
        "product_id": slug_of(p),
        "width_cm": sp["width_cm"],
        "depth_cm": sp["length_cm"],
        "height_cm": sp["height_cm"],
    }


def build_fin_groups(p, shim):
    kind = CATEGORY_SHAPES.get(p.get("category"), "storage")
    W = shim["width_cm"] / 100.0
    D = shim["depth_cm"] / 100.0
    H = shim["height_cm"] / 100.0
    return SHAPES[kind](W, D, H, colour_of_fin(p))


def ensure_internal_ids(products):
    seen = {}
    for p in products:
        v = p.get("internal_id")
        if v is None:
            continue
        if not isinstance(v, int) or isinstance(v, bool) or v < 1:
            raise SystemExit("internal_id must be a positive int, got %r on %s"
                             % (v, p.get("id")))
        if v in seen:
            raise SystemExit("duplicate internal_id %d on %s and %s"
                             % (v, seen[v], p.get("id")))
        seen[v] = p.get("id")
    next_id = max(seen, default=0) + 1
    assigned = 0
    for p in products:
        if p.get("internal_id") is None:
            p["internal_id"] = next_id
            next_id += 1
            assigned += 1
    for i, p in enumerate(products):
        products[i] = {"internal_id": p["internal_id"],
                       **{k: v for k, v in p.items() if k != "internal_id"}}
    return assigned


def registry_entry(p, shim, usdz_path):
    with open(usdz_path, "rb") as f:
        blob = f.read()
    return {
        "internal_id": p["internal_id"],
        "id": p["id"],
        "product_name": p.get("product_name", ""),
        "generated_3d_object": URL_PREFIX + shim["product_id"] + ".usdz",
        "format": "usdz",
        "cdn_target_url": (p.get("urls") or {}).get("3d_model_url", ""),
        "dimensions_cm": {
            "length": shim["depth_cm"], "width": shim["width_cm"],
            "height": shim["height_cm"],
        },
        "sha256": hashlib.sha256(blob).hexdigest(),
        "size_bytes": len(blob),
    }


def dump_json(obj, path):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)
        f.write("\n")


def main():
    check_only = "--check" in sys.argv
    with open(CATALOG, encoding="utf-8") as f:
        products = json.load(f)

    problems, warnings = [], []

    if check_only:
        good = []
        for p in products:
            v = p.get("internal_id")
            if isinstance(v, int) and not isinstance(v, bool) and v >= 1:
                good.append(v)
            else:
                problems.append("%s: internal_id missing/invalid (%r)"
                                % (p.get("id"), v))
        if len(set(good)) != len(good):
            problems.append("duplicate internal_ids: %s"
                            % sorted(v for v in set(good) if good.count(v) > 1))
        assigned = 0
    else:
        assigned = ensure_internal_ids(products)
        os.makedirs(OUT_DIR, exist_ok=True)

    entries, built = [], 0
    for p in products:
        shim = shim_for(p)
        pid = shim["product_id"]
        for axis in ("width_cm", "depth_cm", "height_cm"):
            v = shim[axis]
            if not 5 <= v <= 400:
                warnings.append("%s (%s): %s=%gcm is implausible — check the "
                                "source extraction" % (p["id"], pid, axis, v))
        usdz_path = os.path.join(OUT_DIR, pid + ".usdz")
        try:
            if check_only:
                self_check_usdz(usdz_path, shim)
                with zipfile.ZipFile(usdz_path) as zf:
                    packaged = zf.read(zf.infolist()[0])
                if packaged != usda_for(shim, build_fin_groups(p, shim)):
                    raise AssertionError("packaged layer differs from today's "
                                         "catalog — stale, rerun the generator")
            else:
                tmp = usdz_path + ".tmp"
                write_usdz(tmp, pid + ".usda",
                           usda_for(shim, build_fin_groups(p, shim)))
                self_check_usdz(tmp, shim)
                os.replace(tmp, usdz_path)
                built += 1
            if isinstance(p.get("internal_id"), int):
                entries.append(registry_entry(p, shim, usdz_path))
        except (AssertionError, KeyError, OSError, zipfile.BadZipFile) as e:
            problems.append("%s: %s" % (pid, e))
            if not check_only:
                for stale in (usdz_path + ".tmp", usdz_path):
                    if os.path.exists(stale):
                        os.remove(stale)
    entries.sort(key=lambda e: e["internal_id"])

    if check_only:
        try:
            with open(REGISTRY, encoding="utf-8") as f:
                if json.load(f) != entries:
                    problems.append("3D_Catalog.json is stale — rerun the generator")
        except (OSError, ValueError) as e:
            problems.append("3D_Catalog.json unreadable: %s" % e)
    else:
        dump_json(products, CATALOG)
        dump_json(entries, REGISTRY)

    print("products: %d | internal_ids assigned: %d | usdz built: %d | registry: %d"
          % (len(products), assigned, built, len(entries)))
    for msg in warnings:
        print("  WARN %s" % msg)
    for msg in problems:
        print("  FAIL %s" % msg)
    if not problems and not check_only:
        print("wrote %s" % os.path.normpath(CATALOG))
        print("wrote %s" % os.path.normpath(REGISTRY))
        print("wrote %s/*.usdz" % os.path.normpath(OUT_DIR))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
