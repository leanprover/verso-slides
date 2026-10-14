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
 * @typedef {{ names: string[], ppType?: string | FormatData }} Hypothesis
 *
 * @typedef {{ name?: string, hypotheses: Hypothesis[], goalPrefix: string, ppConclusion?: string | FormatData }} GoalData
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

/** Parse rich metadata, insert goal structure and measure after layout. Every
 * caller uses this rendering path, including font/resize/readiness reflow.
 * @param {HTMLElement} container @param {Element} source
 */
function renderRichFormat(container, source) {
    var rich = source.getAttribute("data-rich-format");
    if (!rich) throw new PrettyFormatError("invalidInput");
    var parsed = JSON.parse(rich);
    if (Array.isArray(parsed)) {
        var result = goalsToHtml(parsed);
        container.innerHTML = '<span class="hl lean">' + result.html + "</span>";
        var measurer = createDOMMeasurer(container);
        try {
            fillReflowedSpans(container, result.formats, measurer);
        } finally {
            measurer.cleanup();
        }
    } else {
        var measurer = createDOMMeasurer(container);
        try {
            var style = getComputedStyle(container);
            var width = Math.max(
                0,
                container.clientWidth -
                    parseFloat(style.paddingLeft || "0") -
                    parseFloat(style.paddingRight || "0"),
            );
            source.innerHTML =
                '<span class="reflowed">' +
                formatToHtml(parsed.fmt, parsed.annotations, width, measurer) +
                "</span>";
        } finally {
            measurer.cleanup();
        }
    }
}
