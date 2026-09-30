# Product Requirements

Status: Living · Last updated: 2026-09-30 · Related: [vision.md](vision.md), [roadmap.md](roadmap.md)

This document is the single source of truth for **what** Doro Cam must do. Each requirement has a stable ID. IDs are never reused or renumbered. A removed requirement keeps its row with the scope `Dropped`.

**Scope tags:**
- `MVP`: required for the first complete release (roadmap P0–P7).
- `Post`: planned after the MVP.
- `Future`: direction only; must not be built without owner approval.

**Definition format:** a requirement is *defined* by a table row whose first cell is its ID. Other documents *reference* IDs, and the docs checker verifies every reference resolves to a definition here.

**Capability rule for all camera requirements:** "where supported" means *reported by the platform API at runtime for the active physical camera, and verified to take effect*. Unsupported capabilities are hidden or disabled with an explanation, never simulated (CAM-005).

## MVP journey

The MVP proves this end-to-end flow on the reference Android device (iOS follows once a macOS machine is available):

1. Open the app and choose a camera Experience (EXP-001).
2. Configure supported camera settings (CAM-010, CAM-011, CAM-020, CAM-030, CAM-006) or pick a scenario or preset (EXP-004, EXP-006).
3. Choose an image profile with live preview (PRF-001).
4. Capture a high-quality photo (CAM-003), optionally as a Motion Memory (MOT-001, MOT-002).
5. The Memory is saved locally and durably (MEM-001, NFR-002).
6. Sign in (AUTH-001).
7. The Memory uploads at original quality, resumably (SYNC-002, SYNC-003).
8. View it in the local library (LIB-001) and in the web dashboard (WEB-002, WEB-003).

## Other core journeys (Post-MVP)

- **Trip album:** create a trip album, invite friends as contributors, everyone's captures upload at original quality, and members download originals (SHR-001–SHR-006).
- **Understand:** open insights and see focal length, profile, and ISO distributions with plain-language summaries (ANL-001–ANL-005).
- **Suggested preset:** a suggestion explains the pattern it found; the user accepts, edits, or dismisses it (PRE-001–PRE-003).
- **Video:** record video with the same capability-aware controls; it is preserved and playable on the web (VID-001–VID-006).

## CAM — Camera capture

| ID | Requirement | Scope |
|---|---|---|
| CAM-001 | Show a live rear-camera viewfinder when the camera screen opens. | MVP |
| CAM-002 | Switch between rear and front cameras. | MVP |
| CAM-003 | Capture a still photo at the highest resolution supported by the selected camera and format. | MVP |
| CAM-004 | Detect camera capabilities at runtime **per physical camera** (ranges, modes, formats) and expose them to the app. | MVP |
| CAM-005 | Hide or disable controls the device does not support, with a short explanation. Never simulate hardware controls. | MVP |
| CAM-006 | Select physical lenses (ultra-wide, wide, telephoto) where the platform exposes them to third-party apps. | MVP |
| CAM-007 | Display the active lens's 35 mm-equivalent focal length. | MVP |
| CAM-008 | Zoom: optical lens steps plus digital zoom; digital zoom is clearly labelled. | MVP |
| CAM-010 | Manual ISO within the device-reported range, where supported. | MVP |
| CAM-011 | Manual shutter speed (exposure duration) within the device-reported range, where supported. | MVP |
| CAM-012 | Exposure compensation within the device-reported range and step. | MVP |
| CAM-013 | Display the lens aperture (f-number). Allow control only if the hardware reports multiple apertures. | MVP |
| CAM-014 | Auto-exposure lock. | MVP |
| CAM-020 | Continuous autofocus and tap-to-focus/meter. | MVP |
| CAM-021 | Manual focus, where supported, labelled with distance only when the device reports calibrated focus distances. | MVP |
| CAM-022 | Focus lock. | MVP |
| CAM-030 | White-balance presets: auto, daylight, cloudy, shade, tungsten, fluorescent. | MVP |
| CAM-031 | White balance in Kelvin, where supported. | MVP |
| CAM-040 | Flash modes (off/auto/on) and torch, where supported. | MVP |
| CAM-041 | Self-timer (3 s / 10 s). | MVP |
| CAM-042 | Composition grid overlay. | MVP |
| CAM-043 | Level (horizon) indicator. | Post |
| CAM-044 | Aspect ratio selection (e.g. 4:3, 3:2, 16:9, 1:1). Non-native ratios are recorded as crop metadata; the original is kept uncropped. | MVP |
| CAM-045 | HDR / platform enhancement toggle, where exposed. | Post |
| CAM-046 | Photo output format selection among supported formats (e.g. HEIF, JPEG). | MVP |
| CAM-047 | RAW capture (DNG) where supported. | Post |
| CAM-048 | Live histogram. | Post |
| CAM-050 | Record the settings **actually applied** at capture (as reported by the device result metadata, not only as requested). | MVP |
| CAM-051 | Capture feedback: visual and haptic, plus shutter sound where regionally required. | MVP |
| CAM-052 | Camera and microphone permission flows with clear recovery when permission is denied. | MVP |
| CAM-053 | Handle interruptions (backgrounding, calls, another app taking the camera, thermal throttling) without crashing or losing a capture in progress. | MVP |

