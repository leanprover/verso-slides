"""Browser tests for the inline Lean term lightbox overlay."""

from playwright.sync_api import expect, Page
from conftest import goto_slide_by_title


class TestLightboxOpen:
    def test_click_inline_token_opens_lightbox(self, code_url: str, page: Page):
        """Clicking a data-verso-hover token in inline code should open a lightbox."""
        slide = goto_slide_by_title(page, code_url, "Inline Lean")

        # Find an inline lean code element
        inline = slide.locator("code.hl.lean.inline").first
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
        slide = goto_slide_by_title(page, code_url, "Inline Lean")

        token = slide.locator("code.hl.lean.inline [data-verso-hover]").first
        token.click()
        page.wait_for_timeout(500)

        inner = page.locator(".lean-hover-inner")
        expect(inner).to_be_visible()
        assert inner.inner_html().strip() != "", "Lightbox content should not be empty"

    def test_lightbox_monospace_font(self, code_url: str, page: Page):
        """Lightbox content should use a monospace font."""
        slide = goto_slide_by_title(page, code_url, "Inline Lean")

        token = slide.locator("code.hl.lean.inline [data-verso-hover]").first
        token.click()
        page.wait_for_timeout(500)

        inner = page.locator(".lean-hover-inner")
        font = inner.evaluate("el => getComputedStyle(el).fontFamily")
        assert "monospace" in font.lower(), f"Expected monospace font, got: {font}"


class TestLightboxClose:
    def _open_lightbox(self, page: Page, code_url: str):
        """Helper to navigate and open a lightbox."""
        slide = goto_slide_by_title(page, code_url, "Inline Lean")
        token = slide.locator("code.hl.lean.inline [data-verso-hover]").first
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
        slide = goto_slide_by_title(page, code_url, "Inline Lean")

        token = slide.locator("code.hl.lean.inline [data-verso-hover]").first
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
        slide = goto_slide_by_title(page, code_url, "Inline Lean")

        token = slide.locator("code.hl.lean.inline [data-verso-hover]").first
        token.click()
        page.wait_for_timeout(500)

        overlay = page.locator(".r-overlay-lean-hover")
        overflow = overlay.evaluate("el => getComputedStyle(el).overflowY")
        assert overflow == "auto", f"Expected overflow-y: auto, got: {overflow}"


class TestLightboxThemeColors:
    """The lightbox must follow the slide theme rather than r-overlay's hardcoded dark."""

    def _click_first_token(self, page: Page):
        """Click within the active slide — multiple slides have inline tokens,
        and clicking an off-screen one would fail with 'outside the viewport'."""
        active = page.locator("section.present")
        token = active.locator("code.hl.lean.inline [data-verso-hover]").first
        token.click()
        page.wait_for_timeout(500)

    def test_dark_slide_no_light_bg_class(self, code_url: str, page: Page):
        """Dark slide (default in this fixture): overlay must NOT get slide-light-bg."""
        goto_slide_by_title(page, code_url, "Inline Lean")
        self._click_first_token(page)

        overlay = page.locator(".r-overlay-lean-hover")
        expect(overlay).to_be_visible()
        assert "slide-light-bg" not in (overlay.get_attribute("class") or "")

    def test_dark_slide_background_not_black(self, code_url: str, page: Page):
        """Overlay background should follow the theme, not r-overlay's hardcoded #000.

        The `code` fixture uses `theme := "black"`, whose --r-background-color is
        a dark grey (#191919) rather than pure black. The bug being fixed was
        r-overlay forcing #000 regardless of theme.
        """
        goto_slide_by_title(page, code_url, "Inline Lean")
        self._click_first_token(page)

        overlay = page.locator(".r-overlay-lean-hover")
        bg = overlay.evaluate("el => getComputedStyle(el).backgroundColor")
        # rgb(0, 0, 0) would mean r-overlay's dark default is still leaking through.
        assert bg != "rgb(0, 0, 0)", f"Expected theme bg, got hardcoded black: {bg}"

    def test_light_slide_copies_light_bg_class(self, code_url: str, page: Page):
        """Light slide: overlay must inherit slide-light-bg from the active section.

        The "Light Inline Lean" slide has backgroundColor "#f5f5f5", which
        code-block-bg.js tags with .slide-light-bg. lightbox.js copies that
        onto the overlay so the light Lean token palette applies.
        """
        goto_slide_by_title(page, code_url, "Light Inline Lean")

        # Sanity check: the active section actually got tagged as light.
        active_section = page.locator("section.present").first
        active_classes = active_section.get_attribute("class") or ""
        assert "slide-light-bg" in active_classes, (
            f"Expected slide-light-bg on the active section; got class={active_classes!r}"
        )

        self._click_first_token(page)
        overlay = page.locator(".r-overlay-lean-hover")
        expect(overlay).to_be_visible()
        assert "slide-light-bg" in (overlay.get_attribute("class") or "")

    def test_light_slide_token_palette_applied(self, code_url: str, page: Page):
        """With slide-light-bg on the overlay, --verso-code-keyword-color uses the light palette."""
        goto_slide_by_title(page, code_url, "Light Inline Lean")
        self._click_first_token(page)

        overlay = page.locator(".r-overlay-lean-hover")
        keyword_color = overlay.evaluate(
            "el => getComputedStyle(el).getPropertyValue('--verso-code-keyword-color').trim()"
        )
        # Light-mode value from slides-highlight.css (`#8839a0`). Dark default is `#c678dd`.
        assert keyword_color == "#8839a0", (
            f"Expected light-mode keyword color #8839a0, got {keyword_color!r}"
        )


class TestTippySuppression:
    def test_no_tippy_on_inline_code(self, code_url: str, page: Page):
        """Hovering an inline Lean token should not create a Tippy tooltip."""
        slide = goto_slide_by_title(page, code_url, "Inline Lean")

        token = slide.locator("code.hl.lean.inline [data-verso-hover]").first
        expect(token).to_be_visible()
        token.hover()
        page.wait_for_timeout(500)

        # Tippy tooltips appear as .tippy-box elements
        tippy_boxes = page.locator(".tippy-box")
        assert tippy_boxes.count() == 0, "Tippy should not appear on inline code tokens"
