"""A polite, cached HTTP client.

Scraping a live retail site badly is how you get blocked, so this layer is
deliberately conservative: it obeys robots.txt, rate-limits per host, retries
with exponential backoff on transient failures only, and caches every response
to disk so a re-run costs the retailer nothing.
"""

from __future__ import annotations

import hashlib
import json
import logging
import random
import threading
import time
import urllib.robotparser
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Mapping
from urllib.parse import urlparse

import requests

log = logging.getLogger(__name__)

DEFAULT_USER_AGENT = (
    "FurnAppCatalogBot/1.0 (+https://furn-app.com/bot; contact: data@furn-app.com) "
    "python-requests"
)

# Transient. Anything else (403, 404, 410) is a real answer and must not be retried.
_RETRY_STATUS = {408, 425, 429, 500, 502, 503, 504}


def _disallow_all() -> urllib.robotparser.RobotFileParser:
    parser = urllib.robotparser.RobotFileParser()
    parser.disallow_all = True
    return parser


class FetchError(RuntimeError):
    """A URL could not be retrieved after exhausting retries."""


class RobotsDisallowed(FetchError):
    """robots.txt forbids this path for our user agent."""


@dataclass
class FetchStats:
    requests_made: int = 0
    cache_hits: int = 0
    retries: int = 0
    failures: int = 0


