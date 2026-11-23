// @ts-check
/* Interactive info panel for Lean code blocks in reveal.js slides. */
(function () {
    "use strict";

    /**
     * @typedef {HTMLElement & { _activeSource: Element | null }} PanelBlock
     * @typedef {HTMLElement & { _reflow: (() => void) | null }} InfoPanel
     * @typedef {{ left: number, right: number, top: number, bottom: number }} LineRect
     */

    /** @type {Record<string, *> | null} */
    let docsJson = null; // fetched once on init

    function init() {
        // Fetch the hover-docs JSON
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

        document.querySelectorAll(".code-with-panel").forEach(setupBlock);

        Reveal.on("fragmentshown", onFragmentShown);
        Reveal.on("fragmenthidden", onFragmentHidden);
        Reveal.on("slidechanged", onSlideChanged);
        Reveal.on("resize", () => {
            document.querySelectorAll(".code-with-panel").forEach((el) => {
                redrawFocusOutline(/** @type {PanelBlock} */ (el));
            });
        });
    }

    // ---- Per-block setup ----

    /** @param {Element} blockEl */
    function setupBlock(blockEl) {
        const block = /** @type {PanelBlock} */ (blockEl);
        const codeEl = /** @type {Element} */ (block.querySelector("code.hl.lean.block"));
        const panel = /** @type {InfoPanel} */ (block.querySelector(".info-panel"));
        if (!block.querySelector("code.hl.lean.block") || !block.querySelector(".info-panel"))
            return;

        block._activeSource = null;

        // Click handler on code element
        codeEl.addEventListener("click", (e) => {
            const chain = findClickableChain(/** @type {Element} */ (e.target), codeEl);
            const chosen = cycleClickable(block, chain);
            if (chosen) {
                clearHoverPreview(codeEl);
                updatePanel(panel, chosen, block);
            }
        });

        // Hover preview — show what would be selected on click
        codeEl.addEventListener("mouseover", (e) => {
            const chain = findClickableChain(/** @type {Element} */ (e.target), codeEl);
            const chosen = cycleClickable(block, chain);
            if (chosen && chosen !== block._activeSource) {
                clearHoverPreview(codeEl);
                chosen.classList.add("panel-hover");
                drawElementOutline(codeEl, chosen, "panel-outline-hover");
            } else {
                clearHoverPreview(codeEl);
            }
        });
        /** @type {HTMLElement} */ (codeEl).addEventListener("mouseout", (e) => {
            if (!e.relatedTarget || !codeEl.contains(/** @type {Node} */ (e.relatedTarget))) {
                clearHoverPreview(codeEl);
            }
        });

        // Binding highlighting — works across code and panel
        /** @param {Event} e */
        function onBindingOver(e) {
            const tok = /** @type {Element} */ (e.target).closest(".token[data-binding]");
            if (!tok) return;
            const binding = tok.getAttribute("data-binding");
            if (!binding) return;
            const sel = `.token[data-binding="${binding}"]`;
            codeEl.querySelectorAll(sel).forEach((t) => {
                t.classList.add("binding-hl");
            });
            panel.querySelectorAll(sel).forEach((t) => {
                t.classList.add("binding-hl");
            });
        }
        /** @param {Event} e */
        function onBindingOut(e) {
            const tok = /** @type {Element} */ (e.target).closest(".token[data-binding]");
            if (!tok) return;
            codeEl.querySelectorAll(".token.binding-hl").forEach((t) => {
                t.classList.remove("binding-hl");
            });
            panel.querySelectorAll(".token.binding-hl").forEach((t) => {
                t.classList.remove("binding-hl");
            });
        }
        codeEl.addEventListener("mouseover", onBindingOver);
        codeEl.addEventListener("mouseout", onBindingOut);
        panel.addEventListener("mouseover", onBindingOver);
        panel.addEventListener("mouseout", onBindingOut);

        // Divider drag
        const divider = block.querySelector(".panel-divider");
        if (divider) setupDividerDrag(block, /** @type {HTMLElement} */ (divider));

        // ResizeObserver for reflowing rich format content and redrawing the
        // focus outline (the code may rewrap when the divider moves)
        if (typeof ResizeObserver !== "undefined") {
            /** @type {ReturnType<typeof setTimeout> | null} */
            let reflowTimer = null;
            const observer = new ResizeObserver(() => {
                if (reflowTimer) clearTimeout(reflowTimer);
                reflowTimer = setTimeout(() => {
                    reflowPanel(panel);
                    redrawFocusOutline(block);
                }, 100);
            });
            observer.observe(panel);
            observer.observe(codeEl);
        }
    }

    /** @param {Element} codeEl */
    function clearHoverPreview(codeEl) {
        codeEl.querySelectorAll(".panel-hover").forEach((el) => {
            el.classList.remove("panel-hover");
        });
        setOutlinePath(codeEl, "panel-outline-hover", "");
    }

    // ---- Focus/hover outline overlay ----
    //
    // CSS `outline` on an inline element that wraps across lines is drawn as a
    // separate closed box per line fragment in Firefox and Safari (only
    // Chromium merges the fragments). To get one contiguous border in every
    // browser we draw it ourselves: merge the element's client rects (one per
    // line) into a single staircase polygon and stroke it in an SVG overlay.

    const SVG_NS = "http://www.w3.org/2000/svg";

    /**
     * Get (or create) the outline overlay for a code block, with one path for
     * the focused element and one for the hover preview.
     * @param {Element} codeEl
     * @returns {SVGSVGElement}
     */
    function ensureOutlineSvg(codeEl) {
        const existing = codeEl.querySelector(":scope > svg.panel-outline-svg");
        if (existing) return /** @type {SVGSVGElement} */ (existing);
        const svg = /** @type {SVGSVGElement} */ (document.createElementNS(SVG_NS, "svg"));
        svg.setAttribute("class", "panel-outline-svg");
        svg.setAttribute("aria-hidden", "true");
        ["panel-outline-focus", "panel-outline-hover"].forEach((cls) => {
            const path = document.createElementNS(SVG_NS, "path");
            path.setAttribute("class", cls);
            svg.appendChild(path);
        });
        codeEl.appendChild(svg);
        return svg;
    }

    /**
     * @param {Element} codeEl
     * @param {string} cls
     * @param {string} d
     */
    function setOutlinePath(codeEl, cls, d) {
        const svg = ensureOutlineSvg(codeEl);
        const path = svg.querySelector(`.${cls}`);
        if (path) path.setAttribute("d", d);
    }

    /**
     * Merge an element's client rects into one rect per line.
     * @param {Element} el
     * @returns {LineRect[]}
     */
    function lineRects(el) {
        /** @type {LineRect[]} */
        const lines = [];
        for (const r of el.getClientRects()) {
            if (r.width === 0 || r.height === 0) continue;
            let merged = false;
            for (const ln of lines) {
                // Same line if the vertical ranges mostly overlap
                const overlap = Math.min(ln.bottom, r.bottom) - Math.max(ln.top, r.top);
                if (overlap > 0.5 * Math.min(ln.bottom - ln.top, r.height)) {
                    ln.left = Math.min(ln.left, r.left);
                    ln.right = Math.max(ln.right, r.right);
                    ln.top = Math.min(ln.top, r.top);
                    ln.bottom = Math.max(ln.bottom, r.bottom);
                    merged = true;
                    break;
                }
            }
            if (!merged) lines.push({ left: r.left, right: r.right, top: r.top, bottom: r.bottom });
        }
        lines.sort((a, b) => {
            return a.top - b.top;
        });
        return lines;
    }

    /**
     * Draw a single contiguous outline around all line fragments of `el`,
     * into the overlay path identified by `cls` ("" for el === null clears it).
     * @param {Element} codeEl
     * @param {Element | null} el
     * @param {string} cls
     */
    function drawElementOutline(codeEl, el, cls) {
        if (!el) {
            setOutlinePath(codeEl, cls, "");
            return;
        }
        const lines = lineRects(el);
        const first = lines[0];
        const final = lines.at(-1);
        if (!first || !final) {
            setOutlinePath(codeEl, cls, "");
            return;
        }

        // Coordinates are computed relative to the SVG overlay itself, and
        // divided by the reveal.js zoom so they live in element-space pixels.
        const svg = ensureOutlineSvg(codeEl);
        const origin = svg.getBoundingClientRect();
        const scale =
            codeEl.getBoundingClientRect().width /
                /** @type {HTMLElement} */ (codeEl).offsetWidth || 1;
        const pad = 2; // outline offset, in element-space pixels

        /** @param {number} x */
        function relX(x) {
            return (x - origin.left) / scale;
        }
        /** @param {number} y */
        function relY(y) {
            return (y - origin.top) / scale;
        }

        // Each pair of consecutive lines meets at a vertical boundary `y`, so
        // adjacent fragments share an edge instead of leaving a gap or double border.
        /** @type {Array<{above: LineRect, below: LineRect, y: number}>} */
        const joints = [];
        let above = first;
        for (const below of lines.slice(1)) {
            joints.push({ above, below, y: relY((above.bottom + below.top) / 2) });
            above = below;
        }

        /** @type {Array<{x: number, y: number}>} */
        const pts = [];
        /**
         * @param {number} x
         * @param {number} y
         */
        function pt(x, y) {
            // Skip zero-length jogs (e.g. consecutive lines with equal edges)
            const last = pts.at(-1);
            if (last && Math.abs(last.x - x) < 0.5 && Math.abs(last.y - y) < 0.5) return;
            pts.push({ x: x, y: y });
        }

        // Clockwise: across the top, down the right side (jogging at each line
        // boundary), back across the bottom, and up the left side.
        pt(relX(first.left) - pad, relY(first.top) - pad);
        pt(relX(first.right) + pad, relY(first.top) - pad);
        for (const j of joints) {
            pt(relX(j.above.right) + pad, j.y);
            pt(relX(j.below.right) + pad, j.y);
        }
        pt(relX(final.right) + pad, relY(final.bottom) + pad);
        pt(relX(final.left) - pad, relY(final.bottom) + pad);
        for (const j of joints.toReversed()) {
            pt(relX(j.below.left) - pad, j.y);
            pt(relX(j.above.left) - pad, j.y);
        }

        setOutlinePath(codeEl, cls, roundedPathFrom(pts, 4));
    }

    /**
     * Build an SVG path for a closed polygon, rounding each corner with a
     * quadratic curve of the given radius (clamped to half of each adjacent
     * segment so short jogs stay well-formed).
     * @param {Array<{x: number, y: number}>} pts
     * @param {number} radius
     * @returns {string}
     */
    function roundedPathFrom(pts, radius) {
        const n = pts.length;
        if (n < 3) return "";
        /** @type {string[]} */
        const parts = [];
        /**
         * The point at index `k`, wrapping around the closed polygon.
         * @param {number} k
         */
        const at = (k) => /** @type {{x: number, y: number}} */ (pts[(k + n) % n]);
        for (let i = 0; i < n; i++) {
            const prev = at(i - 1);
            const cur = at(i);
            const next = at(i + 1);
            const inLen = Math.hypot(cur.x - prev.x, cur.y - prev.y);
            const outLen = Math.hypot(next.x - cur.x, next.y - cur.y);
            if (inLen === 0 || outLen === 0) {
                parts.push(`${(i === 0 ? "M" : "L") + cur.x.toFixed(2)} ${cur.y.toFixed(2)}`);
                continue;
            }
            const r = Math.min(radius, inLen / 2, outLen / 2);
            // Corner start: back off along the incoming edge; corner end:
            // advance along the outgoing edge.
            const sx = cur.x + ((prev.x - cur.x) / inLen) * r;
            const sy = cur.y + ((prev.y - cur.y) / inLen) * r;
            const ex = cur.x + ((next.x - cur.x) / outLen) * r;
            const ey = cur.y + ((next.y - cur.y) / outLen) * r;
            parts.push(
                `${(i === 0 ? "M" : "L") + sx.toFixed(2)} ${sy.toFixed(2)}`,
                `Q${cur.x.toFixed(2)} ${cur.y.toFixed(2)} ${ex.toFixed(2)} ${ey.toFixed(2)}`,
            );
        }
        return `${parts.join(" ")} Z`;
    }

    /**
     * Redraw the focus outline of a block (e.g. after a resize or rewrap).
     * @param {PanelBlock} block
     */
    function redrawFocusOutline(block) {
        const codeEl = block.querySelector("code.hl.lean.block");
        if (!codeEl) return;
        drawElementOutline(codeEl, block._activeSource, "panel-outline-focus");
    }

    // ---- Clickable element discovery ----

    /**
     * @param {Element} el
     * @returns {boolean}
     */
    function isClickable(el) {
        return (
            el.classList.contains("tactic") ||
            el.classList.contains("has-info") ||
            el.hasAttribute("data-verso-hover")
        );
    }

    /**
     * Collect clickable ancestors from target up to codeEl, outermost first.
     * @param {Element} target
     * @param {Element} codeEl
     * @returns {Element[]}
     */
    function findClickableChain(target, codeEl) {
        /** @type {Element[]} */
        const chain = [];
        /** @type {Element | null} */
        let el = target;
        while (el && el !== codeEl) {
            if (isClickable(el)) chain.push(el);
            el = el.parentElement;
        }
        chain.reverse(); // outermost first
        return chain;
    }

    /**
     * Pick which element to select: outermost if nothing active in this chain,
     * otherwise cycle inward from the active element toward the click target.
     * @param {PanelBlock} block
     * @param {Element[]} chain
     * @returns {Element | null}
     */
    function cycleClickable(block, chain) {
        if (chain.length === 0) return null;
        const active = block._activeSource;
        const idx = active ? chain.indexOf(active) : -1;
        if (idx >= 0 && idx < chain.length - 1) {
            return chain[idx + 1] ?? null;
        }
        return chain[0] ?? null;
    }

    // ---- Panel update ----

    /**
     * @param {InfoPanel} panel
     * @param {Element} el
     * @param {PanelBlock} block
     */
    function updatePanel(panel, el, block) {
        // Clear previous focus
        const codeEl = block.querySelector("code.hl.lean.block");
        if (codeEl) {
            codeEl.querySelectorAll(".panel-focus").forEach((f) => {
                f.classList.remove("panel-focus");
            });
        }

        block._activeSource = el;
        el.classList.add("panel-focus");
        if (codeEl) drawElementOutline(codeEl, el, "panel-outline-focus");

        // Re-renders the panel's reflowable content at its current width, if any
        panel._reflow = null;

        /** @type {string | null} */
        let html = "";

        if (el.classList.contains("tactic")) {
            // `:scope >` restricts to this tactic's _own_ state. A tactic with nested child tactics
            // (e.g. a multi-step `rw`) holds its own `.tactic-state` as a direct child, after the
            // nested tactics. Each child has its own `.tactic-state`. It's important to avoid
            // selecting one of them by accident.
            const ts = el.querySelector(":scope > .tactic-state");
            if (ts) {
                const staticHtml = `<span class="hl lean">${ts.innerHTML}</span>`;
                const richFmt = ts.getAttribute("data-rich-format");
                if (richFmt) {
                    try {
                        /** @type {unknown} */
                        const parsed = JSON.parse(richFmt);
                        if (!Array.isArray(parsed) || !parsed.every(isGoalData))
                            throw new Error(
                                "data-rich-format on tactic state: expected GoalData[]",
                            );
                        // renderGoals replaces the panel contents before laying them out, so a
                        // failure partway through is repaired with the static rendering
                        panel._reflow = () => {
                            try {
                                renderGoals(panel, parsed);
                            } catch (e) {
                                // eslint-disable-next-line no-unsanitized/property -- the markup is copied from this page, which the slide generator wrote
                                panel.innerHTML = staticHtml;
                                throw e;
                            }
                        };
                        panel._reflow();
                        html = null; // already set innerHTML
                    } catch (e) {
                        console.error(e);
                        html = staticHtml;
                        panel._reflow = null;
                    }
                } else {
                    html = staticHtml;
                }
            }
        } else if (el.classList.contains("has-info")) {
            // `:scope >` ensures that nested info isn't chosen instead of this element's info.
            const msgs = el.querySelector(":scope > .hover-info.messages");
            if (msgs) html = `<span class="hl lean">${msgs.innerHTML}</span>`;
        } else if (el.hasAttribute("data-verso-hover")) {
            const id = el.getAttribute("data-verso-hover");
            html = lookupHoverDoc(id);
        }

        // eslint-disable-next-line no-unsanitized/property -- the markup comes from this page or its generated hover data
        if (html !== null) panel.innerHTML = html;

        // Check for reflowable format data in hover content
        const sigCode = panel.querySelector("code[data-rich-format]");
        if (sigCode) {
            try {
                // Not null: the selector above only matches elements that have this attribute
                const json = /** @type {string} */ (sigCode.getAttribute("data-rich-format"));
                /** @type {unknown} */
                const parsed = JSON.parse(json);
                if (!isFormatData(parsed))
                    throw new Error("data-rich-format on hover code: expected FormatData");
                panel._reflow = () => renderFormat(panel, sigCode, parsed, contentWidth(panel));
                panel._reflow();
            } catch (e) {
                // Fall back to plain text signature on error
                console.error(e);
                panel._reflow = null;
            }
        }
    }

    /**
     * Re-render the panel's reflowable content at its current width.
     * @param {InfoPanel} panel
     */
    function reflowPanel(panel) {
        if (!panel._reflow) return;
        try {
            panel._reflow();
        } catch (e) {
            // The closure leaves the panel in a displayable state when it fails
            console.error(e);
        }
    }

    /**
     * @param {string | null} id
     * @returns {string}
     */
    function lookupHoverDoc(id) {
        if (!docsJson || !id) return "";
        const entry = docsJson[id];
        if (!entry) return "";
        // entry is the HTML string from verso hover data
        if (typeof entry === "string") {
            return `<span class="hl lean">${entry}</span>`;
        }
        // Could be an object with .hover field
        if (entry.hover) {
            return `<span class="hl lean">${entry.hover}</span>`;
        }
        return "";
    }

    // ---- Fragment automation ----

    /** @param {{ fragment: HTMLElement }} evt */
    function onFragmentShown(evt) {
        const frag = evt.fragment;
        if (!frag || !frag.classList.contains("slide-click-only")) return;

        const block = /** @type {PanelBlock | null} */ (frag.closest(".code-with-panel"));
        if (!block) return;

        const panel = /** @type {InfoPanel | null} */ (block.querySelector(".info-panel"));
        if (!panel) return;

        // Find the clickable element targeted by this fragment
        const target = frag.querySelector(".tactic, .has-info, [data-verso-hover]");
        if (target) updatePanel(panel, target, block);
    }

    /** @param {{ fragment: HTMLElement }} evt */
    function onFragmentHidden(evt) {
        const frag = evt.fragment;
        if (!frag || !frag.classList.contains("slide-click-only")) return;

        const block = /** @type {PanelBlock | null} */ (frag.closest(".code-with-panel"));
        if (!block) return;

        syncPanelToLastVisible(block);
    }

    function onSlideChanged() {
        const slide = Reveal.getCurrentSlide();
        if (!slide) return;
        slide.querySelectorAll(".code-with-panel").forEach((el) => {
            syncPanelToLastVisible(/** @type {PanelBlock} */ (el));
        });
    }

    /** @param {PanelBlock} block */
    function syncPanelToLastVisible(block) {
        const panel = /** @type {InfoPanel | null} */ (block.querySelector(".info-panel"));
        if (!panel) return;

        // Find the last visible slide-click-only fragment
        const frags = block.querySelectorAll(".fragment.slide-click-only.visible");
        const last = frags[frags.length - 1];
        if (last) {
            const target = last.querySelector(".tactic, .has-info, [data-verso-hover]");
            if (target) {
                updatePanel(panel, target, block);
                return;
            }
        }

        // No visible fragments — clear panel
        const codeEl = block.querySelector("code.hl.lean.block");
        if (codeEl) {
            codeEl.querySelectorAll(".panel-focus").forEach((f) => {
                f.classList.remove("panel-focus");
            });
            drawElementOutline(codeEl, null, "panel-outline-focus");
        }
        block._activeSource = null;
        panel.innerHTML = "";
    }

    // ---- Divider drag ----

    /**
     * @param {HTMLElement} block
     * @param {HTMLElement} divider
     */
    function setupDividerDrag(block, divider) {
        let dragging = false;

        divider.addEventListener("mousedown", (e) => {
            e.preventDefault();
            dragging = true;
            document.body.style.cursor = "col-resize";
            document.body.style.userSelect = "none";
        });

        document.addEventListener("mousemove", (e) => {
            if (!dragging) return;
            const rect = block.getBoundingClientRect();
            const x = e.clientX - rect.left;
            const pct = x / rect.width;

            if (pct > 0.95) {
                // Collapse panel
                block.classList.add("panel-collapsed");
            } else {
                block.classList.remove("panel-collapsed");
                const codeFr = Math.max(0.2, Math.min(0.9, pct));
                const panelFr = 1 - codeFr;
                block.style.setProperty("--code-ratio", `${codeFr}fr`);
                block.style.setProperty("--panel-ratio", `${panelFr}fr`);
            }
        });

        document.addEventListener("mouseup", () => {
            if (!dragging) return;
            dragging = false;
            document.body.style.cursor = "";
            document.body.style.userSelect = "";
        });
    }

    // ---- Entry point ----
    Reveal.on("ready", init);
})();
