# ADR-0001: Flutter app with a first-party native camera plugin

Status: Accepted
Date: 2026-09-30
Related: CAM-004, CAM-006, CAM-010, CAM-011, CAM-021, CAM-031, ADR-0002, [camera-apis.md](../../research/camera-apis.md)

## Context

The product needs professional camera control (manual ISO, shutter, focus, Kelvin WB, physical lens selection), GPU-graded preview, and custom motion capture. The owner chose Flutter for cross-platform app development. The official Flutter `camera` plugin doesn't expose manual controls (R-CAM-1), and community forks are stale and Android-only (R-CAM-2).

## Decision

- The mobile app is Flutter (Dart 3).
- All camera access goes through an in-repo plugin, `packages/doro_camera`:
  - a Dart API and an abstract `CameraPlatform`;
  - **Pigeon**-generated typed bindings;
  - **Android:** Kotlin, CameraX with Camera2 interop, and raw Camera2 only where CameraX cannot do the job (e.g. the motion ring buffer, if S3 requires it);
  - **iOS:** Swift, AVFoundation.
- Preview frames reach Flutter through `TextureRegistry` textures.
- Native code implements hardware behavior only. Product logic (scenarios, presets, intent resolution, Memory creation) lives in Dart.
- The official `camera` plugin and other camera plugins must not be added.

## Alternatives

- **Official `camera` plugin:** insufficient controls; forking it means inheriting a large surface we don't control.
- **Community forks:** stale, single-platform.
- **Fully native apps (Swift + Kotlin UIs):** best camera fidelity, but it doubles all UI, library, sync, and auth work for a solo developer.
- **React Native / KMP:** the owner chose Flutter, and neither removes the need for native camera code.

## Consequences

- Camera features are written twice (Kotlin and Swift). iOS is blocked until a Mac is available, so Android leads.
- We control the full camera stack, including preview grading and motion buffering.
- A `FakeCameraPlatform` makes the app's camera UI testable without hardware.
- Revisit if an actively maintained plugin appears that covers our full contract on both platforms.
