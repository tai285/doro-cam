import Foundation

// Capability value types (docs/specs/camera.md "CameraCapabilities"). Foundation only, so they are
// testable with `swift test`. A capability that is `nil` or empty means "the platform did not report
// it": the app then hides the control and never simulates it (CAM-005, ADR-0002).

public struct IntRange: Equatable, Sendable {
    public let min: Int
    public let max: Int

    public init(min: Int, max: Int) {
        self.min = min
        self.max = max
    }

    public func clamped(_ value: Int) -> Int { Swift.min(Swift.max(value, min), max) }
    public func contains(_ value: Int) -> Bool { value >= min && value <= max }
}

public struct DoubleRange: Equatable, Sendable {
    public let min: Double
    public let max: Double

    public init(min: Double, max: Double) {
        self.min = min
        self.max = max
    }

    public func clamped(_ value: Double) -> Double { Swift.min(Swift.max(value, min), max) }
    public func contains(_ value: Double) -> Bool { value >= min && value <= max }
}

/// Exposure duration range in nanoseconds (the unit the Dart side and the API use).
public struct ExposureRangeNs: Equatable, Sendable {
    public let min: Int64
    public let max: Int64

    public init(min: Int64, max: Int64) {
        self.min = min
        self.max = max
    }

    public func clamped(_ value: Int64) -> Int64 { Swift.min(Swift.max(value, min), max) }
}

public enum CameraFacing: String, Equatable, Sendable {
    case back, front, external
}

public enum LensKind: String, Equatable, Sendable {
    case ultraWide, wide, tele, front, other
}

public enum FocusCalibration: String, Equatable, Sendable {
    case uncalibrated, approximate, calibrated
}

public enum WhiteBalancePreset: String, CaseIterable, Equatable, Sendable {
    case auto, daylight, cloudy, shade, tungsten, fluorescent
}

public enum FlashMode: String, CaseIterable, Equatable, Sendable {
    case off, auto, on
}

public enum PhotoFormat: String, Equatable, Sendable {
    case heif, jpeg, dng
}

public struct PixelSize: Equatable, Hashable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var megapixels: Double { Double(width * height) / 1_000_000 }
}

public enum CameraSource: String, Equatable, Sendable {
    case hardware, synthetic
}

public struct CameraDescriptor: Equatable, Sendable {
    public let id: String
    public let facing: CameraFacing
    public let lensKind: LensKind
    public let isLogical: Bool
    public let physicalIds: [String]
    public let sensorOrientationDegrees: Int
    public let focalLengthMm: Double?
    public let focalLength35mmEq: Double?
    public let source: CameraSource

    public init(
        id: String,
        facing: CameraFacing,
        lensKind: LensKind,
        isLogical: Bool,
        physicalIds: [String],
        sensorOrientationDegrees: Int,
        focalLengthMm: Double?,
        focalLength35mmEq: Double?,
        source: CameraSource
    ) {
        self.id = id
        self.facing = facing
        self.lensKind = lensKind
        self.isLogical = isLogical
        self.physicalIds = physicalIds
        self.sensorOrientationDegrees = sensorOrientationDegrees
        self.focalLengthMm = focalLengthMm
        self.focalLength35mmEq = focalLength35mmEq
        self.source = source
    }
}

public struct ExposureBiasCapability: Equatable, Sendable {
    public let range: DoubleRange
    /// Step in EV. iOS does not report one; the plugin uses 1/3 EV.
    public let step: Double

    public init(range: DoubleRange, step: Double) {
        self.range = range
        self.step = step
    }
}

public struct ManualFocusCapability: Equatable, Sendable {
    /// iOS reports a normalized lens position 0...1 only, never calibrated distances: always uncalibrated.
    public let calibration: FocusCalibration
    /// Diopters (1 / metres) of the closest focus distance. Manual focus accepts 0 (infinity) ... this.
    public let minFocusDistanceDiopters: Double

    public init(calibration: FocusCalibration, minFocusDistanceDiopters: Double) {
        self.calibration = calibration
        self.minFocusDistanceDiopters = minFocusDistanceDiopters
    }
}

public struct FocusCapability: Equatable, Sendable {
    public let auto: Bool
    public let continuous: Bool
    public let tapToFocus: Bool
    public let manual: ManualFocusCapability?

    public init(auto: Bool, continuous: Bool, tapToFocus: Bool, manual: ManualFocusCapability?) {
        self.auto = auto
        self.continuous = continuous
        self.tapToFocus = tapToFocus
        self.manual = manual
    }
}

public struct WhiteBalanceCapability: Equatable, Sendable {
    public let presets: [WhiteBalancePreset]
    /// `nil` when the device cannot lock gains, so no Kelvin control is offered.
    public let kelvin: IntRange?

    public init(presets: [WhiteBalancePreset], kelvin: IntRange?) {
        self.presets = presets
        self.kelvin = kelvin
    }
}

public struct ZoomCapability: Equatable, Sendable {
    public let min: Double
    public let max: Double
    /// Zoom factors at which the camera switches physical lens (optical steps), always starting at `min`.
    public let opticalSteps: [Double]

    public init(min: Double, max: Double, opticalSteps: [Double]) {
        self.min = min
        self.max = max
        self.opticalSteps = opticalSteps
    }
}

public struct LiveCapability: Equatable, Sendable {
    public let supported: Bool
    public let maxPreBufferMs: Int
    public let audio: Bool

    public init(supported: Bool, maxPreBufferMs: Int, audio: Bool) {
        self.supported = supported
        self.maxPreBufferMs = maxPreBufferMs
        self.audio = audio
    }
}

public struct CameraCapabilities: Equatable, Sendable {
    public let iso: IntRange?
    public let exposureTime: ExposureRangeNs?
    public let exposureBias: ExposureBiasCapability?
    /// Usually one value, in which case the aperture is display-only (CAM-013).
    public let apertures: [Double]
    public let focus: FocusCapability
    public let whiteBalance: WhiteBalanceCapability
    public let zoom: ZoomCapability
    public let flash: [FlashMode]
    public let torch: Bool
    public let photoFormats: [PhotoFormat]
    public let photoSizes: [PixelSize]
    public let hdr: Bool
    public let live: LiveCapability

    public init(
        iso: IntRange?,
        exposureTime: ExposureRangeNs?,
        exposureBias: ExposureBiasCapability?,
        apertures: [Double],
        focus: FocusCapability,
        whiteBalance: WhiteBalanceCapability,
        zoom: ZoomCapability,
        flash: [FlashMode],
        torch: Bool,
        photoFormats: [PhotoFormat],
        photoSizes: [PixelSize],
        hdr: Bool,
        live: LiveCapability
    ) {
        self.iso = iso
        self.exposureTime = exposureTime
        self.exposureBias = exposureBias
        self.apertures = apertures
        self.focus = focus
        self.whiteBalance = whiteBalance
        self.zoom = zoom
        self.flash = flash
        self.torch = torch
        self.photoFormats = photoFormats
        self.photoSizes = photoSizes
        self.hdr = hdr
        self.live = live
    }

    /// Manual exposure needs BOTH ranges: iOS custom exposure sets ISO and duration together.
    public var supportsManualExposure: Bool { iso != nil && exposureTime != nil }
}
