# Testing Strategy

Status: Accepted · Last updated: 2026-09-30 · Related: NFR-009, NFR-010, NFR-014, NFR-015, NFR-016, ADR-0013, [development-guide.md](development-guide.md), [field-verification.md](field-verification.md)

## The rule: a full automated test suite

**Every function, class, widget, endpoint, job, migration and feature ships with automated tests in the same change** (NFR-014). There are no exceptions for "simple" code, and there is no "tests later". Agents verify their own work on host test runners, the Android Emulator, and the iOS Simulator on cloud macOS (ADR-0013). A change that isn't tested isn't done.

Tests must prove behavior:
- **No fake assertions.** No tests that only check a mock was called when real behavior is observable. No snapshot-everything tests without intent.
- **Assert outcomes.** Returned values, persisted state, files written, HTTP responses, rendered semantics.
- **Cover the unhappy paths.** Every error code and every branch listed in a spec has a test.
- **Regressions first.** Every bug fix starts with a failing test that reproduces it.
- **No weakening.** Never delete, skip, loosen, or `@Skip` a test to get green. If a test is wrong, fix it in the same change and explain why in the report.
- **Deterministic.** Inject clocks, random seeds, IDs, and network. A flaky test is a bug: fix it or quarantine it with a linked task within one day. Quarantine never lasts past the next phase.

## Test obligations by artifact

| Artifact | Required tests | Tool |
|---|---|---|
| Pure function or value type (Dart/TS/Kotlin/Swift) | Unit tests for normal, boundary and invalid inputs; property-based tests for resolvers, parsers, math | `package:test` / Vitest / JUnit / XCTest (+ `glados`/`fast-check`/Kotest property tests) |
| Stateful class or state machine | A test per transition, including illegal transitions | same |
| Riverpod provider / use case | Tests with fakes at boundaries (camera platform, clock, transport) and **real** drift | `package:test` |
| Widget / screen | Widget tests: rendering per state, interactions, semantics labels; golden tests for Experience skins | `flutter_test` |
| drift schema | DAO tests on real SQLite; **a migration test for every schema version step** | drift `SchemaVerifier` |
| Pigeon message / platform mapping | Round-trip mapping tests on both sides (Dart and Kotlin/Swift) | `package:test`, JUnit, XCTest |
| Native camera logic (Kotlin/Swift) | Unit tests behind seams (characteristics fixtures, fake capture devices). Kotlin runs through the app's Gradle project (`./gradlew :doro_camera:testDebugUnitTest` in `apps/mobile/android`); Swift logic lives in the Flutter-free `doro_camera_core` package and runs with `swift test` on a macOS runner (ADR-0015) | kotlin-test (JUnit 5), XCTest |
| Native camera integration | Instrumented tests on the **Android Emulator**; XCTest plus the synthetic source on the **iOS Simulator** | AndroidX Test, XCTest |
| App feature (end to end on mobile) | `integration_test` flows on the Android Emulator and iOS Simulator | `integration_test` |
| API endpoint | Integration tests: success, validation error, 401, IDOR (404), idempotent replay, and every documented error code | Vitest + Fastify `inject` against the real Postgres/S3 from `pnpm infra:up` (an isolated database per test file) |
| DB query / repository | Tests on real Postgres (isolated database per test file) | Vitest |
| Worker job | Handler tests with real Postgres and S3 (Garage), run twice to prove idempotency; media outputs checked with ffprobe/exif parsing | Vitest |
| Web component / hook | Component tests with MSW for HTTP; accessibility assertions (axe) | Vitest + Testing Library |
| Web journey | Playwright E2E against the Docker Compose stack | Playwright |
| Cross-system journey | Emulator app captures and uploads to the local stack in CI, then Playwright confirms the Memory on the web | `integration_test` + Playwright |
| Contract | Committed OpenAPI equals generated; the Dart and TS clients regenerate without diff | script in CI |
| Docs | `tools/docs-check` | node:test |
| Repository tooling | Unit tests plus fixture-based tests | node:test |

## Requirement traceability (NFR-015)

Every requirement of a `done` task must be covered by at least one automated test. Tests carry requirement IDs in their names, e.g. `test('[CAM-010] clamps ISO to the device range', …)`; Swift and Kotlin test method names cannot hold brackets (the JVM forbids `[` and `]` in names), so Swift and Kotlin tests put the tag in a comment directly above the test (`// [CAM-010]`). `pnpm check:traceability` (`tools/docs-check`, task FND-T-011) scans every test source (Dart, TypeScript, Playwright, Kotlin, Swift), and CI fails when a tag names an unknown requirement or when a done task's requirement has no tagged test.

Requirements that cannot be proven by a test (process and meta requirements such as NFR-009, NFR-010, NFR-014) are listed with a reason in [traceability-waivers.json](../product/traceability-waivers.json). Waivers without a reason do not count, and a waiver becomes an error once the requirement does get a tagged test, so the file cannot rot. Add a waiver only for genuine process requirements, never to skip writing a test.

## Coverage gates (enforced in CI)

