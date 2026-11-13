#if DOROCAM_SYNTHETIC_CAMERA

import CoreImage
import CoreMedia
import CoreVideo
import DoroCameraCore
import Foundation

// The synthetic test camera (ADR-0013): a deterministic picture and sound for the iOS Simulator, which
// has no camera. It is compiled only into debug builds, reports `source: synthetic` everywhere, and
// listCameras offers it only when the machine has no real camera.

enum SyntheticCamera {
    static let cameraId = "synthetic-camera-0"

    /// What a plausible phone sensor would report. Marked synthetic so the app never presents it as hardware.
    static func facts() -> DeviceFacts {
        DeviceFacts(
            uniqueId: cameraId,
            position: .back,
            deviceTypeName: "AVCaptureDeviceTypeBuiltInWideAngleCamera",
            minISO: 25,
            maxISO: 3200,
            minExposureSeconds: 1.0 / 8000,
            maxExposureSeconds: 1.0 / 2,
            supportsCustomExposure: true,
            minExposureTargetBias: -4,
            maxExposureTargetBias: 4,
            lensAperture: 1.8,
            horizontalFieldOfViewDegrees: 65,
            supportsLockedLensPosition: true,
            minimumFocusDistanceMillimeters: 100,
            minZoom: 1,
            maxZoom: 5,
            switchOverZoomFactors: [2],
            hasFlash: false,
            hasTorch: false,
            supportsHDR: false,
            supportsHEIF: false,
            supportsRAW: false,
            photoSizes: [PixelSize(width: 216, height: 288)],
            livePhotoCaptureSupported: false,
            hasMicrophone: true
        )
    }

    static func descriptor() -> CameraDescriptor {
        let base = CapabilityProbe.descriptor(for: facts())
        return CameraDescriptor(
            id: base.id, facing: base.facing, lensKind: base.lensKind, isLogical: false, physicalIds: [],
            sensorOrientationDegrees: 0, focalLengthMm: nil, focalLength35mmEq: base.focalLength35mmEq, source: .synthetic
        )
    }

    static func capabilities() -> CameraCapabilities {
        CapabilityProbe.capabilities(for: facts())
    }
}

/// Produces frames and audio on a timer, on the session's queue, through the same `ingest` calls the real camera uses.
final class SyntheticDriver {
    private weak var session: CameraSession?
    private let source = SyntheticSource(width: 216, height: 288, fps: 30, flashPeriod: 1.0, flashDuration: 1.0 / 30.0)
    private var timer: DispatchSourceTimer?
    private var index = 0
    private static let context = CIContext()

    init(session: CameraSession) {
        self.session = session
    }

    func start() {
        guard timer == nil, let session = session else { return }
        let timer = DispatchSource.makeTimerSource(queue: session.queue)
        timer.schedule(deadline: .now(), repeating: 1.0 / 30.0)
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        guard let session = session else { return }
        let time = CMClockGetTime(CMClockGetHostTimeClock()).seconds
        let frame = source.frame(index: index)
        if let buffer = Self.pixelBuffer(from: frame) {
            session.ingest(video: buffer, time: time)
        }
        let samples = source.audio(start: Double(index) / 30.0, duration: 1.0 / 30.0)
        var pcm = Data(capacity: samples.count * 2)
        for sample in samples {
            var value = Int16(max(-1, min(1, sample)) * 32767)
            withUnsafeBytes(of: &value) { pcm.append(contentsOf: $0) }
        }
        session.ingest(audio: AudioChunk(time: time, pcm: pcm))
        index += 1
    }

    private static func pixelBuffer(from frame: SyntheticFrame) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attributes: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()]
        guard CVPixelBufferCreate(nil, frame.width, frame.height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer) == kCVReturnSuccess,
              let output = buffer else { return nil }
        CVPixelBufferLockBaseAddress(output, [])
        defer { CVPixelBufferUnlockBaseAddress(output, []) }
        guard let base = CVPixelBufferGetBaseAddress(output) else { return nil }
        let stride = CVPixelBufferGetBytesPerRow(output)
        frame.bgra.withUnsafeBytes { raw in
            guard let source = raw.baseAddress else { return }
            for row in 0..<frame.height {
                memcpy(base + row * stride, source + row * frame.width * 4, frame.width * 4)
            }
        }
        return output
    }

    /// Encodes the latest synthetic frame as the "photo" of a capture.
    static func jpeg(from buffer: CVPixelBuffer) -> Data? {
        let image = CIImage(cvPixelBuffer: buffer)
        return context.jpegRepresentation(of: image, colorSpace: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(), options: [:])
    }
}

#endif
