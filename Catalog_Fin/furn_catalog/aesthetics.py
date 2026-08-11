"""Deriving the aesthetic feature vector that feeds the Aesthetic AI Engine.

Two backends, same output shape:

* `RuleBasedExtractor` — deterministic, offline, auditable. Maps the retailer's
  own colour/material vocabulary onto a normalised English feature set. This is
  the default: it never invents a fact and it costs nothing to re-run.
* `VisionExtractor` — sends the real product image to Claude and asks for the
  same fields. This is the "act as the AI vision" path; it sees the product
  rather than inferring from its name, at the cost of an API call per item.

Both emit English only, regardless of the source locale.
"""

from __future__ import annotations

import json
import logging
import os
from dataclasses import dataclass

from .schema import AestheticFeatures

log = logging.getLogger(__name__)

# ---------------------------------------------------------------- vocabularies

# Retailer colour token -> normalised English colour. Arabic tokens are included
# because Abyat and the IKEA `/sa/ar/` pages leak them into product names even
# on the English locale.
COLOUR_LEXICON: dict[str, str] = {
    "anthracite": "Dark Grey",
    "dark grey": "Dark Grey",
    "dark gray": "Dark Grey",
    "grey": "Grey",
    "gray": "Grey",
    "light grey": "Light Grey",
    "light gray": "Light Grey",
    "black-brown": "Black-Brown",
    "black brown": "Black-Brown",
    "black": "Black",
    "white stained": "White-Stained Oak",
    "white": "White",
    "off-white": "Off-White",
    "beige": "Beige",
    "light beige": "Light Beige",
    "dark beige": "Dark Beige",
    "brown": "Brown",
    "dark brown": "Dark Brown",
    "walnut": "Walnut Brown",
    "oak": "Oak",
    "birch": "Birch",
    "pine": "Natural Pine",
    "ash": "Ash",
    "blue": "Blue",
    "dark blue": "Dark Blue",
    "navy": "Navy",
    "turquoise": "Turquoise",
    "green": "Green",
    "dark green": "Dark Green",
    "red": "Red",
    "yellow": "Yellow",
    "gold": "Gold",
    "silver": "Silver",
    "chrome": "Chrome",
    "terracotta": "Terracotta",
    "rust": "Rust",
    "cream": "Cream",
    "ivory": "Ivory",
    "charcoal": "Charcoal",
    "أسود": "Black",
    "أبيض": "White",
    "رمادي": "Grey",
    "بني": "Brown",
    "بيج": "Beige",
    "أزرق": "Blue",
    "أخضر": "Green",
}

MATERIAL_LEXICON: dict[str, str] = {
    "polyester": "Polyester fabric",
    "cotton": "Cotton fabric",
    "linen": "Linen-blend fabric",
    "velvet": "Velvet",
    "chenille": "Chenille fabric",
    "boucle": "Bouclé fabric",
    "leather": "Leather",
    "coated fabric": "Coated fabric",
    "faux leather": "Faux leather",
    "solid pine": "Solid pine",
    "solid birch": "Solid birch",
    "solid oak": "Solid oak",
    "solid beech": "Solid beech",
    "solid wood": "Solid wood",
    "oak veneer": "Oak veneer",
    "ash veneer": "Ash veneer",
    "birch veneer": "Birch veneer",
    "walnut veneer": "Walnut veneer",
    "veneer": "Wood veneer",
    "particleboard": "Particleboard",
    "fibreboard": "Fibreboard",
    "fiberboard": "Fibreboard",
    "mdf": "MDF",
    "plywood": "Plywood",
    "rattan": "Rattan",
    "bamboo": "Bamboo",
    "steel": "Powder-coated steel",
    "metal": "Metal",
    "aluminium": "Aluminium",
    "aluminum": "Aluminium",
    "glass": "Tempered glass",
    "marble": "Marble",
    "stone": "Stone",
    "foam": "Polyurethane foam",
    "memory foam": "Memory foam",
    "pocket spring": "Pocket springs",
}

