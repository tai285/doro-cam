# Camera UX

Status: Accepted (direction) · Last updated: 2026-09-30 · Related: EXP-001–EXP-011, CAM-005, MOT-001, [ux-principles.md](ux-principles.md), ADR-0003

## Experiences

Every Experience runs on the same engine (ADR-0003). They differ in skin, defaults, workflow, and optional constraints.

| Experience | Character | Default profile | Default aspect ratio | Workflow cues | MVP depth |
|---|---|---|---|---|---|
| **Modern Mirrorless** | Clean, precise, information-rich but calm | Natural | 3:2 | Live exposure readouts; histogram (Post); fast dial access | Full (EXP-011) |
| **Instant** | Warm, tactile, playful | Instant Warm | ~1:1 frame (crop metadata) | Flash auto; big shutter; the capture "ejects" and develops (EXP-010); LIVE prominent | Full (EXP-011) |
| **DSLR** | Dense, top-LCD-style readouts, dark | Natural | 3:2 | P/A/S/M-style exposure selector mapped to real capabilities | Styled variant |
| **Film** | Deliberate, analog | Warm Film | 3:2 | Frame counter; optional roll constraint (EXP-009, Post); no instant review by default (setting) | Styled variant |

Choosing an Experience is a single tap from the camera screen (a mode strip or a "camera body" picker). The last used Experience is restored on launch.

## Screen structure (all Experiences)

```
┌────────────────────────────┐
│ top bar: flash · LIVE · timer · aspect · settings │
│                            │
│        VIEWFINDER          │  ← tap: focus/meter; long-press: AE/AF lock
│                            │
│ adjustment notice (if any) │  ← e.g. "Shutter limited to 1/4 s on this lens"
├────────────────────────────┤
│ control strip: ISO · SS · EV · WB · Focus · Lens │  ← only supported controls
│ dial / scrubber for selected control             │
├────────────────────────────┤
│ [last photo]  (SHUTTER)  [experience / mode]     │
└────────────────────────────┘
```

## Beginner vs professional

- **Assisted (default for new users):** the control strip shows a *scenario chip* (Portrait, Street, Night…). Choosing one applies recommended settings and shows a one-line "why" ("Night: slower shutter and higher ISO for more light; hold steady"). Tapping the explanation reveals the actual values.
- **Manual:** the control strip shows each supported control with its value. Each control has an **Auto** state (value shown dimmed with an "A" badge) and a manual state.
- **Presets:** a preset picker sits beside the scenario chip. "Save as preset" captures the current merged intent (EXP-007).
- Modes are **not tabs**. Touching any dial moves the user into Manual for that field only (a layered override, ADR-0003). "Reset to scenario/preset" clears the overrides.

## Communicating unsupported capabilities (CAM-005)

- Unsupported controls are **absent** from the control strip, not greyed out, to keep the strip clean. A "Not available on this camera" section in the controls sheet lists them, with a short reason ("This phone doesn't allow apps to set shutter speed").
- A control that exists on another lens shows a hint when the user is on a lens without it ("Manual focus available on 1× lens").
- Aperture is shown as a readout (ƒ/1.8), not as a dial, unless the hardware supports several apertures (CAM-013).
- Effects that mimic optics are labelled as effects, e.g. "Background blur (effect)", never "f/1.4".
- When the device ignores a manual setting (detected by applied ≠ requested), the UI shows a one-time notice and disables that control for the session.

## LIVE (Motion Memory)

- The toggle sits in the top bar, with a clear on state and a subtle animated ring while buffering.
- The microphone indicator is explained on first use. A mute toggle is available inside the LIVE long-press menu (MOT-003).
- On capture, the thumbnail shows a LIVE badge. In the library, press and hold plays it (MOT-004).
- LIVE turns off automatically, with a notice, when thermal state is serious or battery saver is on (NFR-012).

## Instant "develop" moment

After capture in Instant, the rendered photo appears as a print sliding up and developing over ~2 s. Tapping skips it. The Memory is already saved before the animation starts (NFR-002). The animation is presentation only.

## Ergonomics

- Portrait-first, with rotation-aware icons and readouts (the UI rotates its elements, not the layout).
- Volume buttons trigger the shutter where the OS permits.
- Left-handed mode mirrors the bottom bar (setting).
- The timer shows a visible countdown and front flash or screen cue.
