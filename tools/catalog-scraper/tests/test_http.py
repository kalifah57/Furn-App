"""The polite HTTP client, against a real local server.

Everything else in the suite fakes the client, which means the client's own
behaviour — robots.txt semantics, caching, redirect tracking, header profiles —
was never actually executed. This runs it against a throwaway server on
localhost: no network, no retailer, still a real socket and a real response.

The robots tests matter most. `RobotFileParser.read()` treats 401/403 as a
blanket disallow, which is the opposite of what RFC 9309 says and would lock the
scraper out of any host that answers a robots.txt request with 403 instead of
404 — IKEA's search backend among them.
"""

from __future__ import annotations

import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest

from furn_catalog.http import FetchError, HttpClient, RobotsDisallowed

ROBOTS_ALLOW_ALL = "User-agent: *\nDisallow: /checkout\n"
ROBOTS_DISALLOW = "User-agent: *\nDisallow: /sa/en/c/\n"


class Handler(BaseHTTPRequestHandler):
    """Serves whatever `routes` says, and records the headers it was sent."""

    routes: dict[str, tuple[int, str]] = {}
    seen_headers: list[dict[str, str]] = []

    def do_GET(self):  # noqa: N802 - BaseHTTPRequestHandler's interface
        Handler.seen_headers.append(dict(self.headers))
        status, body = self.routes.get(self.path, (404, "not found"))

        if 300 <= status < 400:
            self.send_response(status)
            self.send_header("Location", body)
            self.end_headers()
            return

        payload = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, *args):  # keep the test output readable
        pass


@pytest.fixture
def server():
    Handler.seen_headers = []
    httpd = HTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    yield f"http://127.0.0.1:{httpd.server_port}"
    httpd.shutdown()
    httpd.server_close()


def client(tmp_path=None, **kwargs) -> HttpClient:
    # No delay: the throttle is not what these tests are about, and a 1s wait
    # per request would dominate the suite.
    kwargs.setdefault("delay", 0.0)
    kwargs.setdefault("jitter", 0.0)
    kwargs.setdefault("max_retries", 0)
    return HttpClient(cache_dir=tmp_path, **kwargs)


class TestRobots:
    def test_honours_an_explicit_disallow(self, server):
        Handler.routes = {"/robots.txt": (200, ROBOTS_DISALLOW)}
        http = client()

        assert http.allowed(f"{server}/sa/en/p/sofa-1/")
        assert not http.allowed(f"{server}/sa/en/c/furniture")

        with pytest.raises(RobotsDisallowed):
            http.get(f"{server}/sa/en/c/furniture")

    def test_a_404_robots_means_no_policy_not_no_entry(self, server):
        """RFC 9309 §2.3.1.3: 4xx is 'unavailable', so crawling may proceed."""
        Handler.routes = {"/page": (200, "<html>ok</html>")}
        assert client().allowed(f"{server}/page")

    def test_a_403_robots_does_not_lock_us_out(self, server):
        """The regression this rewrite exists for.

        urllib's parser reads 401/403 as a blanket disallow. A host that simply
        does not publish a robots.txt — and answers 403 rather than 404 — would
        become entirely unreachable, silently, with the run just reporting
        fewer products.
        """
        Handler.routes = {"/robots.txt": (403, "forbidden"), "/page": (200, "ok")}
        http = client()

        assert http.allowed(f"{server}/page")
        assert http.get(f"{server}/page") == "ok"

    def test_a_5xx_robots_is_treated_as_disallow(self, server):
        """Same section: 'unreachable' means back off, not push harder."""
        Handler.routes = {"/robots.txt": (503, "down"), "/page": (200, "ok")}
        assert not client().allowed(f"{server}/page")

    def test_robots_is_fetched_once_per_host(self, server):
        Handler.routes = {"/robots.txt": (200, ROBOTS_ALLOW_ALL), "/a": (200, "a"), "/b": (200, "b")}
        http = client()
        http.get(f"{server}/a")
        http.get(f"{server}/b")

        requested = [h for h in Handler.seen_headers]
        assert len(requested) == 3  # robots once, then both pages

    def test_ignore_robots_skips_the_check_entirely(self, server):
        Handler.routes = {"/robots.txt": (200, ROBOTS_DISALLOW), "/sa/en/c/x": (200, "listing")}
        http = client(respect_robots=False)
        assert http.get(f"{server}/sa/en/c/x") == "listing"


class TestFetching:
    def test_reports_the_url_after_a_redirect(self, server):
        Handler.routes = {
            "/robots.txt": (200, ROBOTS_ALLOW_ALL),
            "/old": (301, "/new"),
            "/new": (200, "landed"),
        }
        body, final_url = client().get_with_url(f"{server}/old")

        assert body == "landed"
        assert final_url == f"{server}/new"

    def test_a_404_raises_rather_than_retrying(self, server):
        Handler.routes = {"/robots.txt": (200, ROBOTS_ALLOW_ALL)}
        http = client()
        with pytest.raises(FetchError, match="404"):
            http.get(f"{server}/missing")
        assert http.stats.retries == 0

    def test_get_json_decodes(self, server):
        Handler.routes = {"/robots.txt": (200, ROBOTS_ALLOW_ALL), "/api": (200, '{"a": [1, 2]}')}
        assert client().get_json(f"{server}/api") == {"a": [1, 2]}

    def test_get_json_on_an_html_error_page_is_a_fetch_error(self, server):
        """An endpoint that has moved answers with HTML, not valid JSON."""
        Handler.routes = {"/robots.txt": (200, ROBOTS_ALLOW_ALL), "/api": (200, "<html>gone</html>")}
        with pytest.raises(FetchError, match="non-JSON"):
            client().get_json(f"{server}/api")


