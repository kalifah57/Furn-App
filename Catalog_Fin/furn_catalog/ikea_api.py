"""IKEA's public search backend.

The first live run of this pipeline failed in two ways that both trace back to
the same assumption — that a product page is the only place the facts live:

* 47 candidates 404'd. Seed slugs carry the market they were harvested from
  (`kivik-sofa-tibbleby-beige-gray-s39440593`), and IKEA KSA does **not**
  resolve a product by its trailing article number when the slug disagrees. It
  returns 404. The article number is global; the slug is not.
* 54 pages parsed cleanly for name and image but yielded no measurements. The
  dimensions are not in the server-rendered HTML — not in the measurement
  block, not in the page text, not anywhere a selector can reach.

`sik.search.blue.cdtapps.com` is the backend ikea.com's own search box calls.
It answers with, per product, the canonical `pipUrl` for the requested market,
the CDN `mainImageUrl`, and `itemMeasureReferenceText` — the `228x95x83 cm`
triple. That is exactly the three fields the catalogue could not otherwise get,
from one request per query instead of one per product.

Response shapes here are not contractual, so nothing below indexes into a fixed
path. `products()` walks the decoded JSON and picks out any object that looks
like a product, which survives IKEA renaming a wrapper key.
"""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass
from typing import Any, Iterable, Iterator
from urllib.parse import quote_plus

from .http import FetchError, HttpClient
from .units import Dimensions, parse_triple

log = logging.getLogger(__name__)

SEARCH_HOST = "https://sik.search.blue.cdtapps.com"

#: Tried in order; the first that yields products is remembered for the run.
#: IKEA has shipped all of these shapes, and which one a market answers on is
#: not worth guessing at from here.
_ENDPOINTS = (
    "{host}/{country}/{lang}/search-result-page?q={q}&size={size}&types=PRODUCT",
    "{host}/{country}/{lang}/search-result-page?q={q}&size={size}",
    "{host}/{country}/{lang}/search?c=sr&v=20240110&q={q}&size={size}&types=PRODUCT",
)

# The API is called exactly as ikea.com's own search box calls it; these headers
# are what make it answer with JSON rather than a CORS rejection.
_HEADERS = {
    "Accept": "application/json",
    "Origin": "https://www.ikea.com",
    "Referer": "https://www.ikea.com/",
}

_ARTICLE_RE = re.compile(r"(s?\d{8})", re.IGNORECASE)

# Keys IKEA has used for the WxDxH string. Checked before falling back to
# scanning the object's other strings for a triple.
_MEASURE_KEYS = (
    "itemmeasurereferencetext",
    "measuretext",
    "measurementtext",
    "itemmeasure",
    "measure",
)
_IMAGE_KEYS = ("mainimageurl", "imageurl", "contextualimageurl", "image")
_NAME_KEYS = ("name", "productname", "title")
_TYPE_KEYS = ("typename", "typenameonline", "producttype", "description")


@dataclass(frozen=True)
class ApiProduct:
    """One product as the search backend describes it."""

    item_no: str
    name: str
    type_name: str
    measure_text: str
    image_url: str
    pip_url: str
    colour: str
    price_sar: float | None = None

    @property
    def full_name(self) -> str:
        """`KIVIK 3-seat sofa, Tibbleby beige/grey` from the split fields."""
        parts = [p for p in (self.name, self.type_name) if p]
        title = " ".join(parts)
        return f"{title}, {self.colour}" if self.colour else title

    def dimensions(self) -> Dimensions | None:
        """Parse `itemMeasureReferenceText` into a footprint.

        IKEA writes the triple width-first (`228x95x83 cm` for a sofa that is
        228 wide, 95 deep, 83 tall), which is the order `from_retailer` expects.
        Anything that does not parse to three plausible axes is discarded rather
        than half-used.
        """
        triple = parse_triple(self.measure_text)
        if not triple:
            return None
        width, depth, height = triple
        candidate = Dimensions.from_retailer(width=width, depth=depth, height=height)
        return candidate if candidate.is_plausible() else None


class IkeaSearchApi:
    """Thin, defensive client over the search backend."""

    def __init__(self, client: HttpClient, *, country: str = "sa", lang: str = "en") -> None:
        self.client = client
        self.country = country
        self.lang = lang
        self._endpoint: str | None = None
        self.available = True

    def search(self, query: str, *, size: int = 24) -> list[ApiProduct]:
        """Products matching `query`, or an empty list if the API is unusable.

        A failure here is never fatal: the adapter still has the seed list and
        the HTML listing crawl. It does mean losing the measurement backfill,
        so it is logged at warning level the first time.
        """
        if not self.available:
            return []

        templates = (self._endpoint,) if self._endpoint else _ENDPOINTS
        last_error: Exception | None = None

        for template in templates:
            url = template.format(  # type: ignore[union-attr]
                host=SEARCH_HOST,
                country=self.country,
                lang=self.lang,
                q=quote_plus(query),
                size=size,
            )
            try:
                payload = self.client.get_json(url, headers=_HEADERS)
            except FetchError as exc:
                last_error = exc
                continue

            found = list(products(payload))
            if found:
                if self._endpoint is None:
                    log.info("ikea search API responding on %s", template)
                self._endpoint = template
                return found
            last_error = FetchError(f"no products in response from {url}")

        if self._endpoint is None:
            log.warning(
                "ikea search API unavailable (%s); falling back to seeds and listing pages. "
                "Measurements will come from page markup only.",
                last_error,
            )
            self.available = False
        return []

    def raw(self, query: str, *, size: int = 2) -> Any:
        """The decoded JSON response verbatim, for inspecting a shape this
        client does not yet parse correctly. Not used by the pipeline itself —
        `python -m furn_catalog.diagnose --raw <query>` is the entry point.
        """
        templates = (self._endpoint,) if self._endpoint else _ENDPOINTS
        for template in templates:
            url = template.format(
                host=SEARCH_HOST,
                country=self.country,
                lang=self.lang,
                q=quote_plus(query),
                size=size,
            )
            try:
                return self.client.get_json(url, headers=_HEADERS)
            except FetchError:
                continue
        return None

    def index(self, queries: Iterable[str], *, size: int = 24) -> dict[str, ApiProduct]:
        """Run several queries and collate the results by article number."""
        found: dict[str, ApiProduct] = {}
        for query in queries:
            for product in self.search(query, size=size):
                found.setdefault(product.item_no, product)
        return found


