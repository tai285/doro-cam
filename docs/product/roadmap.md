# Roadmap

Status: Living · Last updated: 2026-09-30 · Related: [requirements.md](requirements.md), [tasks](../tasks/README.md), ADR-0013

Phases are ordered by dependency and risk. Status values are `not started`, `in progress`, and `done`. Fine-grained tasks exist only for the current and next phases (see [tasks/README.md](../tasks/README.md)). Later phases are refined into task files when they start.

**Verification model (ADR-0013):** every phase's acceptance is proven by the full automated test suite. That covers host tests, the Android Emulator, and the iOS Simulator on cloud macOS. Hardware-only aspects are logged in [field-verification.md](../development/field-verification.md) and don't block phases.

## Deviations from the original proposal (and why)

| Change | Reason |
|---|---|
| Local Memory store moved from phase 6 into P1 | Capture must save Memories from the first working build (NFR-002). A camera that writes loose files would need rework. |
| Backend foundation (P4) runs **in parallel** with P2–P3 | The backend has no dependency on camera work. Parallel work shortens the path to the MVP. |
| Video moved after the MVP (P8) | Video isn't in the MVP journey, and it's costly: codecs, transcoding, storage. |
| Motion Memory (P6) after upload (P5) | Motion capture is the riskiest capture feature. Its spike (S3) runs in P0, but the feature ships after the core loop works end to end. |
| Redis removed from the MVP | pg-boss on Postgres covers jobs (ADR-0010). |
| **Android and iOS in parallel, without a local Mac** | iOS builds and tests run on cloud macOS (GitHub Actions and Codemagic). The iOS Simulator has no camera, so it uses a synthetic source in test builds (ADR-0013). |
| Emulators and simulators are the primary verification targets | Agents can verify their own work. Real devices are optional field validation. |

## MVP scope realism

The MVP includes two native camera engines, a GPU look pipeline, motion capture, resumable sync, a backend, and a web app, all with a full test suite. That is large. The committed MVP is therefore:

- **Android and iOS feature parity**, verified on the Android Emulator and the iOS Simulator. iOS iteration is slower because every iOS build is a cloud CI run, so iOS tasks follow their Android counterparts closely rather than simultaneously.
- **Two fully built Experiences** (Mirrorless, Instant); DSLR and Film are styled variants (EXP-011).
- **About five profiles** (PRF-004).
- **Web: read-only library** plus account (WEB-001–WEB-006).

## Phase summary

| Phase | Name | MVP | Status | Depends on |
|---|---|---|---|---|
| P0 | Foundations, test infrastructure and spikes | ✓ | in progress (planning done) | — |
| P1 | Camera core and local Memories | ✓ | not started | P0 |
| P2 | Manual controls, Experiences, presets | ✓ | not started | P1 |
| P3 | Image profile engine | ✓ | not started | P1, S2, S7 |
| P4 | Backend foundation and auth | ✓ | not started | P0 |
| P5 | Cloud storage, upload queue, sync | ✓ | not started | P1, P4, S4, S5 |
| P6 | Motion Memory (LIVE) | ✓ | not started | P1, P5, S3 |
| P7 | Web dashboard (library) → **MVP complete** | ✓ | not started | P4, P5 |
| P8 | Video | | not started | P2, P5, S6 |
| P9 | Shared albums and trips | | not started | P5, P7 |
| P10 | Photography analytics | | not started | P5 |
| P11 | Personalized presets | | not started | P10 |
| P12 | AI | | not started | P10, new ADR |
| P13 | Physical QR/NFC memories | | not started | P9 |

## Phase details

### P0 — Foundations, test infrastructure and spikes
- **Objective:** a working monorepo skeleton with CI, **complete test infrastructure** (Android Emulator locally and in CI, iOS Simulator on cloud macOS, coverage gates, requirement traceability), and answers to the feasibility questions.
- **Deliverables:** repo layout per ADR-0012; CI workflows; Docker Compose (Postgres, Garage S3); Flutter, API, and web scaffolds each with passing tests; emulator/simulator pipelines; spikes S1–S7 with results in [spikes.md](../research/spikes.md).
- **Risks:** WHPX availability on the owner's PC (one-time admin enable); scarce macOS CI minutes; the Android motion ring buffer (S3).
- **Acceptance:** CI green on all scaffolds, including an emulator job and an iOS Simulator job; coverage gates active; each spike has a recorded result.
- **Tests:** scaffold tests per package; docs check; traceability report.
- **Docs:** spikes.md, capability-matrix.md (emulator columns), local-development.md, AGENTS.md commands.

