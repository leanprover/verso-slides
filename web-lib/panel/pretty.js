// @ts-check
// pretty.js: layout of Lean pretty-printer output for the info panel and the lightbox.
//
// The core is a direct port of Lean 4's Std.Format pretty printer
// (Init/Data/Format/Basic.lean). It lays out a serialized Std.Format tree at a
// given pixel width, measuring text in the DOM, and emits HTML carrying the
// token annotations.

"use strict";

/* exported contentWidth, isFormatData, isGoalData, renderFormat, renderGoals */

/**
 * @typedef {{ type: "nil" }
 *   | { type: "line" }
 *   | { type: "align", force: boolean }
 *   | { type: "text", str: string }
 *   | { type: "nest", indent: number, f: FormatNode }
 *   | { type: "append", f1: FormatNode, f2: FormatNode }
 *   | { type: "group", f: FormatNode, behavior: "allOrNone" | "fill" }
 *   | { type: "tag", n: number, f: FormatNode }} FormatNode
 *
 * @typedef {{
 *   measure: (s: string) => number,
 *   spaceWidth: number,
 *   measureElWidth: (el: Element) => number,
 *   cleanup: () => void
 * }} DOMMeasurer
 *
 * @typedef {{ foundLine: boolean, foundFlattenedHardLine: boolean, space: number }} SpaceResult
 *
 * @typedef {{ type: string, fits: boolean }} Fla
 *
 * @typedef {{ f: FormatNode, indent: number, activeTags: number }} WorkItem
 *
 * @typedef {{ fla: Fla, flb: "allOrNone" | "fill", items: WorkItem[] }} WorkGroup
 *
 * @typedef {{ text: string, tags: number[] }} Segment
 *
 * @typedef {{ cssClass: string, binding?: string }} TokenAnnotation
 *
 * @typedef {{
 *   column: number,
 *   tagStack: number[],
 *   segments: Segment[],
 *   annotations: Record<string, TokenAnnotation>,
 *   pushOutput: (s: string) => void,
 *   pushNewline: (indent: number) => void,
 *   startTag: (t: number) => void,
 *   endTags: (count: number) => void
 * }} RenderContext
 *
 * @typedef {{ fmt: *, annotations: Record<string, TokenAnnotation> }} FormatData
 *
 * @typedef {{ names: string[], ppType: string | null }} Hypothesis
 *
 * @typedef {{ name: string | null, hypotheses: Hypothesis[], goalPrefix: string, ppConclusion: string | null }} GoalData
 *
 * @typedef {{ html: string, formats: FormatData[] }} GoalsResult
 */

/**
 * Deserialize a compact JSON format node into a tree.
 *
 * Wire format (from Highlighted.lean formatToJson):
 *   null            → nil
 *   "str"           → text(str)
 *   1               → line
 *   [2, bool]       → align(force)
 *   [3, int, sub]   → nest(indent, sub)
 *   [4, a, b]       → append(a, b)
 *   [5, sub]        → group(sub, allOrNone)
 *   [6, sub]        → group(sub, fill)
 *   [7, nat, sub]   → tag(nat, sub)
 * @param {*} json
 * @returns {FormatNode}
 */
function deserializeFormat(json) {
    if (json === null || json === undefined) return { type: "nil" };
    if (json === 1) return { type: "line" };
    if (typeof json === "string") return { type: "text", str: json };
    if (!Array.isArray(json) || json.length === 0) return { type: "nil" };
    switch (json[0]) {
        case 2:
            return { type: "align", force: !!json[1] };
        case 3:
            return { type: "nest", indent: json[1], f: deserializeFormat(json[2]) };
        case 4:
            return {
                type: "append",
                f1: deserializeFormat(json[1]),
                f2: deserializeFormat(json[2]),
            };
        case 5:
            return { type: "group", f: deserializeFormat(json[1]), behavior: "allOrNone" };
        case 6:
            return { type: "group", f: deserializeFormat(json[1]), behavior: "fill" };
        case 7:
            return { type: "tag", n: json[1], f: deserializeFormat(json[2]) };
        default:
            return { type: "nil" };
    }
}

/**
 * Create a DOM-based measurer for pixel-accurate text width measurement.
 * Accounts for reveal.js CSS transform scaling.
 * @param {HTMLElement} panel
 * @returns {DOMMeasurer}
 */
