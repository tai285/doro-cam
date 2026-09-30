# ADR-0006: Fastify modular monolith with a separate worker process

Status: Accepted
Date: 2026-09-30
Related: NFR-013, [backend.md](../../architecture/backend.md)

## Context

A solo developer needs a backend that is simple to run and change, yet can scale later. The heavy work (media processing) has a different resource profile from request handling.

## Decision

- One TypeScript codebase (`services/api`) using **Fastify**, organized as **modules** (auth, users, memories, assets, albums, presets, analytics, sync), each owning its routes, service, repository, and tables.
- Modules interact only through each other's services. There are no cross-module table access and no circular dependencies (lint-enforced).
- Two processes from the same image: the **API** and the **worker**.
- No microservices. Splitting any module into a separate deployable requires a new ADR with measured justification.

## Alternatives

- **Microservices:** operational overhead with no benefit at this scale.
- **Single process doing jobs in-process:** media processing would degrade API latency (S6).
- **NestJS / Express:** Fastify has better performance, first-class schema validation and serialization, and the owner chose it.

## Consequences

- Simple deployment: one image, two commands.
- Module boundaries need discipline, supported by lint rules and review.
- The worker can scale independently when needed.
