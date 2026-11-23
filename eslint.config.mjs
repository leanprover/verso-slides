import globals from "globals";
import shared from "./eslint.shared.mjs";

export default [
    {
        ignores: [
            "vendor/",
            "**/*.min.js",
            "node_modules/",
            ".lake/",
            "**/.lake/",
            "_out/",
            "_slides/",
            "_test/",
            "browser-tests/",
        ],
    },
    {
        files: ["web-lib/**/*.js"],
        languageOptions: {
            ecmaVersion: 2024,
            sourceType: "script",
            globals: { ...globals.browser },
        },
    },
    {
        files: ["web-lib/widget/**/*.js"],
        languageOptions: { sourceType: "module" },
    },
    {
        files: ["web-lib/animate/**/*.js", "web-lib/panel/**/*.js"],
        languageOptions: { globals: { Reveal: "readonly" } },
    },
    {
        // anim_core.js from Illuminate is prepended to this script by the Lean build.
        files: ["web-lib/animate/illuminate-reveal-init.js"],
        languageOptions: {
            globals: {
                animClampFrame: "readonly",
                animComputeFrame: "readonly",
                animFindCurrentStep: "readonly",
                animFindSegment: "readonly",
                animFindStepEnd: "readonly",
                animRenderSegFrame: "readonly",
                animWrapLoop: "readonly",
            },
        },
    },
    {
        files: ["web-lib/math/math.js"],
        languageOptions: { globals: { katex: "readonly" } },
    },
    {
        files: ["web-lib/panel/tippy-panel-filter.js"],
        languageOptions: { globals: { tippy: "writable" } },
    },
    {
        // pretty.js is loaded before these scripts and defines these functions.
        files: ["web-lib/panel/panel.js", "web-lib/panel/lightbox.js"],
        languageOptions: {
            globals: {
                contentWidth: "readonly",
                isFormatData: "readonly",
                isGoalData: "readonly",
                renderFormat: "readonly",
                renderGoals: "readonly",
            },
        },
    },
    ...shared,
];
