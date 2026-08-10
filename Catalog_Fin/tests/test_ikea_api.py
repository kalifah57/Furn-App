"""The search-backend decoder, tested against realistic response shapes.

This layer is now the primary source of both the canonical KSA product URL and
the footprint, so its failure mode matters more than most: if `products()`
silently yields nothing, the whole run degrades to the HTML path that already
failed to produce measurements. These tests pin the two things that would break
it — a renamed wrapper key, and a renamed measurement field.

No network and no beautifulsoup4: `ikea_api` decodes plain JSON.
"""

from __future__ import annotations

import json

import pytest

from furn_catalog.ikea_api import ApiProduct, IkeaSearchApi, products

KIVIK = {
    "id": "s49440597",
    "itemNo": "s49440597",
    "name": "KIVIK",
    "typeName": "3-seat sofa",
    "itemMeasureReferenceText": "228x95x83 cm",
    "mainImageUrl": "https://www.ikea.com/sa/en/images/products/kivik__1103001_pe867123_s5.jpg",
    "pipUrl": "https://www.ikea.com/sa/en/p/kivik-3-seat-sofa-tibbleby-beige-grey-s49440597/",
    "colors": [{"name": "Tibbleby beige/grey", "hex": "#c8bfb0"}],
    "price": {"currencyCode": "SAR", "numeral": 2495},
}

BILLY = {
    "id": "20522046",
    "itemNo": "20522046",
    "name": "BILLY",
    "typeName": "Bookcase",
    "itemMeasureReferenceText": "80x28x202 cm",
    "mainImageUrl": "https://www.ikea.com/sa/en/images/products/billy__0625599_pe692385_s5.jpg",
    "pipUrl": "https://www.ikea.com/sa/en/p/billy-bookcase-white-20522046/",
    "colors": [{"name": "white"}],
}


def search_response(*items: dict) -> dict:
    """The nesting ikea.com's search box gets back."""
    return {
        "searchResultPage": {
            "products": {
                "main": {
                    "items": [{"product": item} for item in items],
                    "count": len(items),
                }
            }
        }
    }


class TestDecoding:
    def test_reads_products_out_of_the_search_nesting(self):
        found = list(products(search_response(KIVIK, BILLY)))
        assert [p.item_no for p in found] == ["s49440597", "20522046"]

    def test_carries_the_three_fields_the_page_could_not_give_us(self):
        kivik = next(iter(products(search_response(KIVIK))))
        assert kivik.pip_url.endswith("s49440597/")
        assert kivik.image_url.startswith("https://www.ikea.com/")
        assert kivik.measure_text == "228x95x83 cm"

    def test_maps_the_measure_text_onto_the_furn_app_axes(self):
        """`228x95x83` is IKEA's W x D x H; Furn-App calls depth `length`."""
        kivik = next(iter(products(search_response(KIVIK))))
        assert kivik.dimensions().as_dict() == {
            "length_cm": 95.0,
            "width_cm": 228.0,
            "height_cm": 83.0,
        }

    def test_composes_a_full_product_name(self):
        kivik = next(iter(products(search_response(KIVIK))))
        assert kivik.full_name == "KIVIK 3-seat sofa, Tibbleby beige/grey"

    def test_survives_a_renamed_wrapper(self):
        """The path to the products has moved before; the walk shouldn't care."""
        flat = {"productListPage": {"productWindow": [KIVIK, BILLY]}}
        assert len(list(products(flat))) == 2

    def test_survives_a_renamed_measurement_field(self):
        """Any string on the object holding a `WxDxH cm` is the measurement."""
        renamed = {k: v for k, v in KIVIK.items() if k != "itemMeasureReferenceText"}
        renamed["someNewFieldName"] = "228x95x83 cm"
        found = next(iter(products(search_response(renamed))))
        assert found.dimensions().as_dict()["width_cm"] == 228

    def test_finds_a_measurement_nested_inside_a_sub_object(self):
        """Regression: a live check against the real search endpoint (see
        README) found every product's *direct* string values empty of
        measurements — on a legitimate 'sofa' query, not a bad lookup. A field
        nested one level down (a variant block, a specs sub-object) would look
        exactly like that from the old top-level-only scan."""
        nested = {k: v for k, v in KIVIK.items() if k != "itemMeasureReferenceText"}
        nested["specifications"] = {"packaging": {"note": "228x95x83 cm"}}
        found = next(iter(products(search_response(nested))))
        assert found.dimensions().as_dict()["width_cm"] == 228

    def test_a_genuinely_empty_response_still_yields_no_dimensions(self):
        """The nested scan must not manufacture a match that is not there."""
        bare = {k: v for k, v in KIVIK.items() if k != "itemMeasureReferenceText"}
        bare["unrelated"] = {"note": "some other text with no measurement in it"}
        found = next(iter(products(search_response(bare))))
        assert found.dimensions() is None

    def test_ignores_objects_that_are_not_products(self):
        noise = {
            "filters": [{"id": "colour", "name": "Colour"}],
            "breadcrumb": {"url": "https://www.ikea.com/sa/en/cat/sofas-fu003/"},
        }
        assert list(products(noise)) == []

    def test_deduplicates_repeated_articles(self):
        payload = search_response(KIVIK, KIVIK)
        assert len(list(products(payload))) == 1

    def test_no_dimensions_rather_than_wrong_ones(self):
        """A product with no measurement text yields None, never a guess."""
        bare = {k: v for k, v in KIVIK.items() if k != "itemMeasureReferenceText"}
        assert next(iter(products(search_response(bare)))).dimensions() is None

    def test_rejects_an_implausible_triple(self):
        absurd = dict(KIVIK, itemMeasureReferenceText="2280x950x830 cm")
        assert next(iter(products(search_response(absurd)))).dimensions() is None


