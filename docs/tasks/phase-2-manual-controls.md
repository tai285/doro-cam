# Phase 2 — Manual Controls, Experiences, Presets

Roadmap: [P2](../product/roadmap.md). Goal: honest, capability-driven manual control and distinct Experiences on one engine (ADR-0003), on Android and iOS, verified on the emulator and simulator (ADR-0013). The resolver comes first because every control depends on it.

### EXP-T-001 CaptureIntent and resolver
- **Status:** todo
- **Platform:** dart
- **Depends:** CAM-T-001
- **Requirements:** EXP-008, CAM-005
- **Docs:** [specs/camera.md](../specs/camera.md) (intent resolution), ADR-0003
- **Scope:** `CaptureIntent` (partial, layered), the layer merge function, and `resolve(intent, caps)` implementing rules 1–6 with the `Adjustment` model.
- **Out of scope:** UI.
- **Acceptance:** the resolver is total and deterministic; the output is always within capabilities.
- **Tests:** table-driven tests for each rule; property-based tests (random intents × random capabilities); 100% branch coverage enforced by the coverage gate.
- **Doc updates:** specs/camera.md if the rules are clarified.

### EXP-T-002 Experience definitions
- **Status:** todo
- **Platform:** dart
- **Depends:** EXP-T-001
- **Requirements:** EXP-001, EXP-002, EXP-003, EXP-011
- **Docs:** [camera-ux.md](../design/camera-ux.md), ADR-0003
- **Scope:** data definitions for Mirrorless, Instant, DSLR, and Film (defaults, constraints, token theme ID, workflow flags); a constraint validator hook in the resolver.
- **Out of scope:** skins (EXP-T-006).
- **Acceptance:** each Experience resolves to valid settings against fixture capabilities (synthetic, limited, full).
- **Tests:** unit tests per Experience × capability fixture; constraint validator tests (accept and reject).
- **Doc updates:** none.

### EXP-T-003 Assisted scenarios
- **Status:** todo
- **Platform:** dart
- **Depends:** EXP-T-001
- **Requirements:** EXP-004
- **Docs:** [camera-ux.md](../design/camera-ux.md) (beginner vs professional)
- **Scope:** the scenario table (Portrait, Street, Landscape, Night, Sunset, Indoor, Bright Day, Film, Instant, Cinema) with recommended ranges and explanation strings; conversion into an intent layer.
- **Out of scope:** scene detection or ML.
- **Acceptance:** each scenario resolves on limited and full fixtures, with explanations that reference applied values.
- **Tests:** unit tests per scenario × fixture; explanation formatting tests in two locales.
- **Doc updates:** none.

### CAM-T-020 Android: apply exposure (ISO, shutter, EV, AE lock)
- **Status:** todo
- **Platform:** android
- **Depends:** CAM-T-005, EXP-T-001
- **Requirements:** CAM-010, CAM-011, CAM-012, CAM-014, CAM-050
- **Docs:** [specs/camera.md](../specs/camera.md), [camera-apis.md](../research/camera-apis.md)
- **Scope:** apply resolved exposure via Camera2 interop; report applied values from `TotalCaptureResult`; mismatch detection that downgrades the capability after 3 consecutive mismatches.
- **Out of scope:** UI.
- **Acceptance:** on the emulator, applied values track requested values for each supported control (instrumented sweep); unsupported controls are never applied.
- **Tests:** JUnit tests for request building and mismatch detection (using a sink that ignores requests); an instrumented sweep test.
- **Doc updates:** capability-matrix.md.

### CAM-T-021 Android: focus (tap, continuous, manual, lock)
- **Status:** todo
- **Platform:** android
- **Depends:** CAM-T-020
- **Requirements:** CAM-020, CAM-021, CAM-022
- **Docs:** [specs/camera.md](../specs/camera.md)
- **Scope:** metering-point focus, AF lock, manual focus distance (diopters) when supported, and calibration reporting.
- **Out of scope:** focus peaking.
- **Acceptance:** instrumented tests on the emulator confirm the AF mode and focus distance in the capture results for each mode.
- **Tests:** JUnit tests for coordinate transforms (preview → sensor, all rotations, mirroring); instrumented mode tests.
- **Doc updates:** capability-matrix.md.

