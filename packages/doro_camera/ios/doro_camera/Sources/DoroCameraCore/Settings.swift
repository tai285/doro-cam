import Foundation

// Native-side view of capture settings. Product logic (scenarios, presets, intent resolution) lives in
// Dart (ADR-0001). Dart sends already-resolved values; this layer clamps again as a safety net and
// reports honestly what the device accepted (CAM-050). It never invents a capability.

public enum ExposureMode: String, Equatable, Sendable {
    case auto
    case manual
}

public enum FocusMode: String, Equatable, Sendable {
    case continuous
    /// One autofocus run, then hold.
    case auto
    /// Distance set by the user in diopters; uncalibrated on iOS (CAM-021).
    case manual
}

/// Diopters (1 / metres) to the normalized lens position AVFoundation takes (0 = nearest, 1 = farthest).
public enum FocusMath {
    public static func lensPosition(forDiopters diopters: Double, minFocusDiopters: Double) -> Double {
        guard minFocusDiopters > 0 else { return 1 }
        let fraction = Swift.min(Swift.max(diopters / minFocusDiopters, 0), 1)
        return 1 - fraction
    }

    public static func diopters(forLensPosition position: Double, minFocusDiopters: Double) -> Double {
        (1 - Swift.min(Swift.max(position, 0), 1)) * Swift.max(minFocusDiopters, 0)
    }
}

public enum WhiteBalanceMode: Equatable, Sendable {
    case auto
    case preset(WhiteBalancePreset)
    case kelvin(Int)
}

/// What Dart asks the device to do. `nil` fields mean "leave automatic".
public struct RequestedSettings: Equatable, Sendable {
    public var iso: Int?
    public var exposureTimeNs: Int64?
    public var exposureBiasEV: Double?
    public var exposureLocked: Bool
    public var focusMode: FocusMode
    public var focusDiopters: Double?
    public var focusLocked: Bool
    public var whiteBalance: WhiteBalanceMode
    public var zoomFactor: Double
    public var flash: FlashMode
    public var torch: Bool

    public init(
        iso: Int? = nil,
        exposureTimeNs: Int64? = nil,
        exposureBiasEV: Double? = nil,
        exposureLocked: Bool = false,
        focusMode: FocusMode = .continuous,
        focusDiopters: Double? = nil,
        focusLocked: Bool = false,
        whiteBalance: WhiteBalanceMode = .auto,
        zoomFactor: Double = 1,
        flash: FlashMode = .off,
        torch: Bool = false
    ) {
        self.iso = iso
        self.exposureTimeNs = exposureTimeNs
        self.exposureBiasEV = exposureBiasEV
        self.exposureLocked = exposureLocked
        self.focusMode = focusMode
        self.focusDiopters = focusDiopters
        self.focusLocked = focusLocked
        self.whiteBalance = whiteBalance
        self.zoomFactor = zoomFactor
        self.flash = flash
        self.torch = torch
    }
}

public enum AdjustmentReason: String, Equatable, Sendable {
    case outOfRange
    case unsupported
    case notApplicableInManual
    case deviceReportedDifferent
}

/// "You asked for X, the device used Y, because Z" (EXP-008).
public struct Adjustment: Equatable, Sendable {
    public let field: String
    public let requested: String
    public let applied: String
    public let reason: AdjustmentReason

    public init(field: String, requested: String, applied: String, reason: AdjustmentReason) {
        self.field = field
        self.requested = requested
        self.applied = applied
        self.reason = reason
    }
}

/// What the device will be asked to do after the safety clamp.
public struct EffectiveSettings: Equatable, Sendable {
    public var exposureMode: ExposureMode
    public var iso: Int?
    public var exposureTimeNs: Int64?
    public var exposureBiasEV: Double?
    public var exposureLocked: Bool
    public var focusMode: FocusMode
    public var focusDiopters: Double?
    public var focusLocked: Bool
    public var whiteBalance: WhiteBalanceMode
    public var zoomFactor: Double
    public var flash: FlashMode
    public var torch: Bool

    public init(
        exposureMode: ExposureMode,
        iso: Int?,
        exposureTimeNs: Int64?,
        exposureBiasEV: Double?,
        exposureLocked: Bool,
        focusMode: FocusMode,
        focusDiopters: Double?,
        focusLocked: Bool,
        whiteBalance: WhiteBalanceMode,
        zoomFactor: Double,
        flash: FlashMode,
        torch: Bool
    ) {
        self.exposureMode = exposureMode
        self.iso = iso
        self.exposureTimeNs = exposureTimeNs
        self.exposureBiasEV = exposureBiasEV
        self.exposureLocked = exposureLocked
        self.focusMode = focusMode
        self.focusDiopters = focusDiopters
        self.focusLocked = focusLocked
        self.whiteBalance = whiteBalance
        self.zoomFactor = zoomFactor
        self.flash = flash
        self.torch = torch
    }
}

