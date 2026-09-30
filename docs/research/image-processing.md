# Research: Image Processing (Preview, Capture, Server)

Status: Living · Researched: 2026-09-30 · Related: ADR-0004, [image-profile.md](../specs/image-profile.md), [spikes.md](spikes.md)

---

### R-IMG-1 — Flutter fragment shaders over widgets
- **Source:** Flutter docs "Writing and using fragment shaders" (https://docs.flutter.dev/ui/design/graphics/fragment-shaders); `ImageFilter.shader` API (https://api.flutter.dev/flutter/dart-ui/ImageFilter/ImageFilter.shader.html); flutter/flutter issue #132099.
- **Date:** 2026-09-30
- **Finding:** With Impeller, `ImageFilter.shader` applies a custom fragment shader as a filter over child content (including a `Texture`). The shader must declare a size uniform and a `sampler2D` input. Using a 3D LUT requires packing it into a 2D texture passed as an extra sampler.
- **Confidence:** Medium. The API exists; the performance of filtering a live 30 fps camera texture on a mid-range device is unmeasured.
- **Implication:** A candidate for single-source preview grading, but only for the preview. It doesn't help full-resolution capture or video.
- **Action:** S2 compares it with native GPU grading.

### R-IMG-2 — Native GPU preview grading
- **Source:** CameraX `CameraEffect` / `SurfaceProcessor` (Android), OpenGL ES 3.0 3D textures; Apple Core Image `CIColorCubeWithColorSpace`, Metal.
- **Date:** 2026-09-30
- **Finding:** Both platforms support GPU processing of camera frames before display. CameraX effects can target preview, video, and image capture. On iOS, a `AVCaptureVideoDataOutput` → Metal → `CVPixelBuffer` → `FlutterTexture` pipeline is standard.
- **Confidence:** High
- **Implication:** A proven path, reusable for video recording (PRF-011). It costs two shader implementations.
- **Action:** The default choice unless S2 shows the Flutter shader path is equally fast.

### R-IMG-3 — 3D LUTs as the portable color representation
- **Source:** The Adobe/IRIDAS `.cube` format; ffmpeg `lut3d` filter documentation; OpenGL ES 3.0 `GL_TEXTURE_3D`; Core Image color cube filters.
- **Date:** 2026-09-30
- **Finding:** Any per-pixel color transform (curves, HSL, split-tone, saturation) can be baked into a 3D LUT (33³ is the common size) and applied identically by GPUs, CPUs, and ffmpeg (trilinear or tetrahedral interpolation).
- **Confidence:** High
- **Implication:** One compiled artifact serves preview, capture, server re-render, and video. Spatial effects must stay separate.
- **Action:** ADR-0004; the spec defines the compilation order. S7 checks cross-renderer parity (interpolation differences are the main risk: tetrahedral vs trilinear).

### R-IMG-4 — Server-side HEIC decoding
- **Source:** sharp documentation on HEIF support (prebuilt libvips binaries include AVIF, i.e. AV1-in-HEIF, but not HEVC-encoded HEIC, for patent reasons; HEIC needs a custom libvips build with libheif + libde265).
- **Date:** 2026-09-30
- **Finding:** HEIC photos from phones can't be decoded by the default sharp install.
- **Confidence:** High
- **Implication:** Server thumbnailing of HEIC would need a custom native build and carries patent-licensing questions.
- **Action:** Devices generate the rendered, display, and thumbnail JPEGs at capture (see [media-pipeline.md](../architecture/media-pipeline.md)). The worker only processes JPEG derivatives and video (ffmpeg).

### R-IMG-5 — Grain and spatial effects consistency
- **Source:** Analysis.
- **Date:** 2026-09-30
- **Finding:** Grain defined in pixels looks different at 1080p preview and 12–108 MP capture.
- **Confidence:** High
- **Implication:** Effect parameters must be normalized to the image's short edge. Noise must be seeded for reproducibility.
- **Action:** Specified in [image-profile.md](../specs/image-profile.md).
