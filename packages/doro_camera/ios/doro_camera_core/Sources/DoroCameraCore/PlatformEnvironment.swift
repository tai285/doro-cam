import Foundation

/// What the plugin needs to know about the device. A seam so unit tests need no real device.
public protocol PlatformEnvironment {
    /// Operating system version, for example `18.6`.
    var osVersion: String { get }
}

/// Formats an OS version as `major.minor`, adding `.patch` only when the patch number is not zero.
public func formatOSVersion(_ version: OperatingSystemVersion) -> String {
    let base = "\(version.majorVersion).\(version.minorVersion)"
    return version.patchVersion == 0 ? base : "\(base).\(version.patchVersion)"
}

/// The real device.
public struct SystemPlatformEnvironment: PlatformEnvironment {
    public init() {}

    public var osVersion: String {
        formatOSVersion(ProcessInfo.processInfo.operatingSystemVersion)
    }
}
