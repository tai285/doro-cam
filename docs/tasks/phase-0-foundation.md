# Phase 0 — Foundations, Test Infrastructure and Spikes

Roadmap: [P0](../product/roadmap.md). Planning (docs, ADRs, docs checker, CI for docs) is complete. The remaining work is scaffolding, **test infrastructure** (ADR-0013), and spikes. Every scaffold ships with passing tests and CI. Spikes run on the Android Emulator and the iOS Simulator (cloud macOS).

Recommended order: FND-T-001 → (FND-T-003, FND-T-004, FND-T-006, FND-T-007 in parallel) → FND-T-008 and FND-T-009 → FND-T-005 → FND-T-010 → FND-T-011, with spikes as their dependencies allow.

### FND-T-001 Convert repo root to a pnpm workspace
- **Status:** done
- **Platform:** infra
- **Depends:** none
- **Requirements:** NFR-010
- **Docs:** [development-guide.md](../development/development-guide.md), ADR-0012
- **Scope:** install pnpm (user-level; Corepack needs admin here); add `pnpm-workspace.yaml` (`apps/web`, `services/*`, `packages/profiles`, `packages/api-contract`, `tools/*`); move `tools/docs-check` into a workspace package with its own `package.json`; replace `package-lock.json` with `pnpm-lock.yaml`; keep root scripts `test`, `typecheck`, `check:docs` working; update `docs.yml`.
- **Out of scope:** creating the app packages themselves.
- **Acceptance:** `pnpm install && pnpm test && pnpm typecheck && pnpm check:docs` pass locally and in CI; no `package-lock.json` remains.
- **Tests:** all existing docs-check tests (35+) pass unchanged through pnpm, and the CI run shows the same counts.
- **Doc updates:** AGENTS.md §8 commands; local-development.md; the CI workflow.

### FND-T-002 CI baseline and dependency automation
- **Status:** todo
- **Platform:** infra
- **Depends:** FND-T-001
- **Requirements:** NFR-010
- **Docs:** [testing-strategy.md](../development/testing-strategy.md) (CI layout)
- **Scope:** create `ci.yml` with path-filtered jobs, following the CI layout table (docs/tools now; later tasks add jobs); Dependabot for npm, pub, gradle, and github-actions; required status checks documented.
- **Out of scope:** emulator and iOS jobs (FND-T-008, FND-T-009).
- **Acceptance:** CI green on main; a docs-only PR runs only the docs job (verified with a real test PR via `gh pr create`, then closed).
- **Tests:** the path-filter behavior is verified by the test PR; the workflow is linted with `actionlint` in CI.
- **Doc updates:** development-guide.md (CI section).

### FND-T-003 Local infrastructure with Docker Compose
- **Status:** done
- **Platform:** infra
- **Depends:** FND-T-001
- **Requirements:** NFR-013
- **Docs:** [local-development.md](../development/local-development.md), ADR-0008
- **Scope:** `infrastructure/docker-compose.yml` with Postgres 17 and Garage S3 (ADR-0014; MinIO is no longer maintained); a bootstrap in `tools/local-infra` creating the bucket, dev key, CORS, and the abort-multipart lifecycle rule via the S3 API; `.env.example`; live-stack protocol tests.
- **Out of scope:** production deployment.
- **Acceptance:** `docker compose up -d` gives healthy services on Windows and on the CI Linux runner; the lifecycle rule exists.
- **Tests:** `tools/local-infra`: 38 unit tests (config, bootstrap idempotency, CORS/lifecycle builders, presigned URLs carry no checksum params) and 15 live tests in CI (Postgres 17, SKIP LOCKED, presigned PUT/GET SHA-256 round-trip, out-of-order multipart with ListParts, part retry, wrong-ETag rejection, abort, expiry, tamper rejection, CORS, lifecycle).
- **Doc updates:** local-development.md (move from planned to available).

### FND-T-004 Flutter app scaffold
- **Status:** done
- **Platform:** dart
- **Depends:** FND-T-001
- **Requirements:** NFR-009, NFR-014
- **Docs:** [mobile.md](../architecture/mobile.md), ADR-0012
- **Scope:** install the Flutter SDK (stable), JDK 17, and Android command-line tools; root `pubspec.yaml` pub workspace; `apps/mobile` with the mobile.md folder layout, Riverpod, go_router, strict analysis options, and an empty camera route; minimum platforms decided and recorded (Android `minSdk` 28, iOS 16.0, app ID `com.dorocam.app`); `apps/mobile/AGENTS.md`; CI job for `flutter analyze` and `flutter test --coverage`.
- **Out of scope:** camera functionality; emulator runs (FND-T-008).
- **Acceptance:** analyze is clean; tests pass in CI.
- **Tests:** 38 unit/widget tests (routing, deep links, unknown routes, theme tokens with a WCAG contrast check, semantics, the shared back button) at 100% line coverage of `lib/`; `integration_test/app_smoke_test.dart` verified on the Android Emulator (`doro_api35`).
- **Doc updates:** AGENTS.md §8; local-development.md; testing-strategy.md (confirmed min API).

