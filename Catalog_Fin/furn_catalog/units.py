"""Dimension parsing and normalisation to centimetres.

Retailers express measurements in a dozen shapes: `95 cm`, `95cm`, `950 mm`,
`0.95 m`, `37 3/8 "`, and — on the Arabic locales — `٩٥ سم`. The Spatial Engine
needs one canonical form, so every extractor funnels through here.
"""

from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass

# Arabic-Indic and Extended Arabic-Indic digits, mapped to ASCII. IKEA's `/sa/ar/`
# pages and Abyat both serve these, and int() rejects them outright.
_ARABIC_DIGITS = str.maketrans("٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹", "01234567890123456789")

_TO_CM = {
    "cm": 1.0,
    "سم": 1.0,
    "mm": 0.1,
    "مم": 0.1,
    "m": 100.0,
    "م": 100.0,
    "in": 2.54,
    '"': 2.54,
    "inch": 2.54,
    "inches": 2.54,
    "بوصة": 2.54,
}

# `95`, `95.5`, `1,250` (thousands separator), or a vulgar fraction like `37 3/8`.
#
# The comma-grouped form is tried first so `1,250` is consumed whole. The plain
# form then allows up to five digits: capping it at three silently mangled every
# millimetre measurement of 1000mm or more, because the regex would skip the
# leading digit and match the *tail* — `2280 mm` came back as 280mm, i.e. 28cm
# instead of 228cm. That survives the plausibility gate untouched, which makes
# it exactly the kind of quiet 10x error the Spatial Engine cannot detect.
_NUMBER = (
    r"\d{1,3}(?:,\d{3})+(?:\.\d+)?"  # 1,250 / 1,250.5
    r"|\d{1,5}(?:\.\d+)?(?:\s*\d+/\d+)?"  # 95 / 95.5 / 2280 / 37 3/8
    r"|\d+/\d+"  # 3/8
)
_UNIT = r"cm|mm|m|in(?:ch(?:es)?)?|\"|سم|مم|م|بوصة"

# `(?<!\d)` stops a match starting mid-number, the other half of the same trap.
#
# `(?![a-z])` rather than `\b`: a trailing `"` is a non-word character, so `\b`
# fails at end-of-string and an inch measurement would silently fall through to
# the centimetre default — a 2.54x error reaching the solver. This form still
# stops `m` from matching inside `metres`, and keeps `mm` ahead of `m`.
_MEASUREMENT_RE = re.compile(rf"(?<!\d)({_NUMBER})\s*({_UNIT})(?![a-z])", re.IGNORECASE)

# "80x28x202 cm" / "90 x 46 x 83" — IKEA puts this straight in <title> on many
# locales, which makes it a cheap and surprisingly reliable fallback.
_TRIPLE_RE = re.compile(
    rf"(?<!\d)({_NUMBER})\s*[x×]\s*({_NUMBER})\s*[x×]\s*({_NUMBER})\s*({_UNIT})?", re.IGNORECASE
)
_PAIR_RE = re.compile(rf"(?<!\d)({_NUMBER})\s*[x×]\s*({_NUMBER})\s*({_UNIT})?", re.IGNORECASE)


class DimensionError(ValueError):
    """Raised when a measurement string cannot be resolved to centimetres."""


