# ADR-0012: Polyglot monorepo and OpenAPI contract generation

Status: Accepted
Date: 2026-09-30
Related: NFR-010, [development-guide.md](../../development/development-guide.md), [api.md](../../specs/api.md)

## Context

The project spans Dart (mobile + plugin), TypeScript (API, worker, web, tooling), Kotlin, and Swift. Dart and Node have separate package ecosystems. The API contract must stay consistent between server, web, and mobile without hand-maintained duplicate types.

## Decision

- **One Git repository** with the layout in the development guide (`apps/`, `packages/`, `services/`, `tools/`, `infrastructure/`, `docs/`).
- TypeScript packages use **pnpm workspaces**. Dart packages use a **pub workspace**. They are not forced into one tool.
- The **API contract flows one way:** Zod route schemas (Fastify) → generated `openapi.json` (committed in `packages/api-contract`) → a generated TS client (web) and a generated Dart client (mobile). CI regenerates and fails on drift.
- Other shared artifacts between ecosystems are data files (compiled profile LUTs, JSON schemas), never shared code.
- CI is GitHub Actions, with path filters per package.

## Alternatives

- **Separate repos:** contract drift and cross-repo coordination overhead for a solo developer.
- **Nx / Turborepo:** useful later for caching. They don't solve Dart and aren't needed now.
- **Hand-written Dart models:** drift-prone.

## Consequences

- Contributors need both toolchains for full builds, but each package builds independently.
- The Dart OpenAPI generator's output quality must be evaluated at P4 (fallback: a generated low-level client plus thin handwritten adapters, still contract-tested).
