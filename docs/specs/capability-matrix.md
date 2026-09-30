# Capability Matrix

Status: Living · Last updated: 2026-09-30 · Related: CAM-004, CAM-005, ADR-0002, [camera-apis.md](../research/camera-apis.md), [spikes.md](../research/spikes.md)

This matrix makes platform limits explicit. It has **two kinds of columns**:
- **API-level:** what the platform API can expose on *some* devices (from documentation research).
- **Verified:** what we observed on a real device, filled in by spikes and on-device tests.

Legend: ✓ available · ◐ device-dependent / partial · ✗ not available · ? not yet verified · — not applicable

The app never reads this table at runtime. It probes capabilities (ADR-0002). This table is for planning and for spotting quirks.

## Photo controls

| Capability | Android API-level | iOS API-level | Honor X9c (verified) | iPhone 12 Pro Max (verified) | Notes |
|---|---|---|---|---|---|
| Manual ISO | ◐ needs `MANUAL_SENSOR` | ✓ custom exposure | ? | ? (needs macOS) | Many mid-range Android devices report LIMITED |
| Manual shutter | ◐ needs `MANUAL_SENSOR` | ✓ | ? | ? | iOS max duration depends on the active format |
| Exposure compensation | ✓ | ✓ | ? | ? | |
| Aperture control | ◐ extremely rare (variable-aperture devices only) | ✗ read-only `lensAperture` | ? (expected fixed) | fixed per lens | **Display only** on almost all phones |
| Autofocus / tap-to-focus | ✓ | ✓ | ? | ? | |
| Manual focus | ◐ `MINIMUM_FOCUS_DISTANCE > 0` | ✓ `lensPosition` 0–1 | ? | ? | Distance labels only if calibration is `CALIBRATED`/`APPROXIMATE` (Android); iOS lensPosition is unitless |
| WB presets | ✓ | ◐ via gains (no named presets API) | ? | ? | iOS presets are implemented as Kelvin → gains |
| WB Kelvin | ◐ needs `MANUAL_POST_PROCESSING` | ✓ temperature/tint → gains | ? | ? | |
| Physical lens selection | ◐ physical IDs of logical multi-camera; OEMs may hide | ✓ discrete physical devices | ? | ✓ (0.5×, 1×, 2.5×) expected | OEMs often hide ultra-wide/tele from third-party apps |
| Focal length reporting | ✓ `LENS_INFO_AVAILABLE_FOCAL_LENGTHS` | ✓ via format FOV / device type | ? | ? | 35 mm-eq computed from sensor size |
| Optical zoom steps | ◐ | ✓ virtual device switch-over factors | ? | ? | |
| Flash / torch | ✓ | ✓ | ? | ? | |
| RAW (DNG) | ◐ needs `RAW` capability | ✓ Bayer RAW; ProRAW on Pro models (iOS 14.3+) | ? | ✓ ProRAW expected | RAW is Post (CAM-047) |
| HEIF output | ◐ CameraX 1.5+ / device encoder | ✓ | ? | ✓ | JPEG is the universal fallback |
| HDR / enhancement | ◐ CameraX Extensions (OEM) | ◐ smart HDR automatic | ? | ? | Post (CAM-045) |
| Hardware level | LEGACY / LIMITED / FULL / LEVEL_3 | — | ? | — | Recorded by S1 |

## Video and motion

| Capability | Android API-level | iOS API-level | Honor X9c | iPhone 12 Pro Max | Notes |
|---|---|---|---|---|---|
| Video resolutions / fps | ✓ per device | ✓ per format | ? | 4K60 expected | P8 |
| Manual exposure during video | ◐ | ✓ | ? | ? | P8 |
| Stabilization | ◐ `CONTROL_VIDEO_STABILIZATION_MODE`, OIS | ✓ standard/cinematic | ? | ? | |
| Native Live Photo capture | ✗ (no public API) | ✓ `livePhotoCaptureEnabled` | — | ? | Android uses a custom ring buffer (S3) |
| Audio capture during preview buffer | ✓ AudioRecord | ✓ | ? | ? | Microphone privacy indicator shows while LIVE is on |
| HEVC encode | ◐ | ✓ | ? | ✓ | H.264 fallback |

## System

| Capability | Android | iOS | Notes |
|---|---|---|---|
| Background uploads after app kill | ✓ WorkManager / UIDT (OEM battery managers may delay) | ✓ background URLSession (file-based, system-scheduled) | S4 |
| Background processing (rendering) | ◐ WorkManager | ◐ BGProcessingTask (opportunistic) | Rendering happens in the foreground at capture |
| Secure token storage | ✓ Keystore | ✓ Keychain | |

## Quirks log

| Date | Device | Quirk | Handling |
|---|---|---|---|
| — | — | (none recorded yet; spikes S1–S3 fill this) | — |
