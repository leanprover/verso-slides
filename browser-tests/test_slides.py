"""Static HTML tests for slide structure, fragments, notes, and metadata."""

from bs4 import BeautifulSoup


class TestSlideStructure:
    def test_slide_count(self, markup_doc: BeautifulSoup):
        """The .slides div should contain the expected number of top-level sections."""
        slides_div = markup_doc.select_one("div.slides")
        assert slides_div is not None
        top_sections = slides_div.find_all("section", recursive=False)
        assert len(top_sections) == 10

    def test_slide_titles(self, markup_doc: BeautifulSoup):
        """Each top-level slide should have the expected heading."""
        slides_div = markup_doc.select_one("div.slides")
        top_sections = slides_div.find_all("section", recursive=False)

        expected_titles = [
            "Slide One",
            "Vertical Section",
            "Fragments",
            "Metadata",
            "Auto-Animate One",
            "Auto-Animate Two",
            "Image Test",
            "CSS Test",
            "Tables",
            "Last Slide",
        ]

        actual_titles = []
        for sec in top_sections:
            # For vertical groups, the heading is inside the first nested section
            heading = sec.find(["h1", "h2"])
            actual_titles.append(heading.get_text(strip=True) if heading else "")

        assert actual_titles == expected_titles

    def test_vertical_slides(self, markup_doc: BeautifulSoup):
        """The 'Vertical Section' should have nested section children."""
        slides_div = markup_doc.select_one("div.slides")
        top_sections = slides_div.find_all("section", recursive=False)

        # Second section (index 1) is "Vertical Section"
        vertical_section = top_sections[1]
        inner_sections = vertical_section.find_all("section", recursive=False)
        assert len(inner_sections) == 3  # implicit first + Sub A + Sub B

    def test_slide_metadata_background_color(self, markup_doc: BeautifulSoup):
        """Sections with backgroundColor metadata should have data-background-color."""
        colored = markup_doc.select("section[data-background-color]")
        colors = {s["data-background-color"] for s in colored}
        assert "#4d7e65" in colors  # Sub B green
        assert "#2d1b69" in colors  # Metadata purple

    def test_slide_metadata_auto_animate(self, markup_doc: BeautifulSoup):
        """Auto-Animate slides should have data-auto-animate attribute."""
        auto_animate = markup_doc.select("section[data-auto-animate]")
        assert len(auto_animate) == 2

    def test_slide_metadata_transition(self, markup_doc: BeautifulSoup):
        """Metadata slide should have data-transition='zoom'."""
        zoom = markup_doc.select("section[data-transition='zoom']")
        assert len(zoom) == 1


class TestNotes:
    def test_notes_present(self, markup_doc: BeautifulSoup):
        """Speaker notes should be rendered as <aside class='notes'>."""
        notes = markup_doc.select("aside.notes")
        assert len(notes) == 3  # Slide One, Sub B, Last Slide


class TestFragments:
    def test_block_fragment(self, markup_doc: BeautifulSoup):
        """Block-level fragments should exist."""
        fragments = markup_doc.select("p.fragment")
        assert len(fragments) >= 1

    def test_fragment_fade_up(self, markup_doc: BeautifulSoup):
        """Fade-up fragments should have class 'fragment fade-up'."""
        fade_up = markup_doc.select(".fragment.fade-up")
        assert len(fade_up) == 2

    def test_fragment_index(self, markup_doc: BeautifulSoup):
        """Fragments with explicit index should have data-fragment-index."""
        indexed = markup_doc.select("[data-fragment-index]")
        indices = {el["data-fragment-index"] for el in indexed}
        assert "2" in indices
        assert "3" in indices

    def test_inline_fragment(self, markup_doc: BeautifulSoup):
        """Inline fragments should be rendered as <span class='fragment ...'>."""
        inline_frags = markup_doc.select("span.fragment:not(.slide-click-only)")
        assert len(inline_frags) == 2  # highlight-red and highlight-blue

    def test_inline_fragment_styles(self, markup_doc: BeautifulSoup):
        """Inline fragments should have the correct style classes."""
        assert markup_doc.select_one("span.fragment.highlight-red") is not None
        assert markup_doc.select_one("span.fragment.highlight-blue") is not None
