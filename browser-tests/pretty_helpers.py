"""Helpers for the formatter's ordinary emitted code fixture."""
from playwright.sync_api import expect


def open_demo(page, server):
    page.goto(f"{server}/code/index.html")
    page.wait_for_function("window.Reveal?.isReady() && window.versoVirState === 'ready'")
    expect(page.get_by_role('alert')).to_have_count(0)
    # Python cannot receive BigInt JSON values; check their type before conversion.
    page.evaluate("""() => {
        window.testSegmentsForJSON = segments => segments.map(({text, tags}) => ({
            text, tags: tags.map(tag => {
                if (typeof tag !== 'bigint') throw Error('expected a BigInt tag');
                return tag.toString();
            }),
        }));
    }""")


def select_goal(page):
    page.evaluate("""() => {
        const sections = [...document.querySelectorAll('.slides > section')];
        Reveal.slide(sections.findIndex(s => s.querySelector('.code-with-panel .tactic')), 0, 0);
    }""")
    block = page.locator('.slides > section.present .code-with-panel', has=page.locator('.tactic')).first
    block.locator('.tactic:visible').first.click()
    return block, block.locator('.info-panel')


def set_goal(block, format_value, binding='test-binding'):
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


def hold_or_fail_wasm(page, fail=False):
    page.add_init_script("""(() => {
        const fail = FAIL;
        const failure = new Error('test acquisition failure');
        const original = window.fetch;
        window.formatterProbe = {requests: 0, unhandled: []};
        if (fail) {
            window.formatterProbe.diagnostics = [];
            const originalError = console.error;
            console.error = (...args) => {
                if (args[0] === 'VIR initialization failed' && args[1]?.cause === failure)
                    formatterProbe.diagnostics.push(args);
                else originalError.apply(console, args);
            };
        }
        window.addEventListener('unhandledrejection', e => formatterProbe.unhandled.push(String(e.reason)));
        window.fetch = (url, init) => {
            if (!String(url).endsWith('/runtime.wasm')) return original(url, init);
            formatterProbe.requests++;
            if (fail) return Promise.reject(failure);
            return new Promise(resolve => {
                formatterProbe.release = () => resolve(original(url, init));
            });
        };
    })()""".replace("FAIL", "true" if fail else "false"))