### FND-T-008 Android Emulator: local AVD and CI instrumentation job
- **Status:** todo
- **Platform:** infra
- **Depends:** FND-T-004
- **Requirements:** NFR-016, NFR-010
- **Docs:** [local-development.md](../development/local-development.md) (Android Emulator on Windows), [testing-strategy.md](../development/testing-strategy.md), ADR-0013
- **Scope:**
  - Install the emulator and API 35 image locally and create AVD `doro_api35`. If `emulator -accel-check` reports WHPX is unavailable, ask the owner to enable Windows Hypervisor Platform.
  - Scripts: `scripts/emulator-start.(sh|ps1)` that boots headless and waits for `sys.boot_completed`.
  - CI `android` job on `ubuntu-latest` with KVM (`reactivecircus/android-emulator-runner`), AVD caching, and a nightly API 28 (minimum supported) job.
  - Run `flutter test integration_test` on the emulator; upload the debug APK as an artifact (for optional field verification).
- **Out of scope:** camera tests (added by camera tasks).
- **Acceptance:** an `integration_test` smoke test (app launches, navigates the routes) passes locally on `doro_api35` and in CI.
- **Tests:** the integration smoke test; script tests for the boot-wait helper (timeout path included).
- **Doc updates:** local-development.md, testing-strategy.md, AGENTS.md §8.

### FND-T-009 iOS on cloud macOS: build, XCTest and Simulator job
- **Status:** todo
- **Platform:** infra
- **Depends:** FND-T-004
- **Requirements:** NFR-016, NFR-010
- **Docs:** [local-development.md](../development/local-development.md) (iOS without a Mac), [testing-infrastructure.md](../research/testing-infrastructure.md), ADR-0013
- **Scope:**
  - `ios.yml` on `macos-*` runners: path filters, `workflow_dispatch`, and a weekly schedule. It builds the Flutter iOS app for the Simulator, boots an iPhone 12 Pro Max–profile simulator, and runs `flutter test integration_test`. It caches pub, CocoaPods/SwiftPM, and DerivedData, and uploads `.xcresult` bundles.
  - An equivalent `codemagic.yaml` workflow.
  - A `scripts/ios-ci.sh` helper that wraps `gh workflow run` and `gh run watch` for agents.
  - Record the macOS minutes each run consumes.
- **Out of scope:** signing and TestFlight (owner decision).
- **Acceptance:** the smoke `integration_test` passes on the iOS Simulator in GitHub Actions; minutes per run are recorded in testing-infrastructure.md; Codemagic config validated by one run (after the owner connects the repo in the Codemagic UI).
- **Tests:** the integration smoke test on the Simulator; `actionlint` on the workflow.
- **Doc updates:** local-development.md, testing-infrastructure.md (measured minutes), AGENTS.md §8.

### FND-T-005 doro_camera plugin scaffold with Pigeon
- **Status:** todo
- **Platform:** dart
- **Depends:** FND-T-008, FND-T-009
- **Requirements:** CAM-004, NFR-014
- **Docs:** [specs/camera.md](../specs/camera.md), [architecture/camera.md](../architecture/camera.md) (testability seams), ADR-0001, ADR-0013
- **Scope:**
  - `packages/doro_camera` in the pub workspace, with an Android Kotlin module (Kover configured) and an iOS Swift module (xccov, SwiftLint).
  - Pigeon setup with a `ping` host API.
  - The `CameraPlatform` abstract class, and `FakeCameraPlatform` in `lib/testing.dart`.
  - Swift protocol seams `CaptureDeviceProviding` and `CaptureSessionControlling` (declared, not yet used).
  - The `DOROCAM_SYNTHETIC_CAMERA` build flag wiring (debug and test only), plus a CI assertion that release builds exclude it.
  - `packages/doro_camera/AGENTS.md`.
- **Out of scope:** real camera calls.
- **Acceptance:** the app calls `ping` successfully on the Android Emulator and the iOS Simulator in CI; the release-exclusion check passes.
- **Tests:** Dart tests for the fake and the mapping; JUnit and XCTest tests for the `ping` host API; an integration test on both platforms.
- **Doc updates:** development-guide.md (codegen notes).

