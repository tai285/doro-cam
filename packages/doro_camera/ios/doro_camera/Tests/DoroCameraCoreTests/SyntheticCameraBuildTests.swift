import XCTest
@testable import DoroCameraCore

final class SyntheticCameraBuildTests: XCTestCase {
    // [NFR-016]
    func testDebugBuildsContainTheSyntheticCameraAndReleaseBuildsDoNot() {
        #if DOROCAM_SYNTHETIC_CAMERA
        XCTAssertTrue(SyntheticCameraBuild.isCompiledIn)
        XCTAssertEqual(SyntheticCameraBuild.marker, "dorocam.synthetic-camera.v1")
        #else
        XCTAssertFalse(SyntheticCameraBuild.isCompiledIn)
        #endif
    }
}
