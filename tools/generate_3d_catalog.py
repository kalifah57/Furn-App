#!/usr/bin/env python3
"""
Catalog -> internal IDs + true-scale USDZ + 3D_Catalog.json registry
(pure stdlib, no dependencies).

Three steps, one idempotent pipeline:

1. Inject a stable integer `internal_id` (1..N, file order) into every product
   in assets/catalog/catalog.json. The store `product_id` is never touched —
   `internal_id` is the app's own primary key, `product_id` stays the join key
   back to the supplier. Existing internal_ids are preserved on rerun; only
   products without one get the next free id, so ids never reshuffle. Deleting
   a product leaves a permanent gap by design — a registry key must never be
   reused for a different product.

2. Generate one .usdz per product into web/models/usdz/<product_id>.usdz.
   The geometry is the exact silhouette generate_catalog_glb.py ships as .glb
   (same builders, same palette), authored in metres with the floor at y=0, so
   iOS Quick Look places it at true size — and the GLB and USDZ for a product
   are visually the same object. `image_url` is empty for the whole catalog,
   so the spatial attributes (width/depth/height, category silhouette, colour
   tags) are the reference; these are honest real-scale placeholders, not
   photogrammetry. The catalog's `model_usdz_url` is filled in because the
   files now really exist (see the warning in backfill_catalog_ar.py).

3. Write assets/catalog/3D_Catalog.json: the explicit registry mapping each
   `internal_id` to its generated 3D asset (path, format, sha256, size, dims).

USDZ packaging follows the spec (openusd.org/release/spec_usdz.html): a zip
with no compression, every file's data 64-byte aligned (via extra-field
padding), first file is the default .usda layer. Zip timestamps are pinned so
reruns are byte-identical and git-friendly.

Every package is verified by reading it back from disk: alignment + stored
compression checked from the raw local headers, and the packaged usda's
points re-parsed so the bbox provably equals the catalog's W x H x D within
1cm with the floor at y=0.

Usage:  python3 tools/generate_3d_catalog.py [--check]
        --check  verify without writing: ids present/positive/unique, every
                 package byte-equal to what today's catalog would author
                 (generation is deterministic), registry in sync
                 (exit 1 on any violation)
Output: assets/catalog/catalog.json     (internal_id + model_usdz_url)
        web/models/usdz/<product_id>.usdz
        assets/catalog/3D_Catalog.json
"""

import hashlib
import json
import os
import re
import struct
import sys
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generate_catalog_glb import (  # noqa: E402
    BUILDERS, CEILING_SUBS, colour_of, shape_lamp, shape_storage,
)
from generate_furniture_glb import coffee_table  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
CATALOG = os.path.join(ROOT, "assets", "catalog", "catalog.json")
REGISTRY = os.path.join(ROOT, "assets", "catalog", "3D_Catalog.json")
OUT_DIR = os.path.join(ROOT, "web", "models", "usdz")
# Web-relative, like model_glb_url: ar.html resolves it against <base href>.
URL_PREFIX = "models/usdz/"

GENERATOR_NOTE = "Furn-App catalog->USDZ generator (real-scale placeholder)"


# --------------------------------------------------------------------------
# Step 1 — internal ids: stable, sequential, never reshuffled.
# --------------------------------------------------------------------------

def ensure_internal_ids(products):
    """Assign internal_id to products lacking one; keep existing ids as-is."""
    seen = {}
    for p in products:
        v = p.get("internal_id")
        if v is None:
            continue
        if not isinstance(v, int) or isinstance(v, bool) or v < 1:
            raise SystemExit("internal_id must be a positive int, got %r on %s"
                             % (v, p.get("product_id")))
        if v in seen:
            raise SystemExit("duplicate internal_id %d on %s and %s"
                             % (v, seen[v], p.get("product_id")))
        seen[v] = p.get("product_id")

    next_id = max(seen, default=0) + 1
    assigned = 0
    for p in products:
        if p.get("internal_id") is None:
            p["internal_id"] = next_id
            next_id += 1
            assigned += 1
    # internal_id leads each record: it is the app's primary key.
    for i, p in enumerate(products):
        products[i] = {"internal_id": p["internal_id"],
                       **{k: v for k, v in p.items() if k != "internal_id"}}
    return assigned


