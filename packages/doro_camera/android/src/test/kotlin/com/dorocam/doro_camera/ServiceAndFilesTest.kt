package com.dorocam.doro_camera

import android.graphics.SurfaceTexture
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking

// ---------- fakes ----------

private class FakePlatform : PermissionPlatform {
    val granted = mutableSetOf<String>()
    val requested = mutableSetOf<String>()
    var rationale = false
    var policyDisabled = false
    var activity = true
    var requestedArgs: List<String>? = null
    var settingsOpened = false
    var onRequest: (() -> Unit)? = null
    override fun isGranted(permission: String) = permission in granted
    override fun shouldShowRationale(permission: String) = rationale
    override fun wasRequestedBefore(permission: String) = permission in requested
    override fun markRequested(permission: String) { requested += permission }
    override fun cameraDisabledByPolicy() = policyDisabled
    override fun hasActivity() = activity
    override fun request(permissions: Array<String>, code: Int) { requestedArgs = permissions.toList(); onRequest?.invoke() }
    override fun openSettings() { settingsOpened = true }
}

private fun grantedPermissions(camera: PermissionStatusMessage = PermissionStatusMessage.GRANTED, mic: PermissionStatusMessage = PermissionStatusMessage.GRANTED) =
    PermissionsMessage(camera, mic, false, false)

private class FakeSession(override val info: SessionInfoMessage) : BackendSession {
    val calls = mutableListOf<String>()
    var closeFails = false
    override suspend fun applySettings(settings: ResolvedCaptureSettingsMessage): AppliedSettingsMessage {
        calls += "apply"
        return AppliedSettingsMessage(aeLocked = false, afLocked = false, zoomRatio = settings.zoomRatio, mismatches = emptyList(), iso = settings.iso)
    }
    override suspend fun focusAt(x: Double, y: Double) { calls += "focus:$x,$y" }
    override fun setLive(enabled: Boolean) { calls += "live:$enabled" }
    override suspend fun capture(request: CaptureRequestMessage): CaptureResultMessage = throw CameraException("storage_full", "disk full")
    override suspend fun startVideo(request: VideoRequestMessage) { calls += "startVideo" }
    override suspend fun stopVideo(): VideoResultMessage = VideoResultMessage("/x.mp4", 1, 2, 3, false, 4, 0, "video/mp4")
    override suspend fun suspend() { calls += "suspend" }
    override suspend fun resume() { calls += "resume" }
    override suspend fun close() { calls += "close"; if (closeFails) error("close failed") }
}

private class FakeBackend(private val prefix: String) : CameraBackend {
    val sessions = mutableListOf<FakeSession>()
    var openError: Throwable? = null
    var lastAudioAllowed: Boolean? = null
    override fun owns(cameraId: String) = cameraId.startsWith(prefix)
    override fun listCameras() = listOf(
        CameraDescriptorMessage("${prefix}0", CameraFacingMessage.BACK, LensKindMessage.WIDE, false, emptyList(), 90, CameraSourceMessage.HARDWARE, "Back camera"),
    )
    override fun capabilities(cameraId: String) = CapabilityProbe.capabilities(Fixtures.full(cameraId), Fixtures.media)
    override suspend fun open(sessionId: Long, config: SessionConfigMessage, texture: PreviewTexture, events: SessionEvents, audioAllowed: Boolean): BackendSession {
        openError?.let { throw it }
        lastAudioAllowed = audioAllowed
        val info = SessionInfoMessage(
            sessionId, texture.textureId, config.cameraId, SizeMessage(640, 480), SizeMessage(4000, 3000), config.photoFormat, 90,
            CameraSourceMessage.HARDWARE, config.live, config.audio,
        )
        return FakeSession(info).also { sessions += it }
    }
}

private class FakeTexture(override val textureId: Long) : PreviewTexture {
    var released = false
    override val surfaceTexture: SurfaceTexture get() = throw UnsupportedOperationException("not needed by the fake backend")
    override fun release() { released = true }
}

private fun config(id: String) = SessionConfigMessage(id, PhotoFormatMessage.JPEG, live = false, audio = false)

// ---------- tests ----------

internal class PermissionControllerTest {
    private val platform = FakePlatform()
    private val controller = PermissionController(platform)

    // [CAM-052]
    @Test
    fun `before anything is asked the status is not determined and nothing is permanently denied`() {
        val s = controller.check()
        assertEquals(PermissionStatusMessage.NOT_DETERMINED, s.camera)
        assertEquals(PermissionStatusMessage.NOT_DETERMINED, s.microphone)
        assertFalse(s.cameraPermanentlyDenied)
    }

