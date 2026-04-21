// Type declarations for external globals used by math.js.

/** KaTeX renderer (global, loaded from lib/katex/dist/katex.min.js). */
declare var katex:
    | {
          render(
              tex: string,
              element: HTMLElement,
              options?: { throwOnError?: boolean; displayMode?: boolean },
          ): void;
      }
    | undefined;
