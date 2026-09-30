# Spec: HTTP API

Status: Draft · Last updated: 2026-09-30 · Related: ADR-0006, ADR-0012, [upload-sync.md](upload-sync.md), [sharing.md](sharing.md)

## Authority

Until the API is scaffolded, this document is the contract. **Once `services/api` exists, the generated `packages/api-contract/openapi.json` is authoritative** for request and response shapes. This document then keeps only conventions and the endpoint catalogue, and it must be updated whenever the catalogue changes. CI fails if the committed OpenAPI is stale (ADR-0012).

## Conventions

- Base path `/v1`. Breaking changes need `/v2` for the affected routes. Additive changes are allowed within v1.
- JSON only; `camelCase` fields; timestamps are RFC 3339 UTC strings; IDs are UUID strings.
- **Auth:** session cookie (web) or `Authorization: Bearer <token>` (mobile).
- **Pagination:** cursor-based. `?limit=` (default 50, max 200) and `&cursor=`. The response is `{ items, nextCursor | null }`. Cursors are opaque (base64url of the sort key).
- **Idempotency:** mutating endpoints accept `Idempotency-Key`. The server stores the key and response hash for 24 h and replays the stored response for duplicates.
- **Concurrency:** entity responses carry `version`. Updates may send `If-Match: <version>`, and a mismatch returns `409 conflict.version`.
- **Errors:** `{ "error": { "code": "memory.not_found", "message": "…", "details": {…}?, "requestId": "…" } }`.
- **Media URLs** in responses are presigned and short-lived (`expiresAt` included). Clients must not cache them beyond expiry.
- **Rate limits:** `429` with `Retry-After`.

## Endpoint catalogue

| Method & path | Purpose | Phase | Req |
|---|---|---|---|
| `POST /v1/auth/*` | Better Auth routes (sign-up, sign-in, verify email, reset, sign-out) | P4 | AUTH-001, AUTH-006 |
| `GET /v1/me` | Current user, storage usage | P4 | WEB-005 |
| `GET /v1/me/sessions` · `DELETE /v1/me/sessions/{id}` | Device sessions | P4 | AUTH-004 |
| `POST /v1/me/deletion` · `DELETE /v1/me/deletion` | Request or cancel account deletion | P4 | PRIV-004, WEB-006 |
| `GET /v1/memories` | List own Memories (filters: kind, favorite, trashed) | P4 | WEB-002 |
| `PUT /v1/memories/{id}` | Register Memory (idempotent upsert of immutable fields + initial metadata) | P5 | SYNC-004 |
| `GET /v1/memories/{id}` | Memory detail, asset statuses, rendition URLs | P4 | WEB-003 |
| `PATCH /v1/memories/{id}` | Update caption, favorite, location removal, tags | P4 | MEM-004, MEM-006 |
| `POST /v1/memories/{id}/trash` · `POST /v1/memories/{id}/restore` | Trash and restore | P4 | MEM-007 |
| `POST /v1/memories/{id}/assets/{assetId}/upload` | Create or resume an upload | P5 | SYNC-003 |
| `POST /v1/memories/{id}/assets/{assetId}/upload/complete` | Complete an upload | P5 | SYNC-008 |
| `GET /v1/memories/{id}/assets/{assetId}/download` | Presigned download URL (authorized; sanitized when required) | P5 | WEB-004, PRIV-002 |
| `GET /v1/sync/changes?cursor=` | Change feed with tombstones | P5 (minimal) / Post | SYNC-006 |
| `GET/PUT/DELETE /v1/presets[/{id}]` | Preset sync | Post | WEB-008 |
| `…/v1/albums…` | Albums, members, invites, items (see [sharing.md](sharing.md)) | P9 | SHR-001–SHR-007 |
| `GET /v1/insights/*` | Analytics aggregates | P10 | ANL-001–ANL-005 |
| `GET /healthz` · `GET /readyz` | Health | P4 | NFR-013 |

## Acceptance criteria

- Every endpoint has integration tests for success, validation failure, unauthenticated, and unauthorized (IDOR) cases.
- OpenAPI is generated from the route schemas; the Dart and TS clients are generated from it; CI checks for drift.
