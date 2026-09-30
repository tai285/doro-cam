# Spec: Upload and Sync Protocol

Status: Draft (validated by spikes S4, S5) · Last updated: 2026-09-30 · Related: SYNC-001–SYNC-008, NFR-005, ADR-0008, ADR-0009, [sync.md](../architecture/sync.md)

## Purpose

Define the client–server protocol for getting Memories and their media to the cloud exactly once, resumably, with verified integrity.

## Inputs and outputs

- **Input:** a locally committed Memory with assets (file path, bytes, sha256, mime, role).
- **Output:** a server Memory with every uploaded asset in status `verified` or `ready`, and the local asset `upload_state = synced`.

## Protocol

### 1. Register the Memory (idempotent upsert)
`PUT /v1/memories/{memoryId}` with the metadata body. `Idempotency-Key: {memoryId}:register`.
- `201` created or `200` already exists with identical immutable fields.
- `409 memory.conflict` if immutable fields differ (a client bug; logged, surfaced as a permanent failure).

### 2. Create an upload for an asset
`POST /v1/memories/{memoryId}/assets/{assetId}/upload` with `{ role, mime, bytes, sha256 }`.
- Server behavior:
  - If an asset with this `assetId` exists and is `verified`/`ready` → `200 { status: "complete" }` (the client marks it synced).
  - If the owner already has a verified object with the same `sha256` and `bytes` → deduplicate: link the new asset to the existing object, `200 { status: "complete", deduplicated: true }` (SYNC-004).
  - Otherwise create or resume the upload session:
    - `bytes ≤ 16 MiB` → `{ mode: "single", url, headers, expiresAt }` (presigned PUT).
    - `bytes > 16 MiB` → `{ mode: "multipart", uploadId, partSize, parts: [{partNumber, url}], expiresAt }`. `partSize` = max(8 MiB, ceil(bytes/10000)), a multiple of 1 MiB.
  - Repeating this call for an in-progress asset returns the **same** `uploadId` with freshly presigned URLs for the parts that aren't completed yet (the server lists parts via `ListParts`).

### 3. Transfer
- The client PUTs each part (or the single object) directly to storage and stores the returned `ETag` per part in `upload_parts` before moving to the next state.
- Each part is a separate background transfer task. On iOS this requires a **part file** on disk (a byte-range slice written to a temp file just before its task is scheduled, deleted after success). At most 2 part files exist per asset at a time, to bound disk use.
- An expired or otherwise rejected presigned URL triggers a re-call of step 2, which returns fresh URLs. This is not an error. **Providers disagree on the status:** AWS S3 answers `403 AccessDenied` ("Request has expired"), Garage answers `400 InvalidRequest` ("Date is too old"). The client therefore treats **400 and 403 from a presigned URL as "re-presign and retry once"** and only counts a failure toward the permanent-failure limit if a *freshly* presigned URL is also rejected. It also re-requests URLs proactively once `expiresAt` has passed.
- **Presigner requirement:** the server's S3 client must disable the SDK's default flexible checksums (`requestChecksumCalculation: 'WHEN_REQUIRED'`). Otherwise the SDK embeds the CRC32 of an *empty* body in every presigned URL and every real upload is rejected with `InvalidDigest` (found while building the local stack; regression-tested in `tools/local-infra`).

### 4. Complete
`POST /v1/memories/{memoryId}/assets/{assetId}/upload/complete` with `{ uploadId?, parts: [{partNumber, etag}] }`.
- Server: `CompleteMultipartUpload` (multipart) or `HeadObject` (single) → checks `ContentLength == bytes` → in one transaction sets `asset.status = uploaded` and enqueues `asset.verify`.
- Idempotent: completing an already-completed asset returns the current status.

### 5. Verify (server, async)
The worker streams the object and computes SHA-256.
- Match → `verified` (then derived jobs run).
- Mismatch → delete the object, `status = failed (checksum_mismatch)`. The client sees it on its next status poll and restarts from step 2 (at most 3 times, then permanent failure, SYNC-008).

The client polls `GET /v1/memories/{id}` with backoff, or receives the status in pull sync, until all assets are `verified`/`ready`, then marks them synced.

## Invariants

1. The client never marks an asset synced before the server reports `verified` or `ready`.
2. The server never exposes an asset to anyone before `verified`.
3. One `assetId` corresponds to at most one stored object.
4. All mutating endpoints are idempotent under retries.

## Error cases

| Code | HTTP | Client action |
|---|---|---|
| `upload.too_large` | 413 | Permanent failure; show the limit |
| `upload.unsupported_type` | 415 | Permanent failure |
| `upload.quota_exceeded` | 403 | Pause the queue; notify the user |
| `upload.not_found` | 404 | The upload session expired server-side; restart step 2 |
| `upload.size_mismatch` | 422 | Restart step 2 (the object is deleted) |
| `auth.unauthenticated` | 401 | Refresh the session; if that fails, pause the queue and prompt sign-in |
| `rate_limited` | 429 | Back off per `Retry-After` |
| any 5xx / network | — | Exponential backoff with jitter |

## Edge cases

- **App killed mid-part:** on restart, parts without a stored ETag are re-uploaded. Storage overwrites the part number safely.
- **Local file deleted by the OS or user before upload:** permanent failure with a clear status. The Memory remains metadata-only, and this is flagged.
- **Account switch:** the queue is partitioned by account. Uploads never cross accounts.
- **Anonymous captures:** held until sign-in (AUTH-005), then registered to the new account.
- **Stale multipart uploads:** a bucket lifecycle rule aborts incomplete multipart uploads after 7 days. The server treats the session as expired (`upload.not_found`).

## Acceptance criteria

- S4/S5 scenario: a 200 MB motion or video test file uploads through 5 random network drops and 2 app kills. The final object's SHA-256 matches, there is exactly one asset row, and there are no orphan objects after the lifecycle rule runs.
- API integration tests (real Postgres + Garage S3) cover every error code above and every idempotency path.