function createDOMMeasurer(panel) {
    const container = document.createElement("span");
    container.className = "hl lean reflowed";
    container.style.cssText =
        "position:absolute;visibility:hidden;white-space:pre;pointer-events:none";
    const probe = document.createElement("span");
    container.appendChild(probe);
    panel.appendChild(container);

    // Compute CSS transform scale factor.
    // reveal.js applies transform:scale() to slides, which makes
    // getBoundingClientRect() return viewport-scaled values while
    // clientWidth returns CSS layout pixels. We need CSS pixels.
    const clientW = panel.clientWidth;
    let scale = 1;
    if (clientW > 0) {
        scale = panel.getBoundingClientRect().width / clientW;
    }

    /** @type {Record<string, number>} */
    const cache = {};
    /**
     * @param {string} s
     * @returns {number}
     */
    function measure(s) {
        const cached = cache[s];
        if (cached !== undefined) return cached;
        probe.textContent = s;
        const w = probe.getBoundingClientRect().width / scale;
        cache[s] = w;
        return w;
    }
    const spaceWidth = measure(" ");
    return {
        measure: measure,
        spaceWidth: spaceWidth,
        measureElWidth: function (el) {
            return el.getBoundingClientRect().width / scale;
        },
        cleanup: function () {
            panel.removeChild(container);
        },
    };
}

/**
 * Constructs a SpaceResult with the given values, defaulting to false/0.
 * @param {boolean} [foundLine]
 * @param {boolean} [foundFlattenedHardLine]
 * @param {number} [space]
 * @returns {SpaceResult}
 */
function spaceResult(foundLine, foundFlattenedHardLine, space) {
    return {
        foundLine: foundLine || false,
        foundFlattenedHardLine: foundFlattenedHardLine || false,
        space: space || 0,
    };
}

/**
 * @param {number} w
 * @param {SpaceResult} r1
 * @param {(w2: number) => SpaceResult} r2fn
 * @returns {SpaceResult}
 */
function merge(w, r1, r2fn) {
    if (r1.space > w || r1.foundLine) return r1;
    const r2 = r2fn(w - r1.space);
    return {
        foundLine: r2.foundLine,
        foundFlattenedHardLine: r2.foundFlattenedHardLine,
        space: r1.space + r2.space,
    };
}

/**
 * Measures how much horizontal space a format takes (in pixels) before a line break.
 * @param {FormatNode} f
 * @param {boolean} flatten
 * @param {number} m
 * @param {number} w
 * @param {DOMMeasurer} measurer
 * @returns {SpaceResult}
 */
function spaceUptoLine(f, flatten, m, w, measurer) {
    switch (f.type) {
        case "nil":
            return spaceResult();
        case "line":
            return flatten ? spaceResult(false, false, measurer.spaceWidth) : spaceResult(true);
        case "align":
            if (flatten && !f.force) return spaceResult();
            if (w < m) return spaceResult(false, false, Math.max(0, m - w));
            return spaceResult(true);
        case "text": {
            const idx = f.str.indexOf("\n");
            if (idx === -1) {
                return spaceResult(false, false, measurer.measure(f.str));
            }
            return spaceResult(true, flatten, measurer.measure(f.str.substring(0, idx)));
        }
        case "append":
            return merge(w, spaceUptoLine(f.f1, flatten, m, w, measurer), (w2) => {
                return spaceUptoLine(f.f2, flatten, m, w2, measurer);
            });
        case "nest":
            return spaceUptoLine(f.f, flatten, m - f.indent * measurer.spaceWidth, w, measurer);
        case "group":
            return spaceUptoLine(f.f, true, m, w, measurer);
        case "tag":
            return spaceUptoLine(f.f, flatten, m, w, measurer);
        default:
            return spaceResult();
    }
}

/**
 * @param {Fla} fla
 * @returns {boolean}
 */
function shouldFlatten(fla) {
    return fla.type === "allow" && !!fla.fits;
}

/**
 * Measures space for a list of work groups. Items within each group are stored
 * in reverse order (last element = next to process), so we iterate backwards.
 * @param {WorkGroup[]} groups - groups in reverse order (last = current)
 * @param {number} col
 * @param {number} w
 * @param {DOMMeasurer} measurer
 * @returns {SpaceResult}
 */