    @Test
    fun `granted permissions are reported as granted`() {
        platform.granted += listOf(PermissionController.CAMERA, PermissionController.MICROPHONE)
        val s = controller.check()
        assertEquals(PermissionStatusMessage.GRANTED, s.camera)
        assertEquals(PermissionStatusMessage.GRANTED, s.microphone)
    }

    // [CAM-052]
    @Test
    fun `denied after asking with no rationale means the dialog will not show again`() {
        platform.requested += PermissionController.CAMERA
        platform.rationale = false
        assertTrue(controller.check().cameraPermanentlyDenied)
        assertEquals(PermissionStatusMessage.DENIED, controller.check().camera)
        platform.rationale = true // the user can still be asked once more
        assertFalse(controller.check().cameraPermanentlyDenied)
    }

    @Test
    fun `a device policy disabling the camera is reported as restricted, not as a denial`() {
        platform.policyDisabled = true
        assertEquals(PermissionStatusMessage.RESTRICTED, controller.check().camera)
        platform.granted += PermissionController.CAMERA
        assertEquals(PermissionStatusMessage.GRANTED, controller.check().camera)
    }

    @Test
    fun `requesting asks only for what is missing and returns the new status after the answer`() = runBlocking {
        platform.granted += PermissionController.MICROPHONE
        platform.onRequest = {
            platform.granted += PermissionController.CAMERA
            controller.onResult(PermissionController.REQUEST_CODE)
        }
        val result = controller.request(camera = true, microphone = true)
        assertEquals(listOf(PermissionController.CAMERA), platform.requestedArgs)
        assertEquals(PermissionStatusMessage.GRANTED, result.camera)
        assertTrue(PermissionController.CAMERA in platform.requested)
    }

    @Test
    fun `requesting something already granted shows no dialog`() = runBlocking {
        platform.granted += PermissionController.CAMERA
        val result = controller.request(camera = true, microphone = false)
        assertEquals(null, platform.requestedArgs)
        assertEquals(PermissionStatusMessage.GRANTED, result.camera)
    }

    @Test
    fun `a denial leaves the status denied`() = runBlocking {
        platform.onRequest = { controller.onResult(PermissionController.REQUEST_CODE) }
        val result = controller.request(camera = true, microphone = false)
        assertEquals(PermissionStatusMessage.DENIED, result.camera)
    }

    @Test
    fun `no foreground activity means the request cannot be shown`() {
        platform.activity = false
        val error = assertFailsWith<CameraException> { runBlocking { controller.request(true, false) } }
        assertEquals("permission_denied", error.code)
    }

    @Test
    fun `results for other request codes are ignored and settings can be opened`() {
        assertFalse(controller.onResult(1))
        assertTrue(controller.onResult(PermissionController.REQUEST_CODE))
        controller.openSettings()
        assertTrue(platform.settingsOpened)
    }

    @Test
    fun `a newer request supersedes a pending one`() = runBlocking {
        val first = async { controller.request(true, false) }
        kotlinx.coroutines.yield()
        platform.onRequest = { controller.onResult(PermissionController.REQUEST_CODE) }
        val second = controller.request(true, false)
        assertEquals(PermissionStatusMessage.DENIED, second.camera)
        assertTrue(runCatching { first.await() }.isFailure)
    }
}

internal class CameraServiceTest {
    private val permissionsFlow = arrayOf(grantedPermissions())
    private val hardware = FakeBackend("hw:")
    private val synthetic = FakeBackend("syn:")
    private val textures = mutableListOf<FakeTexture>()
    private val emitted = mutableListOf<SessionEventMessage>()
    private val service = CameraService(
        listOf(hardware, synthetic),
        { FakeTexture(textures.size + 100L).also { textures += it } },
        { permissionsFlow[0] },
        { emitted += it },
    )

    // [CAM-004]
    @Test
    fun `cameras of every backend are listed and routed by id`() {
        assertEquals(listOf("hw:0", "syn:0"), service.listCameras().map { it.id })
        assertEquals("hw:7", service.capabilities("hw:7").cameraId)
        val error = assertFailsWith<CameraException> { service.capabilities("nope") }
        assertEquals("unsupported_configuration", error.code)
    }

    // [CAM-052]
    @Test
    fun `opening without camera permission is refused with a typed error and no texture is leaked`() {
        permissionsFlow[0] = grantedPermissions(camera = PermissionStatusMessage.DENIED)
        assertEquals("permission_denied", assertFailsWith<CameraException> { runBlocking { service.openSession(config("hw:0")) } }.code)
        permissionsFlow[0] = grantedPermissions(camera = PermissionStatusMessage.NOT_DETERMINED)
        assertEquals("permission_denied", assertFailsWith<CameraException> { runBlocking { service.openSession(config("hw:0")) } }.code)
        permissionsFlow[0] = grantedPermissions(camera = PermissionStatusMessage.RESTRICTED)
        assertEquals("permission_restricted", assertFailsWith<CameraException> { runBlocking { service.openSession(config("hw:0")) } }.code)
        assertTrue(textures.isEmpty())
        assertEquals(0, service.openSessionCount)
    }

