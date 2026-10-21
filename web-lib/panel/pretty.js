// @ts-check
// pretty.js — Browser adapter around Lean's Std.Format.prettyM.
//
// Lean owns layout, executed by VIR. This is the shared browser measurement,
// annotation and presentation layer for panels and lightboxes.

"use strict";

class PrettyFormatError extends Error {
    /** @param {string} code */
    constructor(code) {
        super("PrettyM input error: " + code);
        this.name = "PrettyFormatError";
        this.code = code;
    }
}

/** Typed array boundary for the compact format emitted by Verso.
 * @param {VersoVirProgram} program @param {*} format
 * @param {number} width @param {number} indent
 * @return {PrettySegment[]}
 */
function formatCompactSegments(program, format, width, indent) {
    var admitted = compactFormatToStdFormat(format);
    return /** @type {PrettySegment[]} */ (
        program.call("VersoSlides.VirPrettyM.formatSegments", admitted, width, indent)
    );
}

/**
 * @typedef {{
 *   spaceWidth: number,
 *   measureElWidth: (el: Element) => number,
 *   cleanup: () => void
 * }} DOMMeasurer
 *
 * @typedef {{ cssClass: string, binding?: string }} TokenAnnotation
 *
 * @typedef {{ fmt: *, annotations: Record<string, TokenAnnotation> }} FormatData
 *
 * @typedef {{ names: string[], ppType: string | null }} Hypothesis
 *
 * @typedef {{ name: string | null, hypotheses: Hypothesis[], goalPrefix: string, ppConclusion: string | null }} GoalData
 *
 * @typedef {{ html: string, formats: FormatData[] }} GoalsResult
 */

/** Convert Verso's compact format to VIR's Std.Format representation.
 * Preserve numeric fields for VIR to validate/marshal as Nat or Int.
 * Slides checks its compact constructor shape; resource budgets are deferred.
 * @param {*} json @return {*}
 */
function compactFormatToStdFormat(json) {
    if (json === null) return { kind: "nil" };
    if (typeof json === "string") return { kind: "text", value: json };
    if (json === 1) return { kind: "line" };
    if (!Array.isArray(json) || json.length === 0) {
        throw new PrettyFormatError("invalidInput");
    }
    switch (json[0]) {
        case 2:
            if (json.length !== 2 || typeof json[1] !== "boolean")
                throw new PrettyFormatError("invalidInput");
            return { kind: "align", value: !!json[1] };
        case 3:
            if (json.length !== 3) throw new PrettyFormatError("invalidInput");
            return {
                kind: "nest",
                fields: { indent: json[1], f: compactFormatToStdFormat(json[2]) },
            };
        case 4:
            if (json.length !== 3) throw new PrettyFormatError("invalidInput");
            return {
                kind: "append",
                fields: {
                    arg1: compactFormatToStdFormat(json[1]),
                    arg2: compactFormatToStdFormat(json[2]),
                },
            };
        case 5:
            if (json.length !== 2) throw new PrettyFormatError("invalidInput");
            return {
                kind: "group",
                fields: { arg1: compactFormatToStdFormat(json[1]), behavior: "allOrNone" },
            };
        case 6:
            if (json.length !== 2) throw new PrettyFormatError("invalidInput");
            return {
                kind: "group",
                fields: { arg1: compactFormatToStdFormat(json[1]), behavior: "fill" },
            };
        case 7:
            if (json.length !== 3) throw new PrettyFormatError("invalidInput");
            return {
                kind: "tag",
                fields: {
                    arg1: json[1],
                    arg2: compactFormatToStdFormat(json[2]),
                },
            };
        default:
            throw new PrettyFormatError("invalidInput");
    }
}

/**
 * Create a DOM-based measurer for panel widths. The text itself is monospace,
 * so one measured space converts the CSS-pixel boundary to `prettyM` columns.
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

    var clientW = panel.clientWidth;
    var scale = 1;
    if (clientW > 0) {
        scale = panel.getBoundingClientRect().width / clientW;
    }

    probe.textContent = " ";
    var spaceWidth = probe.getBoundingClientRect().width / scale;
    return {
        spaceWidth: spaceWidth,
        measureElWidth: function (el) {
            return el.getBoundingClientRect().width / scale;
        },
        cleanup: function () {
            container.remove();
        },
    };
}

/**
 * Render a compact format through Lean's `Std.Format.prettyM`, then feed the
 * result back into the existing JavaScript annotation/HTML stage.
 * @param {*} fmtJson
 * @param {Record<string, TokenAnnotation>} annotations
 * @param {number} pixelWidth
 * @param {DOMMeasurer} measurer
 * @return {string}
 */
