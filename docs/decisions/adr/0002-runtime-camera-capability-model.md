# ADR-0002: Runtime, per-physical-camera capability model

Status: Accepted
Date: 2026-09-30
Related: CAM-004, CAM-005, CAM-013, CAM-050, [specs/camera.md](../../specs/camera.md), [capability-matrix.md](../../specs/capability-matrix.md)

## Context

Camera capabilities differ by platform, OEM, model, lens, and even the selected format. The product promise is to never fake hardware controls. Boolean flags such as `supportsManualISO` lose the information the UI needs (ranges, steps), and hardcoded model tables go stale.

## Decision

- Capabilities are **probed at runtime** from platform APIs, **per physical camera** (and re-probed when the format changes).
- They are expressed as **ranges, steps, and sets** (e.g. `iso: IntRange?`). Booleans are derived.
- The UI renders controls **only** from capabilities.
- After capture, applied values from result metadata are compared with requested values. Persistent mismatches downgrade the capability for the session.
- Device quirks discovered in testing go into a small, documented, tested quirks table and into the capability matrix. They are never hardcoded ad hoc in UI code.
- Aperture is modeled as a list of available f-numbers. With one entry, it is display-only.

## Alternatives

- **Boolean capability flags:** insufficient for dials and clamping.
- **Model allow-lists:** don't scale and go stale; they can't cover every OEM.
- **Always show controls and hope they work:** violates the honesty principle.

## Consequences

- The UI has to handle many permutations. Widget tests must cover them.
- The resolver (ADR-0003) needs capabilities as input, which keeps it pure and testable.
- Honest behavior on limited devices may mean fewer controls there. That is intended.
