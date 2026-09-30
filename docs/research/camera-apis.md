# Research: Camera APIs (Flutter, Android, iOS)

Status: Living · Researched: 2026-09-30 · Related: ADR-0001, ADR-0002, [capability-matrix.md](../specs/capability-matrix.md), [spikes.md](spikes.md)

Format for each finding: **Source · Date · Finding · Confidence · Implication · Action**. Findings marked *unverified* have not been observed on our devices.

---

### R-CAM-1 — Official Flutter `camera` plugin lacks manual controls
- **Source:** flutter/flutter issue #73250 "[camera] ISO, Shutter Speed, Aperture" (https://github.com/flutter/flutter/issues/73250); pub.dev `camera` API docs.
- **Date:** 2026-09-30
- **Finding:** The official plugin exposes exposure mode, offset, focus mode and point, flash, zoom, and image streams. It does **not** expose manual ISO, exposure duration, Kelvin WB, manual focus distance, or physical lens selection. The feature request remains open.
- **Confidence:** High
- **Implication:** The official plugin can't meet CAM-010, CAM-011, CAM-021, CAM-031, or CAM-006.
- **Action:** Build the first-party `doro_camera` plugin (ADR-0001).

### R-CAM-2 — Community manual-camera forks are stale and Android-only
- **Source:** `manual_camera` fork (https://github.com/Afonsocraposo/manual_camera); `manual_camera_pro` on pub.dev (https://pub.dev/documentation/manual_camera_pro/latest/).
- **Date:** 2026-09-30
- **Finding:** They add ISO, shutter, focus, and WB presets on Android via Camera2. Their maintenance status and iOS support are weak, and they're based on old plugin versions.
- **Confidence:** Medium
- **Implication:** Not a foundation. Possibly a reference for Camera2 key usage.
- **Action:** Don't depend on them. Read them for reference only; check licenses before reusing any snippet.

### R-CAM-3 — CameraX manual exposure via Camera2 interop
- **Source:** CameraX release notes (https://developer.android.com/jetpack/androidx/releases/camera); camerax-developers group thread on manual exposure (https://groups.google.com/a/android.com/g/camerax-developers/c/jAuYkLc1wLg); community write-ups (2026).
- **Date:** 2026-09-30
- **Finding:** CameraX supports manual sensor control by injecting Camera2 request options: `CONTROL_AE_MODE_OFF`, `SENSOR_SENSITIVITY`, `SENSOR_EXPOSURE_TIME`, and `LENS_FOCUS_DISTANCE` with `CONTROL_AF_MODE_OFF`. Recent CameraX releases deprecated the legacy `Camera2Interop.Extender` / `Camera2CameraControl` in favor of configurator factory methods and Kotlin DSL `camera2Interop {}` blocks. Ranges come from `CameraCharacteristics`, which are available through `Camera2CameraInfo`.
- **Confidence:** High (API) · Low (behavior on the Honor X9c, unverified)
- **Implication:** CameraX remains the Android base (lifecycle, preview, capture, extensions). Manual keys go through interop. Manual control is usable only when the device reports `MANUAL_SENSOR`.
- **Action:** S1 verifies on the Honor X9c. The plugin must detect ignored keys by reading `TotalCaptureResult` (CAM-050).

### R-CAM-4 — Android hardware levels and OEM exposure
- **Source:** Android `CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL` and `REQUEST_AVAILABLE_CAPABILITIES` documentation; long-standing community experience.
- **Date:** 2026-09-30
- **Finding:** `LEGACY` and many `LIMITED` devices lack `MANUAL_SENSOR`. OEMs frequently hide ultra-wide and tele modules from third-party apps, or expose them only through a logical multi-camera with zoom-based switching.
- **Confidence:** High (general) · Unknown (Honor X9c)
- **Implication:** The capability-driven UI is mandatory, and the Honor might offer only auto exposure with compensation.
- **Action:** S1 records the hardware level and physical camera IDs. The owner is advised to add a Pixel as the Android reference device.

### R-CAM-5 — iOS AVFoundation manual controls
- **Source:** Apple AVFoundation documentation for `AVCaptureDevice` (`setExposureModeCustom(duration:iso:)`, `setFocusModeLocked(lensPosition:)`, `setWhiteBalanceModeLocked(with:)`, `deviceWhiteBalanceGains(for:)`, `lensAperture`).
- **Date:** 2026-09-30
- **Finding:** Custom exposure (duration + ISO within `activeFormat` limits), lens position 0–1, and WB gains (with temperature/tint conversion) are available on all modern iPhones. `lensAperture` is read-only. Virtual devices (dual/triple camera) switch physical lenses automatically; for precise manual control, bind a physical device (`builtInWideAngleCamera`, `builtInUltraWideCamera`, `builtInTelephotoCamera`).
- **Confidence:** High (documented API) · unverified on the iPhone 12 Pro Max (no Mac)
- **Implication:** iOS offers richer and more uniform manual control than Android. Aperture is display-only.
- **Action:** iOS implementation tasks are blocked until macOS is available. The contract is already platform-neutral.

### R-CAM-6 — RAW / ProRAW
- **Source:** Apple `AVCapturePhotoOutput.availableRawPhotoPixelFormatTypes`, Apple ProRAW (iOS 14.3+ on iPhone 12 Pro/Pro Max and later); Android `REQUEST_AVAILABLE_CAPABILITIES_RAW` + `DngCreator`.
- **Date:** 2026-09-30
- **Finding:** The iPhone 12 Pro Max supports ProRAW and Bayer RAW. Android RAW depends on the device.
- **Confidence:** High (iOS) · Unknown (Honor)
- **Implication:** RAW is Post (CAM-047). The capability model already includes RAW kinds.
- **Action:** None for the MVP.

### R-CAM-7 — Flutter platform integration mechanics
- **Source:** Flutter docs on platform channels, Pigeon, and `Texture`/`TextureRegistry`; flutter/flutter issue #114653 (Impeller external texture interop) (https://github.com/flutter/flutter/issues/114653).
- **Date:** 2026-09-30
- **Finding:** Pigeon generates type-safe Dart↔Kotlin/Swift bindings. Camera preview is delivered through `TextureRegistry` (Android `SurfaceProducer`, iOS `FlutterTexture` with `CVPixelBuffer`). Impeller supports external textures.
- **Confidence:** High
- **Implication:** The standard, supported path for a custom camera plugin.
- **Action:** ADR-0001.