function spaceUptoLineGroups(groups, col, w, measurer) {
    let result = spaceResult();
    let remainingW = w;

    for (let gi = groups.length - 1; gi >= 0; gi--) {
        const g = /** @type {WorkGroup} */ (groups[gi]);
        const flatten = shouldFlatten(g.fla);
        for (let ii = g.items.length - 1; ii >= 0; ii--) {
            const item = /** @type {WorkItem} */ (g.items[ii]);
            const r = spaceUptoLine(
                item.f,
                flatten,
                remainingW + col - item.indent,
                remainingW,
                measurer,
            );
            result = {
                foundLine: r.foundLine,
                foundFlattenedHardLine: result.foundFlattenedHardLine || r.foundFlattenedHardLine,
                space: result.space + r.space,
            };
            if (r.space > remainingW || r.foundLine) return result;
            remainingW -= r.space;
        }
    }
    return result;
}

/**
 * Creates a new work group with a flattening decision based on available space.
 * Items and groups are in reverse order (last = next to process).
 * @param {"allOrNone" | "fill"} flb
 * @param {WorkItem[]} items - in reverse order
 * @param {WorkGroup[]} gs - in reverse order
 * @param {number} w
 * @param {RenderContext} ctx
 * @param {DOMMeasurer} measurer
 * @returns {WorkGroup[]}
 */
function pushGroup(flb, items, gs, w, ctx, measurer) {
    const k = ctx.column;
    const remaining = w - k;
    const g = { fla: { type: "allow", fits: flb === "allOrNone" }, flb: flb, items: items };
    const r = spaceUptoLineGroups([g], k, remaining, measurer);
    const r2 = merge(remaining, r, (w2) => {
        return spaceUptoLineGroups(gs, k, w2, measurer);
    });
    const fits = !r.foundFlattenedHardLine && r2.space <= remaining;
    gs.push({ fla: { type: "allow", fits: fits }, flb: flb, items: items });
    return gs;
}

/**
 * Main layout engine (iterative port of Lean's `be`). Processes work groups,
 * making flattening and line-break decisions, and emits output via the render context.
 *
 * Items within each group are stored in reverse order: the last element is
 * processed next. This allows O(1) pop/push instead of O(n) slice/concat.
 * Groups are also in reverse order (last = current group).
 *
 * @param {number} w
 * @param {WorkGroup[]} groups - in reverse order (last = current)
 * @param {RenderContext} ctx
 * @param {DOMMeasurer} measurer
 */
