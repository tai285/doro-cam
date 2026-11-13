import XCTest
@testable import DoroCameraCore

final class ErrorsAndPermissionsTests: XCTestCase {
    // docs/specs/camera.md "Errors": the codes are stable strings clients switch on
    func testErrorCodesMatchTheSpecExactly() {
        XCTAssertEqual(
            CameraErrorCode.allCases.map(\.rawValue),
            ["permission_denied", "permission_restricted", "camera_in_use", "camera_disconnected", "unsupported_configuration", "capture_failed", "storage_full", "thermal_shutdown"]
        )
        XCTAssertEqual(CameraError(.captureFailed, "x"), CameraError(.captureFailed, "x"))
    }

    // [CAM-052]
    func testCameraPermissionStates() {
        XCTAssertNil(PermissionEvaluation.cameraError(for: .authorized))
        XCTAssertNil(PermissionEvaluation.cameraError(for: .notDetermined)) // the caller asks first
        XCTAssertEqual(PermissionEvaluation.cameraError(for: .denied)?.code, .permissionDenied)
        XCTAssertEqual(PermissionEvaluation.cameraError(for: .restricted)?.code, .permissionRestricted)
        XCTAssertFalse(PermissionEvaluation.cameraError(for: .denied)?.message.isEmpty ?? true)
    }

    // [MOT-003]
    func testLiveAudioNeedsPermissionHardwareAndNoMute() {
        XCTAssertTrue(PermissionEvaluation.liveAudioAvailable(microphone: .authorized, deviceHasMicrophone: true, muted: false))
        XCTAssertFalse(PermissionEvaluation.liveAudioAvailable(microphone: .denied, deviceHasMicrophone: true, muted: false))
        XCTAssertFalse(PermissionEvaluation.liveAudioAvailable(microphone: .notDetermined, deviceHasMicrophone: true, muted: false))
        XCTAssertFalse(PermissionEvaluation.liveAudioAvailable(microphone: .authorized, deviceHasMicrophone: false, muted: false))
        XCTAssertFalse(PermissionEvaluation.liveAudioAvailable(microphone: .authorized, deviceHasMicrophone: true, muted: true))
    }
}