# Material -> tactile description. The Aesthetic Engine matches on texture
# separately from material, so a coarse mapping is enough.
TEXTURE_BY_MATERIAL: dict[str, str] = {
    "Polyester fabric": "Slightly textured woven",
    "Cotton fabric": "Soft matte weave",
    "Linen-blend fabric": "Natural slubbed weave",
    "Velvet": "Plush, light-catching pile",
    "Chenille fabric": "Soft ribbed pile",
    "Bouclé fabric": "Looped, nubby",
    "Leather": "Smooth semi-gloss grain",
    "Faux leather": "Smooth matte grain",
    "Coated fabric": "Smooth wipeable",
    "Solid pine": "Visible open grain",
    "Solid birch": "Fine even grain",
    "Solid oak": "Pronounced open grain",
    "Solid beech": "Fine tight grain",
    "Solid wood": "Natural wood grain",
    "Oak veneer": "Smooth grain-printed",
    "Ash veneer": "Smooth linear grain",
    "Birch veneer": "Smooth fine grain",
    "Walnut veneer": "Smooth dark grain",
    "Wood veneer": "Smooth grain surface",
    "Particleboard": "Smooth matte laminate",
    "Fibreboard": "Smooth matte laminate",
    "MDF": "Smooth painted",
    "Plywood": "Smooth layered edge",
    "Rattan": "Woven natural",
    "Bamboo": "Fine linear grain",
    "Powder-coated steel": "Matte powder-coated",
    "Metal": "Smooth metallic",
    "Aluminium": "Brushed metallic",
    "Tempered glass": "Smooth reflective",
    "Marble": "Cool polished stone",
    "Stone": "Matte stone",
}

# Category -> what the Spatial/Aesthetic pairing should suggest alongside it.
PAIRS_BY_CATEGORY: dict[str, list[str]] = {
    "sofa": ["Coffee tables", "Floor lighting", "Textured rugs"],
    "armchair": ["Side tables", "Reading lamps", "Throw blankets"],
    "bed": ["Nightstands", "Wardrobes", "Bedside lighting"],
    "dining_table": ["Dining chairs", "Pendant lighting", "Sideboards"],
    "coffee_table": ["Sofas", "Area rugs", "Storage baskets"],
    "side_table": ["Armchairs", "Table lamps", "Sofas"],
    "desk": ["Task chairs", "Desk lighting", "Shelving units"],
    "chair": ["Dining tables", "Desks", "Console tables"],
    "dresser": ["Beds", "Mirrors", "Table lamps"],
    "wardrobe": ["Beds", "Dressers", "Full-length mirrors"],
    "bookcase": ["Armchairs", "Floor lighting", "Desks"],
    "shelving": ["Desks", "Storage boxes", "Sofas"],
    "tv_unit": ["Sofas", "Media storage", "Floor lighting"],
    "nightstand": ["Beds", "Table lamps", "Dressers"],
    "storage": ["Wardrobes", "Shelving units", "Storage boxes"],
    "mattress": ["Bed frames", "Bedding sets", "Nightstands"],
}

_DARK = {"Black", "Dark Grey", "Charcoal", "Black-Brown", "Dark Brown", "Navy", "Dark Blue", "Dark Green"}
_WARM_WOOD = {"Oak", "Walnut Brown", "Natural Pine", "Birch", "Ash", "Brown", "Terracotta", "Rust"}
_NEUTRAL_LIGHT = {"White", "Off-White", "Beige", "Light Beige", "Cream", "Ivory", "Light Grey"}


@dataclass
class SourceSignals:
    """Everything the extractors get to reason over, straight from the page."""

    product_name: str
    category: str
    colour_text: str = ""
    material_text: str = ""
    description: str = ""
    image_url: str = ""

    def haystack(self) -> str:
        return " ".join(
            (self.product_name, self.colour_text, self.material_text, self.description)
        ).lower()


