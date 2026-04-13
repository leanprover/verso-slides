// @ts-check

// Multi-animation reveal.js integration for VersoSlides.
// anim_core.js helpers (animFindSegment, animRenderSegFrame, etc.)
// are prepended by the Lean build via include_str concatenation.

(function () {
    /** @type {Object<string, {data: AnimData, container: HTMLElement, currentSeg: Segment | null, currentFrame: number, animId: number | null, pauseSteps: StepInfo[]}>} */
    var animations = {};

    /**
     * @param {{data: AnimData, container: HTMLElement, currentSeg: Segment | null, currentFrame: number}} state
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

    var scripts = document.querySelectorAll("script[data-illuminate-anim]");
    for (var si = 0; si < scripts.length; si++) {
        var scriptEl = scripts[si];
        var containerId = scriptEl.getAttribute("data-illuminate-anim");
        if (!containerId) continue;
        var container = document.getElementById(containerId);
        if (!container) continue;
        /** @type {AnimData} */
        var data;
        try {
            data = JSON.parse(/** @type {string} */ (scriptEl.textContent));
        } catch (e) {
            continue;
        }
        if (!data || !data.segments || data.segments.length === 0) continue;

        var state = {
            data: data,
            container: container,
            currentSeg: /** @type {Segment | null} */ (null),
            currentFrame: 0,
            animId: /** @type {number | null} */ (null),
            pauseSteps: data.steps.filter(function (s) {
                return s.pause;
            }),
        };
        animations[containerId] = state;

        // Show first frame
        showFrame(state, 0);

        // Fragment spans are emitted in the HTML at build time (not created dynamically),
        // so Reveal.js sees them during its initial scan. Nothing to create here.

        // Read autoplay setting from the container element
        state.autoPlay = container.getAttribute("data-illuminate-autoplay") === "true";
    }

    /**
     * @param {{animId: number | null}} state
     */
    function stopAnim(state) {
        if (state.animId !== null) {
            cancelAnimationFrame(state.animId);
            state.animId = null;
        }
    }

    /**
     * @param {{data: AnimData, container: HTMLElement, currentSeg: Segment | null, currentFrame: number, animId: number | null}} state
     * @param {number} loopStart
     * @param {number} loopEnd
     */
    function startLoop(state, loopStart, loopEnd) {
        var loopLen = loopEnd - loopStart;
        if (loopLen <= 0) return;
        /** @type {number | null} */
        var startTime = null;
        /** @param {number} timestamp */
        function tick(timestamp) {
            if (startTime === null) startTime = timestamp;
            var frame = animComputeFrame(startTime, timestamp, state.data.fps, loopStart);
            var loop = animWrapLoop(frame, loopStart, loopEnd);
            showFrame(state, loop.wrapped);
            state.animId = requestAnimationFrame(tick);
        }
        state.animId = requestAnimationFrame(tick);
    }

    /**
     * @param {{data: AnimData, container: HTMLElement, currentSeg: Segment | null, currentFrame: number, animId: number | null}} state
     * @param {number} targetFrame
     * @param {(() => void)} [onComplete]
     */
    function animateTo(state, targetFrame, onComplete) {
        stopAnim(state);
        var startFrame = state.currentFrame;
        /** @type {number | null} */
        var startTime = null;
        var dir = targetFrame > startFrame ? 1 : -1;
        /** @param {number} timestamp */
        function tick(timestamp) {
            if (startTime === null) startTime = timestamp;
            var frame = animComputeFrame(startTime, timestamp, state.data.fps, startFrame);
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
     * @param {{data: AnimData, container: HTMLElement, currentSeg: Segment | null, currentFrame: number, animId: number | null, pauseSteps: StepInfo[], autoPlay?: boolean}} st
     */
    function syncToFragmentState(st) {
        stopAnim(st);

        // Count how many of this animation's fragments are currently visible
        var parent = st.container.parentElement;
        if (!parent) return;
        var visibleCount = 0;
        var frags = parent.querySelectorAll(
            'span.fragment[data-illuminate-container="' + st.container.id + '"]',
        );
        for (var i = 0; i < frags.length; i++) {
            if (frags[i].classList.contains("visible")) visibleCount++;
        }

        if (visibleCount > 0) {
            // Backward navigation: fragments already shown — jump to end of that step sequence
            var idx = Math.min(visibleCount - 1, st.pauseSteps.length - 1);
            var ps = st.pauseSteps[idx];
            if (ps.loop) {
                var stepIdx = animFindCurrentStep(st.data.steps, ps.frame);
                var stepEnd = animFindStepEnd(st.data.steps, stepIdx, st.data.totalFrames);
                showFrame(st, ps.frame);
                startLoop(st, ps.frame, stepEnd);
            } else {
                showFrame(st, findTargetFrame(st, idx));
            }
        } else if (st.autoPlay) {
            // Forward navigation: auto-play up to (not through) the first pause step
            showFrame(st, 0);
            if (st.pauseSteps.length > 0) {
                animateTo(st, st.pauseSteps[0].frame);
            } else {
                animateTo(st, st.data.totalFrames - 1);
            }
        } else {
            // Forward navigation, no auto-play: show frame 0
            showFrame(st, 0);
        }
    }

    if (typeof Reveal !== "undefined") {
        // Sync animations when entering a slide (handles both forward and backward navigation)
        Reveal.on("slidechanged", function () {
            var slide = Reveal.getCurrentSlide();
            if (!slide) return;
            var containers = slide.querySelectorAll(".illuminate-anim");
            for (var ci = 0; ci < containers.length; ci++) {
                var st = animations[containers[ci].id];
                if (st) syncToFragmentState(st);
            }
        });

        // Also trigger on initial load for the first slide
        Reveal.on("ready", function () {
            var slide = Reveal.getCurrentSlide();
            if (!slide) return;
            var containers = slide.querySelectorAll(".illuminate-anim");
            for (var ci = 0; ci < containers.length; ci++) {
                var st = animations[containers[ci].id];
                if (st) syncToFragmentState(st);
            }
        });

        /**
         * Finds the frame to animate to when pause step `idx` is triggered.
         * Plays through the pause step and any subsequent non-pause steps,
         * stopping at the frame before the next pause step (or at the end).
         */
        function findTargetFrame(state, idx) {
            var nextPauseIdx = idx + 1;
            if (nextPauseIdx < state.pauseSteps.length) {
                // Stop just before the next pause step starts
                return Math.max(
                    state.pauseSteps[nextPauseIdx].frame - 1,
                    state.pauseSteps[idx].frame,
                );
            }
            // Last pause step: play to the end
            return state.data.totalFrames - 1;
        }

        // Helper: process a single animation fragment for fragmentshown
        function handleFragShown(frag) {
            var cid = frag.dataset.illuminateContainer;
            if (!cid) return;
            var state = animations[cid];
            if (!state) return;
            var idx = parseInt(frag.dataset.illuminateStepIndex || "", 10);
            if (isNaN(idx) || idx >= state.pauseSteps.length) return;
            stopAnim(state);
            var ps = state.pauseSteps[idx];
            if (ps.loop) {
                var stepIdx = animFindCurrentStep(state.data.steps, ps.frame);
                var stepEnd = animFindStepEnd(state.data.steps, stepIdx, state.data.totalFrames);
                // Looping step: animate to start, then loop
                animateTo(state, ps.frame, function () {
                    startLoop(state, ps.frame, stepEnd);
                });
            } else {
                // Animate through this step and any following non-pause steps
                var target = findTargetFrame(state, idx);
                animateTo(state, target, function () {
                    // If we landed in a loop step, start looping
                    var finalStepIdx = animFindCurrentStep(state.data.steps, target);
                    var finalStep = state.data.steps[finalStepIdx];
                    if (finalStep && finalStep.loop) {
                        var loopEnd = animFindStepEnd(
                            state.data.steps,
                            finalStepIdx,
                            state.data.totalFrames,
                        );
                        startLoop(state, finalStep.frame, loopEnd);
                    }
                });
            }
        }

        // Helper: process a single animation fragment for fragmenthidden
        function handleFragHidden(frag) {
            var cid = frag.dataset.illuminateContainer;
            if (!cid) return;
            var state = animations[cid];
            if (!state) return;
            var idx = parseInt(frag.dataset.illuminateStepIndex || "", 10);
            if (isNaN(idx)) return;
            stopAnim(state);
            var prevIdx = idx - 1;
            if (prevIdx >= 0) {
                var ps = state.pauseSteps[prevIdx];
                if (ps.loop) {
                    var stepIdx = animFindCurrentStep(state.data.steps, ps.frame);
                    var stepEnd = animFindStepEnd(
                        state.data.steps,
                        stepIdx,
                        state.data.totalFrames,
                    );
                    startLoop(state, ps.frame, stepEnd);
                } else {
                    var target = findTargetFrame(state, prevIdx);
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
        Reveal.on("fragmentshown", function (e) {
            var frags = e.fragments || [e.fragment];
            for (var fi = 0; fi < frags.length; fi++) {
                handleFragShown(frags[fi]);
            }
        });
        Reveal.on("fragmenthidden", function (e) {
            var frags = e.fragments || [e.fragment];
            for (var fi = 0; fi < frags.length; fi++) {
                handleFragHidden(frags[fi]);
            }
        });
    }
})();