# --------------------------------------------------------------------------
# Step 2a — USD authoring. Colours arrive as glTF material dicts from the
# GLB builders; baseColorFactor is already linear, which is exactly what
# UsdPreviewSurface expects.
# --------------------------------------------------------------------------

def _ident(name):
    s = re.sub(r"[^A-Za-z0-9_]", "_", name)
    return s if s and not s[0].isdigit() else "_" + s


def _f(v):
    return "%.6g" % (v + 0.0)


def _vec3s(flat):
    return ", ".join("(%s, %s, %s)" % (_f(flat[i]), _f(flat[i + 1]), _f(flat[i + 2]))
                     for i in range(0, len(flat), 3))


# Products whose GLB is hand-authored must get the SAME detailed geometry in
# the usdz: ar.html prefers `ios-src` whenever a usdz URL exists, so pairing
# the detailed .glb with a generic silhouette would downgrade iOS only.
HAND_AUTHORED_GROUPS = {
    "table_coffee_walnut_ar": lambda p: coffee_table()[:2],
}


def build_groups(p):
    """Same geometry the shipped GLB uses, in metres, floor at y=0."""
    special = HAND_AUTHORED_GROUPS.get(p["product_id"])
    if special:
        return special(p)
    W = p["width_cm"] / 100.0
    D = p["depth_cm"] / 100.0
    H = p["height_cm"] / 100.0
    c = colour_of(p)
    if p["category"] == "lamp":
        return shape_lamp(W, D, H, c, mounted=p.get("subcategory") in CEILING_SUBS)
    return BUILDERS.get(p["category"], shape_storage)(W, D, H, c)