## EXP — Experiences and shooting modes

| ID | Requirement | Scope |
|---|---|---|
| EXP-001 | Choose a camera Experience: Modern Mirrorless, DSLR, Film, Instant. | MVP |
| EXP-002 | An Experience defines UI style, default controls, default profile, default aspect ratio, and shooting workflow. | MVP |
| EXP-003 | Experience constraints are optional; the user can override defaults unless they opted into an "authentic" constraint. | MVP |
| EXP-004 | Assisted mode: choose a scenario (Portrait, Street, Landscape, Night, Sunset, Indoor, Bright Day, Film, Instant, Cinema). The app recommends settings and explains them. | MVP |
| EXP-005 | Manual mode exposes every supported control. | MVP |
| EXP-006 | Select a saved preset (capture settings + profile + experience options). | MVP |
| EXP-007 | Create, edit, rename, and delete custom presets. | MVP |
| EXP-008 | Requested settings are resolved against capabilities. When a value is clamped or unsupported, the user sees what changed and why. | MVP |
| EXP-009 | Film Experience: optional roll constraint (e.g. 24/36 frames) with a frame counter. | Post |
| EXP-010 | Instant Experience: capture is presented as an instant-style print that "develops". | MVP |
| EXP-011 | Fully built Experiences in the MVP: Mirrorless and Instant. DSLR and Film ship as styled variants on the same engine. | MVP |

## PRF — Image profiles and effects

| ID | Requirement | Scope |
|---|---|---|
| PRF-001 | Choose an image profile and see it applied in the live preview. | MVP |
| PRF-002 | The original capture is always preserved; profiles are non-destructive recipes. | MVP |
| PRF-003 | A rendered photo with the profile applied is produced on-device at capture for immediate viewing and sharing. | MVP |
| PRF-004 | Ship at least five original profiles (e.g. Natural, Warm Film, Soft Film, Instant Warm, Black & White). | MVP |
| PRF-005 | Change a Memory's profile after capture (re-render from the original). | Post |
| PRF-006 | Effects: grain and vignette. | MVP |
| PRF-007 | Effects: bloom/halation, light leaks, fade, dust, frame, date stamp. | Post |
| PRF-008 | User-created profiles by adjusting profile parameters. | Post |
| PRF-009 | The preview look matches the rendered output within the tolerance defined in [image-profile.md](../specs/image-profile.md). | MVP |
| PRF-010 | Profiles are original works; no proprietary film names, logos, or trade dress. | MVP |
| PRF-011 | Profiles can be applied to video (baked export). | Post |

## MOT — Motion Memory (LIVE)

| ID | Requirement | Scope |
|---|---|---|
| MOT-001 | A per-capture LIVE on/off toggle, persisted per Experience. | MVP |
| MOT-002 | LIVE capture stores a still plus a short motion clip spanning before and after the shutter, with audio. | MVP |
| MOT-003 | Audio can be muted per capture; without microphone permission, LIVE captures silent motion and says so. | MVP |
| MOT-004 | Playing a Motion Memory (press/tap) plays the motion and sound, then returns to the still. | MVP |
| MOT-005 | Motion Memories work fully offline and sync like any Memory. | MVP |
| MOT-006 | Motion Memories play in the web dashboard. | MVP |
| MOT-007 | Choose a different key frame from the motion clip. | Post |
| MOT-008 | Export as Apple Live Photo / Android Motion Photo. | Future |
| MOT-009 | Pre-capture buffering runs only while LIVE is on and the camera is active. | MVP |

