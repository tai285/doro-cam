package com.dorocam.doro_camera

import java.io.File
import kotlinx.coroutines.delay

/**
 * Maps camera frame timestamps onto the shared boot clock used by audio. Cameras whose timestamp source is
 * REALTIME already use that clock (offset 0). For UNKNOWN sources the offset is learned from capture results:
 * the smallest `now - frameTime` seen is the closest to the true offset (it has the least delivery latency).
 */
class ClockAligner(private val realtimeSource: Boolean, private val nowUs: () -> Long) {
    @Volatile private var offsetUs: Long = 0
    @Volatile private var calibrated: Boolean = realtimeSource

    fun observeFrame(sensorTimestampNs: Long) {
        if (realtimeSource) return
        val candidate = nowUs() - sensorTimestampNs / 1000
        if (!calibrated || candidate < offsetUs) {
            offsetUs = candidate
            calibrated = true
        }
    }

    fun toSharedUs(sensorUs: Long): Long = sensorUs + offsetUs
}

/**
 * LIVE: keeps the encoder pipeline running while LIVE is on, holds the last few seconds as encoded samples and,
 * on a shutter, produces one MP4 with the pre-roll, the post-roll and the audio (ADR-0005, MOT-002, MOT-009).
 * The same coordinator serves the Camera2 session and the synthetic camera: only the pipeline differs.
 */
class MotionCoordinator(
    private val windowMs: Long = CapabilityProbe.LIVE_MAX_PRE_BUFFER_MS,
    private val nowUs: () -> Long,
) {
    private val ring = MotionRingBuffer(windowMs * 1000)
    private var pipeline: EncoderPipeline? = null
    private val collectLock = Any()
    private var postSamples: MutableList<EncodedSample>? = null
    private var postAfterUs = 0L

    @Volatile var newestVideoUs: Long = 0
        private set

    val active: Boolean get() = pipeline != null
    val inputSurface: android.view.Surface? get() = pipeline?.inputSurface
    val width: Int get() = pipeline?.width ?: 0
    val height: Int get() = pipeline?.height ?: 0
    val hasAudio: Boolean get() = pipeline?.audioFormat != null
    val bufferedBytes: Long get() = ring.bytes

    fun sink(sample: EncodedSample) {
        if (sample.isVideo) newestVideoUs = maxOf(newestVideoUs, sample.ptsUs)
        ring.append(sample)
        synchronized(collectLock) {
            if (sample.ptsUs > postAfterUs) postSamples?.add(sample)
        }
    }

    fun attach(started: EncoderPipeline) {
        pipeline = started
    }

    /** Stops buffering and drops what was held (NFR-012: nothing runs while LIVE is off or the camera is idle). */
    fun stop() {
        pipeline?.stop()
        pipeline = null
        ring.clear()
        newestVideoUs = 0
    }

    /**
     * Builds the clip around [shutterUs]. [preRollMs] is a minimum wish; the clip starts on the key frame at or
     * before it. Waits for the post-roll, then writes the MP4 atomically to [target].
     */
    suspend fun captureClip(shutterUs: Long, preRollMs: Long, postRollMs: Long, target: File, orientationDegrees: Int): MotionResultMessage {
        val running = pipeline ?: throw CameraException("capture_failed", "LIVE is not running")
        synchronized(collectLock) {
            postAfterUs = shutterUs
            postSamples = mutableListOf()
        }
        val snapshot = ring.snapshot(shutterUs, preRollMs.coerceAtMost(windowMs) * 1000)
        if (snapshot == null) {
            synchronized(collectLock) { postSamples = null }
            throw CameraException("capture_failed", "No video was buffered yet")
        }
        // Wait until the encoder has delivered video up to the end of the post-roll, with a safety timeout.
        val endUs = shutterUs + postRollMs * 1000
        val deadline = nowUs() + (postRollMs + 2000) * 1000
        while (newestVideoUs < endUs && nowUs() < deadline) delay(20)
        val post = synchronized(collectLock) {
            val list = postSamples.orEmpty().filter { it.ptsUs <= endUs }
            postSamples = null
            list
        }
        val videoFormat = running.videoFormat ?: throw CameraException("capture_failed", "The video encoder produced no format")
        val clip = ClipAssembler.assemble(snapshot, post, shutterUs)
        Mp4Writer.writeClip(target, clip, videoFormat, running.audioFormat, orientationDegrees)
        val shutterOffsetMs = clip.shutterOffsetUs / 1000
        val total = clip.durationUs / 1000
        return MotionResultMessage(
            path = target.path,
            durationMs = total,
            preRollMs = shutterOffsetMs,
            postRollMs = (total - shutterOffsetMs).coerceAtLeast(0),
            keyFrameTimeMs = shutterOffsetMs,
            hasAudio = clip.hasAudio,
            width = running.width.toLong(),
            height = running.height.toLong(),
            orientationDegrees = orientationDegrees.toLong(),
            mime = "video/mp4",
        )
    }
}
