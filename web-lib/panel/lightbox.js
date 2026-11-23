// @ts-check
/* Lightbox overlay for inline Lean term hover info in reveal.js slides. */
(function () {
    "use strict";

    /** @type {Record<string, *> | null} */
    let docsJson = null;

    /** @type {HTMLElement | null} */
    let currentOverlay = null;

    /** @type {HTMLElement | null} */
    let currentBackdrop = null;

    /** @type {HTMLElement | null} */
    let currentInner = null;

    function init() {
        // Fetch the hover-docs JSON (may already be cached by panel.js)
        fetch("-verso-docs.json")
            .then((r) => {
                return r.ok ? r.json() : {};
            })
            .then((j) => {
                docsJson = j;
            })
            .catch(() => {
                docsJson = {};
            });

        // Set up click handlers on inline Lean code tokens
        document.querySelectorAll("code.hl.lean.inline").forEach((codeEl) => {
            codeEl.addEventListener("click", (e) => {
                const target = /** @type {Element} */ (e.target);

                // Check for hover doc tokens (normal case)
                const tok = target.closest("[data-verso-hover]");
                if (tok) {
                    const id = tok.getAttribute("data-verso-hover");
                    if (id) {
                        e.preventDefault();
                        e.stopPropagation();
                        openLightbox(id);
                        return;
                    }
                }

                // Check for error/warning tokens with embedded messages
                const infoSpan = target.closest(".has-info");
                if (infoSpan) {
                    const msgEl = infoSpan.querySelector(".hover-info.messages");
                    if (msgEl) {
                        e.preventDefault();
                        e.stopPropagation();
                        openLightboxWithHtml(msgEl.innerHTML);
                    }
                }
            });
        });

        // Close on slide change
        Reveal.on("slidechanged", closeLightbox);

        // Rescale lightbox content when viewport changes
        Reveal.on("resize", applyScale);

        // Close on Escape — use capture phase to intercept before reveal.js
        document.addEventListener(
            "keydown",
            (e) => {
                if (e.key === "Escape" && currentOverlay) {
                    closeLightbox();
                    e.preventDefault();
                    e.stopImmediatePropagation();
                }
            },
            true,
        );
    }

    /**
     * Apply reveal.js scale factor to the lightbox content so text matches
     * slide text size and grows/shrinks with the viewport.
     */
    function applyScale() {
        if (!currentInner) return;
        const scale = Reveal.getScale();
        currentInner.style.fontSize = `${scale * 0.75}em`;
    }

    /**
     * Look up hover doc HTML from the docs JSON.
     * @param {string} id
     * @returns {string}
     */
    function lookupHoverDoc(id) {
        if (!docsJson || !id) return "";
        const entry = docsJson[id];
        if (!entry) return "";
        if (typeof entry === "string") {
            return `<span class="hl lean">${entry}</span>`;
        }
        if (entry.hover) {
            return `<span class="hl lean">${entry.hover}</span>`;
        }
        return "";
    }

    /**
     * Open the lightbox overlay with hover info for the given docs ID.
     * @param {string} id
     */
    function openLightbox(id) {
        const html = lookupHoverDoc(id);
        if (!html) return;
        openLightboxWithHtml(html);
    }

    /**
     * Open the lightbox overlay with the given HTML content.
     * @param {string} html
     */
    function openLightboxWithHtml(html) {
        // Close any existing overlay first
        if (currentOverlay) closeLightbox();

        if (!html) return;

        const revealEl = Reveal.getRevealElement();
        if (!revealEl) return;

        // Full-screen backdrop to catch clicks outside the lightbox
        const backdrop = document.createElement("div");
        backdrop.className = "lean-hover-backdrop";
        backdrop.addEventListener("click", closeLightbox);

        // Build overlay following the r-overlay pattern from reveal.js 5.2.1
        const overlay = document.createElement("div");
        overlay.className = "r-overlay r-overlay-lean-hover";

        // Propagate the active slide's light/dark tag to the overlay so the
        // light-mode Lean token palette in slides-highlight.css applies here.
        const currentSlide = Reveal.getCurrentSlide();
        if (currentSlide && currentSlide.classList.contains("slide-light-bg")) {
            overlay.classList.add("slide-light-bg");
        }

        const viewport = document.createElement("div");
        viewport.className = "r-overlay-viewport";

        // Content area
        const content = document.createElement("div");
        content.className = "r-overlay-content lean-hover-content";

        const inner = document.createElement("div");
        inner.className = "lean-hover-inner hl lean";
        // eslint-disable-next-line no-unsanitized/property -- the markup comes from this page or its generated hover data
        inner.innerHTML = html;
        versoRenderMath(inner);
        content.appendChild(inner);

        viewport.appendChild(content);
        overlay.appendChild(viewport);

        revealEl.appendChild(backdrop);
        revealEl.appendChild(overlay);
        currentBackdrop = backdrop;
        currentOverlay = overlay;
        currentInner = inner;

        // Scale content to match slide text size
        applyScale();

        // Lay out the hover's format data, if it has any
        reflowLightboxFormat(inner);

        // Set up binding highlighting within the lightbox
        inner.addEventListener("mouseover", (e) => {
            const tok = /** @type {Element} */ (e.target).closest(".token[data-binding]");
            if (!tok) return;
            const binding = tok.getAttribute("data-binding");
            if (!binding) return;
            const sel = `.token[data-binding="${binding}"]`;
            inner.querySelectorAll(sel).forEach((t) => {
                t.classList.add("binding-hl");
            });
        });
        inner.addEventListener("mouseout", (e) => {
            const tok = /** @type {Element} */ (e.target).closest(".token[data-binding]");
            if (!tok) return;
            inner.querySelectorAll(".token.binding-hl").forEach((t) => {
                t.classList.remove("binding-hl");
            });
        });
    }

    /**
     * Reflow any rich format data in the lightbox content.
     * @param {HTMLElement} container
     */
    function reflowLightboxFormat(container) {
        const codeEl = container.querySelector("code[data-rich-format]");
        if (codeEl) {
            try {
                // Not null: the selector above only matches elements that have this attribute
                const json = /** @type {string} */ (codeEl.getAttribute("data-rich-format"));
                /** @type {unknown} */
                const parsed = JSON.parse(json);
                if (!isFormatData(parsed))
                    throw new Error("data-rich-format on hover code: expected FormatData");
                let width = contentWidth(container);
                if (width <= 0) width = 600; // fallback
                renderFormat(container, codeEl, parsed, width);
            } catch (e) {
                // Fall back to plain text signature
                console.error(e);
            }
        }
    }

    /** Close the lightbox overlay if open. */
    function closeLightbox() {
        if (currentBackdrop) {
            currentBackdrop.remove();
            currentBackdrop = null;
        }
        if (currentOverlay) {
            currentOverlay.remove();
            currentOverlay = null;
            currentInner = null;
        }
    }

    // ---- Entry point ----
    Reveal.on("ready", init);
})();
