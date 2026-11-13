package com.dorocam.doro_camera

import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.SurfaceTexture
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLSurface
import android.opengl.GLES20
import android.os.Handler
import android.os.HandlerThread
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.abs
import kotlin.math.sqrt

/**
 * A preview texture with a real GL consumer, like Flutter's texture registry: frames are consumed with
 * `updateTexImage`, so the camera never stalls and tests can count delivered preview frames.
 */
class GlPreviewTexture(override val textureId: Long = 1) : PreviewTexture {
    private val thread = HandlerThread("test-gl").also { it.start() }
    private val handler = Handler(thread.looper)
    val frames = AtomicInteger(0)
    private var display: EGLDisplay = EGL14.EGL_NO_DISPLAY
    private var eglContext: EGLContext = EGL14.EGL_NO_CONTEXT
    private var eglSurface: EGLSurface = EGL14.EGL_NO_SURFACE
    override lateinit var surfaceTexture: SurfaceTexture
        private set

    init {
        val ready = CountDownLatch(1)
        handler.post {
            display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
            val version = IntArray(2)
            EGL14.eglInitialize(display, version, 0, version, 1)
            val attribs = intArrayOf(EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT, EGL14.EGL_SURFACE_TYPE, EGL14.EGL_PBUFFER_BIT, EGL14.EGL_NONE)
            val configs = arrayOfNulls<EGLConfig>(1)
            val count = IntArray(1)
            EGL14.eglChooseConfig(display, attribs, 0, configs, 0, 1, count, 0)
            eglContext = EGL14.eglCreateContext(display, configs[0], EGL14.EGL_NO_CONTEXT, intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE), 0)
            eglSurface = EGL14.eglCreatePbufferSurface(display, configs[0], intArrayOf(EGL14.EGL_WIDTH, 16, EGL14.EGL_HEIGHT, 16, EGL14.EGL_NONE), 0)
            EGL14.eglMakeCurrent(display, eglSurface, eglSurface, eglContext)
            val tex = IntArray(1)
            GLES20.glGenTextures(1, tex, 0)
            surfaceTexture = SurfaceTexture(tex[0])
            surfaceTexture.setOnFrameAvailableListener({ st ->
                try {
                    st.updateTexImage()
                    frames.incrementAndGet()
                } catch (_: Exception) {
                    // Released while a frame was in flight.
                }
            }, handler)
            ready.countDown()
        }
        check(ready.await(10, TimeUnit.SECONDS)) { "GL consumer did not start" }
    }

    fun waitForFrames(count: Int, timeoutMs: Long = 8000): Boolean {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (frames.get() < count && System.currentTimeMillis() < deadline) Thread.sleep(50)
        return frames.get() >= count
    }

    override fun release() {
        handler.post {
            surfaceTexture.release()
            EGL14.eglMakeCurrent(display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
            EGL14.eglDestroySurface(display, eglSurface)
            EGL14.eglDestroyContext(display, eglContext)
            EGL14.eglTerminate(display)
            thread.quitSafely()
        }
    }
}

/** Fixed orientation source for deterministic tests. */
class FixedOrientation(override var degrees: Int = 0) : OrientationSource {
    override fun addListener(listener: (Int) -> Unit) = Unit
    override fun removeListener(listener: (Int) -> Unit) = Unit
}

class FixedThermal(override var state: ThermalStateMessage = ThermalStateMessage.NOMINAL) : ThermalSource {
    val listeners = mutableListOf<(ThermalStateMessage) -> Unit>()
    override fun addListener(listener: (ThermalStateMessage) -> Unit) { listeners += listener }
    override fun removeListener(listener: (ThermalStateMessage) -> Unit) { listeners -= listener }
    fun set(next: ThermalStateMessage) {
        state = next
        listeners.toList().forEach { it(next) }
    }
}

/** A service wired like the app, on the real camera HAL and the synthetic camera, with a recording event sink. */
class Rig(
    val context: Context = InstrumentationRegistry.getInstrumentation().targetContext,
    val orientation: FixedOrientation = FixedOrientation(),
    val thermal: FixedThermal = FixedThermal(),
) {
    val events = java.util.concurrent.CopyOnWriteArrayList<SessionEventMessage>()
    val textures = mutableListOf<GlPreviewTexture>()
    val camera2 = Camera2Backend.create(context, orientation, thermal)
    val service = CameraService(
        listOfNotNull(camera2, SyntheticCameraBuild.createBackend(context, orientation)),
        { GlPreviewTexture(textures.size + 1L).also { textures += it } },
        { PermissionsMessage(PermissionStatusMessage.GRANTED, PermissionStatusMessage.GRANTED, false, false) },
        { events += it },
    )
    val outDir: File = File(context.cacheDir, "rig-${System.nanoTime()}").also { it.mkdirs() }

    fun hardwareCameras() = service.listCameras().filter { it.source == CameraSourceMessage.HARDWARE }
    fun syntheticCameras() = service.listCameras().filter { it.source == CameraSourceMessage.SYNTHETIC }

    fun request(name: String, live: Boolean = false, aspect: String? = null) = CaptureRequestMessage(
        memoryId = name,
        outputDir = outDir.path,
        originalName = "$name-original.jpg",
        renderedName = "$name-rendered.jpg",
        thumbnailName = "$name-thumb.jpg",
        displayName = "$name-display.jpg",
        motionName = "$name-motion.mp4",
        live = live,
        preRollMs = 1500,
        postRollMs = 1500,
        jpegQuality = 92,
        render = RenderSpecMessage(grain = 0.0, vignette = 0.0, aspectRatio = aspect),
    )

    fun cleanup() {
        outDir.deleteRecursively()
    }
}

