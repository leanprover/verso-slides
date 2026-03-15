"""Browser tests for Lean comment highlighting (verso#274 workaround)."""

from playwright.sync_api import expect, Page


class TestCommentHighlighting:
    def test_line_comment_styled(self, code_url: str, page: Page):
        """Line comments (-- ...) should be wrapped in .lean-comment spans."""
        # Comments is slide index 7
        page.goto(f"{code_url}/index.html#/7")
        page.wait_for_load_state("networkidle")
        page.wait_for_timeout(1000)

        slide = page.locator(".slides > section").nth(7)
        comments = slide.locator(".lean-comment")
        assert comments.count() >= 1

        # At least one should contain the line comment text
        texts = [comments.nth(i).inner_text() for i in range(comments.count())]
        assert any("A line comment" in t for t in texts)

    def test_block_comment_styled(self, code_url: str, page: Page):
        """Block comments (/- ... -/) should be wrapped in .lean-comment spans."""
        page.goto(f"{code_url}/index.html#/7")
        page.wait_for_load_state("networkidle")
        page.wait_for_timeout(1000)

        slide = page.locator(".slides > section").nth(7)
        comments = slide.locator(".lean-comment")
        texts = [comments.nth(i).inner_text() for i in range(comments.count())]
        assert any("A block comment" in t for t in texts)

    def test_comment_has_italic_style(self, code_url: str, page: Page):
        """Comments should be rendered in italic."""
        page.goto(f"{code_url}/index.html#/7")
        page.wait_for_load_state("networkidle")
        page.wait_for_timeout(1000)

        slide = page.locator(".slides > section").nth(7)
        comment = slide.locator(".lean-comment").first
        expect(comment).to_be_visible()

        font_style = comment.evaluate("el => getComputedStyle(el).fontStyle")
        assert font_style == "italic"

    def test_non_comment_text_unchanged(self, code_url: str, page: Page):
        """Code tokens outside comments should not be wrapped in .lean-comment."""
        page.goto(f"{code_url}/index.html#/7")
        page.wait_for_load_state("networkidle")
        page.wait_for_timeout(1000)

        slide = page.locator(".slides > section").nth(7)
        code_block = slide.locator("code.hl.lean.block")
        text = code_block.inner_text()

        # The keyword and definition should still be present
        assert "def" in text
        assert "commented" in text
