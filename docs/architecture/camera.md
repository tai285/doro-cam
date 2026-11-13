# Camera Architecture

Status: Accepted (pending spikes S1, S2, S3) · Last updated: 2026-09-30 · Related: ADR-0001, ADR-0002, ADR-0003, ADR-0004, ADR-0005, CAM-004, CAM-005, EXP-008

## Why a first-party plugin

The official Flutter `camera` plugin does not expose manual ISO, shutter, Kelvin white balance, manual focus, or physical lens selection, and community forks are stale or single-platform ([camera-apis.md](../research/camera-apis.md)). Doro Cam therefore owns `packages/doro_camera`: a Dart API plus native implementations (ADR-0001). The app is cross-platform at the **Dart** level. Hardware behavior is native and per-platform, and differences surface through capabilities, not `if (Platform.isIOS)` branches in app code.

## Component view

```mermaid
flowchart TB
  subgraph Dart
    UI[Camera UI<br/>renders from capabilities] --> Ctl[CameraSessionController]
    Ctl --> Res[CaptureIntentResolver<br/>pure Dart]
    Ctl --> API[doro_camera Dart API]
  end
  API -- Pigeon --> A[Android: Kotlin<br/>CameraX + Camera2 interop]
  API -- Pigeon --> I[iOS: Swift<br/>AVFoundation]
  A --> T1[Preview texture<br/>GL grading]
  I --> T2[Preview texture<br/>Metal/CI grading]
```

## Responsibilities

| Concern | Where | Notes |
|---|---|---|
| Enumerate cameras, probe capabilities | Native → mapped to Dart `CameraCapabilities` | Per **physical** camera (ADR-0002) |
| Choose settings (scenario, preset, manual) | Dart `CaptureIntentResolver` | Pure, exhaustively unit-tested |
| Clamp to capabilities, explain changes | Dart resolver | Output: `ResolvedCaptureSettings` + `List<Adjustment>` |
| Apply settings to hardware | Native | Reports *applied* values back via result metadata (CAM-050) |
| Preview rendering + live profile | Native GPU or Flutter shader | Decided by spike S2 |
| Full-resolution capture render | Native GPU/CPU | Applies the compiled LUT + effects (ADR-0004) |
| Motion pre/post buffering | Native | ADR-0005, spike S3 |
| Writing files | Native writes to the path Dart provides | Dart owns naming and the DB transaction |

## Session lifecycle

```mermaid
stateDiagram-v2
  [*] --> Uninitialized
  Uninitialized --> RequestingPermission: open()
  RequestingPermission --> Denied: denied
  RequestingPermission --> Configuring: granted
  Configuring --> Previewing: session running
  Previewing --> Capturing: capture()
  Capturing --> Previewing: saved / failed
  Previewing --> Reconfiguring: lens / format / LIVE change
  Reconfiguring --> Previewing
  Previewing --> Suspended: app background / interruption
  Suspended --> Configuring: resume
  Previewing --> Closed: close()
  Closed --> [*]
```

- A capture in flight when the app is backgrounded must complete writing to disk or be discarded atomically (CAM-053, NFR-002).
- Thermal state events (`nominal/fair/serious/critical`) are forwarded. At `serious`, LIVE buffering pauses. At `critical`, preview grading falls back to ungraded preview and the UI says why (NFR-012).

## Capability model (summary)

Full contract: [specs/camera.md](../specs/camera.md). Key rules:

- Capabilities are **ranges and sets**, not booleans. For example, ISO is `IntRange(min, max)`, not `supportsManualISO`. Booleans are derived getters (`hasManualIso => iso != null`).
- **Probed at runtime** from `CameraCharacteristics` / `AVCaptureDevice.formats`. Nothing is hardcoded per model. Device quirks, when discovered, go into a small, documented, tested *quirks table* keyed by manufacturer/model. They are recorded in [capability-matrix.md](../specs/capability-matrix.md).
- **Verified, not trusted:** after capture, the applied ISO and exposure time from the result metadata are compared with the request. A persistent mismatch (the device ignores manual keys) downgrades the capability for the session and is logged (S1 validates this on the Android Emulator; FV-001 checks the Honor).
- Manual mode binds a **physical** lens. On iOS, virtual multi-camera devices switch lenses automatically and limit manual control. On Android, logical multi-cameras may expose physical IDs only on some devices.
- **Aperture** is almost always a single fixed value on phones. It is shown, and controllable only if more than one value is reported (CAM-013).

