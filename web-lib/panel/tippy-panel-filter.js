(function () {
    const _origTippy = tippy;

    /**
     * @param {Element} el
     * @returns {Element | null | undefined}
     */
    function shouldSuppress(el) {
        return el.closest && (el.closest(".code-with-panel") || el.closest("code.hl.lean.inline"));
    }

    /**
     * @param {unknown} targets
     * @returns {unknown}
     */
    function filterTargets(targets) {
        if (typeof targets === "string") {
            targets = document.querySelectorAll(targets);
        }
        if (targets instanceof Element) {
            return shouldSuppress(targets) ? [] : [targets];
        }
        if (targets && typeof (/** @type {{ length?: unknown }} */ (targets).length) === "number") {
            const arrayLike = /** @type {ArrayLike<Element>} */ (targets);
            const filtered = [];
            for (const el of Array.from(arrayLike)) {
                if (!shouldSuppress(el)) filtered.push(el);
            }
            return filtered;
        }
        return targets;
    }

    /** @type {any} */
    const wrapped = function (/** @type {unknown} */ targets, /** @type {unknown} */ props) {
        return _origTippy(filterTargets(targets), props);
    };
    Object.keys(_origTippy).forEach((k) => {
        wrapped[k] = /** @type {Record<string, unknown>} */ (_origTippy)[k];
    });
    tippy = wrapped;
})();
