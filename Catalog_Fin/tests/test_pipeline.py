"""End-to-end pipeline test against fixture pages — no network required.

This is the test that proves the parts fit together: a page shaped like IKEA's
real markup goes in, a schema-valid catalogue record comes out, and the
dimension-required rule actually drops what it promises to drop.
"""

from __future__ import annotations

import json

import pytest

from furn_catalog.adapters.ikea import IkeaAdapter
from furn_catalog.aesthetics import RuleBasedExtractor
from furn_catalog.ikea_api import ApiProduct
from furn_catalog.pipeline import Pipeline
from furn_catalog.render import RenderResult

KIVIK_URL = "https://www.ikea.com/sa/en/p/kivik-3-seat-sofa-tresund-anthracite-s79482824/"
BILLY_URL = "https://www.ikea.com/sa/en/p/billy-bookcase-white-20522046/"
NODIMS_URL = "https://www.ikea.com/sa/en/p/mystery-sofa-s11111111/"


def ikea_page(
    *,
    name: str,
    sku: str,
    image: str,
    colour: str,
    measurements: dict[str, str] | None = None,
    materials: str = "",
) -> str:
    """Reproduce the surfaces the adapter reads: JSON-LD, canonical, dl block."""
    ld = {
        "@context": "https://schema.org",
        "@type": "Product",
        "name": name,
        "image": [image],
        "sku": sku,
        "color": colour,
        "description": f"{name} for the living room.",
    }
    rows = "".join(
        f"<dt>{label}</dt><dd>{value}</dd>" for label, value in (measurements or {}).items()
    )
    return f"""<!doctype html>
<html><head>
  <title>{name} - IKEA</title>
  <link rel="canonical" href="https://www.ikea.com/sa/en/p/{_slug(name)}-{sku}/">
  <meta property="og:image" content="{image}">
  <script type="application/ld+json">{json.dumps(ld)}</script>
</head><body>
  <dl class="pip-product-dimensions">{rows}</dl>
  <div id="SEC_product-details-material">{materials}</div>
</body></html>"""


def _slug(name: str) -> str:
    return "".join(c.lower() if c.isalnum() else "-" for c in name).strip("-")


class FakeClient:
    """Stands in for HttpClient; serves fixtures and 404s everything else."""

    def __init__(self, pages: dict[str, str]) -> None:
        self.pages = pages
        self.fetched: list[str] = []

    def get_with_url(
        self, url: str, *, use_cache: bool = True, headers=None
    ) -> tuple[str, str]:
        self.fetched.append(url)
        if url not in self.pages:
            from furn_catalog.http import FetchError

            raise FetchError(f"HTTP 404 for {url}")
        return self.pages[url], url

    def get(self, url: str, *, use_cache: bool = True, headers=None) -> str:
        return self.get_with_url(url)[0]


class FakeRenderer:
    """A browser that serves the expanded version of a page.

    Returns a bare string — the pre-RenderResult contract — deliberately, to
    pin that older test doubles and any third-party renderer that still
    returns HTML keep working.
    """

    def __init__(self, expanded: dict[str, str]) -> None:
        self.expanded = expanded
        self.rendered: list[str] = []

    def render(self, url: str) -> str | None:
        self.rendered.append(url)
        return self.expanded.get(url)


class FakeResultRenderer:
    """A browser returning the full RenderResult, like the real one now does."""

    def __init__(self, results: dict[str, "RenderResult"]) -> None:
        self.results = results
        self.rendered: list[str] = []

    def render(self, url: str) -> "RenderResult | None":
        self.rendered.append(url)
        return self.results.get(url)


@pytest.fixture
def pages() -> dict[str, str]:
    return {
        KIVIK_URL: ikea_page(
            name="KIVIK 3-seat sofa, Tresund anthracite",
            sku="s79482824",
            image="https://www.ikea.com/sa/en/images/products/kivik__1103001_pe867123_s5.jpg",
            colour="Tresund anthracite",
            measurements={
                "Width": "228 cm",
                "Depth": "95 cm",
                "Height": "83 cm",
                "Seat depth": "60 cm",
            },
            materials="Polyester fabric. Frame: solid pine. Cushion: polyurethane foam.",
        ),
        BILLY_URL: ikea_page(
            name="BILLY bookcase, white, 80x28x202 cm",
            sku="20522046",
            image="https://www.ikea.com/sa/en/images/products/billy__0625599_pe692385_s5.jpg",
            colour="white",
            measurements={},  # forces the title-triple fallback
            materials="Particleboard, paper foil.",
        ),
        NODIMS_URL: ikea_page(
            name="MYSTERY sofa, grey",
            sku="s11111111",
            image="https://www.ikea.com/sa/en/images/products/mystery__1.jpg",
            colour="grey",
            measurements={"Seat depth": "60 cm"},  # no usable footprint
            materials="Polyester fabric.",
        ),
    }


