// Renders Verso's inline and display math elements with KaTeX.
//
// Verso emits `<code class="math inline">TEX</code>` and
// `<code class="math display">TEX</code>`. Reveal.js's KaTeX plugin uses
// auto-render, which explicitly skips <code> tags, so we render them here.
//
// A document-level prelude of `\def` / `\newcommand` / `\gdef` commands
// may be set on `window.__versoMathPrelude` by the page template; it is
// rendered into a shared `macros` object with `globalGroup: true` so the
// definitions are in scope for every math element that is rendered.

/**
 * Typesets the math elements inside `root` with KaTeX.
 *
 * Scripts that insert generated HTML into the page, such as hover contents,
 * call this on the inserted content. Each math element is typeset once: its
 * TeX source is replaced by KaTeX's output.
 */
const versoRenderMath = (() => {
    /** @type {Record<string, unknown> | null} */
    let macros = null;

    /**
     * Returns the shared macro table, evaluating the prelude on first use.
     * @param {NonNullable<typeof katex>} k
     * @returns {Record<string, unknown>}
     */
    const getMacros = (k) => {
        if (macros) return macros;
        macros = {};
        const prelude = window.__versoMathPrelude;
        if (typeof prelude === "string" && prelude.length > 0) {
            try {
                k.renderToString(prelude, {
                    macros,
                    globalGroup: true,
                    throwOnError: false,
                    displayMode: false,
                });
            } catch (e) {
                console.error("KaTeX prelude failed to parse:", e);
            }
        }
        return macros;
    };

    /** @param {ParentNode} root */
    return (root) => {
        if (typeof katex === "undefined") return;
        const table = getMacros(katex);
        for (const m of root.querySelectorAll("code.math.inline, code.math.display")) {
            const el = /** @type {HTMLElement} */ (m);
            const displayMode = el.classList.contains("display");
            katex.render(el.textContent ?? "", el, {
                throwOnError: false,
                displayMode,
                macros: table,
            });
        }
    };
})();

document.addEventListener("DOMContentLoaded", () => versoRenderMath(document));