# ------------------------------------------------------------------- decoding


def products(payload: Any) -> Iterator[ApiProduct]:
    """Yield every product-shaped object anywhere in a decoded response.

    Deliberately structure-agnostic. `searchResultPage.products.main.items[]`
    is today's path and `productListPage.productWindow[]` is another, but both
    have moved before; what stays stable is that a product object carries a
    `pipUrl` pointing at `/p/`. Walking for that is more durable than encoding
    a path that will be wrong again in a year.
    """
    seen: set[str] = set()
    for node in _walk(payload):
        product = _product_from(node)
        if product and product.item_no not in seen:
            seen.add(product.item_no)
            yield product


def _walk(node: Any) -> Iterator[dict[str, Any]]:
    if isinstance(node, dict):
        yield node
        for value in node.values():
            yield from _walk(value)
    elif isinstance(node, list):
        for value in node:
            yield from _walk(value)


def _product_from(node: dict[str, Any]) -> ApiProduct | None:
    lowered = {str(k).lower(): v for k, v in node.items()}

    pip_url = _first_string(lowered, ("pipurl", "url", "producturl"))
    if not pip_url or "/p/" not in pip_url:
        return None

    item_no = _first_string(lowered, ("itemno", "id", "sku", "identifier"))
    item_no = _clean_article(item_no) or _clean_article(pip_url)
    if not item_no:
        return None

    return ApiProduct(
        item_no=item_no,
        name=_first_string(lowered, _NAME_KEYS),
        type_name=_first_string(lowered, _TYPE_KEYS),
        measure_text=_measure_text(lowered),
        image_url=_image_url(lowered),
        pip_url=pip_url,
        colour=_colour(lowered),
        price_sar=_price(lowered),
    )


def _price(node: dict[str, Any]) -> float | None:
    """Riyal price from the API's price object, if it is denominated in SAR.

    The search backend answers per market, so a KSA query returns SAR — but it
    says so explicitly, and a price carried under the wrong currency is worse
    than none, so an explicit non-SAR currency is discarded rather than trusted.
    """
    price = node.get("price")
    if isinstance(price, dict):
        currency = str(price.get("currencyCode") or price.get("currency") or "").upper()
        if currency and currency != "SAR":
            return None
        for key in ("numeral", "value", "amount", "price"):
            value = price.get(key)
            if isinstance(value, (int, float)) and not isinstance(value, bool) and value > 0:
                return float(value)
    if isinstance(price, (int, float)) and not isinstance(price, bool) and price > 0:
        return float(price)
    return None


def _first_string(node: dict[str, Any], keys: tuple[str, ...]) -> str:
    for key in keys:
        value = node.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return ""


def _clean_article(text: str) -> str:
    """The trailing `s79482824` / `20522046` token, lowercased."""
    if not text:
        return ""
    matches = _ARTICLE_RE.findall(text)
    return matches[-1].lower() if matches else ""


def _measure_text(node: dict[str, Any]) -> str:
    explicit = _first_string(node, _MEASURE_KEYS)
    if explicit and parse_triple(explicit):
        return explicit

    # The key was renamed, or the triple lives in a nested object — a variant
    # block, a specifications sub-object — rather than a direct field. A live
    # check against the real search-result-page endpoint (see README) came
    # back with every product's *direct* string values empty of measurements,
    # which is exactly what a one-level-deeper field would look like from
    # here. So the scan walks the whole object now, not just its own values.
    for value in _all_strings(node):
        if parse_triple(value):
            return value
    return explicit


def _all_strings(node: Any) -> Iterator[str]:
    """Every string value anywhere under `node`, however deeply nested."""
    if isinstance(node, str):
        yield node
    elif isinstance(node, dict):
        for value in node.values():
            yield from _all_strings(value)
    elif isinstance(node, list):
        for value in node:
            yield from _all_strings(value)


def _image_url(node: dict[str, Any]) -> str:
    for key in _IMAGE_KEYS:
        value = node.get(key)
        if isinstance(value, str) and value.startswith("https://"):
            return value
        if isinstance(value, dict):
            nested = _first_string(
                {str(k).lower(): v for k, v in value.items()}, ("url", "src", "href")
            )
            if nested.startswith("https://"):
                return nested
    return ""


def _colour(node: dict[str, Any]) -> str:
    colours = node.get("colors") or node.get("colours")
    if isinstance(colours, list):
        names = [
            c.get("name")
            for c in colours
            if isinstance(c, dict) and isinstance(c.get("name"), str)
        ]
        if names:
            return ", ".join(n for n in names if n)
    return _first_string({str(k).lower(): v for k, v in node.items()}, ("color", "colour"))


__all__ = ["ApiProduct", "IkeaSearchApi", "SEARCH_HOST", "products"]
