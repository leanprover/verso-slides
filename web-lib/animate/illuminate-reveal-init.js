// @ts-check

// Multi-animation reveal.js integration for VersoSlides.
// anim_core.js helpers (animFindSegment, animRenderSegFrame, etc.)
// are prepended by the Lean build via include_str concatenation.

(function () {
    /**
     * @typedef {{
     *   data: AnimData,
     *   container: HTMLElement,
     *   currentSeg: Segment | null,
     *   currentFrame: number,
     *   animId: number | null,
     *   pauseSteps: StepInfo[],
     *   autoPlay: boolean
     * }} AnimState
     */

    /** @type {Record<string, AnimState>} */
    const animations = {};

    /**
     * @param {AnimState} state
     * @param {number} frame
     */
    function showFrame(state, frame) {
        frame = animClampFrame(frame, state.data.totalFrames);
        state.currentSeg = animRenderSegFrame(
            state.container,
            animFindSegment(state.data.segments, frame),
            state.currentSeg,
            frame - animFindSegment(state.data.segments, frame).sf,
        );
        state.currentFrame = frame;
    }

    const scripts = document.querySelectorAll("script[data-illuminate-anim]");
    for (const scriptEl of scripts) {
        const containerId = scriptEl.getAttribute("data-illuminate-anim");
        if (!containerId) continue;
        const container = document.getElementById(containerId);
        if (!container) continue;
        /** @type {AnimData} */
        let data;
        try {
            data = JSON.parse(/** @type {string} */ (scriptEl.textContent));
        } catch {
            continue;
        }
        if (!data || !data.segments || data.segments.length === 0) continue;

        /** @type {AnimState} */
        const state = {
            data: data,
            container: container,
            currentSeg: null,
            currentFrame: 0,
            animId: null,
            pauseSteps: data.steps.filter((s) => {
                return s.pause;
            }),
            // Read autoplay setting from the container element
            autoPlay: container.getAttribute("data-illuminate-autoplay") === "true",
        };
        animations[containerId] = state;

        // Show first frame
        showFrame(state, 0);

        // Fragment spans are emitted in the HTML at build time (not created dynamically),
        // so Reveal.js sees them during its initial scan. Nothing to create here.
    }

    /**
     * @param {AnimState} state
     */
    function stopAnim(state) {
        if (state.animId !== null) {
            cancelAnimationFrame(state.animId);
            state.animId = null;
        }
    }

    /**
     * @param {AnimState} state
     * @param {number} loopStart
     * @param {number} loopEnd
     */
    function startLoop(state, loopStart, loopEnd) {
        const loopLen = loopEnd - loopStart;
        if (loopLen <= 0) return;
        /** @type {number | null} */
        let startTime = null;
        /** @param {number} timestamp */
        function tick(timestamp) {
            if (startTime === null) startTime = timestamp;
            const frame = animComputeFrame(startTime, timestamp, state.data.fps, loopStart);
            const loop = animWrapLoop(frame, loopStart, loopEnd);
            showFrame(state, loop.wrapped);
            state.animId = requestAnimationFrame(tick);
        }
        state.animId = requestAnimationFrame(tick);
    }

    /**
     * @param {AnimState} state
     * @param {number} targetFrame
     * @param {(() => void)} [onComplete]
     */
    function animateTo(state, targetFrame, onComplete) {
        stopAnim(state);
        const startFrame = state.currentFrame;
        /** @type {number | null} */
        let startTime = null;
        const dir = targetFrame > startFrame ? 1 : -1;
        /** @param {number} timestamp */
        function tick(timestamp) {
            if (startTime === null) startTime = timestamp;
            let frame = animComputeFrame(startTime, timestamp, state.data.fps, startFrame);
            if (dir < 0) {
                frame = startFrame - (frame - startFrame);
            }
            if ((dir > 0 && frame >= targetFrame) || (dir < 0 && frame <= targetFrame)) {
                showFrame(state, targetFrame);
                state.animId = null;
                if (onComplete) onComplete();
                return;
            }
            showFrame(state, frame);
            state.animId = requestAnimationFrame(tick);
        }
        if (startFrame === targetFrame) {
            if (onComplete) onComplete();
        } else {
            state.animId = requestAnimationFrame(tick);
        }
    }

    /**
     * Syncs an animation to the current fragment state on the slide.
     * When navigating backward, fragments are already visible, so the
     * animation should jump to the corresponding frame.
     * @param {AnimState} st
     */
    function syncToFragmentState(st) {
        stopAnim(st);

        // Count how many of this animation's fragments are currently visible
        const parent = st.container.parentElement;
        if (!parent) return;
        let visibleCount = 0;
        const frags = parent.querySelectorAll(
            `span.fragment[data-illuminate-container="${st.container.id}"]`,
        );
        for (const frag of frags) {
            if (frag.classList.contains("visible")) visibleCount++;
        }

        if (visibleCount > 0) {
            // Backward navigation: fragments already shown — jump to end of that step sequence
            const idx = Math.min(visibleCount - 1, st.pauseSteps.length - 1);
            const ps = st.pauseSteps[idx];
            if (ps?.loop) {
                const stepIdx = animFindCurrentStep(st.data.steps, ps.frame);
                const stepEnd = animFindStepEnd(st.data.steps, stepIdx, st.data.totalFrames);
                showFrame(st, ps.frame);
                startLoop(st, ps.frame, stepEnd);
            } else {
                showFrame(st, findTargetFrame(st, idx));
            }
        } else if (st.autoPlay) {
            // Forward navigation: auto-play up to (not through) the first pause step
            showFrame(st, 0);
            const firstPause = st.pauseSteps[0];
            if (firstPause) {
                animateTo(st, firstPause.frame);
            } else {
                animateTo(st, st.data.totalFrames - 1);
            }
        } else {
            // Forward navigation, no auto-play: show frame 0
            showFrame(st, 0);
        }
    }

    /**
     * Finds the frame to animate to when pause step `idx` is triggered.
     * Plays through the pause step and any subsequent non-pause steps,
     * stopping at the frame before the next pause step (or at the end).
     * @param {AnimState} state
     * @param {number} idx
     * @returns {number}
     */
    function findTargetFrame(state, idx) {
        const current = state.pauseSteps[idx];
        const next = state.pauseSteps[idx + 1];
        if (current && next) {
            // Stop just before the next pause step starts
            return Math.max(next.frame - 1, current.frame);
        }
        // Last pause step: play to the end
        return state.data.totalFrames - 1;
    }

    if (typeof Reveal !== "undefined") {
        // Sync animations when entering a slide (handles both forward and backward navigation)
        Reveal.on("slidechanged", () => {
            const slide = Reveal.getCurrentSlide();
            if (!slide) return;
            const containers = slide.querySelectorAll(".illuminate-anim");
            for (const containerEl of containers) {
                const st = animations[containerEl.id];
                if (st) syncToFragmentState(st);
            }
        });

        // Also trigger on initial load for the first slide
        Reveal.on("ready", () => {
            const slide = Reveal.getCurrentSlide();
            if (!slide) return;
            const containers = slide.querySelectorAll(".illuminate-anim");
            for (const containerEl of containers) {
                const st = animations[containerEl.id];
                if (st) syncToFragmentState(st);
            }
        });

        /**
         * Processes a single animation fragment for fragmentshown.
         * @param {HTMLElement} frag
         */
        function handleFragShown(frag) {
            const cid = frag.getAttribute("data-illuminate-container");
            if (!cid) return;
            const state = animations[cid];
            if (!state) return;
            const idx = parseInt(frag.getAttribute("data-illuminate-step-index") || "", 10);
            if (isNaN(idx) || idx >= state.pauseSteps.length) return;
            stopAnim(state);
            const ps = state.pauseSteps[idx];
            if (ps?.loop) {
                const stepIdx = animFindCurrentStep(state.data.steps, ps.frame);
                const stepEnd = animFindStepEnd(state.data.steps, stepIdx, state.data.totalFrames);
                // Looping step: animate to start, then loop
                animateTo(state, ps.frame, () => {
                    startLoop(state, ps.frame, stepEnd);
                });
            } else {
                // Animate through this step and any following non-pause steps
                const target = findTargetFrame(state, idx);
                animateTo(state, target, () => {
                    // If we landed in a loop step, start looping
                    const finalStepIdx = animFindCurrentStep(state.data.steps, target);
                    const finalStep = state.data.steps[finalStepIdx];
                    if (finalStep && finalStep.loop) {
                        const loopEnd = animFindStepEnd(
                            state.data.steps,
                            finalStepIdx,
                            state.data.totalFrames,
                        );
                        startLoop(state, finalStep.frame, loopEnd);
                    }
                });
            }
        }

        /**
         * Processes a single animation fragment for fragmenthidden.
         * @param {HTMLElement} frag
         */
        function handleFragHidden(frag) {
            const cid = frag.getAttribute("data-illuminate-container");
            if (!cid) return;
            const state = animations[cid];
            if (!state) return;
            const idx = parseInt(frag.getAttribute("data-illuminate-step-index") || "", 10);
            if (isNaN(idx)) return;
            stopAnim(state);
            const prevIdx = idx - 1;
            const ps = state.pauseSteps[prevIdx];
            if (ps) {
                if (ps.loop) {
                    const stepIdx = animFindCurrentStep(state.data.steps, ps.frame);
                    const stepEnd = animFindStepEnd(
                        state.data.steps,
                        stepIdx,
                        state.data.totalFrames,
                    );
                    startLoop(state, ps.frame, stepEnd);
                } else {
                    const target = findTargetFrame(state, prevIdx);
                    animateTo(state, target);
                }
            } else {
                // No previous step — go back to frame 0
                animateTo(state, 0);
            }
        }

        // Reveal.js may fire fragmentshown/hidden with e.fragment (one element)
        // or e.fragments (all elements at that index). Iterate all to find
        // animation fragments when multiple fragments share the same index.
        Reveal.on("fragmentshown", (e) => {
            const frags = e.fragments || [e.fragment];
            for (const frag of frags) {
                handleFragShown(frag);
            }
        });
        Reveal.on("fragmenthidden", (e) => {
            const frags = e.fragments || [e.fragment];
            for (const frag of frags) {
                handleFragHidden(frag);
            }
        });
    }
})();
