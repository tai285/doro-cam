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
| Camera / native plugin | [architecture/camera.md](docs/architecture/camera.md), [specs/camera.md](docs/specs/camera.md), [specs/capability-matrix.md](docs/specs/capability-matrix.md), ADR-0001, ADR-0002, ADR-0003 |
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

You do **not** need to read every document for every task.

## 4. Workflow (every task)

1. Read this file, then the task, then the docs routed above.
2. Inspect the current implementation of the affected modules.
3. Check the ADRs that govern the area. Never contradict an accepted ADR.
4. For anything touching more than one module, write a short plan first: affected files, approach, tests, and doc updates.
5. Implement **only the requested scope**. Record discovered follow-ups as new tasks; do not implement them.
6. Write tests alongside the code. Tests must exercise real behavior. See [testing-strategy.md](docs/development/testing-strategy.md).
7. Run the relevant tests, linters, and type checks until they are green.
8. Review your own diff: no unrelated changes, no debug leftovers, no commented-out code.
9. Update the docs the change affects (see §6), and update the task's status.
10. Run `npm run check:docs`. It must report 0 errors.
11. Report what changed, which tests ran, which acceptance criteria are verified and how, what was *not* verified (e.g. "needs real device"), and any remaining issues.

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
- Mark a task `done` when acceptance criteria that need a real device were not verified. Use `blocked` or state what remains.

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
- tests are added and passing;
- lint and type checks pass;
- error cases are handled;
- security and privacy are considered;
- the docs are updated;
- `check:docs` passes;
- the acceptance criteria are verified, and anything that needs a real device is explicitly marked as such.

## 8. Commands

| Purpose | Command |
|---|---|
| Docs integrity check | `npm run check:docs` |
| Tooling tests | `npm test` |
| Tooling type check | `npm run typecheck` |

App-level commands (Flutter, API, web) are added here by the scaffolding tasks as they land. See [local-development.md](docs/development/local-development.md).

## 9. Environment facts

- Owner develops on **Windows 11**. **No macOS machine yet**, so iOS native code cannot be built. iOS tasks are `blocked: needs macOS`. Android leads.
- Reference devices: **Honor X9c** (Android, MagicOS) and **iPhone 12 Pro Max** (iOS, unusable until a Mac is available).
- Keep shell commands cross-platform or provide both PowerShell and POSIX variants. Line endings are LF (see `.gitattributes`).
