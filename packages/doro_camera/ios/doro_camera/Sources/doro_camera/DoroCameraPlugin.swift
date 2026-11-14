import AVFoundation
import DoroCameraCore
import Flutter
import UIKit

/// iOS side of the Doro Cam camera plugin. It only does hardware work: product logic such as
/// scenarios, presets and intent resolution lives in Dart (ADR-0001). Everything with a branch worth
/// testing lives in DoroCameraCore; this class converts messages and owns the open sessions.
public class DoroCameraPlugin: NSObject, FlutterPlugin, CameraHostApi {
    private let registrar: FlutterPluginRegistrar
    private let events: CameraEventsApi
    private let pingResponder = PingResponder()
    private let lock = NSLock()
    private var sessions: [Int64: CameraSession] = [:]
    private var nextSessionId: Int64 = 1

    init(registrar: FlutterPluginRegistrar) {
        self.registrar = registrar
        self.events = CameraEventsApi(binaryMessenger: registrar.messenger())
        super.init()
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = DoroCameraPlugin(registrar: registrar)
        CameraHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance)
    }

    // MARK: ping

    func ping(message: String) throws -> PingResultMessage {
        let response = pingResponder.respond(to: message)
        return PingResultMessage(
            echo: response.echo,
            platform: response.platform,
            osVersion: response.osVersion,
            syntheticCameraCompiledIn: response.syntheticCameraCompiledIn
        )
    }

    // MARK: permissions (CAM-052)

    private static func state(for type: AVMediaType) -> AuthorizationState {
        switch AVCaptureDevice.authorizationStatus(for: type) {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        default: return .notDetermined
        }
    }

    func checkPermissions() throws -> PermissionsMessage {
        let camera = Self.state(for: .video)
        let microphone = Self.state(for: .audio)
        return PermissionsMessage(
            camera: PermissionStatusMessage(camera),
            microphone: PermissionStatusMessage(microphone),
            // iOS never shows the system dialog a second time: a denial always needs the Settings app.
            cameraPermanentlyDenied: camera == .denied || camera == .restricted,
            microphonePermanentlyDenied: microphone == .denied || microphone == .restricted
        )
    }

    func requestPermissions(camera: Bool, microphone: Bool) async throws -> PermissionsMessage {
        if camera, Self.state(for: .video) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        if microphone, Self.state(for: .audio) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
        return try checkPermissions()
    }

    func openAppSettings() throws {
        DispatchQueue.main.async {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
    }

    // MARK: cameras and capabilities

    func listCameras() throws -> [CameraDescriptorMessage] {
        let devices = DeviceDiscovery.devices()
        var result: [CameraDescriptorMessage] = []
        for device in devices {
            let facts = DeviceFacts(device: device, photoOutput: nil)
            result.append(CameraDescriptorMessage(CapabilityProbe.descriptor(for: facts), label: DeviceDiscovery.label(for: facts)))
        }
        #if DOROCAM_SYNTHETIC_CAMERA
        // Debug builds always offer the labelled synthetic camera next to real hardware (ADR-0013), so
        // tests and the Simulator (which has no camera) can capture without a device.
        result.append(CameraDescriptorMessage(SyntheticCamera.descriptor(), label: "Synthetic test camera"))
        #endif
        return result
    }

    /// Facts for a camera, probed with a throwaway (never started) session so photo codecs and RAW formats are real.
    private func probe(device: AVCaptureDevice) -> (DeviceFacts, [StabilizationModeMessage]) {
        let probeSession = AVCaptureSession()
        let output = AVCapturePhotoOutput()
        probeSession.beginConfiguration()
        probeSession.sessionPreset = .photo
        if let input = try? AVCaptureDeviceInput(device: device), probeSession.canAddInput(input) { probeSession.addInput(input) }
        if probeSession.canAddOutput(output) { probeSession.addOutput(output) }
        probeSession.commitConfiguration()
        let facts = DeviceFacts(device: device, photoOutput: output)
        var stabilization: [StabilizationModeMessage] = [.off]
        if device.activeFormat.isVideoStabilizationModeSupported(.standard) { stabilization.append(.standard) }
        if device.activeFormat.isVideoStabilizationModeSupported(.cinematic) { stabilization.append(.optical) }
        return (facts, stabilization)
    }

    func getCapabilities(cameraId: String) throws -> CameraCapabilitiesMessage {
        #if DOROCAM_SYNTHETIC_CAMERA
        if cameraId == SyntheticCamera.cameraId {
            return CameraCapabilitiesMessage(
                cameraId: cameraId, SyntheticCamera.capabilities(), stabilizationVideo: [.off], videoSize: PixelSize(width: 216, height: 288), videoFps: 30
            )
        }
        #endif
        guard let device = DeviceDiscovery.device(id: cameraId) else {
            throw CameraError(.cameraDisconnected, "That camera is not available.").pigeon
        }
        let (facts, stabilization) = probe(device: device)
        return CameraCapabilitiesMessage(
            cameraId: cameraId, CapabilityProbe.capabilities(for: facts),
            stabilizationVideo: stabilization, videoSize: PixelSize(width: 1080, height: 1440), videoFps: 30
        )
    }

    // MARK: sessions

    private func session(_ id: Int64) throws -> CameraSession {
        lock.lock()
        defer { lock.unlock() }
        guard let session = sessions[id] else {
            throw CameraError(.cameraDisconnected, "The camera session is closed.").pigeon
        }
        return session
    }

    private func send(_ event: SessionEventMessage) {
        let target = events
        Task { @MainActor in
            try? await target.onSessionEvent(event: event)
        }
    }

    /// Runs a body and turns a CameraError into the bridge's error type (stable code plus message).
    private func translating<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as CameraError {
            throw error.pigeon
        }
    }

    func openSession(config: SessionConfigMessage) async throws -> SessionInfoMessage {
        try await translating {
            var camera = Self.state(for: .video)
            if camera == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .video)
                camera = Self.state(for: .video)
            }
            if let error = PermissionEvaluation.cameraError(for: camera) { throw error }

            let resolved: (CameraBackend, CameraDescriptor, CameraCapabilities)
            #if DOROCAM_SYNTHETIC_CAMERA
            if config.cameraId == SyntheticCamera.cameraId {
                resolved = (.synthetic, SyntheticCamera.descriptor(), SyntheticCamera.capabilities())
            } else {
                resolved = try hardwareSetup(cameraId: config.cameraId)
            }
            #else
            resolved = try hardwareSetup(cameraId: config.cameraId)
            #endif
            let (backend, descriptor, capabilities) = resolved

            // The format actually used can differ from the request (typed fallback, docs/specs/camera.md).
            var format = config.photoFormat.core
            if !capabilities.photoFormats.contains(format) { format = capabilities.photoFormats.first ?? .jpeg }

            lock.lock()
            let id = nextSessionId
            nextSessionId += 1
            lock.unlock()

            let texture = PreviewTexture(registry: registrar.textures())
            let setup = SessionSetup(
                id: id, cameraId: config.cameraId, backend: backend, descriptor: descriptor, capabilities: capabilities,
                photoFormat: format, live: config.live && capabilities.live.supported, wantsAudio: config.audio,
                microphone: Self.state(for: .audio),
                requestedPhotoSize: config.photoSize.map { PixelSize(width: Int($0.width), height: Int($0.height)) }
            )
            let created = CameraSession(setup: setup, texture: texture) { [weak self] event in self?.send(event) }
            do {
                try await created.open()
            } catch {
                await created.close()
                texture.dispose()
                throw error
            }
            lock.lock()
            sessions[id] = created
            lock.unlock()

            let flags = created.info
            return SessionInfoMessage(
                sessionId: id,
                textureId: texture.textureId,
                cameraId: config.cameraId,
                previewSize: SizeMessage(created.previewSize),
                photoSize: SizeMessage(created.photoSize),
                photoFormat: PhotoFormatMessage(format),
                sensorOrientation: 0, // frames are delivered upright in portrait (see CameraSession)
                source: CameraSourceMessage(descriptor.source),
                liveActive: flags.liveActive,
                audioActive: flags.audioActive
            )
        }
    }

    private func hardwareSetup(cameraId: String) throws -> (CameraBackend, CameraDescriptor, CameraCapabilities) {
        guard let device = DeviceDiscovery.device(id: cameraId) else {
            throw CameraError(.cameraDisconnected, "That camera is not available.")
        }
        let (facts, _) = probe(device: device)
        return (.hardware(device), CapabilityProbe.descriptor(for: facts), CapabilityProbe.capabilities(for: facts))
    }

    func closeSession(sessionId: Int64) async throws {
        lock.lock()
        let session = sessions.removeValue(forKey: sessionId)
        lock.unlock()
        await session?.close() // idempotent: a second call finds nothing
    }

    func applySettings(sessionId: Int64, settings: ResolvedCaptureSettingsMessage) async throws -> AppliedSettingsMessage {
        let target = try session(sessionId)
        return try await translating { try await target.apply(settings: RequestedSettings(settings)) }
    }

    func focusAt(sessionId: Int64, x: Double, y: Double) async throws {
        let target = try session(sessionId)
        try await translating { try await target.focus(at: CGPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1))) }
    }

    func setLive(sessionId: Int64, enabled: Bool) throws {
        try session(sessionId).setLive(enabled)
    }

    func capture(sessionId: Int64, request: CaptureRequestMessage) async throws -> CaptureResultMessage {
        let target = try session(sessionId)
        return try await translating { try await target.capture(request) }
    }

    func startVideo(sessionId: Int64, request: VideoRequestMessage) async throws {
        let target = try session(sessionId)
        let directory = URL(fileURLWithPath: request.outputPath).deletingLastPathComponent()
        try await translating { try await target.startVideo(request, directory: directory) }
    }

    func stopVideo(sessionId: Int64) async throws -> VideoResultMessage {
        let target = try session(sessionId)
        return try await translating { try await target.stopVideo() }
    }

    func suspendSession(sessionId: Int64) async throws {
        let target = try session(sessionId)
        await target.suspend()
    }

    func resumeSession(sessionId: Int64) async throws {
        let target = try session(sessionId)
        await target.resume()
    }
}
