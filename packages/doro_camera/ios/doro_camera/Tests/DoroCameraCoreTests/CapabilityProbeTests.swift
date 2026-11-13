import XCTest
@testable import DoroCameraCore

/// Fake capture devices: the facts a real AVCaptureDevice would report (ADR-0013). Tests tagged by requirement ID in comments.
enum FakeDevices {
    static func wideBack(overrides: (inout DeviceFacts) -> Void = { _ in }) -> DeviceFacts {
        var facts = DeviceFacts(
            uniqueId: "back-wide",
            position: .back,
            deviceTypeName: "AVCaptureDeviceTypeBuiltInWideAngleCamera",
            minISO: 25,
            maxISO: 3072,
            minExposureSeconds: 1.0 / 40000,
            maxExposureSeconds: 1.0 / 3,
            supportsCustomExposure: true,
            minExposureTargetBias: -8,
            maxExposureTargetBias: 8,
            lensAperture: 1.8,
            horizontalFieldOfViewDegrees: 69.4,
            supportsLockedLensPosition: true,
            minimumFocusDistanceMillimeters: 120,
            maxWhiteBalanceGain: 4,
            minZoom: 1,
            maxZoom: 15,
            switchOverZoomFactors: [2, 5],
            hasFlash: true,
            hasTorch: true,
            supportsHDR: true,
            supportsHEIF: true,
            supportsRAW: true,
            photoSizes: [PixelSize(width: 4032, height: 3024)],
            livePhotoCaptureSupported: true
        )
        overrides(&facts)
        return facts
    }

    static func front() -> DeviceFacts {
        DeviceFacts(
            uniqueId: "front",
            position: .front,
            deviceTypeName: "AVCaptureDeviceTypeBuiltInWideAngleCamera",
            minISO: 50,
            maxISO: 1600,
            minExposureSeconds: 1.0 / 8000,
            maxExposureSeconds: 1.0 / 3,
            supportsCustomExposure: false,
            minExposureTargetBias: -4,
            maxExposureTargetBias: 4,
            horizontalFieldOfViewDegrees: 71,
            supportsLockedLensPosition: false,
            supportsLockedWhiteBalance: false,
            photoSizes: [PixelSize(width: 3088, height: 2316)]
        )
    }
}

final class CapabilityProbeTests: XCTestCase {
    // [CAM-004] ranges come from the device, never from a model name
    func testReadsManualRangesFromTheActiveFormat() {
        let caps = CapabilityProbe.capabilities(for: FakeDevices.wideBack())
        XCTAssertEqual(caps.iso, IntRange(min: 25, max: 3072))
        XCTAssertEqual(caps.exposureTime?.min, 25_000)
        XCTAssertEqual(caps.exposureTime?.max, 333_333_333)
        XCTAssertTrue(caps.supportsManualExposure)
    }

    // [CAM-005] no manual exposure without custom exposure support
    func testHidesManualISOAndShutterWhenCustomExposureIsNotSupported() {
        let caps = CapabilityProbe.capabilities(for: FakeDevices.front())
        XCTAssertNil(caps.iso)
        XCTAssertNil(caps.exposureTime)
        XCTAssertFalse(caps.supportsManualExposure)
    }

    // [CAM-005] invalid ranges are not offered
    func testRejectsDegenerateRanges() {
        let sameISO = FakeDevices.wideBack { $0.maxISO = $0.minISO }
        XCTAssertNil(CapabilityProbe.capabilities(for: sameISO).iso)
        let zeroDuration = FakeDevices.wideBack { $0.minExposureSeconds = 0 }
        XCTAssertNil(CapabilityProbe.capabilities(for: zeroDuration).exposureTime)
        let noBias = FakeDevices.wideBack { $0.maxExposureTargetBias = $0.minExposureTargetBias }
        XCTAssertNil(CapabilityProbe.capabilities(for: noBias).exposureBias)
    }