## Mode composition (ADR-0003)

The four "modes" are not four camera implementations. They are layers producing one `CaptureIntent`:

```
Experience defaults  (e.g. Instant: 1:1-ish frame, Instant Warm, flash auto)
  ⊕ Source layer     (Scenario recommendation | Preset | none)
  ⊕ Manual overrides (whatever the user touched in this session)
  → CaptureIntent    (requested values, possibly unsupported)
  → resolve(intent, capabilities) → ResolvedCaptureSettings + adjustments[]
```

- Later layers override earlier ones, field by field.
- "Custom mode" is simply saving the current merged intent as a Preset.
- Experience *constraints* (e.g. Film roll count, a fixed profile in an authentic mode) are validation rules applied in the resolver, not UI hacks.
- Assisted scenarios are data (a table of recommended ranges plus explanation strings), versioned in code, and unit-tested.

## Preview pipeline

Two candidate designs. **Spike S2 decides**, and the result becomes an ADR update:

| Option | How | Pros | Cons |
|---|---|---|---|
| A. Native GPU grading | Android: CameraX `CameraEffect`/`SurfaceProcessor` with a GLES shader applying the 3D LUT + grain/vignette → output surface → Flutter `Texture`. iOS: `AVCaptureVideoDataOutput` → Metal/Core Image → `CVPixelBuffer` → `FlutterTexture`. | Proven performance path; the same shader math is reused for video recording (P8) | Shader logic written twice (GLSL, Metal) |
| B. Flutter shader | Raw preview `Texture` + `ImageFilter.shader` (Impeller) running one GLSL fragment shader | One shader for both platforms | Unproven at 30 fps on a mid-range device; doesn't help capture or video rendering |

In either case, **capture rendering is native** and uses the same compiled LUT data as preview, which is how parity is achieved (PRF-009).

## Capture pipeline (still)

1. Dart calls `session.capture(CaptureRequest{ memoryId, assetIds, outputDir, format, renderProfile, live })`.
2. Native triggers capture with the resolved settings and receives the processed original (HEIF/JPEG, or DNG when RAW is enabled) plus result metadata.
3. Native writes the **original** unchanged (temp file → fsync → rename).
4. Native renders the **rendered** JPEG: original → LUT → effects → crop per aspect ratio → JPEG, with EXIF (orientation, time) and XMP (`doro:memoryId`). GPS is written only if location is enabled (PRIV-001).
5. Native generates a **thumbnail** and a **display** rendition (JPEG) so the server never has to decode HEIC ([media-pipeline.md](media-pipeline.md)).
6. Native returns `CaptureResult{ files, appliedSettings, timestamps, dimensions }`. Dart commits the Memory + assets in one drift transaction, then enqueues upload.

If steps 4–5 fail, the Memory is still saved with the original, and rendering is retried later. The original is never lost to a rendering failure.

## Testability seams (ADR-0013)

Every layer is testable without a physical phone:

| Layer | Seam | Test double | Runs on |
|---|---|---|---|
| Dart app | `CameraPlatform` | `FakeCameraPlatform` (scriptable capabilities, results, errors, events) | Dart VM (unit and widget tests) |
| Kotlin plugin | `CameraCharacteristicsSource`, `CaptureRequestSink`, `Clock` | Fixture characteristics, recording sinks | JVM (JUnit + Robolectric) |
| Kotlin plugin, real paths | The Android Emulator's emulated camera HAL | — (real CameraX/Camera2 code) | Android Emulator instrumentation |
| Swift plugin core | `DeviceFacts` (plain values read from `AVCaptureDevice` by `DeviceAdapter`), the capture-session state machine, `TimedRing`, `AtomicOutput` | Fake devices built from `DeviceFacts`, scripted events, temp directories, synthetic CoreImage inputs | `swift test` (`DOROCAM_SWIFT_STANDALONE=1`) on cloud macOS, manual `ios.yml` (ADR-0015, ADR-0016) |
| Swift plugin, end to end | `SyntheticCamera` + `SyntheticDriver` (debug builds only, `DOROCAM_SYNTHETIC_CAMERA`) | Deterministic frames (moving gradient, white flash every second) and a matching 1 kHz beep | iOS Simulator `integration_test` on cloud macOS |
| Motion pipeline | Frame/audio sample providers | Synthetic flash frames and beep tones at known timestamps | Emulator and Simulator |

