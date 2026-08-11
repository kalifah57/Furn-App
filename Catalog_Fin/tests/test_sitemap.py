"""Sitemap discovery, which replaced the hardcoded category paths.

Those paths were guesses and the live run scored them: five 404s and five 202
challenge pages out of ten. A sitemap is published by the retailer for this
exact purpose, so these tests care most about robustness — malformed XML, an
HTML error page served under an XML content type, and nested indexes are all
things a real storefront has served at some point.
"""

from __future__ import annotations

import re

from furn_catalog.sitemap import discover_products, iter_sitemap, sitemap_urls_from_robots

ROBOTS = """User-agent: *
Disallow: /sa/en/checkout
Sitemap: https://www.homecentre.com/sitemap_index.xml
sitemap: https://www.homecentre.com/sitemap_products.xml
"""

INDEX = """<?xml version="1.0" encoding="UTF-8"?>
<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <sitemap><loc>https://www.homecentre.com/sitemap_products_1.xml</loc></sitemap>
  <sitemap><loc>https://www.homecentre.com/sitemap_categories.xml</loc></sitemap>
</sitemapindex>"""

PRODUCTS = """<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>https://www.homecentre.com/sa/en/sofas/p/1234567</loc></url>
  <url><loc>https://www.homecentre.com/sa/en/beds/p/2345678</loc></url>
  <url><loc>https://www.homecentre.com/ae/en/sofas/p/9999999</loc></url>
</urlset>"""

CATEGORIES = """<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>https://www.homecentre.com/sa/en/c/furniture</loc></url>
</urlset>"""


class FakeClient:
    def __init__(self, pages: dict[str, str]) -> None:
        self.pages = pages
        self.fetched: list[str] = []

    def get(self, url: str, *, headers=None, use_cache: bool = True) -> str:
        self.fetched.append(url)
        if url not in self.pages:
            from furn_catalog.http import FetchError

            raise FetchError(f"HTTP 404 for {url}")
        return self.pages[url]


def client() -> FakeClient:
    return FakeClient(
        {
            "https://www.homecentre.com/robots.txt": ROBOTS,
            "https://www.homecentre.com/sitemap_index.xml": INDEX,
            "https://www.homecentre.com/sitemap_products_1.xml": PRODUCTS,
            "https://www.homecentre.com/sitemap_categories.xml": CATEGORIES,
        }
    )


class TestRobots:
    def test_reads_sitemap_directives_case_insensitively(self):
        found = sitemap_urls_from_robots(client(), "https://www.homecentre.com")
        assert found == [
            "https://www.homecentre.com/sitemap_index.xml",
            "https://www.homecentre.com/sitemap_products.xml",
        ]

    def test_missing_robots_is_empty_not_fatal(self):
        assert sitemap_urls_from_robots(FakeClient({}), "https://www.abyat.com") == []


class TestIterSitemap:
    def test_follows_a_nested_index(self):
        urls = list(iter_sitemap(client(), "https://www.homecentre.com/sitemap_index.xml"))
        assert "https://www.homecentre.com/sa/en/sofas/p/1234567" in urls
        assert "https://www.homecentre.com/sa/en/c/furniture" in urls

    def test_filter_applies_to_urls_not_to_indexes(self):
        """A product sitemap is rarely named after its products."""
        urls = list(
            iter_sitemap(
                client(),
                "https://www.homecentre.com/sitemap_index.xml",
                match=re.compile(r"/p/\d+"),
            )
        )
        assert urls == [
            "https://www.homecentre.com/sa/en/sofas/p/1234567",
            "https://www.homecentre.com/sa/en/beds/p/2345678",
            "https://www.homecentre.com/ae/en/sofas/p/9999999",
        ]

    def test_recovers_locs_from_malformed_xml(self):
        """Storefronts serve sitemaps with stray doctypes and BOMs."""
        broken = FakeClient(
            {
                "https://x/s.xml": "<urlset><url><loc>https://x/sa/en/p/1</loc></url>"
                "<url><loc>https://x/sa/en/p/2</loc>"  # unclosed
            }
        )
        assert list(iter_sitemap(broken, "https://x/s.xml")) == [
            "https://x/sa/en/p/1",
            "https://x/sa/en/p/2",
        ]

    def test_an_unreachable_sitemap_yields_nothing(self):
        assert list(iter_sitemap(FakeClient({}), "https://x/s.xml")) == []

    def test_does_not_revisit_a_self_referencing_index(self):
        looping = FakeClient(
            {
                "https://x/s.xml": "<sitemapindex><sitemap><loc>https://x/s.xml</loc>"
                "</sitemap></sitemapindex>"
            }
        )
        assert list(iter_sitemap(looping, "https://x/s.xml")) == []
        assert looping.fetched == ["https://x/s.xml"]


class TestDiscoverProducts:
    def test_finds_products_through_robots(self):
        found = list(
            discover_products(
                client(),
                "https://www.homecentre.com",
                product_pattern=re.compile(r"/sa/en/.*/p/\d+"),
            )
        )
        assert found == [
            "https://www.homecentre.com/sa/en/sofas/p/1234567",
            "https://www.homecentre.com/sa/en/beds/p/2345678",
        ]

    def test_falls_back_to_conventional_paths(self):
        """Several storefronts serve /sitemap.xml without advertising it."""
        unadvertised = FakeClient({"https://www.abyat.com/sitemap.xml": PRODUCTS})
        found = list(
            discover_products(
                unadvertised,
                "https://www.abyat.com",
                product_pattern=re.compile(r"/p/\d+"),
                extra_sitemaps=("/sitemap.xml",),
            )
        )
        assert len(found) == 3

    def test_no_sitemap_anywhere_is_empty_not_fatal(self):
        assert (
            list(
                discover_products(
                    FakeClient({}),
                    "https://www.abyat.com",
                    product_pattern=re.compile(r"/p/"),
                    extra_sitemaps=("/sitemap.xml",),
                )
            )
            == []
        )
