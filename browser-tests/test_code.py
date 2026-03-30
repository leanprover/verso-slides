"""Static HTML tests for elaborated Lean code blocks."""

from bs4 import BeautifulSoup


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
