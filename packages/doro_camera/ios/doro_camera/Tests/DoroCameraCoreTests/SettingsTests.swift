import XCTest
@testable import DoroCameraCore

final class SettingsClampTests: XCTestCase {
    private let caps = CapabilityProbe.capabilities(for: FakeDevices.wideBack())
    private let limited = CapabilityProbe.capabilities(for: FakeDevices.front())

    // [CAM-010][CAM-011] in-range manual values pass through untouched
    func testManualExposureInRangeIsAppliedAsRequested() {
        let result = SettingsClamp.effective(RequestedSettings(iso: 200, exposureTimeNs: 8_000_000), capabilities: caps)
        XCTAssertEqual(result.settings.exposureMode, .manual)
        XCTAssertEqual(result.settings.iso, 200)
        XCTAssertEqual(result.settings.exposureTimeNs, 8_000_000)
        XCTAssertTrue(result.adjustments.isEmpty)
    }

    // [EXP-008] out-of-range values are clamped and explained
    func testClampsISOAndShutterAndReportsWhy() {
        let result = SettingsClamp.effective(RequestedSettings(iso: 100_000, exposureTimeNs: 1), capabilities: caps)
        XCTAssertEqual(result.settings.iso, 3072)
        XCTAssertEqual(result.settings.exposureTimeNs, 25_000)
        XCTAssertEqual(result.adjustments.map(\.field), ["iso", "exposureTimeNs"])
        XCTAssertTrue(result.adjustments.allSatisfy { $0.reason == .outOfRange })
        XCTAssertEqual(result.adjustments.first?.requested, "100000")
        XCTAssertEqual(result.adjustments.first?.applied, "3072")
    }

    // [CAM-005] a manual request on a device without manual exposure becomes auto, never faked
    func testUnsupportedManualExposureFallsBackToAuto() {
        let result = SettingsClamp.effective(RequestedSettings(iso: 400, exposureTimeNs: 1_000_000), capabilities: limited)
        XCTAssertEqual(result.settings.exposureMode, .auto)
        XCTAssertNil(result.settings.iso)
        XCTAssertNil(result.settings.exposureTimeNs)
        XCTAssertEqual(result.adjustments.map(\.reason), [.unsupported, .unsupported])
    }

    // [CAM-012] bias applies only when exposure is not fully manual
    func testExposureBiasClampsAndIsIgnoredInManualMode() {
        let auto = SettingsClamp.effective(RequestedSettings(exposureBiasEV: 12), capabilities: caps)
        XCTAssertEqual(auto.settings.exposureBiasEV, 8)
        XCTAssertEqual(auto.adjustments.first?.reason, .outOfRange)
        let manual = SettingsClamp.effective(RequestedSettings(iso: 100, exposureTimeNs: 5_000_000, exposureBiasEV: 1), capabilities: caps)
        XCTAssertNil(manual.settings.exposureBiasEV)
        XCTAssertEqual(manual.adjustments.map(\.reason), [.notApplicableInManual])
        let none = FakeDevices.wideBack { $0.maxExposureTargetBias = $0.minExposureTargetBias }
        let unsupported = SettingsClamp.effective(RequestedSettings(exposureBiasEV: 1), capabilities: CapabilityProbe.capabilities(for: none))
        XCTAssertEqual(unsupported.adjustments.map(\.reason), [.unsupported])
    }

    func testExposureBiasInRangeHasNoAdjustment() {
        let result = SettingsClamp.effective(RequestedSettings(exposureBiasEV: -0.7), capabilities: caps)
        XCTAssertEqual(result.settings.exposureBiasEV, -0.7)
        XCTAssertTrue(result.adjustments.isEmpty)
    }

    // [CAM-021]
    func testManualFocusClampsDioptersAndFallsBackWhenUnsupported() {
        let maxDiopters = 1000.0 / 120.0
        let ok = SettingsClamp.effective(RequestedSettings(focusMode: .manual, focusDiopters: 50), capabilities: caps)
        XCTAssertEqual(ok.settings.focusMode, .manual)
        XCTAssertEqual(ok.settings.focusDiopters ?? 0, maxDiopters, accuracy: 1e-9)
        XCTAssertEqual(ok.adjustments.first?.reason, .outOfRange)
        XCTAssertEqual(SettingsClamp.effective(RequestedSettings(focusMode: .manual, focusDiopters: -2), capabilities: caps).settings.focusDiopters, 0)
        let exact = SettingsClamp.effective(RequestedSettings(focusMode: .manual, focusDiopters: 2.5), capabilities: caps)
        XCTAssertEqual(exact.settings.focusDiopters, 2.5)
        XCTAssertTrue(exact.adjustments.isEmpty)
        let fallback = SettingsClamp.effective(RequestedSettings(focusMode: .manual, focusDiopters: 2.5), capabilities: limited)
        XCTAssertEqual(fallback.settings.focusMode, .continuous)
        XCTAssertEqual(fallback.adjustments.map(\.reason), [.unsupported])
        let missingPosition = SettingsClamp.effective(RequestedSettings(focusMode: .manual), capabilities: caps)
        XCTAssertEqual(missingPosition.settings.focusMode, .continuous)
    }

