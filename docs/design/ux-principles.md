# UX Principles and Design System Direction

Status: Accepted (direction; visual specifics TBD by design work) · Last updated: 2026-09-30 · Related: NFR-007, [camera-ux.md](camera-ux.md)

## Principles

1. **Intentional, not generic.** Doro Cam should feel like picking up a specific camera, not like opening a social story camera. There are no sticker trays and no beauty filters.
2. **Honest instruments.** Every control reflects a real hardware capability or is explicitly labelled as an effect. Values show units (ISO 400, 1/250 s, 5200 K, 35 mm).
3. **The photo is the hero.** Chrome recedes. The viewfinder and the image get the most space and contrast.
4. **Progressive depth.** Beginners see a scenario and a shutter. Professionals reach every dial in one gesture. The same screen serves both through disclosure, not separate apps.
5. **Nostalgia with restraint.** Film and instant cues (frame counters, a developing print, a shutter feel) are used where they add meaning, never as decoration that slows the user down.
6. **Never lose a moment.** Launch-to-shutter-ready speed and capture reliability beat visual flourish.
7. **Calm sync.** Sync status is visible but never nags. Offline is a normal state, not an error.
8. **Explain, don't hide.** When the app changes or refuses a setting, it says why in one short sentence (EXP-008).

## Visual system approach

Colors and typefaces are **not locked yet**. They will be chosen during P2 design work. What is fixed now is the structure:

- **Design tokens** (color roles, type scale, spacing, radii, motion durations) are defined once per platform: a Flutter `ThemeExtension` and CSS custom properties on the web. Components use tokens, never raw values.
- **Experience themes:** each camera Experience provides a token *override set* (e.g. DSLR: dense, dark, high-contrast readouts; Instant: warm, rounded, tactile). The shared components are the same.
- **Color roles** include `surface`, `onSurface`, `accent`, `readout` (numeric camera values), `warning` (clamped or unsupported), and `recording` (LIVE and video active).
- **Numerics** use tabular figures so values don't jitter while dials move.
- The camera UI is dark by default (it preserves night vision and reduces glare). The library and web support light and dark.

## Interaction principles (mobile)

- **One-hand reach:** the shutter, mode switch, and last-photo thumbnail sit in the bottom thumb zone. Dials are horizontal scrubbers near the bottom.
- **Direct manipulation:** drag on a dial; tap a value to type or snap; long-press to reset to auto.
- **Haptics** on dial detents, lock and unlock, and capture (CAM-051).
- **Motion** is short (≤ 250 ms) and purposeful. The "developing" animation in Instant is the exception and can be skipped.
- **Latency:** the preview must stay live during setting changes. No blocking spinners on the camera screen.

## Accessibility (NFR-007)

- All controls have semantic labels with values ("ISO, 400, adjustable").
- Dials are operable by screen-reader increment and decrement actions.
- Text scales with system settings. Camera readouts may cap the scale but must remain legible (at least 1.3×).
- Contrast is at least 4.5:1 for text and 3:1 for essential UI over the live preview, using scrims where needed.
- Motion playback respects "reduce motion" (no autoplay; explicit play control).
- Color is never the only signal: clamped or unsupported values show an icon and text too.
- Web: WCAG 2.2 AA, full keyboard navigation, visible focus, and alt text built from Memory captions and metadata.

## Responsive web

- The web app is a library and management tool. It has no camera UI.
- Layouts: a single column below 640 px, a two-pane layout (grid + detail) at 1024 px and wider, and a dense grid option on large screens.
- The grid uses the `thumbnail` asset; detail uses `photo_display`, with original download explicit (WEB-004).
- Data-heavy views (insights) use accessible charts with table fallbacks.

## Information architecture

**Mobile:** Camera (home) · Library · Memory detail · Albums (P9) · Insights (P10) · Settings (account, sync, privacy/location, storage).

**Web:** Library · Memory detail · Albums (P9) · Presets (Post) · Insights (P10) · Storage · Account (sessions, deletion, export).
