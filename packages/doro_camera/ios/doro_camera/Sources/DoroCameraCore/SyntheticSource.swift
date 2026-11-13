import Foundation

// The synthetic test camera (ADR-0013). The iOS Simulator has no camera, so debug builds can feed the
// pipeline a deterministic picture and sound. It exists only in debug builds (flag
// DOROCAM_SYNTHETIC_CAMERA) and always reports `source: synthetic`; it can never pass for hardware.

#if DOROCAM_SYNTHETIC_CAMERA

/// A frame as plain bytes (BGRA), so the pattern can be checked without CoreVideo.
public struct SyntheticFrame: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let time: Double
    public let bgra: [UInt8]
    public let isFlash: Bool

    public init(width: Int, height: Int, time: Double, bgra: [UInt8], isFlash: Bool) {
        self.width = width
        self.height = height
        self.time = time
        self.bgra = bgra
        self.isFlash = isFlash
    }
}

/// Generates frames and audio on a fixed schedule: a white flash frame every `flashPeriod` seconds
/// and a matching 1 kHz beep burst, so tests can measure audio/video sync (MOT, NFR-012).
public struct SyntheticSource: Sendable {
    public static let sampleRate = 44_100.0
    public static let beepHz = 1000.0

    public let width: Int
    public let height: Int
    public let fps: Double
    public let flashPeriod: Double
    public let flashDuration: Double

    public init(width: Int = 64, height: Int = 48, fps: Double = 30, flashPeriod: Double = 1.0, flashDuration: Double = 1.0 / 30.0) {
        precondition(width > 0 && height > 0 && fps > 0 && flashPeriod > 0 && flashDuration > 0)
        self.width = width
        self.height = height
        self.fps = fps
        self.flashPeriod = flashPeriod
        self.flashDuration = flashDuration
    }

    /// True while a flash (and its beep) is active at time `t`.
    public func isFlash(at t: Double) -> Bool {
        guard t >= 0 else { return false }
        return t.truncatingRemainder(dividingBy: flashPeriod) < flashDuration
    }

    public func frame(index: Int) -> SyntheticFrame {
        let t = Double(index) / fps
        let flash = isFlash(at: t)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                if flash {
                    bytes[offset] = 255; bytes[offset + 1] = 255; bytes[offset + 2] = 255
                } else {
                    // A gradient that moves with time, so successive frames differ.
                    bytes[offset] = UInt8((x * 255) / Swift.max(1, width - 1))
                    bytes[offset + 1] = UInt8((y * 255) / Swift.max(1, height - 1))
                    bytes[offset + 2] = UInt8(truncatingIfNeeded: index * 5)
                }
                bytes[offset + 3] = 255
            }
        }
        return SyntheticFrame(width: width, height: height, time: t, bgra: bytes, isFlash: flash)
    }

    /// Mono Float samples for the interval [start, start + duration): silence outside flashes, a sine burst inside.
    public func audio(start: Double, duration: Double) -> [Float] {
        let count = Int((duration * SyntheticSource.sampleRate).rounded())
        var samples = [Float](repeating: 0, count: Swift.max(0, count))
        for i in 0..<samples.count {
            let t = start + Double(i) / SyntheticSource.sampleRate
            if isFlash(at: t) {
                samples[i] = Float(0.8 * sin(2 * Double.pi * SyntheticSource.beepHz * t))
            }
        }
        return samples
    }

    /// First instant a flash is visible in a run of frames, or nil.
    public static func firstFlashTime(in frames: [SyntheticFrame]) -> Double? {
        frames.first(where: { $0.isFlash })?.time
    }

    /// First sample index (as time) where audio amplitude exceeds a threshold, or nil.
    public static func firstBeepTime(in samples: [Float], start: Double, threshold: Float = 0.1) -> Double? {
        guard let index = samples.firstIndex(where: { abs($0) > threshold }) else { return nil }
        return start + Double(index) / sampleRate
    }
}

#endif