    // [CAM-022] locked focus is a plain mode
    func testFocusLockAndAutoModeArePassedThrough() {
        let result = SettingsClamp.effective(RequestedSettings(focusMode: .auto, focusLocked: true), capabilities: caps).settings
        XCTAssertEqual(result.focusMode, .auto)
        XCTAssertTrue(result.focusLocked)
    }

    // diopters <-> AVFoundation lens position (0 = nearest, 1 = farthest)
    func testFocusMathConvertsBothWays() {
        XCTAssertEqual(FocusMath.lensPosition(forDiopters: 0, minFocusDiopters: 8), 1)
        XCTAssertEqual(FocusMath.lensPosition(forDiopters: 8, minFocusDiopters: 8), 0)
        XCTAssertEqual(FocusMath.lensPosition(forDiopters: 2, minFocusDiopters: 8), 0.75, accuracy: 1e-12)
        XCTAssertEqual(FocusMath.lensPosition(forDiopters: 20, minFocusDiopters: 8), 0)
        XCTAssertEqual(FocusMath.lensPosition(forDiopters: 1, minFocusDiopters: 0), 1)
        XCTAssertEqual(FocusMath.diopters(forLensPosition: 0.75, minFocusDiopters: 8), 2, accuracy: 1e-12)
        XCTAssertEqual(FocusMath.diopters(forLensPosition: 5, minFocusDiopters: 8), 0)
        XCTAssertEqual(FocusMath.diopters(forLensPosition: 0, minFocusDiopters: 8), 8)
    }

    // [CAM-030][CAM-031]
    func testWhiteBalanceFallsBackToAutoWhenTheDeviceCannotLockGains() {
        XCTAssertEqual(SettingsClamp.effective(RequestedSettings(whiteBalance: .preset(.tungsten)), capabilities: caps).settings.whiteBalance, .preset(.tungsten))
        let preset = SettingsClamp.effective(RequestedSettings(whiteBalance: .preset(.tungsten)), capabilities: limited)
        XCTAssertEqual(preset.settings.whiteBalance, .auto)
        XCTAssertEqual(preset.adjustments.first?.reason, .unsupported)
        let kelvinOK = SettingsClamp.effective(RequestedSettings(whiteBalance: .kelvin(5200)), capabilities: caps)
        XCTAssertEqual(kelvinOK.settings.whiteBalance, .kelvin(5200))
        let kelvinHigh = SettingsClamp.effective(RequestedSettings(whiteBalance: .kelvin(20000)), capabilities: caps)
        XCTAssertEqual(kelvinHigh.settings.whiteBalance, .kelvin(10000))
        let kelvinNone = SettingsClamp.effective(RequestedSettings(whiteBalance: .kelvin(5200)), capabilities: limited)
        XCTAssertEqual(kelvinNone.settings.whiteBalance, .auto)
        XCTAssertEqual(SettingsClamp.effective(RequestedSettings(whiteBalance: .preset(.auto)), capabilities: limited).adjustments.count, 0)
    }

    // [CAM-008]
    func testZoomIsClampedIntoTheDeviceRange() {
        XCTAssertEqual(SettingsClamp.effective(RequestedSettings(zoomFactor: 3), capabilities: caps).settings.zoomFactor, 3)
        let high = SettingsClamp.effective(RequestedSettings(zoomFactor: 99), capabilities: caps)
        XCTAssertEqual(high.settings.zoomFactor, 15)
        XCTAssertEqual(high.adjustments.first?.field, "zoomFactor")
        XCTAssertEqual(SettingsClamp.effective(RequestedSettings(zoomFactor: 0.2), capabilities: caps).settings.zoomFactor, 1)
    }

    // [CAM-040]
    func testFlashAndTorchRequireTheHardware() {
        let on = SettingsClamp.effective(RequestedSettings(flash: .auto, torch: true), capabilities: caps)
        XCTAssertEqual(on.settings.flash, .auto)
        XCTAssertTrue(on.settings.torch)
        let off = SettingsClamp.effective(RequestedSettings(flash: .on, torch: true), capabilities: limited)
        XCTAssertEqual(off.settings.flash, .off)
        XCTAssertFalse(off.settings.torch)
        XCTAssertEqual(off.adjustments.map(\.field), ["flash", "torch"])
        XCTAssertTrue(SettingsClamp.effective(RequestedSettings(flash: .off), capabilities: limited).adjustments.isEmpty)
    }

    // [CAM-014]
    func testExposureLockIsCarriedThrough() {
        XCTAssertTrue(SettingsClamp.effective(RequestedSettings(exposureLocked: true), capabilities: caps).settings.exposureLocked)
    }

