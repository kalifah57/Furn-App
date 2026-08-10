"""Furn-App catalogue extraction pipeline.

The schema and unit layers are dependency-free on purpose: a consumer that only
wants to read or validate a catalogue should not have to install the scraping
stack. `Pipeline` and the adapters are therefore imported lazily (PEP 562), so
`from furn_catalog import Dimensions` works without beautifulsoup4 present.
"""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from .schema import AestheticFeatures, Product, ValidationError, dump_catalogue
from .units import Dimensions

if TYPE_CHECKING:  # pragma: no cover
    from .pipeline import Pipeline, RunReport

__version__ = "1.0.0"

_LAZY = {"Pipeline": ".pipeline", "RunReport": ".pipeline"}


def __getattr__(name: str) -> Any:
    """Import scraping-only symbols on first use."""
    module_name = _LAZY.get(name)
    if module_name is None:
        raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
    from importlib import import_module

    return getattr(import_module(module_name, __package__), name)


def __dir__() -> list[str]:
    return sorted(__all__)


__all__ = [
    "AestheticFeatures",
    "Dimensions",
    "Pipeline",
    "Product",
    "RunReport",
    "ValidationError",
    "dump_catalogue",
]
