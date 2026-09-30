# ADR-0010: Background jobs with pg-boss on PostgreSQL

Status: Accepted
Date: 2026-09-30
Related: ADR-0006, ADR-0007, [backend.md](../../architecture/backend.md), [uploads-storage.md](../../research/uploads-storage.md)

## Context

The original proposal included Redis and a job queue. At MVP scale the job volume is small (a few jobs per upload), and a solo developer benefits from fewer services. Jobs must not be lost when the triggering DB change commits (the dual-write problem).

## Decision

- Use **pg-boss** on the primary PostgreSQL database for all background jobs.
- Jobs are **enqueued inside the same transaction** as the state change that triggers them.
- Job handlers are idempotent and keyed by entity ID (singleton keys where appropriate).
- **No Redis in the MVP.** Rate limiting starts in memory (single instance).
- The owner approved this on 2026-09-30.

## Alternatives

- **BullMQ on Redis:** a mature, high-throughput option, but it adds a service and requires an outbox to avoid dual writes.
- **In-process async tasks:** lost on crash; degrade API latency.

## Consequences

- One fewer container locally and in production.
- Job throughput is bounded by Postgres. That's fine for MVP and early growth. Revisit (new ADR) if measured job latency or DB load becomes a problem, or when multi-instance rate limiting or caching needs Redis anyway.
