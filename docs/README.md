# Documentation Index

This is the map of all project documentation. Every document has exactly one purpose. If you need to add a document, add it here with its purpose. The docs checker fails when a document is unreachable from this index.

## Authority and conflicts

- **What to build:** [product/requirements.md](product/requirements.md) is authoritative. Requirements change only with owner approval.
- **How to build:** accepted ADR > spec > architecture doc > research note.
- **What is built:** the code and its tests. Docs describing unbuilt things must say *planned*.
- **Conflicts:** stop and report. Never resolve a contradiction silently. Fix the losing document in the same change once the owner decides.

Document header convention for important docs:

```
Status: Draft | Accepted | Living | Superseded
Last updated: YYYY-MM-DD
Related: requirement IDs, ADR IDs
```

## Product — what and why

| Doc | Purpose |
|---|---|
| [product/vision.md](product/vision.md) | Vision, philosophy, users, problems, goals, non-goals, success criteria |
| [product/requirements.md](product/requirements.md) | All functional and non-functional requirements with stable IDs, MVP tags, and core journeys |
| [product/roadmap.md](product/roadmap.md) | Phases, dependencies, deliverables, risks, acceptance, and **status** |

## Architecture — how the system is structured

| Doc | Purpose |
|---|---|
| [architecture/overview.md](architecture/overview.md) | System context, containers, ownership boundaries, tech stack, scalability path |
| [architecture/mobile.md](architecture/mobile.md) | Flutter app layering, state management, feature layout, native bridge boundary |
| [architecture/camera.md](architecture/camera.md) | Camera engine: sessions, capabilities, intent resolution, preview and capture pipelines |
| [architecture/media-pipeline.md](architecture/media-pipeline.md) | Asset roles, derivatives, on-device vs worker processing, video and motion handling |
| [architecture/sync.md](architecture/sync.md) | Offline-first model, local DB, upload queue state machine, reconciliation |
| [architecture/backend.md](architecture/backend.md) | Fastify modular monolith, module rules, worker and jobs, errors, logging |
| [architecture/security.md](architecture/security.md) | Authentication, authorization, media access, privacy (location), deletion, secrets, rate limits |

## Specs — exact contracts

| Doc | Purpose |
|---|---|
| [specs/memory-domain.md](specs/memory-domain.md) | The domain model: Memory, Asset, Album, Preset, Profile; invariants and lifecycles |
| [specs/camera.md](specs/camera.md) | Camera platform interface, capability contract, intent resolution rules, errors |
| [specs/capability-matrix.md](specs/capability-matrix.md) | Per-platform and per-device capability support, API-level vs verified |
| [specs/image-profile.md](specs/image-profile.md) | Profile schema, LUT compilation, effects, versioning, parity tolerance |
| [specs/media.md](specs/media.md) | Media formats, Motion Memory manifest, naming, metadata embedding, limits |
| [specs/upload-sync.md](specs/upload-sync.md) | Upload protocol, idempotency, retries, dedupe, sync endpoints |
| [specs/sharing.md](specs/sharing.md) | Albums, trips, membership roles, permission rules |
| [specs/api.md](specs/api.md) | HTTP API conventions and endpoint catalogue |
| [specs/database.md](specs/database.md) | PostgreSQL schema, indexes, constraints, migration policy |

## Design — how it should feel

| Doc | Purpose |
|---|---|
| [design/ux-principles.md](design/ux-principles.md) | UX principles, visual system approach, accessibility, responsive web |
| [design/camera-ux.md](design/camera-ux.md) | Camera Experiences, control organization, beginner vs pro, LIVE behavior |

## Development — how to work

| Doc | Purpose |
|---|---|
| [development/development-guide.md](development/development-guide.md) | Repo structure, conventions, dependency policy, Definition of Done, doc rules |
| [development/testing-strategy.md](development/testing-strategy.md) | What to test where, CI vs real-device testing |
| [development/local-development.md](development/local-development.md) | Local setup (Windows-first), Docker Compose, commands |

## Research — evidence and open questions

| Doc | Purpose |
|---|---|
| [research/camera-apis.md](research/camera-apis.md) | Flutter, CameraX/Camera2, and AVFoundation capabilities and limits |
| [research/motion-capture.md](research/motion-capture.md) | Live Photo / Motion Photo research, buffering, A/V sync |
| [research/image-processing.md](research/image-processing.md) | Real-time grading, LUTs, capture rendering, server-side processing |
| [research/uploads-storage.md](research/uploads-storage.md) | Background uploads, resumability, object storage providers, local persistence |
| [research/spikes.md](research/spikes.md) | Technical spike definitions (S1–S7) and results |

## Decisions and work

| Doc | Purpose |
|---|---|
| [decisions/adr/README.md](decisions/adr/README.md) | ADR index and process |
| [tasks/README.md](tasks/README.md) | Task format, statuses, and index of task files |
