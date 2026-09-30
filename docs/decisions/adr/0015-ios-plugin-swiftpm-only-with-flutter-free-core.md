# ADR-0015: iOS camera plugin is SwiftPM-only with a Flutter-free core target

Status: Accepted
Date: 2026-10-01
Related: ADR-0001, ADR-0013, NFR-014, NFR-016, [camera.md](../../architecture/camera.md)

## Context

The `doro_camera` plugin needs native iOS code (AVFoundation) that is unit-tested thoroughly, yet we have no local Mac and every iOS run happens on cloud macOS (ADR-0013). Two facts shape the structure:

- Flutter 3.47 integrates plugins through **Swift Package Manager** by default. The app had no Podfile; the Xcode project already references `FlutterGeneratedPluginSwiftPackage`. A plugin template supports CocoaPods and SwiftPM side by side, which means two build definitions to keep identical.
- A plugin's own SwiftPM package cannot be built on its own: it depends on a `FlutterFramework` package that only exists inside an app's generated integration. So XCTest of logic inside the plugin target would need a full app build and a simulator.
- Flutter exposes only the plugin's own package directory (`ios/<plugin>/`) to the app's generated integration. A sibling folder such as `ios/doro_camera_core/` is **not reachable**. We learned this the hard way: a first version with a sibling core package failed in CI with "the package ... doro_camera_core cannot be accessed".

## Decision

- The iOS plugin is **SwiftPM only**: `ios/doro_camera/Package.swift`, with no podspec.
- The package (`ios/doro_camera/Package.swift`) has two targets. **`DoroCameraCore`** holds all logic that does not need Flutter, together with its XCTests. **`doro_camera`** is a thin Flutter glue layer: it implements the Pigeon host API and delegates to the core.
- The glue target and its `doro-camera` product are declared **by default**, which is what Flutter's app build needs. Setting `DOROCAM_SWIFT_STANDALONE=1` leaves the glue out (it needs a `FlutterFramework` package that only exists inside an app build), so `DOROCAM_SWIFT_STANDALONE=1 swift test --package-path ios/doro_camera` works on any Mac runner: fast, deterministic, no simulator. An explicit switch is used because probing the file system for the sibling package does not work: SwiftPM resolves the symlinked plugin to its real path, where the sibling does not exist (our first attempt at detection failed in CI for exactly that reason).
- The glue's behavior is verified end to end by the `integration_test` ping on the iOS Simulator.
- The synthetic test camera flag (`DOROCAM_SYNTHETIC_CAMERA`) is defined for the **debug** configuration in the core package, and CI proves by scanning artifacts that debug builds contain the marker and release builds do not.
- If another dependency requires CocoaPods, Flutter adds a Podfile for that dependency alongside SwiftPM. That is unaffected by this decision.

## Alternatives

- **Keep CocoaPods and SwiftPM in parallel:** two definitions to maintain, and the Flutter-free core split does not work with a single-module pod.
- **Put all Swift in the plugin target:** logic could then only be tested through a simulator build, which is slow (about 9 minutes) and cannot run the pure-logic tests in milliseconds.
- **Put core logic in the app:** breaks the plugin's ownership of camera behavior (ADR-0001).
- **A separate sibling core package:** tried first; Flutter does not expose sibling folders to the app integration, so the app build failed.

## Consequences

- iOS unit tests are fast and independent of Flutter upgrades.
- The glue layer must stay trivially thin; anything with a branch belongs in the core where it is tested.
- The plugin cannot be consumed by an app that disables Swift Package Manager. That is acceptable: the only consumer is our app.
- SwiftPM may cache manifest evaluation: after switching `DOROCAM_SWIFT_STANDALONE` on a Mac, run `swift package clean` first. CI uses fresh runners, so it is unaffected.
- The package also declares macOS 13 so the core compiles for `swift test`; it is never built for macOS in the app.
