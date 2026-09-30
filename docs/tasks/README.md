# Tasks

Tasks are the unit of implementation work for agents. Each task is small (about 0.5–2 days), independently verifiable, linked to requirements and docs, and ordered by explicit dependencies. The docs checker validates the task format and the dependency graph.

## Task files

| File | Contents |
|---|---|
| [phase-0-foundation.md](phase-0-foundation.md) | P0: repo scaffolds, CI, local infrastructure, spikes S1–S7 |
| [phase-1-camera-core.md](phase-1-camera-core.md) | P1: camera plugin core, capture, local Memory store, minimal library |
| [phase-2-manual-controls.md](phase-2-manual-controls.md) | P2: manual controls, intent resolver, Experiences, presets |
| [backlog.md](backlog.md) | Coarse epics for P3–P13, refined into phase files when each phase starts |

## Format

```markdown
### CAM-T-020 Manual ISO (Android)
- **Status:** todo
- **Platform:** android | ios | dart | api | web | infra | any
- **Depends:** CAM-T-003, EXP-T-001        (or "none")
- **Requirements:** CAM-010
- **Docs:** links to the spec/architecture sections to read
- **Scope:** what to build
- **Out of scope:** what not to build
- **Acceptance:** verifiable criteria
- **Tests:** tests to write
- **Doc updates:** docs that must change on completion
```

- **IDs:** `<AREA>-T-<NNN>`. Areas: `FND` (foundation), `SPK` (spike), `CAM`, `EXP`, `MEM`, `LIB`, and later `PRF`, `API`, `SYNC`, `WEB`, and so on. IDs are never reused.
- **Status:** `todo` · `in-progress` · `blocked (<reason>)` · `done`. The checker requires one of these as the first word.
- **Required fields:** Status, Depends, Requirements, Acceptance. Every ID in `Depends` must exist, and the graph must be acyclic. Every requirement ID must exist in [requirements.md](../product/requirements.md).
- **Platform pairs:** native work is split into `-android` and `-ios` tasks. iOS tasks stay `blocked (needs macOS)` until a Mac is available.

## Picking a task

1. Choose the lowest-numbered `todo` task in the current phase whose `Depends` are all `done`.
2. Set it to `in-progress` in the same change that starts the work.
3. If the task turns out bigger than about 2 days, split it into new IDs, update dependents, and note the split.
4. On completion, set `done` only when all acceptance items are verified. Device-dependent items need an executed device script (see [testing-strategy.md](../development/testing-strategy.md)).
5. Found work outside scope? Add a new `todo` task. Don't do it now.

## Refining a phase

When a phase starts, convert its epic in [backlog.md](backlog.md) into a `phase-N-*.md` file with fine-grained tasks, add it to the table above, and remove or mark the epic as refined.
