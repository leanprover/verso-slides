"""Tests for inline and display math rendering via KaTeX."""

from bs4 import BeautifulSoup

from conftest import goto_slide_by_title


class TestMathMarkup:
    def test_inline_math_emitted(self, markup_doc: BeautifulSoup):
        """Inline $`...` sources produce <code class="math inline">TEX</code>."""
        nodes = markup_doc.select("code.math.inline")
        assert len(nodes) >= 2, f"expected at least two inline math nodes, got {len(nodes)}"
        tex = [n.get_text() for n in nodes]
        assert r"e^{i\pi} + 1 = 0" in tex, f"missing Euler identity source, got {tex}"

    def test_display_math_emitted(self, markup_doc: BeautifulSoup):
        """Display $$`...` sources produce <code class="math display">TEX</code>."""
        nodes = markup_doc.select("code.math.display")
        assert len(nodes) >= 1, f"expected at least one display math node, got {len(nodes)}"
        tex = nodes[0].get_text()
        assert r"\int_0^\infty" in tex, f"display math TeX missing integral, got {tex!r}"

    def test_math_style_link_in_head(self, markup_doc: BeautifulSoup):
        """The page head should link KaTeX's stylesheet."""
        links = markup_doc.select('head link[href$="katex.min.css"]')
        assert len(links) == 1, f"expected one KaTeX stylesheet link, got {len(links)}"

    def test_math_script_tags_present(self, markup_doc: BeautifulSoup):
        """The page body should load KaTeX and our math.js renderer."""
        scripts = [s.get("src", "") for s in markup_doc.select("script[src]")]
        assert any(s.endswith("katex/dist/katex.min.js") for s in scripts), \
            f"KaTeX JS not loaded, scripts: {scripts}"
        assert any(s.endswith("lib/math.js") for s in scripts), \
            f"math.js not loaded, scripts: {scripts}"

    def test_math_prelude_script_emitted(self, markup_doc: BeautifulSoup):
        """When Config.mathPrelude is non-empty, a <script> sets window.__versoMathPrelude."""
        inline_scripts = [s.get_text() for s in markup_doc.select("script") if not s.get("src")]
        prelude_scripts = [s for s in inline_scripts if "__versoMathPrelude" in s]
        assert len(prelude_scripts) == 1, \
            f"expected one prelude <script>, got {len(prelude_scripts)}"
        body = prelude_scripts[0]
        assert "\\\\def\\\\RR" in body or "\\def\\RR" in body, \
            f"prelude script missing \\RR definition, got: {body!r}"

    def test_old_reveal_math_plugin_not_wired(self, markup_doc: BeautifulSoup):
        """The reveal.js math plugin's auto-render skips <code> tags, so it's unused.

        The initialize() call should not reference RevealMath.KaTeX, and the
        plugin/math/math.js asset should not be loaded as a <script>.
        """
        scripts = markup_doc.select("script")
        init_text = "\n".join(s.get_text() for s in scripts if not s.get("src"))
        assert "RevealMath" not in init_text, \
            f"Reveal math plugin should not be registered, found reference in init script"
        srcs = [s.get("src", "") for s in scripts if s.get("src")]
        assert not any(s.endswith("plugin/math/math.js") for s in srcs), \
            f"reveal.js math plugin should not be loaded, scripts: {srcs}"


class TestMathAssets:
    def test_math_js_written(self, site_dir):
        """lib/math.js should be written to every fixture output dir."""
        path = site_dir / "markup" / "lib" / "math.js"
        assert path.exists(), f"Expected math.js at {path}"
        body = path.read_text()
        assert "katex.render" in body, "math.js should call katex.render"
        assert "code.math.inline" in body, "math.js should select inline math"
        assert "code.math.display" in body, "math.js should select display math"

    def test_katex_assets_written(self, site_dir):
        """Vendored KaTeX CSS, JS, and fonts should be written alongside the output."""
        lib = site_dir / "markup" / "lib" / "katex" / "dist"
        assert (lib / "katex.min.css").exists(), "katex.min.css missing"
        assert (lib / "katex.min.js").exists(), "katex.min.js missing"
        fonts = list((lib / "fonts").iterdir())
        assert len(fonts) > 0, "expected at least one KaTeX font file"


class TestMathRendering:
    """In-browser tests that KaTeX actually runs and produces rendered output."""

    def test_inline_math_is_rendered(self, page, markup_url):
        """After load, each inline math node contains a .katex element."""
        goto_slide_by_title(page, markup_url, "Math")
        # Wait for math.js to finish its DOMContentLoaded pass.
        page.wait_for_function(
            "() => document.querySelectorAll('code.math.inline .katex').length > 0",
            timeout=5000,
        )
        rendered = page.evaluate(
            "() => Array.from(document.querySelectorAll('code.math.inline'))"
            "       .every(n => n.querySelector('.katex') !== null)"
        )
        assert rendered, "every inline math node should contain a .katex element after render"

    def test_display_math_is_rendered(self, page, markup_url):
        """Display math nodes contain a .katex-display wrapper."""
        goto_slide_by_title(page, markup_url, "Math")
        page.wait_for_function(
            "() => document.querySelector('code.math.display .katex-display') !== null",
            timeout=5000,
        )

    def test_math_prelude_macros_expand(self, page, markup_url):
        """Macros defined in Config.mathPrelude are available to all math on the page.

        The markup fixture's Config sets `\\def\\RR{\\mathbb{R}}`. After render, the
        math slide should contain a KaTeX `.mathbb` span, which only appears when
        `\\RR` successfully expanded — an unexpanded control sequence would render
        as error text.
        """
        goto_slide_by_title(page, markup_url, "Math")
        page.wait_for_function(
            "() => document.querySelectorAll('code.math.inline .katex').length > 0",
            timeout=5000,
        )
        has_blackboard = page.evaluate(
            "() => document.querySelector('code.math .mathbb') !== null"
        )
        assert has_blackboard, (
            "no .mathbb span found — prelude macro \\RR did not expand"
        )

    def test_math_tex_source_not_visible(self, page, markup_url):
        """Raw TeX source (backslashes) should not appear in the visible DOM text."""
        goto_slide_by_title(page, markup_url, "Math")
        page.wait_for_function(
            "() => document.querySelectorAll('code.math.inline .katex').length > 0",
            timeout=5000,
        )
        # After KaTeX renders, node.textContent still contains the MathML
        # fallback text, but the original raw TeX string is gone. Check that
        # the inline math nodes no longer carry the literal TeX as their
        # sole contents (i.e., rendering replaced the text child).
        leftover = page.evaluate(
            r"""() => {
                const nodes = document.querySelectorAll('code.math.inline');
                for (const n of nodes) {
                    // Unrendered nodes have exactly one text-node child.
                    if (n.childNodes.length === 1
                        && n.childNodes[0].nodeType === Node.TEXT_NODE) {
                        return n.textContent;
                    }
                }
                return null;
            }"""
        )
        assert leftover is None, f"found unrendered inline math: {leftover!r}"
