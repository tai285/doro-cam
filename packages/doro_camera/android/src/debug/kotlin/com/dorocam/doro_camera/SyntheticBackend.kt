package com.dorocam.doro_camera

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.os.Handler
import android.os.HandlerThread
import android.view.Surface
import java.io.ByteArrayOutputStream
import java.io.File
import kotlin.math.pow
import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** Debug-only switches for tests. */
object SyntheticControl {
    /** When true the camera ignores manual requests and reports auto values (for the mismatch-downgrade test). */
    @Volatile var ignoreManualRequests = false
}

/** Monotonic microsecond clock shared by synthetic video, audio and flashes. */
internal fun syntheticNowUs(): Long = System.nanoTime() / 1000

/** Test tone: silence with a 100 ms, 1 kHz beep at the start of every second, timed from [t0Us]. */
internal class TonePcmSource(private val t0Us: Long) : AudioPcmSource {
    override val sampleRate = 44_100
    override val channelCount = 1
    override var lastChunkPtsUs: Long = 0
        private set
    private var frame = 0L
    private var running = false
    private val chunkFrames = 882 // 20 ms

    override fun start() {
        running = true
        frame = ((syntheticNowUs() - t0Us) * sampleRate / 1_000_000L).coerceAtLeast(0)
    }

    override fun read(buffer: ByteArray): Int {
        if (!running) return -1
        val frames = minOf(chunkFrames, buffer.size / 2)
        val chunkStartUs = t0Us + frame * 1_000_000L / sampleRate
        val waitMs = (chunkStartUs + frames * 1_000_000L / sampleRate - syntheticNowUs()) / 1000
        if (waitMs > 0) Thread.sleep(waitMs)
        for (i in 0 until frames) {
            val tUs = (frame + i) * 1_000_000L / sampleRate
            val inBeep = tUs % 1_000_000L < 100_000L
            val sample = if (inBeep) (kotlin.math.sin(2.0 * Math.PI * 1000.0 * (frame + i) / sampleRate) * 12_000).toInt().toShort() else 0
            buffer[i * 2] = (sample.toInt() and 0xFF).toByte()
            buffer[i * 2 + 1] = ((sample.toInt() shr 8) and 0xFF).toByte()
        }
        lastChunkPtsUs = chunkStartUs
        frame += frames
        return frames * 2
    }

    override fun stop() {
        running = false
    }
}

/** What the synthetic camera currently "applies", reported back exactly (the source declares only what it simulates). */
internal class SyntheticState(
    var iso: Int = 100,
    var exposureNs: Long = AUTO_EXPOSURE_NS,
    var biasEv: Double = 0.0,
    var kelvin: Int? = null,
    var zoom: Double = 1.0,
) {
    companion object {
        const val AUTO_EXPOSURE_NS = 16_666_667L
    }
}

internal object SyntheticFrame {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)

    /** Brightness factor 1.0 = nominal: ISO x shutter x 2^EV relative to ISO 100 at 1/60 s. */
    fun exposureFactor(s: SyntheticState): Double =
        (s.iso / 100.0) * (s.exposureNs / SyntheticState.AUTO_EXPOSURE_NS.toDouble()) * 2.0.pow(s.biasEv)

    /** Draws one deterministic frame: gradient, moving bar, frame number and the exposure/WB/zoom effects. */
    fun draw(canvas: Canvas, w: Int, h: Int, tUs: Long, t0Us: Long, s: SyntheticState, frameNumber: Long, flashes: Boolean = true) {
        val rel = (tUs - t0Us).coerceAtLeast(0)
        // Flashes mark time in preview and video; stills never flash, so a photo's brightness depends only on exposure.
        val flash = flashes && rel % 1_000_000L < 100_000L
        canvas.save()
        if (s.zoom > 1.0) canvas.scale(s.zoom.toFloat(), s.zoom.toFloat(), w / 2f, h / 2f)
        canvas.drawColor(if (flash) Color.WHITE else Color.rgb(40, 90, 140))
        paint.style = Paint.Style.FILL
        paint.color = Color.rgb(230, 160, 40)
        val bar = ((rel / 4_000L) % w.coerceAtLeast(1)).toFloat()
        canvas.drawRect(bar, 0f, bar + w / 12f, h.toFloat(), paint)
        paint.color = Color.rgb(20, 20, 20)
        paint.textSize = h / 8f
        canvas.drawText("TEST CAMERA #$frameNumber", w / 20f, h / 2f, paint)
        canvas.restore()

        val factor = exposureFactor(s)
        if (factor < 1.0) {
            paint.color = Color.argb(((1.0 - factor.coerceAtLeast(0.0)) * 255).toInt().coerceIn(0, 255), 0, 0, 0)
            canvas.drawRect(0f, 0f, w.toFloat(), h.toFloat(), paint)
        } else if (factor > 1.0) {
            paint.color = Color.argb(((factor - 1.0) / (factor + 1.0) * 255).toInt().coerceIn(0, 255), 255, 255, 255)
            canvas.drawRect(0f, 0f, w.toFloat(), h.toFloat(), paint)
        }
        s.kelvin?.let { k ->
            val (r, g, b) = KelvinGains.lightRgb(k)
            paint.color = Color.argb(70, r.toInt(), g.toInt(), b.toInt())
            canvas.drawRect(0f, 0f, w.toFloat(), h.toFloat(), paint)
        }
    }
}