@dataclass
class HttpClient:
    user_agent: str = DEFAULT_USER_AGENT
    cache_dir: Path | None = None
    # Seconds between requests to the same host. IKEA tolerates this fine; the
    # jitter keeps us from hammering in lockstep when running concurrently.
    delay: float = 1.0
    jitter: float = 0.4
    timeout: float = 30.0
    max_retries: int = 4
    respect_robots: bool = True

    _session: requests.Session = field(init=False, repr=False)
    _last_request: dict[str, float] = field(default_factory=dict, init=False, repr=False)
    _robots: dict[str, urllib.robotparser.RobotFileParser | None] = field(
        default_factory=dict, init=False, repr=False
    )
    _lock: threading.Lock = field(default_factory=threading.Lock, init=False, repr=False)
    stats: FetchStats = field(default_factory=FetchStats, init=False)

    def __post_init__(self) -> None:
        self._session = requests.Session()
        self._session.headers.update(
            {
                "User-Agent": self.user_agent,
                # Ask for the English locale explicitly. IKEA and Home Centre
                # both content-negotiate, and an Arabic response would fail the
                # English-only rule downstream.
                "Accept-Language": "en-US,en;q=0.9",
                "Accept": "text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8",
            }
        )
        if self.cache_dir:
            self.cache_dir.mkdir(parents=True, exist_ok=True)

    # ---------------------------------------------------------------- caching

    def _cache_path(self, url: str) -> Path | None:
        if not self.cache_dir:
            return None
        digest = hashlib.sha256(url.encode("utf-8")).hexdigest()[:32]
        return self.cache_dir / f"{digest}.html"

    def _read_cache(self, url: str) -> str | None:
        path = self._cache_path(url)
        if path and path.exists():
            self.stats.cache_hits += 1
            return path.read_text(encoding="utf-8")
        return None

    def _write_cache(self, url: str, body: str) -> None:
        path = self._cache_path(url)
        if path:
            path.write_text(body, encoding="utf-8")

    def _read_cache_url(self, url: str) -> str | None:
        """The post-redirect URL recorded alongside a cached body."""
        path = self._cache_path(url)
        if path:
            sidecar = path.with_suffix(".url")
            if sidecar.exists():
                return sidecar.read_text(encoding="utf-8").strip()
        return None

    def _write_cache_url(self, url: str, final_url: str) -> None:
        path = self._cache_path(url)
        if path:
            path.with_suffix(".url").write_text(final_url, encoding="utf-8")

    # ---------------------------------------------------------------- robots

    def _robots_for(self, url: str) -> urllib.robotparser.RobotFileParser | None:
        """Fetch and parse a host's robots.txt, following RFC 9309 status rules.

        We fetch it ourselves rather than calling `RobotFileParser.read()`,
        because that method treats 401/403 as a blanket *disallow*. RFC 9309
        §2.3.1.3 says the opposite: any 4xx is an "unavailable" status meaning
        no policy is published, and a crawler may proceed. That distinction
        matters for API hosts (IKEA's search backend among them) that serve no
        robots.txt at all and answer with 403 rather than 404 — urllib's rule
        would lock us out of a host that has published no objection.

        A 5xx is "unreachable" and *is* treated as a full disallow, per the
        same section: a host that is failing should not be crawled harder.
        """
        parsed = urlparse(url)
        origin = f"{parsed.scheme}://{parsed.netloc}"
        if origin in self._robots:
            return self._robots[origin]

        parser: urllib.robotparser.RobotFileParser | None = urllib.robotparser.RobotFileParser()
        robots_url = f"{origin}/robots.txt"
        parser.set_url(robots_url)  # type: ignore[union-attr]

        self._throttle(parsed.netloc)
        try:
            response = self._session.get(robots_url, timeout=self.timeout)
        except requests.RequestException as exc:
            log.warning("could not read %s (%s); proceeding politely", robots_url, exc)
            parser = None
        else:
            if response.status_code == 200:
                parser.parse(response.text.splitlines())  # type: ignore[union-attr]
            elif 400 <= response.status_code < 500:
                log.info(
                    "no robots.txt published at %s (HTTP %d); proceeding politely",
                    origin,
                    response.status_code,
                )
                parser = None
            else:
                log.warning(
                    "robots.txt at %s returned HTTP %d; treating the host as disallowed",
                    origin,
                    response.status_code,
                )
                parser = _disallow_all()

        self._robots[origin] = parser
        return parser

    def allowed(self, url: str) -> bool:
        if not self.respect_robots:
            return True
        parser = self._robots_for(url)
        if parser is None:
            return True
        return parser.can_fetch(self.user_agent, url)

    # ---------------------------------------------------------------- fetching

    def _throttle(self, host: str) -> None:
        with self._lock:
            last = self._last_request.get(host, 0.0)
            wait = (last + self.delay) - time.monotonic()
            if wait > 0:
                time.sleep(wait + random.uniform(0, self.jitter))
            self._last_request[host] = time.monotonic()

    def get(
        self, url: str, *, use_cache: bool = True, headers: Mapping[str, str] | None = None
    ) -> str:
        """Fetch a URL as text, honouring cache, robots.txt, and rate limits."""
        return self.get_with_url(url, use_cache=use_cache, headers=headers)[0]

    def get_json(
        self, url: str, *, use_cache: bool = True, headers: Mapping[str, str] | None = None
    ) -> Any:
        """Fetch and decode a JSON endpoint.

        A malformed body is a FetchError rather than a JSONDecodeError so
        callers only have one failure type to handle — an endpoint that has
        moved usually answers with an HTML error page, not valid JSON.
        """
        body = self.get(url, use_cache=use_cache, headers=headers)
        try:
            return json.loads(body)
        except json.JSONDecodeError as exc:
            raise FetchError(f"non-JSON response from {url}: {exc}") from exc

    def get_with_url(
        self, url: str, *, use_cache: bool = True, headers: Mapping[str, str] | None = None
    ) -> tuple[str, str]:
        """Fetch a URL, returning `(body, final_url)` after any redirects.

        The final URL matters: seed lists carry per-market slugs (US `gray` vs
        SA `grey`), and IKEA resolves by article number and redirects to the
        canonical path. The catalogue must record where we actually landed, not
        where we aimed.
        """
        if use_cache:
            cached = self._read_cache(url)
            if cached is not None:
                return cached, self._read_cache_url(url) or url

        if not self.allowed(url):
            raise RobotsDisallowed(f"robots.txt disallows {url}")

        host = urlparse(url).netloc
        last_error: Exception | None = None

        for attempt in range(self.max_retries + 1):
            self._throttle(host)
            try:
                response = self._session.get(url, timeout=self.timeout, headers=headers)
                self.stats.requests_made += 1
            except requests.RequestException as exc:
                last_error = exc
            else:
                if response.status_code == 200:
                    body = response.text
                    final_url = str(response.url)
                    if use_cache:
                        self._write_cache(url, body)
                        self._write_cache_url(url, final_url)
                    return body, final_url

                if response.status_code not in _RETRY_STATUS:
                    # 404 is the expected answer for a seed that isn't stocked
                    # in KSA. The caller drops it; there is nothing to retry.
                    self.stats.failures += 1
                    raise FetchError(f"HTTP {response.status_code} for {url}")

                last_error = FetchError(f"HTTP {response.status_code} for {url}")

            if attempt < self.max_retries:
                self.stats.retries += 1
                backoff = (2**attempt) + random.uniform(0, 1)
                log.debug("retry %d for %s in %.1fs (%s)", attempt + 1, url, backoff, last_error)
                time.sleep(backoff)

        self.stats.failures += 1
        raise FetchError(f"giving up on {url} after {self.max_retries} retries: {last_error}")

    def exists(self, url: str) -> bool:
        """True if the URL resolves. Used to validate seeds against the KSA site."""
        try:
            self.get(url)
        except FetchError:
            return False
        return True
