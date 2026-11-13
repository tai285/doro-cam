import XCTest
@testable import DoroCameraCore

#if DOROCAM_SYNTHETIC_CAMERA

/// ADR-0013: the Simulator has no camera, so the synthetic source drives the pipeline. These tests
/// only exist in debug builds, like the source itself.
final class SyntheticSourceTests: XCTestCase {
    private let source = SyntheticSource(width: 8, height: 6, fps: 30, flashPeriod: 1.0, flashDuration: 1.0 / 30.0)

    func testFlashesRepeatOnASchedule() {
        XCTAssertTrue(source.isFlash(at: 0))
        XCTAssertFalse(source.isFlash(at: 0.5))
        XCTAssertTrue(source.isFlash(at: 2.0))
        XCTAssertFalse(source.isFlash(at: 2.04))
        XCTAssertFalse(source.isFlash(at: -1))
    }

    func testFramesAreDeterministicAndDifferOverTime() {
        XCTAssertEqual(source.frame(index: 3), source.frame(index: 3))
        XCTAssertNotEqual(source.frame(index: 3).bgra, source.frame(index: 4).bgra)
        XCTAssertEqual(source.frame(index: 3).bgra.count, 8 * 6 * 4)
        XCTAssertEqual(source.frame(index: 3).time, 0.1, accuracy: 1e-9)
    }

    func testFlashFramesAreWhiteAndOpaque() {
        let flash = source.frame(index: 0)
        XCTAssertTrue(flash.isFlash)
        XCTAssertTrue(stride(from: 0, to: flash.bgra.count, by: 4).allSatisfy { flash.bgra[$0] == 255 && flash.bgra[$0 + 1] == 255 && flash.bgra[$0 + 2] == 255 && flash.bgra[$0 + 3] == 255 })
        XCTAssertFalse(source.frame(index: 5).isFlash)
    }

    // the A/V sync fixture: the first flash frame and the first beep line up
    func testBeepStartsWithTheFlash() {
        let frames = (0..<90).map(source.frame(index:))
        let audio = source.audio(start: 0, duration: 3)
        let flash = SyntheticSource.firstFlashTime(in: frames)
        let beep = SyntheticSource.firstBeepTime(in: audio, start: 0)
        XCTAssertEqual(flash, 0)
        XCTAssertNotNil(beep)
        XCTAssertLessThan(abs((beep ?? 9) - (flash ?? 0)), MotionClipPlanner.avSyncToleranceSeconds)
        XCTAssertEqual(audio.count, Int(3 * SyntheticSource.sampleRate))
    }

    func testAudioIsSilentBetweenFlashes() {
        let quiet = source.audio(start: 0.2, duration: 0.5)
        XCTAssertTrue(quiet.allSatisfy { $0 == 0 })
        XCTAssertNil(SyntheticSource.firstBeepTime(in: quiet, start: 0.2))
        XCTAssertNil(SyntheticSource.firstFlashTime(in: [source.frame(index: 5)]))
        XCTAssertEqual(source.audio(start: 0, duration: 0).count, 0)
    }

    func testMarkerIsPresentOnlyInDebug() {
        XCTAssertTrue(SyntheticCameraBuild.isCompiledIn)
        XCTAssertEqual(SyntheticCameraBuild.marker, "dorocam.synthetic-camera.v1")
    }
}

#endif