### FND-T-006 Fastify API skeleton
- **Status:** done
- **Platform:** api
- **Depends:** FND-T-001, FND-T-003
- **Requirements:** NFR-008, NFR-011, NFR-013, NFR-014
- **Docs:** [backend.md](../architecture/backend.md), ADR-0006, ADR-0007, ADR-0010
- **Scope:** `services/api` with `app.ts`, `server.ts`, `worker.ts`, zod config, pino with request IDs, the error envelope, `/healthz` and `/readyz`, Drizzle with an empty migration, pg-boss boot in the worker, Vitest against the real local stack (isolated database per test file; Testcontainers was dropped because the compose stack is already required and CI-proven) + coverage thresholds, a Dockerfile, `services/api/AGENTS.md`, and a CI job.
- **Out of scope:** auth and business modules.
- **Acceptance:** `/readyz` reports DB and storage status correctly, including degraded states; CI green with coverage gates met.
- **Tests:** 122 tests at 100% statements / 98.6% branches: health endpoints in every degraded state, the error envelope for every AppError class and framework error (bad JSON, too large, wrong type), non-Error throws, request IDs, log redaction, config validation, migrations (idempotent), pg-boss on our Postgres (including a job surviving a restart), API and worker lifecycles (port in use, leaked connections), and the real `server.ts`/`worker.ts` entrypoints as child processes. The Docker image is built and run against the stack (migrate, ready, non-root, graceful SIGTERM) locally and in CI.
- **Doc updates:** backend.md status; AGENTS.md §8.

### FND-T-007 React web scaffold
- **Status:** done
- **Platform:** web
- **Depends:** FND-T-001
- **Requirements:** NFR-007, NFR-014
- **Docs:** [ux-principles.md](../design/ux-principles.md), ADR-0012
- **Scope:** `apps/web` with Vite, React, TypeScript strict, React Router, TanStack Query, ESLint and Prettier, Vitest + Testing Library + axe, a Playwright config (Chromium, Firefox, WebKit), design-token CSS variables, `apps/web/AGENTS.md`, and a CI job.
- **Out of scope:** real pages.
- **Acceptance:** the build succeeds; tests pass with coverage gates; the Playwright smoke test passes on all three browsers in CI.
- **Tests:** 57 unit/component tests at 100% coverage (every page renders, sets its title, has one h1 and one main, and passes axe; keyboard navigation and focus management; error boundary hides internals; query defaults; real-history App mount; WCAG contrast of the actual design tokens in light and dark) and a Playwright suite run in Chromium, Firefox, WebKit and a phone profile (25 pass; browser-specific cases skipped with a stated reason).
- **Doc updates:** AGENTS.md §8.

### FND-T-010 Coverage gates and ratchet across packages
- **Status:** todo
- **Platform:** infra
- **Depends:** FND-T-005, FND-T-006, FND-T-007
- **Requirements:** NFR-014
- **Docs:** [testing-strategy.md](../development/testing-strategy.md) (coverage gates)
- **Scope:** enforce the coverage table per package (Dart lcov, Vitest, Kover, xccov) with generated code excluded. A `coverage-ratchet.json` per package records current values; CI fails if coverage drops below the floor or the ratchet, and a script bumps the ratchet upward only.
- **Out of scope:** raising coverage of code that doesn't exist yet.
- **Acceptance:** a deliberately uncovered function in a throwaway branch fails CI (demonstrated, then the branch is deleted); main is green.
- **Tests:** unit tests for the ratchet script (increase, decrease, missing file, malformed file).
- **Doc updates:** testing-strategy.md if the thresholds are adjusted (owner approval required).

### FND-T-011 Requirement-to-test traceability report
- **Status:** todo
- **Platform:** infra
- **Depends:** FND-T-001
- **Requirements:** NFR-015
- **Docs:** [testing-strategy.md](../development/testing-strategy.md) (requirement traceability)
- **Scope:** extend `tools/docs-check` (or a sibling tool) to scan test sources (`**/*_test.dart`, `**/*.test.ts`, `**/*Test.kt`, `**/*Tests.swift`) for `[REQ-ID]` tags and write `traceability.json`. It fails when any requirement listed by a task with `Status: done` has no tagged test, or when a tag references an unknown requirement.
- **Out of scope:** coverage-quality scoring.
- **Acceptance:** runs in CI; on the current repo (no done tasks) it passes; fixture repos prove both failure modes.
- **Tests:** fixture-based tests like the existing docs-check suite: tag parsing per language, unknown tag, missing coverage for a done task, clean pass.
- **Doc updates:** testing-strategy.md; AGENTS.md §8.

