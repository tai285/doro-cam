# ADR-0005: Platform-neutral Motion Memory representation

Status: Accepted (validated by spike S3)
Date: 2026-09-30
Related: MOT-001–MOT-009, [media.md](../../specs/media.md), [motion-capture.md](../../research/motion-capture.md)

## Context

LIVE captures must preserve photo + motion + sound, sync to the cloud, and play on iOS, Android, and the web. Apple's Live Photo format (paired HEIC + MOV) and Google's Motion Photo (a single file with an embedded MP4) are vendor-specific. Android has no capture API for pre-shutter buffering.

## Decision

- A Motion Memory is a Memory (`kind = motion`) with a `photo_original`/`photo_rendered` still, **one `motion_clip` asset** (MP4/MOV, H.264/HEVC video + AAC audio in the same container), and a **manifest** (`keyFrameTimeMs`, pre/post roll, orientation, source).
- Audio lives inside the clip container. There is no separate audio asset, so the muxer guarantees A/V sync.
- **iOS** may use native Live Photo capture as its source and repackage the result. **Android** uses a custom encoded-sample ring buffer (S3).
- The worker produces an H.264 MP4 web rendition.
- Export to vendor formats is a Future feature (MOT-008).

## Alternatives

- **Adopt Apple's format everywhere:** not supported by Android or web tooling.
- **Adopt Google Motion Photo everywhere:** a single-file container complicates independent upload and processing; iOS has no native support.
- **Separate audio file:** creates a sync problem that containers already solve.

## Consequences

- The Android ring buffer is the riskiest implementation item. S3 fallbacks (post-roll-only motion) are pre-agreed.
- The storage model stays uniform (assets + roles), and the web plays standard MP4.
- The stored clip is ungraded in the MVP. Grading motion is PRF-011 (Post).
