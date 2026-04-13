"""Tests for animation code blocks — both static HTML and browser interaction."""

import json
import re
import time
from bs4 import BeautifulSoup
from playwright.sync_api import Page
from conftest import goto_slide_by_title


# ---------------------------------------------------------------------------
# Static HTML tests (BeautifulSoup)
# ---------------------------------------------------------------------------


class TestAnimationHTML:
    def test_animation_container_exists(self, diagramanim_doc: BeautifulSoup):
        """An .illuminate-anim div with an id attribute exists."""
        containers = diagramanim_doc.select("div.illuminate-anim")
        assert len(containers) >= 1, "Expected at least one .illuminate-anim container"
        assert containers[0].get("id"), "Container should have an id attribute"

    def test_animation_data_script(self, diagramanim_doc: BeautifulSoup):
        """A <script type='application/json' data-illuminate-anim> with valid JSON."""
        scripts = diagramanim_doc.select("script[data-illuminate-anim]")
        assert len(scripts) >= 1, "Expected at least one animation data script"
        data = json.loads(scripts[0].string)
        assert "totalFrames" in data
        assert "steps" in data
        assert "segments" in data
        assert data["totalFrames"] > 0

    def test_animation_fragment_spans(self, diagramanim_doc: BeautifulSoup):
        """Hidden fragment spans with data-illuminate-container exist in the HTML."""
        frags = diagramanim_doc.select("span.fragment[data-illuminate-container]")
        assert len(frags) >= 1, "Expected at least one animation fragment span"
        frag = frags[0]
        assert frag.get("data-illuminate-step-index") is not None
        assert "display:none" in frag.get("style", "") or "display: none" in frag.get("style", "")

    def test_animation_fragment_indices(self, diagramanim_doc: BeautifulSoup):
        """Fragment spans with explicit fragmentIndex have data-fragment-index."""
        # The Shape Morphing slide has fragmentIndex := some 1
        frags = diagramanim_doc.select(
            "span.fragment[data-illuminate-container][data-fragment-index]"
        )
        assert len(frags) >= 1, "Expected at least one fragment with explicit index"
        idx = frags[0].get("data-fragment-index")
        assert idx is not None and idx.isdigit()

    def test_animation_autoplay_attribute(self, diagramanim_doc: BeautifulSoup):
        """Containers have data-illuminate-autoplay='true' or 'false'."""
        containers = diagramanim_doc.select("div.illuminate-anim")
        autoplay_values = [c.get("data-illuminate-autoplay") for c in containers]
        assert "true" in autoplay_values, "Expected at least one autoplay=true"
        assert "false" in autoplay_values, "Expected at least one autoplay=false"

    def test_animation_js_loaded(self, diagramanim_doc: BeautifulSoup):
        """illuminate-reveal.js is loaded in the HTML body."""
        scripts = diagramanim_doc.select("script[src]")
        srcs = [s.get("src", "") for s in scripts]
        assert any("illuminate-reveal.js" in s for s in srcs), \
            f"Expected illuminate-reveal.js script, found: {srcs}"

    def test_animation_css_loaded(self, diagramanim_doc: BeautifulSoup):
        """illuminate-anim.css is linked in the head."""
        links = diagramanim_doc.select('head link[rel="stylesheet"]')
        hrefs = [link.get("href", "") for link in links]
        assert any("illuminate-anim.css" in h for h in hrefs), \
            f"Expected illuminate-anim.css link, found: {hrefs}"


# ---------------------------------------------------------------------------
# Browser interaction tests (Playwright)
# ---------------------------------------------------------------------------


class TestAnimationAutoplay:
    def test_autoplay_runs_on_slide_entry(self, diagramanim_url: str, page: Page):
        """An +autoplay animation renders SVG content on slide entry."""
        goto_slide_by_title(page, diagramanim_url, "Animation Autoplay")
        # Wait for autoplay to start and render
        page.wait_for_timeout(2000)
        container = page.locator("section.present .illuminate-anim").first
        svg = container.locator("svg")
        assert svg.count() > 0, "Expected SVG to be rendered by autoplay"

    def test_autoplay_stops_at_first_pause(self, diagramanim_url: str, page: Page):
        """After autoplay finishes, ArrowRight advances a fragment (not next slide)."""
        goto_slide_by_title(page, diagramanim_url, "Animation Autoplay")
        page.wait_for_timeout(2000)  # Wait for autoplay to finish
        # The autoplay slide has a pause step, so there should be a fragment to advance
        # Press ArrowRight — should advance a fragment, not go to the next slide
        page.keyboard.press("ArrowRight")
        page.wait_for_timeout(500)
        # We should still be on the same slide (Animation Autoplay)
        heading = page.locator(".present h2").first
        assert heading.count() > 0
        assert "Autoplay" in heading.text_content()

    def test_no_autoplay_waits_for_click(self, diagramanim_url: str, page: Page):
        """A non-autoplay animation with a non-pause first step does NOT auto-play."""
        goto_slide_by_title(page, diagramanim_url, "Animation No Autoplay")
        page.wait_for_timeout(1500)
        container = page.locator("section.present .illuminate-anim").first
        # The animation should show frame 0 (SVG rendered) but NOT have advanced
        svg_before = container.inner_html()
        page.wait_for_timeout(1000)
        svg_after = container.inner_html()
        # SVG content should not have changed (no auto-play)
        assert svg_before == svg_after, "Non-autoplay animation should not change without clicks"


