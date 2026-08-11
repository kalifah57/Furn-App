"""Price and room-category extraction.

Price is the field most likely to be *quietly* wrong rather than absent: a
number is always available somewhere on a retail page, and one from the wrong
currency or the wrong element still looks like a price. So these tests care as
much about what is refused as what is read.
"""

from __future__ import annotations

import pytest

from furn_catalog.adapters.base import price_from_json_ld, price_from_text
from furn_catalog.schema import ROOMS, room_for


class TestPriceFromText:
    @pytest.mark.parametrize(
        "text,expected",
        [
            ("SAR 2,495.00", 2495.0),
            ("2495 SAR", 2495.0),
            ("SR 1,299.50", 1299.5),
            ("﷼ 2,495", 2495.0),
            ("Price: SAR 899", 899.0),
        ],
    )
    def test_reads_riyal_prices(self, text, expected):
        assert price_from_text(text) == expected

    def test_a_price_after_a_full_stop_is_still_found(self):
        """Regression: `[\\d.,]+` matched the sentence-ending period as the
        amount, so the real price right after it was never reached. Every
        product whose price followed prose lost the field silently."""
        text = "Frame: solid pine. Cushion: polyurethane foam. SAR 2,495.00"
        assert price_from_text(text) == 2495.0

    def test_scans_past_an_unparseable_candidate(self):
        assert price_from_text("SAR . then SAR 1,750.00") == 1750.0

    @pytest.mark.parametrize(
        "text",
        [
            "2495",  # no currency at all — could be anything
            "AED 2495",  # a real price, in the wrong country
            "USD 650",
            "",
            "no price here",
        ],
    )
    def test_refuses_anything_not_clearly_riyals(self, text):
        assert price_from_text(text) is None

    def test_does_not_match_a_currency_code_inside_a_word(self):
        """`SR` sits inside plenty of ordinary words."""
        assert price_from_text("MIRROR 120") is None
        assert price_from_text("SRSLY 99") is None


class TestPriceFromJsonLd:
    def test_reads_a_single_offer(self):
        product = {"offers": {"price": "2495.00", "priceCurrency": "SAR"}}
        assert price_from_json_ld(product) == 2495.0

    def test_reads_a_list_of_offers(self):
        product = {"offers": [{"price": 899, "priceCurrency": "SAR"}]}
        assert price_from_json_ld(product) == 899.0

    def test_rejects_a_foreign_currency(self):
        """A number labelled AED in a `price_sar` field is a silent error."""
        product = {"offers": {"price": "2495.00", "priceCurrency": "AED"}}
        assert price_from_json_ld(product) is None

    def test_skips_a_foreign_offer_to_find_the_saudi_one(self):
        product = {
            "offers": [
                {"price": 2650, "priceCurrency": "AED"},
                {"price": 2495, "priceCurrency": "SAR"},
            ]
        }
        assert price_from_json_ld(product) == 2495.0

    def test_falls_back_to_a_price_range(self):
        product = {"offers": {"lowPrice": 1999, "highPrice": 2499, "priceCurrency": "SAR"}}
        assert price_from_json_ld(product) == 1999.0

    @pytest.mark.parametrize(
        "product",
        [{}, {"offers": None}, {"offers": {}}, {"offers": {"price": 0, "priceCurrency": "SAR"}}],
    )
    def test_absent_or_zero_reads_as_no_price(self, product):
        """`0` is not a price; None keeps 'unknown' distinct from 'free'."""
        assert price_from_json_ld(product) is None


class TestRoomCategory:
    @pytest.mark.parametrize(
        "category,room",
        [
            ("sofa", "living_room"),
            ("armchair", "living_room"),
            ("bed", "bedroom"),
            ("wardrobe", "bedroom"),
            ("dining_table", "dining_room"),
            ("desk", "office"),
        ],
    )
    def test_maps_categories_to_rooms(self, category, room):
        assert room_for(category) == room

    def test_every_room_is_a_known_room(self):
        assert room_for("sofa") in ROOMS

    def test_an_unmapped_category_is_explicit_rather_than_guessed(self):
        assert room_for("hammock") == "unassigned"
