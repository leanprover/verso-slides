// Renders Verso's inline and display math elements with KaTeX.
//
// Verso emits `<code class="math inline">TEX</code>` and
// `<code class="math display">TEX</code>`. Reveal.js's KaTeX plugin uses
// auto-render, which explicitly skips <code> tags, so we render them here.

document.addEventListener("DOMContentLoaded", () => {
  if (typeof katex === "undefined") return;
  for (const m of document.querySelectorAll("code.math.inline")) {
    katex.render(m.textContent, m, { throwOnError: false, displayMode: false });
  }
  for (const m of document.querySelectorAll("code.math.display")) {
    katex.render(m.textContent, m, { throwOnError: false, displayMode: true });
  }
});