public enum SettingsClamp {
    /// Clamps a request into the capabilities. Total: never throws, never returns something outside the ranges.
    public static func effective(
        _ requested: RequestedSettings,
        capabilities caps: CameraCapabilities
    ) -> (settings: EffectiveSettings, adjustments: [Adjustment]) {
        var adjustments: [Adjustment] = []
        var exposureMode = ExposureMode.auto
        var iso: Int?
        var exposureTime: Int64?

        let wantsManual = requested.iso != nil || requested.exposureTimeNs != nil
        if wantsManual {
            if let isoRange = caps.iso, let durationRange = caps.exposureTime {
                exposureMode = .manual
                if let value = requested.iso {
                    let applied = isoRange.clamped(value)
                    iso = applied
                    if applied != value {
                        adjustments.append(Adjustment(field: "iso", requested: String(value), applied: String(applied), reason: .outOfRange))
                    }
                }
                if let value = requested.exposureTimeNs {
                    let applied = durationRange.clamped(value)
                    exposureTime = applied
                    if applied != value {
                        adjustments.append(
                            Adjustment(field: "exposureTimeNs", requested: String(value), applied: String(applied), reason: .outOfRange)
                        )
                    }
                }
            } else {
                // iOS custom exposure needs both ranges; without them the control does not exist.
                if let value = requested.iso {
                    adjustments.append(Adjustment(field: "iso", requested: String(value), applied: "auto", reason: .unsupported))
                }
                if let value = requested.exposureTimeNs {
                    adjustments.append(Adjustment(field: "exposureTimeNs", requested: String(value), applied: "auto", reason: .unsupported))
                }
            }
        }

        var bias: Double?
        if let value = requested.exposureBiasEV {
            if exposureMode == .manual {
                adjustments.append(
                    Adjustment(field: "exposureBiasEV", requested: format(value), applied: "ignored", reason: .notApplicableInManual)
                )
            } else if let capability = caps.exposureBias {
                let applied = capability.range.clamped(value)
                bias = applied
                if applied != value {
                    adjustments.append(
                        Adjustment(field: "exposureBiasEV", requested: format(value), applied: format(applied), reason: .outOfRange)
                    )
                }
            } else {
                adjustments.append(Adjustment(field: "exposureBiasEV", requested: format(value), applied: "0", reason: .unsupported))
            }
        }

        var focusMode = requested.focusMode
        var focusDiopters: Double?
        if requested.focusMode == .manual {
            if let manual = caps.focus.manual, let diopters = requested.focusDiopters {
                let applied = DoubleRange(min: 0, max: manual.minFocusDistanceDiopters).clamped(diopters)
                focusDiopters = applied
                if applied != diopters {
                    adjustments.append(
                        Adjustment(field: "focusDistanceDiopters", requested: format(diopters), applied: format(applied), reason: .outOfRange)
                    )
                }
            } else {
                focusMode = .continuous
                adjustments.append(Adjustment(field: "focus", requested: "manual", applied: "continuous", reason: .unsupported))
            }
        }

        var whiteBalance = requested.whiteBalance
        switch requested.whiteBalance {
        case .auto:
            break
        case .preset(let preset):
            if preset != .auto && !caps.whiteBalance.presets.contains(preset) {
                whiteBalance = .auto
                adjustments.append(Adjustment(field: "whiteBalance", requested: preset.rawValue, applied: "auto", reason: .unsupported))
            }
        case .kelvin(let kelvin):
            if let range = caps.whiteBalance.kelvin {
                let applied = range.clamped(kelvin)
                whiteBalance = .kelvin(applied)
                if applied != kelvin {
                    adjustments.append(
                        Adjustment(field: "whiteBalanceKelvin", requested: String(kelvin), applied: String(applied), reason: .outOfRange)
                    )
                }
            } else {
                whiteBalance = .auto
                adjustments.append(Adjustment(field: "whiteBalanceKelvin", requested: String(kelvin), applied: "auto", reason: .unsupported))
            }
        }

        let zoom = DoubleRange(min: caps.zoom.min, max: caps.zoom.max).clamped(requested.zoomFactor)
        if zoom != requested.zoomFactor {
            adjustments.append(Adjustment(field: "zoomFactor", requested: format(requested.zoomFactor), applied: format(zoom), reason: .outOfRange))
        }

        var flash = requested.flash
        if flash != .off && !caps.flash.contains(flash) {
            flash = .off
            adjustments.append(Adjustment(field: "flash", requested: requested.flash.rawValue, applied: "off", reason: .unsupported))
        }
        var torch = requested.torch
        if torch && !caps.torch {
            torch = false
            adjustments.append(Adjustment(field: "torch", requested: "on", applied: "off", reason: .unsupported))
        }

        return (
            EffectiveSettings(
                exposureMode: exposureMode,
                iso: iso,
                exposureTimeNs: exposureTime,
                exposureBiasEV: bias,
                exposureLocked: requested.exposureLocked,
                focusMode: focusMode,
                focusDiopters: focusDiopters,
                focusLocked: requested.focusLocked,
                whiteBalance: whiteBalance,
                zoomFactor: zoom,
                flash: flash,
                torch: torch
            ),
            adjustments
        )
    }

