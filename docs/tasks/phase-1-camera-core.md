# Phase 1 — Camera Core and Local Memories

Roadmap: [P1](../product/roadmap.md). Goal: preview → capture → durable Memory → local library, on **Android and iOS**. Everything is verified automatically on the Android Emulator (`doro_api35`) and the iOS Simulator on cloud macOS, with the synthetic camera source (ADR-0013). iOS tasks closely follow their Android counterparts; batch iOS changes to save macOS CI minutes.

### CAM-T-001 Dart camera domain types
- **Status:** todo
- **Platform:** dart
- **Depends:** FND-T-005
- **Requirements:** CAM-004
- **Docs:** [specs/camera.md](../specs/camera.md), ADR-0002
- **Scope:** immutable Dart types in `doro_camera`: `CameraDescriptor` (including `source`), `CameraCapabilities` (with ranges and derived getters), `IntRange`/`DurationRange`, `WbPreset`, `FocusCapability`, `CaptureRequest`, `CaptureResult`, `AppliedSettings`, `SessionEvent`, and the typed error codes from the spec.
- **Out of scope:** native code.
- **Acceptance:** types match the spec field for field; equality, `hashCode`, and `toString` are implemented; no `dynamic`.
- **Tests:** unit tests for every type: construction, range validation (min ≤ max, rejecting invalid), derived getters, equality and hash; property tests for range invariants. 100% line coverage.
- **Doc updates:** specs/camera.md if any field is renamed.

### CAM-T-002 Pigeon camera API definition
- **Status:** todo
- **Platform:** dart
- **Depends:** CAM-T-001
- **Requirements:** CAM-004
- **Docs:** [specs/camera.md](../specs/camera.md), [mobile.md](../architecture/mobile.md)
- **Scope:** `pigeons/camera_api.dart` with host APIs (listCameras, capabilities, open, close, capture, focus/exposure locks) and Flutter APIs (events); generated Kotlin and Swift code committed; Dart mapping from Pigeon messages to domain types.
- **Out of scope:** native implementation.
- **Acceptance:** the generated code compiles on Android (CI) and iOS (cloud macOS CI); mapping round-trips are lossless.
- **Tests:** mapping unit tests for every message type in both directions, including null capability fields and every error code.
- **Doc updates:** none expected.

### CAM-T-016 Synthetic camera source (debug/test builds)
- **Status:** todo
- **Platform:** any
- **Depends:** CAM-T-002
- **Requirements:** CAM-004, NFR-016
- **Docs:** [architecture/camera.md](../architecture/camera.md) (testability seams), ADR-0013
- **Scope:**
  - A `SyntheticCameraSource` in Swift (behind `DOROCAM_SYNTHETIC_CAMERA`) and Kotlin (debug source set).
  - It produces deterministic frames (test pattern, frame counter, timestamp), and optionally a synthetic audio tone.
  - It declares honest capabilities (only what it simulates; ISO and shutter simulated as brightness scaling), reports `source: synthetic`, and the UI shows a TEST CAMERA badge.
- **Out of scope:** use in release builds (forbidden).
- **Acceptance:** the Simulator lists and streams the synthetic camera; release builds of both platforms contain no synthetic symbols (CI check).
- **Tests:** XCTest and JUnit tests for frame determinism (the same seed gives identical frames), timestamp monotonicity, and declared-vs-applied honesty; the CI release-exclusion check.
- **Doc updates:** capability-matrix.md (S entries confirmed).

### CAM-T-003 Android: enumerate cameras and probe capabilities
- **Status:** todo
- **Platform:** android
- **Depends:** CAM-T-002, SPK-T-001
- **Requirements:** CAM-004, CAM-005, CAM-007, CAM-013
- **Docs:** [specs/camera.md](../specs/camera.md) (probe rules), [capability-matrix.md](../specs/capability-matrix.md)
- **Scope:** Kotlin `CapabilityProbe` behind a `CameraCharacteristicsSource` seam, mapping characteristics to Pigeon capability messages per camera and physical ID, following the probe rules; 35 mm-equivalent focal length computation.
- **Out of scope:** applying settings.
- **Acceptance:** on the emulator, the probe output matches the S1 dump (instrumented test).
- **Tests:** JUnit/Robolectric tests with characteristics fixtures (LEGACY, LIMITED without MANUAL_SENSOR, FULL, LEVEL_3, logical multi-camera, invalid ranges ⇒ null); the 35 mm-eq math on known sensors; an instrumented probe test on the emulator.
- **Doc updates:** capability-matrix.md (emulator column).

