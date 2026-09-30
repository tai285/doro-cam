# Doro Cam

> Capture the image. Preserve the moment. Keep the memory.

Doro Cam is a photography and memory platform. It combines a Flutter camera app with honest professional controls and original film-inspired profiles, optional Motion Memories (photo + motion + sound), offline-first capture, original-quality cloud storage and sharing, a React web library, and personal photography insights.

## Status

**Phase 0 (foundations) nearly done.** Done and green in CI: the docs and traceability checkers, the pnpm workspace, the local Postgres + S3 stack, the API and worker skeleton, the web app shell, the Flutter app shell, the native camera plugin bridge (Dart to Kotlin and Swift, verified on the Android Emulator and the iOS Simulator), the emulator and cloud-macOS pipelines, and the coverage gate. Remaining: the technical spikes S1-S7. See the [roadmap](docs/product/roadmap.md) and [tasks](docs/tasks/README.md).

Everything is built with a full automated test suite and verified on the Android Emulator and the iOS Simulator (via cloud macOS CI). No physical device or local Mac is required ([ADR-0013](docs/decisions/adr/0013-emulator-simulator-and-cloud-macos-verification.md)).

## Where to start

| You are… | Start at |
|---|---|
| A coding agent | [AGENTS.md](AGENTS.md) |
| New to the project | [docs/product/vision.md](docs/product/vision.md), then [docs/architecture/overview.md](docs/architecture/overview.md) |
| Looking for any document | [docs/README.md](docs/README.md) |
| Picking up work | [docs/tasks/README.md](docs/tasks/README.md) |

## Stack (planned)

- Flutter/Dart mobile, with first-party native camera plugin code (Kotlin/CameraX, Swift/AVFoundation)
- React + TypeScript + Vite web
- Fastify + TypeScript modular monolith with a pg-boss worker
- PostgreSQL + Drizzle
- S3-compatible object storage
- Docker Compose for local development; GitHub Actions for CI

Rationale for each choice: [docs/decisions/adr/](docs/decisions/adr/README.md).

## Repository checks

```sh
pnpm test           # tests for all TypeScript packages
pnpm check:docs     # documentation integrity (links, requirement IDs, ADRs, task graph)
```
