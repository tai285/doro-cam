# Capability Matrix

Status: Living · Last updated: 2026-11-14 · Related: CAM-004, CAM-005, ADR-0002, ADR-0013, [camera-apis.md](../research/camera-apis.md), [testing-infrastructure.md](../research/testing-infrastructure.md), [spikes.md](../research/spikes.md), [field-verification.md](../development/field-verification.md)

This matrix makes platform limits explicit. The columns fall into three kinds:
- **API-level:** what the platform API can expose on *some* devices (from documentation research).
- **Test targets:** what the Android Emulator AVD `doro_api35` and the iOS Simulator actually report. Filled in by spikes and test runs. These are the targets agents verify against (ADR-0013, ADR-0016).
- **Field:** what the owner's real devices report. Filled in by field verification when available.

Legend: ✓ available · ◐ device-dependent / partial · ✗ not available · ? not yet verified · — not applicable · S synthetic source only (debug and test builds)

The app never reads this table at runtime. It probes capabilities (ADR-0002). This table is for planning and for spotting quirks.

## Photo controls

| Capability | Android API-level | iOS API-level | Android Emulator (API 35) | iOS Simulator | Honor X9c (field) | iPhone 12 Pro Max (field) | Notes |
|---|---|---|---|---|---|---|---|
| Any camera | ✓ | ✓ | ✓ emulated HAL (back virtual scene, front emulated) | ✗ no capture devices → S | ✓ | ✓ | Simulator uses `SyntheticCameraSource` |
| Manual ISO | ◐ needs `MANUAL_SENSOR` | ✓ custom exposure | ? expected ✓ (emulated HAL advertises Level 3) | S (and fakes in XCTest) | ? FV-001 | ? FV-002 | Many mid-range Android devices report LIMITED |
| Manual shutter | ◐ needs `MANUAL_SENSOR` | ✓ | ? expected ✓ | S | ? | ? | iOS max duration depends on the active format |
| Exposure compensation | ✓ | ✓ | ? | S | ? | ? | |
| Aperture control | ◐ extremely rare (variable-aperture devices only) | ✗ read-only `lensAperture` | ? (expected fixed) | S (fixed) | ? (expected fixed) | fixed per lens | **Display only** on almost all phones |
| Autofocus / tap-to-focus | ✓ | ✓ | ? | S | ? | ? | |
| Manual focus | ◐ `MINIMUM_FOCUS_DISTANCE > 0` | ✓ `lensPosition` 0–1 | ? | S | ? | ? | Distance labels only if calibration is `CALIBRATED`/`APPROXIMATE` |
| WB presets | ✓ | ◐ via gains | ? | S | ? | ? | iOS presets are implemented as Kelvin → gains |
| WB Kelvin | ◐ needs `MANUAL_POST_PROCESSING` | ✓ temperature/tint → gains | ? expected ✓ | S | ? | ? | |
| Physical lens selection | ◐ physical IDs of logical multi-camera; OEMs may hide | ✓ discrete physical devices | ? (logical camera supported on API 30+) | S (one synthetic lens, optional second) | ? | ✓ (0.5×, 1×, 2.5×) expected | |
| Focal length reporting | ✓ | ✓ | ? | S | ? | ? | 35 mm-eq computed from sensor size |
| Flash / torch | ✓ | ✓ | ? | ✗ | ? | ? | |
| RAW (DNG) | ◐ needs `RAW` capability | ✓ Bayer RAW; ProRAW on Pro models | ? expected ✓ (API 30+) | ✗ | ? | ✓ ProRAW expected | RAW is Post (CAM-047) |
| HEIF output | ◐ | ✓ | ? | S | ? | ✓ | JPEG is the universal fallback |
| HDR / enhancement | ◐ CameraX Extensions (OEM) | ◐ automatic | ✗ expected | ✗ | ? | ? | Post (CAM-045) |
| Hardware level | LEGACY / LIMITED / FULL / LEVEL_3 | — | ? (recorded by S1) | — | ? | — | |

## Video and motion

| Capability | Android API-level | iOS API-level | Android Emulator | iOS Simulator | Honor X9c | iPhone 12 Pro Max | Notes |
|---|---|---|---|---|---|---|---|
| Video resolutions / fps | ✓ per device | ✓ per format | ? | S | ? | 4K60 expected | P8 |
| Stabilization | ◐ | ✓ | ? (emulated stabilization, API 30+) | ✗ | ? | ? | |
| Native Live Photo capture | ✗ (no public API) | ✓ | — | ✗ | — | ? | Both platforms use the ring-buffer design; native Live Photo is optional (FV-004) |
| Audio input | ✓ | ✓ | ◐ host mic locally, silent in CI → synthetic tone in tests | ◐ synthetic tone in tests | ? | ? | |
| H.264 / HEVC encode | ✓ / ◐ | ✓ | ? (software codecs) | ? | ? | ✓ | |

## System

| Capability | Android | iOS | Emulator/Simulator | Notes |
|---|---|---|---|---|
| Background uploads after app kill | ✓ WorkManager / UIDT (OEM battery managers may delay) | ✓ background URLSession | ✓ emulator · ◐ Simulator (background sessions are limited) | S4; OEM behavior FV-005 |
| Background processing (rendering) | ◐ WorkManager | ◐ BGProcessingTask | ✓ / ◐ | Rendering happens in the foreground at capture |
| Secure token storage | ✓ Keystore | ✓ Keychain | ✓ | |

## Quirks log

| Date | Device | Quirk | Handling |
|---|---|---|---|
| 2026-11-14 | iOS (design) | The iOS plugin offers manual focus only when `isLockingFocusWithCustomLensPositionSupported` **and** `minimumFocusDistance` is known (it is -1 when unknown); the range is diopters and is always `uncalibrated` | Capability probe; the app hides the control otherwise |
| 2026-11-14 | iOS (design) | Photo stabilization cannot be controlled on iOS; the system decides | `stabilization.photo` is empty |
| 2026-11-14 | iOS (design) | The Live pre-roll copies frames to a private pool because the camera's own buffer pool is tiny (holding its buffers makes it drop frames) | 15 fps, 960 px long edge, about 2 s; clips are lower resolution than stills (FV-012) |
| 2026-11-14 | iOS (design) | `AVCapturePhotoOutput` exposes RAW only with a processed companion for rendering | DNG capture requests `rawPixelFormatType` plus a JPEG |
