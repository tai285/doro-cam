import XCTest
@testable import DoroCameraCore

final class SessionMachineTests: XCTestCase {
    private func running(live: Bool = false) -> SessionMachine {
        var machine = SessionMachine(liveEnabled: live)
        machine.handle(.open)
        machine.handle(.started)
        return machine
    }

    func testOpenStartsTheSessionThenRunsWithPreview() {
        var machine = SessionMachine()
        XCTAssertEqual(machine.handle(.open), Transition(state: .opening, effects: [.startSession]))
        XCTAssertEqual(machine.handle(.started), Transition(state: .running, effects: [.startPreview]))
    }

    // [MOT-009] buffering runs only while LIVE is on
    func testLiveBufferingStartsOnlyWhenLiveIsEnabled() {
        var machine = SessionMachine(liveEnabled: true)
        machine.handle(.open)
        XCTAssertEqual(machine.handle(.started).effects, [.startPreview, .startLiveBuffering])
    }

    func testTogglingLiveStartsAndStopsBufferingOnlyWhileActive() {
        var machine = SessionMachine()
        XCTAssertEqual(machine.setLive(true), []) // not running yet
        machine.handle(.open); machine.handle(.started)
        XCTAssertEqual(machine.setLive(false), [.stopLiveBuffering])
        XCTAssertEqual(machine.setLive(true), [.startLiveBuffering])
        XCTAssertTrue(machine.liveEnabled)
    }

    // [NFR-012] background stops preview and buffering, foreground resumes them
    func testBackgroundingStopsPreviewAndBufferingAndForegroundResumes() {
        var machine = running(live: true)
        XCTAssertEqual(machine.handle(.appBackgrounded), Transition(state: .suspended, effects: [.stopLiveBuffering, .stopPreview]))
        XCTAssertEqual(machine.handle(.appForegrounded), Transition(state: .running, effects: [.startPreview, .startLiveBuffering]))
    }

    // [CAM-053] another app taking the camera
    func testInterruptionPausesAndResumesWhenItEnds() {
        var machine = running()
        XCTAssertEqual(machine.handle(.interrupted(.videoDeviceInUseByAnotherClient)).state, .interrupted(.videoDeviceInUseByAnotherClient))
        XCTAssertEqual(machine.handle(.interrupted(.other)).state, .interrupted(.videoDeviceInUseByAnotherClient)) // already interrupted
        XCTAssertEqual(machine.handle(.interruptionEnded), Transition(state: .running, effects: [.startPreview]))
    }

    // [CAM-053] a capture in progress is never lost to an interruption
    func testInterruptionDuringACaptureWaitsForTheCaptureToFinish() {
        var machine = running()
        machine.handle(.captureRequested)
        XCTAssertEqual(machine.state, .capturing)
        XCTAssertEqual(machine.handle(.interrupted(.audioDeviceInUseByAnotherClient)), Transition(state: .capturing, effects: [.deferUntilCaptureEnds]))
        let after = machine.handle(.captureFinished)
        XCTAssertEqual(after.state, .interrupted(.audioDeviceInUseByAnotherClient))
        XCTAssertEqual(after.effects, [.stopLiveBuffering, .stopPreview])
    }

    func testBackgroundingDuringACaptureAlsoWaits() {
        var machine = running()
        machine.handle(.captureRequested)
        machine.handle(.appBackgrounded)
        XCTAssertEqual(machine.handle(.captureFinished).state, .suspended)
    }

    func testFailedCaptureReturnsToRunningAndReportsTheError() {
        var machine = running()
        machine.handle(.captureRequested)
        XCTAssertEqual(machine.handle(.captureFailed), Transition(state: .running, effects: [.emitError(.captureFailed)]))
    }

