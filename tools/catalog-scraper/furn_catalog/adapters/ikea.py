"""IKEA Saudi Arabia (`ikea.com/sa/en`).

IKEA is the highest-yield source for this catalogue: article numbers are stable
and global, the English locale is a first-class site rather than a translation
layer, and every product page carries JSON-LD.

**Dimensions do not come from the page.** The first live run proved it: 54 of
102 candidates parsed cleanly for name and image and produced no measurements
at all, including under a whole-page text sweep for `Width: … cm`. IKEA renders
the measurement block client-side. So the search backend
(`furn_catalog.ikea_api`) is the primary source of the footprint, and the page
is read for everything else. Layered, so a change to any single surface
degrades rather than breaks:

    name / colour / material   JSON-LD `Product` -> og: meta -> <title>
    image                      search API -> JSON-LD -> og:image
    dimensions                 search API -> embedded JSON -> labelled block
                               -> title triple -> page-wide triple

Discovery runs off the same API. Seed lists carry per-market slugs, and IKEA
KSA answers 404 rather than redirecting when the slug disagrees with the
article number, so a harvested URL is not a usable address here — only the
`pipUrl` the API returns for this market is.
"""

from __future__ import annotations

import logging
import re
from collections import Counter
from itertools import zip_longest
from typing import Iterator

from bs4 import BeautifulSoup

from ..aesthetics import SourceSignals
from ..http import FetchError
from ..ikea_api import ApiProduct, IkeaSearchApi
from ..locale import enforce as enforce_ksa
from ..units import (
    Dimensions,
    before_other_sections,
    dimensions_from_labelled,
    measurement_sections,
    parse_triple,
    seat_depth_from_labelled,
    to_cm,
)
from .base import Adapter, RawProduct, classify_category, price_from_json_ld, price_from_text

log = logging.getLogger(__name__)

# Trailing token of an IKEA product URL: `s79482824` (a multi-part article) or
# `00519361` (a single article). This is the SKU the Furn-App record needs.
_SKU_RE = re.compile(r"/p/(?:[a-z0-9\-]+?)-(s?\d{8})/?$", re.IGNORECASE)

#: Locale-agnostic product path, used to rewrite a seed onto the KSA site.
_PRODUCT_PATH_RE = re.compile(r"/p/([a-z0-9\-]+-s?\d{8})/?", re.IGNORECASE)

#: `"itemMeasureReferenceText":"228x95x83 cm"` inside any embedded JSON blob.
_MEASURE_JSON_RE = re.compile(
    r'"(?:itemMeasureReferenceText|measureText|measurementText|itemMeasure)"\s*:\s*"([^"]{3,60})"'
)

#: `Width: 228 cm`, `Seat depth: 54 cm`, `Height including back cushions: 84 cm`
#: — wherever they appear in text, capturing the **whole label**, qualifier and
#: all, so `classify_label` can judge it.
#:
#: The predecessor captured only the bare axis word, which destroyed the
#: qualifier before anything could reject it: `Armrest width: 3.5 cm` arrived
#: downstream as `width: 3.5 cm` and, first-match-wins, beat the real
#: `Width: 132 cm`. The fix is not a longer list of lookbehinds — it is to stop
#: throwing away the evidence and let one whitelist decide.
#:
#: Two words before the axis word and four after: enough for `Compressed
#: packaging depth` and `Height including back cushions`, tight enough that a
#: run-on sentence does not swallow a legitimate label. Section headings that
#: still slip in ("Measurements Width") are stripped by `classify_label`.
_AXIS_WORDS_RE = (
    r"width|depth|height|length|"
    r"عرض|العرض|عمق|العمق|طول|الطول|ارتفاع|الارتفاع"
)
_LABEL_VALUE_RE = re.compile(
    r"(?P<label>(?:[A-Za-z؀-ۿ.]+[ \t]+){0,2}?"
    rf"(?:{_AXIS_WORDS_RE})"
    r"(?:[ \t]+[A-Za-z؀-ۿ.]+){0,4}?)"
    r"[ \t]*[:：\-]?[ \t]*"
    r"(?P<value>\d[\d.,]*(?:[ \t]*\d+/\d+)?[ \t]*(?:cm|mm|m|in|inches|\"|سم|مم)(?![a-z]))",
    re.IGNORECASE,
)

