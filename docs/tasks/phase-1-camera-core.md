# Phase 1 — Camera Core and Local Memories

Roadmap: [P1](../product/roadmap.md). Goal: preview → capture → durable Memory → local library on the Honor X9c. iOS counterparts are defined and blocked until macOS is available.

### CAM-T-001 Dart camera domain types
- **Status:** todo
- **Platform:** dart
- **Depends:** FND-T-005
- **Requirements:** CAM-004
- **Docs:** [specs/camera.md](../specs/camera.md), ADR-0002
- **Scope:** immutable Dart types in `doro_camera`: `CameraDescriptor`, `CameraCapabilities` (with ranges and derived getters), `IntRange`/`DurationRange`, `WbPreset`, `FocusCapability`, `CaptureRequest`, `CaptureResult`, `AppliedSettings`, `SessionEvent`, and the typed error codes from the spec.
- **Out of scope:** native code.
- **Acceptance:** types match the spec field for field; equality and `toString` are implemented; no `dynamic`.
- **Tests:** unit tests for range validation (min ≤ max), derived getters, and equality.
- **Doc updates:** specs/camera.md if any field is renamed.

### CAM-T-002 Pigeon camera API definition
- **Status:** todo
- **Platform:** dart
- **Depends:** CAM-T-001
- **Requirements:** CAM-004
- **Docs:** [specs/camera.md](../specs/camera.md), [mobile.md](../architecture/mobile.md)
- **Scope:** `pigeons/camera_api.dart` with host APIs (listCameras, capabilities, open, close, capture, focus/exposure locks) and Flutter APIs (events); generated Kotlin and Swift code committed; Dart mapping from Pigeon messages to the domain types.
- **Out of scope:** native implementation.
- **Acceptance:** the generated code compiles on Android; mapping round-trips are lossless.
- **Tests:** mapping unit tests for every message type, including null capability fields.
- **Doc updates:** none expected.

### CAM-T-003 Android: enumerate cameras and probe capabilities
- **Status:** todo
- **Platform:** android
- **Depends:** CAM-T-002, SPK-T-001
- **Requirements:** CAM-004, CAM-005, CAM-007, CAM-013
- **Docs:** [specs/camera.md](../specs/camera.md) (probe rules), [capability-matrix.md](../specs/capability-matrix.md)
- **Scope:** Kotlin `CapabilityProbe` mapping `CameraCharacteristics` to Pigeon capability messages per camera and physical ID, following the probe rules; 35 mm-equivalent focal length computation.
- **Out of scope:** applying settings.
- **Acceptance:** on the Honor, the probe output matches the S1 dump.
- **Tests:** JUnit/Robolectric tests with characteristics fixtures (LEGACY, LIMITED without MANUAL_SENSOR, FULL, logical multi-camera, invalid ranges ⇒ null).
- **Doc updates:** capability-matrix.md (Honor verified column).

### CAM-T-004 Android: session and preview texture
- **Status:** todo
- **Platform:** android
- **Depends:** CAM-T-003
- **Requirements:** CAM-001, CAM-002, CAM-053
- **Docs:** [architecture/camera.md](../architecture/camera.md) (session lifecycle)
- **Scope:** CameraX session bound to the lifecycle; a `SurfaceProducer` texture; open and close; front/back switch; lifecycle states and events per the state diagram; handling of the camera in use or disconnected.
- **Out of scope:** grading (P3), manual settings (P2).
- **Acceptance:** preview shows correctly oriented on the Honor for the back and front cameras; backgrounding releases the camera; returning restores the preview.
- **Tests:** JUnit tests for the state machine transitions (pure Kotlin class); device script for orientation and interruption.
- **Doc updates:** none expected.

### CAM-T-005 Android: still capture to file with applied metadata
- **Status:** todo
- **Platform:** android
- **Depends:** CAM-T-004
- **Requirements:** CAM-003, CAM-046, CAM-050
- **Docs:** [architecture/camera.md](../architecture/camera.md) (capture pipeline), [media.md](../specs/media.md)
- **Scope:** capture at the maximum size in JPEG (and HEIF if supported); atomic write (temp → fsync → rename) to the path given by Dart; read the applied ISO, exposure time, focal length, and aperture from the capture result; return `CaptureResult`. The rendered, display, and thumbnail outputs at this stage are the same pixels (no profile yet): produce the display and thumbnail JPEGs.
- **Out of scope:** profile rendering, LIVE.
- **Acceptance:** 100 consecutive captures produce valid files and results; EXIF orientation is correct.
- **Tests:** JUnit tests for the file-writing utility (atomicity via a temp dir) and the EXIF mapping; device script.
- **Doc updates:** capability-matrix.md (HEIF support on the Honor).

### CAM-T-006 Camera permission flow
- **Status:** todo
- **Platform:** dart
- **Depends:** CAM-T-004
- **Requirements:** CAM-052
- **Docs:** [specs/camera.md](../specs/camera.md) (errors), [camera-ux.md](../design/camera-ux.md)
- **Scope:** permission request, denied and permanently-denied states with a settings deep link, and the restricted state.
- **Out of scope:** microphone (P6).
- **Acceptance:** all states are reachable and explained on the device.
- **Tests:** widget tests with `FakeCameraPlatform` returning each permission error.
- **Doc updates:** none.

