import XCTest
@testable import DoroCameraCore

final class PlatformEnvironmentTests: XCTestCase {
    func testFormatsMajorAndMinor() {
        XCTAssertEqual(formatOSVersion(OperatingSystemVersion(majorVersion: 18, minorVersion: 6, patchVersion: 0)), "18.6")
        XCTAssertEqual(formatOSVersion(OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)), "26.0")
    }

    func testIncludesThePatchOnlyWhenItIsNotZero() {
        XCTAssertEqual(formatOSVersion(OperatingSystemVersion(majorVersion: 18, minorVersion: 6, patchVersion: 1)), "18.6.1")
        XCTAssertEqual(formatOSVersion(OperatingSystemVersion(majorVersion: 16, minorVersion: 0, patchVersion: 3)), "16.0.3")
    }

    func testTheSystemEnvironmentReportsARealVersion() {
        let version = SystemPlatformEnvironment().osVersion
        XCTAssertFalse(version.isEmpty)
        XCTAssertNotNil(version.first?.wholeNumberValue, "starts with a number, got \(version)")
        XCTAssertTrue(version.contains("."), "expected major.minor, got \(version)")
    }
}