class RuleBasedExtractor:
    """Deterministic feature derivation from the retailer's own vocabulary."""

    name = "rules"

    def extract(self, signals: SourceSignals) -> AestheticFeatures:
        haystack = signals.haystack()
        colours = self._colours(haystack)
        materials = self._materials(haystack)
        primary_material = materials[0] if materials else "Composite wood"

        return AestheticFeatures(
            primary_colors=colours,
            material=", ".join(materials) if materials else primary_material,
            style=self._style(signals.category, colours, materials),
            texture=TEXTURE_BY_MATERIAL.get(primary_material, "Smooth matte"),
            vibe=self._vibe(colours, materials),
            pairs_with=PAIRS_BY_CATEGORY.get(signals.category, ["Area rugs", "Floor lighting"]),
        )

    def _colours(self, haystack: str) -> list[str]:
        found: list[str] = []
        # Longest token first so "dark grey" wins over "grey" and
        # "black-brown" is never split into "black".
        for token in sorted(COLOUR_LEXICON, key=len, reverse=True):
            if token in haystack:
                colour = COLOUR_LEXICON[token]
                if colour not in found and not any(colour in f for f in found):
                    found.append(colour)
            if len(found) >= 3:
                break
        return found or ["Neutral"]

    def _materials(self, haystack: str) -> list[str]:
        found: list[str] = []
        for token in sorted(MATERIAL_LEXICON, key=len, reverse=True):
            if token in haystack:
                material = MATERIAL_LEXICON[token]
                if material not in found:
                    found.append(material)
            if len(found) >= 3:
                break
        return found

    def _style(self, category: str, colours: list[str], materials: list[str]) -> str:
        material_blob = " ".join(materials).lower()
        colour_set = set(colours)

        if "rattan" in material_blob or "bamboo" in material_blob:
            return "Natural Coastal"
        if "marble" in material_blob or "velvet" in material_blob:
            return "Modern Luxe"
        if "solid" in material_blob and colour_set & _WARM_WOOD:
            return "Warm Scandinavian"
        if colour_set & _DARK and ("steel" in material_blob or "metal" in material_blob):
            return "Industrial Modern"
        if colour_set & _DARK:
            return "Contemporary Dark"
        if colour_set & _NEUTRAL_LIGHT:
            return "Minimalist Scandinavian"
        return "Contemporary Casual"

    def _vibe(self, colours: list[str], materials: list[str]) -> str:
        colour_set = set(colours)
        material_blob = " ".join(materials).lower()
        traits: list[str] = []

        if colour_set & _DARK:
            traits += ["Grounded", "masculine"]
        elif colour_set & _NEUTRAL_LIGHT:
            traits += ["Airy", "calm"]
        else:
            traits += ["Warm", "inviting"]

        if any(t in material_blob for t in ("fabric", "velvet", "bouclé", "chenille")):
            traits.append("cosy")
        if any(t in material_blob for t in ("steel", "metal", "glass")):
            traits.append("clean-lined")
        if "solid" in material_blob:
            traits.append("sturdy")

        traits.append("practical")
        return ", ".join(dict.fromkeys(traits))


# ---------------------------------------------------------------- vision path

_VISION_SCHEMA = {
    "type": "object",
    "properties": {
        "primary_colors": {
            "type": "array",
            "items": {"type": "string"},
            "description": "1-3 dominant colours in plain English, e.g. 'Dark Grey'.",
        },
        "material": {
            "type": "string",
            "description": "Visible materials in English, comma-separated.",
        },
        "style": {
            "type": "string",
            "description": "Design style, 1-3 words, e.g. 'Warm Scandinavian'.",
        },
        "texture": {
            "type": "string",
            "description": "Tactile surface quality, e.g. 'Plush, light-catching pile'.",
        },
        "vibe": {
            "type": "string",
            "description": "3-5 comma-separated adjectives describing the mood.",
        },
        "pairs_with": {
            "type": "array",
            "items": {"type": "string"},
            "description": "3 furniture categories that complement this piece.",
        },
    },
    "required": ["primary_colors", "material", "style", "texture", "vibe", "pairs_with"],
    "additionalProperties": False,
}

