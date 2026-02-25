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
