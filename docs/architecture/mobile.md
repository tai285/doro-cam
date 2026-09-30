# Mobile Architecture (Flutter)

Status: Accepted (planned; not yet scaffolded) · Last updated: 2026-09-30 · Related: ADR-0001, ADR-0003, ADR-0009

## Layers

```
presentation  → widgets, screens, view state (Riverpod Notifiers)
application   → use cases (CaptureMemory, ResolveCaptureIntent, EnqueueUpload…)
domain        → pure Dart entities & rules (Memory, CaptureIntent, CameraCapabilities, Preset)
data          → drift DB, file store, API client (generated), upload transport
platform      → doro_camera plugin (Dart API → Pigeon → Kotlin/Swift)
```

Dependency direction: `presentation → application → domain ← data`. `data` and `platform` implement interfaces declared in `domain` or `application`. `domain` imports nothing from Flutter, drift, HTTP, or the plugin.

## Folder layout (feature-first)

```
apps/mobile/lib/
  main.dart
  app/                  # app shell, router (go_router), theme tokens (ThemeExtension), shared widgets, DI (ProviderScope)
  core/                 # shared utilities: result types, logging, clock, ids (UUIDv7)
  features/
    camera/             # presentation/ application/ domain/
    experiences/
    profiles/
    library/
    memory_detail/
    sync/
    auth/
    settings/
  data/
    db/                 # drift database, tables, DAOs, migrations
    files/              # MediaFileStore (app-private dirs, atomic moves)
    api/                # generated client + thin adapters
    upload/             # upload queue runner, transport adapter
```

Shared domain types used by more than one feature live in `lib/domain/`. A feature never imports another feature's `presentation/`.

## State management

- **Riverpod 3** with hand-written providers (`Provider`, `NotifierProvider`, `AsyncNotifierProvider`); no code generation, so there is no `build_runner` step for providers. Chosen for compile-safe DI and testability without `BuildContext`. Recorded in the overview tech stack; it is not an ADR-level decision.
- Providers expose *immutable* state objects (freezed or plain `final` classes with `==`).
- There is no global mutable singleton. The camera session is owned by a single `CameraSessionController` provider, scoped to the camera route and disposed with it.
- Long-lived services (upload queue runner, DB) are app-scoped providers.

## Native bridge boundary

- The app talks only to `package:doro_camera`'s Dart API (`DoroCamera`, `CameraSession`). It never uses raw `MethodChannel`.
- The plugin's Dart layer has an abstract `CameraPlatform`. The real implementation uses Pigeon-generated host APIs. `FakeCameraPlatform` (in the plugin's `testing/` library) is used by app widget tests.
- Events from native (capture progress, errors, thermal state, device orientation) arrive through Pigeon Flutter APIs or event channels, mapped to typed Dart streams.
- Details: [camera.md](camera.md), contract: [specs/camera.md](../specs/camera.md).

## Local persistence

- **drift (SQLite)** is the source of truth for Memories, assets, presets, settings, and the upload queue (ADR-0009). The choice is backed by [uploads-storage.md](../research/uploads-storage.md).
- Media files live under the app-private documents directory: `media/{memoryId}/{assetId}.{ext}`. Files are written to a temp path, fsynced, then atomically renamed. Only then is the DB row committed (NFR-002).
- Export to the system gallery is an explicit user action (Post-MVP). The app does not depend on the system gallery.

## Navigation

go_router with typed routes: `/camera` (initial), `/library`, `/memory/:id`, `/settings`, `/auth/*`. The camera route stays the app's home. Returning to it must restore the session quickly.

## Error handling

- Domain and application layers return typed results (`Result<T, Failure>`) for expected failures (permission denied, unsupported setting, storage full). Exceptions are reserved for programmer errors.
- Presentation maps failures to user-facing messages defined in one place per feature.

## Testing hooks

- Everything above `platform` is testable on the JVM/Dart VM with fakes.
- See [testing-strategy.md](../development/testing-strategy.md).
