"""Tests for diagram code blocks."""

import json
import re
from bs4 import BeautifulSoup


class TestDiagramHTML:
    def test_diagram_container_exists(self, diagramanim_doc: BeautifulSoup):
        """A .diagram div exists with an inline width in vw units."""
        diagrams = diagramanim_doc.select("div.diagram")
        assert len(diagrams) >= 1, "Expected at least one .diagram container"
        style = diagrams[0].get("style", "")
        assert "vw" in style, f"Expected vw width in style, got: {style}"

    def test_diagram_svg_present(self, diagramanim_doc: BeautifulSoup):
        """An SVG element exists inside a .diagram container."""
        svg = diagramanim_doc.select("div.diagram svg")
        assert len(svg) >= 1, "Expected SVG inside .diagram"
        viewbox = svg[0].get("viewbox") or svg[0].get("viewBox")
        assert viewbox is not None, "SVG should have a viewBox attribute"

    def test_diagram_background_style(self, diagramanim_doc: BeautifulSoup):
        """The second diagram (with background param) has a background in its style."""
        diagrams = diagramanim_doc.select("div.diagram")
        assert len(diagrams) >= 2, "Expected at least two .diagram containers"
        style = diagrams[1].get("style", "")
        assert "background" in style, f"Expected background in style, got: {style}"
        assert "#ffffff" in style, f"Expected #ffffff background, got: {style}"

    def test_diagram_css_loaded(self, diagramanim_doc: BeautifulSoup):
        """A <link> to diagram.css exists in <head>."""
        links = diagramanim_doc.select('head link[rel="stylesheet"]')
        hrefs = [link.get("href", "") for link in links]
        assert any("diagram.css" in h for h in hrefs), \
            f"Expected diagram.css link in head, found: {hrefs}"
