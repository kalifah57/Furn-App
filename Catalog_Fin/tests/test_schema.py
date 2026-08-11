import json

import pytest

from furn_catalog.schema import AestheticFeatures, Product, ValidationError, dump_catalogue
from furn_catalog.units import Dimensions


def make_product(**overrides) -> Product:
    defaults = dict(
        product_name="KIVIK - 3-seat sofa (Anthracite)",
        store="IKEA KSA",
        category="sofa",
        product_link="https://www.ikea.com/sa/en/p/kivik-3-seat-sofa-tresund-anthracite-s79482824/",
        image_url="https://www.ikea.com/sa/en/images/products/kivik__1103001_pe867123_s5.jpg",
        model_3d_url="https://api.furn-app.com/assets/models/kivik_3seat_s79482824.usdz",
        dimensions=Dimensions.from_retailer(width=228, depth=95, height=83),
        aesthetics=AestheticFeatures(
            primary_colors=["Dark Grey"],
            material="Polyester fabric, memory foam",
            style="Contemporary Casual",
            texture="Slightly textured",
            vibe="Cozy, masculine, practical",
            pairs_with=["Dark wood tables", "Geometric rugs"],
        ),
        sku="s79482824",
    )
    defaults.update(overrides)
    return Product(**defaults)


class TestStrictSchema:
    """The contract the Dart PlacementSolver and Riverpod store consume.

    Exact key set, exact nesting, float numerics. These assertions are the
    contract itself — if one has to change, a downstream model has to change
    with it, so they are written to fail loudly rather than accommodate.
    """

    def test_emits_exactly_the_contract_keys(self):
        payload = make_product().as_dict()
        assert list(payload) == [
            "id",
            "product_name",
            "store",
            "category",
            "price_sar",
            "urls",
            "spatial_attributes",
            "aesthetic_features",
        ]
        assert set(payload["urls"]) == {"product_link", "image_url", "3d_model_url"}
        assert set(payload["spatial_attributes"]) == {"length_cm", "width_cm", "height_cm"}
        assert set(payload["aesthetic_features"]) == {
            "primary_colors",
            "material",
            "style",
            "vibe",
        }

    def test_id_is_the_article_number(self):
        assert make_product().as_dict()["id"] == "s79482824"

    def test_advisory_fields_stay_out_of_the_strict_shape(self):
        """seat_depth_cm and depth_cm exist, but the solver must not see them:
        a box with four axes invites picking the wrong one."""
        dims = Dimensions.from_retailer(width=228, depth=95, height=83, seat_depth=60)
        payload = make_product(dimensions=dims).as_dict()

        assert "seat_depth_cm" not in payload["spatial_attributes"]
        assert "depth_cm" not in payload["spatial_attributes"]
        assert "room_category" not in payload
        assert payload["spatial_attributes"]["length_cm"] == 95.0

    def test_rejects_an_unknown_profile(self):
        with pytest.raises(ValueError, match="unknown profile"):
            make_product().as_dict("loose")


class TestTypeSafety:
    """`95` and `95.0` are different JSON tokens.

    Dart's jsonDecode yields `int` for `95`, and `data['length_cm'] as double`
    throws a runtime TypeError on it. Most furniture measures a whole number of
    centimetres, so emitting ints would crash the solver on the common case and
    work only on the odd 83.5cm chair.
    """

    def test_axes_serialise_as_json_floats(self):
        text = json.dumps(make_product().as_dict())
        assert '"length_cm": 95.0' in text
        assert '"width_cm": 228.0' in text
        assert '"height_cm": 83.0' in text

    def test_axes_are_python_floats_not_ints(self):
        spatial = make_product().as_dict()["spatial_attributes"]
        for axis in ("length_cm", "width_cm", "height_cm"):
            assert isinstance(spatial[axis], float), axis

    def test_price_serialises_as_a_float(self):
        payload = make_product(price_sar=2495).as_dict()
        assert isinstance(payload["price_sar"], float)
        assert '"price_sar": 2495.0' in json.dumps(payload)

    def test_a_fractional_axis_survives_rounding(self):
        dims = Dimensions.from_retailer(width=228, depth=95, height=83.5)
        assert make_product(dimensions=dims).as_dict()["spatial_attributes"]["height_cm"] == 83.5


class TestAestheticFallback:
    """Rule: keys always ship, values may be empty. An unreadable style must
    not cost the catalogue a product the solver could otherwise place."""

    def test_empty_features_keep_every_key(self):
        payload = make_product(aesthetics=AestheticFeatures.empty()).as_dict()
        features = payload["aesthetic_features"]

        assert set(features) == {"primary_colors", "material", "style", "vibe"}
        assert features["primary_colors"] == []
        assert features["material"] == ""
        assert features["style"] == ""
        assert features["vibe"] == ""

    def test_a_record_with_no_aesthetics_still_validates(self):
        make_product(aesthetics=AestheticFeatures.empty()).validate()

    def test_empty_values_are_never_null(self):
        """`null` and `""` force two different checks downstream; pick one."""
        text = json.dumps(make_product(aesthetics=AestheticFeatures.empty()).as_dict())
        assert "null" not in text.replace('"price_sar": null', "")


