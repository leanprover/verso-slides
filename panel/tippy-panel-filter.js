(function () {
    var _origTippy = tippy;
    tippy = function (targets, props) {
        if (typeof targets === "string") {
            var all = document.querySelectorAll(targets);
            var filtered = [];
            all.forEach(function (el) {
                if (!el.closest(".code-with-panel") && !el.closest("code.hl.lean.inline"))
                    filtered.push(el);
            });
            return _origTippy(filtered, props);
        }
        return _origTippy(targets, props);
    };
    Object.keys(_origTippy).forEach(function (k) {
        tippy[k] = _origTippy[k];
    });
})();
