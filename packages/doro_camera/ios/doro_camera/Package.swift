// swift-tools-version: 5.9
// The Doro Cam iOS camera plugin, Swift Package Manager only (no podspec, ADR-0015).
//
// Two targets with different needs:
//   DoroCameraCore  Flutter-free logic. Unit-tested with plain `swift test`, no app and no simulator.
//   doro_camera     Flutter glue (Pigeon host API + plugin registration). Needs FlutterFramework.
//
// FlutterFramework is a sibling package that only Flutter's tooling provides inside an app build, so
// a standalone `swift test` of the core must leave the glue out: set DOROCAM_SWIFT_STANDALONE=1 for it.
// (Probing the file system for the sibling does not work: SwiftPM resolves the symlinked plugin to its
// real path, where the sibling does not exist. The default, unset, is what Flutter's build needs.)
import Foundation
import PackageDescription

let flutterFrameworkPath = "../FlutterFramework"
let insideFlutterApp = ProcessInfo.processInfo.environment["DOROCAM_SWIFT_STANDALONE"] != "1"

// Debug builds contain the synthetic test camera (ADR-0013); Profile and Release builds never do.
let syntheticCameraInDebug: [SwiftSetting] = [
    .define("DOROCAM_SYNTHETIC_CAMERA", .when(configuration: .debug)),
]

var dependencies: [Package.Dependency] = []
var products: [Product] = []
var targets: [Target] = [
    .target(
        name: "DoroCameraCore",
        path: "Sources/DoroCameraCore",
        swiftSettings: syntheticCameraInDebug
    ),
    .testTarget(
        name: "DoroCameraCoreTests",
        dependencies: ["DoroCameraCore"],
        path: "Tests/DoroCameraCoreTests",
        swiftSettings: syntheticCameraInDebug
    ),
]

if insideFlutterApp {
    dependencies.append(.package(name: "FlutterFramework", path: flutterFrameworkPath))
    products.append(.library(name: "doro-camera", targets: ["doro_camera"]))
    targets.append(
        .target(
            name: "doro_camera",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                "DoroCameraCore",
            ],
            path: "Sources/doro_camera"
        )
    )
} else {
    // Keeps the package valid for standalone builds; Flutter never uses this product.
    products.append(.library(name: "DoroCameraCore", targets: ["DoroCameraCore"]))
}

let package = Package(
    name: "doro_camera",
    platforms: [
        .iOS("16.0"),
        .macOS("13.0"),
    ],
    products: products,
    dependencies: dependencies,
    targets: targets
)
