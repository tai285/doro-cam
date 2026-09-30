// swift-tools-version: 5.9
// Flutter-free core of the Doro Cam iOS camera plugin: pure logic that can be unit-tested with
// `swift test` on any Mac runner, without Flutter or a simulator (docs/architecture/camera.md).
import PackageDescription

// Debug builds contain the synthetic test camera (ADR-0013); Profile and Release builds never do.
let syntheticCameraInDebug: [SwiftSetting] = [
    .define("DOROCAM_SYNTHETIC_CAMERA", .when(configuration: .debug)),
]

let package = Package(
    name: "doro_camera_core",
    platforms: [
        .iOS("16.0"),
        .macOS("13.0"),
    ],
    products: [
        .library(name: "DoroCameraCore", targets: ["DoroCameraCore"]),
    ],
    targets: [
        .target(
            name: "DoroCameraCore",
            swiftSettings: syntheticCameraInDebug
        ),
        .testTarget(
            name: "DoroCameraCoreTests",
            dependencies: ["DoroCameraCore"],
            swiftSettings: syntheticCameraInDebug
        ),
    ]
)
