// swift-tools-version: 5.9
// Flutter glue of the Doro Cam camera plugin. Logic lives in ../doro_camera_core (Flutter-free, tested
// with `swift test`); this target only connects Flutter to it. Swift Package Manager only (no podspec).
import PackageDescription

let package = Package(
    name: "doro_camera",
    platforms: [
        .iOS("16.0")
    ],
    products: [
        .library(name: "doro-camera", targets: ["doro_camera"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        .package(name: "doro_camera_core", path: "../doro_camera_core"),
    ],
    targets: [
        .target(
            name: "doro_camera",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "DoroCameraCore", package: "doro_camera_core"),
            ]
        )
    ]
)
