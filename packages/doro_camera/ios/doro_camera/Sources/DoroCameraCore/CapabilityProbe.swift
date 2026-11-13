import Foundation

/// Plain facts about one capture device and its active format. The plugin target fills this from
/// `AVCaptureDevice`; tests fill it with fakes ("fake capture devices", ADR-0013). Nothing here is
/// guessed from a device model name (ADR-0002).
public struct DeviceFacts: Equatable, Sendable {
    public var uniqueId: String
    public var position: CameraFacing
    /// `AVCaptureDevice.DeviceType` raw value, for example `AVCaptureDeviceTypeBuiltInUltraWideCamera`.
    public var deviceTypeName: String
    public var isLogical: Bool
    public var constituentIds: [String]

    public var minISO: Float
    public var maxISO: Float
    public var minExposureSeconds: Double
    public var maxExposureSeconds: Double
    public var supportsCustomExposure: Bool
    public var minExposureTargetBias: Float
    public var maxExposureTargetBias: Float

    /// `lensAperture` is read-only on iOS, so apertures is at most one value.
    public var lensAperture: Float?
    /// Horizontal field of view of the active format in degrees.
    public var horizontalFieldOfViewDegrees: Float?

    public var supportsAutoFocus: Bool
    public var supportsContinuousFocus: Bool
    public var supportsFocusPointOfInterest: Bool
    public var supportsLockedLensPosition: Bool
    public var minimumFocusDistanceMillimeters: Int?

    public var supportsLockedWhiteBalance: Bool
    public var maxWhiteBalanceGain: Float

    public var minZoom: Double
    public var maxZoom: Double
    /// `virtualDeviceSwitchOverVideoZoomFactors` (empty on a single physical camera).
    public var switchOverZoomFactors: [Double]

    public var hasFlash: Bool
    public var hasTorch: Bool
    public var supportsHDR: Bool

    public var supportsHEIF: Bool
    public var supportsRAW: Bool
    public var photoSizes: [PixelSize]

    public var livePhotoCaptureSupported: Bool
    public var hasMicrophone: Bool

    public init(
        uniqueId: String,
        position: CameraFacing,
        deviceTypeName: String,
        isLogical: Bool = false,
        constituentIds: [String] = [],
        minISO: Float,
        maxISO: Float,
        minExposureSeconds: Double,
        maxExposureSeconds: Double,
        supportsCustomExposure: Bool,
        minExposureTargetBias: Float,
        maxExposureTargetBias: Float,
        lensAperture: Float? = nil,
        horizontalFieldOfViewDegrees: Float? = nil,
        supportsAutoFocus: Bool = true,
        supportsContinuousFocus: Bool = true,
        supportsFocusPointOfInterest: Bool = true,
        supportsLockedLensPosition: Bool = false,
        minimumFocusDistanceMillimeters: Int? = nil,
        supportsLockedWhiteBalance: Bool = true,
        maxWhiteBalanceGain: Float = 4,
        minZoom: Double = 1,
        maxZoom: Double = 1,
        switchOverZoomFactors: [Double] = [],
        hasFlash: Bool = false,
        hasTorch: Bool = false,
        supportsHDR: Bool = false,
        supportsHEIF: Bool = true,
        supportsRAW: Bool = false,
        photoSizes: [PixelSize] = [],
        livePhotoCaptureSupported: Bool = false,
        hasMicrophone: Bool = true
    ) {
        self.uniqueId = uniqueId
        self.position = position
        self.deviceTypeName = deviceTypeName
        self.isLogical = isLogical
        self.constituentIds = constituentIds
        self.minISO = minISO
        self.maxISO = maxISO
        self.minExposureSeconds = minExposureSeconds
        self.maxExposureSeconds = maxExposureSeconds
        self.supportsCustomExposure = supportsCustomExposure
        self.minExposureTargetBias = minExposureTargetBias
        self.maxExposureTargetBias = maxExposureTargetBias
        self.lensAperture = lensAperture
        self.horizontalFieldOfViewDegrees = horizontalFieldOfViewDegrees
        self.supportsAutoFocus = supportsAutoFocus
        self.supportsContinuousFocus = supportsContinuousFocus
        self.supportsFocusPointOfInterest = supportsFocusPointOfInterest
        self.supportsLockedLensPosition = supportsLockedLensPosition
        self.minimumFocusDistanceMillimeters = minimumFocusDistanceMillimeters
        self.supportsLockedWhiteBalance = supportsLockedWhiteBalance
        self.maxWhiteBalanceGain = maxWhiteBalanceGain
        self.minZoom = minZoom
        self.maxZoom = maxZoom
        self.switchOverZoomFactors = switchOverZoomFactors
        self.hasFlash = hasFlash
        self.hasTorch = hasTorch
        self.supportsHDR = supportsHDR
        self.supportsHEIF = supportsHEIF
        self.supportsRAW = supportsRAW
        self.photoSizes = photoSizes
        self.livePhotoCaptureSupported = livePhotoCaptureSupported
        self.hasMicrophone = hasMicrophone
    }
}