def usda_for(p):
    groups, materials = build_groups(p)
    root = _ident(p["product_id"])
    out = [
        "#usda 1.0",
        "(",
        '    defaultPrim = "%s"' % root,
        '    doc = "%s"' % GENERATOR_NOTE,
        "    metersPerUnit = 1",
        '    upAxis = "Y"',
        ")",
        "",
        'def Xform "%s" (' % root,
        '    kind = "component"',
        ")",
        "{",
        '    def Scope "Materials"',
        "    {",
    ]
    for gi, m in enumerate(materials):
        pbr = m["pbrMetallicRoughness"]
        r, g, b = pbr["baseColorFactor"][:3]
        rough = pbr.get("roughnessFactor", 0.7)
        out += [
            '        def Material "Mat_%d"' % gi,
            "        {",
            "            token outputs:surface.connect = "
            "</%s/Materials/Mat_%d/Shader.outputs:surface>" % (root, gi),
            "",
            '            def Shader "Shader"',
            "            {",
            '                uniform token info:id = "UsdPreviewSurface"',
            "                color3f inputs:diffuseColor = (%s, %s, %s)"
            % (_f(r), _f(g), _f(b)),
            "                float inputs:metallic = 0",
            "                float inputs:roughness = %s" % _f(rough),
            "                token outputs:surface",
            "            }",
            "        }",
        ]
    out.append("    }")

    for gi, (positions, normals, indices) in enumerate(groups):
        xs, ys, zs = positions[0::3], positions[1::3], positions[2::3]
        pbr = materials[gi]["pbrMetallicRoughness"]
        r, g, b = pbr["baseColorFactor"][:3]
        out += [
            "",
            '    def Mesh "Part_%d" (' % gi,
            '        prepend apiSchemas = ["MaterialBindingAPI"]',
            "    )",
            "    {",
            "        uniform bool doubleSided = 1",
            "        float3[] extent = [(%s, %s, %s), (%s, %s, %s)]"
            % (_f(min(xs)), _f(min(ys)), _f(min(zs)),
               _f(max(xs)), _f(max(ys)), _f(max(zs))),
            "        int[] faceVertexCounts = [%s]"
            % ", ".join(["3"] * (len(indices) // 3)),
            "        int[] faceVertexIndices = [%s]"
            % ", ".join(str(i) for i in indices),
            "        rel material:binding = </%s/Materials/Mat_%d>" % (root, gi),
            "        normal3f[] normals = [%s] (" % _vec3s(normals),
            '            interpolation = "vertex"',
            "        )",
            "        point3f[] points = [%s]" % _vec3s(positions),
            "        color3f[] primvars:displayColor = [(%s, %s, %s)]"
            % (_f(r), _f(g), _f(b)),
            '        uniform token subdivisionScheme = "none"',
            "    }",
        ]
    out += ["}", ""]
    return "\n".join(out).encode("utf-8")


# --------------------------------------------------------------------------
# Step 2b — USDZ packaging: uncompressed zip, file data 64-byte aligned.
# --------------------------------------------------------------------------

def write_usdz(path, layer_name, layer_bytes):
    with zipfile.ZipFile(path, "w", zipfile.ZIP_STORED, allowZip64=False) as zf:
        offset = zf.fp.tell()
        zi = zipfile.ZipInfo(layer_name, date_time=(1980, 1, 1, 0, 0, 0))
        zi.compress_type = zipfile.ZIP_STORED
        zi.create_system = 3
        zi.external_attr = 0o644 << 16
        header = 30 + len(layer_name.encode("utf-8"))
        pad = (64 - (offset + header) % 64) % 64
        if 0 < pad < 4:      # an extra field needs >= 4 bytes (id + size)
            pad += 64
        if pad:
            # Same mechanism Pixar's usdzip uses: a throwaway extra field.
            zi.extra = struct.pack("<HH", 0x1986, pad - 4) + b"\x00" * (pad - 4)
        zf.writestr(zi, layer_bytes)


def self_check_usdz(path, p):
    """Verify the written package from raw disk bytes, not from intent."""
    with open(path, "rb") as f:
        raw = f.read()
    with zipfile.ZipFile(path) as zf:
        infos = zf.infolist()
        assert infos, "%s: empty package" % path
        assert infos[0].filename.endswith(".usda"), \
            "%s: first file must be the usd layer" % path
        for zi in infos:
            assert zi.compress_type == zipfile.ZIP_STORED, \
                "%s: %s is compressed" % (path, zi.filename)
            sig, = struct.unpack_from("<I", raw, zi.header_offset)
            assert sig == 0x04034B50, "%s: bad local header" % path
            nlen, elen = struct.unpack_from("<HH", raw, zi.header_offset + 26)
            data_off = zi.header_offset + 30 + nlen + elen
            assert data_off % 64 == 0, \
                "%s: %s data at %d not 64-byte aligned" % (path, zi.filename, data_off)
        usda = zf.read(infos[0]).decode("utf-8")

    pts = []
    for block in re.findall(r"point3f\[\] points = \[(.*?)\]", usda):
        pts += [tuple(float(v) for v in m)
                for m in re.findall(r"\(([^,)]+), ([^,)]+), ([^)]+)\)", block)]
    assert pts, "%s: no points in packaged layer" % path
    lo = [min(c) for c in zip(*pts)]
    hi = [max(c) for c in zip(*pts)]
    dims = [round((hi[i] - lo[i]) * 100) for i in range(3)]
    target = [round(p["width_cm"]), round(p["height_cm"]), round(p["depth_cm"])]
    for got, want in zip(dims, target):
        assert abs(got - want) <= 1, \
            "%s: bbox %s cm != catalog %s cm (W,H,D)" % (path, dims, target)
    assert abs(lo[1]) <= 0.005, "%s: floor not at y=0 (%.4f)" % (path, lo[1])


# --------------------------------------------------------------------------
# Step 3 — the registry: internal_id -> generated 3D asset.
# --------------------------------------------------------------------------

def registry_entry(p, usdz_path):
    with open(usdz_path, "rb") as f:
        blob = f.read()
    return {
        "internal_id": p["internal_id"],
        "product_id": p["product_id"],
        "generated_3d_object": URL_PREFIX + p["product_id"] + ".usdz",
        "format": "usdz",
        "model_glb_url": p.get("model_glb_url", ""),
        "dimensions_cm": {
            "width": p["width_cm"], "depth": p["depth_cm"], "height": p["height_cm"],
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

    problems = []

    if check_only:
        # Assert exactly the invariants ensure_internal_ids maintains: present,
        # positive non-bool int, unique. NOT density — deleting a product
        # leaves a permanent gap by design (ids are stable registry keys).
        good = []
        for p in products:
            v = p.get("internal_id")
            if isinstance(v, int) and not isinstance(v, bool) and v >= 1:
                good.append(v)
            else:
                problems.append("%s: internal_id missing/invalid (%r)"
                                % (p.get("product_id"), v))
        if len(set(good)) != len(good):
            dupes = sorted(v for v in set(good) if good.count(v) > 1)
            problems.append("duplicate internal_ids: %s" % dupes)
        assigned = 0
    else:
        assigned = ensure_internal_ids(products)
        os.makedirs(OUT_DIR, exist_ok=True)

    entries, built = [], 0
    for p in products:
        pid = p["product_id"]
        usdz_path = os.path.join(OUT_DIR, pid + ".usdz")
        try:
            if check_only:
                self_check_usdz(usdz_path, p)
                # Deterministic authoring makes byte-equality the strongest
                # staleness check: a bbox-preserving catalog edit (colour,
                # silhouette) must fail here, not slip through.
                with zipfile.ZipFile(usdz_path) as zf:
                    packaged = zf.read(zf.infolist()[0])
                if packaged != usda_for(p):
                    raise AssertionError(
                        "packaged layer differs from today's catalog "
                        "— stale, rerun the generator")
            else:
                # Verify before install: the live path never holds an asset
                # that failed its check, and the URL is only written for a
                # verified file.
                tmp = usdz_path + ".tmp"
                write_usdz(tmp, pid + ".usda", usda_for(p))
                self_check_usdz(tmp, p)
                os.replace(tmp, usdz_path)
                p["model_usdz_url"] = URL_PREFIX + pid + ".usdz"
                built += 1
            if isinstance(p.get("internal_id"), int):
                entries.append(registry_entry(p, usdz_path))
        except (AssertionError, KeyError, OSError, zipfile.BadZipFile) as e:
            problems.append("%s: %s" % (pid, e))
            if not check_only:
                # Roll back fully: a stale file left behind would resurrect
                # the URL through backfill's existence gate, and ar.html
                # sends iOS to `ios-src` whenever the URL is non-empty.
                for stale in (usdz_path + ".tmp", usdz_path):
                    if os.path.exists(stale):
                        os.remove(stale)
                p["model_usdz_url"] = ""
    entries.sort(key=lambda e: e["internal_id"])

    if check_only:
        try:
            with open(REGISTRY, encoding="utf-8") as f:
                if json.load(f) != entries:
                    problems.append("3D_Catalog.json is stale — rerun the generator")
        except (OSError, ValueError) as e:
            problems.append("3D_Catalog.json unreadable: %s" % e)
        for p in products:
            want = URL_PREFIX + p["product_id"] + ".usdz"
            if p.get("model_usdz_url") != want:
                problems.append("%s: model_usdz_url != %s" % (p["product_id"], want))
    else:
        dump_json(products, CATALOG)
        dump_json(entries, REGISTRY)

    print("products: %d | internal_ids assigned: %d | usdz built: %d | registry: %d"
          % (len(products), assigned, built, len(entries)))
    for msg in problems:
        print("  FAIL %s" % msg)
    if not problems and not check_only:
        print("wrote %s" % os.path.normpath(CATALOG))
        print("wrote %s" % os.path.normpath(REGISTRY))
        print("wrote %s/*.usdz (verified: aligned, stored, true-scale, floor y=0)"
              % os.path.normpath(OUT_DIR))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
