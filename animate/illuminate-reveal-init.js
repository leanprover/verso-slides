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

        // Create hidden fragment spans for each pause step
        var parent = container.parentElement;
        if (parent) {
            for (var i = 0; i < state.pauseSteps.length; i++) {
                var frag = document.createElement("span");
                frag.className = "fragment";
                frag.style.display = "none";
                frag.dataset.illuminateContainer = containerId;
                frag.dataset.illuminateStepIndex = String(i);
                parent.appendChild(frag);
            }
        }

        // If the first step is not a pause, auto-play to the first pause step
        // (or to the end) when the slide becomes visible.
        if (data.steps.length > 0 && !data.steps[0].pause) {
            state.autoPlay = true;
        }
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
            var frame = animComputeFrame(
                startTime,
                timestamp,
                state.data.fps,
                loopStart,
            );
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
            var frame = animComputeFrame(
                startTime,
                timestamp,
                state.data.fps,
                startFrame,
            );
            if (dir < 0) {
                frame = startFrame - (frame - startFrame);
            }
            if (
                (dir > 0 && frame >= targetFrame) ||
                (dir < 0 && frame <= targetFrame)
            ) {
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
            // Backward navigation: fragments already shown — jump to that state
            var idx = Math.min(visibleCount - 1, st.pauseSteps.length - 1);
            var ps = st.pauseSteps[idx];
            showFrame(st, ps.frame);
            if (ps.loop) {
                var stepIdx = animFindCurrentStep(st.data.steps, ps.frame);
                startLoop(
                    st,
                    ps.frame,
                    animFindStepEnd(st.data.steps, stepIdx, st.data.totalFrames),
                );
            }
        } else if (st.autoPlay) {
            // Forward navigation: auto-play to first pause step
            showFrame(st, 0);
            var target =
                st.pauseSteps.length > 0
                    ? st.pauseSteps[0].frame
                    : st.data.totalFrames - 1;
            animateTo(st, target);
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

        Reveal.on("fragmentshown", function (/** @type {{fragment: HTMLElement}} */ e) {
            var cid = e.fragment.dataset.illuminateContainer;
            if (!cid) return;
            var state = animations[cid];
            if (!state) return;
            var idx = parseInt(
                e.fragment.dataset.illuminateStepIndex || "",
                10,
            );
            if (isNaN(idx) || idx >= state.pauseSteps.length) return;
            stopAnim(state);
            var ps = state.pauseSteps[idx];
            var stepIdx = animFindCurrentStep(state.data.steps, ps.frame);
            animateTo(state, ps.frame, function () {
                if (ps.loop) {
                    startLoop(
                        state,
                        ps.frame,
                        animFindStepEnd(
                            state.data.steps,
                            stepIdx,
                            state.data.totalFrames,
                        ),
                    );
                }
            });
        });
        Reveal.on("fragmenthidden", function (/** @type {{fragment: HTMLElement}} */ e) {
            var cid = e.fragment.dataset.illuminateContainer;
            if (!cid) return;
            var state = animations[cid];
            if (!state) return;
            var idx = parseInt(
                e.fragment.dataset.illuminateStepIndex || "",
                10,
            );
            if (isNaN(idx)) return;
            stopAnim(state);
            var prevIdx = idx - 1;
            if (prevIdx >= 0 && state.pauseSteps[prevIdx].loop) {
                var ps = state.pauseSteps[prevIdx];
                var stepIdx = animFindCurrentStep(
                    state.data.steps,
                    ps.frame,
                );
                startLoop(
                    state,
                    ps.frame,
                    animFindStepEnd(
                        state.data.steps,
                        stepIdx,
                        state.data.totalFrames,
                    ),
                );
            } else {
                var prevFrame =
                    prevIdx >= 0 ? state.pauseSteps[prevIdx].frame : 0;
                animateTo(state, prevFrame);
            }
        });
    }
})();