    // [NFR-012] critical heat shuts the session down, even mid-capture
    func testCriticalThermalStateClosesTheSessionWithAnError() {
        var machine = running(live: true)
        machine.handle(.captureRequested)
        let transition = machine.handle(.thermal(.critical))
        XCTAssertEqual(transition.state, .failed(.thermalShutdown))
        XCTAssertTrue(transition.effects.contains(.emitError(.thermalShutdown)))
        XCTAssertTrue(transition.effects.contains(.releaseResources))
    }

    func testNonCriticalThermalStateChangesNothing() {
        var machine = running()
        XCTAssertEqual(machine.handle(.thermal(.serious)), Transition(state: .running, effects: []))
        machine.handle(.captureRequested)
        XCTAssertEqual(machine.handle(.thermal(.fair)).state, .capturing)
    }

    func testRuntimeErrorsFailTheSessionWithTheirCode() {
        var machine = running()
        let transition = machine.handle(.runtimeError(.cameraDisconnected))
        XCTAssertEqual(transition.state, .failed(.cameraDisconnected))
        XCTAssertTrue(transition.effects.contains(.emitError(.cameraDisconnected)))
    }

    // close is idempotent and reopening works
    func testCloseReleasesEverythingAndTheSessionCanBeReopened() {
        var machine = running(live: true)
        XCTAssertEqual(machine.handle(.close).state, .closed)
        XCTAssertEqual(machine.handle(.close).state, .closed)
        XCTAssertEqual(machine.handle(.open).state, .opening)
    }

    func testEventsThatMakeNoSenseAreIgnored() {
        var machine = SessionMachine()
        XCTAssertEqual(machine.handle(.captureRequested), Transition(state: .idle, effects: []))
        XCTAssertEqual(machine.handle(.appForegrounded).state, .idle)
        machine.handle(.open)
        XCTAssertEqual(machine.handle(.captureFinished).state, .opening)
    }

    func testBackgroundDuringInterruptionResumesToRunningAfterForeground() {
        var machine = running()
        machine.handle(.interrupted(.other))
        XCTAssertEqual(machine.handle(.appBackgrounded).state, .suspended)
        XCTAssertEqual(machine.handle(.appForegrounded).state, .running)
    }

    func testThermalPolicy() {
        XCTAssertEqual([0, 1, 2, 3, 7, -2].map(ThermalPolicy.level(forProcessInfoRawValue:)), [.nominal, .fair, .serious, .critical, .critical, .nominal])
        XCTAssertEqual(ThermalPolicy.maxPreBufferMs(requested: 3000, level: .fair), 3000)
        XCTAssertEqual(ThermalPolicy.maxPreBufferMs(requested: 3000, level: .serious), 1000)
        XCTAssertEqual(ThermalPolicy.maxPreBufferMs(requested: 500, level: .serious), 500)
        XCTAssertEqual(ThermalPolicy.maxPreBufferMs(requested: 3000, level: .critical), 0)
        XCTAssertTrue(ThermalLevel.nominal < ThermalLevel.critical)
    }
}

final class MotionBufferTests: XCTestCase {
    func testRingDropsEverythingOlderThanTheWindow() {
        var ring = TimedRing<Int>(windowSeconds: 1.0)
        for i in 0...40 { ring.append(i, at: Double(i) * 0.1) } // 0.0 ... 4.0
        XCTAssertEqual(ring.newestTime ?? 0, 4.0, accuracy: 1e-9)
        XCTAssertEqual(ring.oldestTime ?? 0, 3.0, accuracy: 1e-9)
        XCTAssertEqual(ring.count, 11)
        XCTAssertFalse(ring.isEmpty)
    }

    func testRingDropsOutOfOrderSamplesAndCanBeCleared() {
        var ring = TimedRing<Int>(windowSeconds: 5)
        ring.append(1, at: 1.0)
        ring.append(2, at: 0.5) // out of order
        ring.append(3, at: 1.0) // equal timestamps are fine
        XCTAssertEqual(ring.entries.map(\.element), [1, 3])
        ring.removeAll()
        XCTAssertTrue(ring.isEmpty)
        XCTAssertNil(ring.oldestTime)
        XCTAssertNil(ring.newestTime)
    }

