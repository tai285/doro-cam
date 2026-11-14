# Field Verification Log

Status: Living · Last updated: 2026-11-14 · Related: ADR-0013, [capability-matrix.md](../specs/capability-matrix.md)

Emulators and simulators verify **correctness**. Some facts can only come from real hardware, and one part of the product (iOS) can only be built on cloud macOS (ADR-0016). This log lists them so they are never silently assumed. Per ADR-0013, entries **do not block tasks**. They are run whenever a real device is available: the owner's Honor X9c or iPhone 12 Pro Max, or a device farm later.

When an entry is run, record the result, copy capability facts into [capability-matrix.md](../specs/capability-matrix.md), and open a fix task if behavior differs from the emulator.

## How to add an entry

Any task whose acceptance includes a hardware-only aspect adds a row here in the same change:

| ID | Source task | What to verify | Why it can't be emulated | Device(s) | Status | Result / date |
|---|---|---|---|---|---|---|

Status is `pending`, `pass`, `fail (task link)`, or `n/a`.

## Entries

| ID | Source task | What to verify | Why it can't be emulated | Device(s) | Status | Result / date |
|---|---|---|---|---|---|---|
| FV-001 | SPK-T-001 | Which manual controls the Honor X9c exposes and honours (hardware level, `MANUAL_SENSOR`, physical lenses) | OEM camera HAL behavior | Honor X9c | pending | — |
| FV-002 | SPK-T-001 | iPhone 12 Pro Max lens set and manual ranges | The Simulator has no camera | iPhone 12 Pro Max | pending | — |
| FV-003 | SPK-T-002 | Preview grading sustains ≥ 30 fps for 10 min (NFR-003) | Emulator GPU performance isn't representative | Honor X9c, iPhone | pending | — |
| FV-004 | SPK-T-003 | Motion clip A/V sync with a real microphone (clap test), plus battery and thermal cost of LIVE | Real audio path, battery, thermals | Honor X9c, iPhone | pending | — |
| FV-005 | SPK-T-004 | Background upload continues under MagicOS battery management after an app kill. The scheduler is `WorkmanagerBackgroundScheduler` (see FV-015) | OEM power management | Honor X9c | pending | — |
| FV-006 | CAM-T-005 | Shutter-to-saved latency baseline (NFR-004) | Real sensor pipeline timing | Honor X9c, iPhone | pending | — |
| FV-007 | SPK-T-007 | Preview vs capture color parity on real camera frames | Real sensor color | Honor X9c, iPhone | pending | — |
| FV-008 | iOS plugin | **iOS Swift plugin: build.** The whole `doro_camera` iOS implementation (AVFoundation engine, preview texture, Pigeon bridge) is written but has never been compiled. Verified only when `bash scripts/ios-ci.sh` (manual cloud macOS dispatch) builds it | No Mac; cloud macOS is manual-dispatch only (ADR-0016) | cloud macOS (`ios.yml`) | verified: cloud macOS run 43584089870 (commit 74ddd8c, Xcode 26.3) builds the plugin and app for the iOS 18.6 Simulator and the release build excludes the synthetic camera | — |
| FV-009 | iOS plugin | **iOS Swift core tests.** `DoroCameraCore` XCTests (capability probe, settings clamp, session state machine, motion ring buffer and clip planner, atomic output, still renderer with real CoreImage pixels, synthetic source) pass under `swift test` | No Mac | cloud macOS (`ios.yml` core job) | verified: `swift test` core job passes in run 43584089870 | — |
| FV-010 | iOS plugin | **iOS Simulator end to end** with the synthetic camera: preview texture, capture to Memory, Motion clip with audio/video sync (flash and beep), video recording, interruptions | The Simulator has no camera; the synthetic source stands in | cloud macOS (`ios.yml` simulator job) | partly verified: Simulator integration tests pass in run 43584089870 (synthetic camera listed, still capture, capture flow, smoke); preview texture, Motion clip A/V sync and video recording on the Simulator are not asserted there yet | — |
| FV-011 | iOS plugin | Real iPhone: manual ISO/shutter/focus/white balance honoured and reported, lens switching, HEIC/DNG capture, GPS in EXIF only when enabled, interruptions (call, another app), thermal behaviour of the Live buffer | Real camera pipeline | iPhone 12 Pro Max | pending | — |
| FV-012 | iOS plugin | Motion clip quality and memory: the Live buffer keeps about 2 s of frames at 15 fps and 960 px long edge (about 60 MB), so clips are lower resolution than the stills. Check memory pressure and clip quality on a real device | Real memory limits and encoder | iPhone 12 Pro Max | pending | — |
| FV-013 | full-stack scenario | The Android app against the API over a real network: TLS, mobile data and flaky links, a public hostname instead of `10.0.2.2` and loopback storage, uploads of full-size originals and long Motion clips | The scenario runs the emulator against the same machine over plain HTTP with tiny synthetic media | Honor X9c, a deployed API | pending | — |
| FV-014 | full-stack scenario | The same scenario with the iOS app (sign-up, photo, Motion Memory, back-up, web dashboard) | No Mac; `ios.yml` does not run the stack | iPhone 12 Pro Max, cloud macOS | pending: not run | — |
| FV-015 | background sync scheduler | **Android background passes on a real phone.** Queue a Memory, kill the app, and check that WorkManager starts `runBackgroundSyncPass` (the periodic `doro.sync.periodic` every ~30 min and the `doro.sync.wakeup` one-off) and the upload completes; that it waits for Wi-Fi while "Upload on Wi-Fi only" is on and runs on mobile data when it is off; that it holds off below the low-battery level; and that a pass started while the app is open does not hit "database is locked" (two isolates share the SQLite file; `busy_timeout` is 5 s) or upload the same asset twice | WorkManager timing, Doze, app standby buckets and OEM battery managers are not reproduced by the emulator; the Dart side is only unit-tested against a fake scheduler | Honor X9c | pending | — |
| FV-016 | background sync scheduler | **iOS background refresh.** `AppDelegate.swift` (`WorkmanagerPlugin.registerPeriodicTask`) and the `BGTaskSchedulerPermittedIdentifiers` / `UIBackgroundModes` entries in `Info.plist` have never been compiled or run. Verify the build, that the `doro.sync.periodic` refresh task is granted by the system, and that a pass completes within iOS's time limit (it may be cut short; the queue resumes from persisted state) | No Mac (ADR-0016); iOS decides when background refresh runs and the Simulator does not reproduce it | iPhone 12 Pro Max, cloud macOS for the build | pending: not built or run | — |

## Installing builds on the owner's devices

- **Honor X9c:** build a debug APK locally in WSL (`cd apps/mobile && flutter build apk --debug`) and install it with `adb install` or by opening the APK.
- **iPhone 12 Pro Max:** needs a signed build. TestFlight requires the Apple Developer Program (an owner decision). Until then, iPhone entries stay `pending`.