@dataclass(frozen=True)
class Dimensions:
    """A furniture footprint in centimetres.

    The field names follow the Furn-App schema, which is *not* the same
    convention retailers use. See `from_retailer` for the mapping.
    """

    length_cm: float  # front-to-back (retailer "depth")
    width_cm: float  # side-to-side  (retailer "width")
    height_cm: float  # floor-to-top  (retailer "height")
    #: Seat depth, where the retailer publishes one. Never part of the bounding
    #: box — it describes the cushion, not the footprint — but the Aesthetic
    #: engine uses it to reason about seating comfort, so it is carried
    #: alongside rather than discarded.
    seat_depth_cm: float | None = None

    @classmethod
    def from_retailer(
        cls,
        *,
        width: float,
        depth: float,
        height: float,
        seat_depth: float | None = None,
    ) -> "Dimensions":
        """Map retailer width/depth/height onto the Furn-App length/width/height.

        Retailers publish Width (side-to-side), Depth (front-to-back), Height.
        Furn-App's PlacementSolver calls the front-to-back axis `length`, so
        retailer *depth* becomes `length_cm` and retailer *width* stays
        `width_cm`. Getting this backwards silently rotates every item 90° in
        the room layout, so it lives in one place rather than at each call site.
        """
        return cls(length_cm=depth, width_cm=width, height_cm=height, seat_depth_cm=seat_depth)

    def with_seat_depth(self, seat_depth: float | None) -> "Dimensions":
        """A copy carrying a seat depth, ignoring implausible values."""
        if seat_depth is None or not 1.0 <= seat_depth <= 200.0:
            return self
        return Dimensions(self.length_cm, self.width_cm, self.height_cm, seat_depth)

    def as_dict(self, profile: str = "strict") -> dict[str, float]:
        """The `spatial_attributes` block.

        `strict` is the deterministic collision box and nothing else: exactly
        three axes, all floats. The PlacementSolver reads these and only these,
        so anything advisory is kept out of reach by construction rather than
        by the solver remembering to ignore it.

        `extended` adds `depth_cm` — the same axis as `length_cm` under the
        retailer's naming, so a human cross-checking against IKEA's own listing
        cannot pick the wrong one — and `seat_depth_cm` where published. Seat
        depth is never part of the box: on a sofa it runs ~60cm against a real
        depth of ~95cm, and placing to it would put the sofa 35cm through the
        wall.
        """
        payload: dict[str, float] = {
            "length_cm": _round(self.length_cm),
            "width_cm": _round(self.width_cm),
            "height_cm": _round(self.height_cm),
        }
        if profile == "extended":
            payload["depth_cm"] = _round(self.length_cm)
            if self.seat_depth_cm is not None:
                payload["seat_depth_cm"] = _round(self.seat_depth_cm)
        return payload

    def is_plausible(self) -> bool:
        """Reject values no real piece of furniture has.

        A parser that mistakes a price for a depth produces a number that is
        syntactically fine and physically absurd; this is the last gate before
        a bad footprint reaches the solver. Only the bounding box is gated —
        `seat_depth_cm` is advisory and never placed against a wall.
        """
        return all(1.0 <= v <= 400.0 for v in (self.length_cm, self.width_cm, self.height_cm))


def _round(value: float) -> float:
    """Round to 1dp, always as a float — never an int.

    Type safety for the Dart consumer, not cosmetics. `json.dumps` writes `95`
    for a Python int and `95.0` for a float; Dart's `jsonDecode` then yields
    `int` for the former, and `data['length_cm'] as double` throws a runtime
    TypeError. Since most furniture measures a whole number of centimetres,
    returning ints here would crash the PlacementSolver on the common case and
    work only on the odd 83.5cm chair.
    """
    return float(round(value, 1))


def normalise_digits(text: str) -> str:
    """Fold Arabic-Indic digits to ASCII and normalise unicode fractions."""
    text = unicodedata.normalize("NFKC", text)
    return text.translate(_ARABIC_DIGITS)


def _parse_number(raw: str) -> float:
    """Parse `95`, `1,250`, or the mixed fraction `37 3/8`."""
    raw = raw.replace(",", "").strip()
    if "/" in raw:
        parts = raw.split()
        whole = 0.0
        frac = parts[-1]
        if len(parts) == 2:
            whole = float(parts[0])
        num, _, den = frac.partition("/")
        return whole + float(num) / float(den)
    return float(raw)


def to_cm(raw: str, *, default_unit: str = "cm") -> float:
    """Convert a single measurement string to centimetres.

    >>> to_cm("228 cm")
    228.0
    >>> to_cm("950 mm")
    95.0
    >>> to_cm("٩٥ سم")
    95.0
    """
    if raw is None:
        raise DimensionError("no measurement given")
    text = normalise_digits(str(raw)).strip()
    if not text:
        raise DimensionError("empty measurement")

    match = _MEASUREMENT_RE.search(text)
    if match:
        value = _parse_number(match.group(1))
        unit = match.group(2).lower()
    else:
        # A bare number in a field already labelled "Depth (cm)".
        bare = re.search(_NUMBER, text)
        if not bare:
            raise DimensionError(f"no number found in {raw!r}")
        value = _parse_number(bare.group(0))
        unit = default_unit

    factor = _TO_CM.get(unit)
    if factor is None:
        raise DimensionError(f"unknown unit {unit!r} in {raw!r}")
    return value * factor


def parse_triple(text: str) -> tuple[float, float, float] | None:
    """Extract a `W x D x H` triple in cm from free text, if one is present.

    IKEA titles carry these verbatim (`KOPPANG chest of 3 drawers, white,
    90x46x83 cm`), which gives a usable footprint even when the structured
    measurement block fails to parse.
    """
    if not text:
        return None
    normalised = normalise_digits(text)
    match = _TRIPLE_RE.search(normalised)
    if not match:
        return None
    unit = (match.group(4) or "cm").lower()
    factor = _TO_CM.get(unit, 1.0)
    try:
        return tuple(_parse_number(match.group(i)) * factor for i in (1, 2, 3))  # type: ignore[return-value]
    except (ValueError, ZeroDivisionError):
        return None


