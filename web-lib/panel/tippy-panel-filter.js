(function () {
    var _origTippy = tippy;

    function shouldSuppress(el) {
        return el.closest && (el.closest(".code-with-panel") || el.closest("code.hl.lean.inline"));
    }

    function filterTargets(targets) {
        if (typeof targets === "string") {
            targets = document.querySelectorAll(targets);
        }
        if (targets instanceof Element) {
            return shouldSuppress(targets) ? [] : [targets];
        }
        if (targets && typeof targets.length === "number") {
            var filtered = [];
            for (var i = 0; i < targets.length; i++) {
                if (!shouldSuppress(targets[i])) filtered.push(targets[i]);
            }
            return filtered;
        }
        return targets;
    }

    tippy = function (targets, props) {
        return _origTippy(filterTargets(targets), props);
    };
    Object.keys(_origTippy).forEach(function (k) {
        tippy[k] = _origTippy[k];
    });
})();