| Scope | Lines | Branches |
|---|---|---|
| Critical modules: intent resolver, profile/LUT compiler, upload state machine, sync conflict rules, authz helpers, Kelvin/exposure conversions, ring-buffer indexing | 100% | 100% |
| Dart packages (domain, application, data) | ≥ 95% | ≥ 90% |
| Flutter presentation | ≥ 85% | — |
| TypeScript (API, worker, web, profiles, tools) | ≥ 95% | ≥ 90% |
| Kotlin plugin code (Kover) | ≥ 90% | ≥ 80% |
| Swift plugin code (xccov) | ≥ 90% | — |

Generated code (Pigeon, drift, build_runner, OpenAPI clients) is excluded. Coverage may never decrease on `main` (a ratchet file per package, updated only upward). Coverage is a floor, not the goal: the obligations table still applies.

## Emulator and simulator matrix

| Target | Where | Used for |
|---|---|---|
| Android Emulator: Pixel-class AVD, **API 35**, x86_64, emulated back and front cameras | Local (Windows, WHPX) and CI (`ubuntu-latest` with KVM) | Primary Android instrumentation and `integration_test` runs |
| Android Emulator: API 28 (minimum supported: `minSdk = 28`, decided at FND-T-004) | CI, nightly | Oldest-API regression of app behavior. Advanced emulated-camera features (RAW, logical cameras) need Android 11+ images, so camera-capability tests run on API 35 |
| iOS deployment target | iOS 16.0 (decided at FND-T-004) | Simulator runs use the latest iOS runtime |
| iOS Simulator: a large iPhone on the iOS 18 runtime (the runner image has no iPhone 12 Pro Max device type; `scripts/ios-simulator.sh` picks the closest) | Cloud macOS (GitHub Actions `macos-15`, Xcode 16.4) | iOS unit, XCTest, `integration_test` with the synthetic camera |
| iOS Simulator: newest iPhone profile | Cloud macOS, nightly or manual | Current-device regression |

### What emulators can verify
- Capability probe logic and the reported characteristics of the emulated camera.
- Applying manual ISO/shutter/focus/WB and reading applied values back.
- Session lifecycle, interruptions (backgrounding via `adb`, `simctl`), permissions (`adb shell pm grant/revoke`, `simctl privacy`).
- Capture to file, atomic writes, EXIF, the DB transaction, and kill-during-capture (`adb shell am kill`, `simctl terminate`).
- The motion ring buffer and muxing with **synthetic A/V input**: flash frames and beep tones at known timestamps, with offsets measured automatically after demuxing.
- Upload queue, background transfer, and network loss (`adb shell svc wifi/data disable`, emulator console `network` commands).
- Rendering correctness against reference images (not performance).

### What they cannot verify (goes to [field-verification.md](field-verification.md))
Image quality and real sensor response, OEM-specific camera HAL behavior, real performance (fps, latency), thermals and battery, real microphone acoustics, and OEM background-execution policies.

## CI layout (target; built by FND tasks)

| Workflow | Runner | Trigger | Runs |
|---|---|---|---|
| `docs.yml` (exists) | ubuntu | every push/PR | tooling typecheck and tests, docs check |
| `ci.yml` › api, web, profiles | ubuntu | path-filtered | lint, typecheck, unit and integration (Testcontainers), coverage gates, Playwright |
| `ci.yml` › mobile-dart | ubuntu | path-filtered | `flutter analyze`, `flutter test --coverage`, gates |
| `ci.yml` › android | ubuntu + KVM | path-filtered to mobile/plugin | Gradle unit tests (Kover), emulator instrumentation, `integration_test` against Docker Compose |
| `ios.yml` | `macos-*` | path-filtered to iOS/plugin/Dart changes, `workflow_dispatch`, weekly | build, XCTest (xccov), Simulator `integration_test`, check that release builds exclude the synthetic source |
| `e2e.yml` | ubuntu + KVM | nightly and before a release | full cross-system journey (emulator app → API → web) |

**Cost:** the repository is public, so GitHub-hosted macOS runners are free; a run takes about 9 minutes. Still path-filter and cache, because runs are slow. If the repository ever goes private, macOS minutes count 10x against the free quota (see [testing-infrastructure.md](../research/testing-infrastructure.md)) and Codemagic (500 free minutes a month) becomes the fallback.

## How agents run tests

- **Host:** package-level commands listed in each package's `AGENTS.md`.
- **Android Emulator (local):** start the AVD (`emulator -avd doro_api35 -no-snapshot-save`), then run `flutter test integration_test -d emulator-5554` and `./gradlew connectedDebugAndroidTest`.
- **iOS (cloud):** push the branch, then `gh workflow run ios.yml --ref <branch>` and `gh run watch`. Read failures with `gh run view --log-failed`. XCTest result bundles are uploaded as artifacts.
- A report must cite the actual commands and pass/fail counts. It must not paraphrase them.

## Coverage of special cases

- **Time zones and clocks:** capture-time tests run under at least two TZ settings (`TZ=Asia/Tokyo`, `TZ=America/Los_Angeles`).
- **Locales:** number formatting of camera values is tested in `en` and one comma-decimal locale.
- **Accessibility:** widget tests assert semantics labels. Web tests run axe with zero violations at the "serious" level and above.
- **Security:** each authz rule has an allowed and a denied test. The location-leak test parses EXIF/MP4 atoms of served files.