    // [CAM-012]
    func testReportsExposureBiasRangeWithAThirdOfAStop() {
        let bias = CapabilityProbe.capabilities(for: FakeDevices.wideBack()).exposureBias
        XCTAssertEqual(bias?.range, DoubleRange(min: -8, max: 8))
        XCTAssertEqual(bias?.step ?? 0, 1.0 / 3.0, accuracy: 1e-9)
    }

    // [CAM-013] aperture is display-only: one value, from lensAperture
    func testApertureIsASingleReadOnlyValue() {
        XCTAssertEqual(CapabilityProbe.capabilities(for: FakeDevices.wideBack()).apertures, [1.8 as Float].map(Double.init))
        XCTAssertEqual(CapabilityProbe.capabilities(for: FakeDevices.front()).apertures, [])
    }

    // [CAM-021] iOS reports a lens position, never calibrated distances
    func testManualFocusIsUncalibratedAndOnlyWhenLockedLensPositionIsSupported() {
        let manual = CapabilityProbe.capabilities(for: FakeDevices.wideBack()).focus.manual
        XCTAssertEqual(manual?.calibration, .uncalibrated)
        XCTAssertEqual(manual?.minFocusDistanceDiopters ?? 0, 1000.0 / 120.0, accuracy: 1e-9)
        XCTAssertNil(CapabilityProbe.capabilities(for: FakeDevices.front()).focus.manual)
        // an unknown closest distance means there is no honest range, so no manual focus
        let unknown = FakeDevices.wideBack { $0.minimumFocusDistanceMillimeters = nil }
        XCTAssertNil(CapabilityProbe.capabilities(for: unknown).focus.manual)
        let negative = FakeDevices.wideBack { $0.minimumFocusDistanceMillimeters = -1 }
        XCTAssertNil(CapabilityProbe.capabilities(for: negative).focus.manual)
    }

    // [CAM-030][CAM-031]
    func testWhiteBalanceNeedsLockedGainsForPresetsAndKelvin() {
        let rich = CapabilityProbe.capabilities(for: FakeDevices.wideBack()).whiteBalance
        XCTAssertEqual(rich.presets, WhiteBalancePreset.allCases)
        XCTAssertEqual(rich.kelvin, IntRange(min: 2000, max: 10000))
        let poor = CapabilityProbe.capabilities(for: FakeDevices.front()).whiteBalance
        XCTAssertEqual(poor.presets, [.auto])
        XCTAssertNil(poor.kelvin)
    }

    // [CAM-008] optical steps are the lens switch-over factors within range
    func testOpticalZoomStepsComeFromSwitchOverFactors() {
        let zoom = CapabilityProbe.capabilities(for: FakeDevices.wideBack()).zoom
        XCTAssertEqual(zoom.opticalSteps, [1, 2, 5])
        XCTAssertEqual(zoom.max, 15)
        let beyond = FakeDevices.wideBack { $0.switchOverZoomFactors = [0.5, 2, 99] }
        XCTAssertEqual(CapabilityProbe.capabilities(for: beyond).zoom.opticalSteps, [1, 2])
    }

    // [CAM-040]
    func testFlashAndTorchOnlyWhenTheHardwareHasThem() {
        let withFlash = CapabilityProbe.capabilities(for: FakeDevices.wideBack())
        XCTAssertEqual(withFlash.flash, [.off, .auto, .on])
        XCTAssertTrue(withFlash.torch)
        let without = CapabilityProbe.capabilities(for: FakeDevices.front())
        XCTAssertEqual(without.flash, [])
        XCTAssertFalse(without.torch)
    }

    // [CAM-046]
    func testPhotoFormatsListHeifFirstAndDngOnlyWithRaw() {
        XCTAssertEqual(CapabilityProbe.capabilities(for: FakeDevices.wideBack()).photoFormats, [.heif, .jpeg, .dng])
        let noHeif = FakeDevices.wideBack { $0.supportsHEIF = false; $0.supportsRAW = false }
        XCTAssertEqual(CapabilityProbe.capabilities(for: noHeif).photoFormats, [.jpeg])
    }

