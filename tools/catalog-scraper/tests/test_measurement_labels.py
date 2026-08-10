"""Bounding-box semantics: which measurement labels may define the box.

The defect this pins: `Armrest width: 3.5 cm` was being read as a sofa's width.
Two things went wrong together, and both are covered here.

1. The free-text parser captured only the bare axis word, throwing the
   qualifier away before anything could reject it — so `Armrest width` and
   `Width` arrived downstream indistinguishable, and first-match-wins gave the
   solver a 3.5cm sofa.
2. The qualifier filter was a blacklist of known prefixes, which never
   contained "armrest". A blacklist is only as good as its last update, and a
   miss here produces a physically impossible record that nothing downstream
   can detect.

The fix is a whitelist: a label defines an axis only if it *is* that axis word,
optionally with a `total`/`overall` prefix or an `including ...` clause that can
only widen the extent. Labels nobody has thought of yet are rejected by
construction, which is the right default when the cost of a wrong number is a
sofa placed through a wall.

The panel texts below reproduce IKEA's label *structure*, which is what is
under test. The values are illustrative, not scraped.
"""

from __future__ import annotations

import pytest

from furn_catalog.adapters.ikea import _from_labelled_text, labelled_pairs_from_text
from furn_catalog.units import (
    classify_label,
    dimensions_from_labelled,
    measurement_sections,
)
from furn_catalog.schema import implausible_extents as implausible_for_category

# A 2-seat sofa: component measurements interleaved with the real box, and the
# armrest listed *first* so first-match-wins would take it.
GLOSTAD_PANEL = (
    "Measurements "
    "Armrest width: 3.5 cm "
    "Width: 132 cm "
    "Depth: 75 cm "
    "Height: 71 cm "
    "Seat width: 118 cm "
    "Seat depth: 54 cm "
    "Seat height: 45 cm "
    "Height under furniture: 8 cm"
)

# A sofa published with both a bare height and an "including back cushions"
# height — the second is the extent that has to fit through a doorway.
SALTMYRAN_PANEL = (
    "Measurements "
    "Width: 163 cm "
    "Depth: 88 cm "
    "Height: 78 cm "
    "Height including back cushions: 84 cm "
    "Armrest height: 56 cm "
    "Height backrest: 52 cm "
    "Seat depth: 56 cm "
    "Compressed packaging depth: 42 cm"
)


class TestLabelWhitelist:
    @pytest.mark.parametrize(
        "label,axis",
        [
            ("Width", "width"),
            ("Depth", "depth"),
            ("Height", "height"),
            ("Length", "depth"),  # beds publish Length for front-to-back
            ("Total width", "width"),
            ("Overall height", "height"),
            ("Height including back cushions", "height"),
            ("Width incl. armrests", "width"),
            ("العرض", "width"),
            ("الارتفاع", "height"),
        ],
    )
    def test_accepts_a_global_axis(self, label, axis):
        assert classify_label(label) == axis

    @pytest.mark.parametrize(
        "label",
        [
            "Armrest width",  # the label that caused the defect
            "Armrest height",
            "Seat width",
            "Seat depth",
            "Seat height",
            "Height backrest",
            "Height under furniture",
            "Free height under furniture",
            "Bed width",
            "Mattress length",
            "Compressed packaging depth",
            "Max load",
            "Drawer depth",
            "Shelf width",
            "Thickness",
            "Package weight",
        ],
    )
    def test_rejects_anything_qualified(self, label):
        assert classify_label(label) is None

    def test_rejects_a_qualifier_nobody_listed(self):
        """The point of a whitelist: labels invented tomorrow fail closed."""
        for invented in ("Plinth width", "Canopy height", "Castor depth"):
            assert classify_label(invented) is None

    def test_strips_a_section_heading(self):
        """Read as flat text, the first label follows the panel's own heading.

        Without stripping it the first — often only — global axis on the page
        reads as `Measurements Width`, is rejected as qualified, and the whole
        product drops.
        """
        assert classify_label("Measurements Width") == "width"
        assert classify_label("Dimensions Height") == "height"
        # ...but a heading does not launder a component measurement.
        assert classify_label("Measurements Armrest width") is None

    def test_a_heading_is_a_boundary_not_just_a_prefix(self):
        """Page text runs on: `... 2-seat sofa Measurements Width: 132 cm`.

        Stripping only a *leading* heading leaves `sofa` sitting in front of the
        axis word, where it reads as a qualifier — so the product loses a width
        it published plainly. The last heading in the label ends the context.
        """
        assert classify_label("sofa Measurements Width") == "width"
        assert classify_label("KIVIK 2-seat sofa Measurements Height") == "height"
        assert classify_label("sofa Measurements Seat depth") is None

    def test_strips_a_unit_carried_over_from_the_previous_measurement(self):
        """`... 54 cm Width: 132 cm` leaves `cm` as the preceding word."""
        assert classify_label("cm Width") == "width"


