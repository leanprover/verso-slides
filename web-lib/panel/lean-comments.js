// @ts-check
// TODO: remove when https://github.com/leanprover/verso/issues/274 is fixed
// (SubVerso will tokenize comments natively, making this post-processor unnecessary).
//
// Post-process Lean code blocks to style comments.
// Regular comments (-- …, /- … -/) are not tokenized by SubVerso;
// they end up as plain text inside <span class="inter-text"> elements.
// This script wraps comment text in <span class="lean-comment"> so CSS
// can give them a distinct color.
(function () {
    "use strict";

    /**
     * Finds the end of a /- … -/ block comment, handling nesting.
     * @param {string} text
     * @param {number} start
     * @returns {number}
     */
    function findBlockEnd(text, start) {
        var depth = 0;
        var i = start;
        while (i < text.length) {
            if (i + 1 < text.length && text[i] === "/" && text[i + 1] === "-") {
                depth++;
                i += 2;
            } else if (i + 1 < text.length && text[i] === "-" && text[i + 1] === "/") {
                depth--;
                i += 2;
                if (depth === 0) return i;
            } else {
                i++;
            }
        }
        return text.length;
    }

    /**
     * Splits text into segments, tagging comment regions.
     * @param {string} text
     * @returns {Array<{text: string, isComment: boolean}>|null}
     */
    function parseComments(text) {
        var segments = [];
        var i = 0;
        var plainStart = 0;
        var found = false;

        while (i < text.length) {
            // Block comment  /- … -/  (checked first so /-- is handled as block)
            if (i + 1 < text.length && text[i] === "/" && text[i + 1] === "-") {
                if (i > plainStart)
                    segments.push({ text: text.slice(plainStart, i), isComment: false });
                var end = findBlockEnd(text, i);
                segments.push({ text: text.slice(i, end), isComment: true });
                i = end;
                plainStart = i;
                found = true;
                continue;
            }
            // Line comment  -- …
            if (i + 1 < text.length && text[i] === "-" && text[i + 1] === "-") {
                if (i > plainStart)
                    segments.push({ text: text.slice(plainStart, i), isComment: false });
                var eol = text.indexOf("\n", i);
                var end = eol === -1 ? text.length : eol;
                segments.push({ text: text.slice(i, end), isComment: true });
                i = end;
                plainStart = i;
                found = true;
                continue;
            }
            i++;
        }

        if (!found) return null;
        if (plainStart < text.length)
            segments.push({ text: text.slice(plainStart), isComment: false });
        return segments;
    }

    /**
     * Replaces text nodes inside an inter-text span with comment-wrapped spans.
     * @param {Element} el
     */
    function processElement(el) {
        var text = el.textContent;
        if (text === null) return;
        if (text.indexOf("--") === -1 && text.indexOf("/-") === -1) return;

        var segments = parseComments(text);
        if (!segments) return;

        el.textContent = "";
        for (var k = 0; k < segments.length; k++) {
            var seg = segments[k];
            if (seg.isComment) {
                var span = document.createElement("span");
                span.className = "lean-comment";
                span.textContent = seg.text;
                el.appendChild(span);
            } else {
                el.appendChild(document.createTextNode(seg.text));
            }
        }
    }

    function run() {
        document.querySelectorAll(".hl.lean .inter-text").forEach(processElement);
    }

    Reveal.on("ready", run);
})();
