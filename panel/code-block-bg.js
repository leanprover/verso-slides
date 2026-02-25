function parseColor(str) {
    if (!str) return null;
    var h = str.match(/^#([0-9a-f]{3,8})$/i);
    if (h) {
        var hex = h[1];
        if (hex.length === 3)
            return [
                parseInt(hex[0] + hex[0], 16),
                parseInt(hex[1] + hex[1], 16),
                parseInt(hex[2] + hex[2], 16),
            ];
        if (hex.length >= 6)
            return [
                parseInt(hex.slice(0, 2), 16),
                parseInt(hex.slice(2, 4), 16),
                parseInt(hex.slice(4, 6), 16),
            ];
    }
    var m = str.match(/[\d.]+/g);
    if (m && m.length >= 3) return [parseFloat(m[0]), parseFloat(m[1]), parseFloat(m[2])];
    return null;
}
function slideBgColor(section) {
    var attr = section && section.getAttribute("data-background-color");
    if (attr) {
        var c = parseColor(attr);
        if (c) return c;
    }
    var bgEl = Reveal.getSlideBackground(section);
    if (bgEl) {
        var bg = getComputedStyle(bgEl).backgroundColor;
        var c = parseColor(bg);
        if (c && (c[0] !== 0 || c[1] !== 0 || c[2] !== 0 || bg.indexOf("0)") === -1)) return c;
    }
    var revealBg = getComputedStyle(document.querySelector(".reveal")).backgroundColor;
    return parseColor(revealBg);
}
function updateSlides() {
    document.querySelectorAll("section").forEach(function (section) {
        var rgb = slideBgColor(section);
        if (!rgb) return;
        var lum = (0.2126 * rgb[0]) / 255 + (0.7152 * rgb[1]) / 255 + (0.0722 * rgb[2]) / 255;
        var isLight = lum > 0.5;
        section.classList.toggle("slide-light-bg", isLight);
        var codeBg = isLight ? "rgba(0,0,0,0.04)" : "rgba(255,255,255,0.08)";
        section.querySelectorAll("code.hl.lean.block").forEach(function (el) {
            el.style.background = codeBg;
            el.style.setProperty("--verso-info-indicator-color", isLight ? "#2255cc" : "#6a9fff");
            var panel = el.closest(".code-with-panel");
            if (panel) {
                var panelCell = panel.querySelector(".panel-cell");
                if (panelCell) panelCell.style.background = codeBg;
            }
        });
    });
}
Reveal.on("ready", updateSlides);
Reveal.on("slidechanged", updateSlides);