function formatToHtml(fmtJson, annotations, pixelWidth, measurer) {
    var spaceWidth = measurer.spaceWidth;
    if (
        !Number.isFinite(spaceWidth) ||
        spaceWidth <= 0 ||
        !Number.isFinite(pixelWidth) ||
        pixelWidth < 0
    )
        throw new PrettyFormatError("measurement");
    var formatter = window.versoVirFormatSegments;
    if (!formatter) throw new Error("Lean formatting is not ready");
    var columns = Math.max(1, Math.floor(pixelWidth / spaceWidth));
    var segments = formatter(fmtJson, columns, 0);
    return segmentsToHtml(segments, annotations || {});
}

/**
 * @param {PrettySegment[]} segments
 * @param {Record<string, TokenAnnotation>} annotations
 * @return {string}
 */
function segmentsToHtml(segments, annotations) {
    var parts = [];
    for (var si = 0; si < segments.length; si++) {
        var seg = segments[si];
        var text = escapeHtml(seg.text);

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
            parts.push(text);
        }
    }
    return parts.join("");
}

/** @param {string} s @return {string} */
function escapeHtml(s) {
    return s
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;");
}

/**
 * Build structural goal HTML with empty .reflowed placeholders.
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

        if (goal.hypotheses.length > 0) {
            var hypParts = [];
            for (var hi = 0; hi < goal.hypotheses.length; hi++) {
                var hyp = goal.hypotheses[hi];
                var typeHtml;
                if (hyp.ppType) {
                    var idx = formats.length;
                    formats.push(goalFormatData(hyp.ppType));
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

        var vdash = escapeHtml(goal.goalPrefix);
        var conclHtml;
        if (goal.ppConclusion) {
            var idx = formats.length;
            formats.push(goalFormatData(goal.ppConclusion));
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

function formatterIsReady() {
    return window.versoVirState === "ready";
}

/** @param {HTMLElement} container */
function showFormattingStatus(container) {
    var message = document.createElement("p");
    message.className = "vir-panel-status";
    message.setAttribute("role", "status");
    message.textContent =
        window.versoVirState === "loading"
            ? "Loading Lean formatting…"
            : window.versoVirState === "failed"
              ? "Lean formatting is unavailable."
              : "Lean formatting is unavailable.";
    container.appendChild(message);
}

/** @param {HTMLElement} container @param {unknown} error */
function showFormattingFailure(container, error) {
    try {
        console.error("Lean expression formatting failed", error);
    } catch (_) {
        /* Best-effort sink. */
    }
    container.textContent = "";
    var message = document.createElement("p");
    message.className = "vir-panel-status";
    message.setAttribute("role", "alert");
    message.textContent = "This Lean expression could not be formatted.";
    container.appendChild(message);
}

/**
 * Checks whether `v` is a `FormatData`.
 * @param {*} v
 * @return {v is FormatData}
 */
function isFormatData(v) {
    if (typeof v !== "object" || v === null || !("fmt" in v)) return false;
    const annotations = v.annotations;
    if (typeof annotations !== "object" || annotations === null) return false;
    return Object.values(annotations).every(
        (a) => typeof a === "object" && a !== null && typeof a.cssClass === "string",
    );
}

/**
 * Whether `v` is a `Hypothesis`.
 * @param {*} v
 * @return {v is Hypothesis}
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
 * @return {v is GoalData}
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
 * @return {FormatData}
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
 * @param {function(DOMMeasurer): T} layout
 * @return {T}
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
 * @return {number}
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
    panel.innerHTML = '<span class="hl lean">' + result.html + "</span>";
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
    codeEl.innerHTML = withMeasurer(
        container,
        (measurer) =>
            '<span class="reflowed">' +
            formatToHtml(format.fmt, format.annotations, width, measurer) +
            "</span>",
    );
}