    // [MOT-003]
    @Test
    fun `without microphone permission the backend is told audio is not allowed`() = runBlocking {
        permissionsFlow[0] = grantedPermissions(mic = PermissionStatusMessage.DENIED)
        service.openSession(config("hw:0"))
        assertEquals(false, hardware.lastAudioAllowed)
        permissionsFlow[0] = grantedPermissions()
        service.openSession(config("hw:0"))
        assertEquals(true, hardware.lastAudioAllowed)
    }

    @Test
    fun `a failing open releases its texture and keeps the registry clean`() = runBlocking {
        hardware.openError = CameraException("camera_in_use", "busy")
        val error = assertFailsWith<CameraException> { service.openSession(config("hw:0")) }
        assertEquals("camera_in_use", error.code)
        assertTrue(textures.single().released)
        assertEquals(0, service.openSessionCount)
    }

    @Test
    fun `a session lives until closed, close is idempotent and releases the texture`() = runBlocking {
        val info = service.openSession(config("hw:0"))
        assertEquals(1, service.openSessionCount)
        assertEquals(info.textureId, textures.single().textureId)
        service.closeSession(info.sessionId)
        service.closeSession(info.sessionId)
        assertEquals(0, service.openSessionCount)
        assertTrue(textures.single().released)
        assertEquals(listOf("close"), hardware.sessions.single().calls)
    }

    @Test
    fun `session ids are unique`() = runBlocking {
        val a = service.openSession(config("hw:0")).sessionId
        val b = service.openSession(config("syn:0")).sessionId
        assertTrue(a != b)
        assertEquals(1, hardware.sessions.size)
        assertEquals(1, synthetic.sessions.size)
    }

    @Test
    fun `calls on an unknown session answer camera_disconnected`() {
        val error = assertFailsWith<CameraException> { runBlocking { service.applySettings(99, Fixtures.settings()) } }
        assertEquals("camera_disconnected", error.code)
        assertFailsWith<CameraException> { service.setLive(99, true) }
        assertFailsWith<CameraException> { runBlocking { service.capture(99, captureRequest()) } }
    }

    @Test
    fun `calls are delegated to the session`() = runBlocking {
        val id = service.openSession(config("hw:0")).sessionId
        val applied = service.applySettings(id, Fixtures.settings(iso = 400))
        assertEquals(400L, applied.iso)
        service.focusAt(id, 0.25, 0.75)
        service.setLive(id, true)
        service.startVideo(id, VideoRequestMessage(outputPath = "/x.mp4", audio = false))
        assertEquals("/x.mp4", service.stopVideo(id).path)
        service.suspendSession(id)
        service.resumeSession(id)
        assertEquals(listOf("apply", "focus:0.25,0.75", "live:true", "startVideo", "suspend", "resume"), hardware.sessions.single().calls)
    }

    @Test
    fun `a focus point outside the preview is rejected before reaching the camera`() = runBlocking {
        val id = service.openSession(config("hw:0")).sessionId
        for ((x, y) in listOf(-0.1 to 0.5, 0.5 to 1.1, 2.0 to 2.0)) {
            assertEquals("unsupported_configuration", assertFailsWith<CameraException> { service.focusAt(id, x, y) }.code)
        }
        assertTrue(hardware.sessions.single().calls.isEmpty())
    }

    @Test
    fun `closing everything is best effort`() = runBlocking {
        val a = service.openSession(config("hw:0"))
        service.openSession(config("hw:0"))
        hardware.sessions.first().closeFails = true
        service.closeAll()
        assertEquals(0, service.openSessionCount)
        assertTrue(textures.all { it.released })
        assertNotNull(a)
    }

    // docs/specs/camera.md errors
    @Test
    fun `failures cross the bridge with stable codes`() {
        val coded = CameraService.toFlutterError(CameraException("storage_full", "full")) as FlutterError
        assertEquals("storage_full", coded.code)
        assertEquals("full", coded.message)
        val passthrough = FlutterError("x", "y", null)
        assertTrue(CameraService.toFlutterError(passthrough) === passthrough)
        val unknown = CameraService.toFlutterError(IllegalStateException("boom")) as FlutterError
        assertEquals("capture_failed", unknown.code)
        assertEquals("boom", unknown.message)
        assertEquals("RuntimeException", (CameraService.toFlutterError(RuntimeException()) as FlutterError).message)
    }

