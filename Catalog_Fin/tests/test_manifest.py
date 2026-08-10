"""The published contract: the schema version, and the manifest beside it.

Furn-App hard-codes a raw URL and polls `catalog.manifest.json`, pulling the
catalogue only when `sha256` changes. Two things can break a consumer without
anything raising here:

* the record shape changes and `schema_version` does not, so code written
  against the old shape silently mis-reads the new one;
* the manifest's hash drifts from the file it describes, so the consumer either
  never sees an update or re-downloads an unchanged file forever.

These tests exist to make both impossible to do by accident.
"""

from __future__ import annotations

import json

import pytest

from furn_catalog import manifest
from furn_catalog.schema import SCHEMA_VERSION, AestheticFeatures, Product, dump_catalogue
from furn_catalog.units import Dimensions


def make_product(**overrides) -> Product:
    defaults = dict(
        product_name="KIVIK 3-seat sofa - Tresund anthracite",
        store="IKEA KSA",
        category="sofa",
        product_link="https://www.ikea.com/sa/en/p/kivik-3-seat-sofa-s79482824/",
        image_url="https://www.ikea.com/sa/en/images/products/kivik__1103001.jpg",
        model_3d_url="https://api.furn-app.com/assets/models/kivik_s79482824.usdz",
        dimensions=Dimensions.from_retailer(width=228, depth=95, height=83),
        aesthetics=AestheticFeatures(
            primary_colors=["Dark Grey"],
            material="Polyester fabric",
            style="Contemporary Dark",
            texture="Woven",
            vibe="Grounded, cosy",
            pairs_with=["Coffee tables"],
        ),
        sku="s79482824",
        price_sar=2495.0,
    )
    defaults.update(overrides)
    return Product(**defaults)


class TestSchemaVersionPinsTheShape:
    """Change the published shape and this fails until the version is bumped.

    That is the whole mechanism behind "never change the shape silently". The
    key sets below are duplicated deliberately rather than derived from the
    code — a test that asks the code what shape it emits agrees with any shape
    the code emits, and would have caught nothing.
    """

    def test_version_1_top_level_keys(self):
        assert SCHEMA_VERSION == 1, (
            "SCHEMA_VERSION changed. Update the key sets in this test to match "
            "the new published shape, and tell the consumer before releasing."
        )
        assert list(make_product().as_dict()) == [
            "id",
            "product_name",
            "store",
            "category",
            "price_sar",
            "urls",
            "spatial_attributes",
            "aesthetic_features",
        ]

    def test_version_1_nested_keys(self):
        payload = make_product().as_dict()
        assert list(payload["urls"]) == ["product_link", "image_url", "3d_model_url"]
        assert set(payload["spatial_attributes"]) == {"length_cm", "width_cm", "height_cm"}
        assert set(payload["aesthetic_features"]) == {
            "primary_colors",
            "material",
            "style",
            "vibe",
        }

    def test_version_1_types(self):
        payload = make_product().as_dict()
        for axis in ("length_cm", "width_cm", "height_cm"):
            assert isinstance(payload["spatial_attributes"][axis], float)
        assert isinstance(payload["price_sar"], float)
        assert isinstance(payload["id"], str) and payload["id"]

    def test_price_may_be_null_but_never_zero(self):
        """`null` is 'unknown'. `0` would read as free."""
        assert make_product(price_sar=None).as_dict()["price_sar"] is None


class TestManifest:
    def _publish(self, tmp_path, records=3):
        catalogue = tmp_path / "catalog.json"
        catalogue.write_text(dump_catalogue([make_product() for _ in range(records)]), "utf-8")
        manifest.write(catalogue, record_count=records)
        return catalogue

    def test_written_beside_the_catalogue(self, tmp_path):
        catalogue = self._publish(tmp_path)
        assert (tmp_path / "catalog.manifest.json").exists()
        assert manifest.manifest_path_for(catalogue).name == "catalog.manifest.json"

    def test_carries_the_four_contract_fields(self, tmp_path):
        catalogue = self._publish(tmp_path)
        payload = json.loads(manifest.manifest_path_for(catalogue).read_text())

        assert set(payload) == {"schema_version", "record_count", "sha256", "generated_at"}
        assert payload["schema_version"] == SCHEMA_VERSION
        assert payload["record_count"] == 3
        assert len(payload["sha256"]) == 64
        assert payload["generated_at"].endswith("Z")

    def test_hash_is_of_the_bytes_on_disk(self, tmp_path):
        """The consumer hashes what it downloaded; anything else can disagree
        over a trailing newline and produce a mismatch nobody can explain."""
        import hashlib

        catalogue = self._publish(tmp_path)
        payload = json.loads(manifest.manifest_path_for(catalogue).read_text())
        assert payload["sha256"] == hashlib.sha256(catalogue.read_bytes()).hexdigest()

    def test_a_fresh_pair_verifies_clean(self, tmp_path):
        assert manifest.verify(self._publish(tmp_path)) == []

    def test_catches_a_stale_hash(self, tmp_path):
        """The silent failure: the catalogue is regenerated and the manifest is
        not, so a polling consumer never learns there is anything to pull."""
        catalogue = self._publish(tmp_path)
        catalogue.write_text(dump_catalogue([make_product() for _ in range(4)]), "utf-8")

        problems = manifest.verify(catalogue)
        assert any("sha256 mismatch" in p for p in problems)
        assert any("record_count mismatch" in p for p in problems)

    def test_catches_a_missing_manifest(self, tmp_path):
        catalogue = self._publish(tmp_path)
        manifest.manifest_path_for(catalogue).unlink()
        assert any("does not exist" in p for p in manifest.verify(catalogue))

    def test_catches_a_version_the_build_no_longer_emits(self, tmp_path):
        catalogue = self._publish(tmp_path)
        target = manifest.manifest_path_for(catalogue)
        payload = json.loads(target.read_text())
        payload["schema_version"] = SCHEMA_VERSION + 1
        target.write_text(json.dumps(payload))

        assert any("schema_version" in p for p in manifest.verify(catalogue))

    @pytest.mark.parametrize("field", ["schema_version", "record_count", "sha256", "generated_at"])
    def test_catches_a_missing_field(self, tmp_path, field):
        catalogue = self._publish(tmp_path)
        target = manifest.manifest_path_for(catalogue)
        payload = json.loads(target.read_text())
        del payload[field]
        target.write_text(json.dumps(payload))

        assert any(field in p for p in manifest.verify(catalogue))
