import pytest

from furn_catalog.units import (
    DimensionError,
    Dimensions,
    classify_label,
    dimensions_from_labelled,
    parse_pair,
    parse_triple,
    to_cm,
)


class TestToCm:
    @pytest.mark.parametrize(
        "raw,expected",
        [
            ("228 cm", 228.0),
            ("228cm", 228.0),
            ("950 mm", 95.0),
            ("1.5 m", 150.0),
            ("1,250 mm", 125.0),
            # Regression: `_NUMBER` used to cap at three digits, so the regex
            # skipped the leading digit and matched `280 mm` out of `2280 mm`
            # — 28cm instead of 228cm. A tenfold error that looks like a
            # perfectly ordinary furniture measurement on the way out.
            ("2280 mm", 228.0),
            ("2280mm", 228.0),
            ("1080 mm", 108.0),
            ("٢٢٨٠ مم", 228.0),
            ('37 3/8 "', pytest.approx(94.9, abs=0.2)),
            ("95", 95.0),  # bare number in an already-cm-labelled field
        ],
    )
    def test_units(self, raw, expected):
        assert to_cm(raw) == expected

    def test_arabic_indic_digits(self):
        """The /sa/ar/ locale and Abyat both serve these; int() rejects them."""
        assert to_cm("٩٥ سم") == 95.0
        assert to_cm("٢٢٨ سم") == 228.0

    @pytest.mark.parametrize("raw", ["", "   ", "no numbers here", None])
    def test_rejects_unparseable(self, raw):
        with pytest.raises(DimensionError):
            to_cm(raw)


class TestDimensions:
    def test_retailer_mapping_matches_furn_app_schema(self):
        """IKEA reports KIVIK as W228 x D95 x H83.

        The Furn-App schema for that product is length 95, width 228, height 83
        — retailer *depth* becomes `length_cm`. Getting this backwards rotates
        every item 90 degrees in the solver, so it is pinned by a test.
        """
        dims = Dimensions.from_retailer(width=228, depth=95, height=83)
        assert dims.as_dict() == {"length_cm": 95.0, "width_cm": 228.0, "height_cm": 83.0}
        # `depth_cm` is the same axis under the retailer's naming, and is
        # kept out of the solver's reach unless explicitly asked for.
        assert dims.as_dict("extended")["depth_cm"] == 95.0

    def test_rounds_integers_cleanly(self):
        dims = Dimensions.from_retailer(width=228.0, depth=95.04, height=83.5)
        assert dims.as_dict() == {"length_cm": 95.0, "width_cm": 228.0, "height_cm": 83.5}

    @pytest.mark.parametrize(
        "width,depth,height,ok",
        [
            (228, 95, 83, True),
            (0.2, 95, 83, False),  # sub-centimetre — a parse error, not furniture
            (228, 95, 900, False),  # taller than a room
            (5000, 95, 83, False),  # a price mistaken for a measurement
        ],
    )
    def test_plausibility_gate(self, width, depth, height, ok):
        assert Dimensions.from_retailer(width=width, depth=depth, height=height).is_plausible() is ok


class TestTriples:
    def test_parses_ikea_title_triple(self):
        """IKEA puts WxDxH straight in the title on most locales."""
        assert parse_triple("KOPPANG chest of 3 drawers, white, 90x46x83 cm") == (90.0, 46.0, 83.0)

    def test_handles_unicode_multiplication_sign(self):
        assert parse_triple("172 × 44 × 83 cm") == (172.0, 44.0, 83.0)

    def test_converts_units_in_triple(self):
        assert parse_triple("900x460x830 mm") == (90.0, 46.0, 83.0)
        assert parse_triple("2280x950x830 mm") == (228.0, 95.0, 83.0)

    def test_returns_none_without_a_triple(self):
        assert parse_triple("KIVIK 3-seat sofa") is None

    def test_pair_declines_a_triple(self):
        """A pair parser must not silently eat the first two of three axes."""
        assert parse_pair("90x46x83 cm") is None
        assert parse_pair("105x50 cm") == (105.0, 50.0)


class TestLabels:
    @pytest.mark.parametrize(
        "label,axis",
        [
            ("Width", "width"),
            ("Depth", "depth"),
            ("Height", "height"),
            ("Length", "depth"),
            ("العرض", "width"),
            ("الارتفاع", "height"),
        ],
    )
    def test_classifies_axes(self, label, axis):
        assert classify_label(label) == axis

    @pytest.mark.parametrize("label", ["Seat depth", "Mattress length", "Max load", "Seat height"])
    def test_rejects_sub_measurements(self, label):
        """`seat depth` on a sofa is ~60cm against a real depth of ~95cm.

        Using it would let the solver place a sofa 35cm too close to the wall,
        so part-measurements must never resolve to an axis.
        """
        assert classify_label(label) is None

    def test_builds_dimensions_from_table(self):
        """Seat depth is carried, never mistaken for the front-to-back axis.

        Both facts matter and they pull in opposite directions: the Aesthetic
        engine wants the seat depth, and the solver must never see it in place
        of the real 95cm depth.
        """
        dims = dimensions_from_labelled(
            {"Width": "228 cm", "Depth": "95 cm", "Height": "83 cm", "Seat depth": "60 cm"}
        )
        assert dims is not None
        assert dims.as_dict() == {"length_cm": 95.0, "width_cm": 228.0, "height_cm": 83.0}
        assert dims.as_dict("extended") == {
            "length_cm": 95.0,
            "width_cm": 228.0,
            "height_cm": 83.0,
            "depth_cm": 95.0,
            "seat_depth_cm": 60.0,
        }

    def test_seat_depth_alone_is_not_a_footprint(self):
        assert dimensions_from_labelled({"Seat depth": "60 cm"}) is None

    def test_partial_table_yields_nothing(self):
        """A partial footprint is unusable; the product must be dropped."""
        assert dimensions_from_labelled({"Width": "228 cm", "Height": "83 cm"}) is None
