# Research: Uploads, Local Persistence, and Object Storage

Status: Living · Researched: 2026-09-30 · Related: ADR-0008, ADR-0009, ADR-0010, [upload-sync.md](../specs/upload-sync.md)

---

### R-UP-1 — Background transfers in Flutter
- **Source:** `background_downloader` (https://github.com/781flyingdutchman/background_downloader; pub.dev changelog); `flutter_uploader` (https://github.com/fluttercommunity/flutter_uploader).
- **Date:** 2026-09-30
- **Finding:** `background_downloader` supports uploads as well as downloads, using iOS background `URLSession` and Android WorkManager / user-initiated data transfer jobs. Transfers continue when the app is backgrounded or terminated. It is actively maintained. `flutter_uploader` is older and less active.
- **Confidence:** High (features) · unverified under MagicOS battery management
- **Implication:** A suitable transport. Our queue (drift) stays the source of truth, and the plugin is only the transport.
- **Action:** S4 validates per-part PUT uploads, kill/restart, and OEM delays.

### R-UP-2 — iOS background uploads are not resumable per request
- **Source:** Apple Developer Forums thread on background uploads with NSURLSession (https://developer.apple.com/forums/thread/10239); Apple `URLSession` documentation (background sessions require file-based upload tasks).
- **Date:** 2026-09-30
- **Finding:** Background upload tasks must upload from a file. Unlike downloads, there is no built-in resume data for uploads, so an interrupted task restarts from zero.
- **Confidence:** High
- **Implication:** Resumability must be built above the request level.
- **Action:** Use S3 multipart with **one background task per part** and part files sliced on demand ([upload-sync.md](../specs/upload-sync.md)).

### R-UP-3 — S3 multipart constraints
- **Source:** AWS S3 multipart upload documentation (the S3 API is implemented by MinIO, Cloudflare R2, and Backblaze B2).
- **Date:** 2026-09-30
- **Finding:** Parts must be 5 MiB–5 GiB (except the last), with at most 10,000 parts. Parts can be uploaded in any order and retried individually. `ListParts` returns the completed parts. Incomplete uploads should be cleaned up by a lifecycle rule. Presigned URLs work per part (`UploadPart`).
- **Confidence:** High
- **Implication:** Direct-to-storage resumable uploads without routing bytes through the API.
- **Action:** ADR-0008.

### R-UP-4 — Alternative: tus protocol
- **Source:** tus.io resumable upload protocol; tusd server.
- **Date:** 2026-09-30
- **Finding:** tus gives byte-level resumability but requires bytes to flow through a tus server (or tusd with an S3 backend), which is an extra service in the data path.
- **Confidence:** High
- **Implication:** It conflicts with "don't send huge media through the server" and adds infrastructure.
- **Action:** Rejected (recorded in ADR-0008 alternatives).

### R-UP-5 — Object storage providers
- **Source:** Provider pricing and feature pages for Cloudflare R2, AWS S3, and Backblaze B2 (checked 2026-09-30; pricing changes often, so re-check before deciding).
- **Date:** 2026-09-30
- **Finding:** All three support the S3 API, including multipart and presigned URLs. R2 charges **no egress fees**. S3 has the richest ecosystem but charges internet egress. B2 is low-cost with free egress through some CDN partners.
- **Confidence:** Medium (pricing is volatile)
- **Implication:** Original-quality sharing and downloads make egress a major cost driver. R2 is attractive.
- **Action:** An owner decision for production. MinIO is used locally. Code must use only the S3 API features common to all three (no provider-specific SDKs).

### R-UP-6 — Flutter local persistence
- **Source:** pub.dev: `drift`, `sqflite`, `isar`, `hive`/`hive_ce`, `objectbox`.
- **Date:** 2026-09-30
- **Finding:** drift (SQLite) offers typed queries, transactions, reactive streams, and first-class **migration testing**, and it is actively maintained. The original Isar and Hive authors stepped back, and continuity depends on community forks. ObjectBox is fast, but it is a proprietary-core database with a less transparent schema.
- **Confidence:** High
- **Implication:** The upload queue and Memory store need transactions and relational queries. SQLite is the proven durable choice.
- **Action:** drift (ADR-0009). S5 validates durability across kills and reboots.

### R-UP-7 — Job queue on Postgres
- **Source:** pg-boss documentation (uses `SKIP LOCKED`; supports retries, backoff, scheduling, singleton jobs); BullMQ documentation (Redis).
- **Date:** 2026-09-30
- **Finding:** pg-boss provides the features needed for MVP-scale jobs without Redis, and it allows enqueueing inside the same Postgres transaction as a state change (via its `db` option with the transaction's executor).
- **Confidence:** High
- **Implication:** One fewer service, and no dual-write problem between the DB and the queue.
- **Action:** ADR-0010 (owner approved 2026-09-30).
