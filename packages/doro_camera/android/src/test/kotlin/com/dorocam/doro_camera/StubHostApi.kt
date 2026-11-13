package com.dorocam.doro_camera

/** A host API whose every method fails, so a test overrides only what it exercises. */
open class StubHostApi : CameraHostApi {
    private fun unused(): Nothing = error("not used in this test")
    override fun ping(message: String): PingResultMessage = unused()
    override fun checkPermissions(): PermissionsMessage = unused()
    override suspend fun requestPermissions(camera: Boolean, microphone: Boolean): PermissionsMessage = unused()
    override fun openAppSettings() = unused()
    override fun listCameras(): List<CameraDescriptorMessage> = unused()
    override fun getCapabilities(cameraId: String): CameraCapabilitiesMessage = unused()
    override suspend fun openSession(config: SessionConfigMessage): SessionInfoMessage = unused()
    override suspend fun closeSession(sessionId: Long) = unused()
    override suspend fun applySettings(sessionId: Long, settings: ResolvedCaptureSettingsMessage): AppliedSettingsMessage = unused()
    override suspend fun focusAt(sessionId: Long, x: Double, y: Double) = unused()
    override fun setLive(sessionId: Long, enabled: Boolean) = unused()
    override suspend fun capture(sessionId: Long, request: CaptureRequestMessage): CaptureResultMessage = unused()
    override suspend fun startVideo(sessionId: Long, request: VideoRequestMessage) = unused()
    override suspend fun stopVideo(sessionId: Long): VideoResultMessage = unused()
    override suspend fun suspendSession(sessionId: Long) = unused()
    override suspend fun resumeSession(sessionId: Long) = unused()
}
