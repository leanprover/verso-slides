"""Browser tests for JS-dependent features (info panel, adaptive backgrounds)."""

from playwright.sync_api import expect, Page
from conftest import wait_for_reveal_ready


class TestInfoPanel:
    def test_click_shows_hover_info(self, code_url: str, page: Page):
        """Clicking a token with data-verso-hover should populate the info panel."""
        page.goto(f"{code_url}/index.html#/0")
        wait_for_reveal_ready(page)

        # Find the panel block
        block = page.locator(".code-with-panel").first
        panel = block.locator(".info-panel")
        expect(panel).to_be_visible()

        # Find a token with hover data and click it
        token = block.locator("[data-verso-hover]").first
        expect(token).to_be_visible()
        token.click()
        page.wait_for_timeout(500)

        # Panel should be populated
        expect(panel).not_to_be_empty()

    def test_docstring_markdown(self, code_url: str, page: Page):
        """Clicking IO.println should show a rendered docstring with HTML in the panel."""
        page.goto(f"{code_url}/index.html#/0")
        wait_for_reveal_ready(page)

        block = page.locator(".code-with-panel").first
        panel = block.locator(".info-panel")

        # Find IO.println token by text and click it
        token = block.locator(".const:has-text('IO.println')").first
        expect(token).to_be_visible()
        token.click()
        page.wait_for_timeout(500)

        # Docstring should be rendered as HTML, not raw markdown
        docstring = panel.locator(".docstring")
        expect(docstring).to_be_visible()
        inner_html = docstring.inner_html()
        assert "<code>" in inner_html or "<p>" in inner_html


class TestAdaptiveBackground:
    def test_code_bg_dark_slide(self, code_url: str, page: Page):
        """On a dark-themed slide, code blocks should have a light semi-transparent bg."""
        page.goto(f"{code_url}/index.html#/0")
        wait_for_reveal_ready(page)

        slide = page.locator(".slides > section").first
        code_block = slide.locator("code.hl.lean.block").first
        bg = code_block.evaluate("el => el.style.background")
        assert "255" in bg and "0.08" in bg, f"Expected light overlay, got: {bg}"

    def test_code_bg_light_slide(self, code_url: str, page: Page):
        """On a light-background slide, code blocks should have a dark semi-transparent bg."""
        page.goto(f"{code_url}/index.html#/1")
        wait_for_reveal_ready(page)

        slide = page.locator("section[data-background-color='#f5f5f5']")
        code_block = slide.locator("code.hl.lean.block").first
        bg = code_block.evaluate("el => el.style.background")
        assert "0, 0, 0" in bg, f"Expected dark overlay, got: {bg}"
