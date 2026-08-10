"""Sitemap-driven discovery.

The hardcoded category paths in the first version of the Home Centre and Abyat
adapters were guesses, and the live run showed what guesses are worth: five
404s and five 202 challenge pages. Replacing them with *better* guesses would
buy one more run before they rot again.

Sitemaps do not rot the same way. They are published by the retailer, listed in
robots.txt, and exist precisely so that a crawler does not have to guess URL
structure — using them is both more robust and more polite than scraping
navigation. A retailer who reorganises `/c/furniture-beds` into
`/c/bedroom/beds` updates the sitemap in the same deploy.

Two entry points:

* `sitemap_urls_from_robots` — the `Sitemap:` directives a host advertises.
* `iter_sitemap` — walks an index or urlset, following nested indexes to a
  bounded depth, yielding `<loc>` values.

Both are namespace-agnostic (`{...}loc` and bare `loc` are both matched) and
neither raises on a malformed document: a broken sitemap yields nothing and the
caller falls back to its curated paths.
"""

from __future__ import annotations

import logging
import re
from typing import Iterator, Sequence
from xml.etree import ElementTree

from .http import FetchError, HttpClient

log = logging.getLogger(__name__)

#: Depth of nested sitemap indexes to follow. Two is enough for every retail
#: sitemap I have seen (index -> per-type index -> urlset) and bounds the work.
MAX_DEPTH = 2

#: Sitemaps for a big retailer run to hundreds of thousands of URLs; discovery
#: only ever needs the first few hundred matches.
MAX_URLS = 20_000

_LOC_RE = re.compile(r"<loc>\s*([^<\s]+)\s*</loc>", re.IGNORECASE)


def sitemap_urls_from_robots(client: HttpClient, origin: str, **kwargs) -> list[str]:
    """`Sitemap:` directives advertised in a host's robots.txt."""
    try:
        body = client.get(f"{origin}/robots.txt", **kwargs)
    except FetchError as exc:
        log.debug("no robots.txt for %s (%s)", origin, exc)
        return []

    found: list[str] = []
    for line in body.splitlines():
        name, _, value = line.partition(":")
        if name.strip().lower() == "sitemap":
            url = value.strip()
            if url.startswith("http"):
                found.append(url)
    return found


def iter_sitemap(
    client: HttpClient,
    url: str,
    *,
    match: re.Pattern[str] | None = None,
    depth: int = 0,
    limit: int = MAX_URLS,
    seen: set[str] | None = None,
    **kwargs,
) -> Iterator[str]:
    """Yield `<loc>` URLs from a sitemap or sitemap index.

    `match` filters the URLs yielded, not the indexes followed — a product
    sitemap is rarely named after the products it holds, so filtering indexes
    would skip the file we want.
    """
    seen = seen if seen is not None else set()
    if url in seen or depth > MAX_DEPTH or len(seen) > limit:
        return
    seen.add(url)

    try:
        body = client.get(url, **kwargs)
    except FetchError as exc:
        log.debug("sitemap %s unavailable (%s)", url, exc)
        return

    is_index, locations = _parse(body)

    if is_index:
        for child in locations:
            yield from iter_sitemap(
                client, child, match=match, depth=depth + 1, limit=limit, seen=seen, **kwargs
            )
        return

    for location in locations:
        if match is None or match.search(location):
            yield location


def _parse(body: str) -> tuple[bool, list[str]]:
    """`(is_index, locations)` from a sitemap document.

    Tries XML first and falls back to a regex sweep, because retailers serve
    sitemaps with stray doctypes, BOMs, and occasionally HTML error pages under
    an XML content type — none of which should cost us the URLs inside.
    """
    try:
        root = ElementTree.fromstring(body.strip())
    except ElementTree.ParseError:
        locations = _LOC_RE.findall(body)
        return ("<sitemapindex" in body[:2000].lower(), locations)

    tag = _localname(root.tag)
    locations = [
        node.text.strip()
        for node in root.iter()
        if _localname(node.tag) == "loc" and node.text and node.text.strip()
    ]
    return tag == "sitemapindex", locations


def _localname(tag: str) -> str:
    return tag.rsplit("}", 1)[-1].lower()


def discover_products(
    client: HttpClient,
    origin: str,
    *,
    product_pattern: re.Pattern[str],
    extra_sitemaps: Sequence[str] = (),
    limit: int = 500,
    **kwargs,
) -> Iterator[str]:
    """Product URLs for a host, found via its advertised sitemaps.

    `extra_sitemaps` are conventional paths tried when robots.txt advertises
    none — several storefronts serve `/sitemap.xml` without listing it.
    """
    sources = sitemap_urls_from_robots(client, origin, **kwargs) or [
        f"{origin}{path}" for path in extra_sitemaps
    ]
    if not sources:
        log.info("%s advertises no sitemap", origin)
        return

    emitted = 0
    for source in sources:
        for url in iter_sitemap(client, source, match=product_pattern, **kwargs):
            yield url
            emitted += 1
            if emitted >= limit:
                return


__all__ = ["MAX_DEPTH", "discover_products", "iter_sitemap", "sitemap_urls_from_robots"]
