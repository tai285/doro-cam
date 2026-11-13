package com.dorocam.doro_camera

import android.graphics.SurfaceTexture
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.CancellationException

/** A failure with a stable code from docs/specs/camera.md. Converted to a `FlutterError` at the bridge. */
class CameraException(val code: String, message: String, cause: Throwable? = null) : Exception(message, cause)

/** Preview surface handed to a session. In the app it wraps a Flutter `TextureRegistry` entry. */
interface PreviewTexture {
    val textureId: Long
    val surfaceTexture: SurfaceTexture
    fun release()
}

fun interface PreviewTextureFactory {
    fun create(): PreviewTexture
}

fun interface SessionEvents {
    fun emit(event: SessionEventMessage)
}

fun interface PermissionChecker {
    fun check(): PermissionsMessage
}

/** One open camera session of a backend. All methods follow the contract in docs/specs/camera.md. */
interface BackendSession {
    val info: SessionInfoMessage
    suspend fun applySettings(settings: ResolvedCaptureSettingsMessage): AppliedSettingsMessage
    suspend fun focusAt(x: Double, y: Double)
    fun setLive(enabled: Boolean)
    suspend fun capture(request: CaptureRequestMessage): CaptureResultMessage
    suspend fun startVideo(request: VideoRequestMessage)
    suspend fun stopVideo(): VideoResultMessage
    suspend fun suspend()
    suspend fun resume()
    suspend fun close()
}

/** A source of cameras: real Camera2 hardware, or the synthetic test camera in debug builds (ADR-0013). */
interface CameraBackend {
    fun owns(cameraId: String): Boolean
    fun listCameras(): List<CameraDescriptorMessage>
    fun capabilities(cameraId: String): CameraCapabilitiesMessage
    suspend fun open(
        sessionId: Long,
        config: SessionConfigMessage,
        texture: PreviewTexture,
        events: SessionEvents,
        audioAllowed: Boolean,
    ): BackendSession
}

/**
 * The plugin's brain behind the Pigeon bridge: routes camera ids to backends, enforces permissions,
 * keeps the session registry and converts every failure into the documented error codes. It has no
 * Flutter or Android dependencies beyond [SurfaceTexture] so it runs in plain JVM tests with fakes.
 */
class CameraService(
    private val backends: List<CameraBackend>,
    private val textures: PreviewTextureFactory,
    private val permissions: PermissionChecker,
    private val events: SessionEvents,
) {
    private class Entry(val session: BackendSession, val texture: PreviewTexture)

    private val nextId = AtomicLong(1)
    private val sessions = HashMap<Long, Entry>()

    val openSessionCount: Int get() = synchronized(sessions) { sessions.size }

    fun listCameras(): List<CameraDescriptorMessage> = backends.flatMap { it.listCameras() }

    private fun backendFor(cameraId: String): CameraBackend =
        backends.firstOrNull { it.owns(cameraId) } ?: throw CameraException("unsupported_configuration", "Unknown camera $cameraId")

    fun capabilities(cameraId: String): CameraCapabilitiesMessage = backendFor(cameraId).capabilities(cameraId)

    private fun entry(sessionId: Long): Entry =
        synchronized(sessions) { sessions[sessionId] } ?: throw CameraException("camera_disconnected", "Session $sessionId is not open")

    suspend fun openSession(config: SessionConfigMessage): SessionInfoMessage {
        val granted = permissions.check()
        when (granted.camera) {
            PermissionStatusMessage.GRANTED -> Unit
            PermissionStatusMessage.RESTRICTED -> throw CameraException("permission_restricted", "Camera access is restricted on this device")
            else -> throw CameraException("permission_denied", "Camera permission was not granted")
        }
        val backend = backendFor(config.cameraId)
        val id = nextId.getAndIncrement()
        val texture = textures.create()
        try {
            val session = backend.open(id, config, texture, events, audioAllowed = granted.microphone == PermissionStatusMessage.GRANTED)
            synchronized(sessions) { sessions[id] = Entry(session, texture) }
            return session.info
        } catch (e: Throwable) {
            texture.release()
            throw e
        }
    }

    suspend fun closeSession(sessionId: Long) {
        val removed = synchronized(sessions) { sessions.remove(sessionId) } ?: return
        try {
            removed.session.close()
        } finally {
            removed.texture.release()
        }
    }

    /** Closes everything, for example when the Flutter engine detaches. */
    suspend fun closeAll() {
        val ids = synchronized(sessions) { sessions.keys.toList() }
        for (id in ids) {
            try {
                closeSession(id)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                // Closing is best effort: one failing session must not keep the others open.
            }
        }
    }

    suspend fun applySettings(sessionId: Long, settings: ResolvedCaptureSettingsMessage): AppliedSettingsMessage =
        entry(sessionId).session.applySettings(settings)

    suspend fun focusAt(sessionId: Long, x: Double, y: Double) {
        if (x !in 0.0..1.0 || y !in 0.0..1.0) throw CameraException("unsupported_configuration", "Focus point must be within 0..1")
        entry(sessionId).session.focusAt(x, y)
    }

    fun setLive(sessionId: Long, enabled: Boolean) = entry(sessionId).session.setLive(enabled)

    suspend fun capture(sessionId: Long, request: CaptureRequestMessage): CaptureResultMessage =
        entry(sessionId).session.capture(request)

    suspend fun startVideo(sessionId: Long, request: VideoRequestMessage) = entry(sessionId).session.startVideo(request)

    suspend fun stopVideo(sessionId: Long): VideoResultMessage = entry(sessionId).session.stopVideo()

    suspend fun suspendSession(sessionId: Long) = entry(sessionId).session.suspend()

    suspend fun resumeSession(sessionId: Long) = entry(sessionId).session.resume()

    companion object {
        /** Converts any failure to the error crossing the bridge: a [FlutterError] with a stable code. */
        fun toFlutterError(error: Throwable): Throwable = when (error) {
            is FlutterError -> error
            is CameraException -> FlutterError(error.code, error.message, null)
            else -> FlutterError("capture_failed", error.message ?: error.javaClass.simpleName, null)
        }
    }
}
