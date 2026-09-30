# Security and Privacy

Status: Accepted · Last updated: 2026-09-30 · Related: ADR-0008, ADR-0011, AUTH-001–AUTH-006, PRIV-001–PRIV-006, SHR-003, SHR-005, SHR-006, NFR-008, NFR-011

## Authentication (ADR-0011)

- **Better Auth**, self-hosted inside the Fastify `auth` module, with users and sessions in Postgres.
- MVP: email and password with email verification and password reset (AUTH-001, AUTH-006). Google and Apple sign-in are Post (AUTH-002, AUTH-003).
- **Web:** httpOnly, Secure, SameSite=Lax session cookie. CSRF protection is on for state-changing requests.
- **Mobile:** bearer session token stored in platform secure storage (Keychain / Android Keystore via `flutter_secure_storage`). Each device has its own session, which is listable and revocable (AUTH-004).
- Password hashing uses Better Auth's default (scrypt), with rate-limited login and reset endpoints.
- The camera and library work without an account (AUTH-005). Signing in later attaches local Memories to the account on first upload.

## Authorization

The server enforces all authorization in the service layer (`assertCan`). The client UI is never trusted.

**Memory access:**
- The **owner** has full access.
- A **member of an album containing the Memory** has access according to their album role (P9).
- Anyone else gets `404`, not `403`, so existence isn't revealed.

**Album role matrix (P9, [sharing.md](../specs/sharing.md)):**

| Action | Owner | Editor | Contributor | Viewer |
|---|---|---|---|---|
| View album and Memories | ✓ | ✓ | ✓ | ✓ |
| Download originals (if album allows, SHR-005) | ✓ | ✓ | ✓ | ✓ |
| Add own Memories | ✓ | ✓ | ✓ | ✗ |
| Remove own Memories from album | ✓ | ✓ | ✓ | ✗ |
| Remove others' Memories from album | ✓ | ✓ | ✗ | ✗ |
| Edit album title, dates, settings | ✓ | ✓ | ✗ | ✗ |
| Invite and remove members, change roles | ✓ | ✗ | ✗ | ✗ |
| Delete album | ✓ | ✗ | ✗ | ✗ |

Removing a Memory from an album never deletes the Memory; only its owner can delete it.

## Media access

- The bucket is **private**, with no public ACLs and no listing.
- Object keys are opaque: `o/{ownerId}/{memoryId}/{assetId}/{role}` built from UUIDs. They are never used as authorization.
- **Downloads:** the client asks the API for an asset URL. The API authorizes, then returns a presigned GET valid for **≤ 15 minutes**, with `response-content-disposition` for downloads.
- **Uploads:** presigned PUTs are scoped to one key, valid for **≤ 1 hour**, with the expected content length where the provider supports it. On completion the server verifies size and checksum (see [upload-sync.md](../specs/upload-sync.md)).
- Presigned URLs are never logged.

## Upload validation

- The declared `mime`, `bytes`, and `sha256` are required when creating an upload. Limits come from [media.md](../specs/media.md).
- Completion re-checks the stored object size. The worker verifies the checksum and sniffs magic bytes; a mismatch marks the asset `failed` and deletes the object.
- The server never executes or parses media in the API process. Parsing happens only in the worker (ffmpeg, sharp) with resource limits.

## Location privacy

Location is the most sensitive metadata.

1. **Capture:** location capture is off by default (PRIV-001, MEM-003). When enabled, coordinates are stored in the Memory record, and GPS EXIF is written into `photo_original` and `photo_rendered`.
2. **Owner control:** per Memory, the owner can remove location at any time. This clears DB fields. The original file still contains EXIF GPS, so rule 3 applies.
3. **Sharing:** location is visible to album members only if both the album's `share_location` and the Memory's setting allow it (SHR-006). Otherwise:
   - API responses omit location fields (response schemas are role-aware);
   - originals and renditions served to non-owners are **sanitized copies** with GPS removed (`asset.sanitize` job), never the raw original (PRIV-002).
4. Analytics uses coarse location (country or region) only, and only for the owner.
5. Logs never include coordinates.

## Account deletion and export

- Deletion (WEB-006, PRIV-004) needs re-authentication and a 7-day grace period, then the `user.delete` job removes DB rows and all objects. The job is idempotent and resumable. Memories the user contributed to others' albums are deleted with the account; album owners see "removed by owner".
- Export (WEB-010, Post): a worker-built zip is delivered via a presigned URL valid for 24 h.

## Secrets

- Secrets live only in environment variables or the host's secret store. `.env` is git-ignored and `.env.example` has placeholders.
- CI uses GitHub Actions secrets. Workflows run on `pull_request` without secrets from forks.
- S3 credentials used by the API are scoped to the single bucket.

## Rate limiting and abuse

- `@fastify/rate-limit` in memory for the single-instance MVP. When scaling to several instances, move it to Postgres or Redis (ADR needed).
- Stricter limits on auth endpoints and on upload creation.
- Per-user storage accounting enables quotas before any public launch.

## Threat notes (non-exhaustive)

| Threat | Mitigation |
|---|---|
| IDOR on memory or asset IDs | Service-layer `assertCan` on every access; 404 on deny; negative tests required |
| Location leak via EXIF | Sanitized copies for non-owners; role-aware serializers |
| Presigned URL leakage | Short expiry; not logged; download URLs are per-request |
| Upload of malicious files | Size and mime limits; magic-byte check; processing only in the sandboxed worker |
| Session theft on mobile | Secure storage; per-device revocation |
| Dependency supply chain | Dependency policy; lockfiles; Dependabot or Renovate (P0) |