#: A bare `228x95x83 cm` anywhere in the raw markup. Last resort — it will
#: happily match an unrelated triple, so the caller gates it on plausibility.
_RAW_TRIPLE_RE = re.compile(
    r"\b(\d{1,3}(?:[.,]\d+)?)\s*[x×]\s*(\d{1,3}(?:[.,]\d+)?)\s*[x×]\s*"
    r"(\d{1,3}(?:[.,]\d+)?)\s*cm\b",
    re.IGNORECASE,
)


class IkeaAdapter(Adapter):
    store = "IKEA KSA"
    base_url = "https://www.ikea.com/sa/en"

    #: Search terms used to enumerate the catalogue, chosen to spread across the
    #: categories `classify_category` knows about rather than to be exhaustive.
    SEARCH_QUERIES = (
        "sofa",
        "3-seat sofa",
        "corner sofa",
        "armchair",
        "bed frame",
        "chest of drawers",
        "wardrobe",
        "bookcase",
        "shelving unit",
        "dining table",
        "coffee table",
        "bedside table",
        "desk",
        "tv bench",
        "dining chair",
    )

    #: Category listing pages, crawled only if the search API is unreachable.
    LISTINGS = (
        "/cat/sofas-fu003/",
        "/cat/beds-bm003/",
        "/cat/tables-desks-fu004/",
        "/cat/chairs-fu002/",
        "/cat/chests-of-drawers-drawer-units-st002/",
        "/cat/bookcases-shelving-units-st002/",
        "/cat/wardrobes-19053/",
    )

    #: How many fabric/finish variants of one model may be taken before the
    #: rest are deferred. IKEA lists a sofa once per cover, and four colours of
    #: one EKTORP are a single footprint to the solver.
    DEFAULT_MAX_VARIANTS = 2

    def __init__(
        self,
        client,
        seeds: list[str] | None = None,
        *,
        renderer=None,
        use_api: bool = True,
        max_variants_per_model: int | None = None,
    ) -> None:
        super().__init__(client, renderer)
        self._seeds = seeds or []
        self._api = IkeaSearchApi(client) if use_api else None
        #: article number -> what the API told us, consulted during parse().
        self._api_index: dict[str, ApiProduct] = {}
        self.max_variants_per_model = (
            self.DEFAULT_MAX_VARIANTS if max_variants_per_model is None else max_variants_per_model
        )

    # ------------------------------------------------------------- discovery

    @staticmethod
    def to_ksa_url(url: str) -> str | None:
        """Rewrite an IKEA product URL onto the `/sa/en/` locale.

        Only sound when the slug is already the KSA one. A slug harvested from
        another market keeps that market's spelling (`gray` vs `grey`) and IKEA
        KSA 404s it, which is why discovery prefers the API's `pipUrl` and this
        is now a fallback rather than the main path.
        """
        match = _PRODUCT_PATH_RE.search(url)
        if not match:
            return None
        return f"https://www.ikea.com/sa/en/p/{match.group(1)}/"

    def _round_robin(self) -> Iterator[ApiProduct]:
        """Search results interleaved across queries, one per query per pass.

        Also caps how many variants of the same model can come through. IKEA
        lists each sofa once per fabric, so an un-capped `sofa` query returns
        four EKTORPs before it returns a second model — and four colours of one
        sofa are one footprint as far as the solver is concerned. The cap is on
        the model, not the category, so a genuinely different sofa is unaffected.
        """
        buckets: list[list[ApiProduct]] = []
        for query in self.SEARCH_QUERIES:
            found = self._api.search(query) if self._api else []
            if found:
                buckets.append(found)

        families: Counter[str] = Counter()
        deferred: list[ApiProduct] = []

        for row in zip_longest(*buckets):
            for product in row:
                if product is None:
                    continue
                family = f"{product.name} {product.type_name}".strip().lower()
                if families[family] >= self.max_variants_per_model:
                    # Not discarded — a run that would otherwise come up short
                    # should still use them, just after everything else.
                    deferred.append(product)
                    continue
                families[family] += 1
                yield product

        yield from deferred

    def discover(self, limit: int) -> Iterator[str]:
        seen: set[str] = set()

        def offer(url: str) -> Iterator[str]:
            # Locale gate. The API answers with KSA URLs and the seed rewrite
            # targets KSA, but a listing page links wherever it likes, and one
            # `/ae/en/` link that parses cleanly is a product nobody in Riyadh
            # can buy. Everything funnels through here so there is one gate.
            ksa = enforce_ksa(url)
            if ksa and ksa not in seen:
                seen.add(ksa)
                yield ksa

        # 1. The search API, round-robin across queries.
        #
        #    Draining one query before starting the next produced a catalogue
        #    that was 47/50 sofas: `sofa`, `3-seat sofa` and `corner sofa`
        #    between them returned more products than the whole run needed, so
        #    discovery stopped before it ever asked about desks or wardrobes.
        #    Rotating takes the first result of every query, then the second of
        #    every query, so a short run is a broad one.
        if self._api is not None:
            for product in self._round_robin():
                self._api_index.setdefault(product.item_no, product)
                yield from offer(product.pip_url)
                if len(seen) >= limit:
                    return

        # 2. Seeds. Kept because they cost nothing once the API has run: an
        #    article the API index already knows resolves to its canonical URL.
        for seed in self._seeds:
            if len(seen) >= limit:
                return
            article = _article_of(seed)
            known = self._api_index.get(article) if article else None
            url = known.pip_url if known else (self.to_ksa_url(seed) or seed)
            yield from offer(url)

        # 3. HTML listing crawl, for when the API is unavailable entirely.
        for listing in self.LISTINGS:
            if len(seen) >= limit:
                return
            try:
                soup = self.soup(self.base_url + listing)
            except FetchError as exc:
                log.warning("listing %s unavailable (%s)", listing, exc)
                continue

            for anchor in soup.select("a[href*='/p/']"):
                href = anchor.get("href") or ""
                if href.startswith("/"):
                    href = "https://www.ikea.com" + href
                url = self.to_ksa_url(href)
                if url:
                    yield from offer(url)
                    if len(seen) >= limit:
                        return

    # ----------------------------------------------------------------- parse

    def parse(self, url: str, *, render: bool = False) -> RawProduct | None:
        url = enforce_ksa(url) or url
        sku_match = _SKU_RE.search(url)
        if not sku_match:
            log.debug("no article number in %s", url)
            return None
        api = self._api_index.get(sku_match.group(1).lower())

        try:
            html, final_url = self.fetch(url, render=render)
        except FetchError as exc:
            # The article is not stocked in KSA, or the slug is from another
            # market. If the API described it we still have every field the
            # schema needs, so a dead page is not automatically a dead product.
            log.info("page unavailable for %s (%s)", url, exc)
            return self._from_api_only(api) if api else None

        soup = BeautifulSoup(html, "html.parser")

        sku_match = _SKU_RE.search(final_url) or sku_match
        sku = sku_match.group(1)
        # A canonical tag can point at the global site; the locale gate wins.
        canonical = enforce_ksa(_canonical_link(soup) or final_url) or url

        product = self.product_json_ld(soup) or {}

        name = str(product.get("name") or self.meta(soup, "og:title") or "").strip()
        if not name:
            title = soup.find("title")
            name = title.get_text(strip=True) if title else ""
        name = _clean_name(name) or (api.full_name if api else "")
        if not name:
            return None

        image = (
            self.first_image(product.get("image"))
            or self.meta(soup, "og:image")
            or (api.image_url if api else "")
        )
        colour = _colour_from(product, name) or (api.colour if api else "")
        material = _materials_from(soup)
        description = str(product.get("description") or self.meta(soup, "og:description") or "")

        category = classify_category(
            name, description, str(product.get("category") or ""), api.type_name if api else ""
        )
        if category is None:
            log.debug("could not categorise %s", name)
            return None

        # The visible, shadow-pierced text of the rendered page. Only present
        # on a browser retry; the strongest page-level evidence there is,
        # because it is literally what a human reading the panel would see.
        render_text = self.last_render.text if self.last_render else ""

        dimensions, source = self._dimensions(soup, html, name, description, api, render_text)
        price = (
            price_from_json_ld(product)
            or price_from_text(soup.get_text(" ", strip=True)[:4000])
            or price_from_text(render_text[:4000])
            or (api.price_sar if api else None)
        )

        return RawProduct(
            product_name=name,
            product_link=canonical,
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
                "source": "ikea-json-ld" if product else "ikea-html",
                "dimensions_from": source,
                "rendered": render,
                **(
                    {
                        "render_clicks": len(self.last_render.clicks),
                        "render_waited": self.last_render.waited,
                        "render_cm_tokens": (
                            f"{self.last_render.cm_before}->{self.last_render.cm_after}"
                        ),
                    }
                    if self.last_render
                    else {}
                ),
                **({"requested_url": url} if canonical != url else {}),
            },
        )

    def _from_api_only(self, api: ApiProduct) -> RawProduct | None:
        """Build a record from the search API when the product page is gone.

        Every field the schema requires is present in the API response, so this
        is a complete record rather than a degraded one — it just carries no
        materials text, which only softens the aesthetic inference.
        """
        category = classify_category(api.full_name, api.type_name)
        if category is None:
            return None
        link = enforce_ksa(api.pip_url)
        if link is None:
            return None
        return RawProduct(
            product_name=api.full_name,
            product_link=link,
            sku=api.item_no,
            image_url=api.image_url,
            category=category,
            dimensions=api.dimensions(),
            price_sar=api.price_sar,
            signals=SourceSignals(
                product_name=api.full_name,
                category=category,
                colour_text=api.colour,
                material_text="",
                description=api.type_name,
                image_url=api.image_url,
            ),
            notes={"source": "ikea-search-api", "dimensions_from": "search-api"},
        )

    # ------------------------------------------------------------ dimensions

    def _dimensions(
        self,
        soup: BeautifulSoup,
        html: str,
        name: str,
        description: str,
        api: ApiProduct | None,
        render_text: str = "",
    ) -> tuple[Dimensions | None, str]:
        """Try every known source in descending order of authority.

        The winning source is returned alongside the footprint and recorded in
        the record's provenance, so a run can be audited for how much of the
        catalogue leaned on the weaker fallbacks.

        `render_text` is the visible, shadow-pierced text of a browser-rendered
        page — present only on a retry. It sits directly after the search API
        because it is what the opened measurement panel literally displays,
        and the labelled parser it feeds only accepts Width/Depth/Height/Length
        labels, so seat depth or package figures cannot leak into the box.
        """
        labelled = _labelled_measurements(soup)
        candidates: list[tuple[str, Dimensions | None]] = [
            ("search-api", api.dimensions() if api else None),
            ("browser-text", _from_labelled_text(render_text)),
            ("embedded-json", _from_measure_json(html)),
            ("measurement-block", dimensions_from_labelled(labelled)),
            ("description-labels", _from_labelled_text(description)),
            ("title-triple", _from_triple(name)),
            ("page-triple", _from_triple(description)),
            ("markup-triple", _from_raw_triple(html)),
            ("browser-triple", _from_raw_triple(render_text)),
        ]
        # Seat depth comes from the measurement table wherever the bounding box
        # came from — the two are independent, and a sofa sized from the API
        # still has its seat depth published on the page.
        seat_depth = (
            seat_depth_from_labelled(labelled)
            or _seat_depth_from_text(render_text)
            or _seat_depth_from_text(html)
        )

        for source, dims in candidates:
            if dims is not None and dims.is_plausible():
                return dims.with_seat_depth(seat_depth), source
        return None, "none"


