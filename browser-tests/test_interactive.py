"""Browser tests for JS-dependent features (info panel, adaptive backgrounds)."""

from playwright.sync_api import expect, Page
from conftest import (
    assert_docstring_markup_is_text,
    assert_docstring_structure,
    hold_hover_docs,
    goto_slide_by_title,
)


class TestInfoPanel:
    def test_click_shows_hover_info(self, code_url: str, page: Page):
        """Clicking a token with data-verso-hover should populate the info panel."""
        slide = goto_slide_by_title(page, code_url, "Dark Code")

        # Find the panel block
        block = slide.locator(".code-with-panel").first
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
        slide = goto_slide_by_title(page, code_url, "Dark Code")

        block = slide.locator(".code-with-panel").first
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

    def test_click_before_hover_docs_load(self, code_url: str, page: Page):
        """A token clicked while the hover data is loading should show its hover
        in the panel once the data arrives."""
        release = hold_hover_docs(page)
        slide = goto_slide_by_title(page, code_url, "Dark Code")

        block = slide.locator(".code-with-panel").first
        panel = block.locator(".info-panel")
        block.locator(".const:has-text('IO.println')").first.click()
        expect(panel).to_be_empty()

        release()
        expect(panel.locator(".docstring")).to_be_visible()

    def test_docstring_markup_is_text(self, code_url: str, page: Page):
        """HTML tags written in a docstring should show in the panel as text."""
        slide = goto_slide_by_title(page, code_url, "Docstring Markup")

        block = slide.locator(".code-with-panel").first
        panel = block.locator(".info-panel")
        block.locator(".const:has-text('imgTag')").last.click()

        docstring = panel.locator(".docstring")
        expect(docstring).to_be_visible()
        assert_docstring_markup_is_text(docstring)

    def test_docstring_structure(self, code_url: str, page: Page):
        """A docstring's Markdown and math should show in the panel as HTML and KaTeX."""
        slide = goto_slide_by_title(page, code_url, "Docstring Structure")

        block = slide.locator(".code-with-panel").first
        panel = block.locator(".info-panel")
        block.locator(".const:has-text('bump')").last.click()

        docstring = panel.locator(".docstring")
        expect(docstring).to_be_visible()
        assert_docstring_structure(docstring)


class TestAdaptiveBackground:
    def test_code_bg_dark_slide(self, code_url: str, page: Page):
        """On a dark-themed slide, code blocks should have a light semi-transparent bg."""
        slide = goto_slide_by_title(page, code_url, "Dark Code")

        code_block = slide.locator("code.hl.lean.block").first
        bg = code_block.evaluate("el => el.style.background")
        assert "255" in bg and "0.08" in bg, f"Expected light overlay, got: {bg}"

    def test_code_bg_light_slide(self, code_url: str, page: Page):
        """On a light-background slide, code blocks should have a dark semi-transparent bg."""
        slide = goto_slide_by_title(page, code_url, "Light Code")

        code_block = slide.locator("code.hl.lean.block").first
        bg = code_block.evaluate("el => el.style.background")
        assert "0, 0, 0" in bg, f"Expected dark overlay, got: {bg}"
