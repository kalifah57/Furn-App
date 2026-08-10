"""KSA locale enforcement.

The failure this guards against is the quiet one: a `/us/en/` or `/ae/en/` URL
parses perfectly, yields a complete record, and describes a product with the
wrong price and availability for the market this catalogue is for. Nothing
downstream can detect it, so the gate has to be airtight here.
"""

from __future__ import annotations

import pytest

from furn_catalog.locale import OffMarket, enforce, is_ksa, require_ksa, storefront_for


class TestEnforce:
    @pytest.mark.parametrize(
        "url,expected",
        [
            # Another market's storefront, rewritten onto ours.
            (
                "https://www.ikea.com/us/en/p/kivik-sofa-s39440593/",
                "https://www.ikea.com/sa/en/p/kivik-sofa-s39440593/",
            ),
            # The Arabic KSA locale is still the wrong one: output must be English.
            (
                "https://www.ikea.com/sa/ar/p/x-s09929373/",
                "https://www.ikea.com/sa/en/p/x-s09929373/",
            ),
            # Already correct — enforce is idempotent, and every layer calls it.
            (
                "https://www.ikea.com/sa/en/p/billy-20522046/",
                "https://www.ikea.com/sa/en/p/billy-20522046/",
            ),
            # No market segment at all.
            (
                "https://www.ikea.com/p/loose-s1/",
                "https://www.ikea.com/sa/en/p/loose-s1/",
            ),
            # Bare host, and a non-www alias.
            (
                "https://homecentre.com/ae/en/c/furniture",
                "https://www.homecentre.com/sa/en/c/furniture",
            ),
            (
                "https://www.abyat.com/kw/ar/p/sofa-123",
                "https://www.abyat.com/sa/en/p/sofa-123",
            ),
        ],
    )
    def test_rewrites_onto_the_saudi_storefront(self, url, expected):
        assert enforce(url) == expected

    def test_preserves_query_and_fragment(self):
        assert (
            enforce("https://www.ikea.com/us/en/p/x-s1/?colour=grey#specs")
            == "https://www.ikea.com/sa/en/p/x-s1/?colour=grey#specs"
        )

    @pytest.mark.parametrize(
        "url",
        [
            "https://example.com/sa/en/p/sofa-1/",  # not a retailer we know
            "/relative/path",
            "ftp://www.ikea.com/sa/en/",
            "",
        ],
    )
    def test_unknown_urls_are_skipped_not_raised(self, url):
        """Discovery hands this arbitrary hrefs; a stranger is a skip."""
        assert enforce(url) is None

    def test_require_ksa_raises_where_a_miss_is_a_bug(self):
        with pytest.raises(OffMarket):
            require_ksa("https://example.com/p/sofa")


class TestIsKsa:
    @pytest.mark.parametrize(
        "url,expected",
        [
            ("https://www.ikea.com/sa/en/p/x-s1/", True),
            ("https://www.ikea.com/sa/en", True),
            ("https://www.ikea.com/us/en/p/x-s1/", False),
            ("https://www.ikea.com/sa/ar/p/x-s1/", False),
            # A prefix that merely starts with the right letters is not a match.
            ("https://www.ikea.com/sa/enormous/p/", False),
            ("https://other.com/sa/en/p/x/", False),
        ],
    )
    def test_recognises_only_the_saudi_english_storefront(self, url, expected):
        assert is_ksa(url) is expected


class TestStorefrontLookup:
    def test_identifies_each_retailer(self):
        assert storefront_for("https://www.ikea.com/sa/en/").name == "ikea"
        assert storefront_for("https://www.homecentre.com/sa/en/").name == "homecentre"
        assert storefront_for("https://www.abyat.com/sa/en/").name == "abyat"

    def test_returns_none_for_a_stranger(self):
        assert storefront_for("https://www.amazon.sa/") is None
