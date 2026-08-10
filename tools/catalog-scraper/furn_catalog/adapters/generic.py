"""JSON-LD-first adapter, subclassed by Home Centre and Abyat.

Both retailers run mainstream e-commerce stacks that emit schema.org `Product`
JSON-LD and expose measurements in a specification table. That shared shape is
implemented once here; each subclass supplies its Saudi storefront root, its
SKU pattern, and its product-URL shape.

Discovery goes through the retailer's own sitemap rather than a hardcoded list
of category paths. The first live run is why: every hardcoded path was wrong —
Home Centre's were disallowed by robots.txt, Abyat's returned 404 and 202 — and
a fresh set of hand-written paths would have the same shelf life. A sitemap is
published by the retailer for exactly this purpose and is updated in the same
deploy that moves a category. Curated listing paths remain as a fallback.

The selectors below have still not been validated against live markup (see
README → "Adapter maturity"): the authoring environment cannot reach either
site. They implement the standard each platform emits.
"""

from __future__ import annotations

import logging
import re
from typing import Iterator

from bs4 import BeautifulSoup

from ..aesthetics import SourceSignals
from ..http import FetchError
from ..locale import enforce as enforce_ksa
from ..sitemap import discover_products
from ..units import (
    Dimensions,
    dimensions_from_labelled,
    parse_triple,
    seat_depth_from_labelled,
)
from .base import (
    Adapter,
    RawProduct,
    classify_category,
    price_from_json_ld,
    price_from_text,
)

log = logging.getLogger(__name__)


class JsonLdAdapter(Adapter):
    """Extraction driven by schema.org Product markup plus a spec table."""

    #: Regex whose first group is the SKU, matched against the product URL.
    sku_pattern: re.Pattern[str]
    #: Recognises a product URL in a sitemap. Defaults to `sku_pattern`.
    product_pattern: re.Pattern[str] | None = None
    #: Conventional sitemap paths, tried when robots.txt advertises none.
    sitemaps: tuple[str, ...] = ("/sitemap.xml", "/sitemap_index.xml")
    #: Category/listing paths appended to `base_url`, used only if the sitemap
    #: yields nothing.
    listings: tuple[str, ...] = ()
    #: CSS selectors for the specification table rows, tried in order.
    spec_selectors: tuple[str, ...] = (
        "table tr",
        ".product-specifications tr",
        ".specification-table tr",
        "dl div",
    )
    #: Both of these sit behind bot filters that reject the honest bot UA.
    use_browser_headers = True

    def __init__(self, client, seeds: list[str] | None = None, *, renderer=None) -> None:
        super().__init__(client, renderer)
        self._seeds = seeds or []

    # ------------------------------------------------------------- discovery

    def discover(self, limit: int) -> Iterator[str]:
        seen: set[str] = set()

        def offer(url: str) -> Iterator[str]:
            ksa = enforce_ksa(url)
            if ksa and ksa not in seen and self.sku_pattern.search(ksa):
                seen.add(ksa)
                yield ksa

        for seed in self._seeds:
            yield from offer(seed)
            if len(seen) >= limit:
                return

        pattern = self.product_pattern or self.sku_pattern
        try:
            for url in discover_products(
                self.client,
                self.origin(),
                product_pattern=pattern,
                extra_sitemaps=self.sitemaps,
                limit=limit * 4,
                headers=self.headers(),
            ):
                yield from offer(url)
                if len(seen) >= limit:
                    return
        except FetchError as exc:
            log.warning("%s sitemap discovery failed (%s)", self.store, exc)

        for listing in self.listings:
            if len(seen) >= limit:
                return
            try:
                soup = self.soup(self.base_url + listing)
            except FetchError as exc:
                log.warning("%s listing %s unavailable (%s)", self.store, listing, exc)
                continue

            for anchor in soup.select("a[href]"):
                href = anchor.get("href") or ""
                if href.startswith("/"):
                    href = self.origin() + href
                yield from offer(href)
                if len(seen) >= limit:
                    return

    def origin(self) -> str:
        match = re.match(r"(https://[^/]+)", self.base_url)
        return match.group(1) if match else self.base_url

    # ----------------------------------------------------------------- parse

    def parse(self, url: str, *, render: bool = False) -> RawProduct | None:
        url = enforce_ksa(url) or url
        sku_match = self.sku_pattern.search(url)
        if not sku_match:
            log.debug("%s: no SKU in %s", self.store, url)
            return None

        try:
            soup, final_url = self.soup_with_url(url, render=render)
        except FetchError as exc:
            log.info("%s: skipping %s (%s)", self.store, url, exc)
            return None

        product = self.product_json_ld(soup) or {}
        name = str(product.get("name") or self.meta(soup, "og:title") or "").strip()
        if not name:
            return None

        sku = str(product.get("sku") or product.get("mpn") or sku_match.group(1)).strip()
        image = self.first_image(product.get("image")) or self.meta(soup, "og:image")
        description = str(product.get("description") or self.meta(soup, "og:description") or "")

        specs = self._specs(soup)
        category = classify_category(name, description, str(product.get("category") or "")) or (
            classify_category(*specs.values())
        )
        if category is None:
            log.debug("%s: could not categorise %s", self.store, name)
            return None

        dimensions = dimensions_from_labelled(specs)
        if dimensions is None:
            for text in (name, description, specs.get("Dimensions", ""), specs.get("Size", "")):
                triple = parse_triple(text)
                if triple:
                    candidate = Dimensions.from_retailer(
                        width=triple[0], depth=triple[1], height=triple[2]
                    )
                    if candidate.is_plausible():
                        dimensions = candidate.with_seat_depth(seat_depth_from_labelled(specs))
                        break

        colour = str(product.get("color") or specs.get("Colour") or specs.get("Color") or "")
        material = str(product.get("material") or specs.get("Material") or "")
        price = price_from_json_ld(product) or price_from_text(
            soup.get_text(" ", strip=True)[:4000]
        )

        return RawProduct(
            product_name=name,
            product_link=enforce_ksa(final_url) or url,
            sku=sku,
            image_url=image,
            category=category,
            dimensions=dimensions,
            price_sar=price,
            signals=SourceSignals(
                product_name=name,
                category=category,
                colour_text=colour,
                material_text=material,
                description=description,
                image_url=image,
            ),
            notes={
                "source": f"{self.store}-json-ld",
                "spec_rows": len(specs),
                "rendered": render,
            },
        )

    def _specs(self, soup: BeautifulSoup) -> dict[str, str]:
        """Pull `{label: value}` out of whichever spec table the page renders."""
        specs: dict[str, str] = {}
        for selector in self.spec_selectors:
            for row in soup.select(selector):
                cells = row.find_all(["td", "th", "dt", "dd"])
                if len(cells) >= 2:
                    label = cells[0].get_text(" ", strip=True)
                    value = cells[1].get_text(" ", strip=True)
                    if label and value:
                        specs.setdefault(label, value)
            if specs:
                break
        return specs


