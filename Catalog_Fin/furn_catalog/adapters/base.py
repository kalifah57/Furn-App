"""The contract every retailer adapter implements."""

from __future__ import annotations

import json
import re
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Any, Iterator

from bs4 import BeautifulSoup

from ..aesthetics import SourceSignals
from ..http import HttpClient
from ..render import BrowserRenderer, RenderResult, browser_headers
from ..units import (
    Dimensions,
    before_other_sections,
    dimensions_from_labelled,
    measurement_sections,
    parse_triple,
)


@dataclass
class RawProduct:
    """What an adapter manages to pull off a product page, before validation."""

    product_name: str
    product_link: str
    sku: str
    image_url: str
    category: str
    dimensions: Dimensions | None
    signals: SourceSignals
    #: Retail price in SAR, when the page published one.
    price_sar: float | None = None
    notes: dict[str, Any] = field(default_factory=dict)


class Adapter(ABC):
    """A retailer-specific extractor.

    `store` is the label written into the catalogue; `discover` yields candidate
    product URLs; `parse` turns one product page into a RawProduct.
    """

    store: str
    #: Locale-qualified site root, always the Saudi English one.
    base_url: str
    #: Send desktop-Chrome headers instead of the honest bot UA. Set on the
    #: retailers whose filters answer `FurnAppCatalogBot` with a challenge page.
    #: Does not affect robots.txt, which is still evaluated against our own UA.
    use_browser_headers: bool = False

    def __init__(self, client: HttpClient, renderer: BrowserRenderer | None = None) -> None:
        self.client = client
        self.renderer = renderer
        #: The full result of the most recent rendered fetch, so parse() can
        #: reach the visible text and diagnostics that a bare HTML string
        #: cannot carry. Reset on every fetch.
        self.last_render: RenderResult | None = None

    @abstractmethod
    def discover(self, limit: int) -> Iterator[str]:
        """Yield candidate product-page URLs."""

    @abstractmethod
    def parse(self, url: str, *, render: bool = False) -> RawProduct | None:
        """Parse one product page. Return None if it isn't a usable product.

        `render` asks for the headless-browser path, which opens collapsible
        measurement panels before reading the markup. The pipeline sets it on a
        retry, so the expensive path is only paid for pages that need it.
        """

    # ------------------------------------------------------------- utilities

    def headers(self, referer: str = "") -> dict[str, str] | None:
        return browser_headers(referer) if self.use_browser_headers else None

    def fetch(self, url: str, *, render: bool = False) -> tuple[str, str]:
        """Page HTML and the URL we landed on, optionally via the browser.

        A browser render that fails for any reason falls through to the static
        fetch rather than propagating — the static result is what the pipeline
        had before renderers existed, so degrading to it is always safe.

        A successful render also populates `self.last_render` with the full
        RenderResult (visible text, click trail, token counts), because the
        HTML string alone cannot carry the visible-text layer the dimension
        extraction needs. A plain string return is accepted too, for test
        doubles written against the older contract.
        """
        self.last_render = None
        if render and self.renderer is not None:
            result = self.renderer.render(url)
            if isinstance(result, RenderResult) and result.html:
                self.last_render = result
                return result.html, url
            if isinstance(result, str) and result:
                return result, url
        return self.client.get_with_url(url, headers=self.headers())

    def soup(self, url: str, *, render: bool = False) -> BeautifulSoup:
        return BeautifulSoup(self.fetch(url, render=render)[0], "html.parser")

    def soup_with_url(self, url: str, *, render: bool = False) -> tuple[BeautifulSoup, str]:
        """Parse a page and report the URL we actually landed on."""
        body, final_url = self.fetch(url, render=render)
        return BeautifulSoup(body, "html.parser"), final_url

    @staticmethod
    def json_ld(soup: BeautifulSoup) -> list[dict[str, Any]]:
        """Every JSON-LD object on the page, flattened.

        Retailers nest these inconsistently — sometimes a bare object, sometimes
        a list, sometimes an @graph — so normalise all three shapes here.
        """
        blocks: list[dict[str, Any]] = []
        for tag in soup.find_all("script", attrs={"type": "application/ld+json"}):
            raw = tag.string or tag.get_text()
            if not raw:
                continue
            try:
                data = json.loads(raw)
            except json.JSONDecodeError:
                continue
            candidates = data if isinstance(data, list) else [data]
            for entry in candidates:
                if not isinstance(entry, dict):
                    continue
                if "@graph" in entry and isinstance(entry["@graph"], list):
                    blocks.extend(e for e in entry["@graph"] if isinstance(e, dict))
                else:
                    blocks.append(entry)
        return blocks

    @classmethod
    def product_json_ld(cls, soup: BeautifulSoup) -> dict[str, Any] | None:
        for block in cls.json_ld(soup):
            types = block.get("@type", "")
            types = types if isinstance(types, list) else [types]
            if any(str(t).lower() == "product" for t in types):
                return block
        return None

    @staticmethod
    def meta(soup: BeautifulSoup, prop: str) -> str:
        tag = soup.find("meta", attrs={"property": prop}) or soup.find(
            "meta", attrs={"name": prop}
        )
        return (tag.get("content") or "").strip() if tag else ""

    @staticmethod
    def first_image(value: Any) -> str:
        """JSON-LD `image` may be a string, a list, or an ImageObject."""
        if isinstance(value, str):
            return value
        if isinstance(value, list) and value:
            return Adapter.first_image(value[0])
        if isinstance(value, dict):
            return str(value.get("url") or value.get("contentUrl") or "")
        return ""



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


