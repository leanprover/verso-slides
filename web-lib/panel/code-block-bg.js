/**
 * @param {string | null | undefined} str
 * @returns {[number, number, number] | null}
 */
function parseColor(str) {
    if (!str) return null;
    const h = str.match(/^#([0-9a-f]{3,8})$/i);
    if (h) {
        // The pattern has one non-optional group, so a match has it
        const hex = /** @type {string} */ (h[1]);
        if (hex.length === 3)
            return [
                parseInt(hex.charAt(0).repeat(2), 16),
                parseInt(hex.charAt(1).repeat(2), 16),
                parseInt(hex.charAt(2).repeat(2), 16),
            ];
        if (hex.length >= 6)
            return [
                parseInt(hex.slice(0, 2), 16),
                parseInt(hex.slice(2, 4), 16),
                parseInt(hex.slice(4, 6), 16),
            ];
    }
    const [r, g, b] = str.match(/[\d.]+/g) ?? [];
    if (r !== undefined && g !== undefined && b !== undefined)
        return [parseFloat(r), parseFloat(g), parseFloat(b)];
    return null;
}
/**
 * @param {Element} section
 * @returns {[number, number, number] | null}
 */
function slideBgColor(section) {
    const attr = section && section.getAttribute("data-background-color");
    if (attr) {
        const c = parseColor(attr);
        if (c) return c;
    }
    const bgEl = Reveal.getSlideBackground(section);
    if (bgEl) {
        const bg = getComputedStyle(bgEl).backgroundColor;
        const c = parseColor(bg);
        if (c && (c[0] !== 0 || c[1] !== 0 || c[2] !== 0 || bg.indexOf("0)") === -1)) return c;
    }
    const revealRoot = document.querySelector(".reveal");
    if (!revealRoot) return null;
    const revealBg = getComputedStyle(revealRoot).backgroundColor;
    return parseColor(revealBg);
}
function updateSlides() {
    document.querySelectorAll("section").forEach((section) => {
        const rgb = slideBgColor(section);
        if (!rgb) return;
        const lum = (0.2126 * rgb[0]) / 255 + (0.7152 * rgb[1]) / 255 + (0.0722 * rgb[2]) / 255;
        const isLight = lum > 0.5;
        section.classList.toggle("slide-light-bg", isLight);
        const codeBg = isLight ? "rgba(0,0,0,0.04)" : "rgba(255,255,255,0.08)";
        section.querySelectorAll("code.hl.lean.block").forEach((el) => {
            const codeEl = /** @type {HTMLElement} */ (el);
            codeEl.style.background = codeBg;
            codeEl.style.setProperty(
                "--verso-info-indicator-color",
                isLight ? "#2255cc" : "#6a9fff",
            );
            const panel = codeEl.closest(".code-with-panel");
            if (panel) {
                const panelCell = /** @type {HTMLElement | null} */ (
                    panel.querySelector(".panel-cell")
                );
                if (panelCell) panelCell.style.background = codeBg;
            }
        });
        section.querySelectorAll("pre").forEach((el) => {
            if (el.closest(".code-with-panel")) return;
            el.style.background = codeBg;
        });
    });
}
Reveal.on("ready", updateSlides);
Reveal.on("slidechanged", updateSlides);