    // property: whatever is requested, the result stays inside the capabilities
    func testEffectiveSettingsAlwaysLieWithinCapabilities() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<500 {
            let request = RequestedSettings(
                iso: Bool.random(using: &generator) ? Int.random(in: -1000...10_000_000, using: &generator) : nil,
                exposureTimeNs: Bool.random(using: &generator) ? Int64.random(in: -5...5_000_000_000, using: &generator) : nil,
                exposureBiasEV: Bool.random(using: &generator) ? Double.random(in: -50...50, using: &generator) : nil,
                focusMode: [FocusMode.continuous, FocusMode.auto, FocusMode.manual].randomElement(using: &generator)!,
                focusDiopters: Bool.random(using: &generator) ? Double.random(in: -3...30, using: &generator) : nil,
                whiteBalance: [WhiteBalanceMode.auto, WhiteBalanceMode.preset(.shade), WhiteBalanceMode.kelvin(Int.random(in: -100...50_000, using: &generator))].randomElement(using: &generator)!,
                zoomFactor: Double.random(in: -5...100, using: &generator),
                flash: FlashMode.allCases.randomElement(using: &generator)!,
                torch: Bool.random(using: &generator)
            )
            for capabilities in [caps, limited] {
                let s = SettingsClamp.effective(request, capabilities: capabilities).settings
                if let iso = s.iso { XCTAssertTrue(capabilities.iso?.contains(iso) ?? false) }
                if let ns = s.exposureTimeNs {
                    XCTAssertTrue(ns >= (capabilities.exposureTime?.min ?? Int64.max) && ns <= (capabilities.exposureTime?.max ?? Int64.min))
                }
                if let bias = s.exposureBiasEV { XCTAssertTrue(capabilities.exposureBias?.range.contains(bias) ?? false) }
                if let diopters = s.focusDiopters { XCTAssertTrue(diopters >= 0 && diopters <= (capabilities.focus.manual?.minFocusDistanceDiopters ?? -1)) }
                if case .kelvin(let k) = s.whiteBalance { XCTAssertTrue(capabilities.whiteBalance.kelvin?.contains(k) ?? false) }
                XCTAssertTrue(DoubleRange(min: capabilities.zoom.min, max: capabilities.zoom.max).contains(s.zoomFactor))
                if s.flash != .off { XCTAssertTrue(capabilities.flash.contains(s.flash)) }
                if s.torch { XCTAssertTrue(capabilities.torch) }
            }
        }
    }
}

final class AppliedComparisonTests: XCTestCase {
    private func effective(iso: Int? = 200, ns: Int64? = 8_000_000, mode: ExposureMode = .manual, focus: Double? = nil, wb: WhiteBalanceMode = .auto) -> EffectiveSettings {
        EffectiveSettings(
            exposureMode: mode, iso: iso, exposureTimeNs: ns, exposureBiasEV: nil, exposureLocked: false, focusMode: .continuous,
            focusDiopters: focus, focusLocked: false, whiteBalance: wb, zoomFactor: 1, flash: .off, torch: false
        )
    }

    // [CAM-050] quantization inside 8 % is not a mismatch
    func testSmallSensorQuantizationIsAccepted() {
        let report = AppliedReport(iso: 205, exposureTimeNs: 8_100_000, widthPx: 1, heightPx: 1)
        XCTAssertTrue(AppliedComparison.mismatches(effective: effective(), reported: report).isEmpty)
    }

    // [CAM-050] a device that ignores the request is reported
    func testIgnoredManualValuesAreReportedAsMismatches() {
        let report = AppliedReport(iso: 800, exposureTimeNs: 16_000_000, widthPx: 1, heightPx: 1)
        let result = AppliedComparison.mismatches(effective: effective(), reported: report)
        XCTAssertEqual(result.map(\.field), ["iso", "exposureTimeNs"])
        XCTAssertTrue(result.allSatisfy { $0.reason == .deviceReportedDifferent })
    }

    func testAutoExposureNeverMismatches() {
        let report = AppliedReport(iso: 800, exposureTimeNs: 16_000_000, widthPx: 1, heightPx: 1)
        XCTAssertTrue(AppliedComparison.mismatches(effective: effective(mode: .auto), reported: report).isEmpty)
    }

    func testFocusAndKelvinMismatches() {
        let report = AppliedReport(focusDiopters: 6, whiteBalanceKelvin: 7000, widthPx: 1, heightPx: 1)
        let result = AppliedComparison.mismatches(effective: effective(iso: nil, ns: nil, mode: .auto, focus: 1, wb: .kelvin(5000)), reported: report)
        XCTAssertEqual(result.map(\.field), ["focusDistanceDiopters", "whiteBalanceKelvin"])
        let close = AppliedReport(focusDiopters: 1.2, whiteBalanceKelvin: 5200, widthPx: 1, heightPx: 1)
        XCTAssertTrue(AppliedComparison.mismatches(effective: effective(iso: nil, ns: nil, mode: .auto, focus: 1, wb: .kelvin(5000)), reported: close).isEmpty)
    }

    func testMissingReportedValuesAreNotMismatches() {
        XCTAssertTrue(AppliedComparison.mismatches(effective: effective(), reported: AppliedReport(widthPx: 1, heightPx: 1)).isEmpty)
    }
}