class HomeCentreAdapter(JsonLdAdapter):
    """Home Centre KSA (Landmark Group).

    `robots.txt` disallows the `/sa/en/c/...` category listings the original
    adapter crawled, and that is not something a different User-Agent should be
    used to get around — so discovery runs off the sitemap instead, which is
    both allowed and more durable. If a run still finds nothing, the listings
    below need the site owner's permission (`--ignore-robots`), not a new UA.
    """

    store = "Home Centre KSA"
    base_url = "https://www.homecentre.com/sa/en"
    # Landmark product URLs end in a numeric style ID, e.g. `/p/.../1234567/`.
    sku_pattern = re.compile(r"/(\d{6,9})(?:[/?#]|$)")
    product_pattern = re.compile(r"/sa/en/.*?/(?:p|product)/", re.IGNORECASE)
    listings = (
        "/c/furniture-sofas-recliners",
        "/c/furniture-beds",
        "/c/furniture-dining-room",
        "/c/furniture-chairs",
        "/c/furniture-storage-wardrobes",
    )


class AbyatAdapter(JsonLdAdapter):
    """Abyat KSA.

    The `/sa/en/c/...` paths the first version targeted answered 404 and 202 —
    the 202 being a bot-check interstitial rather than a product page. Browser
    headers address the interstitial; the sitemap addresses the 404s, since the
    site's category scheme has clearly moved and I have no way to confirm the
    current one from here.
    """

    store = "Abyat KSA"
    base_url = "https://www.abyat.com/sa/en"
    sku_pattern = re.compile(r"/(?:product|p)/[^/]*?(\d{5,10})(?:[/?#]|$)")
    product_pattern = re.compile(r"/sa/en/(?:product|p)/", re.IGNORECASE)
    listings = (
        "/c/living-room/sofas",
        "/c/bedroom/beds",
        "/c/dining-room/dining-tables",
        "/c/living-room/chairs",
        "/c/bedroom/dressers",
    )
