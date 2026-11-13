import DoroCameraCore
import Foundation

// Mapping between the Pigeon messages and the Flutter-free core types. Anything with a branch worth
// testing belongs in DoroCameraCore; this file is conversion only (ADR-0015).

extension CameraFacingMessage {
    init(_ value: CameraFacing) {
        switch value {
        case .back: self = .back
        case .front: self = .front
        case .external: self = .external
        }
    }
}

extension LensKindMessage {
    init(_ value: LensKind) {
        switch value {
        case .ultraWide: self = .ultraWide
        case .wide: self = .wide
        case .tele: self = .tele
        case .front: self = .front
        case .other: self = .other
        }
    }
}

extension CameraSourceMessage {
    init(_ value: CameraSource) {
        switch value {
        case .hardware: self = .hardware
        case .synthetic: self = .synthetic
        }
    }
}

extension PhotoFormatMessage {
    init(_ value: PhotoFormat) {
        switch value {
        case .heif: self = .heif
        case .jpeg: self = .jpeg
        case .dng: self = .dng
        }
    }

    var core: PhotoFormat {
        switch self {
        case .heif: return .heif
        case .jpeg: return .jpeg
        case .dng: return .dng
        }
    }
}

extension WbPresetMessage {
    init(_ value: WhiteBalancePreset) {
        switch value {
        case .auto: self = .auto
        case .daylight: self = .daylight
        case .cloudy: self = .cloudy
        case .shade: self = .shade
        case .tungsten: self = .tungsten
        case .fluorescent: self = .fluorescent
        }
    }

    var core: WhiteBalancePreset {
        switch self {
        case .auto: return .auto
        case .daylight: return .daylight
        case .cloudy: return .cloudy
        case .shade: return .shade
        case .tungsten: return .tungsten
        case .fluorescent: return .fluorescent
        }
    }
}

extension FlashModeMessage {
    init(_ value: FlashMode) {
        switch value {
        case .off: self = .off
        case .auto: self = .auto
        case .on: self = .on
        }
    }

    var core: FlashMode {
        switch self {
        case .off: return .off
        case .auto: return .auto
        case .on: return .on
        }
    }
}

extension FocusModeMessage {
    init(_ value: FocusMode) {
        switch value {
        case .continuous: self = .continuous
        case .auto: self = .auto
        case .manual: self = .manual
        }
    }

    var core: FocusMode {
        switch self {
        case .continuous: return .continuous
        case .auto: return .auto
        case .manual: return .manual
        }
    }
}

extension PermissionStatusMessage {
    init(_ value: AuthorizationState) {
        switch value {
        case .authorized: self = .granted
        case .denied: self = .denied
        case .restricted: self = .restricted
        case .notDetermined: self = .notDetermined
        }
    }
}

extension ThermalStateMessage {
    init(_ value: ThermalLevel) {
        switch value {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        }
    }
}

extension SizeMessage {
    init(_ size: PixelSize) {
        self.init(width: Int64(size.width), height: Int64(size.height))
    }
}

extension CameraDescriptorMessage {
    init(_ descriptor: CameraDescriptor, label: String) {
        self.init(
            id: descriptor.id,
            facing: CameraFacingMessage(descriptor.facing),
            lensKind: LensKindMessage(descriptor.lensKind),
            isLogical: descriptor.isLogical,
            physicalIds: descriptor.physicalIds,
            sensorOrientation: Int64(descriptor.sensorOrientationDegrees),
            source: CameraSourceMessage(descriptor.source),
            label: label,
            focalLengthMm: descriptor.focalLengthMm,
            focalLength35mmEq: descriptor.focalLength35mmEq
        )
    }
}

