# ADR-0014: Garage as the local S3-compatible server

Status: Accepted
Date: 2026-09-30
Related: ADR-0008, NFR-013, [uploads-storage.md](../../research/uploads-storage.md), [local-development.md](../../development/local-development.md)

## Context

ADR-0008 named MinIO as the local S3-compatible server. While building the local stack (FND-T-003) we found that MinIO's community edition was archived in 2026 and that its official Docker Hub repositories (`minio/minio`, and `minio/mc`) were deleted. There is no upstream to ship security fixes, and unpinned pulls of the old image name fail. Local development and CI need a maintained S3-compatible server that supports presigned URLs, multipart uploads with `ListParts`, CORS, and lifecycle rules.

## Decision

- Local development and CI use **Garage** (`dxflrs/garage`, pinned to a specific version in `infrastructure/docker-compose.yml`), as a single node with replication factor 1.
- The bucket, dev access key, CORS, and lifecycle rules are created by `tools/local-infra` (`pnpm infra:up`): the Garage CLI for cluster layout, bucket, and key; the **S3 API** for CORS and lifecycle. It never uses the MinIO `mc` client or any provider-specific SDK.
- ADR-0008 stands: production storage is still an owner decision (Cloudflare R2 recommended), and **application code uses only S3 API features that Garage, R2, S3, and B2 share**. Provider differences discovered by tests are recorded in the specs (for example, expired presigned URLs return `400` on Garage and `403` on AWS S3).
- Garage is used only as a separate service. It is AGPL-licensed and we never link or bundle it.

## Alternatives

- **The `pgsty/minio` community fork:** a drop-in replacement, but its long-term maintenance is uncertain, and it still needs an `mc`-style client.
- **SeaweedFS:** more capable and heavier (a 724 MB image), and its S3 lifecycle support is less complete.
- **RustFS:** promising, but young.
- **LocalStack:** heavier, and it now requires an account for some features.

## Consequences

- Local behavior must be verified rather than assumed: `tools/local-infra/test-infra` runs a live protocol test suite (presigned PUT/GET, out-of-order multipart parts, `ListParts`, wrong-ETag completion, abort, expiry, tamper rejection, CORS, lifecycle) against the stack in CI.
- The tests found one Garage-independent SDK pitfall (default flexible checksums break presigned URLs), documented in [upload-sync.md](../../specs/upload-sync.md).
- If Garage becomes unmaintained, swapping the server changes only `infrastructure/` and the bootstrap in `tools/local-infra`.