class FakeJsonClient:
    """Serves canned JSON for whichever endpoint shape is asked for."""

    def __init__(self, answers: dict[str, object]) -> None:
        self.answers = answers
        self.asked: list[str] = []

    def get_json(self, url: str, *, headers=None, use_cache: bool = True):
        self.asked.append(url)
        for fragment, payload in self.answers.items():
            if fragment in url:
                return payload
        from furn_catalog.http import FetchError

        raise FetchError(f"HTTP 404 for {url}")


class TestEndpointNegotiation:
    def test_falls_through_to_an_endpoint_that_answers(self):
        client = FakeJsonClient({"/search?c=sr": search_response(KIVIK)})
        api = IkeaSearchApi(client)

        assert [p.item_no for p in api.search("sofa")] == ["s49440597"]
        assert len(client.asked) == 3  # tried the two newer shapes first

    def test_remembers_the_working_endpoint(self):
        client = FakeJsonClient({"/search?c=sr": search_response(KIVIK)})
        api = IkeaSearchApi(client)
        api.search("sofa")
        api.search("bed frame")

        # One probe for the second query, not another three.
        assert len(client.asked) == 4

    def test_a_dead_api_degrades_instead_of_raising(self):
        api = IkeaSearchApi(FakeJsonClient({}))
        assert api.search("sofa") == []
        assert api.available is False
        assert api.search("bed frame") == []  # stops trying

    def test_index_collates_across_queries(self):
        client = FakeJsonClient({"search-result-page": search_response(KIVIK, BILLY)})
        api = IkeaSearchApi(client)
        index = api.index(["sofa", "bookcase"])
        assert set(index) == {"s49440597", "20522046"}
        assert isinstance(index["s49440597"], ApiProduct)


if __name__ == "__main__":  # pragma: no cover - offline manual run
    raise SystemExit(pytest.main([__file__, "-q"]))


class FakeSearchApi:
    """Returns a different product set per query, as the real backend does."""

    def __init__(self, results: dict[str, list]) -> None:
        self.results = results
        self.queried: list[str] = []

    def search(self, query: str, *, size: int = 24):
        self.queried.append(query)
        return self.results.get(query, [])


def _product(model: str, kind: str, colour: str, number: int) -> ApiProduct:
    return ApiProduct(
        item_no=f"s{number:08d}",
        name=model,
        type_name=kind,
        measure_text="200x90x80 cm",
        image_url="https://www.ikea.com/sa/en/images/products/x.jpg",
        pip_url=f"https://www.ikea.com/sa/en/p/{model.lower()}-{colour}-s{number:08d}/",
        colour=colour,
    )


class TestDiscoveryBalance:
    """Three consecutive live runs came back ~94% sofas.

    Not because IKEA has nothing else — because discovery drained `sofa`,
    `3-seat sofa` and `corner sofa` in order, and those three returned more
    products than the whole run needed. The catalogue stopped before it ever
    asked about desks or wardrobes.
    """

    def build(self, **overrides):
        from furn_catalog.adapters.ikea import IkeaAdapter

        results = {
            "sofa": [_product("EKTORP", "3-seat sofa", c, i) for i, c in enumerate("abcd", 1)],
            "wardrobe": [_product("PAX", "wardrobe", c, i) for i, c in enumerate("ab", 21)],
            "desk": [_product("MICKE", "desk", c, i) for i, c in enumerate("ab", 31)],
            "dining table": [_product("EKEDALEN", "dining table", "a", 41)],
        }
        adapter = IkeaAdapter.__new__(IkeaAdapter)
        adapter._api = FakeSearchApi(results)
        adapter.max_variants_per_model = overrides.get(
            "max_variants", IkeaAdapter.DEFAULT_MAX_VARIANTS
        )
        return adapter

    def test_interleaves_queries_instead_of_draining_them(self):
        adapter = self.build()
        first_four = [p.name for _, p in zip(range(4), adapter._round_robin())]
        assert len(set(first_four)) == 4, f"one query dominated: {first_four}"

    def test_caps_variants_of_the_same_model(self):
        """Four colours of one EKTORP are one footprint to the solver."""
        adapter = self.build()
        taken = [p for p in adapter._round_robin()]
        ektorps = [p for p in taken[:6] if p.name == "EKTORP"]
        assert len(ektorps) <= 2

    def test_deferred_variants_are_not_discarded(self):
        """A run that would otherwise come up short still gets them, last."""
        adapter = self.build()
        every = list(adapter._round_robin())
        assert len([p for p in every if p.name == "EKTORP"]) == 4
        assert every[-1].name == "EKTORP"

    def test_the_cap_can_be_lifted(self):
        adapter = self.build(max_variants=0)
        first_four = [p.name for _, p in zip(range(4), adapter._round_robin())]
        assert first_four.count("EKTORP") >= 1

    def test_every_query_is_asked(self):
        adapter = self.build()
        list(adapter._round_robin())
        assert set(adapter._api.queried) == set(adapter.SEARCH_QUERIES)
