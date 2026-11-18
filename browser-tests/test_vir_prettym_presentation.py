"""Mandatory VIR and shared DOM presentation, using emitted assets/native oracle."""
import json
from pathlib import Path

from bs4 import BeautifulSoup

from playwright.sync_api import expect

from conftest import take_console_errors, expect_console_error
from pretty_helpers import open_demo, select_goal, set_goal


def test_published_urls_use_the_selected_runtime(site_dir):
    site = site_dir / 'code'
    html = BeautifulSoup((site / 'index.html').read_text(), 'html.parser')
    scripts = html.select('script[data-runtime-module]')
    assert len(scripts) == 1
    bootstrap = scripts[0]
    for attribute in ['data-runtime-module', 'data-runtime-manifest', 'data-program-manifest']:
        path = bootstrap[attribute]
        assert not Path(path).is_absolute()
        assert (site / path).is_file()
    manifest = json.loads((site / bootstrap['data-runtime-manifest']).read_text())
    dependencies = json.loads((Path(__file__).parents[1] / 'lake-manifest.json').read_text())
    vir = next(p for p in dependencies['packages'] if p['name'] == 'lean_vir')
    assert manifest['descriptor']['logicalId'] == f"lean-vir/runtime/{vir['rev']}"


def test_native_segments_and_annotations_in_dom(page, server, site_dir):
    open_demo(page, server)
    corpus = json.loads((site_dir / "native-corpus.json").read_text())
    assert corpus
    actual = page.evaluate("""cases => cases.map(c => {
        const segments = window.versoVirFormatSegments(c.format, c.width, c.indent);
        const annotations = {'7': {cssClass: 'const', binding: 'outer'},
            '8': {cssClass: 'var', binding: 'inner'}};
        const template = document.createElement('template');
        template.innerHTML = segmentsToHtml(segments, annotations);
        return {segments: window.testSegmentsForJSON(segments), text: template.content.textContent,
            tagged: [...template.content.querySelectorAll('.token')].map(el => ({
                text: el.textContent,
                classes: [...el.classList], binding: el.getAttribute('data-binding'),
            }))};
    })""", corpus)
    assert len(actual) == len(corpus)
    for case, dom in zip(corpus, actual):
        expected = case["result"]["segments"]
        assert dom["segments"] == expected, case["name"]
        assert dom["text"] == "".join(s["text"] for s in expected), case["name"]
        tagged = []
        for s in expected:
            if not s["tags"]:
                continue
            annotation = next((t for t in reversed(s["tags"]) if t in ("7", "8")), None)
            if annotation:
                tagged.append({"text": s["text"], "classes": ["var" if annotation == "8" else "const", "token"],
                    "binding": "inner" if annotation == "8" else "outer"})
        assert dom["tagged"] == tagged, case["name"]


def test_existing_text_and_binding_escaping_with_large_tags(page, server):
    open_demo(page, server)
    result = page.evaluate("""() => {
        const binding = 'b"&<';
        const fmt = [7, '7', [7, '9007199254740993', '<&"']];
        const annotations = {'9007199254740993': {cssClass: 'var', binding}};
        const template = document.createElement('template');
        template.innerHTML = formatToHtml(fmt, annotations, 800, {spaceWidth: 10});
        const span = template.content.querySelector('.token');
        return {text: template.content.textContent, binding: span.getAttribute('data-binding'),
            css: span.getAttribute('class'),
            segments: window.testSegmentsForJSON(window.versoVirFormatSegments(fmt, 80, 0))};
    }""")
    assert result == {"text": '<&"', "binding": 'b"&<', "css": 'var token',
        "segments": [{"text": '<&"', "tags": ["7", "9007199254740993"]}]}


def test_shared_goal_preserves_ordinary_binding_interaction(page, server):
    open_demo(page, server)
    block, panel = select_goal(page)
    expect(panel.locator(".reflowed").first).not_to_be_empty()
    binding = "ordinary-binding"
    set_goal(block, [7, "7", 'x<&"'], binding)
    expect(panel.locator(".reflowed .token").first).to_have_text('x<&"')
    # Query the current token and inspect the handlers in one task: reflow
    # replaces the panel's child nodes.
    interaction = panel.evaluate("""panel => {
        const token = panel.querySelector('.reflowed .token');
        const block = panel.closest('.code-with-panel');
        token.dispatchEvent(new MouseEvent('mouseover', {bubbles: true}));
        const classes = token.className;
        const codeMatches = block.querySelectorAll('code .token.binding-hl').length;
        token.dispatchEvent(new MouseEvent('mouseout', {bubbles: true}));
        return {text: token.textContent, binding: token.getAttribute('data-binding'),
            classes, codeMatches, remaining: block.querySelectorAll('.binding-hl').length};
    }""")
    assert interaction["text"] == 'x<&"'
    assert interaction["binding"] == binding
    assert interaction["classes"] == "var token binding-hl"
    assert interaction["codeMatches"] >= 1
    assert interaction["remaining"] == 0


def test_bad_compact_input_reports_and_recovers(page, server, browser_errors):
    open_demo(page, server)
    block, panel = select_goal(page)
    expect(panel.locator(".reflowed").first).not_to_be_empty()
    page.evaluate("window.originalProgram = window.versoVir")
    cause = 'PrettyFormatError: PrettyM input error: invalidInput'
    with expect_console_error(page, f'Lean expression formatting failed {cause}'):
        set_goal(block, [3, 1, "invalid", "extra"], "bad")
    expect(panel.get_by_role("alert")).to_have_text("This Lean expression could not be formatted.")
    assert "OLD STATIC LAYOUT" not in panel.inner_text()
    expect(panel.locator('[style*="visibility: hidden"]')).to_have_count(0)
    assert page.evaluate("window.versoVir === window.originalProgram && window.versoVir.status === 'active'")
    set_goal(block, [7, "7", "recovered"], "good")
    expect(panel.locator(".reflowed .token")).to_have_text("recovered")
    expect(panel.get_by_role("alert")).to_have_count(0)
    expect(panel.locator('[style*="visibility: hidden"]')).to_have_count(0)
    for label in ['VIR formatting failed', 'Lean expression formatting failed']:
        assert take_console_errors(browser_errors, f'{label} {cause}') >= 1
