# Phase 2 — Manual Controls, Experiences, Presets

Roadmap: [P2](../product/roadmap.md). Goal: honest, capability-driven manual control and distinct Experiences on one engine (ADR-0003). The resolver comes first because every control depends on it.

### EXP-T-001 CaptureIntent and resolver
- **Status:** todo
- **Platform:** dart
- **Depends:** CAM-T-001
- **Requirements:** EXP-008, CAM-005
- **Docs:** [specs/camera.md](../specs/camera.md) (intent resolution), ADR-0003
- **Scope:** `CaptureIntent` (partial, layered), the layer merge function, and `resolve(intent, caps)` implementing rules 1–6 with the `Adjustment` model.
- **Out of scope:** UI.
- **Acceptance:** the resolver is total and deterministic; the output is always within capabilities.
- **Tests:** table-driven tests for each rule; property-based tests (random intents × random capabilities); 100% branch coverage enforced in CI for this file.
- **Doc updates:** specs/camera.md if the rules are clarified.

### EXP-T-002 Experience definitions
- **Status:** todo
- **Platform:** dart
- **Depends:** EXP-T-001
- **Requirements:** EXP-001, EXP-002, EXP-003, EXP-011
- **Docs:** [camera-ux.md](../design/camera-ux.md), ADR-0003
- **Scope:** data definitions for Mirrorless, Instant, DSLR, and Film (defaults, constraints, token theme ID, workflow flags); a constraint validator hook in the resolver.
- **Out of scope:** skins (EXP-T-007).
- **Acceptance:** each Experience resolves to valid settings against fixture capabilities (limited and full).
- **Tests:** unit tests per Experience × capability fixture.
- **Doc updates:** none.

### EXP-T-003 Assisted scenarios
- **Status:** todo
- **Platform:** dart
- **Depends:** EXP-T-001
- **Requirements:** EXP-004
- **Docs:** [camera-ux.md](../design/camera-ux.md) (beginner vs professional)
- **Scope:** scenario table (Portrait, Street, Landscape, Night, Sunset, Indoor, Bright Day, Film, Instant, Cinema) with recommended ranges and explanation strings; conversion into an intent layer.
- **Out of scope:** scene detection or ML.
- **Acceptance:** each scenario resolves on limited and full fixtures, with explanations that reference applied values.
- **Tests:** unit tests per scenario.
- **Doc updates:** none.

### CAM-T-020 Android: apply exposure (ISO, shutter, EV, AE lock)
- **Status:** todo
- **Platform:** android
- **Depends:** CAM-T-005, EXP-T-001
- **Requirements:** CAM-010, CAM-011, CAM-012, CAM-014, CAM-050
- **Docs:** [specs/camera.md](../specs/camera.md), [camera-apis.md](../research/camera-apis.md)
- **Scope:** apply resolved exposure through Camera2 interop; report applied values from `TotalCaptureResult`; mismatch detection that downgrades the capability after 3 consecutive mismatches.
- **Out of scope:** UI.
- **Acceptance:** on the Honor, for each supported control, applied values track requested values (device script); unsupported controls are never applied.
- **Tests:** JUnit tests for request building and mismatch detection logic.
- **Doc updates:** capability-matrix.md.

### CAM-T-021 Android: focus (tap, continuous, manual, lock)
- **Status:** todo
- **Platform:** android
- **Depends:** CAM-T-020
- **Requirements:** CAM-020, CAM-021, CAM-022
- **Docs:** [specs/camera.md](../specs/camera.md)
- **Scope:** metering-point focus, AF lock, manual focus distance (diopters) when supported, and calibration reporting.
- **Out of scope:** focus peaking.
- **Acceptance:** device script confirms each mode.
- **Tests:** JUnit tests for coordinate transforms (preview → sensor, including rotation and mirroring).
- **Doc updates:** capability-matrix.md.

### CAM-T-022 Android: white balance presets and Kelvin
- **Status:** todo
- **Platform:** android
- **Depends:** CAM-T-020
- **Requirements:** CAM-030, CAM-031
- **Docs:** [specs/camera.md](../specs/camera.md) (Kelvin rule)
- **Scope:** AWB mode presets; Kelvin → RGGB gains conversion when manual post-processing is supported.
- **Out of scope:** tint control.
- **Acceptance:** a grey card under a known light shows the expected shift (device script).
- **Tests:** unit tests for the Kelvin → gains conversion against reference values.
- **Doc updates:** capability-matrix.md.

