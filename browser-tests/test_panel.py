"""Browser tests for the interactive info panel."""

from playwright.sync_api import expect, Page


class TestPanelStructure:
    def test_panel_wrapper_exists(self, code_url: str, page: Page):
        """.code-with-panel wrapper should exist around lean code blocks."""
        page.goto(f"{code_url}/index.html#/0")
        page.wait_for_load_state("networkidle")
        page.wait_for_timeout(1000)

        panels = page.locator(".code-with-panel")
        assert panels.count() >= 1

        # Each wrapper should have code, divider, and info-panel
        first = panels.first
        expect(first.locator("code.hl.lean.block")).to_be_visible()
        expect(first.locator(".panel-divider")).to_be_visible()
        expect(first.locator(".info-panel")).to_be_visible()

    def test_no_panel_flag(self, code_url: str, page: Page):
        """lean -panel should render a code block without the panel wrapper."""
        # "No Panel" is slide index 5
        page.goto(f"{code_url}/index.html#/5")
        page.wait_for_load_state("networkidle")
        page.wait_for_timeout(1000)

        slide = page.locator(".slides > section").nth(5)
        # Should have a Lean code block
        code_block = slide.locator("code.hl.lean.block")
        expect(code_block).to_be_visible()

        # Should NOT be wrapped in .code-with-panel
        panels = slide.locator(".code-with-panel")
        assert panels.count() == 0

        # The code block should contain the definition
        assert "noPanelDef" in code_block.inner_text()

    def test_panel_starts_empty(self, code_url: str, page: Page):
        """.info-panel should start with no content."""
        page.goto(f"{code_url}/index.html#/0")
        page.wait_for_load_state("networkidle")
        page.wait_for_timeout(1000)

        panel = page.locator(".code-with-panel .info-panel").first
        expect(panel).to_be_visible()
        assert panel.inner_html().strip() == ""


class TestTacticReflow:
    def test_tactic_goals_reflow_on_resize(self, code_url: str, page: Page):
        """Clicking a tactic should show reflowed goals that re-render when the panel resizes."""
        page.goto(f"{code_url}/index.html#/2")
        page.wait_for_load_state("networkidle")
        page.wait_for_timeout(1000)

        # Scope to the active slide (index 2 = Proof slide)
        slide = page.locator(".slides > section").nth(2)
        block = slide.locator(".code-with-panel").first
        panel = block.locator(".info-panel")

        # Click the first tactic span to populate the panel with goal state
        tactic = block.locator(".tactic").first
        expect(tactic).to_be_visible()
        tactic.click()
        page.wait_for_timeout(500)

        # Panel should now contain reflowed goal content
        reflowed = panel.locator(".reflowed")
        assert reflowed.count() > 0, "Expected .reflowed spans in the panel after clicking a tactic"
        initial_html = reflowed.first.inner_html()
        assert len(initial_html.strip()) > 0, "Reflowed span should have content"

        # Inject a marker attribute into the panel's top-level element.
        # If reflowPanel actually re-renders, it replaces panel.innerHTML entirely,
        # which will remove this marker. If reflow is broken (no-op), the marker stays.
        panel.evaluate("el => el.firstElementChild.setAttribute('data-reflow-marker', '1')")
        assert panel.locator("[data-reflow-marker]").count() == 1, "Marker should be present before resize"

        # Shrink the panel significantly to trigger ResizeObserver → reflowPanel
        block.evaluate("""el => {
            el.style.setProperty('--code-ratio', '0.9fr');
            el.style.setProperty('--panel-ratio', '0.1fr');
        }""")
        # Wait for ResizeObserver debounce (100ms) + rendering
        page.wait_for_timeout(500)

        # The marker should be gone — reflowPanel replaced innerHTML
        assert panel.locator("[data-reflow-marker]").count() == 0, \
            "Reflow marker should be gone after resize (reflowPanel should have re-rendered the panel)"

        # And the panel should still have reflowed content
        reflowed_after = panel.locator(".reflowed")
        assert reflowed_after.count() > 0, "Reflowed spans should still exist after resize"


class TestPanelInteraction:
    def test_click_populates_panel(self, code_url: str, page: Page):
        """Clicking a [data-verso-hover] token should populate the panel."""
        page.goto(f"{code_url}/index.html#/0")
        page.wait_for_load_state("networkidle")
        page.wait_for_timeout(1000)

        block = page.locator(".code-with-panel").first
        panel = block.locator(".info-panel")
        token = block.locator("[data-verso-hover]").first
        expect(token).to_be_visible()

        token.click()

        expect(panel).not_to_be_empty(timeout=5000)

    def test_click_adds_panel_focus(self, code_url: str, page: Page):
        """Clicking a token should add .panel-focus class to it."""
        page.goto(f"{code_url}/index.html#/0")
        page.wait_for_load_state("networkidle")
        page.wait_for_timeout(1000)

        block = page.locator(".code-with-panel").first
        token = block.locator("[data-verso-hover]").first
        token.click()
        page.wait_for_timeout(300)

        # The clicked element (or its clickable ancestor) should have panel-focus
        focused = block.locator(".panel-focus")
        assert focused.count() >= 1

    def test_binding_highlight(self, code_url: str, page: Page):
        """Hovering a token with data-binding should toggle .binding-hl on matching tokens."""
        page.goto(f"{code_url}/index.html#/0")
        page.wait_for_load_state("networkidle")
        page.wait_for_timeout(1000)

        block = page.locator(".code-with-panel").first
        code = block.locator("code.hl.lean.block")

        # Find a token with data-binding
        binding_token = code.locator(".token[data-binding]").first
        if binding_token.count() == 0:
            return  # skip if no binding tokens in this code block

        expect(binding_token).to_be_visible()
        binding_token.hover()
        page.wait_for_timeout(200)

        highlighted = code.locator(".token.binding-hl")
        assert highlighted.count() >= 1

        # Move mouse away from the token — binding-hl should be removed
        page.mouse.move(0, 0)
        page.wait_for_timeout(200)
        assert code.locator(".token.binding-hl").count() == 0
