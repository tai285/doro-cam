# Phase 0 — Foundations and Spikes

Roadmap: [P0](../product/roadmap.md). Planning (docs, ADRs, docs checker, CI for docs) is complete. The remaining work is scaffolding and spikes. Spikes can run in parallel with scaffolding. S1 and S3 are the most important and need the Honor X9c.

### FND-T-001 Convert repo root to a pnpm workspace
- **Status:** todo
- **Platform:** infra
- **Depends:** none
- **Requirements:** NFR-010
- **Docs:** [development-guide.md](../development/development-guide.md), ADR-0012
- **Scope:** enable Corepack + pnpm; add `pnpm-workspace.yaml` (`apps/web`, `services/*`, `packages/profiles`, `packages/api-contract`, `tools/*`); move `tools/docs-check` into a workspace package; replace `package-lock.json` with `pnpm-lock.yaml`; keep root scripts `test`, `typecheck`, `check:docs` working.
- **Out of scope:** creating the app packages themselves.
- **Acceptance:** `pnpm install && pnpm test && pnpm typecheck && pnpm check:docs` pass locally and in CI; no `package-lock.json` remains.
- **Tests:** the existing docs-check tests run through pnpm.
- **Doc updates:** AGENTS.md §8 commands; local-development.md; CI workflow.

### FND-T-002 CI baseline and dependency automation
- **Status:** todo
- **Platform:** infra
- **Depends:** FND-T-001
- **Requirements:** NFR-010
- **Docs:** [testing-strategy.md](../development/testing-strategy.md)
- **Scope:** restructure `.github/workflows/` into `ci.yml` with path-filtered jobs (docs/tools now; mobile, api, web jobs added by their scaffold tasks); add a Dependabot config for npm, pub, gradle, and github-actions; enable branch protection guidance in the docs.
- **Out of scope:** macOS runners.
- **Acceptance:** CI is green on main; a PR touching only docs runs only the docs job.
- **Tests:** CI runs on a test PR.
- **Doc updates:** development-guide.md (CI section).

### FND-T-003 Local infrastructure with Docker Compose
- **Status:** todo
- **Platform:** infra
- **Depends:** FND-T-001
- **Requirements:** NFR-013
- **Docs:** [local-development.md](../development/local-development.md), ADR-0008
- **Scope:** `infrastructure/docker-compose.yml` with Postgres 17 and MinIO; `minio-init` creating the bucket, CORS for the web origin, and a lifecycle rule to abort incomplete multipart uploads after 7 days; `.env.example`.
- **Out of scope:** production deployment.
- **Acceptance:** `docker compose up -d` gives healthy services on Windows; the bucket exists with the lifecycle rule (verified via `mc ilm ls`).
- **Tests:** a smoke script checks Postgres connectivity and a MinIO presigned PUT/GET roundtrip.
- **Doc updates:** local-development.md (move from planned to available).

### FND-T-004 Flutter app scaffold
- **Status:** todo
- **Platform:** dart
- **Depends:** FND-T-001
- **Requirements:** NFR-009, NFR-010
- **Docs:** [mobile.md](../architecture/mobile.md), ADR-0012
- **Scope:** install the Flutter SDK (stable) and Android toolchain; root `pubspec.yaml` pub workspace; `apps/mobile` with the folder layout from mobile.md, Riverpod, go_router, strict analysis options, an empty camera route; `apps/mobile/AGENTS.md`; CI job (analyze, test, build a debug APK).
- **Out of scope:** camera functionality.
- **Acceptance:** the app runs on the Honor X9c showing a placeholder camera route; CI mobile job green.
- **Tests:** one widget test for app startup and routing.
- **Doc updates:** AGENTS.md §8; local-development.md.

### FND-T-005 doro_camera plugin scaffold with Pigeon
- **Status:** todo
- **Platform:** dart
- **Depends:** FND-T-004
- **Requirements:** CAM-004
- **Docs:** [specs/camera.md](../specs/camera.md), ADR-0001
- **Scope:** `packages/doro_camera` federated-style package in the pub workspace (Android Kotlin module and an iOS Swift stub); Pigeon setup with a `ping`/`platformVersion` host API to prove the bridge; `CameraPlatform` abstract class; `FakeCameraPlatform` in `lib/testing.dart`; `packages/doro_camera/AGENTS.md`.
- **Out of scope:** real camera calls.
- **Acceptance:** the app calls `ping` on the Honor and gets a response; Kotlin unit tests run in CI.
- **Tests:** Dart test for the fake; JUnit test for the Kotlin host API.
- **Doc updates:** development-guide.md (codegen notes).

### FND-T-006 Fastify API skeleton
- **Status:** todo
- **Platform:** api
- **Depends:** FND-T-001, FND-T-003
- **Requirements:** NFR-008, NFR-011, NFR-013
- **Docs:** [backend.md](../architecture/backend.md), ADR-0006, ADR-0007
- **Scope:** `services/api` with `app.ts`, `server.ts`, `worker.ts`, zod config, pino logging with request IDs, the error envelope, `/healthz` and `/readyz`, Drizzle setup with an empty migration, pg-boss boot in the worker, Vitest + Testcontainers, a Dockerfile, `services/api/AGENTS.md`, and a CI job.
- **Out of scope:** auth and business modules.
- **Acceptance:** `/readyz` reports DB and storage status correctly (including a test with storage down); CI green.
- **Tests:** integration tests for health endpoints and the error envelope; worker boot test.
- **Doc updates:** backend.md status; AGENTS.md §8.

