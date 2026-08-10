"""Retailer adapters."""

from __future__ import annotations

from ..http import HttpClient
from ..render import BrowserRenderer
from .base import Adapter, RawProduct, classify_category
from .generic import AbyatAdapter, HomeCentreAdapter, JsonLdAdapter
from .ikea import IkeaAdapter

ADAPTERS: dict[str, type[Adapter]] = {
    "ikea": IkeaAdapter,
    "homecentre": HomeCentreAdapter,
    "abyat": AbyatAdapter,
}


def build_adapter(
    name: str,
    client: HttpClient,
    seeds: list[str] | None = None,
    renderer: "BrowserRenderer | None" = None,
    max_variants_per_model: int | None = None,
) -> Adapter:
    try:
        cls = ADAPTERS[name]
    except KeyError:
        raise ValueError(
            f"unknown retailer {name!r} (expected one of {sorted(ADAPTERS)})"
        ) from None
    adapter = cls(client, seeds=seeds, renderer=renderer)  # type: ignore[call-arg]
    # Set after construction rather than through every adapter's signature:
    # only the search-driven adapters have a notion of model variants, and the
    # others should not have to grow a parameter they ignore.
    if max_variants_per_model is not None and hasattr(adapter, "max_variants_per_model"):
        adapter.max_variants_per_model = max_variants_per_model
    return adapter


__all__ = [
    "ADAPTERS",
    "Adapter",
    "AbyatAdapter",
    "HomeCentreAdapter",
    "IkeaAdapter",
    "JsonLdAdapter",
    "RawProduct",
    "build_adapter",
    "classify_category",
]
