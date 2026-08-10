#!/usr/bin/env python3
"""
Catalog -> AR-ready GLB generator (pure stdlib, no dependencies).

Synthesises one true-scale .glb per catalog product by picking a silhouette for
its category and driving it from the product's real width/depth/height. Reuses
the primitives and GLB writer from generate_furniture_glb.py, so every model is
authored in metres with the floor at y=0 — exactly what
`<model-viewer ar-scale="fixed">` needs to place it at real size.

Why generate rather than ship mock paths: `ar_ready` gates the
"شاهدها في غرفتك" button. Pointing it at a .glb that does not exist means 47
buttons that open a broken viewer. A simple box-and-legs model at *correct
dimensions* is honest — the whole point of the AR step is judging scale.

Every model is verified with self_check(): bbox must equal the catalog's
W x H x D within 1cm, and the floor must sit at y=0.

Usage:  python3 tools/generate_catalog_glb.py
Output: web/models/glb/<product_id>.glb   (+ flips ar_ready in catalog.json)
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generate_furniture_glb import (  # noqa: E402
    box, frustum, merge, build_glb, mat_wood, self_check,
)

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
CATALOG = os.path.join(ROOT, "assets", "catalog", "catalog.json")
OUT_DIR = os.path.join(ROOT, "web", "models", "glb")

# Products with a hand-authored model already on disk — never overwrite.
HAND_AUTHORED = {"table_coffee_walnut_ar"}

# sRGB hex per colour tag, so the AR model roughly matches the listed colour.
PALETTE = {
    "white": "#EDEAE4", "black": "#2B2B2E", "gray": "#8C8C90",
    "grey": "#8C8C90", "beige": "#D9C9AE", "brown": "#6B4A2F",
    "blue": "#3E5C7E", "green": "#4A6B52", "red": "#8E3B36",
    "yellow": "#D9B15A", "silver": "#B8BCC0", "gold": "#C2A14D",
    "walnut": "#5A3E28", "oak": "#B08A5A", "natural": "#C6A87C",
}


def colour_of(p, fallback="#8A7A66"):
    for tag in p.get("color_tags", []):
        if tag.lower() in PALETTE:
            return PALETTE[tag.lower()]
    return fallback


def darker(hex_str, factor=0.65):
    h = hex_str.lstrip("#")
    return "#" + "".join(
        "%02X" % max(0, min(255, int(int(h[i:i + 2], 16) * factor)))
        for i in (0, 2, 4)
    )


# --------------------------------------------------------------------------
# Silhouettes. Each returns (groups, materials) with the bbox pinned to
# exactly W x H x D and the lowest vertex at y=0.
# --------------------------------------------------------------------------

def shape_rug(W, D, H, c):
    return [merge([box(0, H / 2, 0, W, H, D)])], [mat_wood(c, roughness=0.95)]


def shape_bed(W, D, H, c):
    base_h = min(0.28, H * 0.35)
    mat_h = min(0.22, H * 0.28)
    hb_t = 0.06
    body = merge([
        box(0, base_h / 2, 0, W * 0.96, base_h, D * 0.96),          # platform
        box(0, H / 2, -(D / 2 - hb_t / 2), W, H, hb_t),             # headboard
    ])
    mattress = merge([box(0, base_h + mat_h / 2, 0, W, mat_h, D)])
    return [body, mattress], [mat_wood(darker(c)), mat_wood(c, roughness=0.85)]


def shape_sofa(W, D, H, c):
    arm_t = min(0.18, W * 0.12)
    back_t = 0.14
    foot_h = min(0.09, H * 0.12)
    seat_h = min(0.20, H * 0.24)
    seat_y = foot_h + seat_h / 2
    frame = merge([
        box(0, H / 2, -(D / 2 - back_t / 2), W, H, back_t),          # back
        box(W / 2 - arm_t / 2, foot_h + (H - foot_h) * 0.32, 0,
            arm_t, (H - foot_h) * 0.64, D),                          # right arm
        box(-(W / 2 - arm_t / 2), foot_h + (H - foot_h) * 0.32, 0,
            arm_t, (H - foot_h) * 0.64, D),                          # left arm
    ])
    seat = merge([box(0, seat_y, back_t / 2, W - 2 * arm_t, seat_h, D - back_t)])
    feet = merge([
        frustum(sx * (W / 2 - arm_t), 0.0, sz * (D / 2 - 0.10),
                0.026, 0.020, foot_h)
        for sx in (1, -1) for sz in (1, -1)
    ])
    return ([frame, seat, feet],
            [mat_wood(c), mat_wood(c, roughness=0.9), mat_wood(darker(c, 0.5))])


def shape_table(W, D, H, c):
    top_t = min(0.04, H * 0.10)
    leg_h = H - top_t
    inset = min(0.09, min(W, D) * 0.14)
    top = merge([box(0, H - top_t / 2, 0, W, top_t, D)])
    legs = merge([
        frustum(sx * (W / 2 - inset), 0.0, sz * (D / 2 - inset),
                0.024, 0.030, leg_h)
        for sx in (1, -1) for sz in (1, -1)
    ])
    return [top, legs], [mat_wood(c), mat_wood(darker(c), roughness=0.55)]


def shape_storage(W, D, H, c):
    plinth_h = min(0.08, H * 0.08)
    body_h = H - plinth_h
    gap = 0.012
    half = (W - gap) / 2
    carcass = merge([box(0, plinth_h / 2, 0, W * 0.94, plinth_h, D * 0.94)])
    doors = merge([
        box(-(half + gap) / 2, plinth_h + body_h / 2, 0, half, body_h, D),
        box((half + gap) / 2, plinth_h + body_h / 2, 0, half, body_h, D),
    ])
    return [carcass, doors], [mat_wood(darker(c, 0.55)), mat_wood(c)]


def shape_lamp(W, D, H, c, mounted=False):
    # Ceiling fixtures are authored as their own slab; the user anchors them up.
    if mounted or H <= 0.12:
        return ([merge([box(0, H / 2, 0, W, H, D)])],
                [mat_wood("#EDEAE4", roughness=0.35)])
    r = min(W, D) / 2
    shade_h = min(0.26, H * 0.30)
    base_h = min(0.035, H * 0.06)
    pole_h = H - shade_h - base_h
    stand = merge([
        frustum(0, 0.0, 0, r * 0.62, r * 0.58, base_h),
        frustum(0, base_h, 0, 0.014, 0.011, pole_h),
    ])
    # Top radius is exactly r, pinning the x/z extent to W (lamps are square).
    shade = merge([frustum(0, H - shade_h, 0, r * 0.72, r, shade_h)])
    return ([stand, shade],
            [mat_wood(darker(c, 0.5), roughness=0.4), mat_wood(c, roughness=0.8)])


BUILDERS = {
    "rug": shape_rug, "bed": shape_bed, "sofa": shape_sofa,
    "table": shape_table, "storage": shape_storage,
}
CEILING_SUBS = {"ceiling", "pendant", "chandelier"}


def build_one(p):
    W, D, H = p["width_cm"] / 100.0, p["depth_cm"] / 100.0, p["height_cm"] / 100.0
    c = colour_of(p)
    cat = p["category"]
    if cat == "lamp":
        groups, materials = shape_lamp(
            W, D, H, c, mounted=p.get("subcategory") in CEILING_SUBS)
    else:
        groups, materials = BUILDERS.get(cat, shape_storage)(W, D, H, c)
    glb = build_glb(groups, materials,
                    "Furn-App catalog->AR generator (real-scale placeholder)")
    self_check(glb, {"w": round(p["width_cm"]), "d": round(p["depth_cm"]),
                     "h": round(p["height_cm"])})
    return glb


def main():
    with open(CATALOG, encoding="utf-8") as f:
        products = json.load(f)
    os.makedirs(OUT_DIR, exist_ok=True)

    built, skipped, failed = 0, 0, []
    for p in products:
        pid = p["product_id"]
        if pid in HAND_AUTHORED:
            p["ar_ready"] = True
            skipped += 1
            continue
        try:
            glb = build_one(p)
        except AssertionError as e:
            failed.append((pid, str(e)))
            p["ar_ready"] = False
            continue
        with open(os.path.join(OUT_DIR, pid + ".glb"), "wb") as f:
            f.write(glb)
        # iOS Quick Look: Safari converts the GLB itself, so no USDZ is shipped
        # yet. Leave the field as the documented path for when one exists.
        p["ar_ready"] = True
        built += 1

    with open(CATALOG, "w", encoding="utf-8") as f:
        json.dump(products, f, ensure_ascii=False, indent=2)
        f.write("\n")

    print("built %d glb | hand-authored kept %d | failed %d"
          % (built, skipped, len(failed)))
    for pid, err in failed:
        print("  FAIL %-26s %s" % (pid, err))
    print("ar_ready: %d / %d" % (sum(1 for p in products if p["ar_ready"]),
                                 len(products)))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
