"""Tests for code included from an external example project."""

import re

from playwright.sync_api import expect, Page
from conftest import goto_slide_by_title


class TestExternalCode:
    def test_anchor_shows_only_anchor(self, externalcode_url: str, page: Page):
        """An anchor renders its region without the anchor comments."""
        slide = goto_slide_by_title(page, externalcode_url, "External Anchor")
        code = slide.locator("code.hl.lean.block")
        expect(code).to_be_visible()
        text = code.inner_text()
        assert "def double" in text
        assert "ANCHOR" not in text
        assert "def one" not in text

    def test_default_layout(self, externalcode_url: str, page: Page):
        """Code boxes have a panel and stretch by default."""
        slide = goto_slide_by_title(page, externalcode_url, "External Anchor")
        box = slide.locator(".code-with-panel")
        expect(box).to_be_visible()
        expect(box).to_have_class(re.compile(r"\br-stretch\b"))

    def test_layout_flags(self, externalcode_url: str, page: Page):
        """-panel and -stretch apply to external code boxes."""
        slide = goto_slide_by_title(page, externalcode_url, "External No Layout")
        code = slide.locator("code.hl.lean.block")
        expect(code).to_be_visible()
        assert slide.locator(".code-with-panel").count() == 0
        assert "r-stretch" not in (code.get_attribute("class") or "")

    def test_magic_comments(self, externalcode_url: str, page: Page):
        """Slide magic comments in external code create fragments."""
        slide = goto_slide_by_title(page, externalcode_url, "External Fragments")
        code = slide.locator("code.hl.lean.block")
        assert "!fragment" not in code.inner_text()
        assert code.locator(".fragment").count() >= 1

    def test_show_proof_states_flag(self, externalcode_url: str, page: Page):
        """-showProofStates removes proof states from the code."""
        slide = goto_slide_by_title(page, externalcode_url, "External No Proof States")
        code = slide.locator("code.hl.lean.block")
        expect(code).to_be_visible()
        assert code.locator(".tactic").count() == 0

    def test_roles(self, externalcode_url: str, page: Page):
        """Name and term roles render inline Lean code."""
        slide = goto_slide_by_title(page, externalcode_url, "External Roles")
        inline = slide.locator("code.hl.lean.inline")
        assert inline.count() == 2
        assert inline.nth(0).inner_text() == "double"
        assert inline.nth(1).inner_text() == "n + n"

    def test_output(self, externalcode_url: str, page: Page):
        """Message blocks render as command output."""
        slide = goto_slide_by_title(page, externalcode_url, "External Output")
        output = slide.locator(".command-output")
        expect(output).to_be_visible()
        assert "42" in output.inner_text()