def labelled_dimensions_from_text(text: str) -> Dimensions | None:
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


def dimensions_from_triple(text: str) -> Dimensions | None:
    """A `W x D x H` triple in free text, mapped onto the Furn-App axes."""
    triple = parse_triple(text or "")
    if not triple:
        return None
    width, depth, height = triple
    return Dimensions.from_retailer(width=width, depth=depth, height=height)


#: `SAR 2,495.00`, `2495 SAR`, `﷼ 2,495`. Currency must be present and Saudi —
#: an unlabelled number could be anything, and a price in the wrong currency is
#: worse than no price because it looks usable.
#
#: The amount must *begin* with a digit. Writing it as `[\d.,]+` also matches a
#: lone `.`, which made the sentence-ending period in "…polyurethane foam. SAR
#: 2,495.00" match as the amount — the price then parsed as nothing and the
#: field came back empty for every product whose price followed a full stop.
_CURRENCY = r"SAR|SR|ر\.س|﷼"
_AMOUNT = r"\d[\d,]*(?:\.\d{1,2})?"
#: Latin currency codes need boundaries so `SR` does not match inside a word.
_SAR_RE = re.compile(
    rf"(?<![A-Za-z])(?:{_CURRENCY})(?![A-Za-z])\s*({_AMOUNT})"
    rf"|({_AMOUNT})\s*(?<![A-Za-z])(?:{_CURRENCY})(?![A-Za-z])",
    re.IGNORECASE,
)


def _to_float(raw: Any) -> float | None:
    """Parse a price that may arrive as a float, an int, or `'2,495.00'`."""
    if isinstance(raw, (int, float)) and not isinstance(raw, bool):
        return float(raw)
    if not isinstance(raw, str) or not any(ch.isdigit() for ch in raw):
        return None
    try:
        return float(raw.replace(",", "").strip())
    except ValueError:
        return None


def price_from_json_ld(product: dict[str, Any]) -> float | None:
    """Riyal price from a schema.org `Product`, or None.

    Only accepts an explicitly Saudi currency. A retailer serving several
    markets from one template can leave a foreign `priceCurrency` in place, and
    a number labelled AED sitting in a `price_sar` field is a silent error of
    exactly the kind this pipeline exists to avoid.
    """
    offers = product.get("offers")
    candidates = offers if isinstance(offers, list) else [offers]
    for offer in candidates:
        if not isinstance(offer, dict):
            continue
        currency = str(offer.get("priceCurrency") or offer.get("currency") or "").upper()
        if currency and currency != "SAR":
            continue
        for key in ("price", "lowPrice", "highPrice"):
            value = _to_float(offer.get(key))
            if value and value > 0:
                return value
    return None


def price_from_text(text: str) -> float | None:
    """Riyal price scraped out of visible page text.

    Scans every candidate rather than trusting the first: one unparseable match
    early in the page used to mean the real price further down was never seen.
    """
    for match in _SAR_RE.finditer(text or ""):
        value = _to_float(match.group(1) or match.group(2))
        if value and value > 0:
            return value
    return None


#: Ordered longest-first so "coffee table" is tested before "table".
CATEGORY_RULES: list[tuple[re.Pattern[str], str]] = [
    (re.compile(r"\bcoffee table\b"), "coffee_table"),
    (re.compile(r"\b(side|bedside|end) table\b"), "side_table"),
    (re.compile(r"\bnightstand\b|\bbedside cabinet\b"), "nightstand"),
    (re.compile(r"\bdining table\b|\bextendable table\b"), "dining_table"),
    (re.compile(r"\btv (bench|unit|stand|storage)\b"), "tv_unit"),
    (re.compile(r"\bdesk\b"), "desk"),
    (re.compile(r"\bbookcase\b|\bbook shelf\b"), "bookcase"),
    (re.compile(r"\bshelf unit\b|\bshelving\b|\bwall shelf\b"), "shelving"),
    (re.compile(r"\bwardrobe\b|\bcloset\b"), "wardrobe"),
    (re.compile(r"\bchest of \d+ drawers\b|\b\d+-drawer (chest|dresser)\b|\bdresser\b"), "dresser"),
    (re.compile(r"\bmattress\b"), "mattress"),
    (re.compile(r"\bbed frame\b|\bdivan\b|\bbed\b"), "bed"),
    (re.compile(r"\barmchair\b|\bwing chair\b|\beasy chair\b|\brocking chair\b"), "armchair"),
    (re.compile(r"\bsofa\b|\bcouch\b|\bsectional\b|\bloveseat\b|\bsettee\b"), "sofa"),
    (re.compile(r"\bchair\b|\bstool\b|\bbench\b"), "chair"),
    (re.compile(r"\bcabinet\b|\bsideboard\b|\bstorage\b|\bchest\b"), "storage"),
    (re.compile(r"\brug\b|\bcarpet\b"), "rug"),
    (re.compile(r"\blamp\b|\blight\b|\bpendant\b"), "lighting"),
    (re.compile(r"\btable\b"), "dining_table"),
]


def classify_category(*texts: str) -> str | None:
    """Infer the Furn-App category from product name / type text."""
    blob = " ".join(t for t in texts if t).lower()
    for pattern, category in CATEGORY_RULES:
        if pattern.search(blob):
            return category
    return None