class TestExtendedSchema:
    def test_adds_the_advisory_fields(self):
        dims = Dimensions.from_retailer(width=228, depth=95, height=83, seat_depth=60)
        payload = make_product(dimensions=dims).as_dict("extended")

        assert payload["room_category"] == "living_room"
        assert payload["spatial_attributes"]["depth_cm"] == 95.0
        assert payload["spatial_attributes"]["seat_depth_cm"] == 60.0
        assert "texture" in payload["aesthetic_features"]
        assert "pairs_with" in payload["aesthetic_features"]

    def test_depth_and_length_remain_the_same_axis(self):
        spatial = make_product().as_dict("extended")["spatial_attributes"]
        assert spatial["depth_cm"] == spatial["length_cm"] == 95.0

    def test_seat_depth_appears_only_when_published(self):
        assert "seat_depth_cm" not in make_product().as_dict("extended")["spatial_attributes"]


class TestSerialisation:
    def test_price_is_null_rather_than_zero_when_unknown(self):
        """`0` would read as free; the two must stay distinguishable."""
        assert make_product().as_dict()["price_sar"] is None
        assert make_product(price_sar=2495.0).as_dict()["price_sar"] == 2495.0

    def test_provenance_never_leaks_into_output(self):
        """Provenance is for the operator, not the app."""
        product = make_product()
        product.provenance = {"extractor": "rules", "source": "ikea-json-ld"}
        assert "provenance" not in json.dumps(product.as_dict())

    def test_dump_is_a_json_array(self):
        parsed = json.loads(dump_catalogue([make_product(), make_product()]))
        assert isinstance(parsed, list) and len(parsed) == 2


class TestValidation:
    def test_accepts_a_good_record(self):
        make_product().validate()

    def test_rejects_missing_sku(self):
        with pytest.raises(ValidationError, match="SKU"):
            make_product(sku="").validate()

    def test_rejects_placeholder_image(self):
        """A placeholder image 404s in the app; better to drop the product."""
        with pytest.raises(ValidationError, match="placeholder"):
            make_product(image_url="https://cdn.example.com/placeholder.png").validate()

    def test_rejects_non_https_image(self):
        with pytest.raises(ValidationError, match="image_url"):
            make_product(image_url="/local/kivik.jpg").validate()

    def test_rejects_implausible_dimensions(self):
        with pytest.raises(ValidationError, match="implausible"):
            make_product(dimensions=Dimensions.from_retailer(width=5000, depth=95, height=83)).validate()

    def test_rejects_untranslated_arabic(self):
        """Requirement 1: English only, even from an Arabic source page."""
        aesthetics = AestheticFeatures(
            primary_colors=["رمادي"],
            material="قماش",
            style="Modern",
            texture="Soft",
            vibe="Cozy",
            pairs_with=["Rugs"],
        )
        with pytest.raises(ValidationError, match="non-English"):
            make_product(aesthetics=aesthetics).validate()

    def test_rejects_unknown_category(self):
        with pytest.raises(ValidationError, match="category"):
            make_product(category="hammock").validate()

    def test_rejects_a_non_saudi_product_link(self):
        """A product from another market parses cleanly and cannot be bought."""
        with pytest.raises(ValidationError, match="Saudi storefront"):
            make_product(
                product_link="https://www.ikea.com/us/en/p/kivik-sofa-s79482824/"
            ).validate()

    def test_rejects_an_implausible_price(self):
        with pytest.raises(ValidationError, match="price_sar"):
            make_product(price_sar=-5).validate()

    def test_accepts_a_missing_price(self):
        make_product(price_sar=None).validate()


class TestIncompleteRecords:
    """`--allow-incomplete` ships a dimensionless record; it must say so."""

    def test_missing_dimensions_are_rejected_by_default(self):
        with pytest.raises(ValidationError, match="no dimensions"):
            make_product(dimensions=None).validate()

    def test_a_flagged_record_is_allowed_through(self):
        product = make_product(dimensions=None, issues=["missing_dimensions"])
        product.validate()

        # The flag only exists in the extended shape — the strict contract has
        # nowhere to declare incompleteness, which is why the CLI refuses the
        # combination outright.
        payload = product.as_dict("extended")
        assert payload["spatial_attributes"] is None
        assert payload["data_quality"] == {
            "complete": False,
            "issues": ["missing_dimensions"],
        }

    def test_a_complete_record_carries_no_data_quality_block(self):
        """Absence of the block is the signal that a record is whole."""
        assert "data_quality" not in make_product().as_dict("extended")
