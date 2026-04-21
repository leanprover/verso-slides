"""Tests for the custom-theme fixture (Config.theme := .custom ...).

Verifies that a user-supplied CustomTheme replaces the vendored reveal.js
theme, that subdirectories in the stylesheet/asset/extraCss filenames are
honored, that the bundled theme assets (from `include_bin_dir`) are written
and actually fetchable from the browser, and that the custom rules are
applied in the rendered page.
"""

import requests

from bs4 import BeautifulSoup
from conftest import goto_slide_by_title


THEME_HREF = "theme/custom.css"
EXTRA_HREF = "css/extra.css"
ASSET_PATH = "theme-assets/marker.png"


class TestCustomThemeStatic:
    def test_theme_file_copied_to_subdir(self, site_dir):
        """.custom theme's CssFile is written at the configured subpath."""
        assert (site_dir / "theme" / "theme" / "custom.css").exists()

    def test_extra_css_file_copied_to_subdir(self, site_dir):
        """extraCss subpath is honored alongside a custom theme."""
        assert (site_dir / "theme" / "css" / "extra.css").exists()

    def test_theme_link_in_head(self, theme_doc: BeautifulSoup):
        """The theme <link> must point at the custom CssFile, not the vendored theme."""
        selector = f'head link[rel="stylesheet"][href="{THEME_HREF}"]'
        links = theme_doc.select(selector)
        assert len(links) == 1

    def test_no_vendored_theme_link(self, theme_doc: BeautifulSoup):
        """With theme := .custom, the vendored theme link must NOT be emitted."""
        links = theme_doc.select('head link[rel="stylesheet"]')
        hrefs = [link.get("href", "") for link in links]
        vendored_theme_hrefs = [h for h in hrefs if h.startswith("lib/reveal.js/dist/theme/")]
        assert vendored_theme_hrefs == [], (
            f"Expected no vendored theme link, got: {vendored_theme_hrefs}"
        )

    def test_extra_css_link_in_head(self, theme_doc: BeautifulSoup):
        """config.extraCss should still emit its subdir href alongside the custom theme."""
        selector = f'head link[rel="stylesheet"][href="{EXTRA_HREF}"]'
        links = theme_doc.select(selector)
        assert len(links) == 1


class TestCustomThemeComputedStyle:
    def test_theme_rule_applied(self, page, theme_url):
        """A rule defined inside the custom theme stylesheet is applied."""
        slide = goto_slide_by_title(page, theme_url, "Custom Theme")
        marker = slide.locator("p.theme-marker")
        assert marker.count() == 1
        color = marker.evaluate("el => getComputedStyle(el).color")
        assert color == "rgb(255, 200, 0)"

    def test_extra_css_rule_applied(self, page, theme_url):
        """A rule from the subdir extraCss entry is also applied in the same page."""
        slide = goto_slide_by_title(page, theme_url, "Custom Theme")
        marker = slide.locator("p.extra-marker")
        assert marker.count() == 1
        bg = marker.evaluate("el => getComputedStyle(el).backgroundColor")
        assert bg == "rgb(40, 80, 120)"


class TestCustomThemeAssets:
    """A custom theme can bundle companion files (images, fonts, etc.)."""

    def test_asset_file_written(self, site_dir):
        """Assets from include_bin_dir are written to the configured path."""
        assert (site_dir / "theme" / ASSET_PATH).exists()
        # And the byte contents must match the source file (i.e. the bundle
        # round-trips through include_bin_dir's Z85 encoding without corruption).
        source = site_dir.parent / "TestFixtures" / ASSET_PATH
        assert source.exists()
        assert (site_dir / "theme" / ASSET_PATH).read_bytes() == source.read_bytes()

    def test_asset_fetchable_over_http(self, server):
        """The asset must be reachable via HTTP so the theme CSS can load it."""
        url = f"{server}/theme/{ASSET_PATH}"
        resp = requests.get(url)
        assert resp.status_code == 200
        assert resp.headers.get("Content-Type", "").startswith("image/")

    def test_asset_referenced_via_background_image(self, page, theme_url):
        """An element styled by the theme CSS must resolve the bundled URL.

        `getComputedStyle(el).backgroundImage` returns the resolved absolute
        URL. We assert that the URL ends at the configured asset path, which
        would only succeed if the browser actually located the file.
        """
        slide = goto_slide_by_title(page, theme_url, "Custom Theme")
        marker = slide.locator("p.asset-marker")
        assert marker.count() == 1
        bg = marker.evaluate("el => getComputedStyle(el).backgroundImage")
        assert ASSET_PATH in bg, f"Expected {ASSET_PATH!r} in background-image, got {bg!r}"
