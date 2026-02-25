// @ts-check
// pretty.js — Direct port of Lean 4's Std.Format pretty printer
// Source: Init/Data/Format/Basic.lean (leanprover/lean4-nightly:nightly-2026-02-23-rev2)
//
// Renders a serialized Std.Format tree at a given pixel width,
// producing an array of output segments with tag annotations.
// Uses DOM-based measurement for accurate pixel widths.

"use strict";

/**
 * @typedef {{ type: string, [key: string]: * }} FormatNode
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
 * @typedef {{ names: string[], ppType?: string | FormatData }} Hypothesis
 *
 * @typedef {{ name?: string, hypotheses: Hypothesis[], goalPrefix: string, ppConclusion?: string | FormatData }} GoalData
 *
 * @typedef {{ html: string, formats: FormatData[] }} GoalsResult
 */

// --- Format deserialization ---

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
 * @return {FormatNode}
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

// --- DOM-based pixel measurement ---

/**
 * Create a DOM-based measurer for pixel-accurate text width measurement.
 * Accounts for reveal.js CSS transform scaling.
 * @param {HTMLElement} panel
 * @return {DOMMeasurer}
 */
function createDOMMeasurer(panel) {
    var container = document.createElement("span");
    container.className = "hl lean reflowed";
    container.style.cssText =
        "position:absolute;visibility:hidden;white-space:pre;pointer-events:none";
    var probe = document.createElement("span");
    container.appendChild(probe);
    panel.appendChild(container);

    // Compute CSS transform scale factor.
    // reveal.js applies transform:scale() to slides, which makes
    // getBoundingClientRect() return viewport-scaled values while
    // clientWidth returns CSS layout pixels. We need CSS pixels.
    var clientW = panel.clientWidth;
    var scale = 1;
    if (clientW > 0) {
        scale = panel.getBoundingClientRect().width / clientW;
    }

    /** @type {Record<string, number>} */
    var cache = {};
    /** @param {string} s @return {number} */
    function measure(s) {
        if (s in cache) return cache[s];
        probe.textContent = s;
        var w = probe.getBoundingClientRect().width / scale;
        cache[s] = w;
        return w;
    }
    var spaceWidth = measure(" ");
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

// --- SpaceResult helpers ---

/**
 * @param {boolean} [foundLine]
 * @param {boolean} [foundFlattenedHardLine]
 * @param {number} [space]
 * @return {SpaceResult}
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
 * @return {SpaceResult}
 */
function merge(w, r1, r2fn) {
    if (r1.space > w || r1.foundLine) return r1;
    var r2 = r2fn(w - r1.space);
    return {
        foundLine: r2.foundLine,
        foundFlattenedHardLine: r1.foundFlattenedHardLine || r2.foundFlattenedHardLine,
        space: r1.space + r2.space,
    };
}

// --- spaceUptoLine: measures how much space a format takes (in pixels) ---

/**
 * @param {FormatNode} f
 * @param {boolean} flatten
 * @param {number} m
 * @param {number} w
 * @param {DOMMeasurer} measurer
 * @return {SpaceResult}
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
            var idx = f.str.indexOf("\n");
            if (idx === -1) {
                return spaceResult(false, false, measurer.measure(f.str));
            } else {
                return spaceResult(true, flatten, measurer.measure(f.str.substring(0, idx)));
            }
        }
        case "append":
            return merge(w, spaceUptoLine(f.f1, flatten, m, w, measurer), function (w2) {
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
 * @return {boolean}
 */
function shouldFlatten(fla) {
    return fla.type === "allow" && !!fla.fits;
}

/**
 * @param {WorkGroup[]} groups
 * @param {number} col
 * @param {number} w
 * @param {DOMMeasurer} measurer
 * @return {SpaceResult}
 */
function spaceUptoLineGroups(groups, col, w, measurer) {
    var result = spaceResult();
    var remainingW = w;

    for (var gi = 0; gi < groups.length; gi++) {
        var g = groups[gi];
        var flatten = shouldFlatten(g.fla);
        for (var ii = 0; ii < g.items.length; ii++) {
            var item = g.items[ii];
            var r = spaceUptoLine(
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

// --- pushGroup: creates a new work group with flattening decision ---

/**
 * @param {"allOrNone" | "fill"} flb
 * @param {WorkItem[]} items
 * @param {WorkGroup[]} gs
 * @param {number} w
 * @param {RenderContext} ctx
 * @param {DOMMeasurer} measurer
 * @return {WorkGroup[]}
 */
function pushGroup(flb, items, gs, w, ctx, measurer) {
    var k = ctx.column;
    var remaining = w - k;
    var g = { fla: { type: "allow", fits: flb === "allOrNone" }, flb: flb, items: items };
    var r = spaceUptoLineGroups([g], k, remaining, measurer);
    var r2 = merge(remaining, r, function (w2) {
        return spaceUptoLineGroups(gs, k, w2, measurer);
    });
    var fits = !r.foundFlattenedHardLine && r2.space <= remaining;
    g = { fla: { type: "allow", fits: fits }, flb: flb, items: items };
    return [g].concat(gs);
}

// --- be: the main layout engine (iterative port) ---

/**
 * @param {number} w
 * @param {WorkGroup[]} groups
 * @param {RenderContext} ctx
 * @param {DOMMeasurer} measurer
 */
function be(w, groups, ctx, measurer) {
    while (groups.length > 0) {
        var g = groups[0];
        if (g.items.length === 0) {
            groups = groups.slice(1);
            continue;
        }
        var i = g.items[0];
        var restItems = g.items.slice(1);
        var restGroup = { fla: g.fla, flb: g.flb, items: restItems };
        var gs = [restGroup].concat(groups.slice(1));

        switch (i.f.type) {
            case "nil":
                ctx.endTags(i.activeTags);
                groups = gs;
                break;

            case "tag":
                ctx.startTag(i.f.n);
                var newItem = { f: i.f.f, indent: i.indent, activeTags: i.activeTags + 1 };
                gs[0] = { fla: g.fla, flb: g.flb, items: [newItem].concat(restItems) };
                groups = gs;
                break;

            case "append":
                var i1 = { f: i.f.f1, indent: i.indent, activeTags: 0 };
                var i2 = { f: i.f.f2, indent: i.indent, activeTags: i.activeTags };
                gs[0] = { fla: g.fla, flb: g.flb, items: [i1, i2].concat(restItems) };
                groups = gs;
                break;

            case "nest":
                var nestItem = {
                    f: i.f.f,
                    indent: i.indent + i.f.indent * measurer.spaceWidth,
                    activeTags: i.activeTags,
                };
                gs[0] = { fla: g.fla, flb: g.flb, items: [nestItem].concat(restItems) };
                groups = gs;
                break;

            case "text": {
                var s = i.f.str;
                var nlIdx = s.indexOf("\n");
                if (nlIdx === -1) {
                    ctx.pushOutput(s);
                    ctx.endTags(i.activeTags);
                    groups = gs;
                } else {
                    ctx.pushOutput(s.substring(0, nlIdx));
                    ctx.pushNewline(Math.max(0, i.indent));
                    /** @type {WorkItem} */
                    var newTextItem = {
                        f: { type: "text", str: s.substring(nlIdx + 1) },
                        indent: i.indent,
                        activeTags: i.activeTags,
                    };
                    var newItems = [newTextItem].concat(restItems);
                    // After hard line break, re-evaluate flattening
                    if (g.fla.type === "disallow") {
                        gs[0] = { fla: g.fla, flb: g.flb, items: newItems };
                        groups = gs;
                    } else {
                        groups = pushGroup(g.flb, newItems, groups.slice(1), w, ctx, measurer);
                    }
                }
                break;
            }

            case "line":
                if (g.flb === "allOrNone") {
                    if (shouldFlatten(g.fla)) {
                        ctx.pushOutput(" ");
                        ctx.endTags(i.activeTags);
                        groups = gs;
                    } else {
                        ctx.pushNewline(Math.max(0, i.indent));
                        ctx.endTags(i.activeTags);
                        groups = gs;
                    }
                } else {
                    // fill behavior
                    var doBreak = function () {
                        ctx.pushNewline(Math.max(0, i.indent));
                        ctx.endTags(i.activeTags);
                        return pushGroup("fill", restItems, groups.slice(1), w, ctx, measurer);
                    };
                    if (shouldFlatten(g.fla)) {
                        // Try to fit next item too
                        var tryGs = pushGroup(
                            "fill",
                            restItems,
                            groups.slice(1),
                            w - measurer.spaceWidth,
                            ctx,
                            measurer,
                        );
                        var nextG = tryGs[0];
                        if (shouldFlatten(nextG.fla)) {
                            ctx.pushOutput(" ");
                            ctx.endTags(i.activeTags);
                            groups = tryGs;
                        } else {
                            groups = doBreak();
                        }
                    } else {
                        groups = doBreak();
                    }
                }
                break;

            case "align":
                if (shouldFlatten(g.fla) && !i.f.force) {
                    ctx.endTags(i.activeTags);
                    groups = gs;
                } else {
                    var k = ctx.column;
                    if (k < i.indent) {
                        var pad = Math.max(0, i.indent - k);
                        ctx.pushOutput(" ".repeat(Math.round(pad / measurer.spaceWidth)));
                        ctx.endTags(i.activeTags);
                        groups = gs;
                    } else {
                        ctx.pushNewline(Math.max(0, i.indent));
                        ctx.endTags(i.activeTags);
                        groups = gs;
                    }
                }
                break;

            case "group":
                if (shouldFlatten(g.fla)) {
                    // flatten(group f) = flatten f
                    var gItem = { f: i.f.f, indent: i.indent, activeTags: i.activeTags };
                    gs[0] = { fla: g.fla, flb: g.flb, items: [gItem].concat(restItems) };
                    groups = gs;
                } else {
                    var groupItem = { f: i.f.f, indent: i.indent, activeTags: i.activeTags };
                    groups = pushGroup(i.f.behavior, [groupItem], gs, w, ctx, measurer);
                }
                break;

            default:
                // Unknown format node, skip
                ctx.endTags(i.activeTags);
                groups = gs;
                break;
        }
    }
}

// --- prettyM: entry point ---

/**
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

// --- Rendering context that collects tagged output segments ---

/**
 * @param {Record<string, TokenAnnotation>} annotations
 * @param {DOMMeasurer} measurer
 * @return {RenderContext}
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
                var spaces = Math.round(indent / measurer.spaceWidth);
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
            for (var j = 0; j < count; j++) {
                this.tagStack.pop();
            }
        },
    };
}

// --- Public API ---

// Known Lean keywords for styling untagged text
/** @type {Set<string>} */
var LEAN_KEYWORDS = new Set([
    "def",
    "theorem",
    "lemma",
    "example",
    "instance",
    "class",
    "structure",
    "inductive",
    "where",
    "let",
    "have",
    "do",
    "if",
    "then",
    "else",
    "match",
    "with",
    "fun",
    "return",
    "by",
    "at",
    "in",
    "for",
    "while",
    "repeat",
    "try",
    "catch",
    "finally",
    "throw",
    "import",
    "open",
    "namespace",
    "section",
    "end",
    "variable",
    "universe",
    "axiom",
    "opaque",
    "abbrev",
    "noncomputable",
    "private",
    "protected",
    "partial",
    "unsafe",
    "mutual",
    "deriving",
    "sorry",
    "admit",
    "Type",
    "Prop",
    "Sort",
    "true",
    "false",
    "calc",
    "suffices",
    "show",
    "from",
    "macro",
    "syntax",
    "elab",
    "attribute",
    "set_option",
    "extends",
    "intro",
    "apply",
    "exact",
    "simp",
    "rfl",
    "rw",
    "rewrite",
    "cases",
    "induction",
    "constructor",
    "exists",
    "use",
    "obtain",
    "rcases",
    "rintro",
    "ring",
    "omega",
    "decide",
    "norm_num",
    "linarith",
    "positivity",
    "aesop",
    "trivial",
    "assumption",
    "contradiction",
    "absurd",
    "exfalso",
    "push_neg",
    "contrapose",
]);

/**
 * Render a format tree to HTML at a given pixel width.
 * @param {*} fmtJson  - compact array format from Highlighted.lean
 * @param {Record<string, TokenAnnotation>} annotations - tag index → { cssClass, binding }
 * @param {number} pixelWidth - target width in pixels
 * @param {DOMMeasurer} measurer
 * @return {string} HTML string
 */
function formatToHtml(fmtJson, annotations, pixelWidth, measurer) {
    var fmt = deserializeFormat(fmtJson);
    var ctx = makeRenderContext(annotations, measurer);
    prettyM(fmt, pixelWidth, 0, ctx, measurer);
    return segmentsToHtml(ctx.segments, annotations);
}

/**
 * @param {Segment[]} segments
 * @param {Record<string, TokenAnnotation>} annotations
 * @return {string}
 */
function segmentsToHtml(segments, annotations) {
    var parts = [];
    for (var si = 0; si < segments.length; si++) {
        var seg = segments[si];
        var text = escapeHtml(seg.text);

        // Find the innermost tag with annotation
        var annotation = null;
        for (var ti = seg.tags.length - 1; ti >= 0; ti--) {
            var tagKey = String(seg.tags[ti]);
            if (annotations[tagKey]) {
                annotation = annotations[tagKey];
                break;
            }
        }

        if (annotation) {
            var cls = annotation.cssClass + " token";
            var bindAttr = annotation.binding
                ? ' data-binding="' + escapeHtml(annotation.binding) + '"'
                : "";
            parts.push('<span class="' + cls + '"' + bindAttr + ">" + text + "</span>");
        } else {
            var trimmed = seg.text.trim();
            if (trimmed && LEAN_KEYWORDS.has(trimmed)) {
                parts.push('<span class="keyword">' + text + "</span>");
            } else {
                parts.push(text);
            }
        }
    }
    return parts.join("");
}

/**
 * @param {string} s
 * @return {string}
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
 * @return {GoalsResult}
 */
function goalsToHtml(goalsJson) {
    /** @type {FormatData[]} */
    var formats = [];
    var parts = [];
    for (var gi = 0; gi < goalsJson.length; gi++) {
        var goal = goalsJson[gi];
        var goalParts = [];

        if (goal.name) {
            goalParts.push('<span class="goal-name">' + escapeHtml(goal.name) + "</span>");
        }

        // Hypotheses
        if (goal.hypotheses.length > 0) {
            var hypParts = [];
            for (var hi = 0; hi < goal.hypotheses.length; hi++) {
                var hyp = goal.hypotheses[hi];
                var typeHtml;
                if (hyp.ppType) {
                    var fmtData =
                        typeof hyp.ppType === "string" ? JSON.parse(hyp.ppType) : hyp.ppType;
                    var idx = formats.length;
                    formats.push({ fmt: fmtData.fmt, annotations: fmtData.annotations || {} });
                    typeHtml = '<span class="reflowed" data-fmt-idx="' + idx + '"></span>';
                } else {
                    typeHtml = '<span class="no-format">(no format data)</span>';
                }
                hypParts.push(
                    '<span class="hypothesis"><span class="name">' +
                        hyp.names.map(escapeHtml).join(" ") +
                        '</span><span class="colon">:</span><span class="type">' +
                        typeHtml +
                        "</span></span>",
                );
            }
            goalParts.push('<span class="hypotheses">' + hypParts.join("") + "</span>");
        }

        // Conclusion
        var vdash = escapeHtml(goal.goalPrefix);
        var conclHtml;
        if (goal.ppConclusion) {
            var conclData =
                typeof goal.ppConclusion === "string"
                    ? JSON.parse(goal.ppConclusion)
                    : goal.ppConclusion;
            var idx = formats.length;
            formats.push({ fmt: conclData.fmt, annotations: conclData.annotations || {} });
            conclHtml = '<span class="reflowed" data-fmt-idx="' + idx + '"></span>';
        } else {
            conclHtml = '<span class="no-format">(no format data)</span>';
        }
        goalParts.push(
            '<span class="conclusion"><span class="goal-vdash">' +
                vdash +
                '</span><span class="type">' +
                conclHtml +
                "</span></span>",
        );

        parts.push('<div class="goal">' + goalParts.join("") + "</div>");
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
    var spans = container.querySelectorAll(".reflowed[data-fmt-idx]");
    for (var i = 0; i < spans.length; i++) {
        var span = spans[i];
        var idx = parseInt(span.getAttribute("data-fmt-idx") || "0");
        var entry = formats[idx];
        if (!entry) continue;
        var cell = span.closest(".type");
        if (!cell) continue;
        var width = measurer.measureElWidth(cell);
        span.innerHTML = formatToHtml(entry.fmt, entry.annotations, width, measurer);
    }
}
