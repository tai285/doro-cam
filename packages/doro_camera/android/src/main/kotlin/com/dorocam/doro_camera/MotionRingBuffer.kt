package com.dorocam.doro_camera

/** One encoded sample of the motion pipeline (video frame or AAC access unit), timestamped on a single clock. */
class EncodedSample(
    val isVideo: Boolean,
    val ptsUs: Long,
    val keyFrame: Boolean,
    val data: ByteArray,
)

/** The clip content chosen by [MotionRingBuffer.snapshot]. */
class MotionSnapshot(
    val video: List<EncodedSample>,
    val audio: List<EncodedSample>,
    /** Presentation time of the first video sample (a key frame). */
    val startUs: Long,
    /** Actual pre-roll delivered: shutter minus [startUs]. At least what was asked unless the buffer was shorter. */
    val preRollUs: Long,
)

/**
 * Rolling window of encoded samples for LIVE capture (ADR-0005, MOT-002, MOT-009).
 *
 * Samples are already encoded, so holding three seconds costs memory in kilobytes per frame, not
 * decoded frames. The window always begins on a video key frame (a clip cannot start mid-GOP), so it
 * keeps the newest key frame at or before `newest - window` and drops everything older.
 *
 * Not thread safe on its own: the pipeline serialises access (one drain thread, one snapshot caller
 * guarded by [lock]).
 */
class MotionRingBuffer(private val windowUs: Long) {
    private val video = ArrayDeque<EncodedSample>()
    private val audio = ArrayDeque<EncodedSample>()
    private val lock = Any()

    val videoCount: Int get() = synchronized(lock) { video.size }
    val audioCount: Int get() = synchronized(lock) { audio.size }
    val bytes: Long get() = synchronized(lock) { video.sumOf { it.data.size.toLong() } + audio.sumOf { it.data.size.toLong() } }

    fun append(sample: EncodedSample) = synchronized(lock) {
        (if (sample.isVideo) video else audio).addLast(sample)
        trim(sample.ptsUs)
    }

    fun clear() = synchronized(lock) {
        video.clear()
        audio.clear()
    }

    private fun trim(newestUs: Long) {
        val cutoff = newestUs - windowUs
        // Keep the newest key frame at or before the cutoff so the window can start on it.
        var keep = -1
        for (i in video.indices) {
            val sample = video[i]
            if (sample.ptsUs > cutoff) break
            if (sample.keyFrame) keep = i
        }
        if (keep > 0) {
            repeat(keep) { video.removeFirst() }
        }
        val startUs = video.firstOrNull()?.ptsUs ?: cutoff
        while (audio.isNotEmpty() && audio.first().ptsUs < startUs) audio.removeFirst()
    }

    /**
     * The samples needed for a clip whose shutter is at [shutterUs] and which wants [preRollUs] before it:
     * video from the newest key frame at or before `shutter - preRoll`, plus the audio from the same start.
     * Returns null when the buffer holds no key frame yet.
     */
    fun snapshot(shutterUs: Long, preRollUs: Long): MotionSnapshot? = synchronized(lock) {
        val wanted = shutterUs - preRollUs
        var startIndex = -1
        for (i in video.indices) {
            val sample = video[i]
            if (!sample.keyFrame) continue
            if (startIndex == -1 || sample.ptsUs <= wanted) startIndex = i
            if (sample.ptsUs > wanted) break
        }
        if (startIndex == -1) return null
        val videoOut = video.subList(startIndex, video.size).filter { it.ptsUs <= shutterUs }
        if (videoOut.isEmpty()) return null
        val startUs = videoOut.first().ptsUs
        val audioOut = audio.filter { it.ptsUs >= startUs && it.ptsUs <= shutterUs }
        MotionSnapshot(videoOut, audioOut, startUs, (shutterUs - startUs).coerceAtLeast(0))
    }
}

/**
 * Collects the post-shutter samples and combines them with a snapshot into the final ordered list for the
 * muxer. Pure, so the interleaving and the clip timing are unit tested without a codec.
 */
object ClipAssembler {
    class Clip(
        val samples: List<EncodedSample>,
        val startUs: Long,
        val durationUs: Long,
        val shutterOffsetUs: Long,
        val hasAudio: Boolean,
    )

    /** Samples sorted by time with rebased timestamps starting at 0, plus the clip facts. */
    fun assemble(snapshot: MotionSnapshot, post: List<EncodedSample>, shutterUs: Long): Clip {
        val all = (snapshot.video + snapshot.audio + post).sortedWith(compareBy<EncodedSample> { it.ptsUs }.thenBy { !it.isVideo })
        val start = snapshot.startUs
        val end = all.maxOf { it.ptsUs }
        return Clip(
            samples = all,
            startUs = start,
            durationUs = end - start,
            shutterOffsetUs = (shutterUs - start).coerceAtLeast(0),
            hasAudio = all.any { !it.isVideo },
        )
    }
}
