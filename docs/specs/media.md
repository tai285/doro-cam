# Spec: Media Formats and Motion Memory

Status: Draft (validated by spike S3) · Last updated: 2026-09-30 · Related: MOT-001–MOT-009, VID-001–VID-006, CAM-046, ADR-0005, [media-pipeline.md](../architecture/media-pipeline.md)

## Photo formats

| Asset | Format | Color | Metadata |
|---|---|---|---|
| `photo_original` | HEIF (preferred where supported), else JPEG; DNG when RAW (Post) | As captured (Display P3 or sRGB) | Platform EXIF as written by the camera stack; XMP `doro:memoryId`; GPS only if location is enabled |
| `photo_rendered` | JPEG, quality 92 | sRGB (MVP) | EXIF: orientation normalized to 1 (pixels rotated), DateTimeOriginal + OffsetTimeOriginal, Make/Model, lens and exposure fields; XMP `doro:memoryId`, `doro:profile` |
| `photo_display` | JPEG q85, long edge 2048 px | sRGB | Minimal EXIF, no GPS |
| `thumbnail` | JPEG q80, long edge 512 px | sRGB | No EXIF |

## Motion Memory (ADR-0005)

A Motion Memory is a Memory with `kind = motion` and one `motion_clip` asset.

### motion_clip
- Container: MP4 (Android) or MOV (iOS native Live Photo source). Both are accepted.
- Video: H.264 or HEVC. Resolution ≤ 1920 px long edge. 30 fps target.
- Audio: AAC-LC, mono or stereo, 44.1/48 kHz, **in the same container**. Audio is absent when muted or without microphone permission (MOT-003).
- Duration target: **~1.5 s before + ~1.5 s after the shutter** (≈ 3 s total), finalized by S3. Hard limits: 1.0–5.0 s.
- The file is self-contained and plays on its own in any player.

### Motion manifest (stored in Memory metadata, and embedded as MP4/MOV metadata `doro:manifest` JSON)

```json
{
  "schema": 1,
  "keyFrameTimeMs": 1500,
  "preRollMs": 1500,
  "postRollMs": 1500,
  "stillAssetId": "0191…",
  "clipAssetId": "0191…",
  "hasAudio": true,
  "orientation": 90,
  "source": "android-ringbuffer | ios-ringbuffer | ios-livephoto | synthetic"
}
```

`keyFrameTimeMs` is the clip time corresponding to the still's sensor timestamp. Both platforms must derive it from sensor timestamps, not wall-clock times.

### Sync tolerance

- Audio/video sync inside the clip: |offset| ≤ 45 ms (starting hypothesis from broadcast guidance; S3 confirms).
- Key-frame alignment: the video frame at `keyFrameTimeMs` is within 1 frame of the still's capture timestamp.

### Playback (MOT-004)

Press-and-hold (mobile) or click (web) plays from 0 with sound (respecting the silent switch on iOS), then cross-fades back to the rendered still. The profile look is applied to motion in preview on-device; the stored clip is **ungraded** in the MVP (grading motion and video is PRF-011, Post). The UI shows the graded still and an ungraded clip, and the difference is subtle but documented.

## Video (P8)

- Originals: device-native (HEVC in MOV on iOS; H.264/HEVC in MP4 on Android), max as captured.
- `video_web`: H.264 High, AAC, MP4, `+faststart`, ≤ 1080p.
- `video_poster`: JPEG from 10% into the clip (or the first frame for clips < 2 s).

## Limits (MVP)

| Asset | Max size |
|---|---|
| photo_original (HEIF/JPEG) | 64 MB |
| photo_original (DNG, Post) | 150 MB |
| motion_clip | 40 MB |
| video_original (P8) | 20 GB |

The server rejects creating uploads beyond these limits (`upload.too_large`).

## Naming

Local: `media/{memoryId}/{assetId}.{ext}`. Server keys: `o/{ownerId}/{memoryId}/{assetId}/{role}` (ADR-0008). File names shown on download: `DoroCam_{YYYYMMDD_HHMMSS}_{role}.{ext}`, using the capture time in the capture time zone.

## Acceptance criteria

- Clips produced on the Android Emulator and the iOS Simulator (synthetic source) pass `ffprobe` validation. The web rendition plays in Chromium, Firefox, and WebKit under Playwright.
- The sync tolerance is met in an automated test: synthetic input with a flash frame and a beep at the same timestamp, 20 runs, offsets measured after demuxing. The real microphone clap test is field verification FV-004.
- Manifest round-trips: embed → extract equals the source.
