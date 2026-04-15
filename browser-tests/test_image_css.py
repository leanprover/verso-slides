"""Tests for the {image} role and css code blocks."""

from pathlib import Path
from bs4 import BeautifulSoup
from conftest import goto_slide_by_title


class TestImageRole:
    def test_image_with_all_attrs(self, markup_doc: BeautifulSoup):
        """An image with width, height, and class emits inline style and explicit-size class."""
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
        # explicit-size class is added so the CSS can lift max-width/max-height
        classes = img.get("class", [])
        assert "explicit-size" in classes
        assert "test-img-class" in classes

    def test_image_plain(self, markup_doc: BeautifulSoup):
        """An image with no optional attrs should have no style, width, height, or explicit-size."""
        img = markup_doc.select_one('img[alt="Plain image"]')
        assert img is not None
        assert img["src"] == "images/plain.png"
        assert img.get("width") is None
        assert img.get("height") is None
        assert img.get("style") is None
        assert "explicit-size" not in img.get("class", [])

    def test_image_with_class(self, markup_doc: BeautifulSoup):
        """An image with only a class (no size) should not get explicit-size."""
        img = markup_doc.select_one('img[alt="Styled image"]')
        assert img is not None
        assert "css-target" in img.get("class", [])
        assert "explicit-size" not in img.get("class", [])

    def test_oversized_image_uses_style(self, markup_doc: BeautifulSoup):
        """An image with dimensions larger than the viewport emits inline style and explicit-size."""
        img = markup_doc.select_one('img[alt="Oversized image"]')
        assert img is not None
        assert img["src"] == "images/oversized-test.png"
        style = img.get("style", "")
        assert "width: 2000px" in style
        assert "height: 1500px" in style
        assert img.get("width") is None
        assert img.get("height") is None
        assert "explicit-size" in img.get("class", [])

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
        assert (images_dir / "oversized-test.png").exists()

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
        """width/height specified on {image} produce the correct rendered proportions.

        Reveal.js scales the whole slide with CSS zoom, so getComputedStyle returns
        zoom-adjusted values — we can't assert exact pixel numbers.  Instead we
        check the ratio of the image width to the slide section width.  With the
        slide configured at 960 px, a 200 px image should occupy 200/960 ≈ 20.8%
        of the slide width.
        """
        slide = goto_slide_by_title(page, markup_url, "Image Test")
        img = slide.locator('img[alt="Test logo"]')
        assert img.count() == 1
        ratio = img.evaluate("""el => {
            const section = el.closest('section');
            const imgW = el.getBoundingClientRect().width;
            const secW = section.getBoundingClientRect().width;
            return imgW / secW;
        }""")
        expected = 200 / 960
        assert abs(ratio - expected) < 0.02, (
            f"Expected image/slide width ratio ≈ {expected:.3f} (200px in 960px slide), "
            f"got {ratio:.3f} — width may not be taking effect"
        )

    def test_oversized_image_not_clamped(self, page, markup_url):
        """An image wider than the slide is not clamped by max-width.

        Before the fix the theme's .reveal img { max-width: 95% } would silently
        cap any image, whether the size came from an HTML attribute or inline style.
        With the CSS override (.reveal img[style*="width"] { max-width: none }) an
        image specified at 2000 px on a 960 px slide should overflow the slide —
        its rendered width must be greater than the section width.
        """
        slide = goto_slide_by_title(page, markup_url, "Image Test")
        img = slide.locator('img[alt="Oversized image"]')
        assert img.count() == 1
        img_wider_than_slide = img.evaluate("""el => {
            const section = el.closest('section');
            return el.getBoundingClientRect().width > section.getBoundingClientRect().width;
        }""")
        assert img_wider_than_slide, (
            "Oversized image (2000px) should be wider than the slide (960px), "
            "but it was clamped — max-width may still be in effect"
        )

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
