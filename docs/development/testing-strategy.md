# Testing Strategy

Status: Accepted · Last updated: 2026-09-30 · Related: NFR-009, NFR-010, [development-guide.md](development-guide.md)

## Principles

1. **Test real behavior.** Use fakes at architectural boundaries (camera platform, clock, network transport). Don't mock the unit under test's own collaborators into meaninglessness.
2. **Real infrastructure for integration tests.** API tests run against real Postgres and MinIO (Testcontainers or the Compose stack), not in-memory substitutes.
3. **No weakening.** Never delete, skip, or loosen a test to get green. Fix the code, or record why the test is wrong and fix the test in the same change with justification.
4. **Deterministic.** Inject clocks, random seeds, and IDs. Flaky tests are bugs with an owner.
5. **Hardware honesty.** CI can't test camera hardware. Device-dependent behavior gets scripted manual verification on real devices, recorded in the task.

## Test matrix

| Layer | Tool | What | Runs in CI |
|---|---|---|---|
| Dart domain/application | `package:test` | Resolver, Memory invariants, upload state machine, sync conflict rules; property tests for the resolver | ✓ |
| Flutter widgets | `flutter_test` + `FakeCameraPlatform` | Camera screen renders from capability permutations; adjustments shown; library states | ✓ |
| drift DB | `drift` in-memory/native SQLite | DAOs, transactions, **every migration step** (drift schema verification) | ✓ |
| Upload queue | Dart tests with a fake transport + real drift | Crash/restart resumes at the right state; no duplicates | ✓ |
| Plugin Dart layer | `package:test` | Pigeon message mapping, error mapping | ✓ |
| Android native | JUnit + Robolectric | Capability mapping from `CameraCharacteristics` fixtures, Kelvin → gains math, ring-buffer indexing | ✓ |
| iOS native | XCTest | Same pure-logic tests | ✓ only with a macOS runner (see below) |
| On-device integration | `integration_test` on a physical device | Open, preview, capture, file + DB written; manual settings applied (reads `CaptureResult`) | ✗ manual on the Honor X9c (and the iPhone later) |
| Device manual scripts | Markdown checklists in the task | Visual, thermal, battery, OEM behaviors, A/V sync clap test | ✗ manual |
| Profiles | Vitest | Schema validation, LUT compiler golden files, CPU reference render parity | ✓ |
| API unit | Vitest | Services with a real DB where queries matter; pure logic without | ✓ |
| API integration | Vitest + Fastify `inject` + Testcontainers (Postgres, MinIO) | Every endpoint: success, validation, 401, IDOR 404, idempotency | ✓ |
| Worker | Vitest + real Postgres/MinIO + ffmpeg in the container | Job handlers idempotent; checksum mismatch path; transcode output probed with ffprobe | ✓ |
| Contract | Script | Committed OpenAPI equals generated; the Dart and TS clients regenerate cleanly | ✓ |
| Web | Vitest + Testing Library | Components and hooks with MSW for HTTP | ✓ |
| E2E | Playwright against the Docker Compose stack | Sign in → library → detail → motion play → download | ✓ |
| Docs | `tools/docs-check` | Links, anchors, requirement IDs, ADRs, task graph, index reachability | ✓ |

## CI vs real devices

- **Linux runners:** everything except iOS native builds and physical-device tests.
- **macOS runners:** needed for iOS builds and XCTest. There is no Mac locally, so iOS CI is enabled when iOS work starts. It uses GitHub macOS runners (billed minutes) on PRs that touch `packages/doro_camera/ios/**` or `apps/mobile/ios/**`, plus nightly.
- **Android emulator in CI:** used only for smoke tests of app startup and plugin registration. The emulator camera is synthetic, so no camera-quality assertions are made there.
- **Physical devices:** the owner's Honor X9c (now) and iPhone 12 Pro Max (once a Mac is available). Cloud device farms (Firebase Test Lab) are an option for OEM coverage later; this needs an owner decision because it is billed.

## Device verification record

Tasks with device-dependent acceptance include a checklist like:

```
Device: Honor X9c, MagicOS x.y, app build <sha>
[ ] Step 1 … expected … observed …
Result: pass/fail · Date: YYYY-MM-DD
```

Results that reveal capability facts are copied into [capability-matrix.md](../specs/capability-matrix.md).

## Coverage expectations

Coverage isn't a goal in itself, but these floors apply:
- The resolver and profile compiler: 100% branch coverage.
- The upload state machine, sync conflict rules, and authz helpers: 100% branch coverage.
- Other modules: every public behavior and every error code has a test.
