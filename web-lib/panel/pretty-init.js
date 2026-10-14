// @ts-check

/* Initialize the document's Lean formatter once. */
(function () {
    "use strict";
    const script = /** @type {HTMLScriptElement} */ (document.currentScript);
    const urls =
        /** @type {{runtimeModule: string, runtimeManifest: string, programManifest: string}} */ (
            script.dataset
        );

    /** @param {string} label @param {unknown} error */
    function report(label, error) {
        try {
            console.error(label, error);
        } catch (_) {
            /* Best-effort diagnostics. */
        }
    }

    /** @param {"loading" | "ready" | "failed"} state */
    function setState(state) {
        window.versoVirState = state;
        try {
            window.dispatchEvent(new Event("verso-vir-statechange"));
        } catch (error) {
            report("VIR state notification failed", error);
        }
    }

    async function initialize() {
        const runtimeModuleUrl = new URL(urls.runtimeModule, document.baseURI);
        const loader = await import(runtimeModuleUrl.href);
        const program = await loader.createProgram({
            runtimeManifestUrl: new URL(urls.runtimeManifest, document.baseURI),
            programManifestUrl: new URL(urls.programManifest, document.baseURI),
        });
        window.versoVir = program;
        window.versoVirFormatSegments = (format, width, indent) => {
            try {
                return formatCompactSegments(program, format, width, indent);
            } catch (error) {
                report("VIR formatting failed", error);
                if (program.status !== "active") {
                    delete window.versoVirFormatSegments;
                    setState("failed");
                }
                throw error;
            }
        };
        setState("ready");
        return program;
    }

    const ready = initialize();
    window.versoVirReady = ready;
    ready.catch((error) => {
        report("VIR initialization failed", error);
        setState("failed");
    });
    setState("loading");
})();
