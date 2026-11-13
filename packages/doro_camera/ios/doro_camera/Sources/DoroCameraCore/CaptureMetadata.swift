import Foundation

/// The settings actually applied at capture, as the device reported them (CAM-050, MEM-002), shaped as
/// the JSON-like dictionary the API stores in `capture`. Keys match packages/api-contract/openapi.json
/// (`isoApplied`, `exposureTimeNsApplied`, `focalLength35mmEq`, `aperture`, `lensKind`, ...).
public enum CaptureMetadataBuilder {
    public static func build(
        descriptor: CameraDescriptor,
        report: AppliedReport,
        effective: EffectiveSettings,
        adjustments: [Adjustment],
        format: PhotoFormat,
        deviceModel: String,
        osVersion: String,
        appVersion: String,
        syntheticSource: Bool
    ) -> [String: MetadataValue] {
        var capture: [String: MetadataValue] = [
            "deviceMake": .string("Apple"),
            "deviceModel": .string(deviceModel),
            "platform": .string("ios"),
            "osVersion": .string(osVersion),
            "appVersion": .string(appVersion),
            "cameraId": .string(descriptor.id),
            "lensKind": .string(descriptor.lensKind.rawValue),
            "widthPx": .int(report.widthPx),
            "heightPx": .int(report.heightPx),
            "format": .string(format.rawValue),
            "zoomFactor": .double(report.zoomFactor),
            "digitalZoom": .bool(report.zoomFactor > 1 && !isOpticalStep(report.zoomFactor)),
            "flash": .string(effective.flash.rawValue),
            "source": .string(syntheticSource ? CameraSource.synthetic.rawValue : CameraSource.hardware.rawValue),
        ]
        if let value = report.iso { capture["isoApplied"] = .int(value) }
        if let value = report.exposureTimeNs { capture["exposureTimeNsApplied"] = .int64(value) }
        if let value = report.exposureBiasEV { capture["exposureBiasEv"] = .double(value) }
        if let value = report.aperture { capture["aperture"] = .double(value) }
        if let value = report.focalLength35mmEq ?? descriptor.focalLength35mmEq { capture["focalLength35mmEq"] = .double(value) }
        if let kelvin = report.whiteBalanceKelvin {
            capture["whiteBalance"] = .map(["mode": .string(whiteBalanceName(effective.whiteBalance)), "kelvin": .int(kelvin)])
        } else {
            capture["whiteBalance"] = .map(["mode": .string(whiteBalanceName(effective.whiteBalance))])
        }
        var focus: [String: MetadataValue] = ["mode": .string(effective.focusMode.rawValue)]
        if let diopters = report.focusDiopters { focus["distanceDiopters"] = .double(diopters) }
        capture["focus"] = .map(focus)
        if !adjustments.isEmpty {
            capture["adjustments"] = .list(
                adjustments.map {
                    .map([
                        "field": .string($0.field),
                        "requested": .string($0.requested),
                        "applied": .string($0.applied),
                        "reason": .string($0.reason.rawValue),
                    ])
                }
            )
        }
        return capture
    }

    private static func whiteBalanceName(_ mode: WhiteBalanceMode) -> String {
        switch mode {
        case .auto: return "auto"
        case .preset(let preset): return preset.rawValue
        case .kelvin: return "kelvin"
        }
    }

    /// Optical lens steps are whole or half factors reported by the device; anything else is digital.
    private static func isOpticalStep(_ zoom: Double) -> Bool {
        zoom == 1
    }
}

/// A tiny JSON-like value, so the core needs neither Foundation JSON types nor Pigeon.
public indirect enum MetadataValue: Equatable, Sendable {
    case string(String)
    case int(Int)
    case int64(Int64)
    case double(Double)
    case bool(Bool)
    case list([MetadataValue])
    case map([String: MetadataValue])

    /// Converts to plain Foundation objects for the bridge or `JSONSerialization`.
    public var foundationObject: Any {
        switch self {
        case .string(let value): return value
        case .int(let value): return value
        case .int64(let value): return NSNumber(value: value)
        case .double(let value): return value
        case .bool(let value): return value
        case .list(let values): return values.map { $0.foundationObject }
        case .map(let values): return values.mapValues { $0.foundationObject }
        }
    }
}
