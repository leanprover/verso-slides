// Type declarations for the globals that illuminate-reveal-init.js uses.
//
// The animation helpers and the shape of the animation data come from Illuminate's
// player_js/anim_core.js and player_js/anim_data.d.ts, which jsconfig.json includes from the Lake
// package. This file declares the Reveal.js API that verso-slides uses.

/** Reveal.js presentation API (global). */
declare var Reveal: {
    on(event: string, callback: (event: any) => void): void;
    getCurrentSlide(): HTMLElement | null;
};
