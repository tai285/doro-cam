# ADR-0008: S3-compatible storage with direct presigned multipart uploads

Status: Accepted
Date: 2026-09-30
Related: SYNC-003, SYNC-004, SYNC-008, NFR-005, PRIV-003, [upload-sync.md](../../specs/upload-sync.md), [uploads-storage.md](../../research/uploads-storage.md)

## Context

Originals can be tens of MB (photos) to GBs (video). Routing bytes through the API wastes resources and hurts latency. Uploads must be resumable, including iOS background uploads, which can't resume a single request (R-UP-2). The storage provider isn't chosen yet.

## Decision

- Media is stored in **one private S3-compatible bucket**. Locally that's MinIO; production is an owner decision (R2 recommended).
- Clients upload **directly** with presigned URLs issued after authorization: single PUT for ≤ 16 MiB, **S3 multipart with per-part presigned PUTs** above that.
- Object keys are opaque: `o/{ownerId}/{memoryId}/{assetId}/{role}`. Objects are immutable.
- Integrity: a client-declared SHA-256, verified by the worker before an asset becomes visible.
- Downloads use short-lived presigned GETs (≤ 15 min) after authorization.
- Only S3 API features common to MinIO, R2, S3, and B2 are used.

## Alternatives

- **Proxy uploads through Fastify:** simple, but doesn't scale and blocks the API.
- **tus protocol (tusd):** byte-level resume, but an extra service in the data path (R-UP-4).
- **Provider-specific SDK features:** lock-in.

## Consequences

- Clients carry more protocol logic (parts, ETags). This is covered by the spec and tests.
- The API never sees media bytes, so the worker must verify integrity asynchronously.
- A bucket lifecycle rule cleans up abandoned multipart uploads.
