# Research: Motion Memory (Live Photo–style) Capture

Status: Living · Researched: 2026-09-30 · Related: ADR-0005, [media.md](../specs/media.md), [spikes.md](spikes.md)

---

### R-MOT-1 — Apple Live Photo capture API
- **Source:** Apple AVFoundation documentation for `AVCapturePhotoOutput.isLivePhotoCaptureSupported`, `isLivePhotoCaptureEnabled`, `AVCapturePhotoSettings.livePhotoMovieFileURL`, and the `didFinishRecordingLivePhotoMovieForEventualFileAt` / `didFinishProcessingLivePhotoToMovieFileAt` delegate callbacks.
- **Date:** 2026-09-30
- **Finding:** The system maintains the pre-capture buffer and delivers a short MOV (≈1.5 s before and after) with audio, paired to the still by an asset identifier. The still and the movie are delivered as separate files.
- **Confidence:** High (API) · unverified whether custom exposure mode or our preview grading pipeline coexists with Live Photo capture on the same session
- **Implication:** On iOS the cheapest path is to use native Live Photo capture as the **source** and repackage it into our Motion Memory representation.
- **Action:** Part of S3-iOS (blocked: needs macOS). The fallback is a custom ring buffer similar to Android's.

### R-MOT-2 — No Android public equivalent; Motion Photo is a format
- **Source:** Android developer documentation (CameraX / Camera2 APIs); Google "Motion Photo" format documentation (JPEG/HEIC with an embedded MP4 via XMP container metadata).
- **Date:** 2026-09-30
- **Finding:** There is no public Android API for pre-shutter video buffering. OEM camera apps implement it privately. Motion Photo defines only the file container, not capture.
- **Confidence:** High
- **Implication:** Android needs a custom implementation: continuous hardware encoding of a preview-size stream into a time-bounded ring buffer of encoded samples, plus an audio ring buffer, muxed around the shutter time.
- **Action:** S3 (highest-risk spike).

### R-MOT-3 — Ring buffer design considerations (Android)
- **Source:** Android `MediaCodec`, `MediaMuxer`, and `AudioRecord` documentation; CameraX `CameraEffect`/`SurfaceProcessor` and Camera2 multi-surface sessions.
- **Date:** 2026-09-30
- **Finding / design notes:**
  - Encode H.264 or HEVC at ≤1080p and 30 fps with a **1 s keyframe interval**, so the buffer can start the clip on a keyframe ≤1 s before the target pre-roll.
  - Keep encoded samples (not raw frames) in memory. Encoded data runs at roughly 1–2 MB/s at 1080p (to be measured), versus hundreds of MB/s raw.
  - Audio: `AudioRecord` PCM → AAC encoder → a separate sample ring buffer, timestamped on the same monotonic clock as video (`SENSOR_TIMESTAMP` / `System.nanoTime` base).
  - On shutter: snapshot the buffer from the nearest keyframe at or before T−pre, continue encoding for `post`, then mux to MP4 with `MediaMuxer`.
  - Surface sharing: CameraX may not allow Preview + ImageCapture + an extra encoder surface on LIMITED devices (stream-combination limits). A Camera2 fallback or sharing the preview stream through `SurfaceProcessor` may be required.
- **Confidence:** Medium (design), unverified on the Honor
- **Implication:** Feasible in principle. The risks are stream-combination limits, battery, thermals, and A/V sync.
- **Action:** S3 measures memory, battery drain per minute with LIVE on, thermal state after 10 minutes, and A/V offset (clap test).

### R-MOT-4 — Representation choice
- **Source:** Analysis (this project).
- **Date:** 2026-09-30
- **Finding:** Copying Apple's format (paired HEIC + MOV with a content identifier) or Google's (a single file with an embedded MP4) would tie cloud and web handling to one vendor's format. A platform-neutral model (still asset + clip asset + manifest) maps onto both and plays everywhere.
- **Confidence:** High
- **Implication:** ADR-0005. Vendor formats become export targets (MOT-008, Future).
- **Action:** Implement the representation defined in [media.md](../specs/media.md).
