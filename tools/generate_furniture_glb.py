#!/usr/bin/env python3
"""
Furniture -> AR-ready GLB generator (pure stdlib, no dependencies).

Turns a real furniture piece — described by its real-world dimensions and a set
of solid "parts" (top slab, apron rails, tapered round legs) — into a valid
glTF-Binary (.glb) authored **in metres at true real-world scale**, so
`<model-viewer ar-scale="fixed">` places it at its actual size in the room.
iOS Safari auto-converts the GLB to USDZ for Quick Look; Android uses the GLB
directly via Scene Viewer.

It also emits an orthographic **spec drawing** (front / side / top, dimensioned)
so the shape and the three dimensions can be compared against the real product
before viewing in AR — the "compare until it matches" step.

Usage:  python3 tools/generate_furniture_glb.py
Output: web/models/<id>.glb  and  web/models/<id>_spec.svg
"""

import json
import math
import os
import struct

# --------------------------------------------------------------------------
# Colour: glTF baseColorFactor is LINEAR; author in sRGB and convert.
# --------------------------------------------------------------------------

def srgb_to_linear(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def rgb(hex_str):
    h = hex_str.lstrip("#")
    return [srgb_to_linear(int(h[i:i + 2], 16)) for i in (0, 2, 4)] + [1.0]


def mat_wood(hex_str, roughness=0.7):
    return {"pbrMetallicRoughness": {
        "baseColorFactor": rgb(hex_str), "metallicFactor": 0.0,
        "roughnessFactor": roughness}, "doubleSided": True}


# --------------------------------------------------------------------------
# Primitives -> (positions, normals, indices) triples. Y-up, metres,
# origin at the floor centre of the piece (bottom of the legs at y=0).
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


def frustum(cx, cy_bottom, cz, r_bot, r_top, height, sides=20):
    """A tapered round leg (cone frustum): smooth radial sides + flat caps."""
    positions, normals, indices = [], [], []
    ang = [2 * math.pi * k / sides for k in range(sides)]
    slope = r_bot - r_top

    def push(p, n):
        positions.extend(p)
        normals.extend(n)
        return len(positions) // 3 - 1

    # smooth-shaded sides
    bot, top = [], []
    for a in ang:
        ca, sa = math.cos(a), math.sin(a)
        nx, ny, nz = ca * height, slope, sa * height
        nl = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
        n = (nx / nl, ny / nl, nz / nl)
        bot.append(push((cx + r_bot * ca, cy_bottom, cz + r_bot * sa), n))
        top.append(push((cx + r_top * ca, cy_bottom + height, cz + r_top * sa), n))
    for k in range(sides):
        k2 = (k + 1) % sides
        indices += [bot[k], bot[k2], top[k2], bot[k], top[k2], top[k]]

    # flat caps
    for cy, r, ny, up in ((cy_bottom, r_bot, -1, False),
                          (cy_bottom + height, r_top, 1, True)):
        center = push((cx, cy, cz), (0, ny, 0))
        ring = [push((cx + r * math.cos(a), cy, cz + r * math.sin(a)), (0, ny, 0))
                for a in ang]
        for k in range(sides):
            k2 = (k + 1) % sides
            tri = [center, ring[k], ring[k2]] if up else [center, ring[k2], ring[k]]
            indices += tri
    return positions, normals, indices


def merge(triples):
    P, N, I = [], [], []
    for (p, n, i) in triples:
        off = len(P) // 3
        P += p
        N += n
        I += [x + off for x in i]
    return P, N, I


# --------------------------------------------------------------------------
# GLB assembly: one mesh, one primitive per material group.
# --------------------------------------------------------------------------

def pad(data, alignment=4, fill=b"\x00"):
    over = len(data) % alignment
    return data + fill * (alignment - over) if over else data


def build_glb(groups, materials, note):
    bin_blob = b""
    buffer_views, accessors, primitives = [], [], []

    def add_view(raw, target):
        nonlocal bin_blob
        bin_blob = pad(bin_blob)
        off = len(bin_blob)
        bin_blob += raw
        buffer_views.append({"buffer": 0, "byteOffset": off,
                             "byteLength": len(raw), "target": target})
        return len(buffer_views) - 1

    for gi, (positions, normals, indices) in enumerate(groups):
        pv = add_view(struct.pack("<%df" % len(positions), *positions), 34962)
        nv = add_view(struct.pack("<%df" % len(normals), *normals), 34962)
        iv = add_view(struct.pack("<%dH" % len(indices), *indices), 34963)
        xs, ys, zs = positions[0::3], positions[1::3], positions[2::3]
        pa = len(accessors)
        accessors.append({"bufferView": pv, "componentType": 5126,
                          "count": len(positions) // 3, "type": "VEC3",
                          "min": [min(xs), min(ys), min(zs)],
                          "max": [max(xs), max(ys), max(zs)]})
        na = len(accessors)
        accessors.append({"bufferView": nv, "componentType": 5126,
                          "count": len(normals) // 3, "type": "VEC3"})
        ia = len(accessors)
        accessors.append({"bufferView": iv, "componentType": 5123,
                          "count": len(indices), "type": "SCALAR"})
        primitives.append({"attributes": {"POSITION": pa, "NORMAL": na},
                           "indices": ia, "material": gi})

    gltf = {
        "asset": {"version": "2.0", "generator": note},
        "scene": 0, "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0, "name": "furniture"}],
        "meshes": [{"primitives": primitives}], "materials": materials,
        "buffers": [{"byteLength": len(bin_blob)}],
        "bufferViews": buffer_views, "accessors": accessors,
    }
    json_blob = pad(json.dumps(gltf, separators=(",", ":")).encode(), fill=b" ")
    bin_blob = pad(bin_blob)
    total = 12 + 8 + len(json_blob) + 8 + len(bin_blob)
    out = struct.pack("<III", 0x46546C67, 2, total)
    out += struct.pack("<II", len(json_blob), 0x4E4F534A) + json_blob
    out += struct.pack("<II", len(bin_blob), 0x004E4942) + bin_blob
    return out


# --------------------------------------------------------------------------
# The real piece: a walnut coffee table, W 110 x D 60 x H 45 cm.
# Scandinavian silhouette: slab top + apron/skirt + 4 tapered round legs.
# --------------------------------------------------------------------------

def coffee_table():
    W, D, H = 1.10, 0.60, 0.45
    top_t = 0.035
    ap_h, ap_t = 0.06, 0.02
    ap_cy = H - top_t - ap_h / 2 - 0.004
    leg_h = H - top_t
    lx, lz = W / 2 - 0.085, D / 2 - 0.085
    ap_x, ap_z = W / 2 - 0.065, D / 2 - 0.065

    boxes = [
        (0, H - top_t / 2, 0, W, top_t, D),                 # top slab
        (0, ap_cy, ap_z, W - 0.20, ap_h, ap_t),             # apron: front
        (0, ap_cy, -ap_z, W - 0.20, ap_h, ap_t),            # apron: back
        (ap_x, ap_cy, 0, ap_t, ap_h, D - 0.20),             # apron: right
        (-ap_x, ap_cy, 0, ap_t, ap_h, D - 0.20),            # apron: left
    ]
    legs = [(sx * lx, sz * lz, 0.022, 0.028, leg_h)
            for sx in (1, -1) for sz in (1, -1)]

    wood = merge([box(*b) for b in boxes])
    legmesh = merge([frustum(x, 0.0, z, rb, rt, h) for (x, z, rb, rt, h) in legs])
    groups = [wood, legmesh]
    materials = [mat_wood("#6B4A2F"), mat_wood("#43301E", roughness=0.55)]
    meta = dict(id="coffee_table_walnut", w=110, d=60, h=45)
    return groups, materials, meta, {"boxes": boxes, "legs": legs, "dims": (W, D, H)}


# --------------------------------------------------------------------------
# Orthographic spec drawing (front / side / top) with dimensions.
# --------------------------------------------------------------------------

def write_spec_svg(parts, meta, path):
    W, D, H = parts["dims"]
    S = 210.0          # px per metre
    pad_px, gap = 46, 40
    wood, dark, line, ink = "#8A6A47", "#5A4230", "#3A2C1E", "#2A2119"

    def rect(x, y, w, h, fill):
        return ('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" '
                'fill="%s" stroke="%s" stroke-width="1"/>'
                % (x, y, w, h, fill, line))

    views = []

    def elevation(ox, oy, horiz, title):
        """horiz='x' -> front (X,Y); horiz='z' -> side (Z,Y)."""
        span = W if horiz == "x" else D
        s = []
        # boxes
        for (cx, cy, cz, sx, sy, sz) in parts["boxes"]:
            c = cx if horiz == "x" else cz
            sw = sx if horiz == "x" else sz
            x = ox + (c - sw / 2 + span / 2) * S
            y = oy + (H - (cy + sy / 2)) * S
            s.append(rect(x, y, sw * S, sy * S, wood))
        # legs as tapered trapezoids
        for (lx, lz, rb, rt, h) in parts["legs"]:
            c = lx if horiz == "x" else lz
            xb, xt = (c - rb + span / 2) * S, (c - rt + span / 2) * S
            s.append('<polygon points="%.1f,%.1f %.1f,%.1f %.1f,%.1f %.1f,%.1f" '
                     'fill="%s" stroke="%s" stroke-width="1"/>' % (
                         ox + xb, oy + H * S, ox + xb + 2 * rb * S, oy + H * S,
                         ox + xt + 2 * rt * S, oy + (H - h) * S, ox + xt,
                         oy + (H - h) * S, dark, line))
        s.append('<text x="%.1f" y="%.1f" text-anchor="middle" '
                 'font-size="13" fill="%s">%s</text>'
                 % (ox + span * S / 2, oy - 12, ink, title))
        return "".join(s), span * S, H * S

    def plan(ox, oy, title):
        s = []
        for (cx, cy, cz, sx, sy, sz) in parts["boxes"][:1]:  # top outline
            s.append(rect(ox, oy, sx * S, sz * S, wood))
        for (lx, lz, rb, rt, h) in parts["legs"]:
            s.append('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="%s" '
                     'stroke="%s" stroke-width="1"/>' % (
                         ox + (lx + W / 2) * S, oy + (lz + D / 2) * S,
                         rt * S, dark, line))
        s.append('<text x="%.1f" y="%.1f" text-anchor="middle" '
                 'font-size="13" fill="%s">%s</text>'
                 % (ox + W * S / 2, oy - 12, ink, title))
        return "".join(s), W * S, D * S

    x0 = pad_px
    front, fw, fh = elevation(x0, pad_px, "x", "أمامي  Front — W %d cm" % meta["w"])
    x1 = x0 + fw + gap
    side, sw, sh = elevation(x1, pad_px, "z", "جانبي  Side — D %d cm" % meta["d"])
    top, tw, th = plan(x0, pad_px + fh + gap + 24, "علوي  Top — %dx%d cm"
                       % (meta["w"], meta["d"]))

    # height dimension tick on the front view
    hx = x0 - 16
    dim = ('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" '
           'stroke-width="1"/><text x="%.1f" y="%.1f" text-anchor="middle" '
           'font-size="12" fill="%s" transform="rotate(-90 %.1f %.1f)">'
           'H %d cm</text>' % (hx, pad_px, hx, pad_px + fh, ink,
                               hx - 8, pad_px + fh / 2, ink, hx - 8,
                               pad_px + fh / 2, meta["h"]))

    total_w = x1 + sw + pad_px
    total_h = pad_px + fh + gap + 24 + th + pad_px
    svg = ('<svg xmlns="http://www.w3.org/2000/svg" width="%.0f" height="%.0f" '
           'viewBox="0 0 %.0f %.0f" font-family="system-ui,sans-serif">'
           '<rect width="100%%" height="100%%" fill="#F5EFE6"/>'
           '<text x="%.1f" y="24" font-size="15" font-weight="700" fill="%s">'
           'طاولة قهوة خشبية — %d×%d×%d سم (بمقاسها الحقيقي)</text>'
           '%s%s%s%s</svg>' % (total_w, total_h, total_w, total_h, pad_px, ink,
                               meta["w"], meta["d"], meta["h"],
                               front, side, top, dim))
    with open(path, "w", encoding="utf-8") as f:
        f.write(svg)


# --------------------------------------------------------------------------

def self_check(glb, meta):
    magic, ver, length = struct.unpack("<III", glb[:12])
    assert magic == 0x46546C67 and ver == 2 and length == len(glb), "bad header"
    jlen, jtype = struct.unpack("<II", glb[12:20])
    assert jtype == 0x4E4F534A, "bad json chunk"
    gltf = json.loads(glb[20:20 + jlen])
    mins = [a["min"] for a in gltf["accessors"] if "min" in a]
    maxs = [a["max"] for a in gltf["accessors"] if "max" in a]
    lo = [min(c) for c in zip(*mins)]
    hi = [max(c) for c in zip(*maxs)]
    dims = [round((hi[i] - lo[i]) * 100) for i in range(3)]
    target = [meta["w"], meta["h"], meta["d"]]  # x=W, y=H, z=D
    for got, want in zip(dims, target):
        assert abs(got - want) <= 1, "scale mismatch: %s vs %s" % (dims, target)
    assert abs(lo[1]) <= 0.005, "floor not at y=0"
    verts = sum(a["count"] for a in gltf["accessors"] if a["type"] == "VEC3") // 2
    return gltf, dims, verts, lo, hi


def main():
    groups, materials, meta, parts = coffee_table()
    glb = build_glb(groups, materials,
                    "Furn-App furniture->AR generator (real-scale, tapered legs)")
    gltf, dims, verts, lo, hi = self_check(glb, meta)

    out_dir = os.path.join(os.path.dirname(__file__), "..", "web", "models")
    os.makedirs(out_dir, exist_ok=True)
    glb_path = os.path.join(out_dir, meta["id"] + ".glb")
    svg_path = os.path.join(out_dir, meta["id"] + "_spec.svg")
    with open(glb_path, "wb") as f:
        f.write(glb)
    write_spec_svg(parts, meta, svg_path)

    print("OK  %s" % os.path.normpath(glb_path))
    print("    size: %d bytes | vertices: %d | primitives: %d | materials: %d"
          % (len(glb), verts, len(gltf["meshes"][0]["primitives"]), len(materials)))
    print("    measured bbox: %d x %d x %d cm (W x H x D)  [target 110 x 45 x 60]"
          % tuple(dims))
    print("    floor at y=%.3f, top at y=%.3f m" % (lo[1], hi[1]))
    print("OK  %s (front/side/top, dimensioned)" % os.path.normpath(svg_path))


if __name__ == "__main__":
    main()
