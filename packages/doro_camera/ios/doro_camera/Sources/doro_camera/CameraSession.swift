import AVFoundation
import CoreImage
import DoroCameraCore
import Foundation
import UIKit

/// How a session gets its frames. Hardware uses AVFoundation; the synthetic camera (debug builds only,
/// ADR-0013) lets the Simulator, which has no camera, drive the same pipeline.
enum CameraBackend {
    case hardware(AVCaptureDevice)
    case synthetic
}

struct SessionSetup {
    let id: Int64
    let cameraId: String
    let backend: CameraBackend
    let descriptor: CameraDescriptor
    let capabilities: CameraCapabilities
    let photoFormat: PhotoFormat
    let live: Bool
    let wantsAudio: Bool
    let microphone: AuthorizationState
    let requestedPhotoSize: PixelSize?
}

/// One open camera: preview texture, stills, Motion pre-roll buffer, video recording, interruptions.
/// Everything mutable lives on `queue`; the public async methods hop onto it.
final class CameraSession: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    let setup: SessionSetup
    private let texture: PreviewTexture
    private let emit: (SessionEventMessage) -> Void

    let queue = DispatchQueue(label: "com.dorocam.camera.session")
    private var machine: SessionMachine
    private let downscaler = FrameDownscaler()
    private var videoRing: TimedRing<VideoFrame>
    private var audioRing: TimedRing<AudioChunk>
    private var lastRingTime = -1.0
    private var frameSizeMeasured = false
    private var liveBuffering = false
    private var audioActive = false
    private var recorder: VideoRecorder?
    private var orientation = DeviceOrientation.portrait
    private var lastEffective = EffectiveSettings(
        exposureMode: .auto, iso: nil, exposureTimeNs: nil, exposureBiasEV: nil, exposureLocked: false, focusMode: .continuous,
        focusDiopters: nil, focusLocked: false, whiteBalance: .auto, zoomFactor: 1, flash: .off, torch: false
    )
    private var thermal = ThermalLevel.nominal
    private var observers: [NSObjectProtocol] = []

    // hardware
    private var session: AVCaptureSession?
    private var photoOutput: AVCapturePhotoOutput?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var audioOutput: AVCaptureAudioDataOutput?
    private var controller: DeviceController?
    private(set) var previewSize = PixelSize(width: 1080, height: 1440)
    private(set) var photoSize = PixelSize(width: 4032, height: 3024)

    #if DOROCAM_SYNTHETIC_CAMERA
    private var synthetic: SyntheticDriver?
    #endif

    private static let previewLongEdge = 1440
    private static let ringLongEdge = 960
    private static let ringFps = 15.0

    init(setup: SessionSetup, texture: PreviewTexture, emit: @escaping (SessionEventMessage) -> Void) {
        self.setup = setup
        self.texture = texture
        self.emit = emit
        self.machine = SessionMachine(liveEnabled: setup.live)
        let window = Double(setup.capabilities.live.maxPreBufferMs) / 1000
        self.videoRing = TimedRing<VideoFrame>(windowSeconds: window)
        self.audioRing = TimedRing<AudioChunk>(windowSeconds: window)
        super.init()
    }

    var info: (liveActive: Bool, audioActive: Bool) { queue.sync { (liveBuffering, audioActive) } }
    var isSynthetic: Bool {
        if case .synthetic = setup.backend { return true }
        return false
    }

    // MARK: lifecycle

    func open() async throws {
        try await onQueue {
            _ = self.machine.handle(.open)
            switch self.setup.backend {
            case .hardware(let device):
                try self.configureHardware(device: device)
            case .synthetic:
                #if DOROCAM_SYNTHETIC_CAMERA
                self.synthetic = SyntheticDriver(session: self)
                #else
                throw CameraError(.unsupportedConfiguration, "The synthetic camera is not available in this build.")
                #endif
            }
            self.audioActive = self.setup.wantsAudio && self.setup.microphone == .authorized && self.setup.capabilities.live.audio
            self.observeSystem()
            self.apply(self.machine.handle(.started))
            self.emitState()
        }
        // The first frame tells the real preview size, which Dart needs to lay out the texture.
        let deadline = Date().addingTimeInterval(2.5)
        while Date() < deadline {
            if await onQueueQuiet2({ self.frameSizeMeasured }) { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        if isSynthetic { photoSize = previewSize } // the synthetic "photo" is a frame of the preview
    }

    func close() async {
        await onQueueQuiet {
            self.apply(self.machine.handle(.close))
            self.emitState()
        }
    }

    func suspend() async {
        await onQueueQuiet {
            self.apply(self.machine.handle(.appBackgrounded))
            self.emitState()
        }
    }

    func resume() async {
        await onQueueQuiet {
            self.apply(self.machine.handle(.appForegrounded))
            self.emitState()
        }
    }

    func setLive(_ enabled: Bool) {
        queue.async {
            self.apply(self.machine.setLive(enabled))
        }
    }

    // MARK: hardware configuration

    private func configureHardware(device: AVCaptureDevice) throws {
        let session = AVCaptureSession()
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo

        guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            throw CameraError(.cameraInUse, "The camera could not be opened. Another app may be using it.")
        }
        session.addInput(input)

        let photo = AVCapturePhotoOutput()
        guard session.canAddOutput(photo) else { throw CameraError(.unsupportedConfiguration, "Photo capture is not available.") }
        session.addOutput(photo)

        let facts = DeviceFacts(device: device, photoOutput: photo)
        let supported = device.activeFormat.supportedMaxPhotoDimensions
        let wanted = setup.requestedPhotoSize
        let chosen =
            supported.first(where: { wanted != nil && Int($0.width) == wanted?.width && Int($0.height) == wanted?.height })
            ?? supported.max(by: { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) })
        if let chosen = chosen {
            photo.maxPhotoDimensions = chosen
            photoSize = PixelSize(width: Int(chosen.width), height: Int(chosen.height))
        } else if let largest = facts.photoSizes.first {
            photoSize = largest
        }
        photo.maxPhotoQualityPrioritization = .quality

        let video = AVCaptureVideoDataOutput()
        video.alwaysDiscardsLateVideoFrames = true
        // 4:3 frames at a size that is cheap to preview, buffer and encode. Photos are captured at full size separately.
        video.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 1440,
            kCVPixelBufferHeightKey as String: 1080,
        ]
        video.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(video) else { throw CameraError(.unsupportedConfiguration, "The preview is not available.") }
        session.addOutput(video)
        if let connection = video.connection(with: .video) {
            if connection.isVideoOrientationSupported { connection.videoOrientation = .portrait }
            // The preview of the front camera is mirrored; the saved photo is not (docs/specs/camera.md).
            if connection.isVideoMirroringSupported { connection.automaticallyAdjustsVideoMirroring = false; connection.isVideoMirrored = device.position == .front }
        }
        previewSize = PixelSize(width: 1080, height: 1440)

        if setup.wantsAudio, setup.microphone == .authorized, let microphone = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: microphone), session.canAddInput(audioInput) {
            session.addInput(audioInput)
            let audio = AVCaptureAudioDataOutput()
            audio.audioSettings = AudioConversion.captureSettings
            audio.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(audio) {
                session.addOutput(audio)
                audioOutput = audio
            }
        }

        self.session = session
        self.photoOutput = photo
        self.videoOutput = video
        self.controller = DeviceController(device: device, capabilities: setup.capabilities)
    }

    // MARK: system events (interruptions, thermal, orientation, app state)

    private func observeSystem() {
        let center = NotificationCenter.default
        func watch(_ name: Notification.Name, object: Any? = nil, _ handler: @escaping (Notification) -> Void) {
            observers.append(center.addObserver(forName: name, object: object, queue: nil) { [weak self] note in
                self?.queue.async { handler(note) }
            })
        }
        if let session = session {
            watch(.AVCaptureSessionWasInterrupted, object: session) { [weak self] note in
                guard let self = self else { return }
                var reason = InterruptionReason.other
                if let raw = note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int,
                   let parsed = AVCaptureSession.InterruptionReason(rawValue: raw) {
                    switch parsed {
                    case .videoDeviceInUseByAnotherClient: reason = .videoDeviceInUseByAnotherClient
                    case .audioDeviceInUseByAnotherClient: reason = .audioDeviceInUseByAnotherClient
                    case .videoDeviceNotAvailableWithMultipleForegroundApps: reason = .notAvailableWithMultipleForegroundApps
                    case .videoDeviceNotAvailableDueToSystemPressure: reason = .notAvailableDueToSystemPressure
                    default: reason = .other
                    }
                }
                self.apply(self.machine.handle(.interrupted(reason)))
                self.emitState()
                self.emitEvent(kind: .interrupted)
            }
            watch(.AVCaptureSessionInterruptionEnded, object: session) { [weak self] _ in
                guard let self = self else { return }
                self.apply(self.machine.handle(.interruptionEnded))
                self.emitState()
                self.emitEvent(kind: .resumed)
            }
            watch(.AVCaptureSessionRuntimeError, object: session) { [weak self] note in
                guard let self = self, let error = note.userInfo?[AVCaptureSessionErrorKey] as? AVError else { return }
                if error.code == .mediaServicesWereReset {
                    // The system restarted its camera services: start the same session again.
                    session.startRunning()
                    return
                }
                self.apply(self.machine.handle(.runtimeError(error.code == .deviceInUseByAnotherApplication ? .cameraInUse : .cameraDisconnected)))
                self.emitState()
            }
        }
        watch(ProcessInfo.thermalStateDidChangeNotification) { [weak self] _ in
            guard let self = self else { return }
            self.thermal = ThermalPolicy.level(forProcessInfoRawValue: ProcessInfo.processInfo.thermalState.rawValue)
            self.emitEvent(kind: .thermal)
            self.apply(self.machine.handle(.thermal(self.thermal)))
            if self.thermal >= .serious {
                // Shorten what the pre-roll keeps so a hot phone stops hoarding frames (NFR-012).
                let keep = Double(ThermalPolicy.maxPreBufferMs(requested: self.setup.capabilities.live.maxPreBufferMs, level: self.thermal)) / 1000
                self.videoRing = TimedRing<VideoFrame>(windowSeconds: keep)
                self.audioRing = TimedRing<AudioChunk>(windowSeconds: keep)
            }
        }
        watch(UIApplication.didEnterBackgroundNotification) { [weak self] _ in
            guard let self = self else { return }
            self.apply(self.machine.handle(.appBackgrounded))
            self.emitState()
        }
        watch(UIApplication.willEnterForegroundNotification) { [weak self] _ in
            guard let self = self else { return }
            self.apply(self.machine.handle(.appForegrounded))
            self.emitState()
        }
        DispatchQueue.main.async {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        }
        watch(UIDevice.orientationDidChangeNotification) { [weak self] _ in
            guard let self = self else { return }
            var mapped: DeviceOrientation?
            switch UIDevice.current.orientation {
            case .portrait: mapped = .portrait
            case .portraitUpsideDown: mapped = .portraitUpsideDown
            case .landscapeLeft: mapped = .landscapeLeft
            case .landscapeRight: mapped = .landscapeRight
            default: mapped = nil // flat or unknown: keep the last known orientation
            }
            if let value = mapped, value != self.orientation {
                self.orientation = value
                self.emit(SessionEventMessage(sessionId: self.setup.id, kind: .orientation, orientationDegrees: Int64(value.rotationDegrees)))
            }
        }
    }

    // MARK: effects of the session state machine

    private func apply(_ transition: Transition) {
        for effect in transition.effects { run(effect) }
    }

    private func apply(_ effects: [SessionEffect]) {
        for effect in effects { run(effect) }
    }

    private func run(_ effect: SessionEffect) {
        switch effect {
        case .startSession, .startPreview:
            if let session = session, !session.isRunning { session.startRunning() }
            #if DOROCAM_SYNTHETIC_CAMERA
            synthetic?.start()
            #endif
        case .stopSession, .stopPreview:
            if let session = session, session.isRunning { session.stopRunning() }
            #if DOROCAM_SYNTHETIC_CAMERA
            synthetic?.stop()
            #endif
        case .startLiveBuffering:
            liveBuffering = true
        case .stopLiveBuffering:
            liveBuffering = false
            videoRing.removeAll()
            audioRing.removeAll()
            lastRingTime = -1
        case .deferUntilCaptureEnds:
            break
        case .emitError(let code):
            emit(SessionEventMessage(sessionId: setup.id, kind: .error, errorCode: code.rawValue, errorMessage: "The camera stopped (\(code.rawValue))."))
        case .releaseResources:
            releaseResources()
        }
    }

    private func releaseResources() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        recorder = nil
        session?.stopRunning()
        videoOutput?.setSampleBufferDelegate(nil, queue: nil)
        audioOutput?.setSampleBufferDelegate(nil, queue: nil)
        #if DOROCAM_SYNTHETIC_CAMERA
        synthetic?.stop()
        synthetic = nil
        #endif
        videoRing.removeAll()
        audioRing.removeAll()
        texture.dispose()
        DispatchQueue.main.async { UIDevice.current.endGeneratingDeviceOrientationNotifications() }
    }

    private func emitState() {
        let state: SessionStateMessage
        switch machine.state {
        case .idle, .opening: state = .configuring
        case .running: state = recorder == nil ? .previewing : .recording
        case .capturing: state = .capturing
        case .interrupted, .suspended: state = .suspended
        case .closed, .failed: state = .closed
        }
        emit(SessionEventMessage(sessionId: setup.id, kind: .state, state: state))
    }

    private func emitEvent(kind: SessionEventKindMessage) {
        switch kind {
        case .thermal: emit(SessionEventMessage(sessionId: setup.id, kind: .thermal, thermal: ThermalStateMessage(thermal)))
        default: emit(SessionEventMessage(sessionId: setup.id, kind: kind))
        }
    }

    // MARK: frames

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output === videoOutput {
            guard let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            ingest(video: pixels, time: CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds)
        } else if output === audioOutput, let chunk = AudioConversion.chunk(from: sampleBuffer) {
            ingest(audio: chunk)
        }
    }

    /// Called on `queue` for every frame, whichever camera produced it.
    func ingest(video pixels: CVPixelBuffer, time: Double) {
        if !frameSizeMeasured {
            previewSize = PixelSize(width: CVPixelBufferGetWidth(pixels), height: CVPixelBufferGetHeight(pixels))
            frameSizeMeasured = true
        }
        texture.publish(pixels)
        if let recorder = recorder {
            recorder.append(VideoFrame(time: time, pixelBuffer: pixels))
        }
        // Pre-roll is only kept while LIVE is on and the camera is active (MOT-009, NFR-012).
        if liveBuffering, time - lastRingTime >= 1.0 / CameraSession.ringFps,
           let copy = downscaler.copy(pixels, longEdge: CameraSession.ringLongEdge) {
            videoRing.append(VideoFrame(time: time, pixelBuffer: copy), at: time)
            lastRingTime = time
        }
    }

    func ingest(audio chunk: AudioChunk) {
        if let recorder = recorder { recorder.append(chunk) }
        if liveBuffering, audioActive { audioRing.append(chunk, at: chunk.time) }
    }

    // MARK: settings

    func apply(settings requested: RequestedSettings) async throws -> AppliedSettingsMessage {
        let (effective, adjustments) = SettingsClamp.effective(requested, capabilities: setup.capabilities)
        _ = adjustments // Dart already received these from its own resolver; the clamp here is a safety net.
        if let controller = controller {
            try await controller.apply(effective)
        }
        let zoomNow = controller.map { Double($0.device.videoZoomFactor) } ?? effective.zoomFactor
        let report: AppliedReport
        if let controller = controller {
            report = controller.report(zoom: zoomNow, dimensions: (photoSize.width, photoSize.height))
        } else {
            // Synthetic camera: it accepts what it was given, and is labelled as synthetic everywhere.
            report = AppliedReport(
                iso: effective.iso, exposureTimeNs: effective.exposureTimeNs, exposureBiasEV: effective.exposureBiasEV,
                aperture: setup.capabilities.apertures.first, focalLength35mmEq: setup.descriptor.focalLength35mmEq,
                focusDiopters: effective.focusDiopters, zoomFactor: effective.zoomFactor, widthPx: photoSize.width, heightPx: photoSize.height
            )
        }
        let mismatches = AppliedComparison.mismatches(effective: effective, reported: report).map { $0.field }
        await onQueueQuiet { self.lastEffective = effective }
        return AppliedSettingsMessage(report: report, effective: effective, mismatches: mismatches)
    }

    func focus(at point: CGPoint) async throws {
        try controller?.focus(at: point)
    }

    // MARK: capture

    func capture(_ request: CaptureRequestMessage) async throws -> CaptureResultMessage {
        let started = try await onQueue { () -> (EffectiveSettings, DeviceOrientation) in
            guard self.machine.state == .running else {
                throw CameraError(.captureFailed, "The camera is not ready. Try again in a moment.")
            }
            self.apply(self.machine.handle(.captureRequested))
            self.emitState()
            return (self.lastEffective, self.orientation)
        }
        let effective = started.0
        let orientation = started.1
        do {
            let result = try await performCapture(request, effective: effective, orientation: orientation)
            await onQueueQuiet {
                self.apply(self.machine.handle(.captureFinished))
                self.emitState()
            }
            return result
        } catch {
            await onQueueQuiet {
                self.apply(self.machine.handle(.captureFailed))
                self.emitState()
            }
            throw (error as? CameraError) ?? CameraError(.captureFailed, "The photo could not be saved.")
        }
    }

    private func performCapture(_ request: CaptureRequestMessage, effective: EffectiveSettings, orientation: DeviceOrientation) async throws -> CaptureResultMessage {
        let directory = URL(fileURLWithPath: request.outputDir, isDirectory: true)
        // Leftovers of a capture that was interrupted by an app kill (NFR-002): nothing half-written is ever kept.
        AtomicOutput.cleanStale(in: directory)
        let shutterHost = CMClockGetTime(CMClockGetHostTimeClock()).seconds
        let capturedAt = request.timestampEpochMs ?? Int64((Date().timeIntervalSince1970 * 1000).rounded())

        try StoragePolicy.ensureRoom(
            availableBytes: Self.availableBytes(at: directory),
            requiredBytes: StoragePolicy.estimatedBytes(widthPx: photoSize.width, heightPx: photoSize.height, motion: request.live)
        )

        let still = try await captureStill(location: request.location, effective: effective, orientation: orientation)

        // The original is saved first and exactly as the camera produced it (NFR-005, PRF-002).
        let original = AtomicOutput(finalURL: directory.appendingPathComponent(request.originalName))
        original.discard()
        do {
            try still.originalData.write(to: original.partialURL, options: .atomic)
            try original.commit()
        } catch {
            original.discard()
            throw (error as? CameraError) ?? CameraError(.storageFull, "The photo could not be written to storage.")
        }

        // Renditions are best effort: a failure keeps the original and flags `renderFailed` so Dart retries later.
        var renderedPath: String?
        var thumbnailPath: String?
        var displayPath: String?
        var renderFailed = false
        do {
            let parameters = Self.renderParameters(from: request.render, jpegQuality: Int(request.jpegQuality))
            let rendered = try StillRenderer.render(source: still.renderSource, parameters: parameters)
            let renderedOutput = AtomicOutput(finalURL: directory.appendingPathComponent(request.renderedName))
            try rendered.jpeg.write(to: renderedOutput.partialURL, options: .atomic)
            try renderedOutput.commit()
            renderedPath = renderedOutput.finalURL.path
            for (name, edge, assign) in [(request.thumbnailName, 512, 0), (request.displayName, 2048, 1)] {
                let small = try StillRenderer.downscale(source: rendered.jpeg, longEdge: edge)
                let output = AtomicOutput(finalURL: directory.appendingPathComponent(name))
                try small.jpeg.write(to: output.partialURL, options: .atomic)
                try output.commit()
                if assign == 0 { thumbnailPath = output.finalURL.path } else { displayPath = output.finalURL.path }
            }
        } catch {
            renderFailed = true
        }

        var motion: MotionResultMessage?
        var liveIncluded = false
        if request.live, let name = request.motionName {
            do {
                motion = try await captureMotion(request: request, name: name, directory: directory, shutterTime: shutterHost, orientation: orientation)
                liveIncluded = motion != nil
            } catch {
                // The still is already safe; the Memory simply has no motion (it degrades to a photo).
                liveIncluded = false
            }
        }

        let zoom = controller.map { Double($0.device.videoZoomFactor) } ?? effective.zoomFactor
        var report = controller?.report(zoom: zoom, dimensions: (still.width, still.height))
            ?? AppliedReport(
                iso: effective.iso, exposureTimeNs: effective.exposureTimeNs, exposureBiasEV: effective.exposureBiasEV,
                aperture: setup.capabilities.apertures.first, focalLength35mmEq: setup.descriptor.focalLength35mmEq,
                focusDiopters: effective.focusDiopters, zoomFactor: effective.zoomFactor, widthPx: still.width, heightPx: still.height
            )
        report = PhotoMetadata.merge(report: report, exif: still.exif)
        report.widthPx = still.width
        report.heightPx = still.height
        let mismatches = AppliedComparison.mismatches(effective: effective, reported: report).map { $0.field }

        return CaptureResultMessage(
            memoryId: request.memoryId,
            originalPath: original.finalURL.path,
            originalMime: still.originalMime,
            width: Int64(still.width),
            height: Int64(still.height),
            orientationDegrees: Int64(orientation.rotationDegrees),
            applied: AppliedSettingsMessage(report: report, effective: effective, mismatches: mismatches),
            capturedAtEpochMs: capturedAt,
            source: CameraSourceMessage(setup.descriptor.source),
            liveIncluded: liveIncluded,
            mirrored: setup.descriptor.facing == .front,
            renderFailed: renderFailed,
            renderedPath: renderedPath,
            thumbnailPath: thumbnailPath,
            displayPath: displayPath,
            motion: motion
        )
    }

    private func captureStill(location: LocationMessage?, effective: EffectiveSettings, orientation: DeviceOrientation) async throws -> CapturedStill {
        #if DOROCAM_SYNTHETIC_CAMERA
        if isSynthetic {
            guard let frame = texture.currentFrame(), let jpeg = SyntheticDriver.jpeg(from: frame) else {
                throw CameraError(.captureFailed, "The synthetic camera has no frame yet.")
            }
            return CapturedStill(originalData: jpeg, originalMime: "image/jpeg", renderSource: jpeg, exif: [:], width: CVPixelBufferGetWidth(frame), height: CVPixelBufferGetHeight(frame))
        }
        #endif
        guard let output = photoOutput else { throw CameraError(.captureFailed, "The camera is not open.") }
        let format = setup.photoFormat
        let settings: AVCapturePhotoSettings
        switch format {
        case .heif where output.availablePhotoCodecTypes.contains(.hevc):
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        case .dng:
            if let raw = output.availableRawPhotoPixelFormatTypes.first {
                settings = AVCapturePhotoSettings(rawPixelFormatType: raw, processedFormat: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            } else {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            }
        default:
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        }
        settings.maxPhotoDimensions = output.maxPhotoDimensions
        let wantedFlash: AVCaptureDevice.FlashMode = effective.flash == .on ? .on : (effective.flash == .auto ? .auto : .off)
        if output.supportedFlashModes.contains(wantedFlash) { settings.flashMode = wantedFlash }

        if let connection = output.connection(with: .video) {
            // Rotation follows the device orientation sensor, not the UI orientation (docs/specs/camera.md).
            if connection.isVideoOrientationSupported {
                switch orientation {
                case .portrait: connection.videoOrientation = .portrait
                case .portraitUpsideDown: connection.videoOrientation = .portraitUpsideDown
                case .landscapeLeft: connection.videoOrientation = .landscapeRight
                case .landscapeRight: connection.videoOrientation = .landscapeLeft
                }
            }
            if connection.isVideoMirroringSupported { connection.automaticallyAdjustsVideoMirroring = false; connection.isVideoMirrored = false }
        }

        let delegate = PhotoCaptureDelegate(location: location, format: format == .heif && !output.availablePhotoCodecTypes.contains(.hevc) ? .jpeg : format)
        return try await delegate.capture(output: output, settings: settings)
    }

    private func captureMotion(request: CaptureRequestMessage, name: String, directory: URL, shutterTime: Double, orientation: DeviceOrientation) async throws -> MotionResultMessage? {
        let maxPre = Double(setup.capabilities.live.maxPreBufferMs) / 1000
        let pre = min(max(Double(request.preRollMs) / 1000, 0), maxPre)
        let post = min(max(Double(request.postRollMs) / 1000, 0), 3)
        let audioWanted = await onQueueQuiet2 { self.audioActive }
        let oldest = await onQueueQuiet2 { self.videoRing.oldestTime }
        let window = MotionClipPlanner.plan(shutterTime: shutterTime, oldestBufferedTime: oldest, preRollSeconds: pre, postRollSeconds: post, audio: audioWanted)

        // Wait for the post-roll to arrive (bounded, so a stalled camera cannot hang the capture).
        let deadline = Date().addingTimeInterval(post + 1.5)
        while Date() < deadline {
            let newest = await onQueueQuiet2 { self.videoRing.newestTime }
            if (newest ?? 0) >= window.endTime { break }
            try await Task.sleep(nanoseconds: 40_000_000)
        }
        let selection = await onQueueQuiet2 { MotionClipPlanner.select(window: window, video: self.videoRing, audio: self.audioRing) }
        guard !selection.video.isEmpty else { return nil }

        let rotation = clipRotationDegrees(for: orientation)
        let output = AtomicOutput(finalURL: directory.appendingPathComponent(name))
        let clip = try await MotionClipWriter.write(
            video: selection.video.map { $0.element },
            audio: selection.audio.map { $0.element },
            startTime: window.startTime,
            output: output,
            rotationDegrees: rotation
        )
        return MotionResultMessage(
            path: output.finalURL.path,
            durationMs: Int64((clip.durationSeconds * 1000).rounded()),
            preRollMs: Int64((window.preRollSeconds * 1000).rounded()),
            postRollMs: Int64((window.postRollSeconds * 1000).rounded()),
            keyFrameTimeMs: Int64((window.preRollSeconds * 1000).rounded()),
            hasAudio: clip.hasAudio,
            width: Int64(clip.width),
            height: Int64(clip.height),
            orientationDegrees: Int64(rotation),
            mime: "video/mp4"
        )
    }

    // MARK: video

    func startVideo(_ request: VideoRequestMessage, directory: URL) async throws {
        try await onQueue {
            guard self.machine.state == .running, self.recorder == nil else {
                throw CameraError(.captureFailed, "Video cannot start right now.")
            }
            let output = AtomicOutput(finalURL: URL(fileURLWithPath: request.outputPath))
            try StoragePolicy.ensureRoom(availableBytes: Self.availableBytes(at: directory), requiredBytes: 200 * 1024 * 1024)
            let rotation = clipRotationDegrees(for: self.orientation)
            self.recorder = try VideoRecorder(
                output: output,
                width: self.previewSize.width,
                height: self.previewSize.height,
                fps: Int(request.fps ?? 30),
                audio: request.audio && self.audioActive,
                rotationDegrees: rotation
            )
            self.emitState()
        }
    }

    func stopVideo() async throws -> VideoResultMessage {
        let (recorder, rotation) = try await onQueue { () -> (VideoRecorder, Int) in
            guard let recorder = self.recorder else { throw CameraError(.captureFailed, "No video is being recorded.") }
            self.recorder = nil
            self.emitState()
            return (recorder, clipRotationDegrees(for: self.orientation))
        }
        let clip = try await recorder.finish()
        return VideoResultMessage(
            path: recorder.outputPath,
            durationMs: Int64((clip.durationSeconds * 1000).rounded()),
            width: Int64(clip.width),
            height: Int64(clip.height),
            hasAudio: clip.hasAudio,
            bytes: clip.bytes,
            orientationDegrees: Int64(rotation),
            mime: "video/mp4"
        )
    }

    // MARK: helpers

    private static func availableBytes(at directory: URL) -> Int64? {
        let values = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    private static func renderParameters(from spec: RenderSpecMessage?, jpegQuality: Int) -> RenderParameters {
        let quality = Double(min(max(jpegQuality, 10), 100)) / 100
        guard let spec = spec else { return RenderParameters(jpegQuality: quality) }
        return RenderParameters(
            lut: spec.lut.map { [UInt8]($0.data) },
            lutSize: spec.lutSize.map { Int($0) },
            grain: spec.grain,
            vignette: spec.vignette,
            aspect: StillRenderer.parseAspect(spec.aspectRatio),
            jpegQuality: quality
        )
    }

    /// Runs `body` on the session queue and returns its result (or throws its error).
    private func onQueue<T>(_ body: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { continuation.resume(returning: try body()) } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func onQueueQuiet(_ body: @escaping () -> Void) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                body()
                continuation.resume()
            }
        }
    }

    private func onQueueQuiet2<T>(_ body: @escaping () -> T) async -> T {
        await withCheckedContinuation { (continuation: CheckedContinuation<T, Never>) in
            queue.async { continuation.resume(returning: body()) }
        }
    }
}