/// Turns device facts into the capability model. Every rule here mirrors "Probe rules" in docs/specs/camera.md.
public enum CapabilityProbe {
    /// Default pre-roll the Live buffer offers. The product asks for about 1.5 s before the shutter.
    public static let defaultMaxPreBufferMs = 2000
    /// iOS reports no exposure-bias step; Dart presents thirds of a stop.
    public static let exposureBiasStepEV = 1.0 / 3.0

    public static func lensKind(for facts: DeviceFacts) -> LensKind {
        if facts.position == .front { return .front }
        let name = facts.deviceTypeName.lowercased()
        if name.contains("ultrawide") { return .ultraWide }
        if name.contains("telephoto") { return .tele }
        if name.contains("wideangle") || name.contains("dual") || name.contains("triple") { return .wide }
        return .other
    }

    /// 35 mm equivalent from the horizontal field of view: f = (36 mm / 2) / tan(fov / 2).
    /// Returns nil without a usable field of view, never a guess (CAM-007).
    public static func equivalentFocalLength35mm(horizontalFieldOfViewDegrees fov: Float?) -> Double? {
        guard let fov = fov, fov > 1, fov < 179 else { return nil }
        let radians = Double(fov) * Double.pi / 180
        return 18.0 / tan(radians / 2)
    }

    public static func descriptor(for facts: DeviceFacts) -> CameraDescriptor {
        let equivalent = equivalentFocalLength35mm(horizontalFieldOfViewDegrees: facts.horizontalFieldOfViewDegrees)
        return CameraDescriptor(
            id: facts.uniqueId,
            facing: facts.position,
            lensKind: lensKind(for: facts),
            isLogical: facts.isLogical,
            physicalIds: facts.constituentIds,
            // iPhone camera sensors are mounted in landscape; the app locks capture rotation to device orientation.
            sensorOrientationDegrees: 90,
            focalLengthMm: nil,
            focalLength35mmEq: equivalent.map { ($0 * 10).rounded() / 10 },
            source: .hardware
        )
    }

    public static func capabilities(for facts: DeviceFacts) -> CameraCapabilities {
        // Manual ISO and shutter are exposed only when custom exposure is supported AND the ranges are valid.
        let validISO = facts.minISO > 0 && facts.maxISO > facts.minISO
        let validDuration = facts.minExposureSeconds > 0 && facts.maxExposureSeconds > facts.minExposureSeconds
        let manual = facts.supportsCustomExposure && validISO && validDuration

        let validBias = facts.maxExposureTargetBias > facts.minExposureTargetBias
        var apertures: [Double] = []
        if let aperture = facts.lensAperture, aperture > 0 {
            apertures = [Double(aperture)]
        }

        // Manual focus is offered only when the lens position can be locked AND the closest focus distance
        // is known; without it there is no honest range for the control.
        var manualFocus: ManualFocusCapability?
        if facts.supportsLockedLensPosition, let millimeters = facts.minimumFocusDistanceMillimeters, millimeters > 0 {
            manualFocus = ManualFocusCapability(calibration: .uncalibrated, minFocusDistanceDiopters: 1000.0 / Double(millimeters))
        }

        // Locked gains allow every preset and Kelvin; without them only automatic white balance is real.
        let whiteBalance: WhiteBalanceCapability = facts.supportsLockedWhiteBalance
            ? WhiteBalanceCapability(presets: WhiteBalancePreset.allCases, kelvin: IntRange(min: 2000, max: 10000))
            : WhiteBalanceCapability(presets: [.auto], kelvin: nil)

        var flash: [FlashMode] = []
        if facts.hasFlash { flash = FlashMode.allCases }

        var formats: [PhotoFormat] = [.jpeg]
        if facts.supportsHEIF { formats.insert(.heif, at: 0) }
        if facts.supportsRAW { formats.append(.dng) }

        let steps = ([facts.minZoom] + facts.switchOverZoomFactors.filter { $0 > facts.minZoom && $0 <= facts.maxZoom }).sorted()

        return CameraCapabilities(
            iso: manual ? IntRange(min: Int(facts.minISO.rounded(.up)), max: Int(facts.maxISO.rounded(.down))) : nil,
            exposureTime: manual
                ? ExposureRangeNs(
                    min: Int64((facts.minExposureSeconds * 1e9).rounded(.up)),
                    max: Int64((facts.maxExposureSeconds * 1e9).rounded(.down))
                )
                : nil,
            exposureBias: validBias
                ? ExposureBiasCapability(
                    range: DoubleRange(min: Double(facts.minExposureTargetBias), max: Double(facts.maxExposureTargetBias)),
                    step: exposureBiasStepEV
                )
                : nil,
            apertures: apertures,
            focus: FocusCapability(
                auto: facts.supportsAutoFocus,
                continuous: facts.supportsContinuousFocus,
                tapToFocus: facts.supportsFocusPointOfInterest,
                manual: manualFocus
            ),
            whiteBalance: whiteBalance,
            zoom: ZoomCapability(min: facts.minZoom, max: Swift.max(facts.minZoom, facts.maxZoom), opticalSteps: steps),
            flash: flash,
            torch: facts.hasTorch,
            photoFormats: formats,
            photoSizes: facts.photoSizes,
            hdr: facts.supportsHDR,
            live: LiveCapability(
                supported: true,
                maxPreBufferMs: defaultMaxPreBufferMs,
                audio: facts.hasMicrophone
            )
        )
    }
}