def build_pipeline(
    pages: dict[str, str],
    seeds: list[str],
    *,
    api: dict[str, ApiProduct] | None = None,
    renderer: FakeRenderer | None = None,
    allow_incomplete: bool = False,
) -> tuple[Pipeline, FakeClient]:
    client = FakeClient(pages)
    # `use_api=False` keeps these tests on the HTML path; the search backend has
    # its own suite in test_ikea_api.py. Where a test needs API data it injects
    # the index directly rather than faking an endpoint.
    adapter = IkeaAdapter(client, seeds=seeds, use_api=False, renderer=renderer)
    if api:
        adapter._api_index.update(api)
    pipeline = Pipeline(
        adapter, extractor=RuleBasedExtractor(), allow_incomplete=allow_incomplete
    )
    return pipeline, client


class TestIkeaAdapter:
    def test_extracts_a_complete_record(self, pages):
        pipeline, _ = build_pipeline(pages, [KIVIK_URL])
        products, report = pipeline.run(limit=1)

        assert report.emitted == 1
        record = products[0].as_dict("extended")

        assert record["store"] == "IKEA KSA"
        assert record["category"] == "sofa"
        assert record["urls"]["product_link"].endswith("s79482824/")
        assert record["urls"]["image_url"].startswith("https://www.ikea.com/")
        # Retailer W228/D95/H83 maps to Furn-App length 95, width 228.
        assert record["spatial_attributes"] == {
            "length_cm": 95,
            "width_cm": 228,
            "height_cm": 83,
            "depth_cm": 95,
            "seat_depth_cm": 60,
        }

    def test_derives_aesthetics_from_page_vocabulary(self, pages):
        pipeline, _ = build_pipeline(pages, [KIVIK_URL])
        products, _ = pipeline.run(limit=1)
        features = products[0].as_dict("extended")["aesthetic_features"]

        assert "Dark Grey" in features["primary_colors"]  # "anthracite"
        assert "Polyester fabric" in features["material"]
        assert features["style"] and features["texture"] and features["vibe"]
        assert len(features["pairs_with"]) >= 3

    def test_the_strict_shape_carries_the_four_contract_features(self, pages):
        pipeline, _ = build_pipeline(pages, [KIVIK_URL])
        products, _ = pipeline.run(limit=1)
        features = products[0].as_dict()["aesthetic_features"]

        assert set(features) == {"primary_colors", "material", "style", "vibe"}
        assert "Dark Grey" in features["primary_colors"]

    def test_falls_back_to_the_title_triple(self, pages):
        """BILLY has no measurement block; `80x28x202 cm` is in the name."""
        pipeline, _ = build_pipeline(pages, [BILLY_URL])
        products, report = pipeline.run(limit=1)

        assert report.emitted == 1
        assert products[0].as_dict("extended")["spatial_attributes"] == {
            "length_cm": 28,
            "width_cm": 80,
            "height_cm": 202,
            "depth_cm": 28,
        }

    def test_3d_model_url_is_deterministic_per_sku(self, pages):
        pipeline, _ = build_pipeline(pages, [KIVIK_URL])
        products, _ = pipeline.run(limit=1)
        assert products[0].as_dict()["urls"]["3d_model_url"].endswith("_s79482824.usdz")


class TestDropRules:
    def test_drops_products_without_dimensions(self, pages):
        """Requirement 4: no measurements, no product. Never a guess."""
        pipeline, _ = build_pipeline(pages, [NODIMS_URL])
        products, report = pipeline.run(limit=1)

        assert products == []
        assert report.drops["no_dimensions"] == 1

    def test_drops_unavailable_seeds_without_failing_the_run(self, pages):
        """A 404 means the article is not stocked in KSA — expected, not fatal."""
        pipeline, _ = build_pipeline(
            pages, ["https://www.ikea.com/sa/en/p/gone-s99999999/", KIVIK_URL]
        )
        products, report = pipeline.run(limit=2)

        assert len(products) == 1
        assert report.drops["not_a_product_page"] == 1

    def test_deduplicates_by_article_number(self, pages):
        """The same article reached via two market slugs is one product."""
        us_slug = "https://www.ikea.com/us/en/p/kivik-sofa-tresund-anthracite-s79482824/"
        pages[IkeaAdapter.to_ksa_url(us_slug)] = pages[KIVIK_URL]

        pipeline, _ = build_pipeline(pages, [KIVIK_URL, us_slug])
        products, report = pipeline.run(limit=5)

        assert len(products) == 1
        assert report.drops["duplicate_sku"] == 1

    def test_every_emitted_record_validates(self, pages):
        pipeline, _ = build_pipeline(pages, list(pages))
        products, _ = pipeline.run(limit=10)

        assert products
        for product in products:
            product.validate()  # raises on any rule violation


