# Technical Spikes

Status: Living · Last updated: 2026-09-30 · Related: [roadmap.md](../product/roadmap.md) P0, SPK tasks in [phase-0-foundation.md](../tasks/phase-0-foundation.md)

Spikes answer feasibility questions **before** architecture is locked in. Rules:
- Spike code lives in `spikes/<id>-<slug>/` and is **never imported by production code**. When a spike ends, its code is deleted or kept only as reference, and its README records how to rerun it.
- Every spike ends with a **Result** section here, and updates to the capability matrix, specs, and ADRs as needed.
- A spike that disproves a hypothesis is a success. Record it honestly.

---

## S1 — Manual camera controls on real devices
- **Question:** Which manual controls (ISO, shutter, EV, focus, WB Kelvin, physical lenses) are exposed **and actually honoured** on the reference devices?
- **Hypothesis:** The Honor X9c reports at least `LIMITED` with EV and AF controls, but possibly no `MANUAL_SENSOR`. The ultra-wide may be hidden from third-party apps. (iPhone: full custom exposure; verified later.)
- **Experiment:** A minimal Android app (Kotlin, CameraX + Camera2 interop) that dumps all relevant `CameraCharacteristics` for every camera ID (including physical IDs), then for each manual control captures frames with a set of requested values and records `TotalCaptureResult` values plus image brightness.
- **Success criteria:** A complete characteristics dump is committed. For each control, "requested vs applied" is recorded over at least 5 values.
- **Failure implications:** If the Honor lacks `MANUAL_SENSOR`, the MVP manual mode on it is limited to EV, AE/AF lock, WB presets, and lens/zoom. The owner should acquire a Pixel to validate the full manual path. The architecture is unchanged (capabilities already drive the UI).
- **Result:** *pending*

## S2 — Real-time profile preview performance
- **Question:** Can we grade the live preview with a 3D LUT + grain + vignette at ≥ 30 fps on the Honor X9c, and which pipeline should we use?
- **Hypothesis:** Native GLES via CameraX `CameraEffect` sustains 30 fps at 1080p. The Flutter `ImageFilter.shader` path may drop frames or add latency.
- **Experiment:** Implement both pipelines in a spike app with the same 33³ LUT and grain shader. Measure fps (frame timing API), added latency (a phone photographing a millisecond clock), GPU/CPU load, and battery drain over 10 minutes.
- **Success criteria:** ≥ 30 fps sustained for 10 minutes without thermal throttling beyond `fair`. Added latency is noted for comparison.
- **Failure implications:** If neither meets the bar: reduce the preview resolution for grading, or apply grain only at capture. Update NFR-003 with the owner.
- **Result:** *pending*

## S3 — Motion capture (still + motion + audio)
- **Question:** Can Android produce a ~3 s clip (≈1.5 s pre, 1.5 s post) with audio, synced and aligned to the still, alongside normal still capture?
- **Hypothesis:** A MediaCodec encoder fed from a shared preview surface, with encoded-sample ring buffers for video and AAC audio and MediaMuxer on shutter, works on the Honor within stream-combination limits. It uses < 50 MB of extra memory, and its battery cost is acceptable. (The memory figure is a hypothesis to measure, not a requirement.)
- **Experiment:** A spike implementation plus a clap test (20 captures) measuring A/V offset and still-to-clip key-frame alignment; battery drain per 10 minutes with LIVE on vs off; thermal state.
- **Success criteria:** A/V offset ≤ 45 ms and key-frame alignment within 1 frame in ≥ 19/20 captures; still capture quality unaffected; no crash across 100 captures.
- **Failure implications:** Fallback A: post-roll-only motion (start recording at the shutter). Fallback B: reduced pre-roll or lower resolution. ADR-0005 is revised accordingly. The iOS equivalent (native Live Photo) runs when macOS is available.
- **Result:** *pending*

## S4 — Background, resumable multipart uploads
- **Question:** Do per-part presigned PUT uploads via `background_downloader` complete reliably through network loss and app kills, including under MagicOS battery management?
- **Hypothesis:** Yes on Android with the app in the foreground or recently backgrounded. OEM battery management may delay (but not lose) work after a kill.
- **Experiment:** A spike Flutter app uploading a 200 MB file in 8 MiB parts to MinIO (then R2 if chosen), with airplane-mode toggles, force-stops, and reboots, logging part timings.
- **Success criteria:** The upload always eventually completes with the correct checksum, and no part is uploaded twice after its ETag was persisted.
- **Failure implications:** Rely on foreground uploads plus user guidance (battery optimization exemption prompt) on affected OEMs. Consider a different transport. The protocol is unchanged.
- **Result:** *pending*

## S5 — Local queue durability
- **Question:** Does the drift-backed queue with atomic file writes survive kill -9 at any point during capture and upload, without losing or duplicating Memories?
- **Hypothesis:** Yes, with WAL mode, a temp-write → fsync → rename file strategy, and state persisted before side effects.
- **Experiment:** An automated kill-loop test on the device: script adb to kill the app at random delays during capture and upload for 200 iterations, then run an integrity check (DB rows ↔ files ↔ server state).
- **Success criteria:** 0 lost captures, 0 orphan DB rows, 0 duplicate server assets. Orphan temp files are cleaned up on the next start.
- **Failure implications:** Revisit the write ordering or the persistence choice (ADR-0009).
- **Result:** *pending*

## S6 — Worker video processing isolation
- **Question:** Can the worker transcode large videos (4K HEVC, ~2 GB) with ffmpeg without affecting API latency on the same host?
- **Hypothesis:** Yes, when the worker runs as a separate process with a CPU limit (Docker `cpus`) and ffmpeg runs at `nice` priority. Streaming from storage avoids loading the file into memory.
- **Experiment:** Load-test API metadata endpoints (autocannon) while the worker transcodes the test file. Measure API p95 latency with and without the transcode.
- **Success criteria:** API p95 degrades by < 20% during the transcode. Worker memory stays bounded.
- **Failure implications:** Run the worker on a separate host or container group earlier than planned.
- **Result:** *pending* (can run on Windows with Docker; no device needed)

## S7 — LUT rendering parity
- **Question:** Do the device GPU preview, the device capture render, and the server (ffmpeg `lut3d`) produce the same colors for a profile?
- **Hypothesis:** With the same LUT and interpolation (tetrahedral where possible), the mean ΔE2000 is ≤ 2.0.
- **Experiment:** Render fixture images (a color chart + 3 natural images) through the TS reference renderer, ffmpeg `lut3d` (both interpolations), and on-device GPU. Compute ΔE2000 statistics.
- **Success criteria:** Mean ≤ 2.0 and p95 ≤ 4.0 against the reference renderer.
- **Failure implications:** Standardize the interpolation, increase the LUT size (65³), or adjust the parity thresholds in [image-profile.md](../specs/image-profile.md) with owner approval.
- **Result:** *pending*