class TestGlostad:
    def test_takes_the_box_not_the_armrest(self):
        assert _from_labelled_text(GLOSTAD_PANEL).as_dict() == {
            "length_cm": 75.0,
            "width_cm": 132.0,
            "height_cm": 71.0,
        }

    def test_the_armrest_is_seen_and_refused_rather_than_missed(self):
        """It must be parsed as a label and rejected — not simply unmatched,
        which would pass for the wrong reason."""
        pairs = labelled_pairs_from_text(GLOSTAD_PANEL)
        armrest = [k for k in pairs if "armrest" in k.lower()]
        assert armrest, "the armrest line was never parsed at all"
        assert all(classify_label(k) is None for k in armrest)

    def test_seat_depth_never_becomes_the_depth_axis(self):
        assert _from_labelled_text(GLOSTAD_PANEL).length_cm == 75.0


class TestSaltmyran:
    def test_prefers_the_total_height(self):
        """84cm including back cushions is what has to clear a doorway, not 78."""
        assert _from_labelled_text(SALTMYRAN_PANEL).as_dict() == {
            "length_cm": 88.0,
            "width_cm": 163.0,
            "height_cm": 84.0,
        }

    def test_packaging_depth_is_not_the_product_depth(self):
        assert _from_labelled_text(SALTMYRAN_PANEL).length_cm == 88.0

    def test_the_first_label_survives_the_panel_heading(self):
        """Regression: `Measurements Width` used to be rejected, dropping the
        product for want of a width it had published plainly."""
        assert _from_labelled_text(SALTMYRAN_PANEL).width_cm == 163.0


class TestIntegrityGate:
    def test_a_panel_of_only_components_drops_the_record(self):
        """The rule that matters: no substitution. A sofa whose global axes are
        unreadable is dropped, never rebuilt out of its parts."""
        parts_only = (
            "Measurements Armrest width: 3.5 cm Seat width: 118 cm "
            "Seat depth: 54 cm Seat height: 45 cm Height under furniture: 8 cm"
        )
        assert _from_labelled_text(parts_only) is None

    def test_two_of_three_axes_is_still_a_drop(self):
        assert dimensions_from_labelled({"Width": "132 cm", "Height": "71 cm"}) is None

    def test_a_component_cannot_fill_a_missing_axis(self):
        """Depth is absent globally; seat depth must not be promoted into it."""
        assert (
            dimensions_from_labelled(
                {"Width": "132 cm", "Height": "71 cm", "Seat depth": "54 cm"}
            )
            is None
        )

    def test_an_implausible_axis_is_refused_not_shrunk(self):
        assert (
            dimensions_from_labelled(
                {"Width": "5000 cm", "Depth": "75 cm", "Height": "71 cm"}
            )
            is None
        )


#: Transcribed from the live EKTORP 3-seat sofa sidebar (article s39508998),
#: including the Package details block the renderer expands along with
#: everything else. Unlike the panels above, these values are observed.
EKTORP_PANEL = (
    "Product details What's included Measurements "
    "Armrest width: 24 cm "
    "Depth: 88 cm "
    "Height including back cushions: 88 cm "
    "Seat depth: 49 cm "
    "Seat height: 45 cm "
    "Width: 218 cm "
    "Package details Width: 102 cm Height: 25 cm Length: 205 cm Weight: 24.50 kg"
)