def api_product(**overrides) -> ApiProduct:
    defaults = dict(
        item_no="s11111111",
        name="MYSTERY",
        type_name="sofa",
        measure_text="220x90x80 cm",
        image_url="https://www.ikea.com/sa/en/images/products/mystery__1.jpg",
        pip_url=NODIMS_URL,
        colour="grey",
    )
    defaults.update(overrides)
    return ApiProduct(**defaults)


class TestDimensionLayers:
    """The first live run dropped 54 products because the page carried no
    measurements at all. These pin the sources that now cover that."""

    def test_search_api_supplies_dimensions_the_page_lacks(self, pages):
        pipeline, _ = build_pipeline(
            pages, [NODIMS_URL], api={"s11111111": api_product()}
        )
        products, report = pipeline.run(limit=1)

        assert report.emitted == 1
        assert products[0].as_dict("extended")["spatial_attributes"] == {
            "length_cm": 90,
            "width_cm": 220,
            "height_cm": 80,
            "depth_cm": 90,
            # The page publishes a seat depth but no footprint; both survive.
            "seat_depth_cm": 60,
        }
        assert products[0].provenance["dimensions_from"] == "search-api"

    def test_reads_the_triple_out_of_embedded_json(self, pages):
        """IKEA renders measurements client-side; the data is still in a blob."""
        pages[NODIMS_URL] = pages[NODIMS_URL].replace(
            "</head>",
            '<script>window.__DATA__={"itemMeasureReferenceText":"200x88x75 cm"}</script></head>',
        )
        pipeline, _ = build_pipeline(pages, [NODIMS_URL])
        products, _ = pipeline.run(limit=1)

        assert products[0].as_dict("extended")["spatial_attributes"] == {
            "length_cm": 88,
            "width_cm": 200,
            "height_cm": 75,
            "depth_cm": 88,
            "seat_depth_cm": 60,
        }
        assert products[0].provenance["dimensions_from"] == "embedded-json"

    def test_records_which_layer_answered(self, pages):
        pipeline, _ = build_pipeline(pages, [KIVIK_URL])
        products, _ = pipeline.run(limit=1)
        assert products[0].provenance["dimensions_from"] == "measurement-block"

    def test_still_drops_when_no_layer_answers(self, pages):
        """The fallbacks widen coverage; they must not invent a footprint."""
        pipeline, _ = build_pipeline(pages, [NODIMS_URL])
        products, report = pipeline.run(limit=1)

        assert products == []
        assert report.drops["no_dimensions"] == 1


class TestApiOnlyRecords:
    def test_builds_a_record_when_the_page_is_gone(self, pages):
        """A 404 slug is not a dead product if the API described the article."""
        dead = "https://www.ikea.com/sa/en/p/kivik-sofa-tibbleby-beige-gray-s39440593/"
        api = api_product(
            item_no="s39440593",
            name="KIVIK",
            type_name="2-seat sofa",
            measure_text="190x95x83 cm",
            pip_url=dead,
        )
        pipeline, _ = build_pipeline(pages, [dead], api={"s39440593": api})
        products, report = pipeline.run(limit=1)

        assert report.emitted == 1
        record = products[0].as_dict("extended")
        assert record["category"] == "sofa"
        assert record["spatial_attributes"] == {
            "length_cm": 95,
            "width_cm": 190,
            "height_cm": 83,
            "depth_cm": 95,
        }
        assert products[0].provenance["source"] == "ikea-search-api"
        products[0].validate()

    def test_a_dead_page_with_no_api_entry_is_still_dropped(self, pages):
        pipeline, _ = build_pipeline(pages, ["https://www.ikea.com/sa/en/p/gone-s99999999/"])
        products, report = pipeline.run(limit=1)

        assert products == []
        assert report.drops["not_a_product_page"] == 1


