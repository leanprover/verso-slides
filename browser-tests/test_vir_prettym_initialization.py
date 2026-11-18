"""Basic asynchronous formatter readiness and failure using the emitted loader."""
from playwright.sync_api import expect

from pretty_helpers import hold_or_fail_wasm, select_goal


def test_pending_formatter_keeps_navigation_and_current_selection_usable(page, server):
    hold_or_fail_wasm(page)
    page.goto(f"{server}/code/index.html")
    page.wait_for_function("window.Reveal?.isReady() && window.formatterProbe.requests === 1")
    block, panel = select_goal(page)
    expect(panel.get_by_role('status')).to_have_text('Loading Lean formatting…')
    block.locator('.tactic:visible').nth(1).click()
    page.evaluate('window.formatterProbe.release()')
    page.wait_for_function("window.versoVirState === 'ready'")
    expect(panel.locator('.reflowed').first).not_to_be_empty()
    expect(panel.locator('.name')).to_have_text(['p', 'q', 'hp', 'hq'])
    expect(panel.locator('.goal-vdash')).to_have_text('⊢ ')
    expect(panel.get_by_role('status')).to_have_count(0)
    assert page.evaluate('window.formatterProbe.unhandled') == []


def test_initialization_failure_reports_without_replacing_the_formatter(page, server):
    hold_or_fail_wasm(page, fail=True)
    page.goto(f"{server}/code/index.html")
    page.wait_for_function("window.Reveal?.isReady() && window.versoVirState === 'failed'")
    _, panel = select_goal(page)
    expect(panel.get_by_role('status')).to_have_text('Lean formatting is unavailable.')
    assert page.evaluate('window.formatterProbe.requests') == 1
    assert page.evaluate('window.versoVirFormatSegments === undefined')
    assert page.evaluate('window.formatterProbe.unhandled') == []
    assert page.evaluate('window.formatterProbe.diagnostics.length') == 1


def test_panel_scripts_initialize_when_reveal_is_already_ready(page, server):
    """Loading a script after Reveal's ready event must still enable interaction."""
    def observe_ready(route):
        response = route.fetch()
        route.fulfill(response=response, body=response.text() + "\n" +
            "Reveal.on('ready', () => { window.revealReadyObserved = true; });")

    def load_after_ready(route):
        response = route.fetch()
        page.wait_for_function("window.revealReadyObserved === true")
        route.fulfill(response=response)

    page.route("**/dist/reveal.js", observe_ready)
    page.route("**/lib/panel.js", load_after_ready)
    page.route("**/lib/lightbox.js", load_after_ready)
    page.goto(f"{server}/code/index.html")
    page.wait_for_function("window.versoVirState === 'ready'")

    block, panel = select_goal(page)
    expect(panel.locator('.reflowed').first).not_to_be_empty()

    page.evaluate("""() => {
        const sections = [...document.querySelectorAll('.slides > section')];
        const index = sections.findIndex(s => s.querySelector('code.hl.lean.inline [data-verso-hover]'));
        Reveal.slide(index, 0, 0);
    }""")
    token = page.locator('.slides > section.present code.hl.lean.inline [data-verso-hover]').first
    token.click()
    expect(page.locator('.r-overlay-lean-hover')).to_be_visible()
    expect(page.locator('.lean-hover-inner .reflowed').first).not_to_be_empty()