/** The synthetic test camera of docs/architecture/camera.md (ADR-0013). Debug and test builds only. */
class SyntheticBackend(private val context: Context, private val orientation: OrientationSource) : CameraBackend {
    private val ids = listOf(WIDE, TELE)

    override fun owns(cameraId: String) = cameraId in ids

    override fun listCameras(): List<CameraDescriptorMessage> = ids.map { descriptor(it) }

    private fun descriptor(id: String) = CameraDescriptorMessage(
        id = id,
        facing = CameraFacingMessage.BACK,
        lensKind = if (id == WIDE) LensKindMessage.WIDE else LensKindMessage.TELE,
        isLogical = false,
        physicalIds = emptyList(),
        sensorOrientation = 0,
        source = CameraSourceMessage.SYNTHETIC,
        label = if (id == WIDE) "Test camera (wide)" else "Test camera (telephoto)",
        focalLengthMm = if (id == WIDE) 4.2 else 9.0,
        focalLength35mmEq = if (id == WIDE) 26.0 else 56.0,
    )

    override fun capabilities(cameraId: String): CameraCapabilitiesMessage {
        if (cameraId !in ids) throw CameraException("unsupported_configuration", "Unknown camera $cameraId")
        val media = Camera2Backend.mediaSupport(context)
        return CameraCapabilitiesMessage(
            cameraId = cameraId,
            iso = IntRangeMessage(50, 3200),
            exposureTimeNs = IntRangeMessage(125_000, 250_000_000),
            exposureBias = ExposureBiasCapabilityMessage(DoubleRangeMessage(-4.0, 4.0), 1.0 / 3.0),
            apertures = listOf(1.8),
            // The synthetic source simulates no focus: it must not offer any (CAM-005).
            focus = FocusCapabilitiesMessage(auto = false, continuous = false, tapToFocus = false, manual = null),
            whiteBalance = WhiteBalanceCapabilitiesMessage(listOf(WbPresetMessage.AUTO), IntRangeMessage(2000, 10000)),
            zoom = ZoomCapabilitiesMessage(1.0, 4.0, listOf(1.0)),
            flash = emptyList(),
            torch = false,
            photoFormats = listOf(PhotoFormatMessage.JPEG),
            photoSizes = listOf(SizeMessage(1600, 1200), SizeMessage(800, 600)),
            stabilization = StabilizationCapabilitiesMessage(listOf(StabilizationModeMessage.OFF), listOf(StabilizationModeMessage.OFF)),
            video = VideoCapabilitiesMessage(
                if (media.videoEncoder) listOf(VideoSizeOptionMessage(SizeMessage(1280, 720), listOf(30)), VideoSizeOptionMessage(SizeMessage(640, 480), listOf(30))) else emptyList(),
                audio = media.audioEncoder,
            ),
            hdr = false,
            live = LiveCapabilitiesMessage(media.videoEncoder, if (media.videoEncoder) 3000 else 0, media.audioEncoder),
            hardwareLevel = "SYNTHETIC",
        )
    }

    override suspend fun open(
        sessionId: Long,
        config: SessionConfigMessage,
        texture: PreviewTexture,
        events: SessionEvents,
        audioAllowed: Boolean,
    ): BackendSession {
        if (config.cameraId !in ids) throw CameraException("unsupported_configuration", "Unknown camera ${config.cameraId}")
        val session = SyntheticSession(sessionId, config, texture, events, orientation, capabilities(config.cameraId), audioAllowed)
        session.start()
        return session
    }