## VID — Video

| ID | Requirement | Scope |
|---|---|---|
| VID-001 | Record video with audio. | Post |
| VID-002 | Choose resolution and frame rate from supported combinations. | Post |
| VID-003 | Manual ISO/shutter/WB/focus during video where supported. | Post |
| VID-004 | Stabilization mode selection where supported. | Post |
| VID-005 | Originals preserved; a web-compatible rendition is generated. | Post |
| VID-006 | Poster frame and thumbnails generated. | Post |

## MEM — Memories

| ID | Requirement | Scope |
|---|---|---|
| MEM-001 | Every capture creates a Memory, durably saved locally before success is shown. | MVP |
| MEM-002 | A Memory records its assets and capture metadata (applied settings, camera and lens, profile, Experience, time with time zone). | MVP |
| MEM-003 | Attach device location to Memories only if the user enabled it (off by default). | MVP |
| MEM-004 | Add or edit a caption. | MVP |
| MEM-005 | Add or edit tags. | Post |
| MEM-006 | Mark favorites. | MVP |
| MEM-007 | Delete a Memory (moves to trash; permanently deleted after 30 days or on empty trash), locally and in the cloud. | MVP |
| MEM-008 | Every Memory has a stable, non-guessable public handle reserved for future physical links. It is not exposed in the MVP UI. | MVP |

## LIB — Local library

| ID | Requirement | Scope |
|---|---|---|
| LIB-001 | Browse local Memories newest first, offline. | MVP |
| LIB-002 | Memory detail view with photo, motion playback, and capture metadata. | MVP |
| LIB-003 | Filter by kind (photo, motion, video) and favorites. | Post |
| LIB-004 | Show per-Memory sync status (local only, uploading, synced, failed). | MVP |
| LIB-005 | Free up space: remove local original files of fully synced Memories, keeping thumbnails. | Post |

## SYNC — Upload and synchronization

| ID | Requirement | Scope |
|---|---|---|
| SYNC-001 | Pending uploads are stored in a durable local queue that survives app kill and device restart. | MVP |
| SYNC-002 | Uploads start automatically when connectivity allows, and continue in the background as far as the OS permits. | MVP |
| SYNC-003 | Large uploads resume from the last completed part instead of restarting. | MVP |
| SYNC-004 | Retries never create duplicate Memories or assets. | MVP |
| SYNC-005 | "Upload on Wi-Fi only" setting (default on). | MVP |
| SYNC-006 | Memories uploaded from one device appear on the user's other devices. | Post |
| SYNC-007 | Metadata edits made offline on multiple devices reconcile deterministically. | Post |
| SYNC-008 | Uploaded media is verified by checksum; mismatches are retried and never marked synced. | MVP |

## SHR — Sharing and albums

| ID | Requirement | Scope |
|---|---|---|
| SHR-001 | Create albums and add Memories. | Post |
| SHR-002 | Trip albums with a date range and optional auto-add of the member's captures during the trip. | Post |
| SHR-003 | Invite members with roles: Owner, Editor, Contributor, Viewer. | Post |
| SHR-004 | Contributors upload original-quality Memories to the album. | Post |
| SHR-005 | Album setting controlling whether members may download originals. | Post |
| SHR-006 | Album and per-Memory control of whether location is visible to other members. | Post |
| SHR-007 | Members can leave; owners can remove members. | Post |
| SHR-008 | View-only share links. | Future |

## WEB — Web dashboard

| ID | Requirement | Scope |
|---|---|---|
| WEB-001 | Sign in to the web dashboard. | MVP |
| WEB-002 | Library grid of the user's Memories, newest first, paginated. | MVP |
| WEB-003 | Memory detail with photo, motion and sound playback, and metadata. | MVP |
| WEB-004 | Download originals. | MVP |
| WEB-005 | Show storage usage. | MVP |
| WEB-006 | Account settings including account deletion. | MVP |
| WEB-007 | Album and sharing management. | Post |
| WEB-008 | Preset management. | Post |
| WEB-009 | Photography statistics and insights. | Post |
| WEB-010 | Data export (downloadable archive of originals and metadata). | Post |

