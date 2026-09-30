# Spec: Camera Platform Contract

Status: Draft (validated by spike S1) · Last updated: 2026-09-30 · Related: CAM-001–CAM-053, EXP-008, ADR-0001, ADR-0002, ADR-0003

## Purpose

Define the Dart-facing contract of `packages/doro_camera` and the rules both native implementations must satisfy. The contract is the same on Android and iOS. Platform differences appear only as capability values.

## Dart API surface (conceptual)

Final signatures are defined in the Pigeon file `packages/doro_camera/pigeons/camera_api.dart` when scaffolded. This table is the normative behavior.

| Call | Input | Output | Notes |
|---|---|---|---|
| `DoroCamera.listCameras()` | — | `List<CameraDescriptor>` | One per **physical** camera usable by third-party apps, plus logical/virtual cameras flagged as such |
| `DoroCamera.capabilities(cameraId)` | id | `CameraCapabilities` | Probed from the platform; cached per session |
| `DoroCamera.open(config)` | `SessionConfig{cameraId, photoFormat, previewSize, live, profileLut?}` | `CameraSession` with `textureId` | Fails with typed errors (below) |
| `session.apply(settings)` | `ResolvedCaptureSettings` | `AppliedSettingsEvent` stream | Native applies; reports what the hardware accepted |
| `session.focusAt(point)` / `session.lockFocus()` / `session.lockExposure()` | normalized point | — | CAM-020, CAM-022, CAM-014 |
| `session.setPreviewProfile(lut, effects)` | LUT bytes + effect params | — | Depends on S2 outcome |
| `session.capture(request)` | `CaptureRequest{memoryId, assetIds, outputDir, render, live, location?}` | `CaptureResult` | See [camera.md](../architecture/camera.md) capture pipeline |
| `session.events` | — | stream of `SessionEvent` | state, errors, thermal, orientation, applied settings |
| `session.close()` | — | — | Idempotent |

## CameraCapabilities

```text
CameraDescriptor { id, facing: back|front|external, lensKind, isLogical, physicalIds[], sensorOrientation,
                   focalLengthMm, focalLength35mmEq }
CameraCapabilities {
  iso:            IntRange?           // null ⇒ no manual ISO
  exposureTime:   DurationRange?      // null ⇒ no manual shutter
  exposureBias:   { range: DoubleRange, step: double }?
  apertures:      double[]            // usually length 1 ⇒ display only
  focus:          { auto: bool, continuous: bool, tapToFocus: bool,
                    manual: { minFocusDistanceDiopters, calibration: uncalibrated|approximate|calibrated }? }
  whiteBalance:   { presets: WbPreset[], kelvin: IntRange? }
  zoom:           { min, max, opticalSteps: double[] }
  flash:          FlashMode[]
  torch:          bool
  photoFormats:   (heif|jpeg|dng)[]
  photoSizes:     Size[]
  stabilization:  { photo: Mode[], video: Mode[] }
  video:          { sizesByFps: Map<Size, int[]> }   // P8
  hdr:            bool
  live:           { supported: bool, maxPreBufferMs, audio: bool }
  hardwareLevel:  string              // Android: LEGACY|LIMITED|FULL|LEVEL_3; iOS: n/a
}
```

### Probe rules

- **Android:** read from `CameraCharacteristics` via Camera2 interop: `SENSOR_INFO_SENSITIVITY_RANGE`, `SENSOR_INFO_EXPOSURE_TIME_RANGE`, `CONTROL_AE_COMPENSATION_RANGE/STEP`, `LENS_INFO_AVAILABLE_APERTURES`, `LENS_INFO_MINIMUM_FOCUS_DISTANCE`, `LENS_INFO_FOCUS_DISTANCE_CALIBRATION`, `CONTROL_AWB_AVAILABLE_MODES`, `REQUEST_AVAILABLE_CAPABILITIES` (MANUAL_SENSOR, RAW, LOGICAL_MULTI_CAMERA), `INFO_SUPPORTED_HARDWARE_LEVEL`. Manual ISO and shutter are exposed only if `MANUAL_SENSOR` is present **and** the ranges are valid (non-null, min < max).
- **iOS:** read from `AVCaptureDevice.activeFormat` (`minISO/maxISO`, `minExposureDuration/maxExposureDuration`), `isExposureModeSupported(.custom)`, `isFocusModeSupported(.locked)`, `isLockingFocusWithCustomLensPositionSupported`, `isWhiteBalanceModeSupported(.locked)`, `lensAperture` (read-only ⇒ `apertures=[value]`), `AVCapturePhotoOutput.availableRawPhotoPixelFormatTypes`, `isLivePhotoCaptureSupported`.
- **Kelvin:** Android supports it only with `CONTROL_AWB_MODE_OFF` + `COLOR_CORRECTION_GAINS` (computed from Kelvin via a documented conversion) if `MANUAL_POST_PROCESSING` is available. iOS converts via `deviceWhiteBalanceGains(for: temperatureAndTintValues)`. Otherwise `kelvin = null`.
- Capabilities may depend on the selected format and size (iOS `activeFormat`). They are re-probed on reconfiguration.

## Intent resolution (Dart, pure)

`resolve(intent: CaptureIntent, caps: CameraCapabilities) → (ResolvedCaptureSettings, List<Adjustment>)`

Rules:
1. Each requested manual value is clamped into its range. A clamp produces `Adjustment{field, requested, applied, reason: outOfRange}`.
2. A requested manual value without a capability becomes auto, with `Adjustment{reason: unsupported}`.
3. ISO and shutter are independent. If only one is manual on a platform that requires both for custom exposure, the other takes the current auto-metered value at the moment manual engages (documented per platform).
4. Exposure bias applies only when exposure is not fully manual. Otherwise it is ignored with `Adjustment{reason: notApplicableInManual}`.
5. The Experience constraints validator runs last. It can reject (e.g. roll finished) with a typed error.
6. The function is total and deterministic: no exceptions for any input, and it has exhaustive unit tests including property-based tests (random intents × random capabilities ⇒ output within capabilities).

## Errors

| Code | Meaning | UI behavior |
|---|---|---|
| `permission_denied` | Camera permission denied | Explain + deep link to settings (CAM-052) |
| `permission_restricted` | Parental or MDM restriction | Explain; no settings link |
| `camera_in_use` | Another app holds the camera | Retry on resume |
| `camera_disconnected` | Hardware error or external camera removed | Reopen default camera |
| `unsupported_configuration` | Requested format or size combination rejected | Fall back to default config + Adjustment |
| `capture_failed` | Capture error | Toast; the Memory is not created |
| `storage_full` | Cannot write | Block capture with explanation |
| `thermal_shutdown` | Critical thermal state | Close session, explain |

## Edge cases

- Rotation: capture orientation comes from the device orientation sensor, not the UI orientation (the camera UI may be locked to portrait).
- Front camera: the preview is mirrored; the saved photo is **not** mirrored by default (setting later).
- A lens switch during a timer countdown cancels the timer.
- An app kill during capture yields no DB row plus a temp file that is cleaned up on next start.
- Devices exposing only a logical camera: lens switching is via zoom steps (`opticalSteps`), and manual mode may be unavailable. This is reported, not faked.

## Acceptance criteria

- On the reference device, every control shown has its effect confirmed in `CaptureResult.appliedSettings` (CAM-050). A control whose request/applied mismatch persists across 3 captures is disabled for the session with an explanation.
- A capability absent from the platform APIs never appears in the UI (CAM-005). Widget tests cover the capability permutations.
- The resolver has 100% branch coverage, and property tests pass.
