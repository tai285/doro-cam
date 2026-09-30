# Technical Spikes

Status: Living · Last updated: 2026-09-30 · Related: [roadmap.md](../product/roadmap.md) P0, SPK tasks in [phase-0-foundation.md](../tasks/phase-0-foundation.md), ADR-0013

Spikes answer feasibility questions **before** architecture is locked in. Rules:
- Spike code lives in `spikes/<id>-<slug>/` and is **never imported by production code**. Measurement tooling written for a spike (dump scripts, analyzers, harnesses) **has its own tests**, because it produces the evidence decisions rely on.
- Experiments run on the **Android Emulator** and the **iOS Simulator on cloud macOS** so agents can execute them (ADR-0013). Hardware-only questions are split into field-verification entries (FV-xxx in [field-verification.md](../development/field-verification.md)) and don't block the spike.
- Every spike ends with a **Result** section here, and updates to the capability matrix, specs, and ADRs as needed.
- A spike that disproves a hypothesis is a success. Record it honestly.

---

## S1 — Manual camera control code paths
- **Question:** Do our CameraX + Camera2 interop manual controls (ISO, shutter, EV, focus, WB Kelvin, logical/physical lenses) work end to end, with applied values read back? What does the emulated camera report?
- **Hypothesis:** The API 35 emulator's emulated HAL reports FULL or LEVEL_3 with `MANUAL_SENSOR`, and applied values track requested values.
- **Experiment:** An instrumented test app on the emulator that:
  - dumps all `CameraCharacteristics` (every camera and physical ID) to JSON;
  - captures with a sweep of requested values per control and records `TotalCaptureResult` values.
  On iOS: an XCTest suite on the Simulator exercising the exposure/focus/WB apply logic against fake `AVCaptureDevice` protocols with realistic iPhone 12 Pro Max format ranges.
- **Success criteria:** the characteristics dump is committed; requested vs applied is recorded for at least 5 values per control; the dump tool's parser has unit tests.
- **Failure implications:** if the emulator lacks `MANUAL_SENSOR`, instrumentation tests of manual paths use a different system image or a Camera2 test double, and the capability matrix records it.
- **Field verification:** FV-001 (Honor), FV-002 (iPhone).
- **Result:** *pending*

## S2 — Real-time profile preview pipeline
- **Question:** Which preview grading pipeline is **correct and maintainable**: native GL via CameraX `CameraEffect` (Metal/Core Image on iOS), or Flutter `ImageFilter.shader`?
- **Hypothesis:** Native GPU grading produces output that matches the reference renderer and integrates with capture and video. The Flutter shader path works for preview only.
- **Experiment:** Implement both on the emulator (and the native iOS path on the Simulator with the synthetic source). Compare rendered frames against the reference renderer for a test-pattern input. Record emulator fps as indicative only.
- **Success criteria:** both pipelines produce frames within parity tolerance; a decision is recorded with rationale.
- **Default if inconclusive:** native GPU (architecture/camera.md option A), since it's also needed for video.
- **Field verification:** FV-003 (≥ 30 fps on real devices).
- **Result:** *pending*

## S3 — Motion capture (still + motion + audio)
- **Question:** Can our ring buffer produce a ~3 s clip (≈1.5 s pre, 1.5 s post) with audio, synced and aligned to the still, alongside still capture?
- **Hypothesis:** A hardware or software encoder fed from a shared preview surface, with encoded-sample ring buffers for video and AAC audio and a muxer at the shutter, works within stream-combination limits.
- **Experiment:** On the emulator (and the Simulator with the synthetic source), feed a **synthetic A/V source**: a white flash frame and a 1 kHz beep at the same known timestamps. Record 20 captures, then demux and measure the A/V offset and the still-to-key-frame alignment automatically. Measure memory usage.
- **Success criteria:** A/V offset ≤ 45 ms and key-frame alignment within 1 frame in ≥ 19/20 runs; no crash across 100 captures. The offset analyzer has unit tests on generated media.
- **Failure implications:** Fallback A is post-roll-only motion; Fallback B is reduced pre-roll or resolution. ADR-0005 is revised accordingly.
- **Field verification:** FV-004 (real microphone clap test, battery, thermals).
- **Result:** *pending*

## S4 — Background, resumable multipart uploads
- **Question:** Do per-part presigned PUT uploads via `background_downloader` complete reliably through network loss and app kills?
- **Hypothesis:** Yes on the emulator. The iOS Simulator's background session support is partial, so foreground resume is verified there.
- **Experiment:** An automated emulator test uploads a 200 MB file in 8 MiB parts to the local Garage S3 (at `10.0.2.2:9000`). It toggles `svc wifi` and `svc data`, force-stops the app, cold-boots the emulator, and logs part timings.
- **Success criteria:** the upload always completes with the correct checksum, and no part is uploaded twice after its ETag was persisted.
- **Field verification:** FV-005 (MagicOS battery management).
- **Result:** *pending*

## S5 — Local queue durability
- **Question:** Does the drift-backed queue with atomic file writes survive kill -9 at any point during capture and upload without losing or duplicating Memories?
- **Hypothesis:** Yes, with WAL mode, temp-write → fsync → rename, and state persisted before side effects.
- **Experiment:** An automated kill-loop harness on the emulator (`adb shell am kill` at random delays) for 200 iterations, plus an integrity checker comparing DB rows, files, and server state.
- **Success criteria:** 0 lost captures, 0 orphan rows, 0 duplicate server assets; orphan temp files cleaned on the next start. The harness and checker have tests and are kept for P5 regression.
- **Result:** *pending*

## S6 — Worker video processing isolation
- **Question:** Can the worker transcode large videos (4K HEVC, ~2 GB) with ffmpeg without affecting API latency on the same host?
- **Hypothesis:** Yes, with a separate process, a Docker CPU limit, `nice`, and streaming I/O.
- **Experiment:** Load-test the API (autocannon) while the worker transcodes a generated 4K HEVC test file. Compare API p95 latency.
- **Success criteria:** API p95 degrades by < 20%; worker memory stays bounded.
- **Result:** *pending* (runs locally in Docker or in CI)

## S7 — LUT rendering parity
- **Question:** Do the reference renderer, ffmpeg `lut3d`, and the device GPU paths produce the same colors for a profile?
- **Hypothesis:** With the same LUT and tetrahedral interpolation, mean ΔE2000 ≤ 2.0.
- **Experiment:** Render fixture images through the TS reference renderer, ffmpeg (both interpolations), and the emulator and Simulator GPU paths. Compute ΔE2000 statistics.
- **Success criteria:** mean ≤ 2.0 and p95 ≤ 4.0; the ΔE2000 implementation is tested against published reference pairs.
- **Field verification:** FV-007 (real camera frames).
- **Result:** *pending*