class TestEktorpAgainstPackaging:
    """The defect no label rule could have caught.

    IKEA labels packaging with bare `Width:` / `Height:` / `Length:` — the same
    words the product uses. Reading the whole page and taking the largest value
    per axis gave this sofa a depth of 205cm, its carton's length, against a
    real depth of 88cm. Only knowing which *section* a label came from
    distinguishes them.
    """

    def test_takes_the_product_depth_not_the_package_length(self):
        assert _from_labelled_text(EKTORP_PANEL).as_dict() == {
            "length_cm": 88.0,
            "width_cm": 218.0,
            "height_cm": 88.0,
        }

    def test_the_measurements_section_excludes_packaging(self):
        section = measurement_sections(EKTORP_PANEL)[0]
        assert "Depth: 88 cm" in section
        assert "205" not in section
        assert "Package" not in section

    def test_package_width_does_not_beat_product_width(self):
        """102cm is smaller than the real 218cm, so `max` hid this one — it
        would have surfaced the moment a carton was wider than its contents."""
        assert _from_labelled_text(EKTORP_PANEL).width_cm == 218.0

    def test_a_page_with_no_panel_still_stops_short_of_packaging(self):
        """The fallback path keeps the packaging cut even without a heading."""
        no_heading = (
            "Depth: 88 cm Width: 218 cm Height: 88 cm "
            "Package details Length: 205 cm Width: 102 cm Height: 25 cm"
        )
        assert _from_labelled_text(no_heading).as_dict() == {
            "length_cm": 88.0,
            "width_cm": 218.0,
            "height_cm": 88.0,
        }

    def test_no_panel_and_a_stray_word_fails_closed(self):
        """`... sofa Depth: 88 cm` with no heading to bound it.

        `sofa` is lexically indistinguishable from `Armrest`, so accepting it
        would reopen the defect. Dropping the product is the correct cost of
        that guarantee — and real pages carry the heading, so this is the rare
        path, not the common one.
        """
        assert (
            _from_labelled_text("EKTORP 3-seat sofa Depth: 88 cm Width: 218 cm") is None
        )


#: Verbatim from the live ÄPPLARYD 3-seat sofa sidebar (article 70575075).
#: Two packages, each with its own bare-labelled block — and both listing
#: `Length: 221 cm`, which is what the shipped record used as the sofa's depth
#: against a real 93cm.
APPLARYD_PANEL = (
    "Measurements "
    "Armrest height: 72 cm Armrest width: 17 cm Depth: 93 cm "
    "Free height under furniture: 20 cm Height backrest: 70 cm "
    "Height including back cushions: 82 cm Seat depth: 61 cm "
    "Seat height: 47 cm Width: 231 cm "
    "Package details This product comes as 2 packages. "
    "ÄPPLARYD 3-seat sofa Article number 705.750.75 "
    "This product has multiple packages. "
    "Package 1 Width: 94 cm Height: 29 cm Length: 221 cm Weight: 42.05 kg Package(s): 1 "
    "Package 2 Width: 94 cm Height: 24 cm Length: 221 cm Weight: 30.41 kg Package(s): 1"
)


class TestApplarydMultiPackage:
    """A flat-pack shipping as several cartons repeats the bare labels once per
    package, so there is more packaging text than product text on the page."""

    def test_takes_the_product_depth_not_the_carton_length(self):
        assert _from_labelled_text(APPLARYD_PANEL).as_dict() == {
            "length_cm": 93.0,
            "width_cm": 231.0,
            "height_cm": 82.0,
        }

    def test_neither_package_block_reaches_the_parser(self):
        section = measurement_sections(APPLARYD_PANEL)[0]
        assert "221" not in section
        assert "Package" not in section

    def test_every_component_label_here_is_refused(self):
        """This panel carries five: two armrest, two seat, one clearance."""
        for label in (
            "Armrest height",
            "Armrest width",
            "Free height under furniture",
            "Height backrest",
            "Seat depth",
            "Seat height",
        ):
            assert classify_label(label) is None, label

    def test_the_back_cushion_height_still_wins(self):
        """82cm including cushions, not the 70cm backrest it sits above."""
        assert _from_labelled_text(APPLARYD_PANEL).height_cm == 82.0


