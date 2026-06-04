"""Browser tests for the interactive info panel."""

from playwright.sync_api import expect, Page
from conftest import goto_slide_by_title


class TestPanelStructure:
    def test_panel_wrapper_exists(self, code_url: str, page: Page):
        """.code-with-panel wrapper should exist around lean code blocks."""
        slide = goto_slide_by_title(page, code_url, "Dark Code")

        panels = slide.locator(".code-with-panel")
        assert panels.count() >= 1

        # Each wrapper should have code, divider, and info-panel
        first = panels.first
        expect(first.locator("code.hl.lean.block")).to_be_visible()
        expect(first.locator(".panel-divider")).to_be_visible()
        expect(first.locator(".info-panel")).to_be_visible()

    def test_no_panel_flag(self, code_url: str, page: Page):
        """lean -panel should render a code block without the panel wrapper."""
        slide = goto_slide_by_title(page, code_url, "No Panel")
        # Should have a Lean code block
        code_block = slide.locator("code.hl.lean.block")
        expect(code_block).to_be_visible()

        # Should NOT be wrapped in .code-with-panel
        panels = slide.locator(".code-with-panel")
        assert panels.count() == 0

        # The code block should contain the definition
        assert "noPanelDef" in code_block.inner_text()

    def test_panel_option_default(self, paneloption_url: str, page: Page):
        """set_option verso.slides.panel false drops the panel from flag-less
        boxes, while +panel still opts an individual box back in."""
        slide = goto_slide_by_title(page, paneloption_url, "Panel Off By Default")

        # The flag-less box (optNoPanelDef) should have no panel wrapper.
        no_panel = slide.locator(
            ".code-with-panel", has=page.get_by_text("optNoPanelDef")
        )
        assert no_panel.count() == 0

        # The +panel box (optPanelDef) should still be wrapped in a panel.
        with_panel = slide.locator(
            ".code-with-panel", has=page.get_by_text("optPanelDef")
        )
        assert with_panel.count() == 1
        expect(with_panel.locator(".info-panel")).to_be_visible()

    def test_panel_starts_empty(self, code_url: str, page: Page):
        """.info-panel should start with no content."""
        slide = goto_slide_by_title(page, code_url, "Dark Code")

        panel = slide.locator(".code-with-panel .info-panel").first
        expect(panel).to_be_visible()
        assert panel.inner_html().strip() == ""


class TestTacticReflow:
    def test_tactic_goals_reflow_on_resize(self, code_url: str, page: Page):
        """Clicking a tactic should show reflowed goals that re-render when the panel resizes."""
        slide = goto_slide_by_title(page, code_url, "Proof")
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


class TestNestedTacticState:
    def test_nested_rw_shows_own_state(self, code_url: str, page: Page):
        """A tactic with nested child tactics (e.g. a multi-rewrite
        ``rw [h1, h2, ...]``) must show its OWN resulting state when clicked.

        In the DOM the outer ``.tactic`` element holds its own ``.tactic-state``
        as its last child, after the nested per-rewrite ``.tactic`` elements (each
        with their own ``.tactic-state``). The panel must use this tactic's
        direct-child state (``All goals completed``), not a nested child's
        intermediate goal (``b = e``).
        """
        slide = goto_slide_by_title(page, code_url, "Nested Tactic")
        block = slide.locator(".code-with-panel").first
        panel = block.locator(".info-panel")

        # Click the `rw` keyword token. Its outermost clickable ancestor is the
        # whole rw tactic, so the panel is populated from that tactic.
        rw = block.get_by_text("rw", exact=True)
        expect(rw).to_be_visible()
        rw.click()
        page.wait_for_timeout(300)

        text = panel.inner_text()
        assert "All goals completed" in text, (
            f"Expected the rw tactic's own final state, but panel showed: {text!r}"
        )
        assert "b = e" not in text, (
            f"Panel showed a nested child tactic's intermediate state: {text!r}"
        )

    def test_rw_click_sequence_reveals_distinct_states(self, code_url: str, page: Page):
        """Repeatedly clicking a deeply nested token cycles the selection
        outward-to-inward through the clickable chain, and each click reveals
        different information.

        The ``h1`` hypothesis in ``rw [h1, h2, h3, ←h4]`` sits three clickable
        levels deep: the whole ``rw`` tactic, the first rewrite step, then the
        ``h1`` variable token. So successive clicks on it surface the rw's own
        resulting state, then that rewrite step's goal, then the hypothesis's
        own hover info — and a fourth click wraps back to the outermost.
        """
        slide = goto_slide_by_title(page, code_url, "Nested Tactic")
        block = slide.locator(".code-with-panel").first
        panel = block.locator(".info-panel")

        rw = block.locator(".tactic[data-tactic-range]", has_text="rw").first
        # The first rewrite step is the outermost nested tactic; its direct-child
        # `.var` is the visible `h1` token (the `:scope >` avoids the hidden `h1`
        # occurrences inside the rewrite step's tactic-state goal).
        first_step = rw.locator(".tactic").first
        h1 = first_step.locator(":scope > .var")
        expect(h1).to_have_count(1)

        seen = []
        for _ in range(3):
            h1.click()
            page.wait_for_timeout(200)
            seen.append(panel.inner_text().strip())

        # 1st click: the whole rw tactic's own resulting state.
        assert "All goals completed" in seen[0], seen
        # 2nd click: the first rewrite step turns the goal `a = e` into `b = e`.
        assert "b = e" in seen[1], seen
        # 3rd click: the `h1` hypothesis itself, whose type is `a = b`.
        assert "a = b" in seen[2], seen
        # Each click revealed information distinct from the previous one.
        assert seen[0] != seen[1] and seen[1] != seen[2] and seen[0] != seen[2], seen

        # A fourth click wraps back around to the outermost selection.
        h1.click()
        page.wait_for_timeout(200)
        assert panel.inner_text().strip() == seen[0]


class TestPanelInteraction:
    def test_click_populates_panel(self, code_url: str, page: Page):
        """Clicking a [data-verso-hover] token should populate the panel."""
        slide = goto_slide_by_title(page, code_url, "Dark Code")

        block = slide.locator(".code-with-panel").first
        panel = block.locator(".info-panel")
        token = block.locator("[data-verso-hover]").first
        expect(token).to_be_visible()

        token.click()

        expect(panel).not_to_be_empty(timeout=5000)

    def test_click_adds_panel_focus(self, code_url: str, page: Page):
        """Clicking a token should add .panel-focus class to it."""
        slide = goto_slide_by_title(page, code_url, "Dark Code")

        block = slide.locator(".code-with-panel").first
        token = block.locator("[data-verso-hover]").first
        token.click()
        page.wait_for_timeout(300)

        # The clicked element (or its clickable ancestor) should have panel-focus
        focused = block.locator(".panel-focus")
        assert focused.count() >= 1

    def test_binding_highlight(self, code_url: str, page: Page):
        """Hovering a token with data-binding should toggle .binding-hl on matching tokens."""
        slide = goto_slide_by_title(page, code_url, "Dark Code")

        block = slide.locator(".code-with-panel").first
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
