import Foundation

/// Device orientation to the rotation applied to a still, taken from the sensor and not from the UI
/// orientation (docs/specs/camera.md "Edge cases": the camera UI may be locked to portrait).
public enum DeviceOrientation: String, Equatable, Sendable {
    case portrait, portraitUpsideDown, landscapeLeft, landscapeRight

    /// Rotation angle in degrees (clockwise) to apply to the sensor image so it appears upright.
    public var rotationDegrees: Int {
        switch self {
        case .portrait: return 90
        case .portraitUpsideDown: return 270
        case .landscapeLeft: return 180
        case .landscapeRight: return 0
        }
    }

    /// EXIF orientation tag value for a back camera.
    public var exifOrientation: Int {
        switch self {
        case .portrait: return 6
        case .portraitUpsideDown: return 8
        case .landscapeLeft: return 3
        case .landscapeRight: return 1
        }
    }
}

/// White balance conversions that must not depend on AVFoundation.
public enum WhiteBalanceMath {
    public static let kelvinRange = IntRange(min: 2000, max: 10000)

    /// Scene presets as color temperatures. Tint stays neutral.
    public static func kelvin(for preset: WhiteBalancePreset) -> Int? {
        switch preset {
        case .auto: return nil
        case .daylight: return 5500
        case .cloudy: return 6500
        case .shade: return 7500
        case .tungsten: return 3000
        case .fluorescent: return 4200
        }
    }

    /// Per-channel gains must lie in [1, maxGain] or AVFoundation raises an exception.
    public static func clampGains(red: Float, green: Float, blue: Float, maxGain: Float) -> (red: Float, green: Float, blue: Float) {
        func clamp(_ value: Float) -> Float { Swift.min(Swift.max(value, 1), Swift.max(1, maxGain)) }
        return (clamp(red), clamp(green), clamp(blue))
    }
}

/// Shutter and exposure helpers shared by the engine and tests.
public enum ExposureMath {
    public static func nanoseconds(fromSeconds seconds: Double) -> Int64 {
        Int64((seconds * 1e9).rounded())
    }

    public static func seconds(fromNanoseconds ns: Int64) -> Double {
        Double(ns) / 1e9
    }
}

/// A capture is on disk completely, or not at all (NFR-002): files are written under a `.partial` name
/// and renamed when finished, and leftovers from a killed app are removed at the next start.
public struct AtomicOutput {
    public static let partialSuffix = ".partial"

    public let finalURL: URL
    public var partialURL: URL { URL(fileURLWithPath: finalURL.path + AtomicOutput.partialSuffix) }

    public init(finalURL: URL) {
        self.finalURL = finalURL
    }

    /// Moves the finished partial file to its final name. Replaces nothing silently: a pre-existing final file is an error.
    public func commit(fileManager: FileManager = .default) throws {
        guard fileManager.fileExists(atPath: partialURL.path) else {
            throw CameraError(.captureFailed, "The capture file was not written.")
        }
        if fileManager.fileExists(atPath: finalURL.path) {
            throw CameraError(.captureFailed, "The capture file already exists.")
        }
        try fileManager.moveItem(at: partialURL, to: finalURL)
    }

    public func discard(fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: partialURL)
    }

    /// Deletes `.partial` files left by an interrupted capture. Returns how many were removed.
    @discardableResult
    public static func cleanStale(in directory: URL, fileManager: FileManager = .default) -> Int {
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return 0 }
        var removed = 0
        for name in names where name.hasSuffix(partialSuffix) {
            if (try? fileManager.removeItem(at: directory.appendingPathComponent(name))) != nil { removed += 1 }
        }
        return removed
    }
}

public enum StoragePolicy {
    /// Headroom kept free beyond the file being written (OS needs space to finalize the container).
    public static let headroomBytes: Int64 = 50 * 1024 * 1024

    /// Throws `storage_full` when the capture cannot be written (the Memory is then not created).
    public static func ensureRoom(availableBytes: Int64?, requiredBytes: Int64) throws {
        guard let available = availableBytes else { return } // unknown: let the write decide
        if available < requiredBytes + headroomBytes {
            throw CameraError(.storageFull, "There is not enough free space to save this photo.")
        }
    }

    /// A deliberately generous estimate used for the pre-check: photos are well under this, Motion clips too.
    public static func estimatedBytes(widthPx: Int, heightPx: Int, motion: Bool) -> Int64 {
        let photo = Int64(widthPx) * Int64(heightPx) / 2 // about 4 bits per pixel worst case
        return motion ? photo + 40 * 1024 * 1024 : photo
    }
}