/** Mean luma (0..255) of an image file, sampled on a grid. */
fun meanLuma(path: String): Double {
    val bitmap = BitmapFactory.decodeFile(path) ?: error("cannot decode $path")
    var sum = 0.0
    var n = 0
    val stepX = (bitmap.width / 32).coerceAtLeast(1)
    val stepY = (bitmap.height / 32).coerceAtLeast(1)
    var y = 0
    while (y < bitmap.height) {
        var x = 0
        while (x < bitmap.width) {
            val p = bitmap.getPixel(x, y)
            sum += 0.299 * ((p shr 16) and 0xFF) + 0.587 * ((p shr 8) and 0xFF) + 0.114 * (p and 0xFF)
            n++
            x += stepX
        }
        y += stepY
    }
    bitmap.recycle()
    return sum / n
}

/** Facts read back from a finished MP4, with video flashes and audio beeps located in time. */
class ClipFacts(
    val durationMs: Long,
    val width: Int,
    val height: Int,
    val hasVideoTrack: Boolean,
    val hasAudioTrack: Boolean,
    val firstVideoPtsUs: Long,
    val firstAudioPtsUs: Long,
)

object ClipInspector {
    fun facts(path: String): ClipFacts {
        val retriever = MediaMetadataRetriever()
        retriever.setDataSource(path)
        val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)!!.toLong()
        val w = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toInt() ?: 0
        val h = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toInt() ?: 0
        retriever.release()
        val extractor = MediaExtractor()
        extractor.setDataSource(path)
        var video = false
        var audio = false
        var firstVideo = -1L
        var firstAudio = -1L
        for (i in 0 until extractor.trackCount) {
            val mime = extractor.getTrackFormat(i).getString(MediaFormat.KEY_MIME).orEmpty()
            extractor.selectTrack(i)
            extractor.seekTo(0, MediaExtractor.SEEK_TO_CLOSEST_SYNC)
            val pts = extractor.sampleTime
            if (mime.startsWith("video/")) { video = true; firstVideo = pts }
            if (mime.startsWith("audio/")) { audio = true; firstAudio = pts }
            extractor.unselectTrack(i)
        }
        extractor.release()
        return ClipFacts(duration, w, h, video, audio, firstVideo, firstAudio)
    }

    /** Times (ms from clip start) where the picture jumps to the bright flash frame. */
    fun flashOnsetsMs(path: String, durationMs: Long): List<Long> {
        val retriever = MediaMetadataRetriever()
        retriever.setDataSource(path)
        val onsets = mutableListOf<Long>()
        // A flash already on at the first frame began before the clip: it is not an onset we can time.
        var previousBright = true
        var t = 0L
        while (t < durationMs) {
            val frame = retriever.getScaledFrameAtTime(t * 1000, MediaMetadataRetriever.OPTION_CLOSEST, 32, 24)
            if (frame != null) {
                val p = frame.getPixel(16, 4) // top strip: untouched by the moving bar and caption
                val luma = 0.299 * ((p shr 16) and 0xFF) + 0.587 * ((p shr 8) and 0xFF) + 0.114 * (p and 0xFF)
                val bright = luma > 200
                if (bright && !previousBright) onsets += t
                previousBright = bright
                frame.recycle()
            }
            t += 16
        }
        retriever.release()
        return onsets
    }

    /** Times (ms from clip start) where the audio goes from silence to the beep. */
    fun beepOnsetsMs(path: String): List<Long> {
        val extractor = MediaExtractor()
        extractor.setDataSource(path)
        val track = (0 until extractor.trackCount).first { extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)!!.startsWith("audio/") }
        val format = extractor.getTrackFormat(track)
        extractor.selectTrack(track)
        val rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        val channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        val decoder = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
        decoder.configure(format, null, null, 0)
        decoder.start()
        val info = MediaCodec.BufferInfo()
        val onsets = mutableListOf<Long>()
        var inputDone = false
        var outputDone = false
        var previousLoud = true
        while (!outputDone) {
            if (!inputDone) {
                val index = decoder.dequeueInputBuffer(10_000)
                if (index >= 0) {
                    val buffer = decoder.getInputBuffer(index)!!
                    val size = extractor.readSampleData(buffer, 0)
                    if (size < 0) {
                        decoder.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        inputDone = true
                    } else {
                        decoder.queueInputBuffer(index, 0, size, extractor.sampleTime, 0)
                        extractor.advance()
                    }
                }
            }
            val out = decoder.dequeueOutputBuffer(info, 10_000)
            if (out >= 0) {
                val buffer = decoder.getOutputBuffer(out)!!
                val shorts = buffer.asShortBuffer()
                val frames = shorts.remaining() / channels
                // 10 ms windows
                val window = (rate / 100).coerceAtLeast(1)
                var i = 0
                while (i + window <= frames) {
                    var sumSq = 0.0
                    for (k in 0 until window) {
                        val v = shorts.get((i + k) * channels).toDouble()
                        sumSq += v * v
                    }
                    val rms = sqrt(sumSq / window)
                    val loud = rms > 2500
                    val tMs = (info.presentationTimeUs + i * 1_000_000L / rate) / 1000
                    if (loud && !previousLoud) onsets += tMs
                    previousLoud = loud
                    i += window
                }
                decoder.releaseOutputBuffer(out, false)
                if ((info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) outputDone = true
            }
        }
        decoder.stop()
        decoder.release()
        extractor.release()
        return onsets
    }
}

/** True when two times agree within [toleranceMs]. */
fun near(a: Long, b: Long, toleranceMs: Long) = abs(a - b) <= toleranceMs
