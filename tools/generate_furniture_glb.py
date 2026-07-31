#!/usr/bin/env python3
"""
Furniture -> AR-ready GLB generator (pure stdlib, no dependencies).

Turns a real furniture piece — described by its real-world dimensions and a set
of box "parts" (top, legs, shelves, panels...) — into a valid glTF-Binary (.glb)
authored **in metres at true real-world scale**, so `<model-viewer ar-scale="fixed">`
places it at its actual size in the room. iOS Safari auto-converts the GLB to
USDZ for Quick Look; Android uses the GLB directly via Scene Viewer.

This is the "apply" half of docs/furniture_to_ar.md: a real product spec in,
a to-scale AR model out. Box geometry keeps it exact and dependency-free; the
same pipeline accepts richer meshes when a supplier/photogrammetry model exists.

Usage:  python3 tools/generate_furniture_glb.py
Output: web/models/<id>.glb   (served at /<base>/models/<id>.glb on GitHub Pages)
"""

import json
import os
import struct

# --------------------------------------------------------------------------
# Colour: glTF baseColorFactor is LINEAR; author colours in sRGB and convert.
# --------------------------------------------------------------------------

def srgb_to_linear(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def rgb(hex_str):
    h = hex_str.lstrip("#")
    return [srgb_to_linear(int(h[i:i + 2], 16)) for i in (0, 2, 4)] + [1.0]


# --------------------------------------------------------------------------
# Geometry: a box -> 24 verts (flat-shaded), 36 indices, outward normals.
# Coordinates are Y-up, metres, origin at the floor centre of the piece.
# --------------------------------------------------------------------------

def box(cx, cy, cz, sx, sy, sz):
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    faces = [
        ((1, 0, 0),  [(hx, -hy, -hz), (hx, -hy, hz), (hx, hy, hz), (hx, hy, -hz)]),
        ((-1, 0, 0), [(-hx, -hy, hz), (-hx, -hy, -hz), (-hx, hy, -hz), (-hx, hy, hz)]),
        ((0, 1, 0),  [(-hx, hy, -hz), (hx, hy, -hz), (hx, hy, hz), (-hx, hy, hz)]),
        ((0, -1, 0), [(-hx, -hy, hz), (hx, -hy, hz), (hx, -hy, -hz), (-hx, -hy, -hz)]),
        ((0, 0, 1),  [(-hx, -hy, hz), (hx, -hy, hz), (hx, hy, hz), (-hx, hy, hz)]),
        ((0, 0, -1), [(hx, -hy, -hz), (-hx, -hy, -hz), (-hx, hy, -hz), (hx, hy, -hz)]),
    ]
    positions, normals, indices = [], [], []
    for normal, corners in faces:
        base = len(positions) // 3
        for (x, y, z) in corners:
            positions += [x + cx, y + cy, z + cz]
            normals += list(normal)
        indices += [base, base + 1, base + 2, base, base + 2, base + 3]
    return positions, normals, indices


def merge(parts):
    """Merge several boxes into one (positions, normals, indices) group."""
    positions, normals, indices = [], [], []
    for p in parts:
        pos, nrm, idx = box(*p)
        offset = len(positions) // 3
        positions += pos
        normals += nrm
        indices += [i + offset for i in idx]
    return positions, normals, indices


# --------------------------------------------------------------------------
# GLB assembly: one mesh, one primitive per material group.
# --------------------------------------------------------------------------

def pad(data, alignment=4, fill=b"\x00"):
    over = len(data) % alignment
    return data + fill * (alignment - over) if over else data


def build_glb(groups, materials, generator_note):
    bin_blob = b""
    buffer_views, accessors = [], []

    def add_view(raw, target):
        nonlocal bin_blob
        bin_blob = pad(bin_blob)
        offset = len(bin_blob)
        bin_blob += raw
        buffer_views.append({
            "buffer": 0, "byteOffset": offset,
            "byteLength": len(raw), "target": target,
        })
        return len(buffer_views) - 1

    primitives = []
    for gi, (positions, normals, indices) in enumerate(groups):
        pos_raw = struct.pack("<%df" % len(positions), *positions)
        nrm_raw = struct.pack("<%df" % len(normals), *normals)
        idx_raw = struct.pack("<%dH" % len(indices), *indices)

        pos_view = add_view(pos_raw, 34962)   # ARRAY_BUFFER
        nrm_view = add_view(nrm_raw, 34962)
        idx_view = add_view(idx_raw, 34963)   # ELEMENT_ARRAY_BUFFER

        xs, ys, zs = positions[0::3], positions[1::3], positions[2::3]
        pos_acc = len(accessors)
        accessors.append({
            "bufferView": pos_view, "componentType": 5126, "count": len(positions) // 3,
            "type": "VEC3", "min": [min(xs), min(ys), min(zs)],
            "max": [max(xs), max(ys), max(zs)],
        })
        nrm_acc = len(accessors)
        accessors.append({
            "bufferView": nrm_view, "componentType": 5126,
            "count": len(normals) // 3, "type": "VEC3",
        })
        idx_acc = len(accessors)
        accessors.append({
            "bufferView": idx_view, "componentType": 5123,  # UNSIGNED_SHORT
            "count": len(indices), "type": "SCALAR",
        })
        primitives.append({
            "attributes": {"POSITION": pos_acc, "NORMAL": nrm_acc},
            "indices": idx_acc, "material": gi,
        })

    gltf = {
        "asset": {"version": "2.0", "generator": generator_note},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0, "name": "furniture"}],
        "meshes": [{"primitives": primitives}],
        "materials": materials,
        "buffers": [{"byteLength": len(bin_blob)}],
        "bufferViews": buffer_views,
        "accessors": accessors,
    }

    json_blob = pad(json.dumps(gltf, separators=(",", ":")).encode("utf-8"),
                    fill=b" ")
    bin_blob = pad(bin_blob)

    total = 12 + 8 + len(json_blob) + 8 + len(bin_blob)
    out = struct.pack("<III", 0x46546C67, 2, total)
    out += struct.pack("<II", len(json_blob), 0x4E4F534A) + json_blob
    out += struct.pack("<II", len(bin_blob), 0x004E4942) + bin_blob
    return out