### CAM-T-022 Android: white balance presets and Kelvin
- **Status:** todo
- **Platform:** android
- **Depends:** CAM-T-020
- **Requirements:** CAM-030, CAM-031
- **Docs:** [specs/camera.md](../specs/camera.md) (Kelvin rule)
- **Scope:** AWB mode presets; Kelvin → RGGB gains conversion when manual post-processing is supported.
- **Out of scope:** tint control.
- **Acceptance:** on the emulator, capture results report the requested AWB mode or gains.
- **Tests:** unit tests for the Kelvin → gains conversion against reference values (100% branch); instrumented tests.
- **Doc updates:** capability-matrix.md.

### CAM-T-023 Android: lens selection and zoom
- **Status:** todo
- **Platform:** android
- **Depends:** CAM-T-020
- **Requirements:** CAM-006, CAM-007, CAM-008
- **Docs:** [specs/camera.md](../specs/camera.md) (edge cases), [capability-matrix.md](../specs/capability-matrix.md)
- **Scope:** physical camera selection where exposed; logical-camera zoom steps otherwise; a digital zoom flag in results.
- **Out of scope:** —
- **Acceptance:** on the emulator (logical camera on API 30+), lens switching and zoom steps work; the digital zoom flag is correct.
- **Tests:** unit tests for lens list construction from fixtures; instrumented switching tests.
- **Doc updates:** capability-matrix.md.

### CAM-T-024 Android: flash, timer, aspect ratio, format
- **Status:** todo
- **Platform:** android
- **Depends:** CAM-T-020
- **Requirements:** CAM-040, CAM-041, CAM-044, CAM-046
- **Docs:** [specs/camera.md](../specs/camera.md), [media.md](../specs/media.md)
- **Scope:** flash and torch modes; timer (Dart-side countdown, native capture); aspect ratio as crop metadata; format choice.
- **Out of scope:** —
- **Acceptance:** instrumented tests on the emulator for the flash mode in results, the format of output files, and crop metadata.
- **Tests:** Dart timer tests with a fake clock (including cancel on lens switch); crop metadata tests; instrumented tests.
- **Doc updates:** none.

### CAM-T-030 iOS: apply exposure (ISO, shutter, EV, AE lock)
- **Status:** todo
- **Platform:** ios
- **Depends:** CAM-T-015, EXP-T-001
- **Requirements:** CAM-010, CAM-011, CAM-012, CAM-014, CAM-050
- **Docs:** [specs/camera.md](../specs/camera.md), [architecture/camera.md](../architecture/camera.md) (testability seams)
- **Scope:** the Swift equivalent of CAM-T-020 via `setExposureModeCustom`; the synthetic source simulates ISO and shutter as brightness scaling.
- **Out of scope:** UI.
- **Acceptance:** XCTest with fake devices proves the requested → applied mapping and mismatch detection; the Simulator synthetic run reports applied values.
- **Tests:** XCTest (100% branch on conversions); a Simulator integration test.
- **Doc updates:** capability-matrix.md.

### CAM-T-031 iOS: focus and white balance
- **Status:** todo
- **Platform:** ios
- **Depends:** CAM-T-030
- **Requirements:** CAM-020, CAM-021, CAM-022, CAM-030, CAM-031
- **Docs:** [specs/camera.md](../specs/camera.md)
- **Scope:** the Swift equivalents of CAM-T-021 and CAM-T-022 (lensPosition, temperature/tint → gains).
- **Out of scope:** —
- **Acceptance:** XCTest with fake devices for each mode; Simulator synthetic run.
- **Tests:** XCTest for coordinate transforms and gains conversion against reference values; a Simulator integration test.
- **Doc updates:** capability-matrix.md.

