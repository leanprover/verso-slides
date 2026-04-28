"""Offline-rendering smoke tests for every bundled reveal.js theme.

Themes that referenced fonts via Google Fonts or expected upstream local fonts that were never
vendored produced 404s and font-fallbacks. The fix vendors every required font and rewrites the
upstream theme CSS to use local imports. These tests guard the offline guarantee by:

  1. Routing the browser so any request to a non-127.0.0.1 host is aborted.
  2. Recording every failed request.
  3. For each built-in theme, navigating to its minimal fixture and asserting reveal.js initialises
     and no resource fetch failed.

If any theme starts pulling fonts (or anything else) from the network again, the corresponding test
will fail with a list of the blocked URLs.
"""

from pathlib import Path

import pytest

from conftest import wait_for_reveal_ready


# Discover the bundled themes from the filesystem so this test stays in sync
# with whatever `TestFixtures/Build.lean` actually built. Each subdirectory
# of `_test/themes/` corresponds to one built-in theme name.
_THEMES_DIR = Path(__file__).parent.parent / "_test" / "themes"
BUNDLED_THEMES = sorted(p.name for p in _THEMES_DIR.iterdir() if p.is_dir()) \
    if _THEMES_DIR.exists() else []
assert BUNDLED_THEMES, (
    f"No theme fixtures found under {_THEMES_DIR}. "
    f"Run 'lake exe test-fixtures-build' first."
)


@pytest.mark.parametrize("theme", BUNDLED_THEMES)
def test_theme_loads_with_no_external_network(page, server, theme):
    """The deck for *theme* must render without any non-local network access."""
    blocked_urls: list[str] = []
    failed_requests: list[tuple[str, str]] = []

    def route_handler(route):
        url = route.request.url
        # Allow data: / blob: URIs (inlined fonts, etc.) and any 127.0.0.1
        # request served by our test HTTP server. Block everything else.
        if (
            url.startswith("data:")
            or url.startswith("blob:")
            or url.startswith("about:")
            or "127.0.0.1" in url
            or url.startswith("http://localhost")
        ):
            route.continue_()
        else:
            blocked_urls.append(url)
            route.abort()

    page.route("**/*", route_handler)
    page.on(
        "requestfailed",
        lambda req: failed_requests.append((req.url, req.failure or "unknown")),
    )

    try:
        page.goto(f"{server}/themes/{theme}/index.html")
        wait_for_reveal_ready(page)

        # The slide content must actually be visible. Verso renders the
        # level-1 slide heading as `<h2>` (the deck title is the implicit
        # `<h1>`). Case-insensitive: several themes apply
        # `text-transform: uppercase` to headings.
        heading = page.locator(".slides section h2").first
        assert heading.inner_text(timeout=5000).strip().lower() == "hello, theme", (
            f"Theme '{theme}' did not render the fixture heading."
        )

        # Failed requests we care about: anything OTHER than the ones we
        # deliberately blocked (those failures are expected). A non-blocked
        # failure means a local file 404'd — usually a missing vendored font.
        unexpected_failures = [
            (url, reason)
            for (url, reason) in failed_requests
            if url not in blocked_urls
        ]

        assert not blocked_urls, (
            f"Theme '{theme}' attempted external requests "
            f"(should be fully offline):\n  " + "\n  ".join(blocked_urls)
        )
        assert not unexpected_failures, (
            f"Theme '{theme}' had local resources fail to load:\n  "
            + "\n  ".join(f"{u}: {r}" for u, r in unexpected_failures)
        )
    finally:
        page.unroute("**/*")