    func testSamplesInARangeAreInclusive() {
        var ring = TimedRing<Int>(windowSeconds: 10)
        for i in 0..<10 { ring.append(i, at: Double(i)) }
        XCTAssertEqual(ring.samples(from: 2, to: 4).map(\.element), [2, 3, 4])
        XCTAssertEqual(ring.samples(from: 20, to: 30).count, 0)
    }

    // [MOT-002] a clip spans before and after the shutter
    func testPlanCoversPreAndPostRollAroundTheShutter() {
        let window = MotionClipPlanner.plan(shutterTime: 10, oldestBufferedTime: 5, audio: true)
        XCTAssertEqual(window.startTime, 8.5, accuracy: 1e-9)
        XCTAssertEqual(window.endTime, 11.5, accuracy: 1e-9)
        XCTAssertEqual(window.durationSeconds, 3.0, accuracy: 1e-9)
        XCTAssertEqual(window.preRollSeconds, 1.5, accuracy: 1e-9)
        XCTAssertEqual(window.postRollSeconds, 1.5, accuracy: 1e-9)
        XCTAssertTrue(window.includesAudio)
    }

    // never claim footage that was not buffered (camera just opened)
    func testPlanStartsAtTheOldestBufferedSampleWhenThePreRollIsShort() {
        let window = MotionClipPlanner.plan(shutterTime: 10, oldestBufferedTime: 9.6, audio: false)
        XCTAssertEqual(window.startTime, 9.6, accuracy: 1e-9)
        XCTAssertEqual(window.preRollSeconds, 0.4, accuracy: 1e-9)
        XCTAssertFalse(window.includesAudio)
    }

    func testPlanWithNothingBufferedStartsAtTheShutter() {
        let window = MotionClipPlanner.plan(shutterTime: 10, oldestBufferedTime: nil, audio: true)
        XCTAssertEqual(window.startTime, 10)
        XCTAssertEqual(window.preRollSeconds, 0)
    }

    func testPlanClampsNegativeRollsAndBufferNewerThanTheShutter() {
        let window = MotionClipPlanner.plan(shutterTime: 10, oldestBufferedTime: 12, preRollSeconds: -3, postRollSeconds: -1, audio: true)
        XCTAssertEqual(window.startTime, 10)
        XCTAssertEqual(window.endTime, 10)
    }

    // [MOT-003] muted clips carry no audio
    func testSelectCutsVideoAndAudioWithTheSameWindow() {
        var video = TimedRing<Int>(windowSeconds: 20)
        var audio = TimedRing<Int>(windowSeconds: 20)
        for i in 0..<100 { video.append(i, at: Double(i) * 0.1) }
        for i in 0..<200 { audio.append(i, at: Double(i) * 0.05) }
        let window = MotionClipPlanner.plan(shutterTime: 5, oldestBufferedTime: 0, audio: true)
        let both = MotionClipPlanner.select(window: window, video: video, audio: audio)
        XCTAssertEqual(both.video.first?.time ?? -1, 3.5, accuracy: 1e-9)
        XCTAssertEqual(both.video.last?.time ?? -1, 6.5, accuracy: 1e-9)
        XCTAssertEqual(both.audio.first?.time ?? -1, 3.5, accuracy: 1e-9)
        let skew = MotionClipPlanner.startSkew(videoFirst: both.video.first?.time, audioFirst: both.audio.first?.time)
        XCTAssertLessThanOrEqual(abs(skew ?? 1), MotionClipPlanner.avSyncToleranceSeconds)

        let mutedWindow = MotionClipPlanner.plan(shutterTime: 5, oldestBufferedTime: 0, audio: false)
        XCTAssertTrue(MotionClipPlanner.select(window: mutedWindow, video: video, audio: audio).audio.isEmpty)
        XCTAssertNil(MotionClipPlanner.startSkew(videoFirst: nil, audioFirst: 1))
    }
}
