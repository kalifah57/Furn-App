"""Command line entry point.

    python -m furn_catalog --limit 50 --out catalog.json

Retailer quotas default to an IKEA-heavy split because IKEA KSA publishes
complete measurements for nearly every article, while the other two are less
consistent. Override with `--retailer` to change the mix.
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
from pathlib import Path

from .adapters import ADAPTERS, build_adapter
from .aesthetics import build_extractor
from .http import HttpClient
from . import manifest as manifest_mod
from .pipeline import DEFAULT_MODEL_TEMPLATE, Pipeline, merge
from .render import BrowserRenderer
from .schema import DEFAULT_PROFILE, PROFILES, dump_catalogue

DEFAULT_SEEDS = Path(__file__).resolve().parent.parent / "seeds" / "ikea_ksa_seeds.json"


def load_seeds(path: Path, retailer: str) -> list[str]:
    """Read candidate product URLs for one retailer from a seed file."""
    if not path.exists():
        return []
    data = json.loads(path.read_text(encoding="utf-8"))
    entries = data.get("seeds", data) if isinstance(data, dict) else data
    urls: list[str] = []
    for entry in entries:
        if isinstance(entry, str):
            urls.append(entry)
        elif isinstance(entry, dict) and entry.get("retailer", retailer) == retailer:
            url = entry.get("url") or entry.get("product_link")
            if url:
                urls.append(url)
    return urls


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="furn_catalog",
        description="Extract a Furn-App furniture catalogue from Saudi retailers.",
    )
    parser.add_argument("--limit", type=int, default=50, help="products to emit (default: 50)")
    parser.add_argument(
        "--retailer",
        action="append",
        metavar="NAME[:COUNT]",
        help=(
            "retailer to scrape, optionally with a quota "
            f"(choices: {', '.join(sorted(ADAPTERS))}). Repeatable. "
            "Default: ikea only — Home Centre and Abyat need a selector-tuning "
            "pass first (see README > Adapter maturity). Any quota a retailer "
            "cannot fill is topped up from the first one listed."
        ),
    )
    parser.add_argument("--out", type=Path, help="write JSON here instead of stdout")
    parser.add_argument(
        "--seeds",
        type=Path,
        default=DEFAULT_SEEDS,
        help=f"seed URL file (default: {DEFAULT_SEEDS})",
    )
    parser.add_argument(
        "--aesthetics",
        choices=("rules", "vision"),
        default="rules",
        help="feature extraction backend. 'vision' sends product images to Claude.",
    )
    parser.add_argument(
        "--render",
        choices=("auto", "always", "browser", "static"),
        default="auto",
        help=(
            "how pages are fetched. 'auto' (default) fetches statically and "
            "retries in Chromium only where measurements come back missing. "
            "'always' opens the measurements panel on every product page — "
            "slower, but the panel is the authoritative source. 'browser' is an "
            "alias for 'always'. 'static' never launches a browser."
        ),
    )
    parser.add_argument(
        "--allow-incomplete",
        action="store_true",
        help=(
            "emit products with no dimensions, flagged with a data_quality block, "
            "instead of dropping them. Off by default: the solver cannot place them. "
            "Requires --schema extended, since the strict shape has no way to say "
            "'this record is incomplete'."
        ),
    )
    parser.add_argument(
        "--schema",
        choices=PROFILES,
        default=DEFAULT_PROFILE,
        help=(
            "output shape. 'strict' (default) emits exactly the contract keys the "
            "PlacementSolver, Aesthetic engine and Riverpod store consume, with "
            "float numerics and no optional fields. 'extended' adds room_category, "
            "depth_cm, seat_depth_cm, texture, pairs_with and data_quality."
        ),
    )
    parser.add_argument(
        "--max-variants",
        type=int,
        default=None,
        metavar="N",
        help=(
            "how many fabric/finish variants of one model to take before "
            "deferring the rest (default: 2). IKEA lists a sofa once per cover, "
            "and four colours of one EKTORP are a single footprint to the "
            "solver. Raise it if you want the colour range; 0 disables the cap."
        ),
    )
    parser.add_argument(
        "--enforce-extents",
        action="store_true",
        help=(
            "drop records whose axes are too small for their category instead of "
            "counting them. Off by default: this repo publishes raw and the "
            "consumer owns that judgement (see README > Published contract)."
        ),
    )
    parser.add_argument(
        "--no-manifest",
        action="store_true",
        help="skip writing catalog.manifest.json beside --out",
    )
    parser.add_argument(
        "--require-price",
        action="store_true",
        help=(
            "drop products with no resolvable price instead of emitting "
            "price_sar: null. Use when the consumer types the field as a "
            "non-nullable number."
        ),
    )
    parser.add_argument(
        "--model-url-template",
        default=DEFAULT_MODEL_TEMPLATE,
        help="template for 3d_model_url; supports {slug}, {sku}, {category}",
    )
    parser.add_argument(
        "--cache-dir",
        type=Path,
        default=Path(".http-cache"),
        help="on-disk HTTP cache (default: .http-cache)",
    )
    parser.add_argument("--no-cache", action="store_true", help="disable the HTTP cache")
    parser.add_argument(
        "--delay", type=float, default=1.0, help="seconds between requests per host (default: 1.0)"
    )
    parser.add_argument(
        "--ignore-robots",
        action="store_true",
        help="skip robots.txt checks (only with the site owner's permission)",
    )
    parser.add_argument("--report", type=Path, help="write the run report here")
    parser.add_argument("-v", "--verbose", action="count", default=0)
    return parser


def parse_quotas(raw: list[str] | None, limit: int) -> list[tuple[str, int]]:
    """Turn `--retailer ikea:30` arguments into (name, quota) pairs."""
    if not raw:
        # IKEA only, by default. The first live run established that Home
        # Centre's robots.txt disallows every category listing we would need,
        # and that Abyat's `/sa/en/c/...` paths no longer exist — between them
        # they contributed nothing but 10 warnings. Both remain available via
        # `--retailer homecentre` for anyone whose access differs, but shipping
        # them in the default split just guarantees an under-delivered run.
        return [("ikea", limit)]

    parsed: list[tuple[str, int]] = []
    explicit_total = 0
    unspecified: list[int] = []
    for item in raw:
        name, _, count = item.partition(":")
        name = name.strip()
        if name not in ADAPTERS:
            raise SystemExit(f"unknown retailer {name!r} (expected one of {sorted(ADAPTERS)})")
        if count:
            parsed.append((name, int(count)))
            explicit_total += int(count)
        else:
            unspecified.append(len(parsed))
            parsed.append((name, 0))

    if unspecified:
        share = max(1, (limit - explicit_total) // len(unspecified))
        for index in unspecified:
            parsed[index] = (parsed[index][0], share)
    return parsed


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)

    # The strict shape has no `data_quality` key, so a dimensionless record
    # could only appear there as a silent `spatial_attributes: null` — exactly
    # the thing a deterministic solver must never be handed unannounced.
    if args.allow_incomplete and args.schema != "extended":
        raise SystemExit(
            "--allow-incomplete needs --schema extended: the strict shape has no "
            "field in which to declare that a record is incomplete."
        )

    logging.basicConfig(
        level=(logging.DEBUG if args.verbose > 1 else logging.INFO if args.verbose else logging.WARNING),
        format="%(levelname)s %(name)s: %(message)s",
        stream=sys.stderr,
    )

    client = HttpClient(
        cache_dir=None if args.no_cache else args.cache_dir,
        delay=args.delay,
        respect_robots=not args.ignore_robots,
    )
    extractor = build_extractor(args.aesthetics)

    render_always = args.render in ("always", "browser")
    renderer = None
    if args.render != "static":
        renderer = BrowserRenderer()
        if not renderer.available:
            if render_always:
                raise SystemExit(
                    f"--render {args.render} needs Playwright: "
                    "pip install playwright && playwright install chromium"
                )
            print(
                "  (Playwright not installed — static fetches only. "
                "Products whose measurements need a browser will be dropped.)",
                file=sys.stderr,
            )
            renderer = None

    def run_retailer(retailer: str, quota: int, exclude: set[str]):
        seeds = load_seeds(args.seeds, retailer)
        print(f"→ {retailer}: target {quota} ({len(seeds)} seeds)", file=sys.stderr)
        pipeline = Pipeline(
            build_adapter(
                retailer, client, seeds, renderer, max_variants_per_model=args.max_variants
            ),
            extractor=extractor,
            model_url_template=args.model_url_template,
            allow_incomplete=args.allow_incomplete,
            require_price=args.require_price,
            render_always=render_always,
            enforce_extents=args.enforce_extents,
        )
        return pipeline.run(limit=quota, exclude_skus=exclude)

    runs = []
    emitted_skus: set[str] = set()
    quotas = parse_quotas(args.retailer, args.limit)
    for retailer, quota in quotas:
        if quota <= 0:
            continue
        result = run_retailer(retailer, quota, emitted_skus)
        runs.append(result)
        emitted_skus.update(p.sku for p in result[0])

    # A retailer that under-delivers its quota shouldn't shorten the catalogue
    # when another source could cover the gap. Top up from the first retailer
    # in the mix, skipping everything already emitted.
    shortfall = args.limit - len(emitted_skus)
    if shortfall > 0 and quotas:
        primary = quotas[0][0]
        print(f"→ {primary}: topping up {shortfall} more", file=sys.stderr)
        result = run_retailer(primary, shortfall, emitted_skus)
        runs.append(result)
        emitted_skus.update(p.sku for p in result[0])

    if renderer is not None:
        renderer.close()

    products, report = merge(runs)
    # merge() sums each pass's target; the run as a whole asked for one number.
    report.requested = args.limit
    payload = dump_catalogue(products, profile=args.schema)

    if args.out:
        args.out.write_text(payload, encoding="utf-8")
        print(f"wrote {len(products)} products to {args.out}", file=sys.stderr)

        # The manifest is derived from the bytes just written, never authored by
        # hand: consumers poll it and pull the catalogue only when `sha256`
        # changes, so a stale hash pins them to an old file silently.
        if not args.no_manifest:
            written = manifest_mod.write(args.out, record_count=len(products))
            problems = manifest_mod.verify(args.out)
            if problems:
                for problem in problems:
                    print(f"MANIFEST ERROR: {problem}", file=sys.stderr)
                return 2
            print(f"wrote {written}", file=sys.stderr)
    else:
        print(payload)

    summary = (
        f"{report.render()}\n"
        f"  http      : {client.stats.requests_made} requests, "
        f"{client.stats.cache_hits} cache hits, {client.stats.retries} retries"
    )
    print(summary, file=sys.stderr)
    if args.report:
        args.report.write_text(summary, encoding="utf-8")

    if len(products) < args.limit:
        print(
            f"\nWARNING: emitted {len(products)} of {args.limit} requested. "
            "Raise --limit oversampling or extend the seed list; see the drop "
            "reasons above for what fell out.",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
