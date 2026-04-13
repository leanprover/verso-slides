"""Browser tests for empty and comment-only Lean code blocks."""

from conftest import goto_slide_by_title
from playwright.sync_api import Page


class TestEmptyCodeBlocks:
    def test_empty_code_block_no_error(self, code_url: str, page: Page):
        """An empty ```lean code block should produce a slide without errors."""
        slide = goto_slide_by_title(page, code_url, "Empty Code Block")
        # The slide should exist and have a heading
        heading = slide.locator("h1, h2, h3").first
        assert "empty code block" in heading.inner_text().lower()

    def test_whitespace_only_code_block_no_error(self, code_url: str, page: Page):
        """A ```lean code block with only newlines should produce a slide without errors."""
        slide = goto_slide_by_title(page, code_url, "Whitespace-Only Code Block")
        heading = slide.locator("h1, h2, h3").first
        assert "whitespace-only code block" in heading.inner_text().lower()

    def test_comment_only_code_block_renders(self, code_url: str, page: Page):
        """A ```lean code block with only a comment should render the comment text."""
        slide = goto_slide_by_title(page, code_url, "Comment-Only Code Block")
        code_block = slide.locator("code.hl.lean.block")
        assert code_block.count() >= 1
        text = code_block.first.inner_text()
        assert "This comment stands alone" in text
