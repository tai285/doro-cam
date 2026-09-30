# Roadmap

Status: Living · Last updated: 2026-09-30 · Related: [requirements.md](requirements.md), [tasks](../tasks/README.md)

Phases are ordered by dependency and risk. Status values are `not started`, `in progress`, and `done`. Fine-grained tasks exist only for the current and next phases (see [tasks/README.md](../tasks/README.md)). Later phases are refined into task files when they start.

## Deviations from the original proposal (and why)

| Change | Reason |
|---|---|
| Local Memory store moved from phase 6 into P1 | Capture must save Memories from the first working build (NFR-002). A camera that writes loose files would need rework. |
| Backend foundation (P4) runs **in parallel** with P2–P3 | The backend has no dependency on camera work. Parallel work shortens the path to the MVP. |
| Video moved after the MVP (P8) | Video isn't in the MVP journey, and it's costly: codecs, transcoding, storage. |
| Motion Memory (P6) after upload (P5) | Motion capture is the riskiest capture feature. Its spike (S3) runs in P0, but the feature ships after the core loop works end to end. |
| Redis removed from the MVP | pg-boss on Postgres covers jobs (ADR-0010). |
| **Android leads, iOS follows** | There is no macOS machine yet. iOS tasks exist but stay `blocked: needs macOS`. |

## MVP scope realism

The MVP includes two native camera engines, a GPU look pipeline, motion capture, resumable sync, a backend, and a web app. That is large for one developer. The committed MVP is therefore:

- **Android-complete.** iOS reaches parity after a Mac is available.
- **Two fully built Experiences** (Mirrorless, Instant); DSLR and Film are styled variants (EXP-011).
- **About five profiles** (PRF-004).
- **Web: read-only library** plus account (WEB-001–WEB-006).

## Phase summary

| Phase | Name | MVP | Status | Depends on |
|---|---|---|---|---|
| P0 | Foundations and spikes | ✓ | in progress (planning done) | — |
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

### P0 — Foundations and spikes
- **Objective:** a working monorepo skeleton with CI, and answers to the feasibility questions before architecture is locked.
- **Deliverables:** repo layout per ADR-0012; CI; Docker Compose (Postgres, MinIO); Flutter, API, and web scaffolds; spikes S1–S7 with results in [spikes.md](../research/spikes.md).
- **Risks:** the Honor X9c may expose limited manual controls (S1). Android motion ring buffer feasibility (S3).
- **Acceptance:** CI green on all scaffolds; each spike has a recorded result and an updated capability matrix and ADR where needed.
- **Tests:** scaffold smoke tests; docs check.
- **Docs:** spikes.md, capability-matrix.md, local-development.md, AGENTS.md commands.

### P1 — Camera core and local Memories
- **Objective:** open the app, see a preview, take a photo, and it's saved durably as a Memory and visible in a local library.
- **Requirements:** CAM-001–CAM-005, CAM-050–CAM-053, MEM-001, MEM-002, MEM-008, LIB-001, LIB-002, NFR-001, NFR-002.
- **Deliverables:** `doro_camera` plugin (Android): capability probe, preview texture, capture. Dart domain types; drift local DB; capture → Memory persistence; minimal library.
- **Risks:** texture/preview performance on the Honor; orientation and EXIF handling.
- **Acceptance:** 100 consecutive captures on the reference device with zero loss; kill during capture leaves either a complete Memory or none, never a broken one.
- **Tests:** Dart unit tests (domain, persistence); widget tests with a fake camera platform; Kotlin unit tests for capability mapping; on-device manual script.
- **Docs:** capability-matrix.md (Honor verified column), specs/camera.md if the contract changed.

### P2 — Manual controls, Experiences, presets
- **Objective:** honest manual control and distinct Experiences on one engine.
- **Requirements:** CAM-006–CAM-008, CAM-010–CAM-014, CAM-020–CAM-022, CAM-030, CAM-031, CAM-040–CAM-042, CAM-044, CAM-046, EXP-001–EXP-008, EXP-010, EXP-011.
- **Deliverables:** manual controls in the plugin; the `CaptureIntent` resolver; Experience definitions; scenarios; local presets; capability-driven UI.
- **Risks:** OEM devices ignoring manual keys (they must be detected via capture results, CAM-050).
- **Acceptance:** each control shown on the reference device demonstrably changes the capture result metadata; unsupported controls are hidden with an explanation.
- **Tests:** exhaustive resolver unit tests; widget tests per capability permutation; on-device verification script.

### P3 — Image profile engine
- **Objective:** original film-inspired looks in live preview and at capture, non-destructively.
- **Requirements:** PRF-001–PRF-004, PRF-006, PRF-009, PRF-010.
- **Deliverables:** profile schema and LUT compiler (`packages/profiles`); preview grading (per the S2 decision); on-device capture render; about five profiles.
- **Risks:** preview/export mismatch; GPU cost on the mid-range device.
- **Acceptance:** preview at ≥ 30 fps with the profile on the Honor (NFR-003); parity within tolerance (S7 method).
- **Tests:** LUT compiler golden tests; render parity tests on fixture images.

### P4 — Backend foundation and auth
- **Objective:** a secure API for accounts and Memory metadata.
- **Requirements:** AUTH-001, AUTH-004–AUTH-006, PRIV-003, NFR-006, NFR-008, NFR-011, NFR-013.
- **Deliverables:** Fastify app with modules; Drizzle schema and migrations; Better Auth; memories metadata API; OpenAPI generation; generated TS and Dart clients; worker process skeleton with pg-boss.
- **Acceptance:** API integration tests (real Postgres) for auth and memories, including authorization-negative cases.

### P5 — Cloud storage, upload queue, sync
- **Objective:** Memories upload at original quality, resumably and idempotently, and appear in the cloud.
- **Requirements:** SYNC-001–SYNC-005, SYNC-008, LIB-004, NFR-005.
- **Deliverables:** uploads module (presign, multipart, complete, verify); mobile upload queue; background transfer; sync status UI; storage usage accounting.
- **Acceptance:** a 200 MB file uploads through airplane-mode toggles and app kills with no duplicates and a verified checksum.

### P6 — Motion Memory
- **Requirements:** MOT-001–MOT-006, MOT-009, NFR-012.
- **Deliverables:** Android ring-buffer capture (per the S3 result); motion manifest; local playback; upload of the motion asset; web rendition job.
- **Acceptance:** A/V in sync within the tolerance set by S3; battery impact measured and documented.

### P7 — Web dashboard (MVP complete)
- **Requirements:** WEB-001–WEB-006, MOT-006.
- **Deliverables:** React app with auth, library grid, detail with motion playback, original download, storage usage, account deletion.
- **Acceptance:** Playwright E2E of the MVP web journey against the Docker stack.

### P8–P13 — Post-MVP
Coarse epics are in [tasks/backlog.md](../tasks/backlog.md). Each phase is refined into a task file when it starts. P12 (AI) requires a new ADR (e.g. embedding storage with pgvector) before any work.
