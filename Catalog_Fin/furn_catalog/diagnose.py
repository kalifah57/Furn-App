"""Report which extraction layer answers for a given IKEA product page.

    python -m furn_catalog.diagnose
    python -m furn_catalog.diagnose https://www.ikea.com/sa/en/p/...-s49440597/

The first live run of this pipeline dropped 54 products for `no_dimensions`
with no way to tell, from the outside, *which* of the layered sources had
failed or whether the page had simply stopped carrying measurements at all.
This prints that: per URL, what each source returned, so a future regression is
localised in one command instead of a round trip.

Runs off the same on-disk cache as a real run, so re-diagnosing costs the
retailer nothing.
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
from pathlib import Path

from bs4 import BeautifulSoup

from .adapters.ikea import (
    IkeaAdapter,
    _from_labelled_text,
    _from_measure_json,
    _from_raw_triple,
    _from_triple,
    _labelled_measurements,
)
from .http import FetchError, HttpClient
from .ikea_api import IkeaSearchApi
from .units import dimensions_from_labelled


def diagnose(client: HttpClient, url: str, api: IkeaSearchApi) -> None:
    print(f"\n{url}")
    print("-" * min(len(url), 100))

    article = ""
    match = IkeaAdapter.to_ksa_url(url)
    if match:
        article = match.rstrip("/").rsplit("-", 1)[-1].lower()

    try:
        html, final_url = client.get_with_url(url)
    except FetchError as exc:
        print(f"  page            : UNREACHABLE ({exc})")
        html, final_url = "", url
    else:
        print(f"  page            : {len(html):,} bytes, landed on {final_url}")

    soup = BeautifulSoup(html, "html.parser") if html else BeautifulSoup("", "html.parser")
    product = IkeaAdapter.product_json_ld(soup) or {}
    name = str(product.get("name") or IkeaAdapter.meta(soup, "og:title") or "")
    description = str(
        product.get("description") or IkeaAdapter.meta(soup, "og:description") or ""
    )
    print(f"  json-ld Product : {'yes' if product else 'NO'}  name={name[:60]!r}")

    # Query by the product's own name, not the bare article number: the search
    # backend is a relevance search, not a lookup-by-id, and this mirrors what
    # the pipeline's own SEARCH_QUERIES actually send. A number as free text is
    # not a query IKEA's own search box would ever be asked either.
    query = name.split(" - ")[0].split(",")[0].strip() if name else article
    api_product = api.index([query or article]).get(article) if article else None
    if api_product is None:
        verdict = "no match"
    elif api_product.measure_text:
        verdict = api_product.measure_text
    else:
        # Distinguish this from "no match": the API knows the product but this
        # response carried no string anywhere that looks like a WxDxH triple.
        verdict = "matched, but no measurement text in this response"
    print(f"  search API      : {verdict}  (query: {query!r})")

    layers = (
        ("search-api", api_product.dimensions() if api_product else None),
        ("embedded-json", _from_measure_json(html)),
        ("measurement-block", dimensions_from_labelled(_labelled_measurements(soup))),
        ("description-labels", _from_labelled_text(description)),
        ("title-triple", _from_triple(name)),
        ("markup-triple", _from_raw_triple(html)),
    )
    print("  dimension layers:")
    for label, dims in layers:
        if dims is None:
            verdict = "—"
        elif not dims.is_plausible():
            verdict = f"{dims.as_dict()}  REJECTED (implausible)"
        else:
            verdict = str(dims.as_dict())
        print(f"      {label:<20} {verdict}")

    # Where a "cm" appears in the raw markup is the fastest tell for whether the
    # page carries measurements at all or renders them client-side.
    hits = html.count("cm")
    print(f"  raw 'cm' hits   : {hits}")


def diagnose_render(url: str, *, headed: bool = False) -> int:
    """Run the real browser retry on one URL and show every piece of evidence.

    This exists because a run report can only say `40 retried, 0 recovered` —
    it cannot say *why*. This prints the why: whether the click landed, whether
    the wait condition fired, whether visible measurement tokens appeared, and
    which extraction layer (if any) reads the rendered DOM. The serialised DOM
    goes to render_dump.html so the markup can be inspected directly — grep it
    for `shadowrootmode` to see whether the page uses shadow DOM at all.
    """
    from .render import BrowserRenderer, count_measure_tokens
    from .adapters.ikea import _seat_depth_from_text

    renderer = BrowserRenderer(headless=not headed)
    if not renderer.available:
        print(
            "Playwright is not installed. Run:\n"
            "  pip install playwright && playwright install chromium",
            file=sys.stderr,
        )
        return 2

    print(f"rendering {url}")
    with renderer:
        result = renderer.render(url)

    if result is None:
        print("render failed entirely — see the log lines above", file=sys.stderr)
        return 1

    dump = Path("render_dump.html")
    dump.write_text(result.html, encoding="utf-8")

    print(f"\n  clicks landed     : {len(result.clicks)}")
    for click in result.clicks:
        print(f"      {click}")
    if not result.clicks:
        print("      (nothing matched a measurements control — selector miss or overlay)")
    print(f"  wait condition    : {'measurement text appeared' if result.waited else 'NEVER FIRED (fell back to settle)'}")
    print(f"  visible cm tokens : {result.cm_before} before expand -> {result.cm_after} after")
    print(f"  shadow roots      : {result.html.count('shadowrootmode=')}")
    print(f"  dumped            : {dump.resolve()} ({len(result.html):,} bytes)")

    soup = BeautifulSoup(result.html, "html.parser")
    layers = (
        ("browser-text", _from_labelled_text(result.text)),
        ("embedded-json", _from_measure_json(result.html)),
        ("measurement-block", dimensions_from_labelled(_labelled_measurements(soup))),
        ("markup-triple", _from_raw_triple(result.html)),
        ("browser-triple", _from_raw_triple(result.text)),
    )
    print("\n  extraction layers against the rendered DOM:")
    verdict = None
    for label, dims in layers:
        if dims is None:
            shown = "—"
        elif not dims.is_plausible():
            shown = f"{dims.as_dict()}  REJECTED (implausible)"
        else:
            shown = str(dims.as_dict())
            verdict = verdict or (label, dims)
        print(f"      {label:<20} {shown}")

    seat = _seat_depth_from_text(result.text)
    if seat:
        print(f"      seat depth           {seat} cm (carried separately, never the box)")

    if verdict:
        label, dims = verdict
        print(f"\n  VERDICT: recoverable — {label} yields {dims.as_dict()}")
        return 0
    print(
        "\n  VERDICT: not recovered. Check render_dump.html: search it for a known "
        "value like '228' or for 'shadowrootmode', and for the literal word "
        "'Measurements' to see what the control actually looks like."
    )
    return 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="furn_catalog.diagnose")
    parser.add_argument("urls", nargs="*", help="product URLs (default: probe via the search API)")
    parser.add_argument(
        "--raw",
        metavar="QUERY",
        help=(
            "print the search API's decoded JSON verbatim for QUERY, and exit. "
            "Use this when the dimension layers all come back empty to see "
            "IKEA's actual field names instead of guessing at them again."
        ),
    )
    parser.add_argument(
        "--render",
        metavar="URL",
        help=(
            "run the real browser retry on one URL with full instrumentation: "
            "what was clicked, whether the measurement text appeared, visible "
            "cm-token counts before/after expansion, and every extraction "
            "layer against the rendered DOM. Dumps the shadow-inclusive HTML "
            "to render_dump.html. This is the tool for a "
            "'N retried, 0 recovered' run."
        ),
    )
    parser.add_argument(
        "--headed",
        action="store_true",
        help="with --render: show the browser window instead of running headless",
    )
    parser.add_argument("--cache-dir", type=Path, default=Path(".http-cache"))
    parser.add_argument("--delay", type=float, default=1.0)
    parser.add_argument("-v", "--verbose", action="count", default=0)
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=logging.DEBUG if args.verbose > 1 else logging.INFO,
        format="%(levelname)s %(name)s: %(message)s",
        stream=sys.stderr,
    )

    client = HttpClient(cache_dir=args.cache_dir, delay=args.delay)
    api = IkeaSearchApi(client)

    if args.raw:
        payload = api.raw(args.raw)
        if payload is None:
            print("no response from any endpoint shape — see the warning above", file=sys.stderr)
            return 1
        text = json.dumps(payload, indent=2, ensure_ascii=False)
        print(text[:12_000])
        if len(text) > 12_000:
            print(f"\n... truncated, {len(text):,} bytes total", file=sys.stderr)
        return 0

    if args.render:
        return diagnose_render(args.render, headed=args.headed)

    urls = args.urls
    if not urls:
        found = api.search("sofa", size=5)
        print(f"search API returned {len(found)} products for 'sofa'")
        for product in found:
            print(f"  {product.item_no:<12} {product.measure_text:<20} {product.pip_url}")
        urls = [p.pip_url for p in found[:3]]
        if not urls:
            print("\nThe search API returned nothing — pass a product URL explicitly.")
            return 1

    for url in urls:
        diagnose(client, url, api)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
