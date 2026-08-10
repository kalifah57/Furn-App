#!/usr/bin/env python3
"""
Backfill AR fields onto assets/catalog/catalog.json (pure stdlib, idempotent).

Adds `model_glb_url`, `model_usdz_url` and `ar_ready` to every product, and
audits every dimension triple against per-category real-world ranges so the
Spatial Decision Engine is never fed a physically impossible product.

The schema written here is the one `CatalogProduct.fromJson` actually reads
(`product_id`, flat `width_cm`/`depth_cm`/`height_cm`, split `*_tags`). A
nested `dims{}` / `id` / `tags` shape would parse to empty strings and zero
dimensions with no error raised.

GLB and USDZ are separate fields on purpose: Android/web Scene Viewer consumes
the .glb, iOS Quick Look needs a .usdz. One URL cannot serve both.

Paths are web-relative (`models/glb/<id>.glb`) because the AR view is a
standalone page (web/ar.html) that resolves them against <base href>.

Usage:  python3 tools/backfill_catalog_ar.py [--check]
        --check  audit only, write nothing (exit 1 on any dimension violation
                 or when a write run would change any ar field — e.g. usdz
                 URLs set in the catalog but the files absent from disk)
"""

import json
import os
import sys

ROOT = os.path.join(os.path.dirname(__file__), "..")
CATALOG = os.path.join(ROOT, "assets", "catalog", "catalog.json")

# Products whose GLB already exists on disk keep their real path untouched.
REAL_MODELS = {
    "table_coffee_walnut_ar": "models/coffee_table_walnut.glb",
}

# Plausible real-world ranges per category, in cm: (min, max) for W, D, H.
# Sourced from standard furniture sizing; a product outside these is a data bug
# that would silently corrupt every room-fit decision downstream.
#
# Subcategory overrides come first: several legitimate pieces sit outside their
# category's usual envelope — an L-shaped sectional has a ~160cm return leg, a
# Saudi floor majlis is ~40cm high by design, a ceiling LED panel is ~8cm thin,
# a console table is ~30cm deep. These are correct products, not bad rows.
RANGES = {
    "bed":     {"w": (90, 200),  "d": (185, 220), "h": (35, 140)},
    "sofa":    {"w": (60, 330),  "d": (60, 115),  "h": (55, 115)},
    "rug":     {"w": (60, 400),  "d": (90, 500),  "h": (0.4, 6)},
    "table":   {"w": (35, 260),  "d": (35, 125),  "h": (30, 85)},
    "lamp":    {"w": (12, 70),   "d": (12, 70),   "h": (20, 200)},
    "storage": {"w": (35, 320),  "d": (25, 75),   "h": (40, 245)},
    "other":   {"w": (5, 400),   "d": (5, 400),   "h": (1, 260)},
}

SUB_RANGES = {
    "sectional":     {"w": (180, 340), "d": (90, 200),  "h": (55, 115)},
    "floor_seating": {"w": (120, 320), "d": (60, 120),  "h": (25, 60)},
    "console_table": {"w": (60, 200),  "d": (22, 50),   "h": (65, 95)},
    "ceiling":       {"w": (12, 120),  "d": (12, 120),  "h": (4, 60)},
    "pendant":       {"w": (12, 90),   "d": (12, 90),   "h": (10, 120)},
    "chandelier":    {"w": (30, 140),  "d": (30, 140),  "h": (20, 150)},
}


def audit(p):
    """Return a list of human-readable range violations for one product."""
    r = SUB_RANGES.get(p.get("subcategory")) or \
        RANGES.get(p.get("category"), RANGES["other"])
    out = []
    for key, field in (("w", "width_cm"), ("d", "depth_cm"), ("h", "height_cm")):
        lo, hi = r[key]
        v = p.get(field, 0)
        if not isinstance(v, (int, float)) or v <= 0:
            out.append("%s missing/zero (%r)" % (field, v))
        elif not (lo <= v <= hi):
            out.append("%s=%g outside [%g, %g] for %s"
                       % (field, v, lo, hi, p["category"]))
    return out


def main():
    check_only = "--check" in sys.argv
    with open(CATALOG, encoding="utf-8") as f:
        products = json.load(f)

    violations, changed = [], 0
    for p in products:
        pid = p["product_id"]
        bad = audit(p)
        if bad:
            violations.append((pid, bad))

        glb = REAL_MODELS.get(pid, "models/glb/%s.glb" % pid)
        # ar.html sets `ios-src` whenever this is non-empty, and a path to a
        # .usdz that does not exist breaks iOS Quick Look. So the field points
        # at models/usdz/<id>.usdz only when that file really exists on disk
        # (generate_3d_catalog.py emits them); otherwise it stays blank and
        # Safari converts the GLB itself.
        usdz_rel = "models/usdz/%s.usdz" % pid
        usdz = usdz_rel if os.path.exists(
            os.path.join(ROOT, "web", "models", "usdz", pid + ".usdz")) else ""
        before = (p.get("model_glb_url"), p.get("model_usdz_url"), p.get("ar_ready"))
        # ar_ready gates the "شاهدها في غرفتك" button. It stays False until the
        # generator has actually emitted the .glb, so the shipped app never
        # offers AR that 404s. generate_catalog_glb.py flips it to True.
        after = (glb, usdz, bool(p.get("ar_ready", False)))
        if before != after:
            p["model_glb_url"], p["model_usdz_url"], p["ar_ready"] = after
            changed += 1

    print("products: %d | ar fields %s: %d"
          % (len(products), "would change" if check_only else "updated", changed))
    if violations:
        print("\nDIMENSION VIOLATIONS (%d):" % len(violations))
        for pid, bad in violations:
            print("  %-28s %s" % (pid, "; ".join(bad)))
    else:
        print("dimension audit: all %d products within category ranges" % len(products))

    if check_only:
        # Pending ar-field drift is a violation too: silently blanking 48
        # usdz URLs because the binaries are missing must not audit green.
        return 1 if (violations or changed) else 0

    with open(CATALOG, "w", encoding="utf-8") as f:
        json.dump(products, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print("wrote %s" % os.path.normpath(CATALOG))
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main())