### CAM-T-004 Android: session and preview texture
- **Status:** todo
- **Platform:** android
- **Depends:** CAM-T-003
- **Requirements:** CAM-001, CAM-002, CAM-053
- **Docs:** [architecture/camera.md](../architecture/camera.md) (session lifecycle)
- **Scope:** a CameraX session bound to the lifecycle; a `SurfaceProducer` texture; open and close; front/back switch; the lifecycle state machine and events per the diagram; handling of the camera in use or disconnected.
- **Out of scope:** grading (P3), manual settings (P2).
- **Acceptance:** on the emulator: the preview texture delivers frames for the back and front cameras; backgrounding (`adb shell input keyevent HOME`) releases the camera and resuming restores it.
- **Tests:** JUnit tests for every state machine transition (including illegal ones); instrumented tests for open/close/switch/background/resume and for camera-in-use (a second client holds the camera).
- **Doc updates:** none expected.

### CAM-T-005 Android: still capture to file with applied metadata
- **Status:** todo
- **Platform:** android
- **Depends:** CAM-T-004
- **Requirements:** CAM-003, CAM-046, CAM-050
- **Docs:** [architecture/camera.md](../architecture/camera.md) (capture pipeline), [media.md](../specs/media.md)
- **Scope:** capture at the maximum size in JPEG (and HEIF if supported); atomic write (temp → fsync → rename) to the path given by Dart; applied metadata from `TotalCaptureResult`; display and thumbnail JPEGs; return `CaptureResult`.
- **Out of scope:** profile rendering, LIVE.
- **Acceptance:** 100 consecutive captures on the emulator produce valid files, correct EXIF orientation, and matching applied metadata.
- **Tests:** JUnit tests for the atomic file writer (including simulated failure mid-write), the EXIF mapping, and the thumbnail sizing math; an instrumented 100-capture test validating files with an EXIF parser. Adds field verification FV-006 (latency).
- **Doc updates:** capability-matrix.md (HEIF on the emulator); field-verification.md.

### CAM-T-013 iOS: enumerate cameras and probe capabilities
- **Status:** todo
- **Platform:** ios
- **Depends:** CAM-T-002, CAM-T-016, FND-T-009
- **Requirements:** CAM-004, CAM-005, CAM-007, CAM-013
- **Docs:** [specs/camera.md](../specs/camera.md) (probe rules), [architecture/camera.md](../architecture/camera.md) (testability seams)
- **Scope:** the Swift equivalent of CAM-T-003 using physical `AVCaptureDevice` discovery through `CaptureDeviceProviding`; include the synthetic source when compiled in.
- **Out of scope:** applying settings.
- **Acceptance:** XCTest on the Simulator (cloud macOS) passes with fake devices modeling iPhone 12 Pro Max lenses and ranges; the Simulator lists only the synthetic camera.
- **Tests:** XCTest with fake-device fixtures (triple camera, single camera, front only, no manual exposure); a probe integration test on the Simulator.
- **Doc updates:** capability-matrix.md (Simulator column).

### CAM-T-014 iOS: session and preview texture
- **Status:** todo
- **Platform:** ios
- **Depends:** CAM-T-013
- **Requirements:** CAM-001, CAM-002, CAM-053
- **Docs:** [architecture/camera.md](../architecture/camera.md)
- **Scope:** the Swift equivalent of CAM-T-004 (`FlutterTexture` with `CVPixelBuffer`) through `CaptureSessionControlling`; synthetic frames on the Simulator.
- **Out of scope:** grading.
- **Acceptance:** on the Simulator the preview texture shows synthetic frames; background and foreground via `simctl` release and restore the session.
- **Tests:** XCTest for every state transition with a fake session; an `integration_test` on the Simulator.
- **Doc updates:** none.

### CAM-T-015 iOS: still capture with applied metadata
- **Status:** todo
- **Platform:** ios
- **Depends:** CAM-T-014
- **Requirements:** CAM-003, CAM-046, CAM-050
- **Docs:** [architecture/camera.md](../architecture/camera.md), [media.md](../specs/media.md)
- **Scope:** the Swift equivalent of CAM-T-005 (HEIF default), capturing from the synthetic source on the Simulator.
- **Out of scope:** profiles, LIVE.
- **Acceptance:** 100 consecutive synthetic captures on the Simulator produce valid files and metadata.
- **Tests:** XCTest for the atomic writer, the metadata mapping, and the thumbnail math; a 100-capture Simulator integration test.
- **Doc updates:** capability-matrix.md.

### CAM-T-006 Camera permission flow
- **Status:** todo
- **Platform:** dart
- **Depends:** CAM-T-004
- **Requirements:** CAM-052
- **Docs:** [specs/camera.md](../specs/camera.md) (errors), [camera-ux.md](../design/camera-ux.md)
- **Scope:** permission request; denied and permanently-denied states with a settings deep link; the restricted state.
- **Out of scope:** microphone (P6).
- **Acceptance:** every state is reachable and explained on the emulator (`pm revoke`) and the Simulator (`simctl privacy`).
- **Tests:** widget tests with `FakeCameraPlatform` for each permission state; `integration_test` for grant and revoke on both platforms.
- **Doc updates:** none.

