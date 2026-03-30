"""Browser tests for /- !replace ... -/ magic comments."""

from conftest import goto_slide_by_title
from playwright.sync_api import expect, Page


class TestReplace:
    def test_replacement_text_visible(self, code_url: str, page: Page):
        """The replacement text '...' should appear in the rendered code."""
        slide = goto_slide_by_title(page, code_url, "Replace")

        code_block = slide.locator("code.hl.lean.block")
        expect(code_block).to_be_visible()

        text = code_block.inner_text()
        assert "..." in text

    def test_original_code_hidden(self, code_url: str, page: Page):
        """The original code between replace markers should not appear."""
        slide = goto_slide_by_title(page, code_url, "Replace")

        code_block = slide.locator("code.hl.lean.block")
        text = code_block.inner_text()

        # The hidden code (List.length [1, 2, 3]) should not be visible
        assert "List.length" not in text
        assert "[1, 2, 3]" not in text

    def test_surrounding_code_present(self, code_url: str, page: Page):
        """Code outside the replace markers should render normally."""
        slide = goto_slide_by_title(page, code_url, "Replace")

        code_block = slide.locator("code.hl.lean.block")
        text = code_block.inner_text()

        assert "def" in text
        assert "replaced" in text
        assert "Nat" in text
