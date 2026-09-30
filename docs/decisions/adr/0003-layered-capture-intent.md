# ADR-0003: One camera engine; modes as layered capture intent

Status: Accepted
Date: 2026-09-30
Related: EXP-001–EXP-008, [architecture/camera.md](../../architecture/camera.md), [camera-ux.md](../../design/camera-ux.md)

## Context

The product has Experiences (Mirrorless, DSLR, Film, Instant) and modes (Assisted, Manual, Preset, Custom). Implementing each as a separate camera would multiply code and bugs, and users expect to move fluidly between them (e.g. start from a scenario and tweak ISO).

## Decision

- There is **one** camera engine and session.
- Settings come from **layers** merged field by field in a fixed order: Experience defaults → source layer (Scenario recommendation or Preset) → user manual overrides → `CaptureIntent`.
- A pure Dart function `resolve(intent, capabilities)` produces `ResolvedCaptureSettings` plus a list of explained adjustments, then applies Experience constraints.
- "Custom mode" is saving the merged intent as a Preset.
- An Experience is data plus a UI skin: defaults, optional constraints, a token theme, and a workflow flags set. It is not a separate implementation.

## Alternatives

- **Separate screens and controllers per mode:** duplicated logic, and inconsistent behavior.
- **A single flat settings object with mode flags:** loses provenance, so the UI can't explain "this came from the Night scenario".

## Consequences

- The resolver becomes the most important pure unit. It requires 100% branch coverage and property tests.
- Adding a scenario or Experience is mostly data.
- Experience UIs must be built from shared components with token overrides, which constrains how exotic each skin can be. This is acceptable.
