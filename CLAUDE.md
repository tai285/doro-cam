# CLAUDE.md

@AGENTS.md

## Claude Code specifics

`AGENTS.md` (imported above) is the canonical instruction set. This file adds only Claude Code–specific guidance. Do not duplicate project rules here.

- **Plan before multi-module work.** For any task touching more than one module or layer, or any native camera code, use plan mode (or write the plan in chat) and list files, tests, and doc updates before editing.
- **Subagents.** Use an Explore subagent for broad searches across the repo. Do not delegate decisions that the ADRs govern.
- **Nested instructions.** Directories such as `apps/mobile/`, `services/api/`, and `packages/doro_camera/` get their own `AGENTS.md` once scaffolded. When working there, read that file too.
- **Verification.** Before reporting completion, run the commands in AGENTS.md §8 plus the package-level test commands, and paste the actual result summary into your report.
- **Emulators and cloud macOS, not phones.** You cannot operate the owner's phones.
  - Verify Android behavior on the Android Emulator.
  - Verify iOS behavior through the cloud macOS workflow (`gh workflow run ios.yml --ref <branch>`, then `gh run watch` and `gh run view --log-failed`).
  - Log hardware-only aspects in `docs/development/field-verification.md`. Never present them as verified.
- **Tests for everything.** Write tests before or with the code. Run them and quote the real results. Never weaken a test to get green.
- **Windows host.** The shell may be PowerShell or Git Bash. Prefer commands that work in both, and keep generated files LF. Use Bash for `gh ... --jq` (PowerShell splits quoted jq expressions). The repo path contains a space, so quote it.
