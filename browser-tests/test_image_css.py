"""Tests for the {image} role and css code blocks."""

from pathlib import Path
from bs4 import BeautifulSoup
from conftest import goto_slide_by_title


class TestImageRole:
    def test_image_with_all_attrs(self, markup_doc: BeautifulSoup):
        """An image with width, height, and class emits inline style (not HTML attrs)."""
        img = markup_doc.select_one('img[alt="Test logo"]')
        assert img is not None
        assert img["src"] == "images/test-logo.png"
        # width and height are emitted as inline style so they override max-width/max-height CSS
        style = img.get("style", "")
        assert "width: 200px" in style
        assert "height: 100px" in style
        # HTML presentation attributes should NOT be set
        assert img.get("width") is None
        assert img.get("height") is None
        assert "test-img-class" in img.get("class", [])

    def test_image_plain(self, markup_doc: BeautifulSoup):
        """An image with no optional attrs should have no style, width, or height."""
        img = markup_doc.select_one('img[alt="Plain image"]')
        assert img is not None
        assert img["src"] == "images/plain.png"
        assert img.get("width") is None
        assert img.get("height") is None
        assert img.get("style") is None

    def test_image_with_class(self, markup_doc: BeautifulSoup):
        """An image with a class should have the class attribute."""
        img = markup_doc.select_one('img[alt="Styled image"]')
        assert img is not None
        assert "css-target" in img.get("class", [])

    def test_oversized_image_uses_style(self, markup_doc: BeautifulSoup):
        """An image with dimensions larger than the viewport emits them as inline style."""
        img = markup_doc.select_one('img[alt="Oversized image"]')
        assert img is not None
        style = img.get("style", "")
        assert "width: 2000px" in style
        assert "height: 1500px" in style
        assert img.get("width") is None
        assert img.get("height") is None

    def test_remote_image_keeps_url(self, markup_doc: BeautifulSoup):
        """A remote URL image should keep its full URL, not be rewritten to images/."""
        img = markup_doc.select_one('img[alt="Remote image"]')
        assert img is not None
        assert img["src"] == "https://example.com/remote.png"

    def test_dedup_same_filename(self, markup_doc: BeautifulSoup):
        """Two local images with the same filename from different dirs get deduped."""
        img1 = markup_doc.select_one('img[alt="Test logo"]')
        img2 = markup_doc.select_one('img[alt="Dedup logo"]')
        assert img1 is not None and img2 is not None
        assert img1["src"] == "images/test-logo.png"
        assert img2["src"] == "images/test-logo-1.png"


class TestImageFiles:
    def test_local_images_copied(self, site_dir):
        """Local images should be copied to the output images/ directory."""
        images_dir = site_dir / "markup" / "images"
        assert images_dir.is_dir()
        assert (images_dir / "test-logo.png").exists()
        assert (images_dir / "plain.png").exists()
        assert (images_dir / "styled.png").exists()

    def test_dedup_file_exists(self, site_dir):
        """The deduplicated image file should exist in the output."""
        assert (site_dir / "markup" / "images" / "test-logo-1.png").exists()


class TestCustomCss:
    def test_css_in_head(self, markup_doc: BeautifulSoup):
        """CSS code blocks should be injected as <style> elements in <head>."""
        styles = markup_doc.select("head style")
        css_texts = [s.string for s in styles if s.string]
        combined = "\n".join(css_texts)
        assert ".css-target" in combined
        assert "border: 3px solid red" in combined

    def test_css_not_visible_in_body(self, markup_doc: BeautifulSoup):
        """CSS code blocks should not render visible content in the slides."""
        # The CSS Test slide should not contain a <pre> or <code> with the CSS
        slides_div = markup_doc.select_one("div.slides")
        sections = slides_div.find_all("section", recursive=False)
        css_slide = None
        for sec in sections:
            h = sec.find(["h1", "h2"])
            if h and h.get_text(strip=True) == "CSS Test":
                css_slide = sec
                break
        assert css_slide is not None
        # No <pre> or raw CSS text should appear in the slide body
        pres = css_slide.find_all("pre")
        assert len(pres) == 0

    def test_image_sizing_respected(self, page, markup_url):
        """Inline style width/height override the slide template's max-width/max-height."""
        slide = goto_slide_by_title(page, markup_url, "Image Test")
        img = slide.locator('img[alt="Test logo"]')
        assert img.count() == 1
        # getComputedStyle reflects the actual rendered size; with inline style the
        # specified value wins over any max-width/max-height rules in the theme CSS.
        computed_width = img.evaluate("el => getComputedStyle(el).width")
        computed_height = img.evaluate("el => getComputedStyle(el).height")
        assert computed_width == "200px", f"Expected 200px width, got {computed_width!r}"
        assert computed_height == "100px", f"Expected 100px height, got {computed_height!r}"

    def test_oversized_image_not_clamped(self, page, markup_url):
        """An image larger than the viewport keeps its inline-style dimensions.

        The slide template applies max-width/max-height to .reveal section img.
        Before the fix, width/height were emitted as HTML presentation attributes
        which lose to stylesheet max-width rules, silently clamping the image.
        With inline style= the author's value wins the cascade, so an image
        specified at 2000×1500 px must be rendered at exactly that size.
        """
        slide = goto_slide_by_title(page, markup_url, "Image Test")
        img = slide.locator('img[alt="Oversized image"]')
        assert img.count() == 1
        computed_width = img.evaluate("el => getComputedStyle(el).width")
        computed_height = img.evaluate("el => getComputedStyle(el).height")
        assert computed_width == "2000px", f"Expected 2000px width, got {computed_width!r} — inline style may have been overridden by max-width"
        assert computed_height == "1500px", f"Expected 1500px height, got {computed_height!r} — inline style may have been overridden by max-height"

    def test_css_affects_image(self, page, markup_url):
        """CSS defined after the image should still style it (injected in head)."""
        slide = goto_slide_by_title(page, markup_url, "CSS Test")
        img = slide.locator('img.css-target')
        assert img.count() == 1
        # The CSS sets opacity: 0.5
        opacity = img.evaluate("el => getComputedStyle(el).opacity")
        assert opacity == "0.5"
        # The CSS sets border: 3px solid red
        border = img.evaluate("el => getComputedStyle(el).borderStyle")
        assert border == "solid"
