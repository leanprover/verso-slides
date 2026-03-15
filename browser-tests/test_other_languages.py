"""Browser tests for non-Lean code blocks (highlight.js integration)."""

from playwright.sync_api import expect, Page


class TestHighlightJs:
    def test_rust_code_block_highlighted(self, code_url: str, page: Page):
        """highlight.js should inject hljs-* spans into the Rust code block."""
        # Rust Code is slide index 8
        page.goto(f"{code_url}/index.html#/8")
        page.wait_for_load_state("networkidle")
        page.wait_for_timeout(1000)

        block = page.locator("pre > code.language-rust")
        expect(block).to_be_visible()

        # highlight.js adds class "hljs" to the <code> element after processing
        expect(block).to_have_class("language-rust hljs")

        # Should contain highlighted keyword tokens (fn, let, for, in)
        keywords = block.locator(".hljs-keyword")
        assert keywords.count() >= 3

        # Should contain highlighted string tokens (the format string)
        strings = block.locator(".hljs-string")
        assert strings.count() >= 1

        # Should contain the original source text
        text = block.inner_text()
        assert "fn main()" in text
        assert "vec!" in text

    def test_rust_block_has_box_styling(self, code_url: str, page: Page):
        """Rust code blocks should have box styling (border-radius, shadow)."""
        page.goto(f"{code_url}/index.html#/8")
        page.wait_for_load_state("networkidle")
        page.wait_for_timeout(1000)

        pre = page.locator("pre:has(> code.language-rust)")
        expect(pre).to_be_visible()

        border_radius = pre.evaluate("el => getComputedStyle(el).borderRadius")
        assert border_radius == "6px"