### CAM-T-007 Camera screen (basic)
- **Status:** todo
- **Platform:** dart
- **Depends:** CAM-T-004, CAM-T-006
- **Requirements:** CAM-001, CAM-002, CAM-051
- **Docs:** [camera-ux.md](../design/camera-ux.md), [mobile.md](../architecture/mobile.md)
- **Scope:** a `CameraSessionController` provider; viewfinder `Texture`; shutter button with haptic; switch camera; last-photo thumbnail. No manual controls yet.
- **Out of scope:** Experiences, controls.
- **Acceptance:** usable on the device; the shutter re-arms after the sensor capture completes.
- **Tests:** widget tests with the fake platform (preview shown, capture invoked, error toast).
- **Doc updates:** none.

### MEM-T-001 drift database and Memory/asset tables
- **Status:** todo
- **Platform:** dart
- **Depends:** FND-T-004
- **Requirements:** MEM-001, MEM-002, MEM-008
- **Docs:** [sync.md](../architecture/sync.md) (local schema), [memory-domain.md](../specs/memory-domain.md)
- **Scope:** drift DB (WAL) with `memories` and `assets` tables per sync.md (upload columns included but unused); DAOs; UUIDv7 generator; `publicHandle` generator (22-char base62 from a CSPRNG); schema version 1 with a migration test harness.
- **Out of scope:** upload queue tables (P5).
- **Acceptance:** domain invariants 1, 2, and 7 from memory-domain.md are enforced in the repository layer.
- **Tests:** DAO tests on native SQLite; invariant violation tests; UUIDv7 monotonicity and handle-format tests.
- **Doc updates:** sync.md if the schema deviates.

### MEM-T-002 Capture → Memory use case
- **Status:** todo
- **Platform:** dart
- **Depends:** MEM-T-001, CAM-T-005
- **Requirements:** MEM-001, MEM-002, NFR-002, CAM-053
- **Docs:** [architecture/camera.md](../architecture/camera.md) (capture pipeline), [sync.md](../architecture/sync.md)
- **Scope:** a `CaptureMemory` use case that allocates IDs and paths, calls capture, and commits the Memory + assets in one transaction; startup cleanup of orphan temp files and file-less rows.
- **Out of scope:** upload enqueue (P5).
- **Acceptance:** killing the app during capture never leaves a partial Memory (device kill test, 30 iterations).
- **Tests:** use-case tests with a fake platform and real drift, covering capture failure, storage full, and crash-before-commit simulation via the cleanup routine.
- **Doc updates:** none.

### LIB-T-001 Local library grid
- **Status:** todo
- **Platform:** dart
- **Depends:** MEM-T-002
- **Requirements:** LIB-001
- **Docs:** [ux-principles.md](../design/ux-principles.md)
- **Scope:** a newest-first grid from a drift stream using thumbnails; empty state; works offline.
- **Out of scope:** filters, sync status (P5).
- **Acceptance:** smooth scrolling with 1,000 Memories on the device (seeded).
- **Tests:** widget tests with a seeded in-memory DB.
- **Doc updates:** none.

### LIB-T-002 Memory detail view
- **Status:** todo
- **Platform:** dart
- **Depends:** LIB-T-001
- **Requirements:** LIB-002, MEM-004, MEM-006, MEM-007
- **Docs:** [memory-domain.md](../specs/memory-domain.md)
- **Scope:** full-screen photo (display rendition, pinch-zoom), capture metadata panel, caption edit, favorite, move to trash, and a trash view with restore.
- **Out of scope:** motion playback (P6).
- **Acceptance:** edits persist across restarts.
- **Tests:** widget and use-case tests.
- **Doc updates:** none.

### CAM-T-013 iOS: enumerate cameras and probe capabilities
- **Status:** blocked (needs macOS)
- **Platform:** ios
- **Depends:** CAM-T-002
- **Requirements:** CAM-004, CAM-005, CAM-007, CAM-013
- **Docs:** [specs/camera.md](../specs/camera.md) (probe rules)
- **Scope:** the Swift equivalent of CAM-T-003, using physical `AVCaptureDevice` discovery.
- **Out of scope:** applying settings.
- **Acceptance:** the probe on the iPhone 12 Pro Max reports three rear lenses with correct ranges.
- **Tests:** XCTest with format fixtures.
- **Doc updates:** capability-matrix.md (iPhone verified column).

### CAM-T-014 iOS: session and preview texture
- **Status:** blocked (needs macOS)
- **Platform:** ios
- **Depends:** CAM-T-013
- **Requirements:** CAM-001, CAM-002, CAM-053
- **Docs:** [architecture/camera.md](../architecture/camera.md)
- **Scope:** the Swift equivalent of CAM-T-004 (`FlutterTexture` with `CVPixelBuffer`).
- **Out of scope:** grading.
- **Acceptance:** same as CAM-T-004 on the iPhone.
- **Tests:** XCTest for the state machine.
- **Doc updates:** none.

### CAM-T-015 iOS: still capture with applied metadata
- **Status:** blocked (needs macOS)
- **Platform:** ios
- **Depends:** CAM-T-014
- **Requirements:** CAM-003, CAM-046, CAM-050
- **Docs:** [architecture/camera.md](../architecture/camera.md), [media.md](../specs/media.md)
- **Scope:** the Swift equivalent of CAM-T-005 (HEIF default).
- **Out of scope:** profiles, LIVE.
- **Acceptance:** same as CAM-T-005 on the iPhone.
- **Tests:** XCTest for file writing and metadata mapping.
- **Doc updates:** capability-matrix.md.
