# Product Vision

Status: Accepted · Last updated: 2026-09-30 · Related: [requirements.md](requirements.md)

## One sentence

**Doro Cam captures and preserves the feeling of a moment:** an honest, beautiful camera whose photos become durable, shareable, relivable Memories.

## Philosophy

```
CAPTURE → PRESERVE → ORGANIZE → SHARE → UNDERSTAND → RELIVE
```

1. **Capture** with intent. The camera should feel like choosing and using a real camera, not like a social filter app.
2. **Preserve** originals. Doro Cam never degrades the original capture. Looks are applied non-destructively.
3. **Organize** around Memories, not files. A Memory is a photo, plus optional motion and sound, plus its context.
4. **Share** at original quality with the people who were there, with no messaging-app compression and no AirDrop workflow.
5. **Understand** your own photography: which lenses, focal lengths, settings, and looks you actually use.
6. **Relive**: tap a photo and the moment moves and sounds again. Later, a printed instant-style photo can lead back to it.

## Honesty principle

The app **never fakes hardware**. If the device exposes manual ISO, the user gets manual ISO. If it doesn't, the app says so plainly. Phone apertures are almost always fixed, so aperture is shown, not "controlled". Software looks (blur, grain, light leaks) are always presented as **effects**, never as camera settings. This is a product differentiator, not only an engineering constraint.

## Target users

| Persona | Description | What they need |
|---|---|---|
| **Enthusiast shooter** | Owns or wants a "real" camera; enjoys manual control and film aesthetics | Honest controls, distinct camera experiences, beautiful original profiles |
| **Nostalgic memory-keeper** | Loves instant film and film looks; cares about moments more than specs | Instant/Film experiences, Motion Memories, easy albums |
| **Trip group** | Friends traveling together | One shared trip album, original quality, everyone contributes |
| **Learning photographer** | Wants to improve | Assisted scenarios that explain settings, insights about their habits |

## Problems we solve

- Phone camera apps either hide all control or expose it clumsily, and many "pro" apps silently fake controls the hardware lacks.
- Filter apps destroy originals and flatten photos into a single aesthetic.
- Sharing trip photos means messaging apps (compressed), AirDrop (same-platform, manual), or cloud drives (not designed for photos).
- Live Photos are Apple-only and hard to share or preserve cross-platform.
- People don't know their own photographic habits.

## Goals

- A camera that feels intentional, with distinct experiences that share one reliable engine.
- Zero lost captures: capture works offline and is durable on disk before the UI confirms it.
- Originals preserved bit-exact from capture to cloud to download.
- Cross-platform Motion Memories (photo + motion + sound).
- Frictionless original-quality shared trip albums.
- Insights and preset suggestions that are explainable, not black boxes.

## Non-goals (for now)

- A social network: no public feeds, followers, likes, or comments on a public graph.
- A general photo editor: no layers, retouching, or healing.
- Replacing the system gallery or backing up non-Doro-Cam photos (import may come later).
- Desktop capture or a web camera UI.
- Microservices, multi-region, or "millions of users" architecture on day one.
- AI as a foundation. AI comes later, on top of a solid data model.
- Physical printing in the MVP. The architecture only reserves room for it.
- Copying proprietary film-simulation names, profiles, or branding.

## North-star journey

1. Open the app and choose an Experience: Modern Mirrorless, DSLR, Film, or Instant.
2. Choose a preset or scenario, or set ISO, shutter, lens, focus, white balance, exposure, and profile manually, all limited to what the device really supports.
3. Turn **LIVE** on to keep the moment beyond a still.
4. Take the photo. Doro Cam stores **PHOTO + MOTION + SOUND** as one Memory, immediately available locally.
5. When online, the Memory syncs to the cloud at original quality.
6. On a trip, friends contribute to one shared album.
7. Later, on phone or web, tap the photo. It moves, and the original sound plays.
8. Doro Cam shows your habits ("most of your street photos are 35mm with Warm Film") and suggests a preset.
9. Eventually, print an instant-style photo, scan its code, and return to the full Memory.

## Success criteria (MVP)

These are measured qualitatively with early users and quantitatively via product analytics once they exist.

- A user can complete the MVP journey (see [requirements.md](requirements.md#mvp-journey)) on a reference Android device without assistance.
- No capture is lost across app kills, offline periods, and restarts during a two-week personal field test.
- Uploaded originals are byte-identical to the local originals (checksum verified) for 100% of uploads.
- Manual controls shown on a device are exactly those the device honours (verified against [capability-matrix.md](../specs/capability-matrix.md)).