def parse_pair(text: str) -> tuple[float, float] | None:
    """Extract a `W x D` pair in cm (desks and tables often omit height here)."""
    if not text:
        return None
    normalised = normalise_digits(text)
    # Reject strings that are really triples — the caller wants parse_triple.
    if _TRIPLE_RE.search(normalised):
        return None
    match = _PAIR_RE.search(normalised)
    if not match:
        return None
    unit = (match.group(3) or "cm").lower()
    factor = _TO_CM.get(unit, 1.0)
    try:
        return (
            _parse_number(match.group(1)) * factor,
            _parse_number(match.group(2)) * factor,
        )
    except (ValueError, ZeroDivisionError):
        return None


# Label vocabularies, English and Arabic. `length` maps to the front-to-back
# axis: on a bed, IKEA publishes Length where a sofa gets Depth.
_AXIS_BY_WORD = {
    "width": "width",
    "عرض": "width",
    "العرض": "width",
    "depth": "depth",
    "length": "depth",
    "عمق": "depth",
    "العمق": "depth",
    "طول": "depth",
    "الطول": "depth",
    "height": "height",
    "ارتفاع": "height",
    "الارتفاع": "height",
}

#: Leading words that still describe the whole object rather than a part.
_GLOBAL_PREFIXES = {"total", "overall", "إجمالي", "الإجمالي"}

#: A trailing clause opening with one of these can only *widen* the extent
#: ("Height including back cushions"), so it still describes the bounding box.
#: Anything else after the axis word narrows or relocates it ("Height under
#: furniture" is floor clearance, not the object) and is rejected.
_EXTENT_PREFIXES = {"including", "incl", "inc", "with", "شامل", "بما"}

#: Units and separators that can end up in front of a label when measurements
#: are read out of free text — the unit of the *previous* measurement becomes
#: the word preceding this one ("... 54 cm Width: 132 cm"). Dropped before the
#: whitelist runs, so they are never mistaken for a disqualifying qualifier.
_NOISE_TOKENS = {"cm", "mm", "m", "kg", "g", "l", "-", "–", "|", "·", "•", ",", "/"}

#: Section headings that sit immediately before the first label when a panel is
#: read as flat text ("Measurements Width: 132 cm"). Without stripping these the
#: first — and often only — global axis on the page is read as `Measurements
#: Width`, rejected as a qualified label, and the whole product dropped. A
#: closed set of our own headings, not a guess about retailer vocabulary.
_SECTION_HEADINGS = {
    "measurements",
    "measurement",
    "dimensions",
    "dimension",
    "size",
    "sizes",
    "القياسات",
    "المقاسات",
    "الأبعاد",
}

#: Headings that open a measurements panel — where a bounding box may be read.
_MEASUREMENT_MARKERS = ("measurements", "dimensions", "القياسات", "المقاسات", "الأبعاد")

#: Headings that end it. `Package details` is the one that matters: IKEA labels
#: packaging with bare `Width:` / `Height:` / `Length:`, indistinguishable from
#: the product's own axes, and a flat carton is often longer than the sofa is
#: deep. Reading the whole page and taking the largest value per axis gave an
#: EKTORP a depth of 205cm — its package length — against a real depth of 88cm.
#: Nothing about the *label* can catch that; only knowing which section it came
#: from can.
_SECTION_STOP_MARKERS = (
    "package details",
    "packaging",
    "package",
    "product details",
    "what's included",
    "whats included",
    "accessories",
    "materials and care",
    "material and care",
    "care instructions",
    "assembly",
    "delivery",
    "reviews",
    "ratings",
    "similar products",
    "related products",
    "you might also like",
    "sustainability",
    "good to know",
    "buying guide",
    "تفاصيل الطرد",
    "تفاصيل المنتج",
    "التغليف",
)

_NUMERIC_RE = re.compile(r"^[\d.,/]+$")


def measurement_sections(text: str) -> list[str]:
    """Slices of `text` that belong to a measurements panel, in page order.

    Each runs from a measurements heading to the next section heading, so
    packaging figures — which carry the same bare axis labels as the product —
    are outside the slice rather than competing with it.

    Returns every candidate rather than guessing which is the real panel: a
    page carries the word twice (the collapsed accordion label and the opened
    panel's own heading), and the caller can simply take the first slice that
    yields a complete footprint.
    """
    if not text:
        return []

    lowered = text.lower()
    starts: set[int] = set()
    for marker in _MEASUREMENT_MARKERS:
        cursor = 0
        while True:
            found = lowered.find(marker, cursor)
            if found == -1:
                break
            starts.add(found)
            cursor = found + len(marker)

    sections: list[str] = []
    for start in sorted(starts):
        end = len(text)
        for stop in _SECTION_STOP_MARKERS:
            found = lowered.find(stop, start + 1)
            if found != -1:
                end = min(end, found)
        section = text[start:end].strip()
        if section:
            sections.append(section)
    return sections


