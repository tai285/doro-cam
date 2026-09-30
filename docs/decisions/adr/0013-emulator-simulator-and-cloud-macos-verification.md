# ADR-0013: Verification on emulators, simulators and cloud macOS

Status: Accepted
Date: 2026-09-30
Related: NFR-009, NFR-010, NFR-014, NFR-015, NFR-016, ADR-0001, ADR-0002, [testing-strategy.md](../../development/testing-strategy.md), [testing-infrastructure.md](../../research/testing-infrastructure.md)

## Context

The owner develops on Windows with no Mac. Implementation will be done by coding agents that cannot operate physical phones. The owner requires a **full automated test suite**: every function and feature tested, and everything verified by the agents themselves. The owner has an iPhone 12 Pro Max and a Honor X9c, but neither can be driven by an agent.

Facts ([testing-infrastructure.md](../../research/testing-infrastructure.md)):
- The Android Emulator (Android 11+ images) has an emulated camera HAL advertising advanced capabilities (RAW, YUV reprocessing, Level 3, logical cameras). It runs on Windows via the Windows Hypervisor Platform, and on GitHub's Linux runners with KVM.
- The iOS Simulator has **no camera**: `AVCaptureDevice` discovery returns nothing.
- iOS builds need macOS. Free options: GitHub Actions macOS runners (about 200 free macOS minutes a month on a private repo, because macOS minutes count 10×), and Codemagic (500 free macOS minutes a month for a personal account).

## Decision

1. **The emulator and simulator are the primary verification targets.** A task is `done` when its acceptance criteria are verified by automated tests on the platforms available to agents:
   - host tests (Dart VM, JVM, Node);
   - Android Emulator instrumentation and `integration_test` runs;
   - iOS Simulator runs on cloud macOS.
2. **Android:** develop and test against Android Emulator AVDs, locally on Windows and in CI on Linux runners. The AVD matrix is defined in [testing-strategy.md](../../development/testing-strategy.md). The emulated camera exercises the real CameraX and Camera2 code paths, including manual sensor keys and applied values read back from capture results.
3. **iOS:** there is no local Mac. All iOS builds and tests run on **cloud macOS**: GitHub Actions `macos-*` runners are primary, and Codemagic is the overflow when the GitHub minutes run out. iOS work proceeds **in parallel** with Android and is no longer blocked. Agents trigger and read these runs with `gh`.
4. **iOS camera testability:** because the Simulator has no camera, the Swift camera code is written behind protocols (`CaptureDeviceProviding`, `CaptureSessionControlling`) so every piece of logic is unit-tested with fakes in XCTest. The plugin also ships a **synthetic camera source** for testing:
   - It is compiled only into debug and test builds (Swift `#if DOROCAM_SYNTHETIC_CAMERA`; the Android equivalent lives in a debug source set).
   - It generates deterministic frames (a test pattern with a frame counter and timestamp), so preview, capture, rendering, and motion pipelines can run end to end on the Simulator.
   - It reports itself as `source: synthetic`. Release builds cannot contain it, and a CI check verifies this.
   This is test infrastructure, not faked hardware, so it doesn't conflict with ADR-0002.
5. **Real devices are optional field validation.** Hardware-only facts (image quality, real sensor response, OEM quirks, performance, thermals, battery, microphone acoustics) are logged in [field-verification.md](../../development/field-verification.md). They never block a task. Whenever someone runs them on a real phone, the results update the capability matrix.
6. **Full test suite:** every function and feature gets automated tests, with coverage gates enforced in CI, and every MVP requirement is traceable to at least one automated test (NFR-014, NFR-015).

## Alternatives

- **Block iOS until a Mac is bought:** delays parity. Rejected by the owner.
- **Paid device farms (Firebase Test Lab, BrowserStack):** real hardware coverage, but billed. Kept as a later option for field validation.
- **Rely on manual device testing:** agents can't perform it, and it doesn't scale.
- **Third-party simulator camera tools (CMIOExtension virtual cameras):** need host-level installation on the Mac. That isn't possible on ephemeral CI runners. The synthetic source achieves the same testability inside our code.

## Consequences

- Agents can verify nearly all behavior on their own. The remaining hardware risk is explicit and tracked, not hidden.
- Performance numbers (NFR-003, NFR-004) and image-quality parity measured on emulators are **not** representative. Emulators verify correctness only. Budgets are set from field measurements when available; until then, the architecture uses the lower-risk native GPU path.
- **CI minutes are the scarce resource.** iOS jobs are path-filtered and use caching. The owner may make the repo public, which gives unlimited standard runners, or rely on Codemagic.
- Installing builds on the owner's iPhone needs signing. TestFlight requires the Apple Developer Program, an owner decision. The Honor can sideload debug APKs directly.
- Revisit if a Mac becomes available (local iteration gets faster) or if CI costs become a problem.
