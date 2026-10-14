"""Basic asynchronous formatter readiness and failure using the emitted loader."""
from playwright.sync_api import expect


def hold_or_fail_wasm(page, fail=False):
    errors = []
    page.on("pageerror", lambda error: errors.append(str(error)))
    page.add_init_script("""(() => {
        const fail = FAIL;
        const original = window.fetch;
        window.formatterProbe = {requests: 0, unhandled: []};
        window.addEventListener('unhandledrejection', e => formatterProbe.unhandled.push(String(e.reason)));
        window.fetch = (url, init) => {
            if (!String(url).endsWith('/runtime.wasm')) return original(url, init);
            formatterProbe.requests++;
            if (fail) return Promise.reject(new Error('test acquisition failure'));
            return new Promise(resolve => {
                formatterProbe.release = () => resolve(original(url, init));
            });
        };
    })()""".replace("FAIL", "true" if fail else "false"))
    return errors


def select_goal(page):
    page.evaluate("""() => {
        const sections = [...document.querySelectorAll('.slides > section')];
        Reveal.slide(sections.findIndex(s => s.querySelector('.code-with-panel .tactic')), 0, 0);
    }""")
    block = page.locator('.slides > section.present .code-with-panel', has=page.locator('.tactic')).first
    block.locator('.tactic:visible').first.click()
    return block, block.locator('.info-panel')


def test_pending_formatter_keeps_navigation_and_current_selection_usable(page, server):
    errors = hold_or_fail_wasm(page)
    page.goto(f"{server}/code/index.html")
    page.wait_for_function("window.Reveal?.isReady() && window.formatterProbe.requests === 1")
    block, panel = select_goal(page)
    expect(panel.get_by_role('status')).to_have_text('Loading Lean formatting…')
    block.locator('.tactic:visible').nth(1).click()
    source = block.evaluate("el => el._activeSource.getAttribute('data-tactic-range')")
    page.evaluate('window.formatterProbe.release()')
    page.wait_for_function("window.versoVirState === 'ready'")
    expect(panel.locator('.reflowed').first).not_to_be_empty()
    assert block.evaluate("el => el._activeSource.getAttribute('data-tactic-range')") == source
    expect(panel.get_by_role('status')).to_have_count(0)
    assert page.evaluate('window.formatterProbe.unhandled') == []
    assert errors == []


def test_initialization_failure_reports_without_replacing_the_formatter(page, server):
    errors = hold_or_fail_wasm(page, fail=True)
    page.goto(f"{server}/code/index.html")
    page.wait_for_function("window.Reveal?.isReady() && window.versoVirState === 'failed'")
    _, panel = select_goal(page)
    expect(panel.get_by_role('status')).to_have_text('Lean formatting is unavailable.')
    assert page.evaluate('window.formatterProbe.requests') == 1
    assert page.evaluate('window.versoVirFormatSegments === undefined')
    assert page.evaluate('window.formatterProbe.unhandled') == []
    assert errors == []
