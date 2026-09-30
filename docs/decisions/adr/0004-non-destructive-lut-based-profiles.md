# ADR-0004: Non-destructive, LUT-based image profiles

Status: Accepted
Date: 2026-09-30
Related: PRF-001–PRF-011, [image-profile.md](../../specs/image-profile.md), [image-processing.md](../../research/image-processing.md)

## Context

Profiles must render in live preview, at full-resolution capture, possibly on the server (re-render), and later on video. They must look the same everywhere, never destroy the original, and be original works rather than copies of commercial film simulations.

## Decision

- The **original capture is always preserved** unmodified. A profile is a versioned recipe (`id@version` + params) stored on the Memory.
- The color portion of each profile is defined as declarative JSON and **compiled to a 3D LUT** (33³) at build time by `packages/profiles`. The compiled LUTs are committed.
- Spatial effects (grain, vignette, halation…) are separate parametric shaders, normalized to image size and seeded per Memory.
- Capture rendering is done on-device, natively, producing `photo_rendered` immediately. The server can re-render later from the original with the same LUT.
- Profile versions are immutable once shipped.

## Alternatives

- **Hand-written shaders per profile per platform:** drift between platforms, and no server or video reuse.
- **Destructive filtering (save only the filtered photo):** violates preservation.
- **Server-side rendering only:** not offline, and not immediate.

## Consequences

- Needs a small LUT compiler with golden tests, plus parity testing (S7).
- Storage cost: roughly two full-size images per photo (original + rendered). This is accepted as the cost of immediate sharing and preservation.
- The LUT can't express spatial or local operations. Those must be effects.
