// Type declarations for external globals used by panel.js and pretty.js.

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

/** pretty.js — render a format tree to HTML at a given pixel width (global). */
declare function formatToHtml(
    fmtJson: any,
    annotations: Record<string, any>,
    pixelWidth: number,
    measurer: DOMMeasurer,
): string;

/** pretty.js — measure panel widths and monospace columns in CSS pixels (global). */
declare function createDOMMeasurer(panel: HTMLElement): DOMMeasurer;

declare function renderRichFormat(container: HTMLElement, source: Element): void;
declare function showFormattingStatus(container: HTMLElement): void;
declare function showFormattingFailure(container: HTMLElement, error: unknown): void;
declare function formatterIsReady(): boolean;

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
