# AGENTS.md — apps/mobile

Flutter app for Doro Cam. Read the root [AGENTS.md](../../AGENTS.md) first; this file adds only what is specific to this package. Architecture: [docs/architecture/mobile.md](../../docs/architecture/mobile.md). Design: [docs/design/](../../docs/design/ux-principles.md).

## Commands

Load the toolchain first (`source scripts/dev-env.sh` or `. .\scripts\dev-env.ps1` from the repo root). Run these from `apps/mobile`:

| Purpose | Command |
|---|---|
| Resolve dependencies (pub workspace: the lockfile is at the repo root) | `flutter pub get` |
| Static analysis (must report no issues) | `flutter analyze` |
| Unit and widget tests with coverage | `flutter test --coverage` |
| Integration tests on the Android Emulator | `flutter test integration_test -d emulator-5554` |
| Debug APK | `flutter build apk --debug` |

Start the emulator with AVD `doro_api35` (see [local-development.md](../../docs/development/local-development.md)). iOS is built and tested only in the cloud (`gh workflow run ios.yml`, ADR-0013).

## Rules specific to this package

- **Layering:** `presentation → application → domain ← data`. `domain` imports no Flutter, drift, HTTP, or plugin code. A feature never imports another feature's `presentation/`.
- **Camera:** the app uses only `package:doro_camera` (not yet created). Never call `MethodChannel` directly and never add another camera plugin (ADR-0001).
- **State:** Riverpod with hand-written providers; no global mutable singletons; providers expose immutable state.
- **Design tokens:** widgets read colors and type from `DoroTokens` / the theme, never raw values (`lib/app/theme/`).
- **Accessibility:** every interactive control has an accessible name (a `label`, not only a tooltip: see `AppBackButton`), a touch target of at least 48 dp, and text that scales with the system setting (NFR-007).
- **Imports:** package imports only (`always_use_package_imports`), single quotes, trailing commas.
- **Strictness:** `strict-casts`, `strict-inference`, `strict-raw-types` are on. Do not add `dynamic`, `// ignore:` or lint suppressions without a comment that explains why.
- **Generated code** (drift, Pigeon, freezed if used): Pigeon output is committed; build_runner output is not.
- **Platform config:** `minSdk = 28` (Android 9), iOS 16.0, app ID `com.dorocam.app`. Changing these needs a docs update.

## Tests

- Unit and widget tests live in `test/`, mirroring `lib/`. Shared helpers are in `test/helpers/` (`pumpApp` starts the real app at any route).
- Integration tests live in `integration_test/` and run on an emulator or simulator, not on the VM.
- Tag tests with the requirement they cover: `test('[CAM-010] clamps ISO to the device range', ...)`.
- Coverage floor for this package: see the table in [testing-strategy.md](../../docs/development/testing-strategy.md). It may never go down.
- Widget tests use `FakeCameraPlatform` (from `doro_camera`) for anything camera-related.