    private static func format(_ value: Double) -> String {
        let text = String(format: "%.3f", value)
        var trimmed = text
        while trimmed.hasSuffix("0") { trimmed.removeLast() }
        if trimmed.hasSuffix(".") { trimmed.removeLast() }
        return trimmed.isEmpty ? "0" : trimmed
    }
}

/// What the device reported back after a capture (from AVCapturePhoto metadata and device state).
public struct AppliedReport: Equatable, Sendable {
    public var iso: Int?
    public var exposureTimeNs: Int64?
    public var exposureBiasEV: Double?
    public var aperture: Double?
    public var focalLength35mmEq: Double?
    public var focusDiopters: Double?
    public var whiteBalanceKelvin: Int?
    public var zoomFactor: Double
    public var flashFired: Bool?
    public var widthPx: Int
    public var heightPx: Int

    public init(
        iso: Int? = nil,
        exposureTimeNs: Int64? = nil,
        exposureBiasEV: Double? = nil,
        aperture: Double? = nil,
        focalLength35mmEq: Double? = nil,
        focusDiopters: Double? = nil,
        whiteBalanceKelvin: Int? = nil,
        zoomFactor: Double = 1,
        flashFired: Bool? = nil,
        widthPx: Int,
        heightPx: Int
    ) {
        self.iso = iso
        self.exposureTimeNs = exposureTimeNs
        self.exposureBiasEV = exposureBiasEV
        self.aperture = aperture
        self.focalLength35mmEq = focalLength35mmEq
        self.focusDiopters = focusDiopters
        self.whiteBalanceKelvin = whiteBalanceKelvin
        self.zoomFactor = zoomFactor
        self.flashFired = flashFired
        self.widthPx = widthPx
        self.heightPx = heightPx
    }
}

public enum AppliedComparison {
    /// Relative tolerance for manual ISO and shutter: sensors quantize to the nearest supported step.
    public static let manualTolerance = 0.08

    /// Lists every place where what the device reports differs from what was effectively requested (CAM-050).
    /// A control whose mismatch persists is disabled by Dart after three captures (docs/specs/camera.md).
    public static func mismatches(effective: EffectiveSettings, reported: AppliedReport) -> [Adjustment] {
        var result: [Adjustment] = []
        if effective.exposureMode == .manual {
            if let want = effective.iso, let got = reported.iso, !within(Double(want), Double(got)) {
                result.append(Adjustment(field: "iso", requested: String(want), applied: String(got), reason: .deviceReportedDifferent))
            }
            if let want = effective.exposureTimeNs, let got = reported.exposureTimeNs, !within(Double(want), Double(got)) {
                result.append(Adjustment(field: "exposureTimeNs", requested: String(want), applied: String(got), reason: .deviceReportedDifferent))
            }
        }
        if let want = effective.focusDiopters, let got = reported.focusDiopters, abs(want - got) > Swift.max(0.5, want * 0.15) {
            result.append(
                Adjustment(field: "focusDistanceDiopters", requested: String(want), applied: String(got), reason: .deviceReportedDifferent)
            )
        }
        if case .kelvin(let want) = effective.whiteBalance, let got = reported.whiteBalanceKelvin,
           abs(Double(want - got)) > Double(want) * 0.1 {
            result.append(
                Adjustment(field: "whiteBalanceKelvin", requested: String(want), applied: String(got), reason: .deviceReportedDifferent)
            )
        }
        return result
    }

    private static func within(_ requested: Double, _ actual: Double) -> Bool {
        guard requested != 0 else { return actual == 0 }
        return abs(actual - requested) / requested <= manualTolerance
    }
}
