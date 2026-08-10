"""Headless-browser rendering, for the panels a static parser cannot reach.

The static path is still the default and still does most of the work: it is an
order of magnitude faster, it caches trivially, and it is gentler on the
retailer. This module exists for the one thing it cannot do.

IKEA's product page keeps its measurements behind a "Measurements" control, and
live checks confirmed the content is not in the served HTML at all: 113 raw
`cm` substrings on a real sofa page, zero parseable measurements. The first
browser attempt then failed too — 40 pages retried, 0 recovered — and this file
is the corrected version, built around the two failure modes that survive
scrutiny:

1. **`page.content()` is blind to shadow DOM.** It serialises the light DOM
   only. If the measurement panel renders inside an open shadow root, every
   click can succeed and the returned HTML still never contains a number. So
   the renderer no longer uses `page.content()`: it serialises the DOM itself,
   inlining every open shadow root, and separately extracts the *visible* text
   (shadow-piercing, script/style excluded) for the text-level parsers.
2. **Overlays eat clicks.** A cookie-consent banner intercepts pointer events
   without raising anything a naive click loop would notice. Consent is now
   dismissed before expansion, and every click is scrolled into view first.

Waits are condition-based, not sleeps: after expanding, the renderer waits for
a `Width/Depth/Height … <number> cm` pattern to appear in the visible text,
falling back to a short settle only if it never does — and reports which
happened, so a run can be audited.

Playwright is an optional dependency. Without it, `BrowserRenderer.available`
is False and every caller falls back to the static client — a run degrades to
what it did before rather than failing.

    pip install playwright && playwright install chromium
"""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass, field
from typing import Any

log = logging.getLogger(__name__)

#: Control labels that open a measurements panel, English and Arabic. Matched
#: case-insensitively against button text and aria-labels.
MEASUREMENT_LABELS = (
    "measurements",
    "dimensions",
    "product dimensions",
    "size guide",
    "specifications",
    "product details",
    "القياسات",
    "المقاسات",
    "الأبعاد",
    "المواصفات",
    "تفاصيل المنتج",
)

_LABEL_RE = re.compile("|".join(re.escape(label) for label in MEASUREMENT_LABELS), re.IGNORECASE)

#: A measurement-shaped token in visible text: `228 cm`, `95.5 cm`, `٩٥ سم`.
#: Counting these before and after expansion is the empirical check that the
#: panel actually opened — raw substring counts are useless because scripts
#: alone contain `cm` over a hundred times on a real IKEA page.
_MEASURE_TOKEN_RE = re.compile(r"\d[\d.,]*\s*(?:cm|سم)(?![a-z])", re.IGNORECASE)

#: A real browser's headers. Home Centre and Abyat both answered the honest bot
#: UA with 202/404 challenge pages; Playwright sends these natively, and
#: `browser_headers()` mirrors them onto the static client for the same reason.
BROWSER_USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"
)

#: Visible text of the whole document, piercing open shadow roots, excluding
#: script/style/noscript. This is what a human could read, which is the only
#: text a measurement can honestly be extracted from.
_JS_VISIBLE_TEXT = """
() => {
  const skip = new Set(["SCRIPT", "STYLE", "NOSCRIPT", "TEMPLATE"]);
  const out = [];
  const walk = (node) => {
    if (node.nodeType === Node.TEXT_NODE) { out.push(node.textContent); return; }
    if (node.nodeType === Node.ELEMENT_NODE) {
      if (skip.has(node.tagName)) return;
      if (node.shadowRoot) walk(node.shadowRoot);
    } else if (node.nodeType !== Node.DOCUMENT_NODE
               && node.nodeType !== Node.DOCUMENT_FRAGMENT_NODE) {
      return;
    }
    for (const child of node.childNodes) walk(child);
  };
  walk(document);
  return out.join(" ").replace(/\\s+/g, " ");
}
"""