class TestAnimationClick:
    def test_fragment_click_advances_animation(self, diagramanim_url: str, page: Page):
        """Clicking ArrowRight on a pause-step animation changes the SVG."""
        goto_slide_by_title(page, diagramanim_url, "Animation Click")
        page.wait_for_timeout(500)
        container = page.locator("section.present .illuminate-anim").first
        svg_before = container.inner_html()
        page.keyboard.press("ArrowRight")
        page.wait_for_timeout(1000)  # Wait for animation to play
        svg_after = container.inner_html()
        assert svg_after != svg_before, "Animation should have changed after click"


class TestAnimationLoop:
    def test_loop_end_animates(self, diagramanim_url: str, page: Page):
        """A loop step at the end (without pause) loops after click-through."""
        goto_slide_by_title(page, diagramanim_url, "Animation Loop End")
        page.wait_for_timeout(500)
        # Click through the first pause step
        page.keyboard.press("ArrowRight")
        page.wait_for_timeout(1500)  # Wait for animation + loop to start
        container = page.locator("section.present .illuminate-anim").first
        svg1 = container.inner_html()
        page.wait_for_timeout(200)
        svg2 = container.inner_html()
        assert svg1 != svg2, "Loop animation should produce changing SVG frames"

    def test_loop_middle_starts(self, diagramanim_url: str, page: Page):
        """A loop step in the middle starts looping when its fragment is shown."""
        goto_slide_by_title(page, diagramanim_url, "Animation Loop Middle")
        page.wait_for_timeout(500)
        # Click to reach the first pause (step 0)
        page.keyboard.press("ArrowRight")
        page.wait_for_timeout(1000)
        # Click to reach the loop step (step 1)
        page.keyboard.press("ArrowRight")
        page.wait_for_timeout(1500)
        container = page.locator("section.present .illuminate-anim").first
        svg1 = container.inner_html()
        page.wait_for_timeout(200)
        svg2 = container.inner_html()
        assert svg1 != svg2, "Middle loop step should produce changing SVG frames"

    def test_loop_middle_stops_on_advance(self, diagramanim_url: str, page: Page):
        """Clicking past a middle loop step stops the loop and advances."""
        goto_slide_by_title(page, diagramanim_url, "Animation Loop Middle")
        page.wait_for_timeout(500)
        # Click to first pause, then to loop step
        page.keyboard.press("ArrowRight")
        page.wait_for_timeout(1000)
        page.keyboard.press("ArrowRight")
        page.wait_for_timeout(1500)
        # Now click to advance past the loop
        page.keyboard.press("ArrowRight")
        page.wait_for_timeout(1000)
        # The loop should have stopped — SVG should be stable
        container = page.locator("section.present .illuminate-anim").first
        svg1 = container.inner_html()
        page.wait_for_timeout(300)
        svg2 = container.inner_html()
        assert svg1 == svg2, "Animation should have stopped after advancing past loop"


class TestInterleavedFragments:
    def test_interleaved_fragments_sync(self, diagramanim_url: str, page: Page):
        """Text fragments and animation fragments with shared indices advance together."""
        goto_slide_by_title(page, diagramanim_url, "Shape Morphing")
        page.wait_for_timeout(500)
        container = page.locator("section.present .illuminate-anim").first
        svg_before = container.inner_html()
        # Text should show "A" initially (fadeOut fragment not yet triggered)
        text_a = page.locator("section.present .fragment.fade-out")
        assert text_a.count() > 0
        # Click to advance index 1 — both text and animation should change
        page.keyboard.press("ArrowRight")
        page.wait_for_timeout(1500)
        svg_after = container.inner_html()
        assert svg_after != svg_before, "Animation should have changed on same click as text"
        # Text "A" should have faded out (has .visible class now for fade-out)
        cls = text_a.first.get_attribute("class") or ""
        assert "visible" in cls, "Text fragment 'A' should be visible (fade-out triggered)"


class TestBackwardNavigation:
    def test_backward_navigation_syncs(self, diagramanim_url: str, page: Page):
        """Going back to an animation slide shows the correct final state."""
        goto_slide_by_title(page, diagramanim_url, "Animation Click")
        page.wait_for_timeout(500)
        # Click through all 3 pause steps
        for _ in range(3):
            page.keyboard.press("ArrowRight")
            page.wait_for_timeout(800)
        container = page.locator("section.present .illuminate-anim").first
        svg_final = container.inner_html()
        # Go to next slide
        page.keyboard.press("ArrowRight")
        page.wait_for_timeout(500)
        # Go back
        page.keyboard.press("ArrowLeft")
        page.wait_for_timeout(1000)
        svg_back = container.inner_html()
        assert svg_back == svg_final, "Backward navigation should show the final animation state"
