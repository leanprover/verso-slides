// Type declarations for third-party globals used by the panel scripts.

/** Reveal.js presentation API (global). */
declare var Reveal: {
    on(event: string, callback: (...args: any[]) => void): void;
    getCurrentSlide(): HTMLElement | null;
    getRevealElement(): HTMLElement | null;
    getScale(): number;
    /** Returns the backdrop element for the given slide `<section>`, if any. */
    getSlideBackground(slide: Element): HTMLElement | null;
};

/**
 * tippy.js (global, loaded from lib/tippy.js). Invoked as a function with a
 * selector/element/list of elements, and also exposes static properties
 * (`setDefaultProps`, `hideAll`, …) copied onto the function object.
 */
declare var tippy: ((targets: unknown, props?: unknown) => unknown) & Record<string, unknown>;

/** marked.js Markdown parser (global, may not be loaded). */
declare var marked: { parse(text: string): string } | undefined;

interface VersoVirProgram {
    readonly status: "active" | "failed" | "disposed";
    call(declaration: string, ...args: unknown[]): unknown;
}

interface PrettySegment {
    text: string;
    tags: bigint[];
}

interface Window {
    versoVir?: VersoVirProgram;
    versoVirReady?: Promise<VersoVirProgram>;
    /** State of this document's one-shot formatter initialization. */
    versoVirState?: "loading" | "ready" | "failed";
    /** Slides facade: compact input converted to typed Lean segments. */
    versoVirFormatSegments?: (format: unknown, width: number, indent: number) => PrettySegment[];
}