    companion object {
        const val WIDE = "synthetic:wide"
        const val TELE = "synthetic:tele"
    }
}

internal class SyntheticSession(
    private val sessionId: Long,
    private val config: SessionConfigMessage,
    private val texture: PreviewTexture,
    private val events: SessionEvents,
    private val orientation: OrientationSource,
    private val caps: CameraCapabilitiesMessage,
    private val audioAllowed: Boolean,
) : BackendSession {
    private val t0Us = syntheticNowUs()
    private val state = SyntheticState()
    private val thread = HandlerThread("doro-synthetic-$sessionId").also { it.start() }
    private val handler = Handler(thread.looper)
    private val lock = Mutex()
    private val previewSize = SizeMessage(640, 480)
    private val photoSize = config.photoSize?.takeIf { it in caps.photoSizes } ?: caps.photoSizes.first()
    private lateinit var previewSurface: Surface
    @Volatile private var running = false
    @Volatile private var suspended = false
    @Volatile private var closed = false
    private var frameNumber = 0L
    private var liveWanted = config.live
    private var motion: MotionCoordinator? = null
    private var recordPipeline: EncoderPipeline? = null
    private var recorder: VideoFileRecorder? = null
    private var recordTarget: File? = null
    private var lastSettings: ResolvedCaptureSettingsMessage? = null
    @Volatile private var currentState = SessionStateMessage.CONFIGURING

    override lateinit var info: SessionInfoMessage
        private set

    private val renderLoop = object : Runnable {
        override fun run() {
            if (!running) return
            frameNumber++
            val now = syntheticNowUs()
            drawTo(previewSurface, previewSize.width.toInt(), previewSize.height.toInt(), now)
            (recordPipeline?.inputSurface ?: motion?.inputSurface)?.let { surface ->
                val size = recordPipeline ?: null
                val w = size?.width ?: motion!!.width
                val h = size?.height ?: motion!!.height
                drawTo(surface, w, h, now)
            }
            handler.postDelayed(this, 33)
        }
    }

    private fun drawTo(surface: Surface, w: Int, h: Int, tUs: Long) {
        try {
            val canvas = surface.lockCanvas(null)
            try {
                SyntheticFrame.draw(canvas, w, h, tUs, t0Us, state, frameNumber)
            } finally {
                surface.unlockCanvasAndPost(canvas)
            }
        } catch (_: Exception) {
            // The surface can disappear while a pipeline stops; the next frame goes to the new one.
        }
    }

    private fun emit(kind: SessionEventKindMessage, newState: SessionStateMessage? = null) {
        events.emit(SessionEventMessage(sessionId, kind, state = newState))
    }

    private fun setState(next: SessionStateMessage) {
        if (currentState == next) return
        currentState = next
        emit(SessionEventKindMessage.STATE, next)
    }

    suspend fun start() {
        texture.surfaceTexture.setDefaultBufferSize(previewSize.width.toInt(), previewSize.height.toInt())
        previewSurface = Surface(texture.surfaceTexture)
        running = true
        handler.post(renderLoop)
        startMotionIfWanted()
        publish()
        setState(SessionStateMessage.PREVIEWING)
    }

    private fun audioWanted() = config.audio && audioAllowed && caps.live.audio

    private fun startMotionIfWanted() {
        motion?.stop()
        motion = null
        if (!liveWanted || !caps.live.supported || recordPipeline != null || suspended) return
        val coordinator = MotionCoordinator(nowUs = ::syntheticNowUs)
        val pipeline = EncoderPipeline(640, 480, 30, 2_000_000, if (audioWanted()) TonePcmSource(t0Us) else null, { it }, coordinator::sink)
        pipeline.start()
        coordinator.attach(pipeline)
        motion = coordinator
    }

    private fun publish() {
        info = SessionInfoMessage(
            sessionId = sessionId,
            textureId = texture.textureId,
            cameraId = config.cameraId,
            previewSize = previewSize,
            photoSize = photoSize,
            photoFormat = PhotoFormatMessage.JPEG,
            sensorOrientation = 0,
            source = CameraSourceMessage.SYNTHETIC,
            liveActive = motion?.active == true,
            audioActive = motion?.active == true && audioWanted(),
        )
    }

    private fun applied(requested: ResolvedCaptureSettingsMessage?): AppliedSettingsMessage {
        val mismatches = buildList {
            if (SyntheticControl.ignoreManualRequests && requested != null) {
                if (requested.iso != null) add("iso")
                if (requested.exposureTimeNs != null) add("exposureTime")
            }
        }
        return AppliedSettingsMessage(
            iso = state.iso.toLong(),
            exposureTimeNs = state.exposureNs,
            exposureBiasEv = state.biasEv,
            aperture = 1.8,
            focalLengthMm = if (config.cameraId == SyntheticBackend.WIDE) 4.2 else 9.0,
            focusDistanceDiopters = null,
            focusMode = null,
            whiteBalanceMode = if (state.kelvin != null) "manual" else "auto",
            whiteBalanceGains = null,
            estimatedKelvin = state.kelvin?.toLong(),
            aeLocked = false,
            afLocked = false,
            zoomRatio = state.zoom,
            flashFired = false,
            flash = FlashModeMessage.OFF,
            stabilization = StabilizationModeMessage.OFF,
            mismatches = mismatches,
        )
    }

    override suspend fun applySettings(settings: ResolvedCaptureSettingsMessage): AppliedSettingsMessage = lock.withLock {
        ensureRunning()
        lastSettings = settings
        if (!SyntheticControl.ignoreManualRequests) {
            val manual = settings.iso != null || settings.exposureTimeNs != null
            state.iso = if (manual) (settings.iso ?: 100).toInt().coerceIn(50, 3200) else 100
            state.exposureNs = if (manual) (settings.exposureTimeNs ?: SyntheticState.AUTO_EXPOSURE_NS).coerceIn(125_000, 250_000_000) else SyntheticState.AUTO_EXPOSURE_NS
            state.biasEv = if (!manual) (settings.exposureBiasEv ?: 0.0).coerceIn(-4.0, 4.0) else 0.0
            state.kelvin = settings.kelvin?.toInt()?.coerceIn(2000, 10000)
            state.zoom = settings.zoomRatio.coerceIn(1.0, 4.0)
        } else {
            state.iso = 100
            state.exposureNs = SyntheticState.AUTO_EXPOSURE_NS
            state.biasEv = 0.0
            state.kelvin = null
        }
        applied(settings)
    }

    override suspend fun focusAt(x: Double, y: Double) {
        throw CameraException("unsupported_configuration", "The test camera has no focus control")
    }

    override fun setLive(enabled: Boolean) {
        if (liveWanted == enabled) return
        liveWanted = enabled
        handler.post {
            startMotionIfWanted()
            publish()
        }
    }

    private fun ensureRunning() {
        if (closed) throw CameraException("camera_disconnected", "The session is closed")
        if (suspended) throw CameraException("camera_disconnected", "The camera is suspended")
    }

    private fun stillBytes(): ByteArray {
        val bitmap = Bitmap.createBitmap(photoSize.width.toInt(), photoSize.height.toInt(), Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        SyntheticFrame.draw(canvas, bitmap.width, bitmap.height, syntheticNowUs(), t0Us, state, frameNumber, flashes = false)
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.JPEG, 95, out)
        bitmap.recycle()
        return out.toByteArray()
    }

    override suspend fun capture(request: CaptureRequestMessage): CaptureResultMessage = lock.withLock {
        ensureRunning()
        if (recordPipeline != null) throw CameraException("capture_failed", "Stop the video before taking a photo")
        val originalFile = AtomicFiles.target(request.outputDir, request.originalName)
        AtomicFiles.target(request.outputDir, request.renderedName)
        AtomicFiles.target(request.outputDir, request.thumbnailName)
        AtomicFiles.target(request.outputDir, request.displayName)
        val wantsMotion = request.live && motion?.active == true
        val motionFile = if (wantsMotion) AtomicFiles.target(request.outputDir, request.motionName ?: "motion.mp4") else null
        setState(SessionStateMessage.CAPTURING)
        try {
            val shutterUs = syntheticNowUs()
            val bytes = stillBytes()
            AtomicFiles.write(originalFile, bytes)
            val rendition = try {
                RenditionWriter().write(originalFile, 0, request)
            } catch (e: CameraException) {
                if (e.code == "storage_full") throw e
                null
            } catch (e: Exception) {
                null
            }
            var motionResult: MotionResultMessage? = null
            if (wantsMotion && motionFile != null) {
                motionResult = try {
                    motion!!.captureClip(shutterUs, request.preRollMs, request.postRollMs, motionFile, orientation.degrees)
                } catch (e: CameraException) {
                    events.emit(SessionEventMessage(sessionId, SessionEventKindMessage.ERROR, errorCode = e.code, errorMessage = e.message))
                    null
                }
            }
            CaptureResultMessage(
                memoryId = request.memoryId,
                originalPath = originalFile.path,
                originalMime = "image/jpeg",
                width = photoSize.width,
                height = photoSize.height,
                orientationDegrees = 0,
                applied = applied(lastSettings),
                capturedAtEpochMs = request.timestampEpochMs ?: System.currentTimeMillis(),
                source = CameraSourceMessage.SYNTHETIC,
                liveIncluded = motionResult != null,
                mirrored = false,
                renderFailed = rendition == null,
                renderedPath = rendition?.rendered?.path,
                thumbnailPath = rendition?.thumbnail?.path,
                displayPath = rendition?.display?.path,
                motion = motionResult,
            )
        } finally {
            if (!closed && currentState == SessionStateMessage.CAPTURING) setState(SessionStateMessage.PREVIEWING)
        }
    }

    override suspend fun startVideo(request: VideoRequestMessage) = lock.withLock {
        ensureRunning()
        if (recordPipeline != null) throw CameraException("capture_failed", "A recording is already running")
        val option = caps.video.options.firstOrNull { it.size == (request.size ?: it.size) }
            ?: throw CameraException("unsupported_configuration", "Video size is not supported")
        val size = request.size ?: option.size
        val fps = (request.fps ?: option.fps.first()).toInt()
        if (fps.toLong() !in option.fps) throw CameraException("unsupported_configuration", "$fps fps is not supported")
        val target = File(request.outputPath)
        if (target.parentFile?.isDirectory != true) throw CameraException("unsupported_configuration", "Output directory does not exist")
        motion?.stop()
        motion = null
        val withAudio = request.audio && audioWanted()
        lateinit var ref: EncoderPipeline
        val rec = VideoFileRecorder(target, size.width.toInt(), size.height.toInt(), orientation.degrees, withAudio, { ref.videoFormat to ref.audioFormat })
        ref = EncoderPipeline(size.width.toInt(), size.height.toInt(), fps, 3_000_000, if (withAudio) TonePcmSource(t0Us) else null, { it }, rec::onSample)
        ref.start()
        recorder = rec
        recordTarget = target
        recordPipeline = ref
        setState(SessionStateMessage.RECORDING)
        publish()
    }

    override suspend fun stopVideo(): VideoResultMessage = lock.withLock {
        val pipeline = recordPipeline ?: throw CameraException("capture_failed", "No recording is running")
        val rec = recorder!!
        val target = recordTarget!!
        pipeline.stop()
        recordPipeline = null
        recorder = null
        val summary = try {
            rec.finish()
        } finally {
            startMotionIfWanted()
            publish()
            setState(SessionStateMessage.PREVIEWING)
        }
        VideoResultMessage(target.path, summary.durationMs, summary.width.toLong(), summary.height.toLong(), summary.hasAudio, summary.bytes, orientation.degrees.toLong(), "video/mp4")
    }

    override suspend fun suspend() = lock.withLock {
        if (suspended) return@withLock
        suspended = true
        recordPipeline?.stop()
        recorder?.abort()
        recordPipeline = null
        recorder = null
        motion?.stop()
        motion = null
        setState(SessionStateMessage.SUSPENDED)
    }

    override suspend fun resume() = lock.withLock {
        if (closed) throw CameraException("camera_disconnected", "The session is closed")
        if (!suspended) return@withLock
        suspended = false
        startMotionIfWanted()
        publish()
        setState(SessionStateMessage.PREVIEWING)
        emit(SessionEventKindMessage.RESUMED)
    }

    override suspend fun close() = lock.withLock {
        if (closed) return@withLock
        closed = true
        running = false
        handler.removeCallbacksAndMessages(null)
        recordPipeline?.stop()
        recorder?.abort()
        motion?.stop()
        motion = null
        if (::previewSurface.isInitialized) previewSurface.release()
        emit(SessionEventKindMessage.STATE, SessionStateMessage.CLOSED)
        thread.quitSafely()
    }
}
