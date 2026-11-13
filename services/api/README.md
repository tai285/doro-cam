# Doro Cam API and worker

Fastify modular monolith plus a pg-boss worker (docs/architecture/backend.md). One image, three commands:
`node dist/server.js` (HTTP API), `node dist/worker.js` (jobs) and `node dist/db/migrate-cli.js` (migrations).

## Run locally (inside WSL)

```bash
source scripts/dev-env.sh && pnpm install
pnpm infra:up                                  # Postgres + Garage S3, bucket and key bootstrapped
cp .env.example .env                           # optional; defaults match the dev stack
pnpm --filter @doro/api db:migrate
pnpm --filter @doro/api dev                    # API on :3000
pnpm --filter @doro/api worker:dev             # worker (needs ffmpeg on PATH for video jobs)
```

Without a mail provider the API logs verification and reset links (`LogMailer`); look for
`email (not delivered: log mailer)` in its output. ADR-0011 leaves the email provider as an owner decision.

## Run as containers

`deploy/docker-compose.yml` builds the image and starts Postgres, the migrations, the API and the worker.
See the header of that file; set `POSTGRES_PASSWORD`, `AUTH_SECRET` and the S3 credentials in `deploy/.env`.

## Configuration

Every variable is in [`.env.example`](../../.env.example). `AUTH_SECRET` is required in production.
Social sign-in (Google, Apple) is off until both the id and secret of a provider are set.

## Tests

```bash
pnpm infra:up
pnpm --filter @doro/api test            # unit + integration against real Postgres and S3
pnpm --filter @doro/api test:coverage   # enforces the coverage floors
pnpm --filter @doro/api openapi         # regenerate packages/api-contract/openapi.json
```

The worker and the test suite need `ffmpeg`/`ffprobe` (`apt install ffmpeg`).