def wood(hex_str, roughness=0.7):
    return {"pbrMetallicRoughness": {
        "baseColorFactor": rgb(hex_str), "metallicFactor": 0.0,
        "roughnessFactor": roughness}, "doubleSided": True}


# --------------------------------------------------------------------------
# The real piece: a walnut coffee table — W 110 x D 60 x H 45 cm (metres below).
# --------------------------------------------------------------------------

def coffee_table():
    W, D, H = 1.10, 0.60, 0.45
    top_t, leg = 0.04, 0.06
    leg_h = H - top_t                      # legs stop under the top slab
    lx = W / 2 - leg / 2 - 0.02
    lz = D / 2 - leg / 2 - 0.02

    wood_parts = [
        (0, H - top_t / 2, 0, W, top_t, D),        # top slab
        (0, 0.14, 0, W - 0.14, 0.03, D - 0.12),    # lower shelf
    ]
    leg_parts = [
        (sx * lx, leg_h / 2, sz * lz, leg, leg_h, leg)
        for sx in (1, -1) for sz in (1, -1)
    ]

    groups = [merge(wood_parts), merge(leg_parts)]
    materials = [wood("#6B4A2F"), wood("#3E2A1A", roughness=0.6)]
    return groups, materials, dict(id="coffee_table_walnut", w=110, d=60, h=45)


# --------------------------------------------------------------------------

def self_check(glb):
    magic, version, length = struct.unpack("<III", glb[:12])
    assert magic == 0x46546C67 and version == 2 and length == len(glb), "bad header"
    jlen, jtype = struct.unpack("<II", glb[12:20])
    assert jtype == 0x4E4F534A, "bad json chunk"
    gltf = json.loads(glb[20:20 + jlen])
    verts = sum(a["count"] for a in gltf["accessors"] if a["type"] == "VEC3") // 2
    return gltf, verts


def main():
    groups, materials, meta = coffee_table()
    glb = build_glb(groups, materials,
                    "Furn-App furniture->AR generator (real-scale box geometry)")
    gltf, verts = self_check(glb)

    out_dir = os.path.join(os.path.dirname(__file__), "..", "web", "models")
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, meta["id"] + ".glb")
    with open(path, "wb") as f:
        f.write(glb)

    print("OK  %s" % os.path.normpath(path))
    print("    size: %d bytes | vertices: %d | primitives: %d | materials: %d"
          % (len(glb), verts, len(gltf["meshes"][0]["primitives"]), len(gltf["materials"])))
    print("    real scale: %d x %d x %d cm (W x D x H), Y-up, floor at y=0"
          % (meta["w"], meta["d"], meta["h"]))


if __name__ == "__main__":
    main()
