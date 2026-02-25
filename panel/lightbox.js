// @ts-check
/* Lightbox overlay for inline Lean term hover info in reveal.js slides. */
(function () {
    "use strict";

    /** @type {Record<string, *> | null} */
    var docsJson = null;

    /** @type {HTMLElement | null} */
    var currentOverlay = null;

    /** @type {HTMLElement | null} */
    var currentBackdrop = null;

    /** @type {HTMLElement | null} */
    var currentInner = null;

    function init() {
        // Fetch the hover-docs JSON (may already be cached by panel.js)
        fetch("-verso-docs.json")
            .then(function (r) {
                return r.ok ? r.json() : {};
            })
            .then(function (j) {
                docsJson = j;
            })
            .catch(function () {
                docsJson = {};
            });

        // Set up click handlers on inline Lean code tokens
        document.querySelectorAll("code.hl.lean.inline").forEach(function (codeEl) {
            codeEl.addEventListener("click", function (e) {
                var target = /** @type {Element} */ (e.target);

                // Check for hover doc tokens (normal case)
                var tok = target.closest("[data-verso-hover]");
                if (tok) {
                    var id = tok.getAttribute("data-verso-hover");
                    if (id) {
                        e.preventDefault();
                        e.stopPropagation();
                        openLightbox(id);
                        return;
                    }
                }

                // Check for error/warning tokens with embedded messages
                var infoSpan = target.closest(".has-info");
                if (infoSpan) {
                    var msgEl = infoSpan.querySelector(".hover-info.messages");
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
            function (e) {
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
        var scale = Reveal.getScale();
        currentInner.style.fontSize = scale * 0.75 + "em";
    }

    /**
     * Look up hover doc HTML from the docs JSON.
     * @param {string} id
     * @return {string}
     */
    function lookupHoverDoc(id) {
        if (!docsJson || !id) return "";
        var entry = docsJson[id];
        if (!entry) return "";
        if (typeof entry === "string") {
            return '<span class="hl lean">' + entry + "</span>";
        }
        if (entry.hover) {
            return '<span class="hl lean">' + entry.hover + "</span>";
        }
        return "";
    }

    /**
     * Open the lightbox overlay with hover info for the given docs ID.
     * @param {string} id
     */
    function openLightbox(id) {
        var html = lookupHoverDoc(id);
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

        var revealEl = Reveal.getRevealElement();
        if (!revealEl) return;

        // Full-screen backdrop to catch clicks outside the lightbox
        var backdrop = document.createElement("div");
        backdrop.className = "lean-hover-backdrop";
        backdrop.addEventListener("click", closeLightbox);

        // Build overlay following the r-overlay pattern from reveal.js 5.2.1
        var overlay = document.createElement("div");
        overlay.className = "r-overlay r-overlay-lean-hover";

        var viewport = document.createElement("div");
        viewport.className = "r-overlay-viewport";

        // Content area
        var content = document.createElement("div");
        content.className = "r-overlay-content lean-hover-content";

        var inner = document.createElement("div");
        inner.className = "lean-hover-inner hl lean";
        inner.innerHTML = html;
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

        // Reflow any rich format signatures
        reflowLightboxSignatures(inner);

        // Render docstrings with marked
        if (typeof marked !== "undefined") {
            inner.querySelectorAll(".docstring").forEach(function (ds) {
                ds.innerHTML = marked.parse(ds.textContent || "");
            });
        }

        // Set up binding highlighting within the lightbox
        inner.addEventListener("mouseover", function (e) {
            var tok = /** @type {Element | null} */ (e.target).closest(".token[data-binding]");
            if (!tok) return;
            var binding = tok.getAttribute("data-binding");
            if (!binding) return;
            var sel = '.token[data-binding="' + binding + '"]';
            inner.querySelectorAll(sel).forEach(function (t) {
                t.classList.add("binding-hl");
            });
        });
        inner.addEventListener("mouseout", function (e) {
            var tok = /** @type {Element | null} */ (e.target).closest(".token[data-binding]");
            if (!tok) return;
            inner.querySelectorAll(".token.binding-hl").forEach(function (t) {
                t.classList.remove("binding-hl");
            });
        });
    }

    /**
     * Reflow any rich format data in the lightbox content.
     * @param {HTMLElement} container
     */
    function reflowLightboxSignatures(container) {
        var sigCode = container.querySelector("code[data-rich-format]");
        if (!sigCode || typeof formatToHtml !== "function") return;
        try {
            var fmtData = JSON.parse(sigCode.getAttribute("data-rich-format") || "{}");
            var measurer = createDOMMeasurer(container);
            var width =
                container.clientWidth -
                parseFloat(getComputedStyle(container).paddingLeft || "0") -
                parseFloat(getComputedStyle(container).paddingRight || "0");
            if (width <= 0) width = 600; // fallback
            var rendered = formatToHtml(fmtData.fmt, fmtData.annotations, width, measurer);
            sigCode.innerHTML = '<span class="reflowed">' + rendered + "</span>";
            measurer.cleanup();
        } catch (e) {
            // Fall back to plain text signature
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
