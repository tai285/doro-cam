import XCTest
@testable import DoroCameraCore

private struct FakeEnvironment: PlatformEnvironment {
    let osVersion: String
}

final class PingResponderTests: XCTestCase {
    // Swift method names cannot hold brackets, so requirement tags live in comments.

    // [CAM-004]
    func testEchoesTheMessageAndReportsPlatformAndOSVersion() {
        let responder = PingResponder(
            platform: "ios",
            environment: FakeEnvironment(osVersion: "18.6"),
            syntheticCameraCompiledIn: false
        )

        let response = responder.respond(to: "hello")

        XCTAssertEqual(
            response,
            PingResponse(echo: "hello", platform: "ios", osVersion: "18.6", syntheticCameraCompiledIn: false)
        )
    }

    func testKeepsUnusualTextIntact() {
        let responder = PingResponder(environment: FakeEnvironment(osVersion: "18.6"))
        let text = "Doro 相机 📷 — café"
        XCTAssertEqual(responder.respond(to: text).echo, text)
        XCTAssertEqual(responder.respond(to: "").echo, "")
    }

    func testDefaultsToTheIOSPlatformAndTheBuildSyntheticCameraFlag() {
        let response = PingResponder(environment: FakeEnvironment(osVersion: "17.0")).respond(to: "x")
        XCTAssertEqual(response.platform, "ios")
        XCTAssertEqual(response.syntheticCameraCompiledIn, SyntheticCameraBuild.isCompiledIn)
    }

    func testReportsWhateverSyntheticCameraFlagItIsGiven() {
        let on = PingResponder(environment: FakeEnvironment(osVersion: "1.0"), syntheticCameraCompiledIn: true)
        let off = PingResponder(environment: FakeEnvironment(osVersion: "1.0"), syntheticCameraCompiledIn: false)
        XCTAssertTrue(on.respond(to: "x").syntheticCameraCompiledIn)
        XCTAssertFalse(off.respond(to: "x").syntheticCameraCompiledIn)
    }

    func testResponsesCompareByValue() {
        let a = PingResponse(echo: "e", platform: "ios", osVersion: "1.0", syntheticCameraCompiledIn: false)
        XCTAssertEqual(a, PingResponse(echo: "e", platform: "ios", osVersion: "1.0", syntheticCameraCompiledIn: false))
        XCTAssertNotEqual(a, PingResponse(echo: "e", platform: "ios", osVersion: "1.0", syntheticCameraCompiledIn: true))
        XCTAssertNotEqual(a, PingResponse(echo: "f", platform: "ios", osVersion: "1.0", syntheticCameraCompiledIn: false))
    }
}
