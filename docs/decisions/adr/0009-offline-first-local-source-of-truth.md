# ADR-0009: Offline-first — drift as local source of truth, idempotent sync

Status: Accepted
Date: 2026-09-30
Related: NFR-001, NFR-002, SYNC-001–SYNC-008, [sync.md](../../architecture/sync.md), [uploads-storage.md](../../research/uploads-storage.md)

## Context

Capture must never depend on connectivity, and uploads must survive kills, restarts, and flaky networks during travel. The system must never duplicate or lose Memories.

## Decision

- **drift (SQLite, WAL mode)** is the device's source of truth for Memories, assets, presets, and queues. The UI reads only from it.
- Memory and asset IDs are **client-generated UUIDv7**.
- Media files are written atomically (temp → fsync → rename) **before** the DB transaction that references them commits.
- Uploads use a persisted per-asset **state machine**. Metadata edits go through a transactional **outbox**.
- The server is idempotent (client IDs, `Idempotency-Key`). Pull sync uses a monotonic server `change_seq` cursor.
- Conflict policy: media is immutable; metadata uses field-level last-writer-wins by server order; delete wins over edit.

## Alternatives

- **Isar / Hive / ObjectBox:** maintenance concerns or weaker relational and transactional support (R-UP-6).
- **Server-first with a cache:** fails the offline requirement.
- **CRDTs:** unnecessary complexity for single-owner metadata with simple fields.

## Consequences

- Migration discipline is needed for the local DB (tested migrations).
- Field-level LWW can drop a concurrent edit to the same field on two devices. That's acceptable for captions and favorites.
- S5 validates durability.
