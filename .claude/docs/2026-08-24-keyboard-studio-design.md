# Keyboard Studio — Design (v1)

**Date:** 2026-08-24 · **Status:** LIVE · **Owner:** Nadir + Claude (co-design)

## Vision

Native, open-source macOS companion app for the Attack Shark K86 (ROYUAN) keyboard:
device control (RGB, side strips, 128×128 TFT screen) + privacy-first keyboard
statistics (SwiftKey-style lifetime counters, monthly/yearly champions) + later
AI-derived insights. Published as MIT open source.

## Decisions log

| Decision | Choice | Why |
|---|---|---|
| Name / repo | Keyboard Studio / `keyboard-studio` | User pick; broad enough for multi-keyboard future |
| License | MIT | Protocol source (shark-k86-mac) is MIT; sharkfin (GPL) is behavioral reference ONLY — no code copied |
| Stats scope v1 | K86 only (VID 0x3151 filter) | Cleanest privacy story; architecture stays keyboard-agnostic |
| Privacy model | Counters only (keycode→count/day), no sequences, no text, no timestamps-per-key, zero network | Input Monitoring API ≈ keylogger API; this design is the trust answer & the marketing line |
| Dependencies | Zero third-party | Auditable open source; IOKit/SwiftUI/ImageIO/SQLite3 are all system |
| UI | MenuBarExtra + main window (Stats / Lights / Screen / Settings) | Native macOS feel |
| Config transport | USB cable only (firmware limitation); stats work on BT too | Settings persist on-board |

## Architecture

```
keyboard-studio/
├── Package.swift            SPM, zero deps, macOS 14+
├── Sources/
│   ├── K86Kit/              HID transport + ROYUAN protocol (feature reports)
│   │                        Port of MIT shark-k86-mac; opcodes documented in PROTOCOL.md
│   ├── StatsCore/           (Faz 2) IOHIDManager input-value counter, K86-only,
│   │                        in-memory counters → batch flush to SQLite each 60s
│   ├── kstudio/             CLI (dev tool + power users): info/color/effect/side/leds/screen
│   └── KeyboardStudio/      (Faz 3) SwiftUI app: MenuBarExtra + window
```

Protocol notes (index mapping!): Python reference reads feature reports through
hidapi which strips report-id 0; device report byte `f[i]` == Python `r[i+1]`.
Swift IOHIDDeviceGetReport returns `f` directly:
- firmware: `f[0]==0x80`, version = `f[2]<<8 | f[1]`
- kboption: `f[2]`=main byte, `f[3]`=side byte, `f[4]`=powersave
- screen canwrite ack: `f[1]==1`

## Roadmap

1. **Faz 0–1 (now):** K86Kit port + `kstudio` CLI, live-verified on device
2. **Faz 2:** StatsCore + SQLite schema (`day × keycode × count` + active minutes)
3. **Faz 3:** SwiftUI app — Stats dashboard (champions, streaks, records), Lights, Screen (drag-drop image/GIF).
   Before freezing the public API: decide `actor K86` + async screen upload — the blocking
   `Thread.sleep` transport (~18 s for a 30-frame GIF) must not run on the main thread.
   Also refactor Screen to an injectable transport so wire-packet unit tests become possible
   (reviewer finding, 2026-08-24).
4. **Faz 4:** Stats→TFT (daily count on keyboard's own screen), heatmap→RGB
5. **Faz 5:** App-aware profiles (NSWorkspace), knob/remap (sharkfin behavioral ref), opt-in AI report
6. **Publish:** GitHub public, README with privacy schema, screenshots

## Verification gates

- `swift build` zero errors per commit
- Protocol changes live-tested on real K86 (cable)
- Stats DB schema documented in README before Faz 2 merge