### SPK-T-001 Spike S1: manual control code paths (emulator; iOS fakes)
- **Status:** todo
- **Platform:** android
- **Depends:** FND-T-008
- **Requirements:** CAM-004, CAM-010, CAM-011, CAM-006
- **Docs:** [spikes.md](../research/spikes.md), [camera-apis.md](../research/camera-apis.md)
- **Scope:** the S1 experiment: characteristics dump and requested-vs-applied sweep on the emulator.
- **Out of scope:** production plugin code; real devices (FV-001, FV-002).
- **Acceptance:** S1 result recorded; the capability matrix emulator column filled.
- **Tests:** unit tests for the dump parser and sweep analyzer; the sweep runs as an instrumented test.
- **Doc updates:** spikes.md, capability-matrix.md, ADR-0002 if the model changes.

### SPK-T-002 Spike S2: preview grading pipeline
- **Status:** todo
- **Platform:** android
- **Depends:** SPK-T-001, SPK-T-007
- **Requirements:** NFR-003, PRF-001
- **Docs:** [spikes.md](../research/spikes.md), [image-processing.md](../research/image-processing.md)
- **Scope:** the S2 experiment comparing native GL and Flutter shader pipelines, both checked against the reference renderer.
- **Out of scope:** the production profile engine; real fps (FV-003).
- **Acceptance:** S2 result recorded; the pipeline decision is written into architecture/camera.md (ADR update if needed).
- **Tests:** a frame-comparison test harness with unit tests; the pipeline output parity test runs on the emulator.
- **Doc updates:** spikes.md, architecture/camera.md.

### SPK-T-003 Spike S3: motion ring buffer with synthetic A/V
- **Status:** todo
- **Platform:** android
- **Depends:** SPK-T-001
- **Requirements:** MOT-002, MOT-009, NFR-012
- **Docs:** [spikes.md](../research/spikes.md), [motion-capture.md](../research/motion-capture.md), ADR-0005
- **Scope:** the S3 experiment on the emulator with a synthetic flash/beep source and an automatic offset analyzer.
- **Out of scope:** UI; the real microphone (FV-004).
- **Acceptance:** S3 result recorded; ADR-0005 status updated (validated or revised with a fallback).
- **Tests:** unit tests for the ring-buffer indexing (100% branch) and the offset analyzer (on generated media); an instrumented 20-run sync test.
- **Doc updates:** spikes.md, media.md, ADR-0005.

### SPK-T-004 Spike S4: background multipart uploads
- **Status:** todo
- **Platform:** dart
- **Depends:** FND-T-003, FND-T-008
- **Requirements:** SYNC-002, SYNC-003
- **Docs:** [spikes.md](../research/spikes.md), [upload-sync.md](../specs/upload-sync.md)
- **Scope:** the S4 automated experiment against the local Garage S3 from the emulator.
- **Out of scope:** the production queue; OEM behavior (FV-005).
- **Acceptance:** S4 result recorded.
- **Tests:** the network-drop and kill scenario runs as an automated integration test with a checksum assertion.
- **Doc updates:** spikes.md, uploads-storage.md.

### SPK-T-005 Spike S5: queue durability kill-loop
- **Status:** todo
- **Platform:** dart
- **Depends:** SPK-T-004
- **Requirements:** SYNC-001, NFR-002
- **Docs:** [spikes.md](../research/spikes.md), [sync.md](../architecture/sync.md)
- **Scope:** the S5 kill-loop harness and integrity checker on the emulator.
- **Out of scope:** —
- **Acceptance:** S5 result recorded; the harness is kept for reuse in P5.
- **Tests:** unit tests for the integrity checker (each inconsistency type detected); the harness itself runs as the test.
- **Doc updates:** spikes.md, ADR-0009 if needed.

### SPK-T-006 Spike S6: worker transcode isolation
- **Status:** todo
- **Platform:** api
- **Depends:** FND-T-006
- **Requirements:** NFR-013
- **Docs:** [spikes.md](../research/spikes.md), [media-pipeline.md](../architecture/media-pipeline.md)
- **Scope:** the S6 experiment with a generated 4K HEVC file.
- **Out of scope:** the production transcode job.
- **Acceptance:** S6 result recorded with a worker resource-limit recommendation.
- **Tests:** unit tests for the load-test result analyzer (p95 computation, degradation threshold).
- **Doc updates:** spikes.md, backend.md.

### SPK-T-007 Spike S7: LUT parity method
- **Status:** todo
- **Platform:** any
- **Depends:** FND-T-001
- **Requirements:** PRF-009
- **Docs:** [spikes.md](../research/spikes.md), [image-profile.md](../specs/image-profile.md)
- **Scope:** a TS reference renderer and ΔE2000 tool; comparison with ffmpeg `lut3d` interpolations. The emulator and Simulator GPU parts follow SPK-T-002.
- **Out of scope:** the full profile set.
- **Acceptance:** S7 result recorded; parity thresholds confirmed or revised with the owner.
- **Tests:** ΔE2000 tested against published reference pairs; renderer golden tests.
- **Doc updates:** spikes.md, image-profile.md.