Rules for the synthetic source:
- It is compiled only with the `DOROCAM_SYNTHETIC_CAMERA` flag (Swift) or the `debug` source set (Kotlin).
- It is listed by `listCameras()` with `source: synthetic`, and the UI shows a "TEST CAMERA" badge.
- It reports honest capabilities: it declares only the controls it actually simulates, and results report exactly what it applied.
- `scripts/check-synthetic-camera.sh` asserts that release artifacts contain no synthetic-source marker (run by `ios.yml`, and locally for Android).

## Performance and battery policy

- The preview stops when the camera route is not visible and when the app is backgrounded.
- LIVE ring buffering runs only while LIVE is on and the preview is visible (MOT-009).
- Capture rendering runs off the camera thread. The shutter button re-arms as soon as the sensor capture completes, not after rendering.
- Budgets (fps, shutter latency) are set from spike measurements (NFR-003, NFR-004). They are not invented here.

## iOS implementation (as built)

The iOS side follows ADR-0015: a Flutter-free `DoroCameraCore` target holds every decision, and the `doro_camera` glue target only converts Pigeon messages and talks to AVFoundation.

| Concern | Where | How it works |
|---|---|---|
| Capability probe | `CapabilityProbe` (core), `DeviceFacts.init(device:photoOutput:)` (glue) | Manual ISO and shutter only with custom exposure **and** valid ranges; focal length from `videoFieldOfView`; white balance Kelvin only with lockable gains; manual focus only with a locked lens position **and** a known closest distance; aperture is display-only |
| Settings | `SettingsClamp`, `AppliedComparison` (core), `DeviceController` (glue) | Dart sends resolved settings; the core clamps again as a safety net; the device is configured with `setExposureModeCustom`, `setFocusModeLocked`, locked white-balance gains, zoom and torch; applied values are read back and compared (mismatch names go to Dart) |
| Manual focus | `FocusMath` | Dart speaks diopters (0 = infinity, up to the closest distance); iOS wants a lens position 0 (near) to 1 (far); the mapping is linear in diopters and always labelled uncalibrated |
| Preview | `PreviewTexture`, `CameraSession` | BGRA frames from `AVCaptureVideoDataOutput` (4:3, portrait connection) published as a Flutter texture; the front preview is mirrored, saved photos never are |
| Still capture | `PhotoCaptureDelegate`, `CameraSession.performCapture` | HEIC (or JPEG; DNG with a processed JPEG for rendering); the camera's file is written bit-exact to `.partial` then renamed (`AtomicOutput`); GPS goes into the photo's own metadata only when the app passes a location |
| Renditions | `StillRenderer` (core, CoreImage and ImageIO) | Rendered JPEG with the LUT, vignette, grain and center crop; thumbnail (512) and display (2048) from it. A failure keeps the original and returns `renderFailed` |
| Motion Memory | `TimedRing`, `MotionClipPlanner` (core), `FrameDownscaler`, `MotionClipWriter` (glue) | While LIVE is on, frames are copied to a private pool (15 fps, 960 px long edge) and audio is kept as 16-bit mono PCM, about 2 s. At the shutter the clip window is planned, post-roll is awaited, and video plus audio are encoded together to one MP4 (H.264 + AAC), so audio/video sync is kept |
| Video | `VideoRecorder` | Real-time `AVAssetWriter` fed from the same frame path |
| Interruptions | `SessionMachine` (core) | Another app, backgrounding, runtime errors and thermal state become events; a capture in progress finishes before the session pauses (no lost capture); critical thermal state closes the session with `thermal_shutdown`; background stops preview and buffering (NFR-012) |
| Permissions | `PermissionEvaluation` (core), `DoroCameraPlugin` | Camera denial maps to `permission_denied` or `permission_restricted`; without microphone permission Motion is silent |
| Synthetic camera | `SyntheticCamera`, `SyntheticDriver` | Debug builds only; offered by `listCameras()` only when the machine has no real camera (the Simulator); reports `source: synthetic` |

Known limits, all recorded in [field-verification.md](../development/field-verification.md): the Motion clip is lower resolution than the still (memory safety); photo stabilization is not controllable on iOS; the iOS code has not yet been built (FV-008) until `ios.yml` has run.