def before_other_sections(text: str) -> str:
    """`text` truncated at the first non-measurement section heading.

    The fallback for a page with no recognisable measurements heading: still
    better than reading to the end of the document, because the packaging block
    is the single most dangerous thing downstream of it.
    """
    if not text:
        return ""
    lowered = text.lower()
    end = len(text)
    for stop in _SECTION_STOP_MARKERS:
        found = lowered.find(stop)
        if found != -1:
            end = min(end, found)
    return text[:end]


def classify_label(label: str) -> str | None:
    """Map a measurement label onto `width`, `depth`, or `height`.

    A **whitelist**, deliberately. The previous version blacklisted known
    sub-measurement prefixes, which fails the moment IKEA publishes one nobody
    listed — and it did: `Armrest width: 3.5 cm` sailed through and became a
    sofa's width. A blacklist is only ever as good as its last update, and the
    cost of a miss here is a physically impossible record reaching a
    deterministic solver.

    So a label qualifies only if it is exactly an axis word, optionally with a
    `total`/`overall` prefix, optionally followed by an `including ...` clause.
    Everything else — `Armrest width`, `Seat depth`, `Height under furniture`,
    `Bed width`, `Compressed packaging depth` — is rejected by construction,
    including the ones not yet invented.
    """
    axis, _ = classify_label_detail(label)
    return axis


def classify_label_detail(label: str) -> tuple[str | None, bool]:
    """`(axis, is_extent_variant)` for a measurement label.

    `is_extent_variant` marks an `including ...` form, which describes the same
    axis at its widest published extent.
    """
    text = normalise_digits(label).strip().lower()
    if not text:
        return None, False

    tokens = [t.strip(".,:") for t in re.split(r"[\s::]+", text.replace("：", " "))]
    tokens = [t for t in tokens if t]

    # A section heading is a boundary: everything before it belongs to the page,
    # not to this label ("... sofa Measurements Width" -> "Width"). Taking the
    # *last* heading matters — stripping only a leading one leaves whatever
    # preceded it in front of the axis word, where it reads as a qualifier and
    # costs the product its width.
    for index in range(len(tokens) - 1, -1, -1):
        if tokens[index] in _SECTION_HEADINGS:
            tokens = tokens[index + 1 :]
            break

    # Strip leading units/numbers picked up from an adjacent measurement.
    while tokens and (tokens[0] in _NOISE_TOKENS or _NUMERIC_RE.match(tokens[0])):
        tokens.pop(0)
    if tokens and tokens[0] in _GLOBAL_PREFIXES:
        tokens.pop(0)
    if not tokens:
        return None, False

    axis = _AXIS_BY_WORD.get(tokens[0])
    if axis is None:
        # The axis word is not the head of the label, so whatever precedes it
        # qualifies it — a part, not the whole.
        return None, False

    rest = tokens[1:]
    if not rest:
        return axis, False
    if rest[0] in _EXTENT_PREFIXES:
        return axis, True
    return None, False


#: Seat depth is deliberately *not* an axis — see `classify_label`. It is
#: collected separately because the Aesthetic engine wants it even though the
#: solver must never see it.
_SEAT_DEPTH_LABELS = ("seat depth", "عمق المقعد", "عمق الجلسة")


def seat_depth_from_labelled(pairs: dict[str, str]) -> float | None:
    """Pull a seat depth out of a measurement table, if one is published."""
    for label, value in pairs.items():
        text = normalise_digits(label).strip().lower()
        if any(key in text for key in _SEAT_DEPTH_LABELS):
            try:
                return to_cm(value)
            except DimensionError:
                continue
    return None


def dimensions_from_labelled(pairs: dict[str, str]) -> Dimensions | None:
    """Build Dimensions from a `{label: value}` measurement table.

    Returns None unless all three axes resolve from labels that pass
    `classify_label` — the Spatial Engine cannot use a partial footprint, and a
    component measurement standing in for a missing axis is worse than no
    product at all. Seat depth rides along without ever entering the box.

    Where a retailer publishes both a bare axis and an `including ...` variant,
    the larger wins: the bounding box is the extent that actually has to fit
    through a doorway, so `Height including back cushions` beats `Height`.
    """
    axes: dict[str, float] = {}
    for label, value in pairs.items():
        axis = classify_label(label)
        if axis is None:
            continue
        try:
            centimetres = to_cm(value)
        except DimensionError:
            continue
        # A single absurd axis is a parse error, not a smaller product; drop the
        # value rather than let it define the box.
        if not 1.0 <= centimetres <= 400.0:
            continue
        if centimetres > axes.get(axis, 0.0):
            axes[axis] = centimetres

    if {"width", "depth", "height"} <= axes.keys():
        return Dimensions.from_retailer(
            width=axes["width"],
            depth=axes["depth"],
            height=axes["height"],
            seat_depth=seat_depth_from_labelled(pairs),
        )
    return None
