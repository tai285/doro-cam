/// The native answer to a Dart `ping` (mapped to the Pigeon message by the Flutter glue).
public struct PingResponse: Equatable, Sendable {
    public let echo: String
    public let platform: String
    public let osVersion: String
    public let syntheticCameraCompiledIn: Bool

    public init(echo: String, platform: String, osVersion: String, syntheticCameraCompiledIn: Bool) {
        self.echo = echo
        self.platform = platform
        self.osVersion = osVersion
        self.syntheticCameraCompiledIn = syntheticCameraCompiledIn
    }
}

/// Builds ping answers. Kept free of Flutter so the logic is testable with `swift test`.
public struct PingResponder {
    private let platform: String
    private let environment: any PlatformEnvironment
    private let syntheticCameraCompiledIn: Bool

    public init(
        platform: String = "ios",
        environment: any PlatformEnvironment = SystemPlatformEnvironment(),
        syntheticCameraCompiledIn: Bool = SyntheticCameraBuild.isCompiledIn
    ) {
        self.platform = platform
        self.environment = environment
        self.syntheticCameraCompiledIn = syntheticCameraCompiledIn
    }

    public func respond(to message: String) -> PingResponse {
        PingResponse(
            echo: message,
            platform: platform,
            osVersion: environment.osVersion,
            syntheticCameraCompiledIn: syntheticCameraCompiledIn
        )
    }
}
