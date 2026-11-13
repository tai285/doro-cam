package com.dorocam.doro_camera

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.AudioTimestamp
import android.media.MediaCodec
import android.media.MediaFormat
import android.media.MediaRecorder
import android.os.SystemClock
import android.view.Surface
import java.nio.ByteBuffer

/** Source of 16-bit PCM audio with timestamps on the pipeline's shared clock. */
interface AudioPcmSource {
    val sampleRate: Int
    val channelCount: Int
    fun start()

    /** Blocks until PCM is available and copies up to `buffer.size` bytes; returns the count, or -1 when finished. */
    fun read(buffer: ByteArray): Int

    /** Timestamp (µs, shared clock) of the first byte returned by the last [read]. */
    val lastChunkPtsUs: Long
    fun stop()
}

/** Microphone input. Timestamps come from `AudioRecord.getTimestamp` on the boot clock, the camera's clock. */
class MicrophoneSource(override val sampleRate: Int = 44_100) : AudioPcmSource {
    override val channelCount: Int = 1
    private var record: AudioRecord? = null
    private var framesRead = 0L
    private var baseUs = 0L
    override var lastChunkPtsUs: Long = 0
        private set

    @Suppress("MissingPermission") // The caller only creates a MicrophoneSource after RECORD_AUDIO is granted.
    override fun start() {
        val min = AudioRecord.getMinBufferSize(sampleRate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val buffer = (min * 4).coerceAtLeast(sampleRate / 5 * 2)
        val r = AudioRecord(MediaRecorder.AudioSource.MIC, sampleRate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, buffer)
        if (r.state != AudioRecord.STATE_INITIALIZED) {
            r.release()
            throw CameraException("capture_failed", "The microphone could not be opened")
        }
        record = r
        framesRead = 0
        baseUs = -1
        r.startRecording()
    }

    override fun read(buffer: ByteArray): Int {
        val r = record ?: return -1
        val n = r.read(buffer, 0, buffer.size)
        if (n <= 0) return n
        val frames = n / 2L
        val timestamp = AudioTimestamp()
        val chunkStartFrame = framesRead
        framesRead += frames
        val ok = r.getTimestamp(timestamp, AudioTimestamp.TIMEBASE_BOOTTIME) == AudioRecord.SUCCESS
        lastChunkPtsUs = if (ok) {
            (timestamp.nanoTime / 1000) + (chunkStartFrame - timestamp.framePosition) * 1_000_000L / sampleRate
        } else {
            // No hardware timestamp yet: assume the chunk just finished being captured.
            SystemClock.elapsedRealtimeNanos() / 1000 - frames * 1_000_000L / sampleRate
        }
        return n
    }

    override fun stop() {
        record?.let {
            try {
                it.stop()
            } catch (_: IllegalStateException) {
                // Already stopped.
            }
            it.release()
        }
        record = null
    }
}

/**
 * H.264 video (from an input [Surface]) plus optional AAC audio, both timestamped on one clock and delivered
 * as [EncodedSample]s. One pipeline feeds either the LIVE ring buffer or a recording (ADR-0005); the audio
 * lives in the same container as the video so A/V sync is the muxer's job, not ours.
 *
 * Video timestamps are whatever the producer stamps on its frames; [toSharedClockUs] maps them onto the
 * clock the audio uses (identity when the camera timestamps are already on the boot clock).
 */
class EncoderPipeline(
    val width: Int,
    val height: Int,
    private val fps: Int,
    private val videoBitrate: Int,
    private val audio: AudioPcmSource?,
    private val toSharedClockUs: (Long) -> Long,
    private val onSample: (EncodedSample) -> Unit,
) {
    @Volatile var videoFormat: MediaFormat? = null
        private set
    @Volatile var audioFormat: MediaFormat? = null
        private set

    lateinit var inputSurface: Surface
        private set

    @Volatile private var running = false
    private var video: MediaCodec? = null
    private var audioCodec: MediaCodec? = null
    private var videoThread: Thread? = null
    private var audioThread: Thread? = null
    @Volatile var failure: Throwable? = null
        private set

    fun start() {
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, android.media.MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE, videoBitrate)
            setInteger(MediaFormat.KEY_FRAME_RATE, fps)
            // One key frame per second: the LIVE pre-roll can start at most a second early.
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        }
        val v = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
        v.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        inputSurface = v.createInputSurface()
        v.start()
        video = v
        running = true
        videoThread = Thread({ drainVideo(v) }, "doro-video-enc").also { it.start() }

