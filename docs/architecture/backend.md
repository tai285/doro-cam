# Backend Architecture (Fastify modular monolith)

Status: Accepted (planned; not yet scaffolded) · Last updated: 2026-09-30 · Related: ADR-0006, ADR-0007, ADR-0010, ADR-0011, ADR-0012

## Shape

One TypeScript codebase in `services/api/` with **two entrypoints**:

- `src/server.ts`: the HTTP API (Fastify).
- `src/worker.ts`: the pg-boss worker (no HTTP server except a health port).

Both share modules, the DB schema, and configuration. They deploy as two processes from the same image (NFR-013).

## Module layout

```
services/api/src/
  app.ts                # builds the Fastify instance (used by server and tests)
  server.ts  worker.ts
  config/               # env parsing (zod), fail fast on invalid config
  db/                   # drizzle client, schema index, migrations/
  lib/                  # errors, logger, ids, pagination, storage (S3 client), jobs (pg-boss wrapper)
  modules/
    auth/               # Better Auth integration, session plugin, device sessions
    users/              # profile, storage usage, deletion request
    memories/           # memory metadata CRUD, listing, trash
    assets/             # upload orchestration, presign, complete, download URLs
    albums/             # (P9) albums, membership, invites
    presets/            # user presets sync
    analytics/          # (P10) aggregates
    sync/               # change feed
  jobs/                 # job handlers, grouped by module: assets.verify, motion.transcode…
```

Each module contains `routes.ts` (HTTP + Zod schemas), `service.ts` (business rules), `repository.ts` (Drizzle queries), `schema.ts` (tables owned by the module), and `*.test.ts`.

## Module rules

1. Routes call their own module's service. Services call their own repository **and other modules' services**, never other modules' repositories or tables.
2. Authorization happens in the service layer through a shared `authz` helper (`assertCan(actor, action, resource)`). Routes only authenticate.
3. Cross-module side effects that can be asynchronous go through jobs, enqueued **inside the same DB transaction** as the state change (pg-boss uses the same Postgres, per ADR-0010).
4. There are no circular module dependencies. A lint rule (dependency-cruiser or eslint boundaries) enforces this once scaffolded.
5. Schemas are Zod. `@fastify/swagger` emits OpenAPI from them, and the committed `openapi.json` is regenerated and diff-checked in CI (ADR-0012).

## Request lifecycle

```
request → requestId → rate limit → auth (session → actor) → zod validation → route → service (authz) → repository → response serializer (zod)
```

Responses are serialized with schemas, so unknown fields (e.g. location for non-owners) cannot leak by accident.

## Error model

A single `AppError` hierarchy maps to the envelope in [specs/api.md](../specs/api.md): `{ error: { code, message, details?, requestId } }`. Codes are stable strings (e.g. `memory.not_found`, `upload.checksum_mismatch`). Unexpected errors → 500 with a generic message. Details are logged, not returned.

## Jobs (pg-boss)

| Job | Trigger | Idempotency key |
|---|---|---|
| `asset.verify` | upload complete | assetId |
| `motion.transcode` | motion_clip verified | assetId |
| `derivative.fallback` | memory complete without thumbnail/display | memoryId |
| `asset.sanitize` | first non-owner request for an original with location hidden | assetId |
| `memory.purge` | trash expiry (scheduled daily) | memoryId |
| `user.delete` | account deletion confirmed | userId |

Handlers are pure functions of `(job data, deps)` so they can be tested directly. Retries use exponential backoff. After max attempts, the asset or memory is marked `failed` with a reason and the failure is visible in logs.

## Logging and observability

- `pino` (Fastify default) JSON logs, with `requestId` and `jobId` correlation.
- Never log tokens, presigned URLs, precise location, or captions (NFR-011).
- Health: `GET /healthz` (process) and `GET /readyz` (DB + storage reachable).
- Metrics and tracing (OpenTelemetry) are deferred until deployment (P4 decision).

## Configuration

All config comes from environment variables validated at startup: `DATABASE_URL`, `S3_ENDPOINT`, `S3_BUCKET`, `S3_REGION`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`, `AUTH_SECRET`, `PUBLIC_BASE_URL`, and so on. `.env.example` documents them. Real `.env` files are never committed.