    private fun captureRequest() = CaptureRequestMessage(memoryId = "m", outputDir = "/tmp", originalName = "o", renderedName = "r", thumbnailName = "t", displayName = "d", live = false, preRollMs = 1500, postRollMs = 1500, jpegQuality = 95)
}

internal class AtomicFilesTest {
    private fun tempDir(): File = java.nio.file.Files.createTempDirectory("doro").toFile().also { it.deleteOnExit() }

    // [NFR-002]
    @Test
    fun `writing is atomic - the final file appears complete and no temp file remains`() {
        val dir = tempDir()
        val target = AtomicFiles.target(dir.path, "photo.jpg")
        AtomicFiles.write(target, byteArrayOf(1, 2, 3, 4))
        assertEquals(listOf<Byte>(1, 2, 3, 4), target.readBytes().toList())
        assertEquals(listOf("photo.jpg"), dir.list()!!.toList())
        // overwriting replaces the content
        AtomicFiles.write(target, byteArrayOf(9))
        assertEquals(listOf<Byte>(9), target.readBytes().toList())
    }

    @Test
    fun `a streamed write is committed the same way`() {
        val dir = tempDir()
        val target = AtomicFiles.target(dir.path, "clip.mp4")
        AtomicFiles.write(target) { it.write(ByteArray(1000) { i -> i.toByte() }) }
        assertEquals(1000, target.length())
        assertEquals(listOf("clip.mp4"), dir.list()!!.toList())
    }

    @Test
    fun `a failing streamed write leaves no partial file`() {
        val dir = tempDir()
        val target = AtomicFiles.target(dir.path, "broken.mp4")
        val error = assertFailsWith<CameraException> {
            AtomicFiles.write(target) { throw java.io.IOException("No space left on device (ENOSPC)") }
        }
        assertEquals("storage_full", error.code)
        assertTrue(dir.list()!!.isEmpty())
    }

    @Test
    fun `I-O errors map to storage_full or capture_failed`() {
        assertEquals("storage_full", AtomicFiles.ioToCamera(java.io.IOException("write failed: ENOSPC")).code)
        assertEquals("storage_full", AtomicFiles.ioToCamera(java.io.IOException("No space left on device")).code)
        assertEquals("capture_failed", AtomicFiles.ioToCamera(java.io.IOException("permission denied")).code)
        assertEquals("capture_failed", AtomicFiles.ioToCamera(java.io.IOException()).code)
    }

    // security: names can never escape the output directory
    @Test
    fun `file names are validated and the directory must exist`() {
        val dir = tempDir()
        for (bad in listOf("", ".", "..", "../evil", "a/b", "a\\b", "x..y")) {
            assertEquals("unsupported_configuration", assertFailsWith<CameraException> { AtomicFiles.target(dir.path, bad) }.code, "name '$bad'")
        }
        assertEquals("unsupported_configuration", assertFailsWith<CameraException> { AtomicFiles.target(File(dir, "missing").path, "a.jpg") }.code)
        assertEquals(File(dir, "ok.jpg"), AtomicFiles.target(dir.path, "ok.jpg"))
    }

    // docs/specs/camera.md edge case: app kill during capture
    @Test
    fun `leftovers of an interrupted capture are cleaned up`() {
        val dir = tempDir()
        File(dir, "a.jpg.doro-tmp").writeText("partial")
        File(dir, "b.mp4.doro-tmp").writeText("partial")
        File(dir, "keep.jpg").writeText("done")
        assertEquals(2, AtomicFiles.cleanStale(dir))
        assertEquals(listOf("keep.jpg"), dir.list()!!.toList())
        File(dir, "recent.doro-tmp").writeText("x")
        assertEquals(0, AtomicFiles.cleanStale(dir, olderThanMs = 60_000))
        assertEquals(0, AtomicFiles.cleanStale(File(dir, "missing")))
    }

    @Test
    fun `committing over an existing file replaces it`() {
        val dir = tempDir()
        val target = File(dir, "x")
        target.writeText("old")
        val temp = AtomicFiles.tempFor(target)
        temp.writeText("new")
        AtomicFiles.commit(temp, target)
        assertEquals("new", target.readText())
    }
}

internal class CompletableDeferredSanityTest {
    @Test
    fun `OpenTarget parses logical and physical ids`() {
        assertEquals(OpenTarget("0", null), OpenTarget.parse("0"))
        assertEquals(OpenTarget("0", "2"), OpenTarget.parse("0#2"))
        assertEquals(CompletableDeferred<Int>().isCompleted, false)
    }
}
