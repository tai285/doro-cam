# Research: Emulators, Simulators and Cloud macOS

Status: Living · Researched: 2026-09-30 · Related: ADR-0013, [testing-strategy.md](../development/testing-strategy.md)

Format for each finding: **Source · Date · Finding · Confidence · Implication · Action**.

---

### R-TST-1 — Android Emulator camera capabilities
- **Source:** Android Studio docs "Camera support" (https://developer.android.com/studio/run/emulator-use-camera); AOSP camera HAL documentation (https://source.android.com/docs/core/camera/camera3).
- **Date:** 2026-09-30
- **Finding:**
  - On Android 11+ system images, the emulator camera supports RAW capture, YUV reprocessing, Level 3 devices, logical cameras, concurrent cameras, and sensor-orientation emulation.
  - The back camera can show a virtual 3D scene with importable images. A host webcam can also be mapped.
  - FULL/LEVEL_3 hardware levels imply `MANUAL_SENSOR` and `MANUAL_POST_PROCESSING`.
- **Confidence:** High (documented) · Medium (the exact characteristics our AVDs report still need a dump, done by SPK-T-001)
- **Implication:** Our CameraX + Camera2 interop code (capability probe, manual keys, applied-value readback, RAW, logical and physical cameras) can be exercised in automated tests. Image content is synthetic, so no image-quality conclusions are possible.
- **Action:** Use the emulator as the primary Android verification target (ADR-0013). SPK-T-001 records the emulator's actual characteristics in the capability matrix.

### R-TST-2 — iOS Simulator has no camera
- **Source:** Community documentation and tools confirming `AVCaptureDevice` returns nil in the Simulator (e.g. RocketSim "iOS Simulator Camera" https://www.rocketsim.app/blog/ios-simulator-camera/; SimulatorCamera https://github.com/dautovri/SimulatorCamera, which works around it with a macOS CMIOExtension virtual camera).
- **Date:** 2026-09-30
- **Finding:** The Simulator exposes no capture devices. Workarounds install a host-level virtual camera on the Mac, which isn't practical on ephemeral CI runners.
- **Confidence:** High
- **Implication:** iOS camera code needs protocol seams plus a synthetic source, compiled in debug and test builds only, for end-to-end tests.
- **Action:** ADR-0013 decision 4; tasks CAM-T-016 and FND-T-009.

### R-TST-3 — GitHub Actions macOS minutes
- **Source:** GitHub Actions billing summaries for 2026 (https://cicdcalculator.com/github-actions-free-tier; https://trimci.com/learn/github-actions-billing-explained/). Re-check GitHub's official billing docs before relying on the numbers.
- **Date:** 2026-09-30
- **Finding:**
  - Free plan, private repo: 2,000 included minutes a month. macOS minutes count 10×, so that's about 200 macOS minutes.
  - Overage costs about $0.062 per macOS minute.
  - Public repositories get free standard runners.
- **Confidence:** Medium (pricing changes)
- **Implication:** Roughly 15–20 iOS CI runs a month on a private repo. Linux minutes are shared with the Android emulator jobs.
- **Action:** Path-filter and cache iOS jobs. Use Codemagic for overflow. Owner decision: make the repo public or not.

### R-TST-4 — Codemagic free macOS minutes
- **Source:** Codemagic pricing docs (https://docs.codemagic.io/billing/pricing/).
- **Date:** 2026-09-30
- **Finding:** Personal accounts get 500 free macOS M2 minutes a month (not on Team accounts). It has Flutter-first tooling and integrates with GitHub.
- **Confidence:** Medium
- **Implication:** A practical secondary "cloud Mac" for iOS builds, simulator tests, and later TestFlight uploads.
- **Action:** FND-T-009 adds a `codemagic.yaml` equivalent of the iOS workflow. The owner connects the repo in the Codemagic UI (one-time).

### R-TST-5 — Android Emulator on Windows and CI
- **Source:** Android Studio emulator acceleration docs (Windows Hypervisor Platform); `reactivecircus/android-emulator-runner` GitHub Action (KVM-accelerated emulators on `ubuntu-latest`). Local check on 2026-09-30: an i5-12450H with 16 GB RAM, with a hypervisor present (WSL2/Docker Desktop).
- **Date:** 2026-09-30
- **Finding:** With Hyper-V/WSL2 active, the emulator must use the Windows Hypervisor Platform (WHPX). Enabling that optional feature needs administrator rights once. GitHub Linux runners support KVM-accelerated emulators.
- **Confidence:** High (docs) · unverified locally until the SDK is installed
- **Implication:** Agents can run the emulator locally and in CI. 16 GB RAM supports one emulator plus the Docker stack; don't run two emulators at once locally.
- **Action:** FND-T-008. If WHPX is disabled, the agent asks the owner to enable "Windows Hypervisor Platform" (an admin action).

### R-TST-6 — Measured: iOS Simulator CI on GitHub Actions (first real runs)
- **Source:** our own `ios.yml` runs on 2026-09-30 (run 36754993639 succeeded).
- **Date:** 2026-09-30
- **Finding:**
  - `macos-15` provides Xcode 16.4 and iOS 18.5/18.6 and 26.x simulator runtimes, but **no iPhone 12 Pro Max device type** (only newer iPhones). `scripts/ios-simulator.sh` picks the closest (iPhone 16 Pro Max).
  - A full run takes **about 9 minutes**: Flutter setup 1.5 min, `flutter build ios --simulator` 1.5 min, simulator boot 1.2 min, integration test 3.8 min.
  - **The first attempt hung for 42 minutes** in `flutter test integration_test` when the script chose the newest runtime (iOS 26.2), which is newer than Xcode 16.4's SDK. Choosing the iOS 18.6 runtime fixed it. Lesson: keep the simulator runtime in step with the runner's Xcode.
  - The repository was made public the same day, so the macOS minutes are free.
- **Confidence:** High (observed)
- **Implication:** iOS verification feedback takes about 9 minutes, so batch iOS-affecting changes and rely on the Linux and emulator jobs for fast feedback.
- **Flakiness:** one later run (with the native plugin, run 36762738387) stalled at "Waiting for VM Service port to be available..." and hit the step timeout, although a launch-diagnostics step on the next run showed the app starting normally and the tests then passed (run 36765907244). The cause is unexplained. Treat a single iOS stall as a flake and rerun (`gh run rerun <id> --failed`), but investigate if it repeats.
- **Action:** ios.yml has a 10-minute timeout on the integration step, a launch-diagnostics step before it (app console, process state, system log, crash reports), and dumps simulator logs on failure. To test the newest iOS, add a nightly job on a `macos-26` runner with Xcode 26 rather than forcing a new runtime onto Xcode 16.
