# Doro Cam

> Capture the image. Preserve the moment. Keep the memory.

Doro Cam is a photography and memory platform. It combines a Flutter camera app with honest professional controls and original film-inspired profiles, optional Motion Memories (photo + motion + sound), offline-first capture, original-quality cloud storage and sharing, a React web library, and personal photography insights.

## Status

**The full product is being built.** Built and tested locally in WSL: the Fastify API and pg-boss worker (accounts, sessions, memories, resumable verified uploads, sync feed, presets, albums and sharing with location privacy, insights and preset suggestions, account deletion; committed OpenAPI contract), and the React dashboard (sign-in, library, memory detail with motion playback, albums, insights, presets, account). The camera app (Flutter, with a first-party Kotlin and Swift camera plugin) is built alongside them. See the [roadmap](docs/product/roadmap.md) and [tasks](docs/tasks/README.md).

Everything is built with a full automated test suite. Tests run locally in WSL (no CI on push); Android is verified on the Android Emulator, and iOS on GitHub-hosted cloud macOS through a manually dispatched workflow. No physical device or local Mac is required ([ADR-0013](docs/decisions/adr/0013-emulator-simulator-and-cloud-macos-verification.md), [ADR-0016](docs/decisions/adr/0016-local-wsl-verification-no-ci.md)).

## Where to start

| You are… | Start at |
|---|---|
| A coding agent | [AGENTS.md](AGENTS.md) |
| New to the project | [docs/product/vision.md](docs/product/vision.md), then [docs/architecture/overview.md](docs/architecture/overview.md) |
| Looking for any document | [docs/README.md](docs/README.md) |
| Picking up work | [docs/tasks/README.md](docs/tasks/README.md) |

## Stack

- Flutter/Dart mobile, with first-party native camera plugin code (Kotlin/CameraX, Swift/AVFoundation)
- React + TypeScript + Vite web
- Fastify + TypeScript modular monolith with a pg-boss worker
- PostgreSQL + Drizzle
- S3-compatible object storage
- Docker Compose for local development; tests run locally in WSL; one manually dispatched GitHub Actions workflow builds iOS on cloud macOS

Rationale for each choice: [docs/decisions/adr/](docs/decisions/adr/README.md).

## Repository checks

```sh
pnpm test           # tests for all TypeScript packages
pnpm check:docs     # documentation integrity (links, requirement IDs, ADRs, task graph)
```
