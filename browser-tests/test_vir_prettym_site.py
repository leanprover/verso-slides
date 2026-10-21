"""Compare the ordinary code fixture's published VIR program with native Lean."""

import hashlib
import json
from bs4 import BeautifulSoup

from playwright.sync_api import expect


def test_published_bundles_and_urls(site_dir):
    root = site_dir / "code"
    assert (root / "index.html").is_file()
    bootstrap = (root / "index.html").read_text()
    assert not (root / "vir-bootstrap.js").exists()
    scripts = BeautifulSoup(bootstrap, "html.parser").select("script[data-runtime-module]")
    assert len(scripts) == 1
    urls = {key: scripts[0][attribute] for key, attribute in [
        ("runtimeModule", "data-runtime-module"), ("runtimeManifest", "data-runtime-manifest"),
        ("programManifest", "data-program-manifest")]}
    assert all(not url.startswith("/") and ".lake" not in url for url in urls.values())
    assert all((root / url).is_file() for url in urls.values())

    # Check the resources used by this page. Older bundles may still be present
    # after rebuilding the fixtures with a new runtime or formatter.
    manifests = {kind: root / urls[f"{kind}Manifest"] for kind in ("runtime", "program")}
    assert len(set(manifests.values())) == 2
    compatibilities = []
    for kind, manifest in manifests.items():
        data = json.loads(manifest.read_text())
        assert data["descriptor"]["kind"] == kind
        assert data["descriptor"]["schemaVersion"] == 2
        assert "exports" not in data["descriptor"]
        if data["descriptor"]["kind"] == "program":
            assert data["descriptor"]["logicalId"] == "VersoSlides.VirPrettyM"
        assert manifest.parent.name == data["contentId"]
        compatibility = data["descriptor"]["compatibility"]
        assert set(compatibility) == {"leanRevision", "virVersion"}
        compatibilities.append(compatibility)
        for entry in data["descriptor"]["files"]:
            content = (manifest.parent / entry["path"]).read_bytes()
            assert len(content) == entry["byteLength"]
            assert hashlib.sha256(content).hexdigest() == entry["sha256"]
    assert compatibilities[0] == compatibilities[1]


def open_demo(page, server):
    errors = []
    page.on("pageerror", lambda error: errors.append(str(error)))
    page.goto(f"{server}/code/index.html")
    page.wait_for_function("window.Reveal?.isReady() === true")
    page.wait_for_function("window.versoVir !== undefined", timeout=30000)
    assert not errors, errors
    assert page.locator('[role="alert"]').count() == 0
    # Test-only JSON projection: assert raw ABI tags are BigInts before sending
    # exact decimal IDs across the browser/Python boundary. Production stays raw.
    page.evaluate("""() => {
        window.testSegmentsForJSON = segments => segments.map(({text, tags}) => ({
            text, tags: tags.map(tag => {
                if (typeof tag !== 'bigint') throw Error('expected a BigInt tag');
                return tag.toString();
            }),
        }));
    }""")


def test_same_wrapper_native_corpus(page, server, site_dir):
    open_demo(page, server)
    corpus = json.loads((site_dir / "native-corpus.json").read_text())
    assert len(corpus) == 8
    for case in corpus:
        actual = page.evaluate("""c => window.testSegmentsForJSON(window.versoVirFormatSegments(
            c.format, c.width, c.indent))""", case)
        assert actual == case["result"]["segments"], case["name"]


def test_published_host_call(page, server):
    open_demo(page, server)
    assert page.evaluate("""() => window.testSegmentsForJSON(window.versoVirFormatSegments(
        [7, '7', 'hello'], 80, 0))""") == [{"text": "hello", "tags": ["7"]}]


def test_only_full_root_declaration_is_callable(page, server):
    open_demo(page, server)
    assert page.evaluate("""() => {
        const program = window.versoVir;
        const rejected = ['formatSegments', 'VersoSlides.Pretty.formatSegments'].map(name => {
            try { program.call(name, {kind: 'text', value: 'x'}, 80, 0); return false; }
            catch (error) { return error.message.startsWith('unknown program export '); }
        });
        const segments = program.call('VersoSlides.VirPrettyM.formatSegments',
            compactFormatToStdFormat([7, '9007199254740993', 'still usable']), 80, 0);
        return {rejected, active: program.status === 'active',
            segments: window.testSegmentsForJSON(segments)};
    }""") == {"rejected": [True, True], "active": True,
        "segments": [{"text": "still usable", "tags": ["9007199254740993"]}]}


def open_proof_panel(page):
    result = page.evaluate("""() => {
        const sections = [...document.querySelectorAll('.slides > section')];
        for (let i = 0; i < sections.length; i++) {
            if (sections[i].querySelector('.code-with-panel .tactic')) {
                Reveal.slide(i, 0, 0);
                return i;
            }
        }
        return -1;
    }""")
    assert result >= 0
    page.wait_for_function("(i) => window.Reveal.getIndices().h === i", arg=result)
    block = page.locator(".slides > section.present .code-with-panel", has=page.locator(".tactic")).first
    tactic = block.locator(".tactic:visible").first
    tactic.click()
    panel = block.locator(".info-panel")
    reflowed = panel.locator(".reflowed")
    expect(reflowed.first).not_to_be_empty()
    return block, panel, reflowed


def test_default_panel_reflows_with_wasm(page, server):
    open_demo(page, server)
    block, panel, reflowed = open_proof_panel(page)
    assert not panel.locator('[role="alert"]').count()

    # The existing ResizeObserver path must perform another Wasm render.
    panel.evaluate("el => el.firstElementChild.setAttribute('data-reflow-marker', '1')")
    block.evaluate("""el => {
        el.style.setProperty('--code-ratio', '0.9fr');
        el.style.setProperty('--panel-ratio', '0.1fr');
    }""")
    expect(panel.locator("[data-reflow-marker]")).to_have_count(0, timeout=5000)
    expect(reflowed.first).not_to_be_empty()