class TestHeaders:
    def test_identifies_itself_by_default(self, server):
        Handler.routes = {"/robots.txt": (200, ROBOTS_ALLOW_ALL), "/p": (200, "ok")}
        client().get(f"{server}/p")

        assert "FurnAppCatalogBot" in Handler.seen_headers[-1]["User-Agent"]

    def test_browser_profile_is_sent_when_asked_for(self, server):
        """Home Centre and Abyat answer the honest UA with a challenge page."""
        from furn_catalog.render import browser_headers

        Handler.routes = {"/robots.txt": (200, ROBOTS_ALLOW_ALL), "/p": (200, "ok")}
        client().get(f"{server}/p", headers=browser_headers())

        sent = Handler.seen_headers[-1]
        assert "Chrome/" in sent["User-Agent"]
        assert sent["Sec-Fetch-Mode"] == "navigate"

    def test_browser_headers_do_not_bypass_robots(self, server):
        """Looking like a browser must not change what we are allowed to fetch."""
        from furn_catalog.render import browser_headers

        Handler.routes = {"/robots.txt": (200, ROBOTS_DISALLOW)}
        with pytest.raises(RobotsDisallowed):
            client().get(f"{server}/sa/en/c/x", headers=browser_headers())


class TestCache:
    def test_second_fetch_comes_from_disk(self, server, tmp_path):
        Handler.routes = {"/robots.txt": (200, ROBOTS_ALLOW_ALL), "/p": (200, "cached body")}
        http = client(tmp_path)

        assert http.get(f"{server}/p") == "cached body"
        before = http.stats.requests_made
        assert http.get(f"{server}/p") == "cached body"

        assert http.stats.requests_made == before
        assert http.stats.cache_hits == 1

    def test_the_post_redirect_url_survives_the_cache(self, server, tmp_path):
        """The canonical URL is what the catalogue records; losing it on a cache
        hit would make a re-run disagree with the first run."""
        Handler.routes = {
            "/robots.txt": (200, ROBOTS_ALLOW_ALL),
            "/old": (301, "/new"),
            "/new": (200, "landed"),
        }
        http = client(tmp_path)
        first = http.get_with_url(f"{server}/old")
        second = http.get_with_url(f"{server}/old")

        assert first == second == ("landed", f"{server}/new")


class TestRobotsUnderABotFilter:
    """A UA-filtered site must not lock the scraper out of itself.

    Landmark answers an unrecognised User-Agent with `202` and a challenge page.
    robots.txt was fetched without the caller's header profile, so it got the
    challenge instead of the policy — and 202 is neither 200 nor 4xx nor 5xx, so
    it fell through to the disallow branch. Every URL on the host became
    forbidden before a single product was read, and the run reported "robots.txt
    disallows" as though the retailer had said so.
    """

    def test_robots_is_fetched_with_the_callers_headers(self, server):
        from furn_catalog.render import browser_headers

        Handler.routes = {
            "/robots.txt": (200, ROBOTS_ALLOW_ALL),
            "/sa/en/x/p/1234567": (200, "product"),
        }
        http = client()
        http.get(f"{server}/sa/en/x/p/1234567", headers=browser_headers())

        robots_request = Handler.seen_headers[0]
        assert "Chrome/" in robots_request["User-Agent"], (
            "robots.txt was fetched as the bot while pages are fetched as a "
            "browser — the policy read is not the policy governing our requests"
        )

    def test_a_2xx_challenge_page_is_not_a_policy(self, server):
        """202 + HTML states nothing. Reading a blanket ban out of a document
        with no directives in it is a guess, not compliance."""
        Handler.routes = {
            "/robots.txt": (202, "<html>Checking your browser…</html>"),
            "/page": (200, "ok"),
        }
        assert client().allowed(f"{server}/page")

    def test_a_200_that_is_not_robots_txt_is_not_a_policy(self, server):
        Handler.routes = {"/robots.txt": (200, "<!doctype html><h1>Not found</h1>"), "/page": (200, "ok")}
        assert client().allowed(f"{server}/page")

    def test_a_real_disallow_still_binds_under_the_same_path(self, server):
        """The permissive readings above must not weaken an actual directive."""
        Handler.routes = {"/robots.txt": (200, ROBOTS_DISALLOW)}
        http = client()
        assert not http.allowed(f"{server}/sa/en/c/furniture")
        with pytest.raises(RobotsDisallowed):
            http.get(f"{server}/sa/en/c/furniture")