final class HelperTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("dorocam-core-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // spec "Edge cases": rotation comes from the device orientation sensor
    func testOrientationMapsToRotationAndExif() {
        XCTAssertEqual(DeviceOrientation.portrait.rotationDegrees, 90)
        XCTAssertEqual(DeviceOrientation.portraitUpsideDown.rotationDegrees, 270)
        XCTAssertEqual(DeviceOrientation.landscapeLeft.rotationDegrees, 180)
        XCTAssertEqual(DeviceOrientation.landscapeRight.rotationDegrees, 0)
        XCTAssertEqual([DeviceOrientation.portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight].map(\.exifOrientation), [6, 8, 3, 1])
    }

    // [CAM-030]
    func testWhiteBalancePresetsAsKelvin() {
        XCTAssertNil(WhiteBalanceMath.kelvin(for: .auto))
        XCTAssertEqual(WhiteBalanceMath.kelvin(for: .daylight), 5500)
        XCTAssertEqual(WhiteBalanceMath.kelvin(for: .cloudy), 6500)
        XCTAssertEqual(WhiteBalanceMath.kelvin(for: .shade), 7500)
        XCTAssertEqual(WhiteBalanceMath.kelvin(for: .tungsten), 3000)
        XCTAssertEqual(WhiteBalanceMath.kelvin(for: .fluorescent), 4200)
        for preset in WhiteBalancePreset.allCases {
            if let kelvin = WhiteBalanceMath.kelvin(for: preset) { XCTAssertTrue(WhiteBalanceMath.kelvinRange.contains(kelvin)) }
        }
    }

    func testGainsAreClampedIntoTheLegalRange() {
        let gains = WhiteBalanceMath.clampGains(red: 0.5, green: 2, blue: 9, maxGain: 4)
        XCTAssertEqual(gains.red, 1); XCTAssertEqual(gains.green, 2); XCTAssertEqual(gains.blue, 4)
        XCTAssertEqual(WhiteBalanceMath.clampGains(red: 3, green: 3, blue: 3, maxGain: 0.2).red, 1) // degenerate max never goes below 1
    }

    func testExposureConversions() {
        XCTAssertEqual(ExposureMath.nanoseconds(fromSeconds: 1.0 / 125), 8_000_000)
        XCTAssertEqual(ExposureMath.seconds(fromNanoseconds: 500_000_000), 0.5, accuracy: 1e-12)
    }

    // [NFR-002] write to .partial, rename when complete
    func testAtomicOutputCommitsACompleteFile() throws {
        let output = AtomicOutput(finalURL: directory.appendingPathComponent("photo.heic"))
        try Data([1, 2, 3]).write(to: output.partialURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.finalURL.path)) // not visible until committed
        try output.commit()
        XCTAssertEqual(try Data(contentsOf: output.finalURL), Data([1, 2, 3]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.partialURL.path))
    }

    func testCommitFailsWithoutAPartialFileAndNeverOverwrites() throws {
        let output = AtomicOutput(finalURL: directory.appendingPathComponent("a.jpg"))
        XCTAssertThrowsError(try output.commit()) { error in XCTAssertEqual((error as? CameraError)?.code, .captureFailed) }
        try Data([9]).write(to: output.finalURL)
        try Data([1]).write(to: output.partialURL)
        XCTAssertThrowsError(try output.commit())
        XCTAssertEqual(try Data(contentsOf: output.finalURL), Data([9]))
    }

    func testDiscardRemovesThePartialFile() throws {
        let output = AtomicOutput(finalURL: directory.appendingPathComponent("b.jpg"))
        try Data([1]).write(to: output.partialURL)
        output.discard()
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.partialURL.path))
        output.discard() // idempotent
    }

    // spec "Edge cases": an app kill during capture leaves a temp file that is cleaned up on next start
    func testCleanStaleRemovesOnlyPartialFiles() throws {
        try Data([1]).write(to: directory.appendingPathComponent("x.heic.partial"))
        try Data([1]).write(to: directory.appendingPathComponent("y.mov.partial"))
        try Data([1]).write(to: directory.appendingPathComponent("keep.heic"))
        XCTAssertEqual(AtomicOutput.cleanStale(in: directory), 2)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["keep.heic"])
        XCTAssertEqual(AtomicOutput.cleanStale(in: directory.appendingPathComponent("missing")), 0)
    }

    func testStoragePolicy() throws {
        XCTAssertNoThrow(try StoragePolicy.ensureRoom(availableBytes: nil, requiredBytes: 1 << 40))
        XCTAssertNoThrow(try StoragePolicy.ensureRoom(availableBytes: 200 * 1024 * 1024, requiredBytes: 100 * 1024 * 1024))
        XCTAssertThrowsError(try StoragePolicy.ensureRoom(availableBytes: 120 * 1024 * 1024, requiredBytes: 100 * 1024 * 1024)) { error in
            XCTAssertEqual((error as? CameraError)?.code, .storageFull)
        }
        XCTAssertGreaterThan(StoragePolicy.estimatedBytes(widthPx: 4000, heightPx: 3000, motion: true), StoragePolicy.estimatedBytes(widthPx: 4000, heightPx: 3000, motion: false))
    }
}

final class CaptureMetadataTests: XCTestCase {
    private let descriptor = CapabilityProbe.descriptor(for: FakeDevices.wideBack())
    private let effective = SettingsClamp.effective(RequestedSettings(iso: 200, exposureTimeNs: 8_000_000), capabilities: CapabilityProbe.capabilities(for: FakeDevices.wideBack())).settings

    private func build(report: AppliedReport, adjustments: [Adjustment] = [], synthetic: Bool = false) -> [String: MetadataValue] {
        CaptureMetadataBuilder.build(
            descriptor: descriptor, report: report, effective: effective, adjustments: adjustments, format: .heif,
            deviceModel: "iPhone13,4", osVersion: "18.6", appVersion: "1.0.0", syntheticSource: synthetic
        )
    }

