// Type declarations for external globals used by math.js.

interface KatexOptions {
    throwOnError?: boolean;
    displayMode?: boolean;
    /** Shared macro table; definitions added by one call are visible to later ones. */
    macros?: Record<string, unknown>;
    /**
     * When true, macros defined with `\def` / `\newcommand` persist in the
     * `macros` object after the render call returns (same as `\gdef`).
     */
    globalGroup?: boolean;
}

/** KaTeX renderer (global, loaded from lib/katex/dist/katex.min.js). */
declare var katex:
    | {
          render(tex: string, element: HTMLElement, options?: KatexOptions): void;
          renderToString(tex: string, options?: KatexOptions): string;
      }
    | undefined;

/** Window globals set by the page template. */
interface Window {
    /** Optional KaTeX prelude string evaluated once before any math is rendered. */
    __versoMathPrelude?: string;
}