    // [MOT-003]
    func testLiveAudioFollowsTheMicrophone() {
        XCTAssertTrue(CapabilityProbe.capabilities(for: FakeDevices.wideBack()).live.audio)
        let mute = FakeDevices.wideBack { $0.hasMicrophone = false }
        XCTAssertFalse(CapabilityProbe.capabilities(for: mute).live.audio)
        XCTAssertEqual(CapabilityProbe.capabilities(for: mute).live.maxPreBufferMs, CapabilityProbe.defaultMaxPreBufferMs)
    }

    // [CAM-006]
    func testLensKindFromDeviceTypeAndPosition() {
        func kind(_ name: String, _ position: CameraFacing = .back) -> LensKind {
            CapabilityProbe.lensKind(for: FakeDevices.wideBack { $0.deviceTypeName = name; $0.position = position })
        }
        XCTAssertEqual(kind("AVCaptureDeviceTypeBuiltInUltraWideCamera"), .ultraWide)
        XCTAssertEqual(kind("AVCaptureDeviceTypeBuiltInTelephotoCamera"), .tele)
        XCTAssertEqual(kind("AVCaptureDeviceTypeBuiltInWideAngleCamera"), .wide)
        XCTAssertEqual(kind("AVCaptureDeviceTypeBuiltInTripleCamera"), .wide)
        XCTAssertEqual(kind("AVCaptureDeviceTypeBuiltInTrueDepthCamera"), .other)
        XCTAssertEqual(kind("AVCaptureDeviceTypeBuiltInWideAngleCamera", .front), .front)
    }

    // [CAM-007] 35 mm equivalent from field of view, never guessed
    func testEquivalentFocalLengthFromFieldOfView() {
        XCTAssertEqual(CapabilityProbe.equivalentFocalLength35mm(horizontalFieldOfViewDegrees: 63.4) ?? 0, 29.2, accuracy: 0.3)
        XCTAssertEqual(CapabilityProbe.equivalentFocalLength35mm(horizontalFieldOfViewDegrees: 90) ?? 0, 18, accuracy: 1e-6)
        XCTAssertNil(CapabilityProbe.equivalentFocalLength35mm(horizontalFieldOfViewDegrees: nil))
        XCTAssertNil(CapabilityProbe.equivalentFocalLength35mm(horizontalFieldOfViewDegrees: 0))
        XCTAssertNil(CapabilityProbe.equivalentFocalLength35mm(horizontalFieldOfViewDegrees: 180))
    }

    func testDescriptorIsHardwareAndCarriesTheEquivalentFocalLength() {
        let descriptor = CapabilityProbe.descriptor(for: FakeDevices.wideBack())
        XCTAssertEqual(descriptor.id, "back-wide")
        XCTAssertEqual(descriptor.source, .hardware)
        XCTAssertEqual(descriptor.lensKind, .wide)
        XCTAssertNotNil(descriptor.focalLength35mmEq)
        XCTAssertNil(CapabilityProbe.descriptor(for: FakeDevices.wideBack { $0.horizontalFieldOfViewDegrees = nil }).focalLength35mmEq)
    }

    func testRangeHelpers() {
        let ints = IntRange(min: 10, max: 20)
        XCTAssertEqual([5, 10, 15, 20, 25].map(ints.clamped), [10, 10, 15, 20, 20])
        XCTAssertTrue(ints.contains(10)); XCTAssertFalse(ints.contains(21))
        let doubles = DoubleRange(min: -1, max: 1)
        XCTAssertEqual(doubles.clamped(5), 1); XCTAssertTrue(doubles.contains(0)); XCTAssertFalse(doubles.contains(-1.5))
        XCTAssertEqual(ExposureRangeNs(min: 5, max: 9).clamped(1), 5)
        XCTAssertEqual(PixelSize(width: 4000, height: 3000).megapixels, 12, accuracy: 1e-9)
    }
}