    // [CAM-050][MEM-002] the API keys carry the values the device reported
    func testBuildsTheKeysTheApiExtractsForAnalytics() {
        let metadata = build(report: AppliedReport(iso: 205, exposureTimeNs: 8_100_000, exposureBiasEV: 0.3, aperture: 1.6, focalLength35mmEq: 26, widthPx: 4032, heightPx: 3024))
        XCTAssertEqual(metadata["isoApplied"], .int(205))
        XCTAssertEqual(metadata["exposureTimeNsApplied"], .int64(8_100_000))
        XCTAssertEqual(metadata["aperture"], .double(1.6))
        XCTAssertEqual(metadata["focalLength35mmEq"], .double(26))
        XCTAssertEqual(metadata["lensKind"], .string("wide"))
        XCTAssertEqual(metadata["widthPx"], .int(4032))
        XCTAssertEqual(metadata["platform"], .string("ios"))
        XCTAssertEqual(metadata["deviceMake"], .string("Apple"))
        XCTAssertEqual(metadata["format"], .string("heif"))
        XCTAssertEqual(metadata["source"], .string("hardware"))
    }

    // the descriptor's equivalent focal length is the fallback
    func testFallsBackToTheDescriptorFocalLengthAndOmitsUnreportedValues() {
        let metadata = build(report: AppliedReport(widthPx: 10, heightPx: 10))
        XCTAssertEqual(metadata["focalLength35mmEq"], descriptor.focalLength35mmEq.map(MetadataValue.double))
        XCTAssertNil(metadata["isoApplied"])
        XCTAssertNil(metadata["aperture"])
        XCTAssertNil(metadata["adjustments"])
    }

    // [EXP-008] adjustments are recorded
    func testRecordsAdjustments() {
        let adjustment = Adjustment(field: "iso", requested: "99999", applied: "3072", reason: .outOfRange)
        let metadata = build(report: AppliedReport(widthPx: 1, heightPx: 1), adjustments: [adjustment])
        XCTAssertEqual(metadata["adjustments"], .list([.map(["field": .string("iso"), "requested": .string("99999"), "applied": .string("3072"), "reason": .string("outOfRange")])]))
    }

    // [CAM-008] digital zoom is labelled
    func testDigitalZoomIsFlagged() {
        XCTAssertEqual(build(report: AppliedReport(zoomFactor: 3, widthPx: 1, heightPx: 1))["digitalZoom"], .bool(true))
        XCTAssertEqual(build(report: AppliedReport(zoomFactor: 1, widthPx: 1, heightPx: 1))["digitalZoom"], .bool(false))
    }

    // ADR-0013: the synthetic camera never reports itself as hardware
    func testSyntheticSourceIsLabelled() {
        XCTAssertEqual(build(report: AppliedReport(widthPx: 1, heightPx: 1), synthetic: true)["source"], .string("synthetic"))
    }

    func testWhiteBalanceAndFocusAreStructured() {
        let metadata = build(report: AppliedReport(focusDiopters: 0.4, whiteBalanceKelvin: 5200, widthPx: 1, heightPx: 1))
        XCTAssertEqual(metadata["whiteBalance"], .map(["mode": .string("auto"), "kelvin": .int(5200)]))
        XCTAssertEqual(metadata["focus"], .map(["mode": .string("continuous"), "distanceDiopters": .double(0.4)]))
        XCTAssertEqual(build(report: AppliedReport(widthPx: 1, heightPx: 1))["whiteBalance"], .map(["mode": .string("auto")]))
    }

    func testMetadataConvertsToFoundationObjects() throws {
        let value = MetadataValue.map(["a": .list([.int(1), .int64(2), .double(3.5), .bool(true), .string("x")])])
        let object = value.foundationObject as? [String: Any]
        let list = object?["a"] as? [Any]
        XCTAssertEqual(list?.count, 5)
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: object as Any))
    }
}