class TestBrowserRetry:
    """IKEA keeps measurements behind a control only a browser opens."""

    def test_retries_a_dimensionless_page_in_the_browser(self, pages):
        expanded = ikea_page(
            name="MYSTERY sofa, grey",
            sku="s11111111",
            image="https://www.ikea.com/sa/en/images/products/mystery__1.jpg",
            colour="grey",
            measurements={"Width": "210 cm", "Depth": "92 cm", "Height": "80 cm"},
            materials="Polyester fabric.",
        )
        renderer = FakeRenderer({NODIMS_URL: expanded})
        pipeline, _ = build_pipeline(pages, [NODIMS_URL], renderer=renderer)
        products, report = pipeline.run(limit=1)

        assert renderer.rendered == [NODIMS_URL]
        assert report.retried == 1 and report.recovered == 1
        assert products[0].as_dict()["spatial_attributes"]["width_cm"] == 210
        assert products[0].provenance["rendered"] is True

    def test_does_not_render_pages_that_already_parsed(self, pages):
        """The browser costs seconds a page; it is spent only where needed."""
        renderer = FakeRenderer({})
        pipeline, _ = build_pipeline(pages, [KIVIK_URL], renderer=renderer)
        products, report = pipeline.run(limit=1)

        assert renderer.rendered == []
        assert report.retried == 0
        assert len(products) == 1

    def test_a_retry_that_still_finds_nothing_drops(self, pages):
        renderer = FakeRenderer({})  # render() returns None -> static fallback
        pipeline, _ = build_pipeline(pages, [NODIMS_URL], renderer=renderer)
        products, report = pipeline.run(limit=1)

        assert products == []
        assert report.retried == 1 and report.recovered == 0
        assert report.drops["no_dimensions"] == 1

    def test_visible_text_from_the_rendered_panel_is_a_source(self, pages):
        """The live failure this exists for: the measurement panel renders into
        a shadow root, so the serialised markup alone may never carry it — but
        the visible text does. RenderResult.text feeds the browser-text layer."""
        result = RenderResult(
            html=pages[NODIMS_URL],  # markup unchanged: still no dims in it
            text="MYSTERY sofa Measurements Width: 210 cm Depth: 92 cm "
            "Height: 80 cm Seat depth: 60 cm",
            clicks=['button:has-text("Measurements")'],
            cm_before=0,
            cm_after=4,
            waited=True,
        )
        renderer = FakeResultRenderer({NODIMS_URL: result})
        pipeline, _ = build_pipeline(pages, [NODIMS_URL], renderer=renderer)
        products, report = pipeline.run(limit=1)

        assert report.emitted == 1 and report.recovered == 1
        record = products[0].as_dict("extended")
        assert record["spatial_attributes"] == {
            "length_cm": 92,
            "width_cm": 210,
            "height_cm": 80,
            "depth_cm": 92,
            "seat_depth_cm": 60,
        }
        assert products[0].provenance["dimensions_from"] == "browser-text"
        assert products[0].provenance["render_waited"] is True
        assert products[0].provenance["render_cm_tokens"] == "0->4"

    def test_seat_depth_alone_in_the_panel_is_never_a_footprint(self, pages):
        """Strictness under the new layer: a panel showing only sub-measurements
        must still drop the record, not improvise a box."""
        result = RenderResult(
            html=pages[NODIMS_URL],
            text="MYSTERY sofa Measurements Seat depth: 60 cm Package weight 41 kg",
            clicks=["x"],
            waited=True,
        )
        renderer = FakeResultRenderer({NODIMS_URL: result})
        pipeline, _ = build_pipeline(pages, [NODIMS_URL], renderer=renderer)
        products, report = pipeline.run(limit=1)

        assert products == []
        assert report.drops["no_dimensions"] == 1

    def test_seat_depth_listed_first_cannot_become_the_depth_axis(self, pages):
        """Order-independence: `Seat depth: 60 cm` printed before `Depth: 92 cm`
        must not win the Depth label. Whether a sofa gets its real depth or its
        seat depth must never hinge on the panel's line order."""
        result = RenderResult(
            html=pages[NODIMS_URL],
            text="Measurements Seat depth: 60 cm Width: 210 cm "
            "Depth: 92 cm Height: 80 cm",
            clicks=["x"],
            waited=True,
        )
        renderer = FakeResultRenderer({NODIMS_URL: result})
        pipeline, _ = build_pipeline(pages, [NODIMS_URL], renderer=renderer)
        products, _ = pipeline.run(limit=1)

        spatial = products[0].as_dict("extended")["spatial_attributes"]
        assert spatial["length_cm"] == 92  # the real depth, not the seat's
        assert spatial["seat_depth_cm"] == 60

    def test_a_seat_depth_first_panel_with_no_real_depth_drops(self, pages):
        """The nastier variant: seat depth present, real depth absent. Before
        the lookbehind fix this fabricated a box with depth=60."""
        result = RenderResult(
            html=pages[NODIMS_URL],
            text="Measurements Seat depth: 60 cm Width: 210 cm Height: 80 cm",
            clicks=["x"],
            waited=True,
        )
        renderer = FakeResultRenderer({NODIMS_URL: result})
        pipeline, _ = build_pipeline(pages, [NODIMS_URL], renderer=renderer)
        products, report = pipeline.run(limit=1)

        assert products == []
        assert report.drops["no_dimensions"] == 1


