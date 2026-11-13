package com.dorocam.doro_camera

import android.media.MediaCodec
import android.media.MediaFormat
import android.media.MediaMuxer
import java.io.File
import java.io.IOException
import java.nio.ByteBuffer

/**
 * Writes encoded samples into one MP4 (video + AAC audio in the same container, ADR-0005). Timestamps are
 * rebased so the file starts at zero, and the file is written to a temp name and renamed when complete.
 */
object Mp4Writer {
    fun writeClip(
        target: File,
        clip: ClipAssembler.Clip,
        videoFormat: MediaFormat,
        audioFormat: MediaFormat?,
        orientationDegrees: Int,
    ) {
        val temp = AtomicFiles.tempFor(target)
        val muxer = try {
            MediaMuxer(temp.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        } catch (e: IOException) {
            throw AtomicFiles.ioToCamera(e)
        }
        try {
            muxer.setOrientationHint(orientationDegrees)
            val videoTrack = muxer.addTrack(videoFormat)
            val audioTrack = if (audioFormat != null && clip.hasAudio) muxer.addTrack(audioFormat) else -1
            muxer.start()
            val info = MediaCodec.BufferInfo()
            var lastVideo = -1L
            var lastAudio = -1L
            for (sample in clip.samples) {
                val track = if (sample.isVideo) videoTrack else audioTrack
                if (track < 0) continue
                // The muxer requires non-decreasing timestamps per track.
                val pts = (sample.ptsUs - clip.startUs).coerceAtLeast(0)
                val last = if (sample.isVideo) lastVideo else lastAudio
                val fixed = if (pts < last) last else pts
                if (sample.isVideo) lastVideo = fixed else lastAudio = fixed
                info.set(0, sample.data.size, fixed, if (sample.keyFrame && sample.isVideo) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0)
                muxer.writeSampleData(track, ByteBuffer.wrap(sample.data), info)
            }
            muxer.stop()
        } catch (e: Throwable) {
            temp.delete()
            throw CameraException("capture_failed", "Could not write the motion clip: ${e.message}", e)
        } finally {
            muxer.release()
        }
        try {
            AtomicFiles.commit(temp, target)
        } catch (e: IOException) {
            temp.delete()
            throw AtomicFiles.ioToCamera(e)
        }
    }
}

/** What a finished recording looks like. */
class RecordingSummary(val durationMs: Long, val width: Int, val height: Int, val hasAudio: Boolean, val bytes: Long)

/**
 * Streams samples of a running [EncoderPipeline] straight into an MP4 (video recording, VID-001).
 * The muxer needs the track formats up front, and the encoders only reveal them with their first output,
 * so early samples are queued until the formats exist (audio is given a short grace period, after which
 * the file is written without audio rather than never starting).
 */
class VideoFileRecorder(
    private val target: File,
    private val width: Int,
    private val height: Int,
    private val orientationDegrees: Int,
    private val expectsAudio: Boolean,
    private val formats: () -> Pair<MediaFormat?, MediaFormat?>,
    private val now: () -> Long = System::currentTimeMillis,
) {
    private val temp = AtomicFiles.tempFor(target)
    private val queue = ArrayDeque<EncodedSample>()
    private var muxer: MediaMuxer? = null
    private var videoTrack = -1
    private var audioTrack = -1
    private var firstUs = -1L
    private var lastUs = 0L
    private var startedAt = now()
    private var wroteAudio = false
    private val lastPts = longArrayOf(-1, -1)
    private val info = MediaCodec.BufferInfo()

    @Synchronized
    fun onSample(sample: EncodedSample) {
        if (muxer == null) {
            queue.addLast(sample)
            tryStart()
            return
        }
        write(sample)
    }

    private fun tryStart() {
        val (video, audio) = formats()
        if (video == null) return
        val waitedLongEnough = now() - startedAt > AUDIO_GRACE_MS
        if (expectsAudio && audio == null && !waitedLongEnough) return
        val m = MediaMuxer(temp.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        m.setOrientationHint(orientationDegrees)
        videoTrack = m.addTrack(video)
        if (audio != null) audioTrack = m.addTrack(audio)
        m.start()
        muxer = m
        while (queue.isNotEmpty()) write(queue.removeFirst())
    }

    private fun write(sample: EncodedSample) {
        val track = if (sample.isVideo) videoTrack else audioTrack
        if (track < 0) return
        // The first video frame defines time zero; earlier audio is dropped so audio never leads the picture.
        if (firstUs < 0) {
            if (!sample.isVideo) return
            firstUs = sample.ptsUs
        }
        if (!sample.isVideo && sample.ptsUs < firstUs) return
        val index = if (sample.isVideo) 0 else 1
        val pts = (sample.ptsUs - firstUs).coerceAtLeast(0).let { if (it < lastPts[index]) lastPts[index] else it }
        lastPts[index] = pts
        lastUs = maxOf(lastUs, pts)
        if (!sample.isVideo) wroteAudio = true
        info.set(0, sample.data.size, pts, if (sample.keyFrame && sample.isVideo) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0)
        muxer!!.writeSampleData(track, ByteBuffer.wrap(sample.data), info)
    }

    @Synchronized
    fun finish(): RecordingSummary {
        if (muxer == null) {
            // Never got a format: nothing was recorded.
            temp.delete()
            throw CameraException("capture_failed", "The recording produced no video")
        }
        try {
            muxer!!.stop()
        } catch (e: Throwable) {
            temp.delete()
            throw CameraException("capture_failed", "Could not finish the recording: ${e.message}", e)
        } finally {
            muxer!!.release()
            muxer = null
        }
        try {
            AtomicFiles.commit(temp, target)
        } catch (e: IOException) {
            temp.delete()
            throw AtomicFiles.ioToCamera(e)
        }
        return RecordingSummary(lastUs / 1000, width, height, wroteAudio, target.length())
    }

    @Synchronized
    fun abort() {
        try {
            muxer?.stop()
        } catch (_: Throwable) {
            // Nothing written yet.
        }
        muxer?.release()
        muxer = null
        temp.delete()
    }

    companion object {
        const val AUDIO_GRACE_MS = 1500L
    }
}