# ------------------------------------------------------------------ helpers


def _article_of(url: str) -> str:
    match = _SKU_RE.search(url) or re.search(r"(s?\d{8})", url)
    return match.group(1).lower() if match else ""


def _from_triple(text: str) -> Dimensions | None:
    triple = parse_triple(text or "")
    if not triple:
        return None
    width, depth, height = triple
    return Dimensions.from_retailer(width=width, depth=depth, height=height)


def _from_measure_json(html: str) -> Dimensions | None:
    """Read the measurement triple out of any JSON embedded in the page."""
    for match in _MEASURE_JSON_RE.finditer(html or ""):
        dims = _from_triple(match.group(1))
        if dims is not None and dims.is_plausible():
            return dims
    return None


def _from_raw_triple(html: str) -> Dimensions | None:
    """Scan the whole markup for a `228x95x83 cm` triple.

    The weakest source by a wide margin: it cannot tell a product's footprint
    from a triple in an unrelated block, so it sits last and only survives the
    plausibility gate.
    """
    for match in _RAW_TRIPLE_RE.finditer(html or ""):
        try:
            width, depth, height = (float(match.group(i).replace(",", ".")) for i in (1, 2, 3))
        except ValueError:
            continue
        candidate = Dimensions.from_retailer(width=width, depth=depth, height=height)
        if candidate.is_plausible():
            return candidate
    return None