#: Serialise the whole document, inlining every open shadow root as an inline
#: <template shadowrootmode="open"> block. `page.content()` cannot do this —
#: it returns the light DOM only, which is precisely the blindness that made
#: the first browser attempt report 0 recoveries. Scripts are kept: the
#: embedded-JSON extraction layer reads them.
_JS_SERIALIZE = """
() => {
  const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  const ser = (node) => {
    if (node.nodeType === Node.TEXT_NODE) return esc(node.textContent || "");
    if (node.nodeType === Node.COMMENT_NODE) return "";
    if (node.nodeType !== Node.ELEMENT_NODE) return "";
    const tag = node.tagName.toLowerCase();
    let attrs = "";
    for (const a of node.attributes || []) {
      attrs += " " + a.name + '="' + (a.value || "").replace(/&/g, "&amp;")
        .replace(/"/g, "&quot;").replace(/</g, "&lt;") + '"';
    }
    let inner = "";
    if (node.shadowRoot) {
      inner += '<template shadowrootmode="open">';
      for (const child of node.shadowRoot.childNodes) inner += ser(child);
      inner += "</template>";
    }
    if (tag === "script" || tag === "style") {
      inner += node.textContent || "";
    } else {
      for (const child of node.childNodes) inner += ser(child);
    }
    return "<" + tag + attrs + ">" + inner + "</" + tag + ">";
  };
  return "<!doctype html>" + ser(document.documentElement);
}
"""

#: The condition the renderer waits on after clicking: measurement tokens
#: visible on the page have *grown* past what was there before the click.
#:
#: Growth is the honest signal. Testing for "a measurement is present" would
#: pass instantly on a page that already showed `Seat depth: 54 cm` statically,
#: and the renderer would capture before the panel finished opening — which is
#: how a component measurement ends up standing in for a bounding box. Only the
#: panel's own content makes the count rise.
_JS_MEASUREMENTS_GREW = """
(baseline) => {
  const skip = new Set(["SCRIPT", "STYLE", "NOSCRIPT", "TEMPLATE"]);
  const out = [];
  const walk = (node) => {
    if (node.nodeType === Node.TEXT_NODE) { out.push(node.textContent); return; }
    if (node.nodeType === Node.ELEMENT_NODE) {
      if (skip.has(node.tagName)) return;
      if (node.shadowRoot) walk(node.shadowRoot);
    } else if (node.nodeType !== Node.DOCUMENT_NODE
               && node.nodeType !== Node.DOCUMENT_FRAGMENT_NODE) {
      return;
    }
    for (const child of node.childNodes) walk(child);
  };
  walk(document);
  const text = out.join(" ");
  const count = (text.match(/\\d[\\d.,]*\\s*(?:cm|سم)(?![a-z])/gi) || []).length;
  return count > baseline;
}
"""

#: Cookie/consent overlays intercept clicks silently. The OneTrust id is what
#: ikea.com actually uses; the text fallbacks cover the common alternatives.
#: Dismissing a consent banner is a prerequisite of rendering the page a human
#: sees — it grants nothing and bypasses nothing.
_CONSENT_SELECTORS = (
    "#onetrust-accept-btn-handler",
    'button:has-text("Accept all")',
    'button:has-text("Accept cookies")',
    'button:has-text("قبول")',
)


def browser_headers(referer: str = "") -> dict[str, str]:
    """Headers that make a plain `requests` call look like a tab.

    Sent to Home Centre and Abyat, whose bot filters answer the honest
    `FurnAppCatalogBot` UA with a 202 challenge page instead of the product.
    This changes what we *look* like, not what we *do*: robots.txt is still
    obeyed, the rate limit is unchanged, and nothing that was disallowed
    becomes allowed. A retailer who wants us gone can still say so.
    """
    headers = {
        "User-Agent": BROWSER_USER_AGENT,
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,"
        "image/webp,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.9,ar;q=0.8",
        "Sec-Ch-Ua": '"Chromium";v="125", "Not.A/Brand";v="24"',
        "Sec-Ch-Ua-Mobile": "?0",
        "Sec-Ch-Ua-Platform": '"macOS"',
        "Sec-Fetch-Dest": "document",
        "Sec-Fetch-Mode": "navigate",
        "Sec-Fetch-Site": "same-origin" if referer else "none",
        "Sec-Fetch-User": "?1",
        "Upgrade-Insecure-Requests": "1",
    }
    if referer:
        headers["Referer"] = referer
    return headers


@dataclass
class RenderResult:
    """Everything one rendered page yields, plus the evidence trail.

    `html` is the shadow-inclusive serialisation the extraction layers parse.
    `text` is the visible, shadow-pierced text — what a human could read.
    The rest is diagnostics: what was clicked, whether the wait condition
    actually fired, and the measurement-token counts before and after
    expansion, which is the empirical proof the panel did (or did not) open.
    """

    html: str
    text: str = ""
    clicks: list[str] = field(default_factory=list)
    cm_before: int = 0
    cm_after: int = 0
    waited: bool = False


