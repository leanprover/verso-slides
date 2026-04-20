// Type declarations for external globals used by panel.js and pretty.js.

/** Reveal.js presentation API (global). */
declare var Reveal: {
    on(event: string, callback: (...args: any[]) => void): void;
    getCurrentSlide(): HTMLElement | null;
    getRevealElement(): HTMLElement | null;
    getScale(): number;
};

/** marked.js Markdown parser (global, may not be loaded). */
declare var marked: { parse(text: string): string } | undefined;

/** pretty.js — render a format tree to HTML at a given pixel width (global). */
declare function formatToHtml(
    fmtJson: any,
    annotations: Record<string, any>,
    pixelWidth: number,
    measurer: DOMMeasurer,
): string;

/** pretty.js — create a DOM-based measurer for pixel-accurate text width measurement (global). */
declare function createDOMMeasurer(panel: HTMLElement): DOMMeasurer;
