"""Mandatory VIR and shared DOM presentation, using emitted assets/native oracle."""
import json
import re

from playwright.sync_api import expect

from test_vir_prettym_site import open_demo, open_proof_panel


def test_published_formatter_has_one_mandatory_path(site_dir):
    root = site_dir / "code"
    pretty = (root / "lib/pretty.js").read_text()
    assert re.search(r'program\.call\(\s*"VersoSlides\.VirPrettyM\.formatSegments"', pretty)
    for old in ("function deserializeFormat", "function spaceUptoLine", "function be("):
        assert old not in pretty
    assert not (root / "vir-bootstrap.js").exists()
    html = (root / "index.html").read_text()
    assert html.count("data-runtime-module=") == 1
    assert "__versoVirResourceUrls" not in html
    assert "__versoVirExpectedExports" not in html

def test_complete_native_segments_tags_classes_and_bindings_in_dom(page, server, site_dir):
    open_demo(page, server)
    corpus = json.loads((site_dir / "native-corpus.json").read_text())
    actual = page.evaluate("""cases => cases.map(c => {
        const direct = window.versoVir.call("VersoSlides.VirPrettyM.formatSegments", compactFormatToStdFormat(c.format), c.width, c.indent);
        const segments = window.versoVirFormatSegments(c.format, c.width, c.indent);
        const annotations = {'7': {cssClass: 'const', binding: 'outer'},
            '8': {cssClass: 'var', binding: 'inner'}};
        const template = document.createElement('template');
        template.innerHTML = formatToHtml(c.format, annotations, c.width * 10, {spaceWidth: 10});
        return {segments: window.testSegmentsForJSON(segments), direct: window.testSegmentsForJSON(direct),
            isArray: Array.isArray(direct), text: template.content.textContent,
            tagged: [...template.content.querySelectorAll('.token')].map(el => ({
                text: el.textContent,
                classes: [...el.classList], binding: el.getAttribute('data-binding'),
            }))};
    })""", corpus)
    for case, dom in zip(corpus, actual):
        expected = case["result"]["segments"]
        assert dom["isArray"] is True, case["name"]
        assert dom["direct"] == expected, case["name"]
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
            css: span.getAttribute('class'), unsafe: template.content.querySelectorAll('[onclick],[data-evil]').length,
            segments: window.testSegmentsForJSON(window.versoVirFormatSegments(fmt, 80, 0))};
    }""")
    assert result == {"text": '<&"', "binding": 'b"&<', "css": 'var token', "unsafe": 0,
        "segments": [{"text": '<&"', "tags": ["7", "9007199254740993"]}]}


def set_goal(block, format_value, binding):
    block.evaluate("""(block, input) => {
        const tactic = block.querySelector('.tactic');
        const source = tactic.querySelector(':scope > .tactic-state');
        source.innerHTML = '<span>OLD STATIC LAYOUT</span>';
        source.setAttribute('data-rich-format', JSON.stringify([{
            name: null, hypotheses: [], goalPrefix: '⊢ ', ppConclusion: JSON.stringify({
                fmt: input.format, annotations: {'7': {cssClass: 'var', binding: input.binding}},
            }),
        }]));
        tactic.querySelector('.token').setAttribute('data-binding', input.binding);
        tactic.dispatchEvent(new MouseEvent('click', {bubbles: true}));
    }""", {"format": format_value, "binding": binding})


def capture_expected_format_errors(page):
    # These negative cases intentionally exercise production diagnostic logging.
    # Retain those calls for assertions; all other console errors still reach
    # the shared page fixture and fail the test.
    page.add_init_script("""(() => {
        window.expectedFormatErrors = [];
        const original = console.error;
        console.error = (...args) => {
            if (args[0] === 'VIR formatting failed' || args[0] === 'Lean expression formatting failed') {
                window.expectedFormatErrors.push(args);
            } else original.apply(console, args);
        };
    })()""")


def test_shared_goal_preserves_ordinary_binding_interaction(page, server):
    errors = []
    page.on("pageerror", lambda error: errors.append(str(error)))
    open_demo(page, server)
    block, panel, _ = open_proof_panel(page)
    binding = "ordinary-binding"
    set_goal(block, [7, "7", 'x<&"'], binding)
    token = panel.locator(".reflowed .token").first
    expect(token).to_have_text('x<&"')
    assert token.get_attribute("data-binding") == binding
    token.dispatch_event("mouseover")
    expect(token).to_have_class("var token binding-hl")
    assert block.locator("code .token.binding-hl").count() >= 1
    token.dispatch_event("mouseout")
    expect(block.locator(".binding-hl")).to_have_count(0)
    assert errors == []


def test_rejected_format_is_visible_without_static_layout_substitution_or_probe_retention(page, server):
    capture_expected_format_errors(page)
    errors = []
    page.on("pageerror", lambda error: errors.append(str(error)))
    open_demo(page, server)
    block, panel, _ = open_proof_panel(page)
    page.evaluate("window.originalProgram = window.versoVir")
    set_goal(block, [3, 1.5, "invalid"], "bad")
    expect(panel.get_by_role("alert")).to_have_text("This Lean expression could not be formatted.")
    assert "OLD STATIC LAYOUT" not in panel.inner_text()
    expect(panel.locator('[style*="visibility: hidden"]')).to_have_count(0)
    assert page.evaluate("window.versoVir === window.originalProgram && window.versoVir.status === 'active'")
    set_goal(block, [7, "7", "recovered"], "good")
    expect(panel.locator(".reflowed .token")).to_have_text("recovered")
    expect(panel.get_by_role("alert")).to_have_count(0)
    expect(panel.locator('[style*="visibility: hidden"]')).to_have_count(0)
    assert page.evaluate("expectedFormatErrors.some(e => e[0] === 'VIR formatting failed')")
    assert page.evaluate("expectedFormatErrors.some(e => e[0] === 'Lean expression formatting failed')")
    assert errors == []


def test_vir_numeric_admission_keeps_the_same_program_usable(page, server):
    capture_expected_format_errors(page)
    errors = []
    page.on("pageerror", lambda error: errors.append(str(error)))
    page.add_init_script("window.numericUnhandled = []; window.addEventListener('unhandledrejection', e => window.numericUnhandled.push(String(e.reason)))")
    open_demo(page, server)
    result = page.evaluate("""() => {
        const program = window.versoVir, facade = window.versoVirFormatSegments;
        const rejected = [];
        for (const [format, width, indent] of [
            [[3, 1.5, 'x'], 80, 0], [[7, -1, 'x'], 80, 0],
            [[7, Number.MAX_SAFE_INTEGER + 1, 'x'], 80, 0],
            ['x', 1.5, 0], ['x', -1, 0], ['x', NaN, 0], ['x', 80, -1],
        ]) {
            let error;
            try { facade(format, width, indent); } catch (cause) { error = cause; }
            rejected.push(!!error && program.status === 'active' && window.versoVir === program);
        }
        const numeric = facade([3, -2, [7, 7, 'x']], 80, 0);
        const exact = facade([7, '9007199254740993', 'y'], 80, 0);
        const big = facade([7, 9007199254740993n, 'z'], 80, 0);
        return {rejected, numeric: window.testSegmentsForJSON(numeric),
            exact: window.testSegmentsForJSON(exact), big: window.testSegmentsForJSON(big),
            recovered: facade('valid', 80, 0),
            same: window.versoVir === program && window.versoVirFormatSegments === facade,
            state: window.versoVirState};
    }""")
    assert result == {"rejected": [True] * 7,
        "numeric": [{"text": "x", "tags": ["7"]}],
        "exact": [{"text": "y", "tags": ["9007199254740993"]}],
        "big": [{"text": "z", "tags": ["9007199254740993"]}],
        "recovered": [{"text": "valid", "tags": []}], "same": True, "state": "ready"}
    page.evaluate("() => new Promise(resolve => setTimeout(resolve, 0))")
    assert page.evaluate("window.numericUnhandled") == []
    assert page.evaluate("expectedFormatErrors.filter(e => e[0] === 'VIR formatting failed').length") == 7
    assert errors == []
