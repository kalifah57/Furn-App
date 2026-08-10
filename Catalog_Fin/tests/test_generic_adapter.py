"""Home Centre / Abyat extraction, at the same level as the IKEA adapter.

Both bugs pinned here were found by running the adapter end-to-end for the
first time, against a fixture reproducing Landmark's page shape. Neither was
visible from reading the code.
"""

from __future__ import annotations

import json

import pytest

from bs4 import BeautifulSoup

from furn_catalog.adapters.generic import HomeCentreAdapter, _is_packaging_row

SPEC_PAGE = """<!doctype html><html><body>
  <h2>Measurements</h2>
  <table class="product-specifications"><tbody>
    <tr><td>Width</td><td>210 cm</td></tr>
    <tr><td>Depth</td><td>88 cm</td></tr>
    <tr><td>Height</td><td>85 cm</td></tr>
    <tr><td>Seat Depth</td><td>55 cm</td></tr>
    <tr><td>Assembly Required</td><td>Yes</td></tr>
  </tbody></table>
  <h2>Package details</h2>
  <table><tbody>
    <tr><td>Width</td><td>224 cm</td></tr>
    <tr><td>Height</td><td>28 cm</td></tr>
    <tr><td>Length</td><td>208 cm</td></tr>
  </tbody></table>
</body></html>"""


def adapter() -> HomeCentreAdapter:
    return HomeCentreAdapter(client=None)


class TestPackagingTables:
    """`table tr` matches every table on the page, and a carton uses the same
    bare Width/Height/Length labels as the product. Since the larger value wins
    an axis, the box beat the thing inside it: an 88cm-deep sofa came back
    208cm deep — its carton's length."""

    def test_the_product_table_wins(self):
        specs = adapter()._specs(BeautifulSoup(SPEC_PAGE, "html.parser"))
        dims, source = adapter()._dimensions(specs, "Alton Sofa", "", "")

        assert dims.as_dict() == {"width_cm": 210.0, "length_cm": 88.0, "height_cm": 85.0}
        assert source == "spec-table"

    def test_packaging_rows_never_reach_the_spec_table(self):
        specs = adapter()._specs(BeautifulSoup(SPEC_PAGE, "html.parser"))
        assert "Length" not in specs, "the carton's Length was read as a product axis"
        assert specs["Depth"] == "88 cm"

    def test_the_row_classifier_sees_the_heading(self):
        soup = BeautifulSoup(SPEC_PAGE, "html.parser")
        rows = soup.select("table tr")
        assert not _is_packaging_row(rows[0])
        assert _is_packaging_row(rows[-1])

    def test_seat_depth_is_carried_but_not_an_axis(self):
        specs = adapter()._specs(BeautifulSoup(SPEC_PAGE, "html.parser"))
        dims, _ = adapter()._dimensions(specs, "Alton Sofa", "", "")
        assert dims.as_dict("extended")["seat_depth_cm"] == 55.0
        assert dims.length_cm == 88.0

    def test_a_page_with_no_headings_still_parses(self):
        """No heading structure must read as 'not packaging', not as 'skip
        everything' — the label whitelist is the backstop there."""
        plain = """<table><tbody>
            <tr><td>Width</td><td>120 cm</td></tr>
            <tr><td>Depth</td><td>60 cm</td></tr>
            <tr><td>Height</td><td>75 cm</td></tr></tbody></table>"""
        specs = adapter()._specs(BeautifulSoup(plain, "html.parser"))
        dims, _ = adapter()._dimensions(specs, "", "", "")
        assert dims.as_dict() == {"width_cm": 120.0, "length_cm": 60.0, "height_cm": 75.0}


class TestSharedParsers:
    """The label whitelist is one implementation for every retailer, so a
    qualifier rejected for IKEA is rejected here too."""

    def test_browser_text_is_a_dimension_source(self):
        text = "Measurements Width: 210 cm Depth: 88 cm Height: 85 cm"
        dims, source = adapter()._dimensions({}, "", "", text)
        assert dims.as_dict() == {"width_cm": 210.0, "length_cm": 88.0, "height_cm": 85.0}
        assert source == "browser-text"

    def test_component_labels_are_refused_here_too(self):
        text = "Measurements Armrest width: 8 cm Seat depth: 55 cm Seat height: 45 cm"
        dims, source = adapter()._dimensions({}, "", "", text)
        assert dims is None and source == "none"

    def test_packaging_in_free_text_is_scoped_out(self):
        text = (
            "Measurements Width: 210 cm Depth: 88 cm Height: 85 cm "
            "Package details Length: 208 cm Width: 224 cm"
        )
        dims, _ = adapter()._dimensions({}, "", "", text)
        assert dims.length_cm == 88.0


class TestManifestPerRetailer:
    """Two catalogues, two manifests. They collided before."""

    @pytest.mark.parametrize(
        "catalogue,expected",
        [
            ("catalog.json", "catalog.manifest.json"),
            ("catalog.homecentre.json", "catalog.homecentre.manifest.json"),
            ("catalog.abyat.json", "catalog.abyat.manifest.json"),
        ],
    )
    def test_each_catalogue_gets_its_own_manifest(self, catalogue, expected):
        from pathlib import Path

        from furn_catalog.manifest import manifest_path_for

        assert manifest_path_for(Path(catalogue)).name == expected

    def test_two_catalogues_do_not_share_a_manifest(self):
        from pathlib import Path

        from furn_catalog.manifest import manifest_path_for

        a = manifest_path_for(Path("catalog.json"))
        b = manifest_path_for(Path("catalog.homecentre.json"))
        assert a != b, "publishing the second catalogue would overwrite the first's manifest"
