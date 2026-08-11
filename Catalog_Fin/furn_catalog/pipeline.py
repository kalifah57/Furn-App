"""Orchestration: discover -> parse -> enrich -> validate -> emit.

The pipeline's contract is that anything it emits is safe to feed straight to
the PlacementSolver. That means every drop reason is counted and reportable:
a run that yields 38 of 50 requested items tells you exactly why the other 12
fell out, rather than silently returning a short list.
"""

from __future__ import annotations

import logging
import unicodedata
from collections import Counter
from dataclasses import dataclass, field
from typing import Iterable

from .adapters import Adapter, RawProduct
from .aesthetics import RuleBasedExtractor, VisionExtractor
from .schema import AestheticFeatures, Product, ValidationError, implausible_extents

log = logging.getLogger(__name__)

DEFAULT_MODEL_TEMPLATE = "https://api.furn-app.com/assets/models/{slug}_{sku}.usdz"


@dataclass
class RunReport:
    requested: int = 0
    seen: int = 0
    emitted: int = 0
    #: Pages re-fetched through the browser after a static miss, and how many
    #: of those retries produced a footprint. The ratio is the honest measure
    #: of whether the browser path is worth its runtime on this retailer.
    retried: int = 0
    recovered: int = 0
    incomplete: int = 0
    #: Emitted records whose axes look like a component measurement rather than
    #: the bounding box. Reported, not dropped — see Pipeline.enforce_extents.
    suspect_extents: int = 0
    drops: Counter[str] = field(default_factory=Counter)
    dropped_examples: dict[str, str] = field(default_factory=dict)

    def record_drop(self, reason: str, detail: str) -> None:
        self.drops[reason] += 1
        self.dropped_examples.setdefault(reason, detail)

    def render(self) -> str:
        lines = [
            "Run report",
            "----------",
            f"  requested : {self.requested}",
            f"  visited   : {self.seen}",
            f"  emitted   : {self.emitted}",
        ]
        if self.retried:
            lines.append(
                f"  rendered  : {self.retried} retried in-browser, {self.recovered} recovered"
            )
        if self.incomplete:
            lines.append(f"  flagged   : {self.incomplete} shipped without dimensions")
        if self.suspect_extents:
            lines.append(
                f"  suspect   : {self.suspect_extents} emitted with a component-sized axis "
                "(published raw; the consumer drops these)"
            )
        if self.drops:
            lines.append("  dropped   :")
            for reason, count in self.drops.most_common():
                example = self.dropped_examples.get(reason, "")
                lines.append(f"      {count:>4}  {reason}")
                if example:
                    lines.append(f"            e.g. {example}")
        return "\n".join(lines)


def _slug(name: str) -> str:
    """A filesystem- and URL-safe stem for the 3D asset filename.

    Folded to ASCII first. `str.isalnum()` is True for `Ä`, so an unfolded slug
    put a raw non-ASCII byte straight into an https URL — ÄPPLARYD produced
    `.../äpplaryd_3_seat_sofa_70575075.usdz`, which needs percent-encoding to be
    a legal URL and will not survive every object store or CDN path unchanged.
    NFKD splits the letter from its diacritic so the diacritic can be dropped,
    leaving `applaryd`.
    """
    folded = unicodedata.normalize("NFKD", name)
    ascii_only = "".join(ch for ch in folded if not unicodedata.combining(ch))
    cleaned = "".join(
        ch.lower() if ch.isalnum() and ch.isascii() else "_" for ch in ascii_only
    )
    while "__" in cleaned:
        cleaned = cleaned.replace("__", "_")
    return cleaned.strip("_")[:60] or "item"