### P1 — Camera core and local Memories
- **Objective:** open the app, see a preview, take a photo, and it's saved durably as a Memory and visible in a local library, on Android and iOS.
- **Requirements:** CAM-001–CAM-005, CAM-050–CAM-053, MEM-001, MEM-002, MEM-008, LIB-001, LIB-002, NFR-001, NFR-002.
- **Deliverables:**
  - `doro_camera` plugin (Kotlin + Swift): capability probe, preview texture, capture, and the synthetic test source (debug and test builds only).
  - Dart domain types; drift local DB; capture → Memory persistence; minimal library.
- **Acceptance (automated):**
  - 100 consecutive captures on the Android Emulator and 100 on the iOS Simulator (synthetic source) with zero loss.
  - An automated kill-during-capture loop leaves either a complete Memory or none.
- **Tests:** full obligations per [testing-strategy.md](../development/testing-strategy.md): Dart unit and widget tests, Kotlin/Swift unit tests, emulator instrumentation, `integration_test` on both platforms.
- **Field verification:** FV-001, FV-002, FV-006.

### P2 — Manual controls, Experiences, presets
- **Objective:** honest manual control and distinct Experiences on one engine.
- **Requirements:** CAM-006–CAM-008, CAM-010–CAM-014, CAM-020–CAM-022, CAM-030, CAM-031, CAM-040–CAM-042, CAM-044, CAM-046, EXP-001–EXP-008, EXP-010, EXP-011.
- **Acceptance (automated):**
  - On the Android Emulator, each manual control the emulated camera supports demonstrably changes the capture-result metadata.
  - On the iOS Simulator, the Swift apply logic is verified against fake capture devices, plus a synthetic-source end-to-end run.
  - Widget tests prove that unsupported controls are hidden, with an explanation, for every capability permutation.
- **Tests:** exhaustive and property-based resolver tests; widget and golden tests; emulator instrumentation.

### P3 — Image profile engine
- **Objective:** original film-inspired looks in live preview and at capture, non-destructively.
- **Requirements:** PRF-001–PRF-004, PRF-006, PRF-009, PRF-010.
- **Acceptance (automated):**
  - LUT compiler golden tests.
  - Render parity within tolerance between the TS reference renderer, ffmpeg, and the on-emulator/simulator GPU paths, using fixture images.
  - Performance (NFR-003) is field verification FV-003.

### P4 — Backend foundation and auth
- **Requirements:** AUTH-001, AUTH-004–AUTH-006, PRIV-003, NFR-006, NFR-008, NFR-011, NFR-013.
- **Deliverables:** Fastify modules; Drizzle schema and migrations; Better Auth; memories API; OpenAPI; generated TS and Dart clients; pg-boss worker.
- **Acceptance:** API integration tests on real Postgres cover every endpoint, error code, and authz-negative case; coverage gates met.

### P5 — Cloud storage, upload queue, sync
- **Requirements:** SYNC-001–SYNC-005, SYNC-008, LIB-004, NFR-005.
- **Acceptance (automated):** on the Android Emulator (and the iOS Simulator), a 200 MB file uploads to local S3 (Garage) through scripted network drops and app kills, with no duplicates and a verified checksum. Field verification FV-005 covers OEM background limits.

### P6 — Motion Memory
- **Requirements:** MOT-001–MOT-006, MOT-009, NFR-012.
- **Acceptance (automated):** an A/V sync test with synthetic flash/beep input on the emulator and simulator is within tolerance; the manifest round-trips; playback widget tests. Real microphone, battery and thermal checks are field verification FV-004.

### P7 — Web dashboard (MVP complete)
- **Requirements:** WEB-001–WEB-006, MOT-006.
- **Acceptance (automated):** Playwright E2E of the web journey, plus the **cross-system E2E**: an emulator app captures and uploads to the Docker stack in CI, and Playwright sees the Memory and plays its motion.

### P8–P13 — Post-MVP
Coarse epics are in [tasks/backlog.md](../tasks/backlog.md). Each phase is refined into a task file when it starts, with the same full-test-suite obligations. P12 (AI) requires a new ADR (e.g. embedding storage with pgvector) before any work.
