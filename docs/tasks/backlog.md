# Backlog — Epics for P3–P13

Coarse epics only. **Do not implement directly from this file.** When a phase starts, refine its epic into a `phase-N-*.md` task file (see [README.md](README.md)).

## EPIC P3 — Image profile engine
Requirements: PRF-001–PRF-004, PRF-006, PRF-009, PRF-010, NFR-003. Docs: [image-profile.md](../specs/image-profile.md), ADR-0004. Depends on the S2 and S7 results.
Includes: `packages/profiles` (schema, compiler, golden tests, committed LUTs); preview grading on Android; capture render pipeline (rendered/display/thumbnail); profile picker UI; five original profiles; parity tests.

## EPIC P4 — Backend foundation and auth
Requirements: AUTH-001, AUTH-004–AUTH-006, PRIV-003, PRIV-004, WEB-005, MEM-004, MEM-006, MEM-007, NFR-006, NFR-008, NFR-011. Docs: [backend.md](../architecture/backend.md), [api.md](../specs/api.md), [database.md](../specs/database.md), ADR-0006, ADR-0007, ADR-0011.
Includes: Better Auth integration; users_profile; memories module (list, get, patch, trash); authz helper with IDOR tests; OpenAPI generation plus the Dart and TS clients; mobile sign-in screens; transactional email provider decision.

## EPIC P5 — Cloud storage, upload queue, sync
Requirements: SYNC-001–SYNC-005, SYNC-008, LIB-004, NFR-005. Docs: [upload-sync.md](../specs/upload-sync.md), [sync.md](../architecture/sync.md), ADR-0008, ADR-0009. Depends on the S4 and S5 results.
Includes: assets module (create/resume upload, complete, download URL); storage_objects and dedupe; the asset.verify job; the mobile queue state machine and background transport; outbox for metadata; sync status UI; storage usage accounting.

## EPIC P6 — Motion Memory
Requirements: MOT-001–MOT-006, MOT-009, CAM-052, NFR-012. Docs: [media.md](../specs/media.md), ADR-0005. Depends on the S3 result.
Includes: productionize the Android ring buffer; microphone permission; LIVE toggle UX; manifest; local playback; motion.transcode job; iOS Live Photo source (blocked: needs macOS).

## EPIC P7 — Web dashboard (MVP complete)
Requirements: WEB-001–WEB-006, MOT-006, NFR-007. Docs: [ux-principles.md](../design/ux-principles.md), [api.md](../specs/api.md).
Includes: auth pages; library grid (cursor pagination); detail with motion playback; original download; storage usage; account deletion; Playwright E2E of the MVP web journey.

## EPIC P8 — Video
Requirements: VID-001–VID-006. Docs: [media-pipeline.md](../architecture/media-pipeline.md). Depends on the S6 result.

## EPIC P9 — Shared albums and trips
Requirements: SHR-001–SHR-007, PRIV-002, WEB-007. Docs: [sharing.md](../specs/sharing.md), [security.md](../architecture/security.md).
Includes: the asset.sanitize job and location-leak tests.

## EPIC P10 — Photography analytics
Requirements: ANL-001–ANL-005, WEB-009. Deterministic aggregates over typed memory columns.

## EPIC P11 — Personalized presets
Requirements: PRE-001–PRE-003. Deterministic clustering of settings and profile usage, with explanations.

## EPIC P12 — AI (requires a new ADR first)
Requirements: AI-001–AI-004. Embedding storage (e.g. pgvector), opt-in, and privacy disclosure.

## EPIC P13 — Physical memories
Requirements: PHY-001–PHY-003. Uses `publicHandle` (MEM-008) and album permissions.

## Unscheduled
- Level indicator (CAM-043), HDR toggle (CAM-045), RAW (CAM-047), histogram (CAM-048), Film roll constraint (EXP-009).
- Multi-device pull sync and conflicts (SYNC-006, SYNC-007), free-up-space (LIB-005), filters (LIB-003), tags (MEM-005).
- Google and Apple sign-in (AUTH-002, AUTH-003), data export (WEB-010, PRIV-006), preset management on the web (WEB-008).
- Post-capture profile change (PRF-005), extra effects (PRF-007), custom profiles (PRF-008), video grading (PRF-011), key frame choice (MOT-007).