function be(w, groups, ctx, measurer) {
    for (let g = groups.at(-1); g !== undefined; g = groups.at(-1)) {
        if (g.items.length === 0) {
            groups.pop();
            continue;
        }
        // Pop current item — O(1). g.items retains the rest.
        // Length was checked above, so pop always returns a value.
        const i = /** @type {WorkItem} */ (g.items.pop());

        switch (i.f.type) {
            case "nil":
                ctx.endTags(i.activeTags);
                break;

            case "tag":
                ctx.startTag(i.f.n);
                // Push replacement (processed next) — O(1)
                g.items.push({ f: i.f.f, indent: i.indent, activeTags: i.activeTags + 1 });
                break;

            case "append":
                // Push f1 last so it is processed next (before f2) — O(1) each
                g.items.push({ f: i.f.f2, indent: i.indent, activeTags: i.activeTags });
                g.items.push({ f: i.f.f1, indent: i.indent, activeTags: 0 });
                break;

            case "nest":
                g.items.push({
                    f: i.f.f,
                    indent: i.indent + i.f.indent * measurer.spaceWidth,
                    activeTags: i.activeTags,
                });
                break;

            case "text": {
                const s = i.f.str;
                const nlIdx = s.indexOf("\n");
                if (nlIdx === -1) {
                    ctx.pushOutput(s);
                    ctx.endTags(i.activeTags);
                } else {
                    ctx.pushOutput(s.substring(0, nlIdx));
                    ctx.pushNewline(Math.max(0, i.indent));
                    /** @type {WorkItem} */
                    const newTextItem = {
                        f: { type: "text", str: s.substring(nlIdx + 1) },
                        indent: i.indent,
                        activeTags: i.activeTags,
                    };
                    // After hard line break, re-evaluate flattening
                    if (g.fla.type === "disallow") {
                        g.items.push(newTextItem);
                    } else {
                        // Remaining items stay in g.items; add newTextItem
                        g.items.push(newTextItem);
                        // Steal items from current group, pop it, create new group
                        const remainingItems = g.items;
                        groups.pop();
                        groups = pushGroup(g.flb, remainingItems, groups, w, ctx, measurer);
                    }
                }
                break;
            }

            case "line":
                if (g.flb === "allOrNone") {
                    if (shouldFlatten(g.fla)) {
                        ctx.pushOutput(" ");
                    } else {
                        ctx.pushNewline(Math.max(0, i.indent));
                    }
                    ctx.endTags(i.activeTags);
                } else {
                    // fill behavior
                    if (shouldFlatten(g.fla)) {
                        // Try to fit next item too — need a copy since pushGroup mutates
                        const savedItems = g.items.slice();
                        const savedGroups = groups.slice(0, groups.length - 1);
                        const tryGs = pushGroup(
                            "fill",
                            savedItems,
                            savedGroups,
                            w - measurer.spaceWidth,
                            ctx,
                            measurer,
                        );
                        // pushGroup always pushes a group, so tryGs is not empty
                        const nextG = /** @type {WorkGroup} */ (tryGs.at(-1));
                        if (shouldFlatten(nextG.fla)) {
                            ctx.pushOutput(" ");
                            ctx.endTags(i.activeTags);
                            groups = tryGs;
                        } else {
                            // Break: use original items
                            ctx.pushNewline(Math.max(0, i.indent));
                            ctx.endTags(i.activeTags);
                            const breakItems = g.items;
                            groups.pop();
                            groups = pushGroup("fill", breakItems, groups, w, ctx, measurer);
                        }
                    } else {
                        ctx.pushNewline(Math.max(0, i.indent));
                        ctx.endTags(i.activeTags);
                        const breakItems2 = g.items;
                        groups.pop();
                        groups = pushGroup("fill", breakItems2, groups, w, ctx, measurer);
                    }
                }
                break;

            case "align":
                if (shouldFlatten(g.fla) && !i.f.force) {
                    ctx.endTags(i.activeTags);
                } else {
                    const k = ctx.column;
                    if (k < i.indent) {
                        const pad = Math.max(0, i.indent - k);
                        ctx.pushOutput(" ".repeat(Math.round(pad / measurer.spaceWidth)));
                    } else {
                        ctx.pushNewline(Math.max(0, i.indent));
                    }
                    ctx.endTags(i.activeTags);
                }
                break;

            case "group":
                if (shouldFlatten(g.fla)) {
                    // flatten(group f) = flatten f
                    g.items.push({ f: i.f.f, indent: i.indent, activeTags: i.activeTags });
                } else {
                    const groupItem = { f: i.f.f, indent: i.indent, activeTags: i.activeTags };
                    groups = pushGroup(i.f.behavior, [groupItem], groups, w, ctx, measurer);
                }
                break;

            default:
                // Unknown format node, skip
                ctx.endTags(i.activeTags);
                break;
        }
    }
}

/**
 * Entry point: pretty-prints a format tree at a given pixel width.
 * @param {FormatNode} f
 * @param {number} w
 * @param {number} indent
 * @param {RenderContext} ctx
 * @param {DOMMeasurer} measurer
 */
function prettyM(f, w, indent, ctx, measurer) {
    indent = indent || 0;
    be(
        w,
        [
            {
                flb: "allOrNone",
                fla: { type: "disallow", fits: false },
                items: [{ f: f, indent: indent, activeTags: 0 }],
            },
        ],
        ctx,
        measurer,
    );
}

/**
 * Creates a rendering context that collects tagged output segments.
 * @param {Record<string, TokenAnnotation>} annotations
 * @param {DOMMeasurer} measurer
 * @returns {RenderContext}
 */
function makeRenderContext(annotations, measurer) {
    return {
        column: 0,
        tagStack: [],
        segments: [], // Array of { text, tags }
        annotations: annotations || {},

        pushOutput: function (s) {
            if (s.length === 0) return;
            this.segments.push({ text: s, tags: this.tagStack.slice() });
            this.column += measurer.measure(s);
        },

        pushNewline: function (indent) {
            this.segments.push({ text: "\n", tags: [] });
            if (indent > 0) {
                const spaces = Math.round(indent / measurer.spaceWidth);
                if (spaces > 0) {
                    this.segments.push({ text: " ".repeat(spaces), tags: [] });
                }
            }
            this.column = indent;
        },

        startTag: function (t) {
            this.tagStack.push(t);
        },

        endTags: function (count) {
            for (let j = 0; j < count; j++) {
                this.tagStack.pop();
            }
        },
    };
}

