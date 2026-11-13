package com.dorocam.doro_camera

import android.content.Context
import android.graphics.ImageFormat
import android.graphics.SurfaceTexture
import android.hardware.camera2.CameraAccessException
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CameraMetadata
import android.hardware.camera2.CaptureFailure
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.TotalCaptureResult
import android.hardware.camera2.params.OutputConfiguration
import android.hardware.camera2.params.SessionConfiguration
import android.media.Image
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import android.view.Surface
import java.io.File
import java.util.concurrent.Executor
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.android.asCoroutineDispatcher
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** Everything a Camera2 session needs from the device and app. */
class Camera2Environment(
    val context: Context,
    val manager: CameraManager,
    val media: MediaSupport,
    val orientation: OrientationSource,
    val thermal: ThermalSource,
    val nowUs: () -> Long = { SystemClock.elapsedRealtimeNanos() / 1000 },
)

/** A logical camera id, optionally narrowed to one of its physical lenses. */
data class OpenTarget(val logicalId: String, val physicalId: String?) {
    companion object {
        fun parse(id: String): OpenTarget {
            val parts = id.split('#', limit = 2)
            return OpenTarget(parts[0], parts.getOrNull(1))
        }
    }
}

/**
 * A running Camera2 session: preview into a Flutter texture, JPEG/HEIC capture with the settings the device
 * reports as applied, LIVE motion buffering, video recording and interruption handling.
 *
 * Product logic is not here (ADR-0001): the session applies already-resolved settings and reports facts.
 * The pure parts (probe, mapping, ring buffer, geometry, rendering math) are tested on the JVM; this class
 * is exercised on the Android Emulator's camera HAL.
 */
