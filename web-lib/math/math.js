// Renders Verso's inline and display math elements with KaTeX.
//
// Verso emits `<code class="math inline">TEX</code>` and
// `<code class="math display">TEX</code>`. Reveal.js's KaTeX plugin uses
// auto-render, which explicitly skips <code> tags, so we render them here.
//
// A document-level prelude of `\def` / `\newcommand` / `\gdef` commands
// may be set on `window.__versoMathPrelude` by the page template; it is
// rendered into a shared `macros` object with `globalGroup: true` so the
// definitions are in scope for every math element rendered below.

document.addEventListener("DOMContentLoaded", () => {
    if (typeof katex === "undefined") return;
    /** @type {Record<string, unknown>} */
    const macros = {};
    const prelude = window.__versoMathPrelude;
    if (typeof prelude === "string" && prelude.length > 0) {
        try {
            katex.renderToString(prelude, {
                macros,
                globalGroup: true,
                throwOnError: false,
                displayMode: false,
            });
        } catch (e) {
            console.error("KaTeX prelude failed to parse:", e);
        }
    }
    for (const m of document.querySelectorAll("code.math.inline")) {
        const el = /** @type {HTMLElement} */ (m);
        katex.render(el.textContent ?? "", el, { throwOnError: false, displayMode: false, macros });
    }
    for (const m of document.querySelectorAll("code.math.display")) {
        const el = /** @type {HTMLElement} */ (m);
        katex.render(el.textContent ?? "", el, { throwOnError: false, displayMode: true, macros });
    }
});