## ANL — Photography analytics

| ID | Requirement | Scope |
|---|---|---|
| ANL-001 | Focal length and lens usage distributions. | Post |
| ANL-002 | Profile and Experience usage, overall and by album or trip. | Post |
| ANL-003 | ISO, shutter, and aperture distributions, filterable by time of day and scenario. | Post |
| ANL-004 | Trends over time. | Post |
| ANL-005 | Plain-language insights generated deterministically, each showing the numbers it is based on. | Post |

## PRE — Personalized presets

| ID | Requirement | Scope |
|---|---|---|
| PRE-001 | Detect recurring combinations of settings, profile, and scenario. | Post |
| PRE-002 | Suggest a preset with an explanation of the pattern and its supporting data. | Post |
| PRE-003 | Suggestions are never auto-applied; the user can accept, edit, or dismiss, and dismissals are remembered. | Post |

## AI — Future intelligence

| ID | Requirement | Scope |
|---|---|---|
| AI-001 | Natural-language and semantic search over Memories. | Future |
| AI-002 | Similarity and duplicate detection. | Future |
| AI-003 | Automatic categorization and tagging. | Future |
| AI-004 | AI features are opt-in, and the privacy impact is disclosed before enabling. | Future |

## PHY — Physical memories

| ID | Requirement | Scope |
|---|---|---|
| PHY-001 | Generate a printable instant-style layout with a QR code for a Memory. | Future |
| PHY-002 | Scanning the code opens the Memory, subject to its sharing permissions. | Future |
| PHY-003 | NFC tag support. | Future |

## AUTH — Accounts

| ID | Requirement | Scope |
|---|---|---|
| AUTH-001 | Email and password accounts with email verification. | MVP |
| AUTH-002 | Sign in with Google. | Post |
| AUTH-003 | Sign in with Apple (required on iOS if other social logins are offered). | Post |
| AUTH-004 | Per-device sessions that the user can view and revoke. | MVP |
| AUTH-005 | The camera and local library work without an account. | MVP |
| AUTH-006 | Password reset. | MVP |

## PRIV — Privacy

| ID | Requirement | Scope |
|---|---|---|
| PRIV-001 | Location capture is off by default and can be toggled at any time. | MVP |
| PRIV-002 | Location is never exposed to other users unless the owner allows it (see SHR-006). Served files have GPS metadata stripped when it isn't allowed. | MVP |
| PRIV-003 | All media is private by default; access requires authorization on every request. | MVP |
| PRIV-004 | Account deletion removes all of the user's data and media within 30 days. | MVP |
| PRIV-005 | No third-party tracking SDKs that receive media or location. | MVP |
| PRIV-006 | Users can export their data (see WEB-010). | Post |

## NFR — Non-functional

| ID | Requirement | Scope |
|---|---|---|
| NFR-001 | All capture, profile, and local library functions work fully offline. | MVP |
| NFR-002 | Zero lost captures: a capture is on disk and recorded in the local DB before success is shown. | MVP |
| NFR-003 | Viewfinder preview with the profile applied runs at ≥ 30 fps on reference devices (to be validated by spike S2). | MVP |
| NFR-004 | Shutter-to-saved latency is measured on reference devices and a budget is set after spike S1. No budget is invented before measurement. | MVP |
| NFR-005 | Originals are stored and served bit-exact (verified by SHA-256). | MVP |
| NFR-006 | API latency budgets are set after the first baseline in P4, then tracked. | MVP |
| NFR-007 | Web meets WCAG 2.2 AA; mobile supports screen readers, dynamic text, and sufficient contrast. | MVP |
| NFR-008 | All network traffic uses TLS; authorization is checked server-side on every metadata and media access. | MVP |
| NFR-009 | Every change passes the Definition of Done in the development guide. | MVP |
| NFR-010 | CI runs tests, linters, type checks, and the docs check on every push and pull request. | MVP |
| NFR-011 | Structured logs with request IDs; no media content, precise location, or secrets in logs. | MVP |
| NFR-012 | LIVE pre-buffering and preview stop when the camera is idle or backgrounded, to protect battery and thermals. | MVP |
| NFR-013 | The backend runs as a single deployable (API + worker processes) on Docker, portable across hosts. | MVP |
