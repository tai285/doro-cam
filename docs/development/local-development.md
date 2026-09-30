# Local Development

Status: Living (partially planned) · Last updated: 2026-09-30 · Related: ADR-0012

## Available now

| Tool | Version (verified 2026-09-30) | Used for |
|---|---|---|
| Git | 2.52 | Version control |
| Node.js | 24.12 | Repo tooling (`tools/docs-check`), later API and web |
| GitHub CLI | 2.102 | Repo and CI operations |
| Docker Desktop | installed | Local Postgres and MinIO (planned) |

```sh
npm install          # installs tooling devDependencies (typescript, @types/node)
npm test             # tooling tests (node:test)
npm run typecheck    # tsc --noEmit for tooling
npm run check:docs   # documentation integrity
```

## Planned (added by P0 scaffolding tasks)

| Tool | Needed for | Task |
|---|---|---|
| pnpm (via Corepack) | TS workspaces | FND-T-001 |
| Flutter SDK (stable) + Android Studio / SDK + JDK 17 | Mobile app and plugin | FND-T-004 |
| Xcode (macOS only) | iOS builds | blocked: needs macOS |

### Planned services (`infrastructure/docker-compose.yml`, FND-T-003)

| Service | Port | Purpose |
|---|---|---|
| postgres | 5432 | Metadata + pg-boss |
| minio | 9000 (S3), 9001 (console) | S3-compatible storage |
| minio-init | — | Creates the bucket, CORS, and lifecycle rule (abort incomplete multipart after 7 days) |

### Planned commands

```sh
docker compose -f infrastructure/docker-compose.yml up -d
pnpm --filter api dev          # API on :3000
pnpm --filter api worker:dev   # worker
pnpm --filter web dev          # web on :5173
cd apps/mobile && flutter run  # on a connected Android device
```

Physical Android device over USB: enable Developer options → USB debugging. For MagicOS, also disable "Install via USB" verification prompts as needed. The phone reaches the local API via `adb reverse tcp:3000 tcp:3000` and `adb reverse tcp:9000 tcp:9000`.

## Windows notes

- Keep LF line endings. `.gitattributes` enforces this, and `core.autocrlf=false` is set in the repo.
- Avoid path-length issues: keep the repo near the drive root if Gradle complains, or enable long paths (`git config core.longpaths true`).
- Commands in docs are POSIX. PowerShell equivalents are given where they differ.