### CAM-T-007 Camera screen (basic)
- **Status:** todo
- **Platform:** dart
- **Depends:** CAM-T-004, CAM-T-006
- **Requirements:** CAM-001, CAM-002, CAM-051
- **Docs:** [camera-ux.md](../design/camera-ux.md), [mobile.md](../architecture/mobile.md)
- **Scope:** a `CameraSessionController` provider; viewfinder `Texture`; shutter button with haptic; switch camera; last-photo thumbnail; TEST CAMERA badge for synthetic sources.
- **Out of scope:** Experiences, controls.
- **Acceptance:** usable on the emulator and the Simulator; the shutter re-arms after the sensor capture completes.
- **Tests:** unit tests for the controller (every state and error); widget tests (preview shown, capture invoked, error toast, badge shown only for synthetic sources, semantics labels).
- **Doc updates:** none.

### MEM-T-001 drift database and Memory/asset tables
- **Status:** todo
- **Platform:** dart
- **Depends:** FND-T-004
- **Requirements:** MEM-001, MEM-002, MEM-008
- **Docs:** [sync.md](../architecture/sync.md) (local schema), [memory-domain.md](../specs/memory-domain.md)
- **Scope:** a drift DB (WAL) with `memories` and `assets` tables per sync.md; DAOs; a UUIDv7 generator; a `publicHandle` generator (22-char base62 from a CSPRNG); schema version 1 with the migration test harness.
- **Out of scope:** upload queue tables (P5).
- **Acceptance:** domain invariants 1, 2, and 7 from memory-domain.md are enforced in the repository layer.
- **Tests:** DAO tests on real SQLite for every query; invariant violation tests; UUIDv7 monotonicity and format tests; handle alphabet, length, and uniqueness property tests; the schema v1 snapshot test.
- **Doc updates:** sync.md if the schema deviates.

### MEM-T-002 Capture → Memory use case
- **Status:** todo
- **Platform:** dart
- **Depends:** MEM-T-001, CAM-T-005
- **Requirements:** MEM-001, MEM-002, NFR-002, CAM-053
- **Docs:** [architecture/camera.md](../architecture/camera.md) (capture pipeline), [sync.md](../architecture/sync.md)
- **Scope:** a `CaptureMemory` use case that allocates IDs and paths, calls capture, and commits the Memory + assets in one transaction; startup cleanup of orphan temp files and file-less rows.
- **Out of scope:** upload enqueue (P5).
- **Acceptance:** an automated kill-during-capture loop (30 iterations each on the emulator and the Simulator) never leaves a partial Memory.
- **Tests:** use-case tests with the fake platform and real drift, covering success, capture failure, storage full, and every cleanup case; the kill-loop integration test on both platforms.
- **Doc updates:** none.

### LIB-T-001 Local library grid
- **Status:** todo
- **Platform:** dart
- **Depends:** MEM-T-002
- **Requirements:** LIB-001
- **Docs:** [ux-principles.md](../design/ux-principles.md)
- **Scope:** a newest-first grid from a drift stream using thumbnails; empty state; works offline.
- **Out of scope:** filters, sync status (P5).
- **Acceptance:** 1,000 seeded Memories scroll without dropped frames in a Flutter performance `integration_test` on the emulator (indicative); correct ordering.
- **Tests:** widget tests (empty, one, many, ordering, stream update); an integration scroll test.
- **Doc updates:** none.

### LIB-T-002 Memory detail view
- **Status:** todo
- **Platform:** dart
- **Depends:** LIB-T-001
- **Requirements:** LIB-002, MEM-004, MEM-006, MEM-007
- **Docs:** [memory-domain.md](../specs/memory-domain.md)
- **Scope:** full-screen photo (display rendition, pinch-zoom), capture metadata panel, caption edit, favorite, move to trash, and a trash view with restore.
- **Out of scope:** motion playback (P6).
- **Acceptance:** edits persist across app restarts (integration test on both platforms).
- **Tests:** widget tests for each control and state; use-case tests for caption, favorite, trash, restore; the restart-persistence integration test.
- **Doc updates:** none.

### CAM-T-018 Phase 1 end-to-end suite on both platforms
- **Status:** todo
- **Platform:** dart
- **Depends:** LIB-T-002, CAM-T-015
- **Requirements:** CAM-001, CAM-003, MEM-001, LIB-001, LIB-002, NFR-002, NFR-016
- **Docs:** [testing-strategy.md](../development/testing-strategy.md)
- **Scope:** an `integration_test` journey: launch → permission → preview → capture ×100 → library shows 100 → detail → caption edit → restart → persisted. It runs on the Android Emulator (CI `android` job) and the iOS Simulator (`ios.yml`).
- **Out of scope:** P2+ features.
- **Acceptance:** green on both platforms in CI; tagged with its requirement IDs.
- **Tests:** this task *is* the test. It must fail when any step regresses, demonstrated by a temporary broken commit in a throwaway branch.
- **Doc updates:** roadmap.md (P1 status).
