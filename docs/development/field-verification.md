# Field Verification Log

Status: Living · Last updated: 2026-09-30 · Related: ADR-0013, [capability-matrix.md](../specs/capability-matrix.md)

Emulators and simulators verify **correctness**. Some facts can only come from real hardware. This log lists them so they are never silently assumed. Per ADR-0013, entries **do not block tasks**. They are run whenever a real device is available: the owner's Honor X9c or iPhone 12 Pro Max, or a device farm later.

When an entry is run, record the result, copy capability facts into [capability-matrix.md](../specs/capability-matrix.md), and open a fix task if behavior differs from the emulator.

## How to add an entry

Any task whose acceptance includes a hardware-only aspect adds a row here in the same change:

| ID | Source task | What to verify | Why it can't be emulated | Device(s) | Status | Result / date |
|---|---|---|---|---|---|---|

Status is `pending`, `pass`, `fail (task link)`, or `n/a`.

## Entries

| ID | Source task | What to verify | Why it can't be emulated | Device(s) | Status | Result / date |
|---|---|---|---|---|---|---|
| FV-001 | SPK-T-001 | Which manual controls the Honor X9c exposes and honours (hardware level, `MANUAL_SENSOR`, physical lenses) | OEM camera HAL behavior | Honor X9c | pending | — |
| FV-002 | SPK-T-001 | iPhone 12 Pro Max lens set and manual ranges | The Simulator has no camera | iPhone 12 Pro Max | pending | — |
| FV-003 | SPK-T-002 | Preview grading sustains ≥ 30 fps for 10 min (NFR-003) | Emulator GPU performance isn't representative | Honor X9c, iPhone | pending | — |
| FV-004 | SPK-T-003 | Motion clip A/V sync with a real microphone (clap test), plus battery and thermal cost of LIVE | Real audio path, battery, thermals | Honor X9c, iPhone | pending | — |
| FV-005 | SPK-T-004 | Background upload continues under MagicOS battery management after an app kill | OEM power management | Honor X9c | pending | — |
| FV-006 | CAM-T-005 | Shutter-to-saved latency baseline (NFR-004) | Real sensor pipeline timing | Honor X9c, iPhone | pending | — |
| FV-007 | SPK-T-007 | Preview vs capture color parity on real camera frames | Real sensor color | Honor X9c, iPhone | pending | — |

## Installing builds on the owner's devices

- **Honor X9c:** CI publishes a debug APK as a workflow artifact. Install it with `adb install` or by opening the APK.
- **iPhone 12 Pro Max:** needs a signed build. TestFlight requires the Apple Developer Program (an owner decision). Until then, iPhone entries stay `pending`.