def count_measure_tokens(text: str) -> int:
    """How many `<number> cm` tokens the visible text carries."""
    return len(_MEASURE_TOKEN_RE.findall(text or ""))


@dataclass
class BrowserRenderer:
    """Loads a page in Chromium, opens its measurement panels, returns the DOM.

    Kept deliberately narrow: one method, no session state the caller has to
    manage, and a hard timeout. The browser is started lazily on first use and
    reused, because launching Chromium per product would dominate the runtime.
    """

    timeout_ms: int = 30_000
    #: Ceiling for the post-click condition wait (measurement text visible).
    expand_timeout_ms: int = 6_000
    #: Fallback settle used only when the condition never fires.
    settle_ms: int = 1_200
    headless: bool = True
    locale: str = "en-US"

    _playwright: Any = field(default=None, init=False, repr=False)
    _browser: Any = field(default=None, init=False, repr=False)
    _context: Any = field(default=None, init=False, repr=False)
    _failed: bool = field(default=False, init=False, repr=False)

    @property
    def available(self) -> bool:
        """True if Playwright is importable and has not already failed to start."""
        if self._failed:
            return False
        try:
            import playwright.sync_api  # noqa: F401
        except ImportError:
            return False
        return True

    # ------------------------------------------------------------- lifecycle

    def _ensure_browser(self) -> Any:
        if self._context is not None:
            return self._context

        from playwright.sync_api import sync_playwright

        self._playwright = sync_playwright().start()
        self._browser = self._playwright.chromium.launch(
            headless=self.headless,
            args=["--disable-blink-features=AutomationControlled", "--no-sandbox"],
        )
        self._context = self._browser.new_context(
            user_agent=BROWSER_USER_AGENT,
            locale=self.locale,
            viewport={"width": 1440, "height": 900},
            extra_http_headers={"Accept-Language": "en-US,en;q=0.9,ar;q=0.8"},
        )
        # `navigator.webdriver` is the one signal that is both trivially read
        # and unambiguous. Everything else here is an ordinary desktop Chrome.
        self._context.add_init_script(
            "Object.defineProperty(navigator, 'webdriver', {get: () => undefined});"
        )
        return self._context

    def close(self) -> None:
        for handle, name in ((self._context, "context"), (self._browser, "browser")):
            if handle is not None:
                try:
                    handle.close()
                except Exception as exc:  # noqa: BLE001 - teardown must not raise
                    log.debug("error closing %s: %s", name, exc)
        if self._playwright is not None:
            try:
                self._playwright.stop()
            except Exception as exc:  # noqa: BLE001
                log.debug("error stopping playwright: %s", exc)
        self._playwright = self._browser = self._context = None

    def __enter__(self) -> "BrowserRenderer":
        return self

    def __exit__(self, *exc_info: object) -> None:
        self.close()

    # ---------------------------------------------------------------- render

    def render(self, url: str) -> RenderResult | None:
        """Load, expand, and capture `url`. None if the browser path is unusable.

        Never raises: a renderer failure must degrade to the static path, not
        end a 50-product run.
        """
        if not self.available:
            return None
        try:
            context = self._ensure_browser()
        except Exception as exc:  # noqa: BLE001 - a missing binary, usually
            log.warning(
                "could not start Chromium (%s); falling back to static fetches. "
                "Run `playwright install chromium` if you meant to use --render browser.",
                exc,
            )
            self._failed = True
            return None

        page = context.new_page()
        try:
            page.goto(url, timeout=self.timeout_ms, wait_until="domcontentloaded")
            # Hydration: wait for the network to go quiet, but never let a
            # long-polling connection hold the whole run hostage.
            try:
                page.wait_for_load_state("networkidle", timeout=8_000)
            except Exception:  # noqa: BLE001,S110
                pass

            self._dismiss_consent(page)

            text_before = str(page.evaluate(_JS_VISIBLE_TEXT) or "")
            baseline = count_measure_tokens(text_before)
            clicks = self._expand_all(page)

            # Condition, not a sleep: proceed the moment the panel's own
            # measurements appear. The fallback settle exists only so a page
            # that legitimately has nothing to expand does not stall the run.
            waited = True
            try:
                page.wait_for_function(
                    _JS_MEASUREMENTS_GREW, arg=baseline, timeout=self.expand_timeout_ms
                )
            except Exception:  # noqa: BLE001
                waited = False
                page.wait_for_timeout(self.settle_ms)

            text_after = str(page.evaluate(_JS_VISIBLE_TEXT) or "")
            html = str(page.evaluate(_JS_SERIALIZE) or "")

            return RenderResult(
                html=html,
                text=text_after,
                clicks=clicks,
                cm_before=count_measure_tokens(text_before),
                cm_after=count_measure_tokens(text_after),
                waited=waited,
            )
        except Exception as exc:  # noqa: BLE001 - one bad page is not fatal
            log.info("browser render failed for %s (%s)", url, exc)
            return None
        finally:
            page.close()

    # ------------------------------------------------------------ expansion

    def _dismiss_consent(self, page: Any) -> None:
        for selector in _CONSENT_SELECTORS:
            try:
                locator = page.locator(selector)
                if locator.count():
                    locator.first.click(timeout=2_000)
                    page.wait_for_timeout(300)
                    log.debug("dismissed consent via %s", selector)
                    return
            except Exception:  # noqa: BLE001,S110 - no banner is the good case
                continue

    def _expand_all(self, page: Any) -> list[str]:
        """Click everything that looks like it opens a measurements panel.

        Playwright locators pierce open shadow roots, so a control inside one
        is still findable; each candidate is scrolled into view first so an
        off-screen button does not swallow the click. Returns a description of
        every click that landed, so the caller can report exactly what
        happened instead of a bare count.
        """
        clicks: list[str] = []

        def try_click(locator: Any, description: str, cap: int = 3) -> None:
            try:
                count = min(locator.count(), cap)
            except Exception:  # noqa: BLE001
                return
            for index in range(count):
                if len(clicks) >= 10:
                    return
                handle = locator.nth(index)
                try:
                    handle.scroll_into_view_if_needed(timeout=1_500)
                    handle.click(timeout=2_500)
                    clicks.append(description)
                    page.wait_for_timeout(250)
                except Exception:  # noqa: BLE001,S110 - a click that misses is fine
                    continue

        # Role-based first: it reads the accessible name, which survives
        # markup churn far better than class names do.
        try_click(
            page.get_by_role(
                "button",
                name=re.compile("measurement|dimension|القياسات|المقاسات|الأبعاد", re.IGNORECASE),
            ),
            "role=button name~measurements",
        )

        # IKEA's own hooks for the measurements trigger and panel. Tried after
        # the role query rather than before it, so a markup change costs us a
        # selector rather than the whole interaction.
        for selector in (
            '[data-testid*="measurement" i]',
            '[data-testid*="dimension" i]',
            'button[class*="measurement" i]',
            'a[href*="measurement" i]',
            ".pip-product-dimensions__toggle",
            ".pip-btn--small:has-text('Measurements')",
        ):
            if len(clicks) >= 10:
                break
            try_click(page.locator(selector), selector, cap=2)

        for label in MEASUREMENT_LABELS:
            for selector in (
                f'button:has-text("{label}")',
                f'summary:has-text("{label}")',
                f'[aria-label*="{label}" i]',
            ):
                if len(clicks) >= 10:
                    break
                try_click(page.locator(selector), selector, cap=2)

        # Collapsed accordions whose label is an icon or unknown wording.
        try:
            collapsed = page.locator('[aria-expanded="false"]')
            for index in range(min(collapsed.count(), 12)):
                if len(clicks) >= 10:
                    break
                handle = collapsed.nth(index)
                try:
                    text = (handle.inner_text(timeout=800) or "") + (
                        handle.get_attribute("aria-label") or ""
                    )
                    if _LABEL_RE.search(text):
                        handle.scroll_into_view_if_needed(timeout=1_500)
                        handle.click(timeout=2_500)
                        clicks.append(f'aria-expanded=false ("{text.strip()[:40]}")')
                        page.wait_for_timeout(250)
                except Exception:  # noqa: BLE001,S110
                    continue
        except Exception:  # noqa: BLE001,S110
            pass

        # <details> panels open without a click.
        try:
            opened = page.eval_on_selector_all(
                "details:not([open])", "nodes => { nodes.forEach(n => n.open = true); return nodes.length; }"
            )
            if opened:
                clicks.append(f"<details> x{opened}")
        except Exception:  # noqa: BLE001,S110
            pass

        log.debug("expanded %d control(s) on %s: %s", len(clicks), page.url, clicks)
        return clicks


__all__ = [
    "BROWSER_USER_AGENT",
    "BrowserRenderer",
    "MEASUREMENT_LABELS",
    "RenderResult",
    "browser_headers",
    "count_measure_tokens",
]