class TestIncompleteRecords:
    def test_allow_incomplete_flags_instead_of_dropping(self, pages):
        pipeline, _ = build_pipeline(pages, [NODIMS_URL], allow_incomplete=True)
        products, report = pipeline.run(limit=1)

        assert report.emitted == 1 and report.incomplete == 1
        record = products[0].as_dict("extended")
        assert record["spatial_attributes"] is None
        assert record["data_quality"]["issues"] == ["missing_dimensions"]
        products[0].validate()

    def test_the_default_still_drops(self, pages):
        pipeline, _ = build_pipeline(pages, [NODIMS_URL])
        products, report = pipeline.run(limit=1)
        assert products == [] and report.incomplete == 0


class TestLocaleEnforcement:
    def test_discovery_rewrites_seeds_onto_the_saudi_storefront(self, pages):
        us_slug = "https://www.ikea.com/us/en/p/kivik-3-seat-sofa-tresund-anthracite-s79482824/"
        pipeline, client = build_pipeline(pages, [us_slug])
        products, _ = pipeline.run(limit=1)

        assert client.fetched == [KIVIK_URL]  # the /us/ slug was never requested
        assert products[0].as_dict()["urls"]["product_link"].startswith(
            "https://www.ikea.com/sa/en/"
        )

    def test_an_off_market_canonical_tag_does_not_win(self, pages):
        """The page can claim any canonical it likes; the locale gate decides."""
        pages[KIVIK_URL] = pages[KIVIK_URL].replace(
            'rel="canonical" href="https://www.ikea.com/sa/en/p/',
            'rel="canonical" href="https://www.ikea.com/us/en/p/',
        )
        pipeline, _ = build_pipeline(pages, [KIVIK_URL])
        products, _ = pipeline.run(limit=1)

        assert products[0].as_dict()["urls"]["product_link"].startswith(
            "https://www.ikea.com/sa/en/"
        )
        products[0].validate()


class TestExpandedMetadata:
    def test_carries_price_room_and_seat_depth(self, pages):
        pages[KIVIK_URL] = pages[KIVIK_URL].replace(
            "</body>", '<div class="price">SAR 2,495.00</div></body>'
        )
        pipeline, _ = build_pipeline(pages, [KIVIK_URL])
        record = pipeline.run(limit=1)[0][0].as_dict("extended")

        assert record["price_sar"] == 2495.0
        assert record["room_category"] == "living_room"
        # The fixture publishes `Seat depth: 60 cm` alongside the real depth.
        assert record["spatial_attributes"]["seat_depth_cm"] == 60
        assert record["spatial_attributes"]["length_cm"] == 95

    def test_a_page_without_a_price_says_null(self, pages):
        pipeline, _ = build_pipeline(pages, [KIVIK_URL])
        assert pipeline.run(limit=1)[0][0].as_dict()["price_sar"] is None


class TestSeedRewriting:
    @pytest.mark.parametrize(
        "url",
        [
            "https://www.ikea.com/us/en/p/kivik-sofa-tibbleby-beige-gray-s39440593/",
            "https://www.ikea.com/kw/en/p/malm-bed-frame-high-white-s09929373/",
            "https://www.ikea.com/se/en/p/koppang-chest-of-3-drawers-white-10385950/",
        ],
    )
    def test_rewrites_any_market_onto_ksa(self, url):
        """Article numbers are global, so a seed from any market is a candidate."""
        rewritten = IkeaAdapter.to_ksa_url(url)
        assert rewritten is not None
        assert rewritten.startswith("https://www.ikea.com/sa/en/p/")

    def test_ignores_non_product_urls(self):
        assert IkeaAdapter.to_ksa_url("https://www.ikea.com/sa/en/cat/sofas-fu003/") is None


class TestReport:
    def test_report_explains_every_drop(self, pages):
        pipeline, _ = build_pipeline(pages, list(pages) + ["https://www.ikea.com/sa/en/p/x-s99999999/"])
        _, report = pipeline.run(limit=10)

        rendered = report.render()
        assert "no_dimensions" in rendered
        assert f"visited   : {report.seen}" in rendered
        # Every product visited is either emitted or accounted for as a drop.
        assert report.seen == report.emitted + sum(report.drops.values())
