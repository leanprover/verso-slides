const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const source = fs.readFileSync(path.join(__dirname, "../web-lib/panel/pretty-init.js"), "utf8");
const deferred = () => {
    let resolve, reject;
    const promise = new Promise((yes, no) => {
        resolve = yes;
        reject = no;
    });
    return { promise, resolve, reject };
};

function fixture(call) {
    const loading = deferred(),
        creation = deferred(),
        started = deferred();
    const diagnostics = [],
        calls = [],
        formatCalls = [],
        states = [];
    const program = {
        status: "active",
        call(declaration, ...args) {
            formatCalls.push({ declaration, args });
            return call ? call(program, ...args) : [{ text: "formatted", tags: [] }];
        },
    };
    const window = {
        dispatchEvent(event) {
            assert.equal(event.type, "verso-vir-statechange");
            states.push(this.versoVirState);
        },
    };
    const context = vm.createContext({
        window,
        URL,
        Event,
        document: {
            baseURI: "http://slides.test/nested/deck/",
            currentScript: {
                dataset: {
                    runtimeModule: "lib/runtime.js",
                    runtimeManifest: "lib/runtime.json",
                    programManifest: "lib/program.json",
                },
            },
        },
        console: {
            error(...args) {
                diagnostics.push(args);
            },
        },
        __loadRuntime: () => loading.promise,
    });
    // Control only module acquisition; execute the actual adapter/bootstrap.
    const marker = "import(runtimeModuleUrl.href)";
    assert.equal(source.split(marker).length, 2);
    vm.runInContext(
        fs.readFileSync(path.join(__dirname, "../web-lib/panel/pretty.js"), "utf8"),
        context,
    );
    vm.runInContext(source.replace(marker, "__loadRuntime(runtimeModuleUrl.href)"), context);
    const loader = {
        createProgram(value) {
            calls.push(value);
            started.resolve();
            return creation.promise;
        },
    };
    return {
        window,
        loading,
        creation,
        started,
        program,
        diagnostics,
        loader,
        calls,
        formatCalls,
        states,
    };
}

async function ready(f) {
    f.loading.resolve(f.loader);
    await f.started.promise;
    f.creation.resolve(f.program);
    await f.window.versoVirReady;
}

test("initialization publishes readiness and resolves library-owned relative URLs", async () => {
    const f = fixture();
    const published = f.window.versoVirReady;
    assert.equal(typeof published.then, "function");
    assert.equal(f.window.versoVirState, "loading");
    assert.equal(f.window.versoVirFormatSegments, undefined);
    f.loading.resolve(f.loader);
    await f.started.promise;
    assert.deepEqual(Object.keys(f.calls[0]).sort(), ["programManifestUrl", "runtimeManifestUrl"]);
    assert.equal(
        f.calls[0].programManifestUrl.href,
        "http://slides.test/nested/deck/lib/program.json",
    );
    assert.equal(
        f.calls[0].runtimeManifestUrl.href,
        "http://slides.test/nested/deck/lib/runtime.json",
    );
    assert.equal(f.window.versoVir, undefined);
    f.creation.resolve(f.program);
    assert.equal(await published, f.program);
    assert.equal(f.window.versoVirReady, published);
    assert.equal(f.window.versoVir, f.program);
    assert.equal(f.window.versoVirState, "ready");
    assert.deepEqual(f.states, ["loading", "ready"]);
});

for (const phase of ["import", "creation"]) {
    test(`${phase} failure preserves primary diagnostics and closes initialization`, async () => {
        const f = fixture();
        const failure = new Error("initialization failed", { cause: new Error("raw cause") });
        if (phase === "import") f.loading.reject(failure);
        else {
            f.loading.resolve(f.loader);
            await f.started.promise;
            f.creation.reject(failure);
        }
        await assert.rejects(f.window.versoVirReady, (e) => e === failure);
        assert.equal(f.diagnostics[0][1], failure);
        assert.equal(f.window.versoVirState, "failed");
        assert.equal(f.window.versoVir, undefined);
        assert.equal(f.window.versoVirFormatSegments, undefined);
        assert.equal(f.calls.length, phase === "import" ? 0 : 1);
        assert.equal(f.window.versoVirRetry, undefined);
    });
}

test("malformed compact input leaves the same initialized program usable", async () => {
    const f = fixture();
    await ready(f);
    assert.throws(
        () => f.window.versoVirFormatSegments([3, 1, "x", "extra"], 80, 0),
        (e) => e.code === "invalidInput",
    );
    assert.equal(f.formatCalls.length, 0);
    assert.equal(f.window.versoVirFormatSegments("valid", 4097, 0)[0].text, "formatted");
    assert.equal(f.formatCalls[0].declaration, "VersoSlides.VirPrettyM.formatSegments");
    assert.equal(f.window.versoVir, f.program);
    assert.equal(f.window.versoVirState, "ready");
    assert.equal(f.calls.length, 1);
});

for (const raw of [new Error("argument rejected"), null, undefined]) {
    test(`active request failure (${typeof raw}) preserves raw evidence and same-program recovery`, async () => {
        let rejected = false;
        const f = fixture(() => {
            if (!rejected) {
                rejected = true;
                throw raw;
            }
            return [{ text: "recovered", tags: [] }];
        });
        await ready(f);
        const facade = f.window.versoVirFormatSegments;
        assert.throws(
            () => facade("x", 80, 0),
            (e) => e === raw,
        );
        assert.equal(f.diagnostics.at(-1)[1], raw);
        assert.equal(f.window.versoVirState, "ready");
        assert.equal(f.window.versoVirFormatSegments, facade);
        assert.equal(facade("valid", 80, 0)[0].text, "recovered");
        assert.equal(f.calls.length, 1);
    });
}

test("failed runtime closes formatting without recreation or replay", async () => {
    const failure = new Error("runtime failed");
    const f = fixture((program) => {
        program.status = "failed";
        throw failure;
    });
    await ready(f);
    assert.throws(
        () => f.window.versoVirFormatSegments("x", 80, 0),
        (e) => e === failure,
    );
    assert.equal(f.diagnostics.at(-1)[1], failure);
    assert.equal(f.window.versoVirState, "failed");
    assert.equal(f.window.versoVirFormatSegments, undefined);
    assert.equal(f.formatCalls.length, 1);
    assert.equal(f.calls.length, 1);
});
