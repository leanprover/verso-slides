"""Browser tests for the inline Lean term lightbox overlay."""

from playwright.sync_api import expect, Page
from conftest import wait_for_reveal_ready


class TestLightboxOpen:
    def test_click_inline_token_opens_lightbox(self, code_url: str, page: Page):
        """Clicking a data-verso-hover token in inline code should open a lightbox."""
        page.goto(f"{code_url}/index.html#/3")
        wait_for_reveal_ready(page)

        # Find an inline lean code element
        inline = page.locator("code.hl.lean.inline").first
        expect(inline).to_be_visible()

        # Click a token with hover data inside it
        token = inline.locator("[data-verso-hover]").first
        expect(token).to_be_visible()
        token.click()
        page.wait_for_timeout(500)

        # Lightbox overlay should appear
        overlay = page.locator(".r-overlay-lean-hover")
        expect(overlay).to_be_visible()

    def test_lightbox_has_content(self, code_url: str, page: Page):
        """The lightbox should contain hover information."""
        page.goto(f"{code_url}/index.html#/3")
        wait_for_reveal_ready(page)

        token = page.locator("code.hl.lean.inline [data-verso-hover]").first
        token.click()
        page.wait_for_timeout(500)

        inner = page.locator(".lean-hover-inner")
        expect(inner).to_be_visible()
        assert inner.inner_html().strip() != "", "Lightbox content should not be empty"

    def test_lightbox_monospace_font(self, code_url: str, page: Page):
        """Lightbox content should use a monospace font."""
        page.goto(f"{code_url}/index.html#/3")
        wait_for_reveal_ready(page)

        token = page.locator("code.hl.lean.inline [data-verso-hover]").first
        token.click()
        page.wait_for_timeout(500)

        inner = page.locator(".lean-hover-inner")
        font = inner.evaluate("el => getComputedStyle(el).fontFamily")
        assert "monospace" in font.lower(), f"Expected monospace font, got: {font}"


class TestLightboxClose:
    def _open_lightbox(self, page: Page, code_url: str):
        """Helper to navigate and open a lightbox."""
        page.goto(f"{code_url}/index.html#/3")
        wait_for_reveal_ready(page)
        token = page.locator("code.hl.lean.inline [data-verso-hover]").first
        token.click()
        page.wait_for_timeout(500)
        expect(page.locator(".r-overlay-lean-hover")).to_be_visible()

    def test_escape_closes_lightbox(self, code_url: str, page: Page):
        """Pressing Escape should close the lightbox."""
        self._open_lightbox(page, code_url)
        page.keyboard.press("Escape")
        page.wait_for_timeout(300)
        expect(page.locator(".r-overlay-lean-hover")).to_have_count(0)

    def test_escape_does_not_toggle_overview(self, code_url: str, page: Page):
        """Pressing Escape to close the lightbox should not open reveal.js overview."""
        self._open_lightbox(page, code_url)
        page.keyboard.press("Escape")
        page.wait_for_timeout(500)

        # Overview mode adds .overview class to .reveal
        is_overview = page.locator(".reveal.overview").count()
        assert is_overview == 0, "Overview should not be triggered by Escape closing lightbox"

    def test_backdrop_click_closes_lightbox(self, code_url: str, page: Page):
        """Clicking the backdrop (outside lightbox) should close it."""
        self._open_lightbox(page, code_url)

        # Click the backdrop element
        backdrop = page.locator(".lean-hover-backdrop")
        expect(backdrop).to_be_visible()
        backdrop.click(position={"x": 10, "y": 10})
        page.wait_for_timeout(300)
        expect(page.locator(".r-overlay-lean-hover")).to_have_count(0)

    def test_slide_change_closes_lightbox(self, code_url: str, page: Page):
        """Navigating to another slide should close the lightbox."""
        self._open_lightbox(page, code_url)

        # Navigate to next slide
        page.keyboard.press("ArrowRight")
        page.wait_for_timeout(500)
        expect(page.locator(".r-overlay-lean-hover")).to_have_count(0)


class TestLightboxSizing:
    def test_lightbox_width(self, code_url: str, page: Page):
        """Lightbox should be 75% of the slide width."""
        page.goto(f"{code_url}/index.html#/3")
        wait_for_reveal_ready(page)

        token = page.locator("code.hl.lean.inline [data-verso-hover]").first
        token.click()
        page.wait_for_timeout(500)

        overlay = page.locator(".r-overlay-lean-hover")
        reveal = page.locator(".reveal")
        overlay_width = overlay.bounding_box()["width"]
        reveal_width = reveal.bounding_box()["width"]

        ratio = overlay_width / reveal_width
        assert 0.70 <= ratio <= 0.80, f"Expected ~75% width ratio, got {ratio:.2f}"

    def test_lightbox_scrollable_when_tall(self, code_url: str, page: Page):
        """Lightbox with overflow-y: auto should allow scrolling if content is tall."""
        page.goto(f"{code_url}/index.html#/3")
        wait_for_reveal_ready(page)

        token = page.locator("code.hl.lean.inline [data-verso-hover]").first
        token.click()
        page.wait_for_timeout(500)

        overlay = page.locator(".r-overlay-lean-hover")
        overflow = overlay.evaluate("el => getComputedStyle(el).overflowY")
        assert overflow == "auto", f"Expected overflow-y: auto, got: {overflow}"


class TestTippySuppression:
    def test_no_tippy_on_inline_code(self, code_url: str, page: Page):
        """Hovering an inline Lean token should not create a Tippy tooltip."""
        page.goto(f"{code_url}/index.html#/3")
        wait_for_reveal_ready(page)

        token = page.locator("code.hl.lean.inline [data-verso-hover]").first
        expect(token).to_be_visible()
        token.hover()
        page.wait_for_timeout(500)

        # Tippy tooltips appear as .tippy-box elements
        tippy_boxes = page.locator(".tippy-box")
        assert tippy_boxes.count() == 0, "Tippy should not appear on inline code tokens"
