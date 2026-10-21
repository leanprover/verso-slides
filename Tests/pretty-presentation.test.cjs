const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

function fixture() {
    const calls = [],
        diagnostics = [];
    function element() {
        let html = "",
            text = "";
        return {
            children: [],
            parentNode: null,
            attributes: {},
            style: {},
            set innerHTML(value) {
                this.replaceChildren();
                html = value;
            },
            get innerHTML() {
                return html;
            },
            set textContent(value) {
                this.replaceChildren();
                text = value;
            },
            get textContent() {
                return text;
            },
            setAttribute(name, value) {
                this.attributes[name] = value;
            },
            appendChild(el) {
                el.remove();
                el.parentNode = this;
                this.children.push(el);
                return el;
            },
            removeChild(el) {
                const index = this.children.indexOf(el);
                if (index < 0) throw new DOMException("The node is not a child", "NotFoundError");
                this.children.splice(index, 1);
                el.parentNode = null;
                return el;
            },
            remove() {
                this.parentNode?.removeChild(this);
            },
            replaceChildren() {
                for (const child of [...this.children]) this.removeChild(child);
            },
            getBoundingClientRect() {
                return { width: 20 };
            },
        };
    }
    const window = Object.assign(new EventTarget(), {
        versoVirState: "ready",
        versoVirFormatSegments(format, width, indent) {
            calls.push({ format, width, indent });
            return [{ text: "native\n  output", tags: [] }];
        },
    });
    const context = vm.createContext({
        window,
        document: { createElement: element },
        getComputedStyle: () => ({ paddingLeft: "10px", paddingRight: "10px" }),
        console: {
            error(...args) {
                diagnostics.push(args);
            },
        },
    });
    vm.runInContext(
        fs.readFileSync(path.join(__dirname, "../web-lib/panel/pretty.js"), "utf8"),
        context,
    );
    const container = Object.assign(element(), {
        clientWidth: 100,
        getBoundingClientRect: () => ({ width: 200 }),
        querySelectorAll: () => [],
    });
    return { context, window, calls, diagnostics, container, element };
}

test("plain text and hard lines survive HTML escaping exactly", () => {
    const { context } = fixture();
    assert.equal(
        context.segmentsToHtml([{ text: '<&>"\n  😀', tags: [] }], {}),
        "&lt;&amp;&gt;&quot;\n  😀",
    );
    for (const old of [
        "deserializeFormat",
        "spaceUptoLine",
        "spaceUptoLineGroups",
        "pushGroup",
        "be",
    ]) {
        assert.equal(context[old], undefined);
    }
});

test("exact tags select the nearest registered annotation", () => {
    const { context } = fixture();
    const tags = [7n, 9007199254740993n, 99999999999999999999n];
    const annotations = {
        7: { cssClass: "const", binding: "outer" },
        "9007199254740993": { cssClass: "var", binding: "inner" },
    };
    assert.equal(
        context.segmentsToHtml([{ text: "x", tags }], annotations),
        '<span class="var token" data-binding="inner">x</span>',
    );
    assert.equal(context.segmentsToHtml([{ text: "x", tags }], {}), "x");
});

test("goal structure shares indexed formats and escapes names/prefixes", () => {
    const { context } = fixture();
    const result = context.goalsToHtml([
        {
            name: "<g>",
            hypotheses: [
                { names: ['a"', "b&"], ppType: JSON.stringify({ fmt: "Nat", annotations: {} }) },
            ],
            goalPrefix: "<⊢ ",
            ppConclusion: JSON.stringify({ fmt: "α\nβ", annotations: {} }),
        },
    ]);
    assert.equal(result.formats.length, 2);
    assert.equal(result.formats[0].fmt, "Nat");
    assert.equal(result.formats[1].fmt, "α\nβ");
    assert.ok(result.html.includes('class="goal-name">&lt;g&gt;'));
    assert.ok(result.html.includes('class="name">a&quot; b&amp;'));
    assert.ok(result.html.includes('class="goal-vdash">&lt;⊢ '));
    assert.ok(result.html.includes('data-fmt-idx="0"'));
    assert.ok(result.html.includes('data-fmt-idx="1"'));
});

test("pixel-to-column conversion calls only the typed VIR facade without changing text", () => {
    const { context, calls } = fixture();
    const format = [5, [4, "a", 1]];
    assert.equal(context.formatToHtml(format, {}, 11.9, { spaceWidth: 2 }), "native\n  output");
    assert.equal(calls[0].format, format);
    assert.equal(calls[0].width, 5);
    assert.equal(calls[0].indent, 0);
    for (const [width, space] of [
        [NaN, 2],
        [-1, 2],
        [5, 0],
        [5, Infinity],
    ]) {
        assert.throws(
            () => context.formatToHtml(format, {}, width, { spaceWidth: space }),
            (e) => e.code === "measurement",
        );
    }
    assert.equal(calls.length, 1);
});