#: `"Seat depth": "60 cm"` in embedded JSON, or `Seat depth: 60 cm` in text.
_SEAT_DEPTH_RE = re.compile(
    r"seat\s*depth\W{0,4}?(\d[\d.,]*\s*(?:cm|mm))", re.IGNORECASE
)


def _seat_depth_from_text(html: str) -> float | None:
    """Seat depth from anywhere in the markup, including embedded JSON."""
    match = _SEAT_DEPTH_RE.search(html or "")
    if not match:
        return None
    try:
        value = to_cm(match.group(1))
    except Exception:  # noqa: BLE001 - an unparseable seat depth is simply absent
        return None
    return value if 1.0 <= value <= 200.0 else None


def labelled_pairs_from_text(text: str) -> dict[str, str]:
    """Every `label: value` measurement in free text, labels kept intact.

    Keys are the full labels (`Seat depth`, not `depth`), because that is what
    `classify_label` needs in order to reject a component measurement. A label
    seen twice keeps its first value; distinct labels never collide, so a
    sub-measurement can no longer occupy the slot of a real axis.
    """
    pairs: dict[str, str] = {}
    for match in _LABEL_VALUE_RE.finditer(text or ""):
        label = " ".join(match.group("label").split())
        pairs.setdefault(label, match.group("value"))
    return pairs


