"""Saudi Arabia locale enforcement.

Every retailer here runs one storefront per market, and the market is in the
URL path. That makes cross-market leakage easy and quiet: a seed harvested from
`/us/en/`, a listing page that links to `/ae/en/`, a canonical tag that points
at the global site — each yields a page that parses perfectly and describes a
product with a different price, different availability, and sometimes different
dimensions from the one a Riyadh customer can actually buy.

Nothing downstream can detect that. So the rule is enforced in one place and
applied at both ends of the pipeline: URLs are rewritten onto the KSA storefront
before they are fetched, and any record whose link is not a KSA link fails
validation before it can be emitted.

`enforce()` returns None rather than raising for a URL that cannot be mapped —
an off-market link is a candidate to skip, not a crash.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from urllib.parse import urlsplit, urlunsplit

#: The one market this catalogue describes.
COUNTRY = "sa"
LANGUAGE = "en"


@dataclass(frozen=True)
class Storefront:
    """One retailer's Saudi storefront, and how to recognise a foreign one."""

    name: str
    host: str
    #: Path prefix that marks the KSA English storefront, e.g. `/sa/en`.
    prefix: str
    #: Matches any market prefix on this host, so it can be swapped for ours.
    market_re: re.Pattern[str]
    #: Hosts that are the same retailer under a different domain.
    aliases: tuple[str, ...] = ()

    def owns(self, host: str) -> bool:
        host = host.lower().removeprefix("www.")
        return host == self.host.removeprefix("www.") or host in self.aliases


STOREFRONTS: tuple[Storefront, ...] = (
    Storefront(
        name="ikea",
        host="www.ikea.com",
        prefix="/sa/en",
        # IKEA uses /{country}/{lang}/, both two-letter.
        market_re=re.compile(r"^/[a-z]{2}/[a-z]{2}(?=/|$)"),
    ),
    Storefront(
        name="homecentre",
        host="www.homecentre.com",
        prefix="/sa/en",
        market_re=re.compile(r"^/[a-z]{2}/[a-z]{2}(?=/|$)"),
        aliases=("homecentre.com",),
    ),
    Storefront(
        name="abyat",
        host="www.abyat.com",
        prefix="/sa/en",
        market_re=re.compile(r"^/[a-z]{2}/[a-z]{2}(?=/|$)"),
        aliases=("abyat.com",),
    ),
)


class OffMarket(ValueError):
    """A URL belongs to a storefront other than Saudi Arabia."""


def storefront_for(url: str) -> Storefront | None:
    host = urlsplit(url).netloc.lower()
    for store in STOREFRONTS:
        if store.owns(host):
            return store
    return None


def enforce(url: str, *, store: Storefront | None = None) -> str | None:
    """Rewrite `url` onto its retailer's KSA storefront.

    Returns None when the URL belongs to no retailer we know, or is not http(s)
    — both mean "not a candidate", which the callers treat as skip-and-continue.

    A URL already on `/sa/en` comes back unchanged, so this is safe to apply
    repeatedly (discovery, parse, and validation all call it).
    """
    if not url or not url.lower().startswith(("http://", "https://")):
        return None

    parts = urlsplit(url)
    store = store or storefront_for(url)
    if store is None:
        return None

    path = parts.path or "/"
    if store.market_re.match(path):
        path = store.market_re.sub(store.prefix, path, count=1)
    else:
        # No market segment at all (a bare `/p/...` or a root-level link).
        path = store.prefix + ("" if path == "/" else path)

    return urlunsplit(("https", store.host, path, parts.query, parts.fragment))


def is_ksa(url: str) -> bool:
    """True if `url` already points at a known retailer's KSA storefront."""
    store = storefront_for(url)
    if store is None:
        return False
    path = urlsplit(url).path or "/"
    return path == store.prefix or path.startswith(store.prefix + "/")


def require_ksa(url: str) -> str:
    """`enforce`, but for places where an off-market URL is a bug, not a skip."""
    fixed = enforce(url)
    if fixed is None:
        raise OffMarket(f"{url!r} is not a recognised Saudi retailer storefront")
    return fixed


__all__ = [
    "COUNTRY",
    "LANGUAGE",
    "OffMarket",
    "STOREFRONTS",
    "Storefront",
    "enforce",
    "is_ksa",
    "require_ksa",
    "storefront_for",
]