class Pipeline:
    def __init__(
        self,
        adapter: Adapter,
        *,
        extractor: RuleBasedExtractor | VisionExtractor | None = None,
        model_url_template: str = DEFAULT_MODEL_TEMPLATE,
        allow_incomplete: bool = False,
        require_price: bool = False,
        render_always: bool = False,
        enforce_extents: bool = False,
    ) -> None:
        self.adapter = adapter
        self.extractor = extractor or RuleBasedExtractor()
        self.model_url_template = model_url_template
        #: Ship dimensionless products with a `data_quality` flag instead of
        #: dropping them. Off by default: the solver cannot place a product with
        #: no footprint, so a flagged record is only useful to a consumer that
        #: has agreed to look at the flag.
        self.allow_incomplete = allow_incomplete
        #: Drop products with no resolvable price, for consumers that type
        #: `price_sar` as non-nullable. Off by default: a missing price costs
        #: nothing spatially, and inventing `0.0` would read as "free".
        self.require_price = require_price
        #: Open the measurements panel on every product rather than only where
        #: the static parse came back short. Slower, but the panel is the
        #: authoritative source — a static page can carry a plausible-looking
        #: measurement that is not the bounding box.
        self.render_always = render_always
        #: Drop records whose axes are too small for their category, instead of
        #: only counting them. Off by default: this repo publishes raw, and the
        #: consumer's ingestion layer is tested against exactly these records —
        #: dropping them here would make its own drop counts meaningless.
        self.enforce_extents = enforce_extents

    def run(
        self,
        *,
        limit: int,
        oversample: float = 4.0,
        exclude_skus: set[str] | None = None,
    ) -> tuple[list[Product], RunReport]:
        """Collect up to `limit` validated products.

        `oversample` widens discovery because a meaningful share of candidates
        drop out — not stocked in KSA, no published dimensions, uncategorisable.
        Visiting only `limit` URLs would reliably under-deliver.

        `exclude_skus` carries articles already emitted by an earlier run, so a
        top-up pass extends the catalogue instead of repeating it.
        """
        report = RunReport(requested=limit)
        products: list[Product] = []
        seen_skus: set[str] = set(exclude_skus or ())

        # Already-emitted articles still get discovered and then dropped as
        # duplicates, so widen the sweep by however many we are skipping.
        candidates = self.adapter.discover(int((limit + len(seen_skus)) * oversample))

        # Pull lazily and check the quota *before* asking for the next URL.
        # Iterating normally and breaking inside the body asks for one URL too
        # many, and discovery is not free: that one extra request can make the
        # adapter crawl a whole set of listing pages to produce a candidate
        # nothing will ever look at.
        while len(products) < limit:
            try:
                url = next(candidates)
            except StopIteration:
                break
            report.seen += 1

            render_first = self.render_always and self.adapter.renderer is not None
            if render_first:
                report.retried += 1

            try:
                raw = self.adapter.parse(url, render=render_first)
            except Exception as exc:  # noqa: BLE001 - one bad page must not end the run
                log.warning("parse failed for %s: %s", url, exc)
                report.record_drop("parse_error", f"{url} ({exc})")
                continue

            if raw is None:
                report.record_drop("not_a_product_page", url)
                continue

            if raw.sku in seen_skus:
                report.record_drop("duplicate_sku", f"{raw.sku} ({url})")
                continue

            # Retry before dropping. IKEA keeps measurements behind a control
            # that only a browser opens, so a static miss is not yet a verdict —
            # but rendering costs seconds per page, so it is spent only on the
            # pages that actually came back short.
            if raw.dimensions is not None and render_first:
                report.recovered += 1

            if raw.dimensions is None and not render_first and self.adapter.renderer is not None:
                report.retried += 1
                log.debug("re-fetching %s with the browser for measurements", url)
                try:
                    retried = self.adapter.parse(url, render=True)
                except Exception as exc:  # noqa: BLE001 - a failed retry is a drop
                    log.debug("render retry failed for %s: %s", url, exc)
                else:
                    if retried is not None and retried.dimensions is not None:
                        raw = retried
                        report.recovered += 1

            # Requirement 4: no dimensions, no product. Enforced before the
            # (potentially paid) enrichment call so we never spend on a record
            # that cannot ship.
            if raw.dimensions is None and not self.allow_incomplete:
                report.record_drop("no_dimensions", f"{raw.product_name} ({url})")
                continue

            if self.require_price and raw.price_sar is None:
                report.record_drop("no_price", f"{raw.product_name} ({url})")
                continue

            product = self._build(raw)
            try:
                product.validate()
            except ValidationError as exc:
                report.record_drop(_drop_reason(exc), f"{raw.product_name}: {exc}")
                continue

            extent_problems = (
                implausible_extents(product.category, product.dimensions.as_dict())
                if product.dimensions is not None
                else []
            )
            if extent_problems and self.enforce_extents:
                report.record_drop(
                    "implausible_for_category", f"{raw.product_name}: {extent_problems[0]}"
                )
                continue
            if extent_problems:
                report.suspect_extents += 1
                log.info("suspect extent kept (publishing raw): %s", extent_problems[0])

            seen_skus.add(raw.sku)
            products.append(product)
            report.emitted += 1
            if product.issues:
                report.incomplete += 1
            log.info("[%d/%d] %s", len(products), limit, product.product_name)

        return products, report

    def _build(self, raw: RawProduct) -> Product:
        # An extractor that yields nothing must still produce the full key set,
        # empty — a record with no readable style is shippable, one with no
        # footprint is not.
        aesthetics = self.extractor.extract(raw.signals) or AestheticFeatures.empty()
        model_url = self.model_url_template.format(
            slug=_slug(raw.product_name), sku=raw.sku, category=raw.category
        )
        issues = [] if raw.dimensions is not None else ["missing_dimensions"]
        return Product(
            product_name=raw.product_name,
            store=self.adapter.store,
            category=raw.category,
            product_link=raw.product_link,
            image_url=raw.image_url,
            model_3d_url=model_url,
            dimensions=raw.dimensions,
            aesthetics=aesthetics,
            sku=raw.sku,
            price_sar=raw.price_sar,
            issues=issues,
            provenance={"extractor": self.extractor.name, **raw.notes},
        )


def _drop_reason(exc: ValidationError) -> str:
    message = str(exc)
    if "implausible extent for category" in message:
        return "implausible_for_category"
    if "Saudi storefront" in message:
        return "off_market_link"
    if "price_sar" in message:
        return "bad_price"
    if "image_url" in message:
        return "bad_image_url"
    if "dimensions" in message:
        return "implausible_dimensions"
    if "non-English" in message:
        return "untranslated_text"
    if "SKU" in message:
        return "missing_sku"
    if "category" in message:
        return "bad_category"
    return "validation_failed"


def merge(runs: Iterable[tuple[list[Product], RunReport]]) -> tuple[list[Product], RunReport]:
    """Fold several per-retailer runs into one catalogue and one report."""
    combined: list[Product] = []
    total = RunReport()
    for products, report in runs:
        combined.extend(products)
        total.requested += report.requested
        total.seen += report.seen
        total.emitted += report.emitted
        total.retried += report.retried
        total.recovered += report.recovered
        total.incomplete += report.incomplete
        total.suspect_extents += report.suspect_extents
        total.drops.update(report.drops)
        for reason, example in report.dropped_examples.items():
            total.dropped_examples.setdefault(reason, example)
    return combined, total