def _from_labelled_text(text: str) -> Dimensions | None:
    """Build a footprint from `Width: 228 cm` phrasing in free text.

    Scoped to the measurements panel. Reading the whole page instead lets the
    packaging block compete for the same axes under the same bare labels — an
    EKTORP came back 205cm deep, which is its carton, not its footprint.
    """
    for section in measurement_sections(text):
        pairs = labelled_pairs_from_text(section)
        if not pairs:
            continue
        dimensions = dimensions_from_labelled(pairs)
        if dimensions is not None:
            return dimensions

    # No recognisable panel; read the page but still stop short of packaging.
    pairs = labelled_pairs_from_text(before_other_sections(text))
    return dimensions_from_labelled(pairs) if pairs else None


def _labelled_measurements(soup: BeautifulSoup) -> dict[str, str]:
    """Pull `{label: value}` pairs out of IKEA's measurement block.

    The markup has changed shape several times, so we try the current
    `dl`/`dt`/`dd` structure, the older `pip-product-dimensions` list, and a
    generic "Label: 95 cm" text sweep as a last resort.
    """
    pairs: dict[str, str] = {}

    for definition in soup.select("dl dt"):
        value = definition.find_next_sibling("dd")
        if value:
            pairs.setdefault(definition.get_text(strip=True), value.get_text(strip=True))

    for item in soup.select(
        ".pip-product-dimensions__measurement, .pip-product-dimensions__dimensions-container p"
    ):
        text = item.get_text(" ", strip=True)
        label, _, value = text.partition(":")
        if value:
            pairs.setdefault(label.strip(), value.strip())

    if not pairs:
        for label, value in labelled_pairs_from_text(soup.get_text(" ", strip=True)).items():
            pairs.setdefault(label, value)

    return pairs


def _canonical_link(soup: BeautifulSoup) -> str:
    """The page's own <link rel="canonical">, the most authoritative URL."""
    tag = soup.find("link", attrs={"rel": "canonical"})
    href = (tag.get("href") or "").strip() if tag else ""
    return href if href.startswith("https://") and "/p/" in href else ""


def _clean_name(raw: str) -> str:
    """Trim IKEA's SEO suffixes off the product title."""
    name = re.sub(r"\s*[-|]\s*IKEA.*$", "", raw, flags=re.IGNORECASE).strip()
    return re.sub(r"\s+", " ", name)


def _colour_from(product: dict, name: str) -> str:
    colour = product.get("color") or product.get("colour")
    if colour:
        return str(colour)
    # IKEA encodes the variant after the last comma: "KIVIK 3-seat sofa, Tresund anthracite".
    _, _, tail = name.rpartition(",")
    return tail.strip()


def _materials_from(soup: BeautifulSoup) -> str:
    """Scrape the materials & care section, which IKEA renders as plain text."""
    chunks: list[str] = []
    for selector in (
        "#SEC_product-details-material",
        ".pip-product-details__container",
        "[id*='material']",
    ):
        for node in soup.select(selector):
            text = node.get_text(" ", strip=True)
            if text:
                chunks.append(text)
        if chunks:
            break
    return " ".join(chunks)[:2000]


__all__ = ["IkeaAdapter", "to_cm"]
