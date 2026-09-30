# Architecture Decision Records

ADRs record significant, hard-to-reverse decisions: why they were made, what was rejected, and the consequences. Trivial choices (a lint rule, a helper library within an ADR's scope) don't get ADRs.

## Process

1. Copy [0000-template.md](0000-template.md) to `NNNN-kebab-title.md` using the next number.
2. Set `Status: Proposed`. Agents may **propose** ADRs, but only the owner accepts them.
3. When accepted, update the status and the affected architecture and spec docs in the same change.
4. ADRs are immutable once accepted, except for the status line. To change a decision, write a new ADR and set the old one to `Superseded by ADR-NNNN`. If the new ADR changes only part of an old one, keep the old one `Accepted` and append `(amended by ADR-NNNN: summary)` to its status line. Readers must then read both.
5. The docs checker enforces required sections and that every referenced ADR exists.

Statuses: `Proposed` · `Accepted` · `Superseded by ADR-NNNN` · `Deprecated`

## Index

| ADR | Title | Status |
|---|---|---|
| [ADR-0001](0001-flutter-with-first-party-camera-plugin.md) | Flutter app with a first-party native camera plugin | Accepted (amended by ADR-0013) |
| [ADR-0002](0002-runtime-camera-capability-model.md) | Runtime, per-physical-camera capability model | Accepted |
| [ADR-0003](0003-layered-capture-intent.md) | One camera engine; modes as layered capture intent | Accepted |
| [ADR-0004](0004-non-destructive-lut-based-profiles.md) | Non-destructive, LUT-based image profiles | Accepted |
| [ADR-0005](0005-platform-neutral-motion-memory.md) | Platform-neutral Motion Memory representation | Accepted (validated by S3) |
| [ADR-0006](0006-modular-monolith-backend.md) | Fastify modular monolith with a separate worker process | Accepted |
| [ADR-0007](0007-postgresql-with-drizzle.md) | PostgreSQL with Drizzle ORM | Accepted |
| [ADR-0008](0008-direct-presigned-multipart-uploads.md) | S3-compatible storage with direct presigned multipart uploads | Accepted (amended by ADR-0014) |
| [ADR-0009](0009-offline-first-local-source-of-truth.md) | Offline-first: drift as local source of truth, idempotent sync | Accepted |
| [ADR-0010](0010-pg-boss-job-queue.md) | Background jobs with pg-boss on PostgreSQL | Accepted |
| [ADR-0011](0011-self-hosted-auth-better-auth.md) | Self-hosted authentication with Better Auth | Accepted |
| [ADR-0012](0012-monorepo-and-contract-generation.md) | Polyglot monorepo and OpenAPI contract generation | Accepted |
| [ADR-0013](0013-emulator-simulator-and-cloud-macos-verification.md) | Verification on emulators, simulators and cloud macOS | Accepted |
| [ADR-0014](0014-garage-for-local-s3.md) | Garage as the local S3-compatible server | Accepted |
| [ADR-0015](0015-ios-plugin-swiftpm-only-with-flutter-free-core.md) | iOS camera plugin is SwiftPM-only with a Flutter-free core package | Accepted |