test("one DOM measurer accounts for Reveal scaling and releases its probe", () => {
    const { context, container } = fixture();
    const measurer = context.createDOMMeasurer(container);
    assert.equal(measurer.spaceWidth, 10);
    assert.equal(measurer.measureElWidth({ getBoundingClientRect: () => ({ width: 80 }) }), 40);
    assert.equal(container.children.length, 1);
    measurer.cleanup();
    assert.equal(container.children.length, 0);
});

for (const kind of ["signature", "goal"]) {
    for (const fails of [false, true]) {
        test(`shared ${kind} rendering always releases measurement (${fails ? "failure" : "success"})`, () => {
            const { context, window, container, element, calls } = fixture();
            const raw = { unchanged: "native error" };
            if (fails)
                window.versoVirFormatSegments = () => {
                    throw raw;
                };
            const source = element();
            const data =
                kind === "signature"
                    ? { fmt: "sig", annotations: {} }
                    : [
                          {
                              name: null,
                              hypotheses: [],
                              goalPrefix: "⊢ ",
                              ppConclusion: JSON.stringify({ fmt: "goal", annotations: {} }),
                          },
                      ];
            const render = () =>
                kind === "signature"
                    ? context.renderFormat(container, source, data, context.contentWidth(container))
                    : context.renderGoals(container, data);
            const span = {
                getAttribute: () => "0",
                closest: () => ({ getBoundingClientRect: () => ({ width: 80 }) }),
            };
            container.querySelectorAll = () => [span];
            if (fails) assert.throws(render, (e) => e === raw);
            else {
                render();
                assert.equal(calls[0].width, kind === "signature" ? 8 : 4);
                assert.equal(
                    kind === "signature" ? source.innerHTML : span.innerHTML,
                    kind === "signature"
                        ? '<span class="reflowed">native\n  output</span>'
                        : "native\n  output",
                );
            }
            assert.equal(container.children.length, 0);
        });
    }
}

test("terminal redraw during shared rendering preserves the original formatting failure", () => {
    const { context, window, container } = fixture();
    const failure = new Error("runtime formatting failed");
    const goals = [
        {
            name: null,
            hypotheses: [],
            goalPrefix: "⊢ ",
            ppConclusion: JSON.stringify({ fmt: "goal", annotations: {} }),
        },
    ];
    const span = {
        getAttribute: () => "0",
        closest: () => ({ getBoundingClientRect: () => ({ width: 80 }) }),
    };
    container.querySelectorAll = () => [span];
    let redraws = 0;
    window.addEventListener("verso-vir-statechange", () => {
        redraws++;
        container.innerHTML = "";
        context.showFormattingStatus(container);
    });
    window.versoVirFormatSegments = () => {
        window.versoVirState = "failed";
        window.dispatchEvent(new Event("verso-vir-statechange"));
        throw failure;
    };
    assert.throws(
        () => context.renderGoals(container, goals),
        (error) => error === failure,
    );
    assert.equal(redraws, 1);
    assert.equal(container.children.length, 1);
    assert.equal(container.children[0].attributes.role, "status");
    assert.equal(container.children[0].textContent, "Lean formatting is unavailable.");
});

test("formatting failure reports raw evidence and deliberate presentation", () => {
    const { context, container, diagnostics } = fixture();
    for (const raw of [null, undefined, { raw: "cause" }]) {
        context.showFormattingFailure(container, raw);
        assert.equal(diagnostics.at(-1)[1], raw);
        assert.equal(container.children.at(-1).attributes.role, "alert");
        assert.equal(
            container.children.at(-1).textContent,
            "This Lean expression could not be formatted.",
        );
    }
});

test("compact adapter passes scalar values and dimensions unchanged to VIR", () => {
    const { context } = fixture();
    const calls = [];
    const program = {
        call(declaration, ...args) {
            calls.push({ declaration, args });
            return [];
        },
    };
    for (const scalar of [7, -2, 1.5, NaN, 9007199254740993n, "9007199254740993", " 007 "]) {
        const fmt = [3, scalar, [7, scalar, "x"]];
        context.formatCompactSegments(program, fmt, scalar, scalar);
        const call = calls.at(-1);
        assert.equal(call.declaration, "VersoSlides.VirPrettyM.formatSegments");
        assert.equal(call.args[0].fields.indent, scalar);
        assert.equal(call.args[0].fields.f.fields.arg1, scalar);
        assert.equal(call.args[1], scalar);
        assert.equal(call.args[2], scalar);
    }
    assert.equal(context.formatScalar, undefined);
    assert.equal(context.checkFormatDimensions, undefined);
});