class Camera2Session(
    private val sessionId: Long,
    private val env: Camera2Environment,
    private val target: OpenTarget,
    private val data: CharacteristicsData,
    realtimeTimestamps: Boolean,
    private val config: SessionConfigMessage,
    private val texture: PreviewTexture,
    private val events: SessionEvents,
    private val audioAllowed: Boolean,
) : BackendSession {
    companion object {
        private const val CAPTURE_TIMEOUT_MS = 12_000L
        private const val SETTLE_TIMEOUT_MS = 1_500L
        private const val FOCUS_TIMEOUT_MS = 2_500L
        private const val APPLIED_EVENT_INTERVAL_MS = 250L

        suspend fun open(
            sessionId: Long,
            env: Camera2Environment,
            target: OpenTarget,
            data: CharacteristicsData,
            realtimeTimestamps: Boolean,
            config: SessionConfigMessage,
            texture: PreviewTexture,
            events: SessionEvents,
            audioAllowed: Boolean,
        ): Camera2Session {
            val session = Camera2Session(sessionId, env, target, data, realtimeTimestamps, config, texture, events, audioAllowed)
            try {
                session.start()
            } catch (e: Throwable) {
                session.teardown()
                throw e
            }
            return session
        }
    }

    private class Latest(val sequenceId: Int, val data: ResultData, val aeState: Int?, val afState: Int?)

    private val thread = HandlerThread("doro-camera-$sessionId").also { it.start() }
    private val handler = Handler(thread.looper)
    private val executor = Executor { handler.post(it) }
    private val scope = CoroutineScope(SupervisorJob() + handler.asCoroutineDispatcher("doro-camera-$sessionId"))
    private val lock = Mutex()
    private val aligner = ClockAligner(realtimeTimestamps, env.nowUs)
    private val frontFacing = data.lensFacing == CameraMetadata.LENS_FACING_FRONT

    private var device: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null
    private lateinit var previewSurface: Surface
    private lateinit var imageReader: ImageReader
    private lateinit var previewSize: SizeMessage
    private lateinit var photoSize: SizeMessage
    private lateinit var photoFormat: PhotoFormatMessage

    private var settings: ResolvedCaptureSettingsMessage = defaultSettings()
    private var params: RequestParams = SettingsMapper.map(settings, data)
    private var region: Region? = null
    private var forceAutoFocus = false
    private var afLocked = false
    private var lastAuto: AutoSnapshot? = null

    @Volatile private var latest: Latest? = null
    private val lastSubmitted = AtomicInteger(-1)
    private var lastAppliedEventMs = 0L

    private var liveWanted = config.live
    private var motion: MotionCoordinator? = null
    private var recordPipeline: EncoderPipeline? = null
    private var recorder: VideoFileRecorder? = null
    private var recordOrientation = 0
    private var recordTarget: File? = null

    @Volatile private var state = SessionStateMessage.CONFIGURING
    @Volatile private var closed = false
    @Volatile private var explicitlySuspended = false
    @Volatile private var interrupted = false
    private var thermalState = ThermalStateMessage.NOMINAL

    override lateinit var info: SessionInfoMessage
        private set

    private val orientationListener: (Int) -> Unit = { degrees ->
        events.emit(SessionEventMessage(sessionId, SessionEventKindMessage.ORIENTATION, orientationDegrees = degrees.toLong()))
    }
    private val thermalListener: (ThermalStateMessage) -> Unit = { next -> scope.launch { onThermal(next) } }
    private val availability = object : CameraManager.AvailabilityCallback() {
        override fun onCameraAvailable(cameraId: String) {
            if (cameraId == target.logicalId && interrupted && !explicitlySuspended && !closed) {
                scope.launch {
                    delay(300)
                    try {
                        resume()
                    } catch (_: Exception) {
                        // Still unavailable: the next availability callback tries again.
                    }
                }
            }
        }
    }

    private fun defaultSettings() = ResolvedCaptureSettingsMessage(
        aeLock = false,
        focusMode = FocusModeMessage.CONTINUOUS,
        afLock = false,
        zoomRatio = 1.0,
        flash = FlashModeMessage.OFF,
        torch = false,
    )

    // ---- lifecycle ------------------------------------------------------------------------------

    private suspend fun start() {
        photoFormat = when {
            config.photoFormat == PhotoFormatMessage.HEIF && data.heifSizes.isNotEmpty() -> PhotoFormatMessage.HEIF
            data.jpegSizes.isNotEmpty() -> PhotoFormatMessage.JPEG
            data.heifSizes.isNotEmpty() -> PhotoFormatMessage.HEIF
            else -> throw CameraException("unsupported_configuration", "The camera offers no still format we can capture")
        }
        val sizes = if (photoFormat == PhotoFormatMessage.HEIF) data.heifSizes else data.jpegSizes
        photoSize = Geometry.choosePhotoSize(sizes, config.photoSize) ?: throw CameraException("unsupported_configuration", "No photo size available")
        previewSize = config.previewSize?.takeIf { it in data.surfaceSizes }
            ?: Geometry.choosePreviewSize(data.surfaceSizes, photoSize)
            ?: throw CameraException("unsupported_configuration", "No preview size available")

        imageReader = ImageReader.newInstance(
            photoSize.width.toInt(),
            photoSize.height.toInt(),
            if (photoFormat == PhotoFormatMessage.HEIF) ImageFormat.HEIC else ImageFormat.JPEG,
            2,
        )
        texture.surfaceTexture.setDefaultBufferSize(previewSize.width.toInt(), previewSize.height.toInt())
        previewSurface = Surface(texture.surfaceTexture)

        device = openDevice()
        env.manager.registerAvailabilityCallback(executor, availability)
        env.orientation.addListener(orientationListener)
        env.thermal.addListener(thermalListener)
        thermalState = env.thermal.state
        rebuildSession()
        publishInfo()
        setState(SessionStateMessage.PREVIEWING)
    }

    private fun publishInfo() {
        info = SessionInfoMessage(
            sessionId = sessionId,
            textureId = texture.textureId,
            cameraId = config.cameraId,
            previewSize = previewSize,
            photoSize = photoSize,
            photoFormat = photoFormat,
            sensorOrientation = data.sensorOrientation.toLong(),
            source = CameraSourceMessage.HARDWARE,
            liveActive = motion?.active == true,
            audioActive = motion?.hasAudio == true || (motion?.active == true && audioWanted()),
        )
    }

    private fun setState(next: SessionStateMessage) {
        if (state == next) return
        state = next
        events.emit(SessionEventMessage(sessionId, SessionEventKindMessage.STATE, state = next))
    }

    private fun emitError(code: String, message: String) {
        events.emit(SessionEventMessage(sessionId, SessionEventKindMessage.ERROR, errorCode = code, errorMessage = message))
    }

    private fun audioWanted() = config.audio && audioAllowed && env.media.microphone && env.media.audioEncoder

    private suspend fun openDevice(): CameraDevice = suspendCancellableCoroutine { cont ->
        val callback = object : CameraDevice.StateCallback() {
            override fun onOpened(camera: CameraDevice) {
                if (cont.isActive) cont.resume(camera) else camera.close()
            }

            override fun onDisconnected(camera: CameraDevice) {
                camera.close()
                if (cont.isActive) cont.resumeWithException(CameraException("camera_in_use", "The camera was taken by another app"))
                else onInterrupted("camera_in_use", "The camera was taken by another app")
            }

            override fun onError(camera: CameraDevice, error: Int) {
                camera.close()
                val (code, message) = mapDeviceError(error)
                if (cont.isActive) cont.resumeWithException(CameraException(code, message)) else onInterrupted(code, message)
            }

            override fun onClosed(camera: CameraDevice) = Unit
        }
        try {
            env.manager.openCamera(target.logicalId, executor, callback)
        } catch (e: CameraAccessException) {
            cont.resumeWithException(mapAccessException(e))
        } catch (e: SecurityException) {
            cont.resumeWithException(CameraException("permission_denied", "Camera permission was not granted", e))
        }
    }

    private fun mapDeviceError(error: Int): Pair<String, String> = when (error) {
        CameraDevice.StateCallback.ERROR_CAMERA_IN_USE, CameraDevice.StateCallback.ERROR_MAX_CAMERAS_IN_USE ->
            "camera_in_use" to "The camera is in use by another app"
        CameraDevice.StateCallback.ERROR_CAMERA_DISABLED -> "permission_restricted" to "The camera is disabled by a device policy"
        else -> "camera_disconnected" to "The camera reported an error ($error)"
    }

    private fun mapAccessException(e: CameraAccessException): CameraException = when (e.reason) {
        CameraAccessException.CAMERA_IN_USE, CameraAccessException.MAX_CAMERAS_IN_USE -> CameraException("camera_in_use", "The camera is in use by another app", e)
        CameraAccessException.CAMERA_DISABLED -> CameraException("permission_restricted", "The camera is disabled by a device policy", e)
        else -> CameraException("camera_disconnected", "The camera could not be reached", e)
    }

    // ---- streams --------------------------------------------------------------------------------

    private fun outputs(extra: Surface?): List<OutputConfiguration> {
        fun cfg(surface: Surface, physical: Boolean): OutputConfiguration = OutputConfiguration(surface).also {
            if (physical && target.physicalId != null) it.setPhysicalCameraId(target.physicalId)
        }
        return buildList {
            add(cfg(previewSurface, true))
            add(cfg(imageReader.surface, true))
            if (extra != null) add(cfg(extra, false))
        }
    }

    private suspend fun createSession(extra: Surface?): CameraCaptureSession = suspendCancellableCoroutine { cont ->
        val cameraDevice = device ?: run {
            cont.resumeWithException(CameraException("camera_disconnected", "The camera is closed"))
            return@suspendCancellableCoroutine
        }
        val callback = object : CameraCaptureSession.StateCallback() {
            override fun onConfigured(session: CameraCaptureSession) {
                if (cont.isActive) cont.resume(session) else session.close()
            }

            override fun onConfigureFailed(session: CameraCaptureSession) {
                session.close()
                if (cont.isActive) cont.resumeWithException(CameraException("unsupported_configuration", "The camera rejected the stream combination"))
            }
        }
        try {
            cameraDevice.createCaptureSession(SessionConfiguration(SessionConfiguration.SESSION_REGULAR, outputs(extra), executor, callback))
        } catch (e: CameraAccessException) {
            cont.resumeWithException(mapAccessException(e))
        } catch (e: IllegalArgumentException) {
            cont.resumeWithException(CameraException("unsupported_configuration", "Invalid stream configuration", e))
        }
    }

    private fun motionSize(): SizeMessage? {
        val candidates = data.surfaceSizes.filter { it.width * it.height <= 1920L * 1080L && it.width >= 640 }
        val aspect = previewSize.width.toDouble() / previewSize.height
        val same = candidates.filter { kotlin.math.abs(it.width.toDouble() / it.height - aspect) < 0.02 }
        return (same.ifEmpty { candidates }).maxByOrNull { it.width * it.height } ?: CapabilityProbe.defaultMotionSize(data)
    }

    private fun newPipeline(size: SizeMessage, fps: Int, withAudio: Boolean, sink: (EncodedSample) -> Unit): EncoderPipeline =
        EncoderPipeline(
            width = size.width.toInt(),
            height = size.height.toInt(),
            fps = fps,
            videoBitrate = (size.width * size.height * fps * 0.07).toInt().coerceIn(1_000_000, 40_000_000),
            audio = if (withAudio) MicrophoneSource() else null,
            toSharedClockUs = aligner::toSharedUs,
            onSample = sink,
        )

    /** (Re)creates the capture session, with the LIVE or recording encoder as an extra output when wanted. */
    private suspend fun rebuildSession() {
        captureSession?.let {
            try {
                it.stopRepeating()
            } catch (_: Exception) {
                // Already closed.
            }
            it.close()
        }
        captureSession = null
        motion?.stop()
        motion = null

        val record = recordPipeline
        var pipelineSurface: Surface? = record?.inputSurface
        var liveCoordinator: MotionCoordinator? = null
        if (record == null && liveWanted && thermalState < ThermalStateMessage.SERIOUS && env.media.videoEncoder) {
            val size = motionSize()
            if (size != null) {
                val coordinator = MotionCoordinator(nowUs = env.nowUs)
                try {
                    val pipeline = newPipeline(size, 30, audioWanted(), coordinator::sink)
                    pipeline.start()
                    coordinator.attach(pipeline)
                    pipelineSurface = pipeline.inputSurface
                    liveCoordinator = coordinator
                } catch (e: Throwable) {
                    coordinator.stop()
                    emitError("capture_failed", "LIVE could not start: ${e.message}")
                }
            }
        }

        captureSession = try {
            createSession(pipelineSurface)
        } catch (e: CameraException) {
            if (pipelineSurface == null) throw e
            // The device cannot run this many streams at once: fall back to preview + photo only, and say so honestly.
            liveCoordinator?.stop()
            liveCoordinator = null
            if (record != null) throw e
            emitError("unsupported_configuration", "LIVE is not available with this camera configuration")
            createSession(null)
        }
        motion = liveCoordinator
        params = SettingsMapper.map(settings, data, lastAuto, forVideo = recordPipeline != null)
        startRepeating()
    }

    private fun repeatingBuilder(): CaptureRequest.Builder {
        val cameraDevice = device ?: throw CameraException("camera_disconnected", "The camera is closed")
        val builder = cameraDevice.createCaptureRequest(if (recordPipeline != null) CameraDevice.TEMPLATE_RECORD else CameraDevice.TEMPLATE_PREVIEW)
        builder.addTarget(previewSurface)
        recordPipeline?.let { builder.addTarget(it.inputSurface) }
        if (recordPipeline == null) motion?.inputSurface?.let { builder.addTarget(it) }
        RequestApplier.apply(builder, activeParams(), data, still = false, region = region)
        return builder
    }

    private fun activeParams(): RequestParams =
        if (forceAutoFocus && CameraMetadata.CONTROL_AF_MODE_AUTO in data.afModes) params.copy(afMode = CameraMetadata.CONTROL_AF_MODE_AUTO) else params

    private val repeatingCallback = object : CameraCaptureSession.CaptureCallback() {
        override fun onCaptureStarted(session: CameraCaptureSession, request: CaptureRequest, timestamp: Long, frameNumber: Long) {
            aligner.observeFrame(timestamp)
        }

        override fun onCaptureCompleted(session: CameraCaptureSession, request: CaptureRequest, result: TotalCaptureResult) {
            val read = RequestApplier.read(result)
            latest = Latest(result.sequenceId, read, RequestApplier.aeState(result), RequestApplier.afState(result))
            if (read.aeMode != null && read.aeMode != CameraMetadata.CONTROL_AE_MODE_OFF && read.sensitivity != null && read.exposureTimeNs != null) {
                lastAuto = AutoSnapshot(read.sensitivity, read.exposureTimeNs)
            }
            val now = SystemClock.elapsedRealtime()
            if (now - lastAppliedEventMs >= APPLIED_EVENT_INTERVAL_MS && state == SessionStateMessage.PREVIEWING) {
                lastAppliedEventMs = now
                events.emit(SessionEventMessage(sessionId, SessionEventKindMessage.APPLIED, applied = AppliedExtractor.extract(activeParams(), read, data)))
            }
        }
    }

    private fun startRepeating() {
        val session = captureSession ?: return
        lastSubmitted.set(session.setRepeatingRequest(repeatingBuilder().build(), repeatingCallback, handler))
    }

    private suspend fun awaitResult(timeoutMs: Long, minSequence: Int = lastSubmitted.get(), predicate: (Latest) -> Boolean): Latest? =
        withTimeoutOrNull(timeoutMs) {
            var found: Latest? = null
            while (found == null) {
                val current = latest
                if (current != null && current.sequenceId >= minSequence && predicate(current)) found = current else delay(25)
            }
            found
        }

    // ---- settings ---------------------------------------------------------------------------------

    override suspend fun applySettings(settings: ResolvedCaptureSettingsMessage): AppliedSettingsMessage = lock.withLock {
        ensureRunning()
        val wasLocked = afLocked
        this.settings = settings
        forceAutoFocus = false
        region = null
        params = SettingsMapper.map(settings, data, lastAuto, forVideo = recordPipeline != null)
        afLocked = settings.afLock && settings.focusMode != FocusModeMessage.MANUAL
        startRepeating()
        if (afLocked && !wasLocked) triggerAutofocus() else if (!afLocked && wasLocked) cancelAutofocus()
        val seq = lastSubmitted.get()
        val settled = awaitResult(SETTLE_TIMEOUT_MS, seq) { AppliedExtractor.mismatches(params, it.data, data).isEmpty() }
        val result = settled ?: latest ?: throw CameraException("capture_failed", "The camera has not produced a frame yet")
        AppliedExtractor.extract(activeParams(), result.data, data)
    }

    private fun oneShot(configure: (CaptureRequest.Builder) -> Unit) {
        val session = captureSession ?: return
        val builder = repeatingBuilder()
        configure(builder)
        session.capture(builder.build(), repeatingCallback, handler)
    }

    private suspend fun triggerAutofocus(): Boolean {
        if (CameraMetadata.CONTROL_AF_MODE_AUTO !in data.afModes) return false
        forceAutoFocus = true
        startRepeating()
        oneShot { it.set(CaptureRequest.CONTROL_AF_TRIGGER, CameraMetadata.CONTROL_AF_TRIGGER_START) }
        val done = awaitResult(FOCUS_TIMEOUT_MS) {
            it.afState == CameraMetadata.CONTROL_AF_STATE_FOCUSED_LOCKED || it.afState == CameraMetadata.CONTROL_AF_STATE_NOT_FOCUSED_LOCKED
        }
        return done != null
    }

    private suspend fun cancelAutofocus() {
        oneShot { it.set(CaptureRequest.CONTROL_AF_TRIGGER, CameraMetadata.CONTROL_AF_TRIGGER_CANCEL) }
        forceAutoFocus = false
        startRepeating()
    }

    override suspend fun focusAt(x: Double, y: Double) = lock.withLock {
        ensureRunning()
        val zoom = params.zoomRatio.toDouble().coerceAtLeast(1.0)
        val cropW = (data.activeArrayWidth / zoom).toInt().coerceAtLeast(1)
        val cropH = (data.activeArrayHeight / zoom).toInt().coerceAtLeast(1)
        region = if (data.maxAfRegions > 0 || data.maxAeRegions > 0) {
            Geometry.meteringRegion(x, y, data.sensorOrientation, frontFacing, data.activeArrayWidth, data.activeArrayHeight, cropW, cropH)
        } else {
            null
        }
        if (params.requestedFocusMode == FocusModeMessage.MANUAL) {
            startRepeating() // metering only: manual focus stays where the user put it
        } else {
            triggerAutofocus()
        }
        Unit
    }

    // ---- LIVE and thermal -------------------------------------------------------------------------

    override fun setLive(enabled: Boolean) {
        if (liveWanted == enabled) return
        liveWanted = enabled
        scope.launch {
            lock.withLock {
                if (!closed && !explicitlySuspended && !interrupted && recordPipeline == null && device != null) {
                    rebuildSession()
                    publishInfo()
                }
            }
        }
    }

    private suspend fun onThermal(next: ThermalStateMessage) {
        thermalState = next
        events.emit(SessionEventMessage(sessionId, SessionEventKindMessage.THERMAL, thermal = next))
        lock.withLock {
            if (closed || explicitlySuspended || interrupted) return@withLock
            when {
                next == ThermalStateMessage.CRITICAL -> {
                    emitError("thermal_shutdown", "The device is too hot to keep the camera running")
                    suspendLocked(explicit = false)
                }
                next >= ThermalStateMessage.SERIOUS && motion?.active == true && recordPipeline == null -> {
                    rebuildSession() // drops LIVE buffering (NFR-012)
                    publishInfo()
                }
                next < ThermalStateMessage.SERIOUS && liveWanted && motion?.active != true && recordPipeline == null -> {
                    rebuildSession()
                    publishInfo()
                }
            }
        }
    }

    // ---- capture ----------------------------------------------------------------------------------

    private fun ensureRunning() {
        if (closed) throw CameraException("camera_disconnected", "The session is closed")
        if (explicitlySuspended || interrupted || device == null || captureSession == null) {
            throw CameraException("camera_disconnected", "The camera is suspended")
        }
    }

    override suspend fun capture(request: CaptureRequestMessage): CaptureResultMessage = lock.withLock {
        ensureRunning()
        if (recordPipeline != null) throw CameraException("capture_failed", "Stop the video before taking a photo")
        val dir = File(request.outputDir)
        if (!dir.isDirectory) throw CameraException("unsupported_configuration", "Output directory does not exist: ${request.outputDir}")
        // Validate names before touching the camera so a bad request cannot leave a half-written capture behind.
        val originalFile = AtomicFiles.target(request.outputDir, request.originalName)
        AtomicFiles.target(request.outputDir, request.renderedName)
        AtomicFiles.target(request.outputDir, request.thumbnailName)
        AtomicFiles.target(request.outputDir, request.displayName)
        val wantsMotion = request.live && motion?.active == true
        val motionFile = if (wantsMotion) AtomicFiles.target(request.outputDir, request.motionName ?: "motion.mp4") else null

        setState(SessionStateMessage.CAPTURING)
        try {
            runPrecaptureIfNeeded()
            val orientation = Geometry.jpegOrientation(data.sensorOrientation, env.orientation.degrees, frontFacing)
            val shutter = takeStill(request, orientation)
            val capturedAt = request.timestampEpochMs ?: System.currentTimeMillis()

            AtomicFiles.write(originalFile, shutter.bytes)
            val applied = AppliedExtractor.extract(params, shutter.resultData, data)

            val renditions = scope.async(Dispatchers.Default) {
                try {
                    RenditionWriter().write(originalFile, orientation, request)
                } catch (e: CameraException) {
                    if (e.code == "storage_full") throw e
                    null
                } catch (e: Exception) {
                    null
                }
            }
            var motionResult: MotionResultMessage? = null
            if (wantsMotion && motionFile != null) {
                motionResult = try {
                    motion!!.captureClip(aligner.toSharedUs(shutter.timestampNs / 1000), request.preRollMs, request.postRollMs, motionFile, orientation)
                } catch (e: CameraException) {
                    emitError(e.code, "The motion clip could not be saved: ${e.message}")
                    null
                }
            }
            val rendered = renditions.await()
            CaptureResultMessage(
                memoryId = request.memoryId,
                originalPath = originalFile.path,
                originalMime = if (photoFormat == PhotoFormatMessage.HEIF) "image/heic" else "image/jpeg",
                width = shutter.width.toLong(),
                height = shutter.height.toLong(),
                orientationDegrees = orientation.toLong(),
                applied = applied,
                capturedAtEpochMs = capturedAt,
                source = CameraSourceMessage.HARDWARE,
                liveIncluded = motionResult != null,
                mirrored = false,
                renderFailed = rendered == null,
                renderedPath = rendered?.rendered?.path,
                thumbnailPath = rendered?.thumbnail?.path,
                displayPath = rendered?.display?.path,
                motion = motionResult,
            )
        } finally {
            if (!closed && state == SessionStateMessage.CAPTURING) setState(SessionStateMessage.PREVIEWING)
        }
    }

    private class Shutter(val bytes: ByteArray, val width: Int, val height: Int, val timestampNs: Long, val resultData: ResultData)

    private suspend fun runPrecaptureIfNeeded() {
        val needsFlash = data.flashAvailable && params.stillAeMode != CameraMetadata.CONTROL_AE_MODE_ON && params.stillAeMode != CameraMetadata.CONTROL_AE_MODE_OFF
        if (needsFlash) {
            oneShot {
                RequestApplier.apply(it, params, data, still = true, region = region)
                it.set(CaptureRequest.CONTROL_AE_PRECAPTURE_TRIGGER, CameraMetadata.CONTROL_AE_PRECAPTURE_TRIGGER_START)
            }
            awaitResult(2_000) {
                it.aeState == CameraMetadata.CONTROL_AE_STATE_CONVERGED || it.aeState == CameraMetadata.CONTROL_AE_STATE_FLASH_REQUIRED
            }
        }
        if (params.afMode == CameraMetadata.CONTROL_AF_MODE_AUTO && !afLocked) triggerAutofocus()
    }

    private suspend fun takeStill(request: CaptureRequestMessage, orientation: Int): Shutter {
        val session = captureSession ?: throw CameraException("camera_disconnected", "The camera is closed")
        val cameraDevice = device ?: throw CameraException("camera_disconnected", "The camera is closed")
        // Drop any stale frame still waiting in the reader.
        while (true) imageReader.acquireLatestImage()?.close() ?: break

        val imageDeferred = CompletableDeferred<Triple<ByteArray, Int, Int>>()
        imageReader.setOnImageAvailableListener({ reader ->
            val image: Image? = try {
                reader.acquireLatestImage()
            } catch (e: IllegalStateException) {
                null
            }
            if (image != null) {
                try {
                    val buffer = image.planes[0].buffer
                    val bytes = ByteArray(buffer.remaining())
                    buffer.get(bytes)
                    imageDeferred.complete(Triple(bytes, image.width, image.height))
                } finally {
                    image.close()
                }
            }
        }, handler)

        val builder = cameraDevice.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE)
        builder.addTarget(imageReader.surface)
        RequestApplier.apply(builder, params, data, still = true, region = region)
        builder.set(CaptureRequest.JPEG_ORIENTATION, orientation)
        builder.set(CaptureRequest.JPEG_QUALITY, request.jpegQuality.toInt().coerceIn(50, 100).toByte())
        request.location?.let { loc ->
            builder.set(CaptureRequest.JPEG_GPS_LOCATION, android.location.Location("doro").apply {
                latitude = loc.latitude
                longitude = loc.longitude
                loc.altitudeM?.let { altitude = it }
                loc.accuracyM?.let { accuracy = it.toFloat() }
                time = request.timestampEpochMs ?: System.currentTimeMillis()
            })
        }
        val resultDeferred = CompletableDeferred<TotalCaptureResult>()
        var startedAt = 0L
        session.capture(
            builder.build(),
            object : CameraCaptureSession.CaptureCallback() {
                override fun onCaptureStarted(s: CameraCaptureSession, r: CaptureRequest, timestamp: Long, frameNumber: Long) {
                    startedAt = timestamp
                    aligner.observeFrame(timestamp)
                }

                override fun onCaptureCompleted(s: CameraCaptureSession, r: CaptureRequest, result: TotalCaptureResult) {
                    resultDeferred.complete(result)
                }

                override fun onCaptureFailed(s: CameraCaptureSession, r: CaptureRequest, failure: CaptureFailure) {
                    resultDeferred.completeExceptionally(CameraException("capture_failed", "The camera failed to capture (reason ${failure.reason})"))
                }
            },
            handler,
        )
        val outcome = withTimeoutOrNull(CAPTURE_TIMEOUT_MS) { resultDeferred.await() to imageDeferred.await() }
            ?: throw CameraException("capture_failed", "The capture timed out")
        imageReader.setOnImageAvailableListener(null, null)
        val (result, image) = outcome
        return Shutter(image.first, image.second, image.third, startedAt, RequestApplier.read(result))
    }

    // ---- video ------------------------------------------------------------------------------------

    override suspend fun startVideo(request: VideoRequestMessage) = lock.withLock {
        ensureRunning()
        if (recordPipeline != null) throw CameraException("capture_failed", "A recording is already running")
        val caps = CapabilityProbe.video(data, env.media)
        val size = request.size ?: caps.options.maxByOrNull { it.size.width * it.size.height }?.size
            ?: throw CameraException("unsupported_configuration", "This camera cannot record video")
        val option = caps.options.firstOrNull { it.size == size }
            ?: throw CameraException("unsupported_configuration", "Video size ${size.width}x${size.height} is not supported")
        val fps = (request.fps ?: option.fps.first()).toInt()
        if (fps.toLong() !in option.fps) throw CameraException("unsupported_configuration", "$fps fps is not supported at ${size.width}x${size.height}")
        val outputFile = File(request.outputPath)
        if (outputFile.parentFile?.isDirectory != true) throw CameraException("unsupported_configuration", "Output directory does not exist")

        val orientation = Geometry.jpegOrientation(data.sensorOrientation, env.orientation.degrees, frontFacing)
        val withAudio = request.audio && audioWanted()
        // Stabilization is a per-recording choice applied through the normal settings path.
        request.stabilization?.let { settings = settings.copy(stabilization = it) }
        lateinit var pipelineRef: EncoderPipeline
        val fileRecorder = VideoFileRecorder(
            target = outputFile,
            width = size.width.toInt(),
            height = size.height.toInt(),
            orientationDegrees = orientation,
            expectsAudio = withAudio,
            formats = { pipelineRef.videoFormat to pipelineRef.audioFormat },
        )
        pipelineRef = newPipeline(size, fps, withAudio, fileRecorder::onSample)
        try {
            pipelineRef.start()
        } catch (e: Throwable) {
            fileRecorder.abort()
            throw CameraException("unsupported_configuration", "The video encoder could not start: ${e.message}", e)
        }
        recorder = fileRecorder
        recordPipeline = pipelineRef
        recordOrientation = orientation
        recordTarget = outputFile
        try {
            rebuildSession()
        } catch (e: Throwable) {
            abortRecording()
            rebuildSession()
            throw CameraException("unsupported_configuration", "The camera cannot record at ${size.width}x${size.height} with this configuration", e)
        }
        setState(SessionStateMessage.RECORDING)
        publishInfo()
    }

    private fun abortRecording() {
        recordPipeline?.stop()
        recorder?.abort()
        recordPipeline = null
        recorder = null
    }

    override suspend fun stopVideo(): VideoResultMessage = lock.withLock {
        val pipeline = recordPipeline ?: throw CameraException("capture_failed", "No recording is running")
        val fileRecorder = recorder!!
        val target = recordTarget!!
        val orientation = recordOrientation
        pipeline.stop()
        recordPipeline = null
        recorder = null
        val summary = try {
            fileRecorder.finish()
        } finally {
            if (!closed && !explicitlySuspended && !interrupted) {
                rebuildSession()
                publishInfo()
                setState(SessionStateMessage.PREVIEWING)
            }
        }
        VideoResultMessage(
            path = target.path,
            durationMs = summary.durationMs,
            width = summary.width.toLong(),
            height = summary.height.toLong(),
            hasAudio = summary.hasAudio,
            bytes = summary.bytes,
            orientationDegrees = orientation.toLong(),
            mime = "video/mp4",
        )
    }

    // ---- interruptions, suspend, resume, close ----------------------------------------------------

    /** Another app took the camera, or the device reported an error (CAM-053). Keeps the session so it can resume. */
    private fun onInterrupted(code: String, message: String) {
        if (closed || explicitlySuspended) return
        scope.launch {
            lock.withLock {
                if (interrupted) return@withLock
                interrupted = true
                releaseCameraLocked()
                emitError(code, message)
                events.emit(SessionEventMessage(sessionId, SessionEventKindMessage.INTERRUPTED, errorCode = code, errorMessage = message))
                setState(SessionStateMessage.SUSPENDED)
            }
        }
    }

    private fun releaseCameraLocked() {
        abortRecording()
        motion?.stop()
        motion = null
        captureSession?.let {
            try {
                it.stopRepeating()
            } catch (_: Exception) {
                // Already closed.
            }
            it.close()
        }
        captureSession = null
        device?.close()
        device = null
        latest = null
    }

    private suspend fun suspendLocked(explicit: Boolean) {
        if (explicit) explicitlySuspended = true else interrupted = true
        releaseCameraLocked()
        setState(SessionStateMessage.SUSPENDED)
    }

    override suspend fun suspend() = lock.withLock {
        if (closed || state == SessionStateMessage.SUSPENDED && explicitlySuspended) return@withLock
        suspendLocked(explicit = true)
    }

    override suspend fun resume() = lock.withLock {
        if (closed) throw CameraException("camera_disconnected", "The session is closed")
        if (device != null && !interrupted && !explicitlySuspended) return@withLock
        thermalState = env.thermal.state
        if (thermalState == ThermalStateMessage.CRITICAL) throw CameraException("thermal_shutdown", "The device is too hot to open the camera")
        try {
            device = openDevice()
            rebuildSession()
        } catch (e: Throwable) {
            releaseCameraLocked()
            throw e
        }
        explicitlySuspended = false
        interrupted = false
        publishInfo()
        setState(SessionStateMessage.PREVIEWING)
        events.emit(SessionEventMessage(sessionId, SessionEventKindMessage.RESUMED))
    }

    override suspend fun close() {
        withContext(Dispatchers.Default) {
            lock.withLock {
                if (closed) return@withLock
                closed = true
                teardown()
            }
        }
    }

    /** Releases every resource. Safe to call twice and from a failed [start]. */
    internal fun teardown() {
        closed = true
        env.orientation.removeListener(orientationListener)
        env.thermal.removeListener(thermalListener)
        try {
            env.manager.unregisterAvailabilityCallback(availability)
        } catch (_: Exception) {
            // Not registered.
        }
        releaseCameraLocked()
        if (::imageReader.isInitialized) imageReader.close()
        if (::previewSurface.isInitialized) previewSurface.release()
        events.emit(SessionEventMessage(sessionId, SessionEventKindMessage.STATE, state = SessionStateMessage.CLOSED))
        scope.cancel(CancellationException("session closed"))
        thread.quitSafely()
    }
}