        if (audio != null) {
            val a = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
            val aFormat = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, audio.sampleRate, audio.channelCount).apply {
                setInteger(MediaFormat.KEY_AAC_PROFILE, android.media.MediaCodecInfo.CodecProfileLevel.AACObjectLC)
                setInteger(MediaFormat.KEY_BIT_RATE, 64_000)
                setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16_384)
            }
            a.configure(aFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            a.start()
            audioCodec = a
            audio.start()
            audioThread = Thread({ runAudio(a, audio) }, "doro-audio-enc").also { it.start() }
        }
    }

    private fun drainVideo(codec: MediaCodec) {
        val info = MediaCodec.BufferInfo()
        try {
            while (true) {
                val index = codec.dequeueOutputBuffer(info, 20_000)
                when {
                    index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> videoFormat = codec.outputFormat
                    index >= 0 -> {
                        val buffer = codec.getOutputBuffer(index)
                        if (buffer != null && info.size > 0 && (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0) {
                            val bytes = ByteArray(info.size)
                            buffer.position(info.offset)
                            buffer.limit(info.offset + info.size)
                            buffer.get(bytes)
                            onSample(
                                EncodedSample(
                                    isVideo = true,
                                    ptsUs = toSharedClockUs(info.presentationTimeUs),
                                    keyFrame = (info.flags and MediaCodec.BUFFER_FLAG_KEY_FRAME) != 0,
                                    data = bytes,
                                ),
                            )
                        }
                        codec.releaseOutputBuffer(index, false)
                        if ((info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) return
                    }
                    index == MediaCodec.INFO_TRY_AGAIN_LATER && !running -> return
                }
            }
        } catch (e: Throwable) {
            if (running) failure = e
        }
    }

    private fun runAudio(codec: MediaCodec, source: AudioPcmSource) {
        val info = MediaCodec.BufferInfo()
        val pcm = ByteArray(4096)
        try {
            while (running) {
                val n = source.read(pcm)
                if (n < 0) break
                if (n > 0) {
                    val ptsUs = source.lastChunkPtsUs
                    var offset = 0
                    while (offset < n) {
                        val index = codec.dequeueInputBuffer(10_000)
                        if (index < 0) {
                            drainAudio(codec, info)
                            if (!running) break
                            continue
                        }
                        val input: ByteBuffer = codec.getInputBuffer(index)!!
                        input.clear()
                        val chunk = minOf(input.remaining(), n - offset)
                        input.put(pcm, offset, chunk)
                        val chunkPts = ptsUs + offset / 2L * 1_000_000L / source.sampleRate
                        codec.queueInputBuffer(index, 0, chunk, chunkPts, 0)
                        offset += chunk
                    }
                }
                drainAudio(codec, info)
            }
            // End of stream: let the encoder flush what it still holds.
            val index = codec.dequeueInputBuffer(50_000)
            if (index >= 0) codec.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
            var done = false
            var spins = 0
            while (!done && spins++ < 50) done = drainAudio(codec, info)
        } catch (e: Throwable) {
            if (running) failure = e
        }
    }

    /** Returns true once the end-of-stream buffer has been seen. */
    private fun drainAudio(codec: MediaCodec, info: MediaCodec.BufferInfo): Boolean {
        while (true) {
            val index = codec.dequeueOutputBuffer(info, 0)
            when {
                index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> audioFormat = codec.outputFormat
                index >= 0 -> {
                    val buffer = codec.getOutputBuffer(index)
                    if (buffer != null && info.size > 0 && (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0) {
                        val bytes = ByteArray(info.size)
                        buffer.position(info.offset)
                        buffer.limit(info.offset + info.size)
                        buffer.get(bytes)
                        onSample(EncodedSample(isVideo = false, ptsUs = info.presentationTimeUs, keyFrame = true, data = bytes))
                    }
                    codec.releaseOutputBuffer(index, false)
                    if ((info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) return true
                }
                else -> return false
            }
        }
    }

    fun stop() {
        running = false
        try {
            video?.signalEndOfInputStream()
        } catch (_: Throwable) {
            // The codec may already be stopped.
        }
        audio?.stop()
        videoThread?.join(2000)
        audioThread?.join(2000)
        for (codec in listOfNotNull(video, audioCodec)) {
            try {
                codec.stop()
            } catch (_: Throwable) {
                // Already stopped.
            }
            codec.release()
        }
        video = null
        audioCodec = null
        if (::inputSurface.isInitialized) inputSurface.release()
    }
}
