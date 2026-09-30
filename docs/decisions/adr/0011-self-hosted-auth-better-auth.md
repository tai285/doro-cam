# ADR-0011: Self-hosted authentication with Better Auth

Status: Accepted
Date: 2026-09-30
Related: AUTH-001–AUTH-006, [security.md](../../architecture/security.md)

## Context

The app needs email/password now, social sign-in later, per-device sessions for mobile, and cookie sessions for the web. The owner chose self-hosted auth in Fastify over a managed provider.

## Decision

- Use **Better Auth**, mounted in the Fastify `auth` module, with its Drizzle adapter on our Postgres.
- Web uses httpOnly session cookies. Mobile uses bearer session tokens stored in secure storage. Each device gets its own session, listable and revocable.
- MVP: email/password with verification and reset. Google and Apple sign-in come later (Apple is required on iOS if any social login is offered).
- Our user-profile data lives in our own tables (`users_profile`), not in library-owned tables.

## Alternatives

- **Managed providers (Clerk, Auth0, Supabase, Firebase):** less code, but per-user cost, vendor lock-in, and user data outside our DB.
- **Hand-rolled auth:** high security risk.
- **Lucia:** deprecated as a library in favor of guidance, so Better Auth is the maintained option.

## Consequences

- We operate auth ourselves: email sending (a transactional email provider is needed, an owner decision at P4), rate limits, and security updates.
- Library upgrades must be tracked. Auth tables are managed by the library's migrations through Drizzle.
