# CLAUDE.md

@AGENTS.md

## Claude Code specifics

`AGENTS.md` (imported above) is the canonical instruction set. This file adds only Claude Code–specific guidance. Do not duplicate project rules here.

- **Plan before multi-module work.** For any task touching more than one module or layer, or any native camera code, use plan mode (or write the plan in chat) and list files, tests, and doc updates before editing.
- **Subagents.** Use an Explore subagent for broad searches across the repo. Do not delegate decisions that the ADRs govern.
- **Nested instructions.** Directories such as `apps/mobile/`, `services/api/`, and `packages/doro_camera/` get their own `AGENTS.md` once scaffolded. When working there, read that file too.
- **Verification.** Before reporting completion, run the commands in AGENTS.md §8 plus the package-level test commands, and paste the actual result summary into your report.
- **Device-only behavior.** You cannot operate the owner's phones. For behavior that needs a real device, provide an exact manual test script and mark the acceptance item as *pending device verification*.
- **Windows host.** The shell may be PowerShell or Git Bash. Prefer commands that work in both, and keep generated files LF.
