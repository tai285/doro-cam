# AGENTS.md — services/api

Fastify API and pg-boss worker (one codebase, two processes). Read the root [AGENTS.md](../../AGENTS.md) first; this file adds only what is specific to this package. Architecture: [docs/architecture/backend.md](../../docs/architecture/backend.md). Contracts: [specs/api.md](../../docs/specs/api.md), [specs/database.md](../../docs/specs/database.md), [architecture/security.md](../../docs/architecture/security.md).

## Commands

Run from `services/api` (or with `pnpm --filter @doro/api <script>` from the root). The integration tests need the local stack: run `pnpm infra:up` from the root first (Docker must be running).

| Purpose | Command |
|---|---|
| Type check | `pnpm typecheck` |
| All tests | `pnpm test` |
| Tests with coverage (enforces the thresholds) | `pnpm test:coverage` |
| Run the API / worker with reload | `pnpm dev` · `pnpm worker:dev` (config comes from the environment, see `.env.example`) |
| Generate a migration after editing a module schema | `pnpm db:generate` |
| Apply migrations | `pnpm db:migrate` |
| Production build | `pnpm build` |
| Docker image (from the repo root) | `docker build -f services/api/Dockerfile -t doro-api .` |

## Structure and rules

- `src/app.ts` builds the app (no listening); `src/runtime/` starts it; `src/server.ts` and `src/worker.ts` are 3-line entrypoints. Keep them that way.
- Modules live in `src/modules/<name>/` (`routes.ts`, `service.ts`, `repository.ts`, `schema.ts`) and register through `buildApp(..., { modules })`. A module calls other modules' **services** only, never their repositories or tables.
- **Authorization is checked in services**, not routes (`assertCan`, added with the first module). Return `404` rather than `403` when the caller must not learn a resource exists.
- **Every route declares Zod schemas** for params, query, body and every response status. Responses are serialized through their schema so unknown fields cannot leak.
- **Throw `AppError` subclasses** (`src/lib/errors.ts`) and never build error bodies by hand. The single handler in `src/lib/error-handler.ts` produces the documented envelope and hides the details of unexpected errors.
- **Never log** tokens, presigned URLs, precise location, captions or request bodies (NFR-011). Authorization and cookie headers are already redacted.
- **Configuration** comes only from `src/config/env.ts` (validated at startup, fails fast, never echoes values). Do not read `process.env` anywhere else.
- **Database changes:** edit the module's `schema.ts`, re-export it from `src/db/schema.ts`, run `pnpm db:generate`, review the SQL, commit the migration. Never edit an applied migration. Update [specs/database.md](../../docs/specs/database.md).
- **Storage:** build S3 clients only through `createStorage` (`src/lib/storage.ts`). It disables the AWS SDK's default checksums, without which every presigned URL is rejected. Do not send media through the API (ADR-0008).
- **Jobs:** create pg-boss instances only through `createJobs`. Enqueue inside the same transaction as the state change that triggers the job (ADR-0010). Handlers must be idempotent.

## Tests

- Tests live in `test/` and run with Vitest. Integration tests use the **real** Postgres and S3 from `pnpm infra:up`, never mocks. `test/helpers/` creates an isolated database per test file (`createTestDatabase`) and builds the real app (`buildTestApp`).
- Every endpoint needs tests for success, validation failure, unauthenticated, and unauthorized (IDOR: expect 404) cases, plus every documented error code.
- Tag tests with the requirement they cover: `it('[SYNC-003] resumes from the last part', ...)`.
- Coverage thresholds are in `vitest.config.ts` (95% statements/lines/functions, 90% branches) and may not be lowered. `server.ts`, `worker.ts` and `migrate-cli.ts` are excluded from coverage because they are tested as real child processes in `test/entrypoints.test.ts`.