### FND-T-007 React web scaffold
- **Status:** todo
- **Platform:** web
- **Depends:** FND-T-001
- **Requirements:** NFR-007, NFR-010
- **Docs:** [ux-principles.md](../design/ux-principles.md), ADR-0012
- **Scope:** `apps/web` with Vite, React, TypeScript strict, React Router, TanStack Query, ESLint and Prettier, Vitest + Testing Library, a Playwright config, design-token CSS variables (placeholder values), `apps/web/AGENTS.md`, and a CI job.
- **Out of scope:** real pages.
- **Acceptance:** `pnpm --filter web build` succeeds; one component test and one Playwright smoke test pass in CI.
- **Tests:** as above.
- **Doc updates:** AGENTS.md §8.

### SPK-T-001 Spike S1: manual controls on Honor X9c
- **Status:** todo
- **Platform:** android
- **Depends:** none
- **Requirements:** CAM-004, CAM-010, CAM-011, CAM-006
- **Docs:** [spikes.md](../research/spikes.md), [camera-apis.md](../research/camera-apis.md)
- **Scope:** the experiment defined in S1; a characteristics dump plus requested-vs-applied measurements.
- **Out of scope:** production plugin code.
- **Acceptance:** S1 result recorded; the capability matrix Honor column filled; the owner is informed whether a Pixel is needed.
- **Tests:** n/a (spike). The dump script is re-runnable.
- **Doc updates:** spikes.md, capability-matrix.md, ADR-0002 if the model changes.

### SPK-T-002 Spike S2: preview grading performance
- **Status:** todo
- **Platform:** android
- **Depends:** SPK-T-001
- **Requirements:** NFR-003, PRF-001
- **Docs:** [spikes.md](../research/spikes.md), [image-processing.md](../research/image-processing.md)
- **Scope:** the S2 experiment comparing the native GL and Flutter shader pipelines.
- **Out of scope:** the production profile engine.
- **Acceptance:** S2 result recorded with fps, latency, and battery numbers; the preview pipeline choice is written into camera.md, and ADR-0004 is updated if needed.
- **Tests:** n/a (spike).
- **Doc updates:** spikes.md, architecture/camera.md.

### SPK-T-003 Spike S3: Android motion ring buffer
- **Status:** todo
- **Platform:** android
- **Depends:** SPK-T-001
- **Requirements:** MOT-002, MOT-009, NFR-012
- **Docs:** [spikes.md](../research/spikes.md), [motion-capture.md](../research/motion-capture.md), ADR-0005
- **Scope:** the S3 experiment, including the clap test and battery and thermal measurement.
- **Out of scope:** UI and the production integration.
- **Acceptance:** S3 result recorded; ADR-0005 status updated (validated or revised with a fallback).
- **Tests:** unit tests for the ring buffer indexing logic (it is pure and reusable later).
- **Doc updates:** spikes.md, media.md, ADR-0005.

### SPK-T-004 Spike S4: background multipart uploads
- **Status:** todo
- **Platform:** dart
- **Depends:** FND-T-003, FND-T-004
- **Requirements:** SYNC-002, SYNC-003
- **Docs:** [spikes.md](../research/spikes.md), [upload-sync.md](../specs/upload-sync.md)
- **Scope:** the S4 experiment against local MinIO (reachable via `adb reverse`).
- **Out of scope:** the production queue.
- **Acceptance:** S4 result recorded, with MagicOS behavior noted.
- **Tests:** n/a (spike).
- **Doc updates:** spikes.md, uploads-storage.md.

### SPK-T-005 Spike S5: queue durability kill-loop
- **Status:** todo
- **Platform:** dart
- **Depends:** SPK-T-004
- **Requirements:** SYNC-001, NFR-002
- **Docs:** [spikes.md](../research/spikes.md), [sync.md](../architecture/sync.md)
- **Scope:** the S5 automated kill-loop harness and integrity checker.
- **Out of scope:** —
- **Acceptance:** S5 result recorded; the harness is kept for reuse in P5.
- **Tests:** the integrity checker itself has unit tests.
- **Doc updates:** spikes.md, ADR-0009 if needed.

### SPK-T-006 Spike S6: worker transcode isolation
- **Status:** todo
- **Platform:** api
- **Depends:** FND-T-006
- **Requirements:** NFR-013
- **Docs:** [spikes.md](../research/spikes.md), [media-pipeline.md](../architecture/media-pipeline.md)
- **Scope:** the S6 experiment.
- **Out of scope:** the production transcode job.
- **Acceptance:** S6 result recorded, with a worker resource-limit recommendation.
- **Tests:** n/a (spike).
- **Doc updates:** spikes.md, backend.md.

### SPK-T-007 Spike S7: LUT parity method
- **Status:** todo
- **Platform:** any
- **Depends:** FND-T-001
- **Requirements:** PRF-009
- **Docs:** [spikes.md](../research/spikes.md), [image-profile.md](../specs/image-profile.md)
- **Scope:** a TS reference renderer and ΔE2000 tool; comparison with ffmpeg `lut3d` interpolations. The on-device part follows SPK-T-002.
- **Out of scope:** the full profile set.
- **Acceptance:** S7 result recorded; parity thresholds confirmed or revised with the owner.
- **Tests:** ΔE2000 implementation tested against published reference pairs.
- **Doc updates:** spikes.md, image-profile.md.
