"""Tests for the configurable highlight.js theme (Config.highlightTheme).

Verifies that the resolved hl.js stylesheet is the one linked in the page,
that the file is written to the configured filename, and that custom
CssFile overrides land at the user-supplied path.
"""

from pathlib import Path

from bs4 import BeautifulSoup


def _doc(site_dir: Path, name: str) -> BeautifulSoup:
    html_path = site_dir / name / "index.html"
    assert html_path.exists(), f"Fixture not found at {html_path}. Run 'lake exe test-fixtures-build' first."
    with open(html_path) as f:
        return BeautifulSoup(f.read(), "html.parser")


def _stylesheet_hrefs(doc: BeautifulSoup) -> list[str]:
    return [link.get("href", "") for link in doc.select('head link[rel="stylesheet"]')]


class TestDefaultPairing:
    """`theme := "white"` (light) pairs with `.github` by default; no `.monokai`."""

    def test_github_link_present(self, site_dir):
        hrefs = _stylesheet_hrefs(_doc(site_dir, "hl-default"))
        assert "lib/github.css" in hrefs

    def test_monokai_not_linked(self, site_dir):
        hrefs = _stylesheet_hrefs(_doc(site_dir, "hl-default"))
        assert "lib/monokai.css" not in hrefs

    def test_legacy_plugin_path_not_linked(self, site_dir):
        """The hardcoded `lib/reveal.js/plugin/highlight/monokai.css` link is gone."""
        hrefs = _stylesheet_hrefs(_doc(site_dir, "hl-default"))
        assert "lib/reveal.js/plugin/highlight/monokai.css" not in hrefs

    def test_css_file_written(self, site_dir):
        assert (site_dir / "hl-default" / "lib" / "github.css").exists()


class TestBuiltinOverride:
    """An explicit `highlightTheme := .githubDark` overrides the default."""

    def test_overridden_link_present(self, site_dir):
        hrefs = _stylesheet_hrefs(_doc(site_dir, "hl-builtin"))
        assert "lib/github-dark.css" in hrefs

    def test_default_link_absent(self, site_dir):
        """`theme := "white"` would default to `.github`; the explicit override wins."""
        hrefs = _stylesheet_hrefs(_doc(site_dir, "hl-builtin"))
        assert "lib/github.css" not in hrefs

    def test_css_file_written(self, site_dir):
        assert (site_dir / "hl-builtin" / "lib" / "github-dark.css").exists()


class TestCustomCssFile:
    """A user-supplied CssFile is linked at its configured subpath and written verbatim."""

    HREF = "hl/my-hl.css"

    def test_custom_link_present(self, site_dir):
        hrefs = _stylesheet_hrefs(_doc(site_dir, "hl-custom"))
        assert self.HREF in hrefs

    def test_bundled_link_absent(self, site_dir):
        """No bundled hl.js stylesheet should be linked when the user supplies one."""
        hrefs = _stylesheet_hrefs(_doc(site_dir, "hl-custom"))
        for bundled in ("lib/monokai.css", "lib/github.css", "lib/github-dark.css"):
            assert bundled not in hrefs

    def test_custom_file_written(self, site_dir):
        path = site_dir / "hl-custom" / self.HREF
        assert path.exists()
        assert path.read_text() == ".hljs { background: #abcdef; }\n"