### CAM-T-032 iOS: lens selection, zoom, flash, timer, aspect, format
- **Status:** todo
- **Platform:** ios
- **Depends:** CAM-T-030
- **Requirements:** CAM-006, CAM-007, CAM-008, CAM-040, CAM-041, CAM-044, CAM-046
- **Docs:** [specs/camera.md](../specs/camera.md)
- **Scope:** the Swift equivalents of CAM-T-023 and CAM-T-024 (physical device switching modeled on the iPhone 12 Pro Max's three lenses in fakes).
- **Out of scope:** —
- **Acceptance:** XCTest with fake triple-camera devices; Simulator synthetic run.
- **Tests:** XCTest; a Simulator integration test.
- **Doc updates:** capability-matrix.md.

### EXP-T-004 Manual controls UI from capabilities
- **Status:** todo
- **Platform:** dart
- **Depends:** EXP-T-001, CAM-T-007
- **Requirements:** EXP-005, CAM-005, CAM-042
- **Docs:** [camera-ux.md](../design/camera-ux.md), [ux-principles.md](../design/ux-principles.md)
- **Scope:** control strip and dials rendered only for supported capabilities; the "not available" sheet; adjustment notices; grid overlay; accessibility labels and actions.
- **Out of scope:** Experience skins.
- **Acceptance:** matches camera-ux.md for each capability fixture.
- **Tests:** widget tests per capability permutation (full, limited, no manual sensor, single lens, synthetic); semantics tests for every dial; a locale formatting test.
- **Doc updates:** none.

### EXP-T-005 Local presets
- **Status:** todo
- **Platform:** dart
- **Depends:** EXP-T-001, MEM-T-001
- **Requirements:** EXP-006, EXP-007
- **Docs:** [memory-domain.md](../specs/memory-domain.md) (Preset)
- **Scope:** a drift `presets` table (migration v2); save the current merged intent; list, apply, rename, and delete.
- **Out of scope:** server sync.
- **Acceptance:** a preset re-applies identically after a restart; a preset referencing unsupported values resolves with adjustments.
- **Tests:** DAO tests, a v1 → v2 migration test, use-case tests, widget tests for the preset UI.
- **Doc updates:** sync.md (local schema).

### EXP-T-006 Experience picker and skins
- **Status:** todo
- **Platform:** dart
- **Depends:** EXP-T-002, EXP-T-004
- **Requirements:** EXP-001, EXP-002, EXP-010, EXP-011
- **Docs:** [camera-ux.md](../design/camera-ux.md)
- **Scope:** Experience switcher; token override themes; the Instant develop animation (presentation only, skippable); the last Experience is restored.
- **Out of scope:** Film roll constraint (EXP-009).
- **Acceptance:** four Experiences selectable; Mirrorless and Instant fully styled.
- **Tests:** widget and golden tests per Experience; a restore-last-Experience test; animation skip and reduce-motion tests.
- **Doc updates:** ux-principles.md if tokens are finalized.

### EXP-T-007 Phase 2 end-to-end suite on both platforms
- **Status:** todo
- **Platform:** dart
- **Depends:** EXP-T-006, EXP-T-005, EXP-T-003, CAM-T-024, CAM-T-032, CAM-T-031
- **Requirements:** EXP-001, EXP-004, EXP-005, EXP-006, EXP-008, CAM-010, CAM-011, CAM-050, NFR-016
- **Docs:** [testing-strategy.md](../development/testing-strategy.md)
- **Scope:** an `integration_test` journey on the Android Emulator and the iOS Simulator: pick an Experience → choose a scenario → override ISO → capture → assert the applied metadata is stored on the Memory → save a preset → restart → apply the preset → capture again.
- **Out of scope:** profiles (P3).
- **Acceptance:** green in both CI jobs.
- **Tests:** this task *is* the test; its regression sensitivity is demonstrated as in CAM-T-018.
- **Doc updates:** roadmap.md (P2 status).
