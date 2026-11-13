import Foundation

public enum InterruptionReason: String, Equatable, Sendable {
    case videoDeviceInUseByAnotherClient
    case audioDeviceInUseByAnotherClient
    case notAvailableWithMultipleForegroundApps
    case notAvailableDueToSystemPressure
    case other
}

public enum ThermalLevel: Int, Comparable, Equatable, Sendable {
    case nominal = 0, fair, serious, critical

    public static func < (lhs: ThermalLevel, rhs: ThermalLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

public enum SessionState: Equatable, Sendable {
    case idle
    case opening
    case running
    /// A still or Motion capture is being written.
    case capturing
    case interrupted(InterruptionReason)
    /// App in background: preview and Live buffering are stopped (NFR-012).
    case suspended
    case closed
    case failed(CameraErrorCode)
}

public enum SessionEvent: Equatable, Sendable {
    case open
    case started
    case captureRequested
    case captureFinished
    case captureFailed
    case interrupted(InterruptionReason)
    case interruptionEnded
    case thermal(ThermalLevel)
    case appBackgrounded
    case appForegrounded
    case runtimeError(CameraErrorCode)
    case close
}

/// What the engine must do as a result of a transition. Keeping this pure makes interruption handling
/// (CAM-053) testable without a device.
public enum SessionEffect: Equatable, Sendable {
    case startSession
    case stopSession
    case startPreview
    case stopPreview
    case startLiveBuffering
    case stopLiveBuffering
    /// Let the in-flight capture finish so no capture is lost, then apply the pending event.
    case deferUntilCaptureEnds
    case emitError(CameraErrorCode)
    case releaseResources
}

public struct Transition: Equatable, Sendable {
    public let state: SessionState
    public let effects: [SessionEffect]
}

/// Lifecycle of one camera session. Pure value-in, value-out.
public struct SessionMachine: Sendable {
    public private(set) var state: SessionState = .idle
    public private(set) var liveEnabled: Bool
    /// The state to return to after an interruption ends or the app returns to the foreground.
    private var resumeState: SessionState = .running
    private var pendingAfterCapture: SessionEvent?

    public init(liveEnabled: Bool = false) {
        self.liveEnabled = liveEnabled
    }

    public mutating func setLive(_ enabled: Bool) -> [SessionEffect] {
        liveEnabled = enabled
        guard state == .running || state == .capturing else { return [] }
        return enabled ? [.startLiveBuffering] : [.stopLiveBuffering]
    }

    @discardableResult
    public mutating func handle(_ event: SessionEvent) -> Transition {
        // A critical thermal state or a hard failure always wins, even mid-capture.
        if case .thermal(let level) = event, level >= .critical {
            return move(to: .failed(.thermalShutdown), [.stopLiveBuffering, .stopPreview, .stopSession, .emitError(.thermalShutdown), .releaseResources])
        }
        if case .runtimeError(let code) = event {
            return move(to: .failed(code), [.stopLiveBuffering, .stopPreview, .stopSession, .emitError(code), .releaseResources])
        }
        if event == .close {
            return move(to: .closed, [.stopLiveBuffering, .stopPreview, .stopSession, .releaseResources])
        }

        switch (state, event) {
        case (.idle, .open), (.closed, .open):
            return move(to: .opening, [.startSession])
        case (.opening, .started):
            return move(to: .running, startEffects())

        case (.running, .captureRequested):
            return move(to: .capturing, [])
        case (.capturing, .captureFinished), (.capturing, .captureFailed):
            let transition = move(to: .running, event == .captureFailed ? [.emitError(.captureFailed)] : [])
            if let pending = pendingAfterCapture {
                pendingAfterCapture = nil
                let followUp = handle(pending)
                return Transition(state: followUp.state, effects: transition.effects + followUp.effects)
            }
            return transition

        // An interruption or backgrounding during a capture waits for the capture to end, so no capture is lost.
        case (.capturing, .interrupted), (.capturing, .appBackgrounded):
            pendingAfterCapture = event
            return Transition(state: state, effects: [.deferUntilCaptureEnds])

        case (.running, .interrupted(let reason)):
            resumeState = .running
            return move(to: .interrupted(reason), [.stopLiveBuffering, .stopPreview])
        case (.interrupted, .interruptionEnded):
            return move(to: resumeState, startEffects())
        case (.interrupted(let reason), .interrupted):
            return Transition(state: .interrupted(reason), effects: [])

        case (.running, .appBackgrounded):
            return move(to: .suspended, [.stopLiveBuffering, .stopPreview])
        case (.interrupted, .appBackgrounded):
            resumeState = .running
            return move(to: .suspended, [])
        case (.suspended, .appForegrounded):
            return move(to: .running, startEffects())

        case (.running, .thermal), (.capturing, .thermal):
            return Transition(state: state, effects: []) // below critical: keep going; Dart may lower quality

        default:
            return Transition(state: state, effects: []) // events that make no sense in this state are ignored
        }
    }

    private func startEffects() -> [SessionEffect] {
        // Live buffering runs only while LIVE is on and the camera is active (MOT-009, NFR-012).
        liveEnabled ? [.startPreview, .startLiveBuffering] : [.startPreview]
    }

    private mutating func move(to newState: SessionState, _ effects: [SessionEffect]) -> Transition {
        state = newState
        return Transition(state: newState, effects: effects)
    }
}

public enum ThermalPolicy {
    /// Maps `ProcessInfo.ThermalState` raw values (0 nominal ... 3 critical).
    public static func level(forProcessInfoRawValue raw: Int) -> ThermalLevel {
        ThermalLevel(rawValue: Swift.min(Swift.max(raw, 0), 3)) ?? .nominal
    }

    /// Serious thermal pressure shortens the Live pre-roll to protect battery and heat (NFR-012).
    public static func maxPreBufferMs(requested: Int, level: ThermalLevel) -> Int {
        switch level {
        case .nominal, .fair: return requested
        case .serious: return Swift.min(requested, 1000)
        case .critical: return 0
        }
    }
}
