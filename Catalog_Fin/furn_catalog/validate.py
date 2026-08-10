"""Audit a finished catalogue.

    python -m furn_catalog.validate catalog.json

The pipeline validates every record before emitting it, so a clean run should
always pass this. That is exactly why it is worth running separately: it checks
the *file* rather than the process that wrote it, so it also catches a truncated
write, a hand-edit, a merge of two runs, or a schema drift between the version
that produced the file and the version about to consume it.

Prints a per-field coverage summary and exits non-zero if anything fails, so it
can gate a deploy.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path
from typing import Any

from .locale import is_ksa
from .schema import CATEGORIES, MIN_EXTENT_CM, ROOMS, implausible_extents

#: The strict contract: exactly these keys, no more, no less.
STRICT_KEYS = {
    "id",
    "product_name",
    "store",
    "category",
    "price_sar",
    "urls",
    "spatial_attributes",
    "aesthetic_features",
}
EXTENDED_EXTRA = {"room_category", "data_quality"}
REQUIRED_AXES = ("length_cm", "width_cm", "height_cm")
#: Always present, even when empty — that is the whole point of the contract.
AESTHETIC_KEYS = ("primary_colors", "material", "style", "vibe")


# Arabic, Persian, Arabic Presentation Forms — the same range schema.py rejects.
_ARABIC = [("؀", "ۿ"), ("ݐ", "ݿ"), ("ﭐ", "﷿"), ("ﹰ", "﻿")]


def _has_arabic(text: str) -> bool:
    return any(any(lo <= ch <= hi for lo, hi in _ARABIC) for ch in text)


def audit(
    records: list[dict[str, Any]],
    *,
    allow_incomplete: bool = False,
    profile: str = "strict",
) -> list[str]:
    """Every problem found, as human-readable lines. Empty means clean."""
    problems: list[str] = []
    links: Counter[str] = Counter()
    ids: Counter[str] = Counter()

    for index, record in enumerate(records):
        if not isinstance(record, dict):
            problems.append(f"[{index}] not an object")
            continue

        name = str(record.get("product_name") or f"<record {index}>")

        def fail(message: str) -> None:
            problems.append(f"{name}: {message}")

        missing = STRICT_KEYS - set(record)
        if missing:
            fail(f"missing keys {sorted(missing)}")
        # A stray key is a contract breach too: the Dart side deserialises into
        # a fixed model, and a field nobody declared is a field nobody reads.
        unexpected = set(record) - STRICT_KEYS - (EXTENDED_EXTRA if profile == "extended" else set())
        if unexpected:
            fail(f"unexpected keys for --schema {profile}: {sorted(unexpected)}")

        identifier = str(record.get("id") or "")
        if not identifier:
            fail("id is empty — no SKU/article number resolved")
        ids[identifier] += 1

        if record.get("category") not in CATEGORIES:
            fail(f"unknown category {record.get('category')!r}")
        if profile == "extended" and record.get("room_category") not in ROOMS | {"unassigned"}:
            fail(f"unknown room_category {record.get('room_category')!r}")

        urls = record.get("urls") or {}
        link = str(urls.get("product_link") or "")
        if not is_ksa(link):
            fail(f"product_link is not a Saudi storefront URL: {link!r}")
        links[link] += 1

        image = str(urls.get("image_url") or "")
        if not image.startswith("https://"):
            fail(f"image_url is not an https CDN link: {image!r}")
        elif any(tok in image.lower() for tok in ("placeholder", "no-image", "default.jpg")):
            fail(f"image_url looks like a placeholder: {image!r}")

        if not str(urls.get("3d_model_url") or "").startswith("https://"):
            fail("3d_model_url is not https")

        flagged = "missing_dimensions" in (record.get("data_quality") or {}).get("issues", [])
        spatial = record.get("spatial_attributes")
        if spatial is None:
            if not flagged:
                fail("no spatial_attributes and no data_quality flag explaining why")
            elif not allow_incomplete:
                fail("shipped without dimensions (re-run without --allow-incomplete)")
        else:
            for axis in REQUIRED_AXES:
                value = spatial.get(axis)
                if not isinstance(value, (int, float)) or isinstance(value, bool):
                    fail(f"{axis} is not a number: {value!r}")
                elif not isinstance(value, float):
                    # `95` decodes to int in Dart and `as double` then throws.
                    fail(f"{axis}={value} is an int, not a float — breaks `as double`")
                elif not 1 <= value <= 400:
                    fail(f"{axis}={value} is outside 1-400cm")
            for message in implausible_extents(str(record.get("category") or ""), spatial):
                fail(message)

            if profile == "extended":
                if spatial.get("depth_cm") != spatial.get("length_cm"):
                    fail("depth_cm and length_cm disagree — they are the same axis")
                seat = spatial.get("seat_depth_cm")
                if seat is not None and not 1 <= seat <= 200:
                    fail(f"seat_depth_cm={seat} is implausible")
                # A seat cannot be as deep as the thing containing it. This is
                # the shape a component-for-axis substitution takes even when
                # the numbers individually look fine.
                if (
                    isinstance(seat, (int, float))
                    and isinstance(spatial.get("length_cm"), (int, float))
                    and seat >= spatial["length_cm"]
                ):
                    fail(
                        f"seat_depth_cm={seat} >= length_cm={spatial['length_cm']} — "
                        "the depth axis is probably a component measurement"
                    )

        price = record.get("price_sar")
        if price is not None:
            if not isinstance(price, (int, float)) or isinstance(price, bool) or price <= 0:
                fail(f"price_sar is not a positive number: {price!r}")
            elif not isinstance(price, float):
                fail(f"price_sar={price} is an int, not a float — breaks `as double`")

        # Keys must exist even when the value could not be deduced; only their
        # emptiness is tolerated.
        aesthetics = record.get("aesthetic_features")
        if not isinstance(aesthetics, dict):
            fail("aesthetic_features is missing or not an object")
        else:
            for key in AESTHETIC_KEYS:
                if key not in aesthetics:
                    fail(f"aesthetic_features.{key} key is absent (must ship even if empty)")

        if _has_arabic(json.dumps(record, ensure_ascii=False)):
            fail("Arabic script survived into an English-only record")

    for link, count in links.items():
        if count > 1:
            problems.append(f"duplicate product_link x{count}: {link}")
    for identifier, count in ids.items():
        if identifier and count > 1:
            problems.append(f"duplicate id x{count}: {identifier}")

    return problems


def summarise(records: list[dict[str, Any]]) -> str:
    total = len(records) or 1
    spatial = [r.get("spatial_attributes") or {} for r in records]

    def pct(count: int) -> str:
        return f"{count:>3}/{len(records):<3} ({count * 100 // total:>3}%)"

    lines = [
        f"records            : {len(records)}",
        f"with dimensions    : {pct(sum(1 for s in spatial if s))}",
        f"with price_sar     : {pct(sum(1 for r in records if r.get('price_sar') is not None))}",
        f"with colours       : {pct(sum(1 for r in records if (r.get('aesthetic_features') or {}).get('primary_colors')))}",
        f"with material      : {pct(sum(1 for r in records if (r.get('aesthetic_features') or {}).get('material')))}",
        f"stores             : {dict(Counter(r.get('store') for r in records))}",
        f"categories         : {len(set(r.get('category') for r in records))} distinct",
    ]
    if any("seat_depth_cm" in s for s in spatial):
        lines.append(f"with seat depth    : {pct(sum(1 for s in spatial if 'seat_depth_cm' in s))}")
    if any(r.get("room_category") for r in records):
        lines.append(f"rooms              : {dict(Counter(r.get('room_category') for r in records))}")
    flagged = sum(1 for r in records if r.get("data_quality"))
    if flagged:
        lines.append(f"flagged incomplete : {flagged}")
    return "\n".join("  " + line for line in lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="furn_catalog.validate")
    parser.add_argument("path", type=Path, help="catalogue JSON to audit")
    parser.add_argument(
        "--allow-incomplete",
        action="store_true",
        help="accept records flagged with data_quality.missing_dimensions",
    )
    parser.add_argument(
        "--expect", type=int, default=0, help="fail if fewer than this many records"
    )
    parser.add_argument(
        "--schema",
        choices=("strict", "extended"),
        default="strict",
        help="which output shape this file is expected to be in (default: strict)",
    )
    args = parser.parse_args(argv)

    try:
        records = json.loads(args.path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"could not read {args.path}: {exc}", file=sys.stderr)
        return 2

    if not isinstance(records, list):
        print(f"{args.path} is not a JSON array", file=sys.stderr)
        return 2

    print(summarise(records))
    problems = audit(
        records, allow_incomplete=args.allow_incomplete, profile=args.schema
    )

    if problems:
        print(f"\n{len(problems)} problem(s):", file=sys.stderr)
        for problem in problems[:40]:
            print(f"  - {problem}", file=sys.stderr)
        if len(problems) > 40:
            print(f"  ... and {len(problems) - 40} more", file=sys.stderr)
        return 1

    if args.expect and len(records) < args.expect:
        print(f"\nexpected at least {args.expect} records, got {len(records)}", file=sys.stderr)
        return 1

    print("\nOK — every record is shippable.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
