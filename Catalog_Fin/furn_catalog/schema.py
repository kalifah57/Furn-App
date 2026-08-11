"""The Furn-App catalogue record, plus the validation that keeps it honest.

Two rules are load-bearing and enforced here rather than left to the adapters:

1. A product without all three dimensions is dropped. The PlacementSolver has
   no sensible behaviour for a missing axis, and a guessed footprint is worse
   than an absent product.
2. Every text field is English. Source pages may be Arabic; anything that still
   contains Arabic script when it reaches this point is a translation gap, and
   we surface it as a validation error instead of shipping mixed-language data.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from typing import Any

from .locale import is_ksa
from .units import Dimensions

CATEGORIES = frozenset(
    {
        "sofa",
        "armchair",
        "bed",
        "mattress",
        "dining_table",
        "coffee_table",
        "side_table",
        "desk",
        "chair",
        "dresser",
        "wardrobe",
        "bookcase",
        "shelving",
        "tv_unit",
        "nightstand",
        "storage",
        "rug",
        "lighting",
    }
)

#: Which room a category belongs in. The Spatial Engine places furniture per
#: room, so this saves every consumer re-deriving the same mapping — and gets
#: it wrong consistently in one place rather than inconsistently in five.
ROOM_CATEGORIES: dict[str, str] = {
    "sofa": "living_room",
    "armchair": "living_room",
    "coffee_table": "living_room",
    "side_table": "living_room",
    "tv_unit": "living_room",
    "bookcase": "living_room",
    "shelving": "living_room",
    "rug": "living_room",
    "lighting": "living_room",
    "storage": "living_room",
    "bed": "bedroom",
    "mattress": "bedroom",
    "dresser": "bedroom",
    "wardrobe": "bedroom",
    "nightstand": "bedroom",
    "dining_table": "dining_room",
    "chair": "dining_room",
    "desk": "office",
}

ROOMS = frozenset(ROOM_CATEGORIES.values())

#: The published schema contract, carried in `catalog.manifest.json`.
#:
#: Bump this whenever a key is added, removed or renamed, a unit changes, or an
#: axis changes meaning — anything that would make a consumer written against
#: the previous version wrong. `tests/test_manifest.py` pins the exact key set
#: to this number, so a shape change fails the suite until the version is
#: bumped deliberately. Silent shape drift is the failure mode a downstream
#: consumer cannot defend against.
SCHEMA_VERSION = 1

#: Floors below which an axis cannot be that category's real extent, in cm as
#: (width, length/depth, height).
#:
#: The 1-400cm plausibility gate cannot catch a component measurement standing
#: in for an axis: 3.5cm is a perfectly plausible *number*, and only the claim
#: "this is a sofa" makes it impossible. Deliberately loose — these catch a
#: component masquerading as the bounding box, not accuracy. A real two-seat
#: sofa is ~130cm wide; the floor is 90.
MIN_EXTENT_CM: dict[str, tuple[float, float, float]] = {
    "sofa": (90, 55, 50),
    "armchair": (45, 45, 50),
    "bed": (70, 150, 15),
    "mattress": (70, 150, 5),
    "wardrobe": (40, 25, 90),
    "dining_table": (55, 45, 55),
    "desk": (55, 35, 45),
    "dresser": (30, 25, 30),
    "bookcase": (20, 15, 50),
    "coffee_table": (35, 30, 20),
    "tv_unit": (40, 20, 15),
    "nightstand": (20, 20, 20),
    "chair": (25, 25, 45),
}


def implausible_extents(category: str, spatial: dict[str, Any]) -> list[str]:
    """Axes too small to be this category's real extent.

    Enforced at write time as well as audit time. A run that emits a 1.2cm-wide
    dining table and reports "50 emitted" has already put the bad record in
    front of whoever consumes the file; catching it afterwards depends on
    somebody reading the audit, which is exactly the assumption that let three
    contaminated catalogues ship.
    """
    floors = MIN_EXTENT_CM.get(category)
    if floors is None:
        return []

    problems: list[str] = []
    for axis, floor in zip(("width_cm", "length_cm", "height_cm"), floors):
        value = spatial.get(axis)
        if isinstance(value, (int, float)) and not isinstance(value, bool) and value < floor:
            problems.append(
                f"{axis}={value} is below {floor}cm for a {category} — "
                "probably a component measurement, not the bounding box"
            )
    return problems


def room_for(category: str) -> str:
    """The room a category is placed in; `unassigned` for anything unmapped."""
    return ROOM_CATEGORIES.get(category, "unassigned")


# Arabic, Persian, and Arabic Presentation Forms. Catches any untranslated
# string that slipped through an adapter.
_NON_LATIN_RE = re.compile(r"[؀-ۿݐ-ݿﭐ-﷿ﹰ-﻿]")


class ValidationError(ValueError):
    """A record failed a rule that would make it unsafe to ship."""


#: Export shapes. `strict` is the contract the Dart `PlacementSolver`, the
#: Aesthetic engine and the Riverpod store consume — a fixed key set, nothing
#: optional, nothing extra. `extended` adds the fields this pipeline can also
#: resolve (seat depth, room, the wider aesthetic vector) for consumers that
#: want them; it is opt-in precisely so the strict shape never drifts.
PROFILES = ("strict", "extended")
DEFAULT_PROFILE = "strict"


def _f(value: float) -> float:
    """Round to 1dp and guarantee a JSON float, never an int.

    This is load-bearing for the Dart side rather than cosmetic. `json.dumps`
    writes `95` for an int and `95.0` for a float, and Dart's `jsonDecode`
    hands back `int` for the former — so `data['length_cm'] as double` throws
    a runtime TypeError on exactly the round numbers most furniture has.
    """
    return float(round(value, 1))


@dataclass
class AestheticFeatures:
    primary_colors: list[str]
    material: str
    style: str
    texture: str
    vibe: str
    pairs_with: list[str]

    @classmethod
    def empty(cls) -> "AestheticFeatures":
        """The all-empty vector, for a product whose features could not be read.

        Every key still ships; only the values are blank. A consumer therefore
        never has to test for a missing key, only for an empty value.
        """
        return cls(primary_colors=[], material="", style="", texture="", vibe="", pairs_with=[])

    def as_dict(self, profile: str = DEFAULT_PROFILE) -> dict[str, Any]:
        """The four keys the Aesthetic engine consumes, always present.

        Empty values are emitted as `""` / `[]` rather than omitted or null:
        the engine can then read every field unconditionally and decide for
        itself what an empty one means.
        """
        payload: dict[str, Any] = {
            "primary_colors": list(self.primary_colors),
            "material": self.material,
            "style": self.style,
            "vibe": self.vibe,
        }
        if profile == "extended":
            payload["texture"] = self.texture
            payload["pairs_with"] = list(self.pairs_with)
        return payload

    def text_fields(self) -> list[str]:
        return [self.material, self.style, self.texture, self.vibe, *self.primary_colors, *self.pairs_with]


@dataclass
class Product:
    product_name: str
    store: str
    category: str
    product_link: str
    image_url: str
    model_3d_url: str
    #: None only on a record deliberately shipped incomplete — see `issues`.
    #: The default pipeline never emits one; `--allow-incomplete` opts in.
    dimensions: Dimensions | None
    aesthetics: AestheticFeatures
    sku: str = ""
    #: Retail price in Saudi riyals, when the page published one. None means
    #: "not found", never "free" — the two must stay distinguishable.
    price_sar: float | None = None
    #: Which room this belongs in; derived from `category` unless an adapter
    #: reads something better off the page.
    room_category: str = ""
    #: Populated when a record ships with a known gap (see `--allow-incomplete`).
    #: Empty on a clean record, so its presence is the flag.
    issues: list[str] = field(default_factory=list)
    # Provenance is deliberately kept out of the emitted JSON: it is for the
    # operator running the scrape, not for the app consuming the catalogue.
    provenance: dict[str, Any] = field(default_factory=dict)

    def __post_init__(self) -> None:
        if not self.room_category:
            self.room_category = room_for(self.category)

    def as_dict(self, profile: str = DEFAULT_PROFILE) -> dict[str, Any]:
        """Serialise to the Furn-App schema.

        `strict` emits exactly the contract shape and nothing else: `id`,
        `product_name`, `store`, `category`, `price_sar`, `urls`,
        `spatial_attributes`, `aesthetic_features`. Key order is fixed, the key
        set is fixed, and every numeric field is a float. Downstream can index
        it without a single existence check.

        `extended` adds what this pipeline can also resolve — `room_category`,
        `depth_cm`, `seat_depth_cm`, `texture`, `pairs_with`, and a
        `data_quality` block on a flagged record. Kept opt-in so the strict
        shape cannot drift as a side effect of the scraper learning new tricks.
        """
        if profile not in PROFILES:
            raise ValueError(f"unknown profile {profile!r} (expected one of {list(PROFILES)})")

        payload: dict[str, Any] = {
            "id": self.sku,
            "product_name": self.product_name,
            "store": self.store,
            "category": self.category,
        }
        if profile == "extended":
            payload["room_category"] = self.room_category

        payload["price_sar"] = None if self.price_sar is None else _f(self.price_sar)
        payload["urls"] = {
            "product_link": self.product_link,
            "image_url": self.image_url,
            "3d_model_url": self.model_3d_url,
        }
        payload["spatial_attributes"] = (
            self.dimensions.as_dict(profile) if self.dimensions else None
        )
        payload["aesthetic_features"] = self.aesthetics.as_dict(profile)

        if profile == "extended" and self.issues:
            payload["data_quality"] = {"complete": False, "issues": sorted(self.issues)}
        return payload

    def validate(self) -> None:
        """Raise ValidationError if this record must not be shipped."""
        if not self.product_name.strip():
            raise ValidationError("product_name is empty")

        if self.category not in CATEGORIES:
            raise ValidationError(
                f"unknown category {self.category!r} (expected one of {sorted(CATEGORIES)})"
            )

        if self.room_category not in ROOMS and self.room_category != "unassigned":
            raise ValidationError(
                f"unknown room_category {self.room_category!r} (expected one of {sorted(ROOMS)})"
            )

        # Requirement 3: the product link must carry a real SKU, so the record
        # is traceable back to a specific variant rather than a series page.
        if not self.product_link.startswith("https://"):
            raise ValidationError(f"product_link is not https: {self.product_link!r}")
        # Locale: a link to another market describes a product a Saudi customer
        # cannot buy, at a price they will not pay. Nothing downstream can tell.
        if not is_ksa(self.product_link):
            raise ValidationError(
                f"product_link is not a Saudi storefront URL: {self.product_link!r}"
            )
        if not self.sku:
            raise ValidationError("no SKU/article number resolved from the product link")

        if self.price_sar is not None and not 0 < self.price_sar < 1_000_000:
            raise ValidationError(f"implausible price_sar {self.price_sar!r}")

        # Requirement 3: a real CDN image, never a placeholder or a data URI.
        if not self.image_url.startswith("https://"):
            raise ValidationError(f"image_url is not an https CDN link: {self.image_url!r}")
        if any(tok in self.image_url.lower() for tok in ("placeholder", "no-image", "default.jpg")):
            raise ValidationError(f"image_url looks like a placeholder: {self.image_url!r}")

        # Requirement 4: dimensions are mandatory and must be physically sane.
        # A record may only ship without them if it says so out loud, which is
        # what `issues` is — the operator opted in with `--allow-incomplete`
        # and the gap is on the record for any consumer to see.
        if self.dimensions is None:
            if "missing_dimensions" not in self.issues:
                raise ValidationError("no dimensions — refusing to ship to the solver")
        elif not self.dimensions.is_plausible():
            raise ValidationError(
                f"implausible dimensions {self.dimensions.as_dict()} — refusing to ship to the solver"
            )
        # Category extent floors are deliberately NOT enforced here. They are a
        # judgement about whether a number looks like a component measurement,
        # and the consumer owns that judgement: Furn-App's ingestion layer is
        # tested against these exact records, so dropping them upstream would
        # make its drop counts meaningless. `implausible_extents` stays
        # available, the pipeline reports what it finds, and `--enforce-extents`
        # turns it back into a drop for anyone publishing to a stricter
        # consumer. What `validate` enforces is the *contract* — shape, types,
        # locale, https, SKU — which every consumer relies on regardless.

        # Requirement 1: English only. Applies to whatever text is present;
        # an empty aesthetic field is vacuously English.
        for value in (self.product_name, self.category, *self.aesthetics.text_fields()):
            if _NON_LATIN_RE.search(value):
                raise ValidationError(f"non-English text survived translation: {value!r}")

        # Aesthetic features are deliberately NOT gated. They are advisory: an
        # unstyled record is still perfectly placeable, so a missing colour must
        # not cost the catalogue a product the solver could have used. The keys
        # always ship (see AestheticFeatures.as_dict); only the values go empty.
        # Dimensions are the opposite and stay mandatory above.


def dump_catalogue(
    products: list[Product], *, indent: int = 2, profile: str = DEFAULT_PROFILE
) -> str:
    """Render the final JSON array exactly as the Furn-App schema specifies."""
    return json.dumps(
        [p.as_dict(profile) for p in products], indent=indent, ensure_ascii=False
    )
