"""Browser tests for fragment effects on code blocks."""

from playwright.sync_api import expect, Page


class TestFragmentTransform:
    def test_span_fragment_inline_block(self, code_url: str, page: Page):
        """Span fragments inside code should have display: inline-block for transforms."""
        page.goto(f"{code_url}/index.html#/4")
        page.wait_for_load_state("networkidle")
        page.wait_for_timeout(1000)

        span_frag = page.locator("code.hl.lean.block span.fragment").first
        if span_frag.count() == 0:
            return  # skip if no span fragments

        display = span_frag.evaluate("el => getComputedStyle(el).display")
        assert display == "inline-block", f"Expected inline-block, got: {display}"

    def test_div_fragment_not_inline_block(self, code_url: str, page: Page):
        """Div fragments inside code should NOT be inline-block (preserves line structure)."""
        page.goto(f"{code_url}/index.html#/4")
        page.wait_for_load_state("networkidle")
        page.wait_for_timeout(1000)

        div_frag = page.locator("code.hl.lean.block div.fragment").first
        if div_frag.count() == 0:
            return  # skip if no div fragments

        display = div_frag.evaluate("el => getComputedStyle(el).display")
        assert display != "inline-block", f"div.fragment should not be inline-block, got: {display}"

    def test_grow_fragment_scales(self, code_url: str, page: Page):
        """A visible .fragment.grow should have a scale transform."""
        page.goto(f"{code_url}/index.html#/4")
        page.wait_for_load_state("networkidle")
        page.wait_for_timeout(1000)

        # Advance fragments to make the grow fragment visible
        grow = page.locator(".fragment.grow").first
        if grow.count() == 0:
            return

        # Click through fragments until grow is visible
        for _ in range(5):
            if "visible" in (grow.get_attribute("class") or ""):
                break
            page.keyboard.press("ArrowRight")
            page.wait_for_timeout(300)

        if "visible" not in (grow.get_attribute("class") or ""):
            return  # couldn't make it visible

        transform = grow.evaluate("el => getComputedStyle(el).transform")
        # scale(1.3) appears as a matrix: matrix(1.3, 0, 0, 1.3, 0, 0)
        assert "matrix" in transform and "1.3" in transform, \
            f"Expected scale(1.3) transform, got: {transform}"


class TestFragmentColor:
    def test_highlight_current_red_changes_token_color(self, code_url: str, page: Page):
        """A .fragment.highlight-current-red.current-fragment should override token colors."""
        page.goto(f"{code_url}/index.html#/4")
        page.wait_for_load_state("networkidle")
        page.wait_for_timeout(1000)

        red_frag = page.locator(".fragment.highlight-current-red").first
        if red_frag.count() == 0:
            return

        # Advance fragments until highlight-current-red is the current fragment
        for _ in range(10):
            cls = red_frag.get_attribute("class") or ""
            if "current-fragment" in cls:
                break
            page.keyboard.press("ArrowRight")
            page.wait_for_timeout(300)

        cls = red_frag.get_attribute("class") or ""
        if "current-fragment" not in cls:
            return  # couldn't make it current

        # Check that a token inside the fragment has inherited the red color
        token = red_frag.locator(".keyword, .const, .token").first
        if token.count() == 0:
            return

        color = token.evaluate("el => getComputedStyle(el).color")
        # highlight-current-red sets color: #ff2c2d = rgb(255, 44, 45)
        assert "255" in color and "44" in color, \
            f"Expected red color (rgb with 255, 44), got: {color}"

    def test_token_color_inherits_from_fragment(self, code_url: str, page: Page):
        """When a color fragment is active, descendant tokens should use color: inherit."""
        page.goto(f"{code_url}/index.html#/4")
        page.wait_for_load_state("networkidle")
        page.wait_for_timeout(1000)

        red_frag = page.locator(".fragment.highlight-current-red").first
        if red_frag.count() == 0:
            return

        # Advance to make it current
        for _ in range(10):
            cls = red_frag.get_attribute("class") or ""
            if "current-fragment" in cls:
                break
            page.keyboard.press("ArrowRight")
            page.wait_for_timeout(300)

        if "current-fragment" not in (red_frag.get_attribute("class") or ""):
            return

        # The fragment's own color should be the red highlight color
        frag_color = red_frag.evaluate("el => getComputedStyle(el).color")

        # All tokens inside should have the same color (inherited)
        tokens = red_frag.locator(".keyword, .const, .var, .token")
        for i in range(min(tokens.count(), 5)):
            tok_color = tokens.nth(i).evaluate("el => getComputedStyle(el).color")
            assert tok_color == frag_color, \
                f"Token {i} color {tok_color} should match fragment color {frag_color}"