extension CameraCapabilitiesMessage {
    /// `video` is what this plugin really records (the session's frame size), never a wish list.
    init(cameraId: String, _ caps: CameraCapabilities, stabilizationVideo: [StabilizationModeMessage], videoSize: PixelSize?, videoFps: Int) {
        var manual: ManualFocusCapabilityMessage?
        if let capability = caps.focus.manual {
            manual = ManualFocusCapabilityMessage(
                minFocusDistanceDiopters: capability.minFocusDistanceDiopters,
                calibration: .uncalibrated
            )
        }
        var videoOptions: [VideoSizeOptionMessage] = []
        if let size = videoSize {
            videoOptions.append(VideoSizeOptionMessage(size: SizeMessage(size), fps: [Int64(videoFps)]))
        }
        self.init(
            cameraId: cameraId,
            iso: caps.iso.map { IntRangeMessage(min: Int64($0.min), max: Int64($0.max)) },
            exposureTimeNs: caps.exposureTime.map { IntRangeMessage(min: $0.min, max: $0.max) },
            exposureBias: caps.exposureBias.map {
                ExposureBiasCapabilityMessage(range: DoubleRangeMessage(min: $0.range.min, max: $0.range.max), step: $0.step)
            },
            apertures: caps.apertures,
            focus: FocusCapabilitiesMessage(auto: caps.focus.auto, continuous: caps.focus.continuous, tapToFocus: caps.focus.tapToFocus, manual: manual),
            whiteBalance: WhiteBalanceCapabilitiesMessage(
                presets: caps.whiteBalance.presets.map { WbPresetMessage($0) },
                kelvin: caps.whiteBalance.kelvin.map { IntRangeMessage(min: Int64($0.min), max: Int64($0.max)) }
            ),
            zoom: ZoomCapabilitiesMessage(min: caps.zoom.min, max: caps.zoom.max, opticalSteps: caps.zoom.opticalSteps),
            flash: caps.flash.map { FlashModeMessage($0) },
            torch: caps.torch,
            photoFormats: caps.photoFormats.map { PhotoFormatMessage($0) },
            photoSizes: caps.photoSizes.map { SizeMessage($0) },
            // Photo stabilization is not controllable on iOS (the system decides), so no modes are offered.
            stabilization: StabilizationCapabilitiesMessage(photo: [], video: stabilizationVideo),
            video: VideoCapabilitiesMessage(options: videoOptions, audio: caps.live.audio),
            hdr: caps.hdr,
            live: LiveCapabilitiesMessage(supported: caps.live.supported, maxPreBufferMs: Int64(caps.live.maxPreBufferMs), audio: caps.live.audio),
            hardwareLevel: "n/a"
        )
    }
}

extension RequestedSettings {
    /// Dart sends values already resolved against the capabilities; the core clamps again as a safety net.
    init(_ message: ResolvedCaptureSettingsMessage) {
        var balance = WhiteBalanceMode.auto
        if let kelvin = message.kelvin {
            balance = .kelvin(Int(kelvin))
        } else if let preset = message.whiteBalancePreset, preset != .auto {
            balance = .preset(preset.core)
        }
        self.init(
            iso: message.iso.map { Int($0) },
            exposureTimeNs: message.exposureTimeNs,
            exposureBiasEV: message.exposureBiasEv,
            exposureLocked: message.aeLock,
            focusMode: message.focusMode.core,
            focusDiopters: message.focusDistanceDiopters,
            focusLocked: message.afLock,
            whiteBalance: balance,
            zoomFactor: message.zoomRatio,
            flash: message.flash.core,
            torch: message.torch
        )
    }
}

extension AppliedSettingsMessage {
    init(report: AppliedReport, effective: EffectiveSettings, mismatches: [String], flashFired: Bool? = nil) {
        var balanceName = "auto"
        switch effective.whiteBalance {
        case .auto: balanceName = "auto"
        case .preset(let preset): balanceName = preset.rawValue
        case .kelvin: balanceName = "manual"
        }
        self.init(
            iso: report.iso.map { Int64($0) },
            exposureTimeNs: report.exposureTimeNs,
            exposureBiasEv: report.exposureBiasEV,
            aperture: report.aperture,
            focalLengthMm: nil,
            focusDistanceDiopters: report.focusDiopters,
            focusMode: FocusModeMessage(effective.focusMode),
            whiteBalanceMode: balanceName,
            whiteBalanceGains: nil,
            estimatedKelvin: report.whiteBalanceKelvin.map { Int64($0) },
            aeLocked: effective.exposureLocked,
            afLocked: effective.focusLocked,
            zoomRatio: report.zoomFactor,
            flashFired: flashFired ?? report.flashFired,
            flash: FlashModeMessage(effective.flash),
            stabilization: nil,
            mismatches: mismatches
        )
    }
}

extension CameraError {
    /// Errors cross the bridge as a stable code plus message (docs/specs/camera.md).
    var pigeon: PigeonError {
        PigeonError(code: code.rawValue, message: message, details: nil)
    }
}
