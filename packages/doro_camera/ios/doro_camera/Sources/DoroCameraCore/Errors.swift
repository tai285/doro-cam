import Foundation

/// The stable error codes of docs/specs/camera.md. They cross the bridge as a code plus a message and
/// never leak platform exception text to users.
public enum CameraErrorCode: String, CaseIterable, Equatable, Sendable {
    case permissionDenied = "permission_denied"
    case permissionRestricted = "permission_restricted"
    case cameraInUse = "camera_in_use"
    case cameraDisconnected = "camera_disconnected"
    case unsupportedConfiguration = "unsupported_configuration"
    case captureFailed = "capture_failed"
    case storageFull = "storage_full"
    case thermalShutdown = "thermal_shutdown"
}

public struct CameraError: Error, Equatable, Sendable {
    public let code: CameraErrorCode
    public let message: String

    public init(_ code: CameraErrorCode, _ message: String) {
        self.code = code
        self.message = message
    }
}

/// Mirrors `AVAuthorizationStatus` without importing AVFoundation into the core.
public enum AuthorizationState: String, Equatable, Sendable {
    case notDetermined, restricted, denied, authorized
}

public enum PermissionEvaluation {
    /// The error a camera request must fail with for this state, or nil when it may proceed.
    /// `notDetermined` is not an error: the caller asks the user first (CAM-052).
    public static func cameraError(for state: AuthorizationState) -> CameraError? {
        switch state {
        case .authorized, .notDetermined:
            return nil
        case .denied:
            return CameraError(.permissionDenied, "Camera access is turned off for Doro Cam. Turn it on in Settings.")
        case .restricted:
            return CameraError(.permissionRestricted, "Camera access is restricted on this device.")
        }
    }

    /// The synthetic test camera makes its own pictures, so it never needs camera permission. Asking would
    /// show a system dialog nobody can answer on the Simulator, and the open call would wait forever.
    public static func cameraPermissionRequired(syntheticSource: Bool) -> Bool {
        !syntheticSource
    }

    /// LIVE without a granted microphone captures silent motion and says so (MOT-003).
    public static func liveAudioAvailable(microphone: AuthorizationState, deviceHasMicrophone: Bool, muted: Bool) -> Bool {
        microphone == .authorized && deviceHasMicrophone && !muted
    }
}