_VISION_SYSTEM = """You are an interior-design feature extractor for a furniture catalogue.

You are shown one product image plus the retailer's own text. Describe only what \
is visibly true of the product itself — ignore staging props, background walls, \
and other furniture in the shot.

Answer strictly in English even when the supplied text is Arabic. Use concrete \
colour names an interior designer would use ("Dark Grey", not "dark-ish"). \
Never invent a material you cannot see or read in the supplied text."""


class VisionExtractor:
    """Ask Claude to read the actual product photograph.

    This is the literal reading of "act as the AI vision": the model sees the
    image the shopper sees. Falls back to the rule-based extractor on any API
    failure so one bad call never sinks a catalogue run.
    """

    name = "vision"

    def __init__(
        self,
        *,
        model: str = "claude-opus-5",
        effort: str = "medium",
        fallback: RuleBasedExtractor | None = None,
    ) -> None:
        try:
            import anthropic
        except ImportError as exc:  # pragma: no cover - dependency guard
            raise RuntimeError(
                "vision enrichment needs the anthropic SDK: pip install anthropic"
            ) from exc

        if not (os.environ.get("ANTHROPIC_API_KEY") or os.environ.get("ANTHROPIC_AUTH_TOKEN")):
            log.info("no ANTHROPIC_API_KEY set; relying on SDK credential resolution")

        self._client = anthropic.Anthropic()
        self._model = model
        self._effort = effort
        self._fallback = fallback or RuleBasedExtractor()

    def extract(self, signals: SourceSignals) -> AestheticFeatures:
        if not signals.image_url:
            return self._fallback.extract(signals)

        prompt = (
            f"Product name: {signals.product_name}\n"
            f"Category: {signals.category}\n"
            f"Retailer colour text: {signals.colour_text or 'n/a'}\n"
            f"Retailer material text: {signals.material_text or 'n/a'}\n\n"
            "Extract the aesthetic features for this product."
        )

        try:
            response = self._client.messages.create(
                model=self._model,
                max_tokens=16000,
                system=_VISION_SYSTEM,
                thinking={"type": "adaptive"},
                output_config={
                    "effort": self._effort,
                    "format": {"type": "json_schema", "schema": _VISION_SCHEMA},
                },
                messages=[
                    {
                        "role": "user",
                        "content": [
                            {"type": "image", "source": {"type": "url", "url": signals.image_url}},
                            {"type": "text", "text": prompt},
                        ],
                    }
                ],
            )
        except Exception as exc:  # noqa: BLE001 - never let enrichment sink the run
            log.warning("vision enrichment failed for %s (%s); using rules", signals.product_name, exc)
            return self._fallback.extract(signals)

        if response.stop_reason == "refusal":
            log.warning("vision enrichment refused for %s; using rules", signals.product_name)
            return self._fallback.extract(signals)

        text = next((b.text for b in response.content if b.type == "text"), "")
        try:
            data = json.loads(text)
        except json.JSONDecodeError:
            log.warning("vision enrichment returned unparseable JSON; using rules")
            return self._fallback.extract(signals)

        return AestheticFeatures(
            primary_colors=list(data["primary_colors"])[:3],
            material=str(data["material"]),
            style=str(data["style"]),
            texture=str(data["texture"]),
            vibe=str(data["vibe"]),
            pairs_with=list(data["pairs_with"])[:4],
        )


def build_extractor(mode: str) -> RuleBasedExtractor | VisionExtractor:
    if mode == "rules":
        return RuleBasedExtractor()
    if mode == "vision":
        return VisionExtractor()
    raise ValueError(f"unknown aesthetic mode {mode!r} (expected 'rules' or 'vision')")