/**
 * Render a format tree to HTML at a given pixel width.
 * @param {*} fmtJson  - compact array format from Highlighted.lean
 * @param {Record<string, TokenAnnotation>} annotations - tag index → { cssClass, binding }
 * @param {number} pixelWidth - target width in pixels
 * @param {DOMMeasurer} measurer
 * @returns {string} HTML string
 */
function formatToHtml(fmtJson, annotations, pixelWidth, measurer) {
    const fmt = deserializeFormat(fmtJson);
    const ctx = makeRenderContext(annotations, measurer);
    prettyM(fmt, pixelWidth, 0, ctx, measurer);
    return segmentsToHtml(ctx.segments, annotations);
}

/**
 * @param {Segment[]} segments
 * @param {Record<string, TokenAnnotation>} annotations
 * @returns {string}
 */
function segmentsToHtml(segments, annotations) {
    const parts = [];
    for (const seg of segments) {
        const text = escapeHtml(seg.text);

        // Find the innermost tag with annotation
        let annotation = null;
        for (const tag of seg.tags.toReversed()) {
            const candidate = annotations[String(tag)];
            if (candidate) {
                annotation = candidate;
                break;
            }
        }

        if (annotation) {
            const cls = `${annotation.cssClass} token`;
            const bindAttr = annotation.binding
                ? ` data-binding="${escapeHtml(annotation.binding)}"`
                : "";
            parts.push(`<span class="${cls}"${bindAttr}>${text}</span>`);
        } else {
            parts.push(text);
        }
    }
    return parts.join("");
}

/**
 * @param {string} s
 * @returns {string}
 */
function escapeHtml(s) {
    return s
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;");
}

/**
 * Build structural goal HTML with empty .reflowed placeholders.
 * Returns { html, formats } where formats is an array of { fmt, annotations }
 * indexed by data-fmt-idx attributes on the .reflowed spans.
 * Caller inserts html into the DOM, measures .type cell widths, then calls
 * fillReflowedSpans to format expressions at measured widths.
 * @param {GoalData[]} goalsJson
 * @returns {GoalsResult}
 */
function goalsToHtml(goalsJson) {
    /** @type {FormatData[]} */
    const formats = [];
    const parts = [];
    for (const goal of goalsJson) {
        const goalParts = [];

        if (goal.name) {
            goalParts.push(`<span class="goal-name">${escapeHtml(goal.name)}</span>`);
        }

        // Hypotheses
        if (goal.hypotheses.length > 0) {
            const hypParts = [];
            for (const hyp of goal.hypotheses) {
                let typeHtml;
                if (hyp.ppType) {
                    const idx = formats.length;
                    formats.push(goalFormatData(hyp.ppType));
                    typeHtml = `<span class="reflowed" data-fmt-idx="${idx}"></span>`;
                } else {
                    typeHtml = '<span class="no-format">(no format data)</span>';
                }
                hypParts.push(
                    `<span class="hypothesis"><span class="name">${hyp.names
                        .map(escapeHtml)
                        .join(" ")}</span><span class="colon">:</span><span class="type">${
                        typeHtml
                    }</span></span>`,
                );
            }
            goalParts.push(`<span class="hypotheses">${hypParts.join("")}</span>`);
        }

        // Conclusion
        const vdash = escapeHtml(goal.goalPrefix);
        let conclHtml;
        if (goal.ppConclusion) {
            const idx = formats.length;
            formats.push(goalFormatData(goal.ppConclusion));
            conclHtml = `<span class="reflowed" data-fmt-idx="${idx}"></span>`;
        } else {
            conclHtml = '<span class="no-format">(no format data)</span>';
        }
        goalParts.push(
            `<span class="conclusion"><span class="goal-vdash">${vdash}</span><span class="type">${
                conclHtml
            }</span></span>`,
        );

        parts.push(`<div class="goal">${goalParts.join("")}</div>`);
    }
    return { html: parts.join(""), formats: formats };
}

/**
 * Format expressions into .reflowed spans using measured .type cell widths.
 * @param {Element} container
 * @param {FormatData[]} formats
 * @param {DOMMeasurer} measurer
 */
