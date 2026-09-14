package dev.sparkison.tv

import androidx.media3.common.C

/**
 * Decision logic for the video-stall watchdog (issue #291).
 *
 * Some devices stall the MediaCodec video output path while the underlying player keeps its
 * clock running and audio keeps draining its already-decoded buffer -- the player never leaves
 * `STATE_BUFFERING`/`STATE_READY` because nothing about audio playback or the reported position
 * looks wrong, so nothing else in the stack (the buffering timer in `PlaybackOrchestrator`, the
 * hard-error handling in `decoder_failure.dart`) ever notices. The user sees a frozen frame with
 * audio continuing normally.
 *
 * This watchdog snapshots the rendered-video-frame counter whenever playback (re)starts and
 * compares it one check window later: if the playback position advanced but no new frame was
 * rendered, the video renderer is stalled with a live clock, and a small backward seek (which
 * forces a codec flush, unlike a same-position seek that ExoPlayer short-circuits) is enough to
 * get it moving again.
 */
internal object ResumeStallPolicy {
    /** Floor for the check window; frame-interval scaling only ever raises it. */
    const val DEFAULT_CHECK_WINDOW_MS = 1000L

    /** Frames that must have been due within the window before calling it a stall. */
    const val MIN_FRAME_INTERVALS = 4

    /** Assumed fps when the current video format does not report one. */
    const val FALLBACK_FPS = 24f

    /** Recovery seek delta. Must be nonzero or ExoPlayer short-circuits the seek. */
    const val SEEK_BACK_MS = 250L

    /** Re-checks allowed while the clock itself is not advancing (generic stall, not this bug). */
    const val MAX_RECHECKS = 2

    /** Recovery cap per player instance; a pathological stream stops arming after this. */
    const val MAX_RECOVERIES_PER_SESSION = 5

    enum class Verdict { HEALTHY, RECHECK, SKIP_NEAR_EOF, STALLED }

    /** Window sized so even low-fps or slowed-down content has had several frames due. */
    fun checkWindowMs(formatFps: Float?, speed: Float): Long {
        val fps = formatFps?.takeIf { it > 1f } ?: FALLBACK_FPS
        val frameIntervalMs = (1000f / fps / speed.coerceAtLeast(0.25f)).toLong()
        return maxOf(DEFAULT_CHECK_WINDOW_MS, MIN_FRAME_INTERVALS * frameIntervalMs)
    }

    fun evaluate(
        baselineFrames: Int,
        currentFrames: Int,
        baselinePositionMs: Long,
        currentPositionMs: Long,
        durationMs: Long,
        windowMs: Long,
    ): Verdict = when {
        // Any counter movement counts as healthy, including a renderer re-enable
        // resetting DecoderCounters below the baseline.
        currentFrames != baselineFrames -> Verdict.HEALTHY
        currentPositionMs - baselinePositionMs < windowMs / 2 -> Verdict.RECHECK
        durationMs != C.TIME_UNSET && durationMs - currentPositionMs < 2 * windowMs -> Verdict.SKIP_NEAR_EOF
        else -> Verdict.STALLED
    }
}
