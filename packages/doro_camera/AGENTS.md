# AGENTS.md — packages/doro_camera

The first-party camera plugin: Dart API, Pigeon bridge, Kotlin (Android) and Swift (iOS) implementations. Read the root [AGENTS.md](../../AGENTS.md) first; this file adds only what is specific to this package. Architecture: [architecture/camera.md](../../docs/architecture/camera.md). Contract: [specs/camera.md](../../docs/specs/camera.md). Decisions: ADR-0001, ADR-0002, ADR-0013, ADR-0015.

## Layout

```
pigeons/camera_api.dart            the ONLY place the Dart <-> native contract is defined
lib/doro_camera.dart               public API (exports)
lib/src/                           domain types, CameraPlatform, Pigeon-backed implementation, generated messages
lib/testing.dart                   FakeCameraPlatform for app tests (import only from tests)
android/src/main/kotlin/           plugin + generated Messages.g.kt
android/src/debug|release/kotlin/  SyntheticCameraBuild (marker exists only in debug)
android/src/test|testDebug/kotlin/ JVM unit tests
ios/doro_camera/Package.swift      the single SwiftPM package (no podspec); DOROCAM_SWIFT_STANDALONE=1 leaves the glue out for `swift test`
ios/doro_camera/Sources/doro_camera/      Swift glue (Flutter + Pigeon)
ios/doro_camera/Sources/DoroCameraCore/   Flutter-free Swift logic
ios/doro_camera/Tests/DoroCameraCoreTests/ XCTests of the core (run with `swift test`)
```

## Commands

Load the toolchain first (`source scripts/dev-env.sh`).

| Purpose | Command |
|---|---|
| Regenerate the bridge after editing `pigeons/camera_api.dart` | `dart run pigeon --input pigeons/camera_api.dart` (from this directory) |
| Dart analyze / tests | `flutter analyze` · `flutter test --coverage` |
| Kotlin unit tests (debug variant) | `cd apps/mobile/android && ./gradlew :doro_camera:testDebugUnitTest` |
| Swift core tests (macOS only: CI runs them) | `DOROCAM_SWIFT_STANDALONE=1 swift test --package-path ios/doro_camera --enable-code-coverage` |
| End to end on the emulator / simulator | `cd apps/mobile && flutter test integration_test -d <device>` |
| Retry a flaky/stalling command with a per-attempt timeout (used for the iOS integration test) | `bash scripts/run-with-retry.sh --attempts 3 --timeout 420 -- <command>` (repo root) |
| Check a build for the synthetic camera | `bash scripts/check-synthetic-camera.sh --expect-present\|--expect-absent <apk or .app>` (repo root) |

## Rules specific to this package

- **Generated files are committed and never hand-edited:** `lib/src/messages.g.dart`, `Messages.g.kt`, `Messages.g.swift`. CI regenerates them and fails on any diff, so always regenerate after changing the Pigeon file.
- **Pigeon message classes end in `Message`.** Dart domain types (`PingResult`, later `CameraCapabilities`, ...) are separate immutable classes that the platform implementation maps from messages; the public API never exposes Pigeon types.
- **No business logic in native code.** Scenarios, presets, intent resolution, Memory creation and anything with product meaning live in Dart. Native code does hardware work only (ADR-0001).
- **Capabilities are probed, never assumed** (ADR-0002). Never hard-code a device model. Report what the platform API says.
- **Errors cross the bridge as a stable code plus message** (`CameraException(code, message)`), using the codes in [specs/camera.md](../../docs/specs/camera.md). Never leak platform exception text to users.
- **Testability seams:** native code depends on small interfaces (`PlatformEnvironment`; later capture-device and session protocols) so logic is tested without hardware. Keep the Flutter-facing Swift and Kotlin classes thin; put anything with a branch behind a seam where it can be unit-tested.
- **The synthetic test camera exists only in debug builds** (Android `src/debug`, Swift `#if DOROCAM_SYNTHETIC_CAMERA`, enabled for the debug configuration only). It reports itself as synthetic and its marker string (`dorocam.synthetic-camera.v1`) must appear in no other source. CI proves debug APKs/apps contain the marker and release ones do not.
- **iOS is SwiftPM only** (no podspec). Put logic in the `DoroCameraCore` target (testable with `swift test`), not in the glue target. Flutter exposes only `ios/doro_camera/` to the app, so never add sibling packages or folders the build depends on.
- **minSdk 28 (Android 9), iOS 16.** Raising or lowering these needs a docs update.
- **Kotlin test names cannot contain `[` or `]`** (a JVM rule), and neither can Swift method names. Put the requirement tag in a comment directly above the test: `// [CAM-004]`.

## Tests

- Dart tests in `test/`, Kotlin in `android/src/test` and `testDebug`, Swift in `ios/doro_camera/Tests`. Use fakes, not mocks (there is no Mockito here).
- The Pigeon wire format is tested on both sides with the real codec: Dart through Flutter's mock messenger, Kotlin through `FakeBinaryMessenger` (`android/src/test`).
- Every new bridge method needs: a Dart mapping test, a Kotlin test, a Swift core test where logic exists, and an `integration_test` in `apps/mobile` that round-trips it on the emulator and the simulator.
- Coverage thresholds are in [testing-strategy.md](../../docs/development/testing-strategy.md). Generated files are excluded.