function fillReflowedSpans(container, formats, measurer) {
    for (const span of container.querySelectorAll(".reflowed[data-fmt-idx]")) {
        const idx = parseInt(span.getAttribute("data-fmt-idx") || "0");
        const entry = formats[idx];
        if (!entry) continue;
        const cell = span.closest(".type");
        if (!cell) continue;
        const width = measurer.measureElWidth(cell);
        // eslint-disable-next-line no-unsanitized/property -- formatToHtml escapes all text
        span.innerHTML = formatToHtml(entry.fmt, entry.annotations, width, measurer);
    }
}

/**
 * Checks whether `v` is a `FormatData`.
 * @param {*} v
 * @returns {v is FormatData}
 */
function isFormatData(v) {
    if (typeof v !== "object" || v === null || !("fmt" in v)) return false;
    const annotations = v.annotations;
    if (typeof annotations !== "object" || annotations === null) return false;
    return Object.values(annotations).every(
        (a) =>
            typeof a === "object" &&
            a !== null &&
            typeof a.cssClass === "string" &&
            (a.binding === undefined || typeof a.binding === "string"),
    );
}

/**
 * Whether `v` is a `Hypothesis`.
 * @param {*} v
 * @returns {v is Hypothesis}
 */
function isHypothesis(v) {
    return (
        typeof v === "object" &&
        v !== null &&
        Array.isArray(v.names) &&
        v.names.every((/** @type {*} */ n) => typeof n === "string") &&
        (v.ppType === null || typeof v.ppType === "string")
    );
}

/**
 * Whether `v` is a `GoalData`.
 * @param {*} v
 * @returns {v is GoalData}
 */
function isGoalData(v) {
    return (
        typeof v === "object" &&
        v !== null &&
        typeof v.goalPrefix === "string" &&
        (v.name === null || typeof v.name === "string") &&
        Array.isArray(v.hypotheses) &&
        v.hypotheses.every(isHypothesis) &&
        (v.ppConclusion === null || typeof v.ppConclusion === "string")
    );
}

/**
 * The `FormatData` encoded by a goal's `ppType` or `ppConclusion` string.
 * @param {string} json
 * @returns {FormatData}
 */
function goalFormatData(json) {
    /** @type {unknown} */
    const parsed = JSON.parse(json);
    if (!isFormatData(parsed)) throw new Error("goal ppType/ppConclusion: expected FormatData");
    return parsed;
}

/**
 * Run `layout` with a text measurer attached to `container`. The measurer is
 * removed from the DOM once `layout` returns or throws.
 * @template T
 * @param {HTMLElement} container
 * @param {(measurer: DOMMeasurer) => T} layout
 * @returns {T}
 */
function withMeasurer(container, layout) {
    const measurer = createDOMMeasurer(container);
    try {
        return layout(measurer);
    } finally {
        measurer.cleanup();
    }
}

/**
 * Width of `el`'s content box in CSS pixels.
 * @param {HTMLElement} el
 * @returns {number}
 */
function contentWidth(el) {
    const style = getComputedStyle(el);
    return (
        el.clientWidth -
        parseFloat(style.paddingLeft || "0") -
        parseFloat(style.paddingRight || "0")
    );
}

/**
 * Replace the contents of `panel` with `goals`, each hypothesis type and
 * conclusion laid out to fit its table cell.
 * @param {HTMLElement} panel
 * @param {GoalData[]} goals
 */
function renderGoals(panel, goals) {
    const result = goalsToHtml(goals);
    // eslint-disable-next-line no-unsanitized/property -- goalsToHtml escapes all text
    panel.innerHTML = `<span class="hl lean">${result.html}</span>`;
    withMeasurer(panel, (measurer) => fillReflowedSpans(panel, result.formats, measurer));
}

/**
 * Replace the contents of `codeEl` with `format` laid out to `width` pixels.
 * Text is measured inside `container`, which must share `codeEl`'s font.
 * @param {HTMLElement} container
 * @param {Element} codeEl
 * @param {FormatData} format
 * @param {number} width
 */
function renderFormat(container, codeEl, format, width) {
    // eslint-disable-next-line no-unsanitized/property -- formatToHtml escapes all text
    codeEl.innerHTML = withMeasurer(
        container,
        (measurer) =>
            `<span class="reflowed">${formatToHtml(
                format.fmt,
                format.annotations,
                width,
                measurer,
            )}</span>`,
    );
}
