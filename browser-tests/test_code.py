"""Static HTML tests for elaborated Lean code blocks."""

from bs4 import BeautifulSoup
from playwright.sync_api import Page
from conftest import goto_slide_by_title


def _code_box_in_section(doc: BeautifulSoup, title: str):
    """Return the outermost code-box element on the slide with the given title.

    With the info panel on (the default), the stretch class lands on the
    ``.code-with-panel`` wrapper; without it, on the bare ``code.hl.lean.block``.
    """
    for s in doc.select("section"):
        h = s.select_one("h1, h2, h3")
        if h and h.get_text().strip() == title:
            return s.select_one(".code-with-panel") or s.select_one("code.hl.lean.block")
    return None


class TestCodeBlocks:
    def test_code_blocks_present(self, code_doc: BeautifulSoup):
        """Elaborated Lean code blocks should render as <code class='hl lean block'>."""
        blocks = code_doc.select("code.hl.lean.block")
        assert len(blocks) >= 3  # hello def, #check hello, greet def + #eval

    def test_keyword_tokens(self, code_doc: BeautifulSoup):
        """Code blocks should contain keyword tokens."""
        keywords = code_doc.select("code.hl.lean.block .keyword")
        keyword_texts = [kw.get_text() for kw in keywords]
        assert "def" in keyword_texts
        assert "do" in keyword_texts

    def test_const_tokens(self, code_doc: BeautifulSoup):
        """Code blocks should contain const tokens for named definitions."""
        consts = code_doc.select("code.hl.lean.block .const")
        const_texts = [c.get_text() for c in consts]
        assert "hello" in const_texts
        assert "IO.println" in const_texts
        assert "greet" in const_texts

    def test_string_literal_tokens(self, code_doc: BeautifulSoup):
        """Code blocks should contain string literal tokens."""
        literals = code_doc.select("code.hl.lean.block .literal.string")
        literal_texts = [lit.get_text() for lit in literals]
        assert any("Hello from VersoSlides!" in t for t in literal_texts)

    def test_var_tokens(self, code_doc: BeautifulSoup):
        """Code blocks should contain variable tokens."""
        vars_ = code_doc.select("code.hl.lean.block .var")
        var_texts = [v.get_text() for v in vars_]
        assert "name" in var_texts

    def test_hover_attributes(self, code_doc: BeautifulSoup):
        """Tokens should have data-verso-hover attributes for tooltip data."""
        hover_tokens = code_doc.select("code.hl.lean.block [data-verso-hover]")
        assert len(hover_tokens) >= 5

    def test_diagnostic_info(self, code_doc: BeautifulSoup):
        """#check and #eval commands should produce diagnostic info spans."""
        info_spans = code_doc.select("code.hl.lean.block .has-info.information")
        assert len(info_spans) >= 2  # #check hello, #eval greet "Lean"

    def test_stretch_default_has_class(self, code_doc: BeautifulSoup):
        """A code box defaults to filling vertical space (carries r-stretch)."""
        box = _code_box_in_section(code_doc, "Stretch Default")
        assert box is not None, "Stretch Default slide not found"
        assert "r-stretch" in box.get("class", [])

    def test_stretch_off_omits_class(self, code_doc: BeautifulSoup):
        """The -stretch flag opts out, so the box is content-sized (no r-stretch)."""
        box = _code_box_in_section(code_doc, "Stretch Off")
        assert box is not None, "Stretch Off slide not found"
        assert "r-stretch" not in box.get("class", [])

    def test_error_block_renders(self, code_doc: BeautifulSoup):
        """A code block with +error should render with error diagnostics as warnings."""
        # Find the slide titled "Expected Error"
        sections = code_doc.select("section")
        error_section = None
        for s in sections:
            h = s.select_one("h1, h2, h3")
            if h and "Expected Error" in h.get_text():
                error_section = s
                break
        assert error_section is not None, "Expected Error slide not found"
        # The code block should be rendered
        code_block = error_section.select_one("code.hl.lean.block")
        assert code_block is not None, "Code block not rendered in +error slide"
        # Should contain the #check token
        tokens = code_block.get_text()
        assert "#check" in tokens


class TestStretchLayout:
    """Browser-rendered layout tests for the vertical-stretch behaviour."""

    def _heights(self, page: Page, code_url: str, title: str):
        """Return (code box height, enclosing section height) in on-screen px."""
        section = goto_slide_by_title(page, code_url, title)
        section_box = section.bounding_box()
        code_box = section.locator("code.hl.lean.block").first.bounding_box()
        assert code_box is not None, f"Code box not visible on slide '{title}'"
        assert section_box is not None, f"Section not visible on slide '{title}'"
        return code_box["height"], section_box["height"]

    def test_stretched_box_fills_more_than_content(self, code_url: str, page: Page):
        """The default (stretched) box is much taller than the same one-line
        snippet rendered with -stretch, and fills a large share of the slide."""
        stretched, section_h = self._heights(page, code_url, "Stretch Default")
        unstretched, _ = self._heights(page, code_url, "Stretch Off")
        # Both boxes hold a single short def; stretched should be far taller.
        assert stretched > unstretched * 3, (
            f"stretched={stretched} not much taller than unstretched={unstretched}"
        )
        # The stretched box should fill a large fraction of its slide. The
        # section and the box are scaled by the same reveal transform, so the
        # ratio is independent of the on-screen scale.
        assert stretched > section_h * 0.5, (
            f"stretched box height {stretched} did not fill section height {section_h}"
        )
