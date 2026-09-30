# Development Guide

Status: Living · Last updated: 2026-09-30 · Related: ADR-0012, NFR-009, NFR-010

## Repository structure

Target layout (ADR-0012). Directories are created by their scaffolding tasks, not ahead of time.

```
/
├── AGENTS.md  CLAUDE.md  README.md  package.json (workspace root)
├── apps/
│   ├── mobile/            Flutter app                       (Dart pub workspace member)
│   └── web/               React + Vite                      (pnpm workspace member)
├── packages/
│   ├── doro_camera/       Flutter plugin: Dart + android/ (Kotlin) + ios/ (Swift)   (pub)
│   ├── profiles/          Profile JSON + schema + LUT compiler (TS) + compiled LUTs (pnpm)
│   └── api-contract/      Generated openapi.json + generated TS client               (pnpm)
├── services/
│   └── api/               Fastify API + worker entrypoints  (pnpm)
├── tools/
│   └── docs-check/        Documentation integrity checker   (exists)
├── infrastructure/        docker-compose.yml, Dockerfiles, bucket policies
├── docs/
└── .github/workflows/
```

**Why not one package manager:** Dart and Node ecosystems don't share tooling. TypeScript packages use **pnpm workspaces**. Dart packages use a **pub workspace** (root `pubspec.yaml` with `workspace:` listing `apps/mobile` and `packages/doro_camera`). They meet only at the OpenAPI contract and the compiled profile LUT files, which are both committed artifacts.

Until FND-T-001 lands, the root `package.json` uses npm with devDependencies only for tooling. FND-T-001 migrates it to pnpm.

## Nested AGENTS.md (created with each scaffold)

Each of `apps/mobile`, `apps/web`, `services/api`, and `packages/doro_camera` gets an `AGENTS.md` of at most ~60 lines containing:
1. What this package is (one paragraph) and links to its architecture doc and spec.
2. Local commands: install, run, test, lint, format, codegen.
3. Package-specific rules (e.g. "no business logic in Kotlin", "every route declares response schemas").
4. Test locations and naming.

They must not restate root rules.

## Conventions

### Dart / Flutter
- `flutter_lints` + `very_good_analysis`-level strictness (decided at scaffold). `strict-casts`, `strict-inference`, `strict-raw-types` are on.
- No `dynamic` in domain or application code. Prefer sealed classes for states and failures.
- File names in `snake_case`. One public type per file in the domain.
- Codegen (riverpod_generator, drift, pigeon, freezed if used): build_runner outputs are **not** committed; CI regenerates them. Pigeon outputs **are** committed, because the native code compiles against them. The scaffold task records this in the package AGENTS.md.

### TypeScript
- `strict: true`, `noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`. ESM only.
- ESLint (typescript-eslint strict) + Prettier.
- No default exports in the API. Zod schemas are colocated with routes.

### Kotlin / Swift
- Kotlin: ktlint; coroutines for async; no blocking on the camera thread.
- Swift: SwiftLint (when a Mac is available); Swift concurrency where AVFoundation permits; camera work on a dedicated serial queue.

### Git
- Trunk-based: short-lived branches `feat/<task-id>-slug`, `fix/…`, `docs/…`.
- Commit messages follow Conventional Commits and reference task IDs: `feat(camera): expose ISO range (CAM-T-020)`.
- Every PR runs CI. No merging on red.

## Dependency policy

Before adding **any** dependency (npm, pub, Gradle, SwiftPM/CocoaPods), the agent must state in the PR or report:

| Question | Minimum bar |
|---|---|
| Necessity | Can it be done in under ~100 lines of our own code with tests? If yes, prefer that. |
| Maintenance | Release within the last 12 months; issues triaged; more than one maintainer or a backing org |
| License | MIT, BSD, Apache-2.0, ISC, MPL-2.0 OK. GPL/AGPL/SSPL are **forbidden** without an owner decision. |
| Security | No open critical advisories; the transitive tree is reviewed for size |
| Platform fit | Supports Android + iOS (mobile), or Node 24 LTS / evergreen browsers |
| Size and performance | Web bundle impact noted; mobile binary size noted for native SDKs |
| Native integration | If it wraps native camera or media APIs, it needs an ADR check: camera access goes through `doro_camera` only (ADR-0001) |

A dependency that becomes a **structural choice** (state management, ORM, auth, queue, router) requires an ADR, or must already be in one.

Lockfiles are always committed. Dependabot or Renovate is configured in P0 (FND-T-002).

## Definition of Done

Three tiers. The PR or report states which tier applies.

**Tier 1 — trivial** (typo, comment, config value, doc fix):
- [ ] Change is minimal and scoped
- [ ] Existing checks pass (`check:docs` for docs changes)

**Tier 2 — feature or bug fix** (the default):
- [ ] Scope matches the task; out-of-scope ideas are recorded as new tasks
- [ ] Unit tests for logic, plus integration tests where a boundary is crossed (DB, HTTP, platform channel)
- [ ] Bug fixes include a regression test that fails before the fix
- [ ] Lint, format, and type checks pass for every touched package
- [ ] Errors handled with typed failures and user-facing messages where relevant
- [ ] Security and privacy considered (authz, validation, location, logging)
- [ ] Logging added where operationally useful, and without sensitive data
- [ ] Docs updated per AGENTS.md §6; `check:docs` passes
- [ ] Acceptance criteria verified. Device-only criteria have an executed manual script or are explicitly marked *pending device verification* (then the task is not `done`)

**Tier 3 — architectural** (new module, new dependency class, protocol or schema change, anything touching an ADR):
- [ ] Everything in Tier 2
- [ ] ADR created or updated, and owner approval recorded
- [ ] Architecture and spec docs updated
- [ ] Migration or rollback considered

## Documentation rules

- Docs describe the *intended* design until code exists, and are marked `(planned)`. After implementation they describe reality.
- Prefer updating an existing doc over creating a new one. A new doc must be added to [docs/README.md](../README.md) with a one-line purpose, or `check:docs` fails.
- Mermaid diagrams show *stable* structure (containers, state machines, sequences). Don't diagram class-level details that change weekly.
- Requirement IDs are defined only in [requirements.md](../product/requirements.md). Reference them everywhere else.
- Research notes record evidence. Decisions go in ADRs.
