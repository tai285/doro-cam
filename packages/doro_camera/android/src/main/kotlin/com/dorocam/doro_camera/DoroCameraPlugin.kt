package com.dorocam.doro_camera

import android.app.Activity
import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.view.TextureRegistry
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Android side of the Doro Cam camera plugin. It only does hardware work: product logic such as
 * scenarios, presets and intent resolution lives in Dart (ADR-0001). Every call goes through
 * [CameraService], which converts failures into the documented error codes.
 */
class DoroCameraPlugin(
    private val environment: PlatformEnvironment = SystemPlatformEnvironment,
) : FlutterPlugin, ActivityAware, CameraHostApi {
    private var messenger: BinaryMessenger? = null
    private var service: CameraService? = null
    private var permissions: PermissionController? = null
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    // ---- FlutterPlugin / ActivityAware ----

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val context = binding.applicationContext
        attach(binding.binaryMessenger)
        permissions = PermissionController(AndroidPermissionPlatform(context) { activity })
        service = buildService(context, binding.textureRegistry, binding.binaryMessenger)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val closing = service
        service = null
        if (closing != null) scope.launch { closing.closeAll() }
        detach()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addRequestPermissionsResultListener { requestCode, _, _ -> permissions?.onResult(requestCode) ?: false }
    }

    override fun onDetachedFromActivity() {
        activity = null
        activityBinding = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    private fun buildService(context: Context, textures: TextureRegistry, binaryMessenger: BinaryMessenger): CameraService {
        val orientation = OrientationMonitor(context)
        val thermal = ThermalMonitor(context) { runnable -> scope.launch { runnable.run() } }
        val eventsApi = CameraEventsApi(binaryMessenger)
        val events = SessionEvents { event -> scope.launch { runCatching { eventsApi.onSessionEvent(event) } } }
        val backends = listOfNotNull(
            Camera2Backend.create(context, orientation, thermal),
            SyntheticCameraBuild.createBackend(context, orientation),
        )
        val textureFactory = PreviewTextureFactory {
            val entry = textures.createSurfaceTexture()
            object : PreviewTexture {
                override val textureId: Long = entry.id()
                override val surfaceTexture = entry.surfaceTexture()
                override fun release() = entry.release()
            }
        }
        return CameraService(backends, textureFactory, requireNotNull(permissions), events)
    }

    // ---- wiring (also used by JVM tests, which pass a fake messenger) ----

    internal fun attach(binaryMessenger: BinaryMessenger) {
        messenger = binaryMessenger
        CameraHostApi.setUp(binaryMessenger, this)
    }

    internal fun detach() {
        messenger?.let { CameraHostApi.setUp(it, null) }
        messenger = null
    }

    /** Test seam: inject the service and permission controller without a Flutter engine. */
    internal fun install(service: CameraService, permissions: PermissionController) {
        this.service = service
        this.permissions = permissions
    }

    private fun requireService(): CameraService = service ?: throw FlutterError("camera_disconnected", "The camera plugin is not attached", null)

    private fun requirePermissions(): PermissionController = permissions ?: throw FlutterError("camera_disconnected", "The camera plugin is not attached", null)

    private suspend fun <T> guarded(block: suspend () -> T): T = try {
        block()
    } catch (e: CancellationException) {
        throw e
    } catch (e: Throwable) {
        throw CameraService.toFlutterError(e)
    }

    // ---- CameraHostApi ----

    override fun ping(message: String): PingResultMessage =
        PingResultMessage(
            echo = message,
            platform = "android",
            osVersion = environment.osVersion,
            syntheticCameraCompiledIn = SyntheticCameraBuild.isCompiledIn,
        )

    override fun checkPermissions(): PermissionsMessage = requirePermissions().check()

    override suspend fun requestPermissions(camera: Boolean, microphone: Boolean): PermissionsMessage =
        guarded { requirePermissions().request(camera, microphone) }

    override fun openAppSettings() = requirePermissions().openSettings()

    override fun listCameras(): List<CameraDescriptorMessage> = try {
        requireService().listCameras()
    } catch (e: Throwable) {
        throw CameraService.toFlutterError(e)
    }

    override fun getCapabilities(cameraId: String): CameraCapabilitiesMessage = try {
        requireService().capabilities(cameraId)
    } catch (e: Throwable) {
        throw CameraService.toFlutterError(e)
    }

    override suspend fun openSession(config: SessionConfigMessage): SessionInfoMessage = guarded { requireService().openSession(config) }

    override suspend fun closeSession(sessionId: Long) = guarded { requireService().closeSession(sessionId) }

    override suspend fun applySettings(sessionId: Long, settings: ResolvedCaptureSettingsMessage): AppliedSettingsMessage =
        guarded { requireService().applySettings(sessionId, settings) }

    override suspend fun focusAt(sessionId: Long, x: Double, y: Double) = guarded { requireService().focusAt(sessionId, x, y) }

    override fun setLive(sessionId: Long, enabled: Boolean) {
        try {
            requireService().setLive(sessionId, enabled)
        } catch (e: Throwable) {
            throw CameraService.toFlutterError(e)
        }
    }

    override suspend fun capture(sessionId: Long, request: CaptureRequestMessage): CaptureResultMessage =
        guarded { requireService().capture(sessionId, request) }

    override suspend fun startVideo(sessionId: Long, request: VideoRequestMessage) = guarded { requireService().startVideo(sessionId, request) }

    override suspend fun stopVideo(sessionId: Long): VideoResultMessage = guarded { requireService().stopVideo(sessionId) }

    override suspend fun suspendSession(sessionId: Long) = guarded { requireService().suspendSession(sessionId) }

    override suspend fun resumeSession(sessionId: Long) = guarded { requireService().resumeSession(sessionId) }
}
