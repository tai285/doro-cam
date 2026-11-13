# ADR-0016: Local WSL verification, no CI/CD

Status: Accepted (supersedes the CI and cloud-macOS parts of ADR-0013)
Date: 2026-11-13
Related: ADR-0013, ADR-0015

## Context

ADR-0013 verified work through GitHub Actions, including a cloud macOS job for iOS. Pipelines slowed delivery (an iOS run took about 9 minutes) and the owner develops on Windows, where path, shell and line-ending differences caused avoidable failures.

## Decision

- All GitHub Actions workflows and Dependabot configuration are removed. No push or pull-request pipeline exists.
- One exception, added the same day at the owner's request: `.github/workflows/ios.yml` runs on GitHub-hosted cloud macOS (free for this public repository) and is **manual dispatch only** (`bash scripts/ios-ci.sh`). It is the only way to build and test iOS, and it is never triggered automatically.
- Every test suite (unit, integration, Playwright e2e, Android Emulator) runs locally inside WSL2 Ubuntu, never in the Windows environment. The Windows tree is mirrored into WSL with `scripts/wsl-sync.sh`.
- The Android Emulator runs in WSL with KVM. Docker runs inside WSL.
- iOS code is verified only by manual runs of that cloud macOS workflow (Swift core tests, build, iOS Simulator tests with the synthetic camera). Until a run has passed for a change, its iOS part is recorded as unverified in `docs/development/field-verification.md`.
- Coverage gates, traceability and docs checks remain, but are run locally.

## Consequences

- Faster feedback and one reproducible environment.
- No automatic protection on `main`; discipline is local: run the suites before every push.
- iOS parity is unverified until a Mac or a runner is available again.

## Alternatives

- Keep GitHub Actions for everything: rejected, too slow and noisy for a solo owner.
- Keep only the iOS cloud job: rejected by the owner; iOS stays unverified instead.
- Run tests natively on Windows: rejected, Windows environment issues.