class TestCategoryFloors:
    """A second, independent gate on the same defect.

    The parser is the fix; this is the check that would have caught it. Two
    catalogues shipped component measurements past a clean validator run,
    because the flat 1–400cm gate cannot see anything wrong with `width_cm:
    3.5` — it is a perfectly plausible number. Only the claim "this is a sofa"
    makes it impossible.
    """

    def test_catches_an_armrest_width_sold_as_a_sofa(self):
        problems = implausible_for_category(
            "sofa", {"width_cm": 3.5, "length_cm": 78.0, "height_cm": 57.0}
        )
        assert any("width_cm=3.5" in p for p in problems)

    def test_catches_a_seat_height_sold_as_a_sofa_height(self):
        problems = implausible_for_category(
            "sofa", {"width_cm": 218.0, "length_cm": 88.0, "height_cm": 43.0}
        )
        assert any("height_cm=43" in p for p in problems)

    def test_passes_a_real_sofa(self):
        assert (
            implausible_for_category(
                "sofa", {"width_cm": 228.0, "length_cm": 95.0, "height_cm": 83.0}
            )
            == []
        )

    @pytest.mark.parametrize(
        "category,spatial",
        [
            ("bookcase", {"width_cm": 80.0, "length_cm": 28.0, "height_cm": 202.0}),
            ("nightstand", {"width_cm": 39.0, "length_cm": 30.0, "height_cm": 55.0}),
            ("coffee_table", {"width_cm": 90.0, "length_cm": 55.0, "height_cm": 45.0}),
            ("bed", {"width_cm": 176.0, "length_cm": 209.0, "height_cm": 100.0}),
            ("chair", {"width_cm": 43.0, "length_cm": 52.0, "height_cm": 91.0}),
        ],
    )
    def test_small_but_legitimate_furniture_is_not_flagged(self, category, spatial):
        """The floors are loose on purpose: a 28cm-deep bookcase is normal, and
        a false alarm that drops real products is its own kind of damage."""
        assert implausible_for_category(category, spatial) == []

    def test_an_unmapped_category_is_not_second_guessed(self):
        """No floor is better than an invented one."""
        assert implausible_for_category("rug", {"width_cm": 2.0}) == []


class TestAssetSlug:
    """`3d_model_url` has to be a legal URL for every product name IKEA uses."""

    def test_folds_a_diacritic_to_ascii(self):
        """`str.isalnum()` is True for `Ä`, so an unfolded slug put a raw
        non-ASCII byte into an https URL: ÄPPLARYD produced
        `.../äpplaryd_3_seat_sofa_70575075.usdz`."""
        from furn_catalog.pipeline import _slug

        slug = _slug("ÄPPLARYD 3-seat sofa - Gunnared black/grey")
        assert slug.isascii()
        assert slug.startswith("applaryd")

    def test_leaves_plain_names_alone(self):
        from furn_catalog.pipeline import _slug

        assert _slug("KIVIK 3-seat sofa") == "kivik_3_seat_sofa"

    def test_never_returns_an_empty_stem(self):
        from furn_catalog.pipeline import _slug

        assert _slug("!!!") == "item"


class TestWriteTimeEnforcement:
    """The floors gate emission, not just the audit.

    A run that emits a 1.2cm-wide dining table and reports "50 emitted" has
    already put the bad record in front of whoever consumes the file. Catching
    it afterwards depends on somebody reading the audit — which is the
    assumption that let three contaminated catalogues ship.
    """

    def _product(self, category, width, length, height):
        from furn_catalog.schema import AestheticFeatures, Product
        from furn_catalog.units import Dimensions

        return Product(
            product_name="TEST item",
            store="IKEA KSA",
            category=category,
            product_link="https://www.ikea.com/sa/en/p/test-s12345678/",
            image_url="https://www.ikea.com/sa/en/images/products/x.jpg",
            model_3d_url="https://api.furn-app.com/assets/models/test_s12345678.usdz",
            dimensions=Dimensions.from_retailer(width=width, depth=length, height=height),
            aesthetics=AestheticFeatures.empty(),
            sku="s12345678",
        )

    def test_a_component_sized_dining_table_cannot_be_emitted(self):
        from furn_catalog.schema import ValidationError

        with pytest.raises(ValidationError, match="implausible extent"):
            self._product("dining_table", width=1.2, length=40.0, height=4.0).validate()

    def test_a_bed_with_a_clearance_height_cannot_be_emitted(self):
        from furn_catalog.schema import ValidationError

        with pytest.raises(ValidationError, match="implausible extent"):
            self._product("bed", width=90.0, length=200.0, height=8.0).validate()

    def test_a_real_product_still_validates(self):
        self._product("dining_table", width=120.0, length=75.0, height=74.0).validate()
        self._product("bed", width=176.0, length=209.0, height=100.0).validate()

    def test_the_drop_reason_names_the_cause(self):
        from furn_catalog.pipeline import _drop_reason
        from furn_catalog.schema import ValidationError

        try:
            self._product("dining_table", width=1.2, length=40.0, height=4.0).validate()
        except ValidationError as exc:
            assert _drop_reason(exc) == "implausible_for_category"
