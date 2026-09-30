# Spec: Image Profiles and Effects

Status: Draft (validated by spikes S2, S7) · Last updated: 2026-09-30 · Related: PRF-001–PRF-011, ADR-0004

## Purpose

Define how photographic looks are described, compiled, rendered, and versioned, so preview, capture, the worker, and future video all produce the same look from one definition.

## Three separate concepts

| Layer | Examples | Where it applies | Stored as |
|---|---|---|---|
| **Capture settings** | ISO, shutter, WB, focus, lens | The sensor, via the camera (not a profile) | `CaptureMetadata` |
| **Image profile** | tone curve, contrast, highlights/shadows, saturation, per-hue response, temperature/tint shift, B&W mix | Color pipeline → **compiled to a 3D LUT** | `ProfileRef {id, version}` |
| **Effects** | grain, vignette, halation/bloom, fade, light leak, dust, frame, date stamp | Spatial shaders after the LUT | Effect params in the profile or user overrides |

A profile never changes capture settings. An Experience or preset may *pair* a profile with capture settings.

## Profile definition (source of truth)

Profiles live in `packages/profiles/definitions/*.json` and are validated by a JSON Schema in the same package.

```json
{
  "id": "warm-film",
  "version": 1,
  "name": "Warm Film",
  "description": "Soft warm highlights, lifted blacks, gentle saturation.",
  "color": {
    "exposureEv": 0.0,
    "contrast": 0.1,
    "highlights": -0.2,
    "shadows": 0.15,
    "blackPoint": 0.04,
    "whitePoint": 0.97,
    "toneCurve": [[0,0.04],[0.25,0.24],[0.5,0.52],[0.75,0.78],[1,0.97]],
    "saturation": -0.05,
    "vibrance": 0.1,
    "temperatureShift": 0.08,
    "tintShift": 0.02,
    "hsl": { "orange": {"hue": 0.02, "sat": 0.05, "lum": 0.03} },
    "splitTone": { "shadows": {"hue": 200, "amount": 0.05}, "highlights": {"hue": 40, "amount": 0.08} },
    "monochrome": null
  },
  "effects": {
    "grain": { "amount": 0.25, "size": 1.2, "chroma": 0.1 },
    "vignette": { "amount": 0.2, "midpoint": 0.6, "roundness": 0.2 }
  }
}
```

Parameter semantics and ranges are defined by the schema, with each field documented. Values are dimensionless in [-1, 1] unless stated otherwise.

## Compilation

- `packages/profiles` (TypeScript, run in CI and at build time) compiles `color` into a **33×33×33 3D LUT** (sRGB-encoded input → output). It writes `.cube` for tooling/ffmpeg and a compact binary (`.lut`, float16 RGB, little-endian, with a header of size and version) for the apps.
- Compilation is deterministic, with golden tests (fixed input params → byte-identical LUT). The compiled assets are committed so apps don't compile at runtime.
- Order of operations inside compilation: exposure → white point/black point → temperature/tint → tone curve and contrast → highlights/shadows → HSL → saturation/vibrance → split tone → monochrome mix. This order is normative.
- Effects are **not** baked into the LUT. They are spatial and resolution-dependent. Each is implemented as a shader with parameters normalized to image size, so grain looks the same at preview and full resolution (size relative to the short edge).

## Rendering sites

| Site | Implementation |
|---|---|
| Live preview | Per S2: native GLES/Metal shader, or a Flutter fragment shader, sampling the LUT as a 3D texture (or a 2D-tiled texture where 3D is unavailable) |
| Capture render | Native: Android GLES offscreen or CPU fallback; iOS Core Image `CIColorCubeWithColorSpace` + Metal kernels for effects |
| Worker (Post: PRF-005 re-render; PRF-011 video) | ffmpeg `lut3d` + equivalent effect filters, or a native re-render on device |

Grain uses a seeded noise function. The seed is derived from `memoryId`, so re-renders are reproducible.

## Parity (PRF-009)

- Preview and capture must match within **mean ΔE2000 ≤ 2.0 and 95th-percentile ≤ 4.0** on the standard fixture set (color chart + three natural images), excluding grain. These thresholds are the starting hypothesis; spike S7 confirms or revises them.
- Parity tests run in CI for the compiler/CPU reference renderer, and on-device for GPU paths.

## Versioning

- A profile's `version` increments on **any** change to its output. Old versions remain in the package so existing Memories can be re-rendered identically.
- A Memory stores `{id, version}`. Removing a profile version requires a migration plan (ADR).

## Initial profile set (PRF-004, original works)

`natural`, `warm-film`, `soft-film`, `instant-warm`, `mono-classic`. Later candidates: `cool-film`, `vintage`, `cinema`, `night`, `disposable`. Names describe a character and must not reference commercial film stocks or brands (PRF-010).

## Errors and edge cases

- A missing or corrupt LUT asset makes the profile unavailable, and the UI falls back to `natural` with a logged error. Capture is never blocked.
- HDR/wide-gamut input: the MVP renders in sRGB/Display P3 → sRGB output JPEG. Wide-gamut rendering is a Post decision.
- Monochrome profiles still preserve the color original.

## Acceptance criteria

- The JSON Schema validates all definitions in CI.
- Compiler golden tests pass; LUTs are byte-stable across runs and OSes.
- Parity thresholds are met on the reference device for all MVP profiles.
