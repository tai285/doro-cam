# AGENTS.md — Doro Cam

Canonical instructions for every coding agent working in this repository: Claude Code, other agents, and humans acting like agents. `CLAUDE.md` imports this file. **Read this file completely before any task.** After that, read only the documents the routing table below points you to.

## 1. What this project is

Doro Cam is a cross-platform photography and memory platform:

**CAPTURE → PRESERVE → ORGANIZE → SHARE → UNDERSTAND → RELIVE.**

- A Flutter mobile app with professional, capability-aware camera controls, camera *Experiences* (Mirrorless, DSLR, Film, Instant), original film-inspired image profiles, and optional **Motion Memories** (photo + motion + sound).
- An offline-first local library that syncs original-quality media to S3-compatible storage through a Fastify API (PostgreSQL metadata).
- A React web dashboard for the library, sharing, and photography insights.

The central domain concept is the **Memory**. The north star is: *capture and preserve the feeling of a moment.* Full context: [docs/product/vision.md](docs/product/vision.md).

**Current state:** planning complete, **no application code yet**. See [docs/product/roadmap.md](docs/product/roadmap.md) for phase status and [docs/tasks/README.md](docs/tasks/README.md) for the next task.

## 2. Source of truth and authority

| Question | Authoritative location |
|---|---|
| *What* the product must do | [docs/product/requirements.md](docs/product/requirements.md) (stable IDs such as `CAM-010`) |
| *Why* a technical choice was made | [docs/decisions/adr/](docs/decisions/adr/README.md) |
| *Exact* contracts, schemas, protocols | [docs/specs/](docs/README.md#specs--exact-contracts) |
| *How* the system is structured | [docs/architecture/](docs/README.md#architecture--how-the-system-is-structured) |
| What to build next, and status | [docs/product/roadmap.md](docs/product/roadmap.md) and [docs/tasks/](docs/tasks/README.md) |
| How to work, test, and add dependencies | [docs/development/](docs/README.md#development--how-to-work) |
| Current behavior of built code | The code and its tests. If docs disagree with code, **report it**. |

For technical "how" questions, the order of precedence is: **accepted ADR > spec > architecture doc > everything else**. For product "what" questions, requirements win.

**Conflict rule:** if two documents contradict each other, or a document contradicts the code, **stop and report the contradiction**. Do not resolve it silently. Do not pick one and move on.

## 3. Task routing: what to read

Always read: this file, the task entry in `docs/tasks/`, and every doc the task's **Docs** field links to. Then add the docs for the task's area:

| Task area | Read |
|---|---|
| Camera / native plugin | [architecture/camera.md](docs/architecture/camera.md), [specs/camera.md](docs/specs/camera.md), [specs/capability-matrix.md](docs/specs/capability-matrix.md), ADR-0001, ADR-0002, ADR-0003, ADR-0013 |
| Image profiles / rendering | [specs/image-profile.md](docs/specs/image-profile.md), [architecture/camera.md](docs/architecture/camera.md), ADR-0004 |
| Motion Memory / media formats | [specs/media.md](docs/specs/media.md), [architecture/media-pipeline.md](docs/architecture/media-pipeline.md), ADR-0005 |
| Flutter app structure / UI | [architecture/mobile.md](docs/architecture/mobile.md), [design/ux-principles.md](docs/design/ux-principles.md), [design/camera-ux.md](docs/design/camera-ux.md) |
| Local DB / upload queue / sync | [architecture/sync.md](docs/architecture/sync.md), [specs/upload-sync.md](docs/specs/upload-sync.md), ADR-0008, ADR-0009 |
| Backend module / API | [architecture/backend.md](docs/architecture/backend.md), [specs/api.md](docs/specs/api.md), [specs/database.md](docs/specs/database.md), ADR-0006, ADR-0007 |
| Auth / permissions / privacy | [architecture/security.md](docs/architecture/security.md), [specs/sharing.md](docs/specs/sharing.md), ADR-0011 |
| Background jobs / worker | [architecture/backend.md](docs/architecture/backend.md), [architecture/media-pipeline.md](docs/architecture/media-pipeline.md), ADR-0010 |
| Web dashboard | [architecture/overview.md](docs/architecture/overview.md), [specs/api.md](docs/specs/api.md), [design/ux-principles.md](docs/design/ux-principles.md) |
| Domain model questions | [specs/memory-domain.md](docs/specs/memory-domain.md) |
| Tooling / CI / repo layout | [development/development-guide.md](docs/development/development-guide.md), ADR-0012 |
| Tests, emulators, simulators, cloud macOS | [development/testing-strategy.md](docs/development/testing-strategy.md), [development/local-development.md](docs/development/local-development.md), [development/field-verification.md](docs/development/field-verification.md), ADR-0013 |

You do **not** need to read every document for every task.

## 4. Workflow (every task)

1. Read this file, then the task, then the docs routed above.
2. Inspect the current implementation of the affected modules.
3. Check the ADRs that govern the area. Never contradict an accepted ADR.
4. For anything touching more than one module, write a short plan first: affected files, approach, tests, and doc updates.
5. Implement **only the requested scope**. Record discovered follow-ups as new tasks; do not implement them.
6. Write tests for **every** function, class, widget, endpoint, job, migration, and feature you add or change, in the same change. Tag tests with the requirement IDs they cover (e.g. `[CAM-010]`). Tests must exercise real behavior. Obligations: [testing-strategy.md](docs/development/testing-strategy.md).
7. Run the relevant tests, linters, type checks, and coverage gates until they are green. For mobile work, also run on the **Android Emulator** (locally or in CI) and the **iOS Simulator** via the cloud macOS workflow (`gh workflow run ios.yml`). See ADR-0013.
8. Review your own diff: no unrelated changes, no debug leftovers, no commented-out code.
9. Update the docs the change affects (see §6), and update the task's status.
10. Run `pnpm check:docs` and `pnpm check:traceability`. Both must report 0 errors.
11. Report:
    - what changed;
    - the exact test commands, with their pass/fail counts and coverage;
    - which acceptance criteria are verified, and where (host, emulator, simulator);
    - which hardware-only aspects you added to [field-verification.md](docs/development/field-verification.md);
    - any remaining issues.

## 5. Hard rules — agents must NOT

- Rewrite, reformat, or "clean up" code unrelated to the task.
- Change architecture silently. Architectural change requires a new or updated ADR **approved by the owner**.
- Add a dependency without following the [dependency policy](docs/development/development-guide.md#dependency-policy) and stating the justification.
- Delete, skip, or weaken tests to make them pass. Never assert on mocked behavior in place of real behavior when real behavior is testable.
- Weaken type safety: no `any` or `dynamic` escapes, no `// @ts-ignore`, no `!` null-assertion sprinkling to silence errors.
- Bypass authentication, authorization, upload validation, or signed-URL checks. This includes "temporarily" and in tests of production code paths.
- **Invent or simulate device capabilities.** If the hardware or API does not report a capability, the app does not offer it. Fake aperture or ISO is forbidden; *effects* must be labelled as effects.
- Implement future-phase features that were not requested.
- Introduce microservices, new datastores, or new infrastructure without an ADR.
- Replace a documented decision without updating its ADR (status `Superseded by ADR-XXXX`).
- Use proprietary film-stock names, logos, or trade dress in profiles.
- Commit secrets, keys, `.env` files, or personal data.
- Ship any function or feature without automated tests, lower a coverage ratchet, or mark a task `done` before its automated acceptance tests pass on every applicable target (host, Android Emulator, iOS Simulator).
- Claim that emulator or simulator results prove hardware-only properties (image quality, real performance, battery, thermals, OEM behavior). Log those in field-verification.md instead.
- Let the synthetic camera source reach a release build or report itself as real hardware.

## 6. Documentation maintenance triggers

| If you changed… | Update… |
|---|---|
| An architectural decision | The relevant `docs/architecture/*` doc and a new or superseding ADR |
| An API endpoint or contract | [specs/api.md](docs/specs/api.md) (and the regenerated OpenAPI once it exists) |
| The database schema | [specs/database.md](docs/specs/database.md) plus a Drizzle migration |
| Local DB schema (drift) | [architecture/sync.md](docs/architecture/sync.md) |
| User-visible behavior | [product/requirements.md](docs/product/requirements.md) (the owner approves requirement changes) |
| A device capability finding | [specs/capability-matrix.md](docs/specs/capability-matrix.md) |
| A spike outcome | [research/spikes.md](docs/research/spikes.md) and the affected research, spec, and ADR docs |
| A completed task | Its `Status:` in `docs/tasks/`, and roadmap status if a phase milestone moved |

Documentation that describes something that no longer exists is a bug.

## 7. Definition of Done (summary)

Full tiered definition: [development-guide.md](docs/development/development-guide.md#definition-of-done). In short, a feature is done when:

- the scope is implemented;
- **every new or changed function has automated tests**, requirement-tagged where applicable;
- all tests pass on host, the Android Emulator, and the iOS Simulator as applicable;
- coverage gates are met;
- lint and type checks pass;
- error cases are handled;
- security and privacy are considered;
- the docs are updated;
- `check:docs` passes;
- hardware-only aspects are logged in field-verification.md.

## 8. Commands

| Purpose | Command |
|---|---|
| Docs integrity check | `pnpm check:docs` |
| Coverage gate (floors + ratchet), after running a package's tests with coverage | `pnpm check:coverage -- --only <package>` · raise the ratchet after improving coverage: add `--update` and commit `coverage-policy.json` |
| Requirement-to-test traceability (every requirement of a `done` task has a tagged test or a reasoned waiver) | `pnpm check:traceability` |
| Tooling tests only (no Docker needed) | `pnpm test:tools` |
| Tests in every TypeScript package (API tests need `pnpm infra:up` first) | `pnpm test` |
| Type check (all TypeScript packages) | `pnpm typecheck` |
| Load the mobile toolchain (Flutter, JDK 17, Android SDK) | `source scripts/dev-env.sh` |
| API type check / tests with coverage (needs `pnpm infra:up`) | `pnpm --filter @doro/api typecheck` · `pnpm --filter @doro/api test:coverage` |
| Web lint / types / tests / e2e | `pnpm --filter @doro/web lint` · `typecheck` · `test:coverage` · `test:e2e` |
| Flutter analyze / tests (from `apps/mobile`) | `flutter analyze` · `flutter test --coverage` |
| Start the Android emulator (headless, waits for boot) / stop it | `bash scripts/emulator-start.sh` · `adb emu kill` |
| Flutter integration tests on the emulator (from `apps/mobile`) | `flutter test integration_test -d emulator-5554` |
| Start local Postgres + S3 (Docker must be running) | `pnpm infra:up` |
| Live-stack tests (after `infra:up`) | `pnpm test:infra` |

App-level commands (Flutter, API, web) are added here by the scaffolding tasks as they land. See [local-development.md](docs/development/local-development.md).

## 9. Environment facts

- The product name is **Doro Cam** (confirmed by the owner, 2026-09-30).
- The owner develops on **Windows 11** (i5-12450H, 16 GB RAM, WSL2 and Docker Desktop). There is **no local Mac** (ADR-0013):
  - **Android:** use the Android Emulator AVD `doro_api35` locally (needs Windows Hypervisor Platform; ask the owner to enable it if `emulator -accel-check` fails) and in CI with KVM.
  - **iOS:** every build and test runs on **cloud macOS** through GitHub Actions `ios.yml` (`bash scripts/ios-ci.sh` triggers it and waits). The repository is **public**, so macOS runners are free. One run takes about 9 minutes (Xcode 16.4, iPhone 16 Pro Max, iOS 18.6 simulator). Do not add an iOS workflow that uses a simulator runtime newer than the runner's Xcode: it hangs.
  - **iOS Simulator has no camera.** Use the plugin's synthetic source in debug and test builds only.
- The owner's physical devices (**Honor X9c**, **iPhone 12 Pro Max**) are for optional field verification only. Agents never depend on them.
- GitHub CLI: `gh` (on Windows at `C:\Program Files\GitHub CLI\gh.exe`), authenticated as `tai285`. The repo is `tai285/doro-cam` (private).
- Keep shell commands cross-platform or provide both PowerShell and POSIX variants. Line endings are LF (see `.gitattributes`).
