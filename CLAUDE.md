# CLAUDE.md

@AGENTS.md

## Claude Code specifics

`AGENTS.md` (imported above) is the canonical instruction set. This file adds only Claude Code–specific guidance. Do not duplicate project rules here.

- **Plan before multi-module work.** For any task touching more than one module or layer, or any native camera code, use plan mode (or write the plan in chat) and list files, tests, and doc updates before editing.
- **Subagents.** Use an Explore subagent for broad searches across the repo. Do not delegate decisions that the ADRs govern.
- **Nested instructions.** Directories such as `apps/mobile/`, `services/api/`, and `packages/doro_camera/` get their own `AGENTS.md` once scaffolded. When working there, read that file too.
- **Verification.** Before reporting completion, run the commands in AGENTS.md §8 plus the package-level test commands, and paste the actual result summary into your report.
- **No CI/CD (owner decision, 2026-11-13).** No push or pull-request pipeline exists; everything is verified locally. The one exception is the manual-dispatch `ios.yml` for cloud macOS (ADR-0016).
- **Tests run in WSL (Ubuntu), not Windows.** Run every test suite (unit, integration, Playwright e2e, Android emulator) inside WSL so there are no Windows environment issues. Use `wsl -e bash -lc '...'` from the Windows shell. The working tree lives on Windows, so a WSL-side clone or sync may be used for speed; the Windows tree remains the source of truth that gets committed.
- **Emulators, not phones.** You cannot operate the owner's phones. Verify Android behavior on the Android Emulator (KVM is available in WSL). iOS is built and tested only on GitHub's cloud macOS through the manual-dispatch workflow `ios.yml` (`bash scripts/ios-ci.sh`, then `gh run view --log-failed`); until a run passes, record the iOS part as unverified in `docs/development/field-verification.md`.
- **Standing permission to commit and push (owner decision, 2026-11-13).** In this repo, commit small logical changes and push to `main` without asking. Conventional Commits, lowercase, ≤72 chars. The owner is the sole author and contributor: no `Co-Authored-By`, no "Generated with", no AI attribution anywhere.
- **Tests for everything.** Write tests before or with the code. Run them and quote the real results. Never weaken a test to get green.
- **Autonomy.** Do the work end to end, including installing tooling in WSL. Do not ask the owner to run commands.