### CAM-T-023 Android: lens selection and zoom
- **Status:** todo
- **Platform:** android
- **Depends:** CAM-T-020
- **Requirements:** CAM-006, CAM-007, CAM-008
- **Docs:** [specs/camera.md](../specs/camera.md) (edge cases), [capability-matrix.md](../specs/capability-matrix.md)
- **Scope:** physical camera selection where exposed; logical-camera zoom steps otherwise; a digital zoom flag in results.
- **Out of scope:** —
- **Acceptance:** available lenses on the Honor match the S1 findings; the digital zoom label is correct.
- **Tests:** unit tests for lens list construction from fixtures.
- **Doc updates:** capability-matrix.md.

### CAM-T-024 Android: flash, timer, aspect ratio, format
- **Status:** todo
- **Platform:** android
- **Depends:** CAM-T-020
- **Requirements:** CAM-040, CAM-041, CAM-044, CAM-046
- **Docs:** [specs/camera.md](../specs/camera.md), [media.md](../specs/media.md)
- **Scope:** flash and torch modes; timer (Dart-side countdown, native capture); aspect ratio as crop metadata; format choice.
- **Out of scope:** —
- **Acceptance:** device script.
- **Tests:** Dart timer tests with a fake clock; crop metadata tests.
- **Doc updates:** none.

### EXP-T-004 Manual controls UI from capabilities
- **Status:** todo
- **Platform:** dart
- **Depends:** EXP-T-001, CAM-T-007
- **Requirements:** EXP-005, CAM-005, CAM-042
- **Docs:** [camera-ux.md](../design/camera-ux.md), [ux-principles.md](../design/ux-principles.md)
- **Scope:** control strip and dials rendered only for supported capabilities; the "not available" sheet; adjustment notices; grid overlay; accessibility labels and actions.
- **Out of scope:** Experience skins.
- **Acceptance:** matches camera-ux.md for each capability fixture.
- **Tests:** widget tests per capability permutation (full, limited, no manual sensor, single lens); semantics tests.
- **Doc updates:** none.

### EXP-T-005 Local presets
- **Status:** todo
- **Platform:** dart
- **Depends:** EXP-T-001, MEM-T-001
- **Requirements:** EXP-006, EXP-007
- **Docs:** [memory-domain.md](../specs/memory-domain.md) (Preset)
- **Scope:** a drift `presets` table (migration v2 with a migration test); save the current merged intent; list, apply, rename, and delete.
- **Out of scope:** server sync.
- **Acceptance:** a preset re-applies identically after a restart; a preset referencing unsupported values resolves with adjustments.
- **Tests:** DAO, migration, and use-case tests.
- **Doc updates:** sync.md (local schema).

### EXP-T-006 Experience picker and skins
- **Status:** todo
- **Platform:** dart
- **Depends:** EXP-T-002, EXP-T-004
- **Requirements:** EXP-001, EXP-002, EXP-010, EXP-011
- **Docs:** [camera-ux.md](../design/camera-ux.md)
- **Scope:** Experience switcher; token override themes; the Instant develop animation (presentation only); the last Experience is restored.
- **Out of scope:** Film roll constraint (EXP-009).
- **Acceptance:** four Experiences selectable; Mirrorless and Instant fully styled.
- **Tests:** widget and golden tests per Experience.
- **Doc updates:** ux-principles.md if tokens are finalized.

### CAM-T-030 iOS: apply exposure, focus, WB, lens
- **Status:** blocked (needs macOS)
- **Platform:** ios
- **Depends:** CAM-T-015, EXP-T-001
- **Requirements:** CAM-010, CAM-011, CAM-012, CAM-014, CAM-020, CAM-021, CAM-022, CAM-030, CAM-031, CAM-006
- **Docs:** [specs/camera.md](../specs/camera.md)
- **Scope:** the Swift equivalents of CAM-T-020 to CAM-T-024. Split into smaller tasks when unblocked.
- **Out of scope:** —
- **Acceptance:** device script on the iPhone 12 Pro Max.
- **Tests:** XCTest for conversions and the mismatch logic.
- **Doc updates:** capability-matrix.md.
