# Adding a keyboard

Keyboard Studio is not written around one model. A keyboard is described by two
JSON files — no Swift required for boards that speak a protocol the app already
knows.

## 1. Find your board's USB ids

```sh
ioreg -p IOUSB -l -w 0 | grep -iE '"USB Product Name"|"USB Vendor Name"|idVendor|idProduct'
```

`idVendor` and `idProduct` are printed in decimal, which is what the profile
wants. Tri-mode boards can enumerate under different product ids over cable,
2.4 GHz and Bluetooth — list every id you see.

## 2. Write a device profile

Drop a file into `~/Library/Application Support/KeyboardStudio/Devices/` (no
rebuild) or `Sources/KeyboardKit/Resources/Devices/` (to contribute it):

```json
{
  "id": "epomaker-rt100",
  "vendor": "Epomaker",
  "model": "RT100",
  "vendorID": 12625,
  "productIDs": [16405, 16406],
  "family": "royuan",
  "layout": "ansi-75-knob",
  "capabilities": {
    "lighting": "whole",
    "sideLighting": true,
    "knob": true,
    "screen": { "width": 128, "height": 128, "pixelFormat": "rgb565",
                "maxFrames": 30, "verified": false }
  }
}
```

`family` picks the wire protocol. `royuan` covers boards sold as Attack Shark,
Epomaker, Akko, Hator, ikbc, NOPPOO and MEETION — they share one manufacturer's
firmware. A board from another manufacturer needs a new family implemented in
`Sources/KeyboardKit/`; open an issue first so we can agree on the shape.

## 3. Check what the board answers

```sh
swift build
.build/debug/kstudio info      # does it identify itself?
.build/debug/kstudio probe     # which read-only opcodes reply?
.build/debug/kstudio measure   # where does the panel end?
```

**About `verified`.** Set it to `true` only after you have looked at the panel.
The ROYUAN firmware answers "ready" to a write handshake for *any* frame size,
so the resolution cannot be asked for — a datasheet or another project's
constant is not evidence. Use:

```sh
.build/debug/kstudio screen --ruler          # border should touch all four edges
.build/debug/kstudio screen --bands          # count 32 px colour bands
```

If the image sits in a corner with dead space, the panel is bigger than the
profile says. Adjust `width`/`height` and try again.

## 4. Draw the layout (optional)

Layouts live in `Sources/KeyboardKit/Resources/Layouts/` or
`~/Library/Application Support/KeyboardStudio/Layouts/`. Field names follow
QMK's `info.json`, so a layout can be converted rather than redrawn:

```json
{
  "id": "ansi-75-knob",
  "name": "75% ANSI with rotary knob",
  "columns": 16.25,
  "rows": 6.25,
  "keys": [
    { "label": "Esc", "usage": 41, "x": 0, "y": 0 },
    { "label": "⌫", "usage": 42, "x": 13, "y": 1.25, "w": 2 },
    { "label": "Knob", "x": 15.25, "y": 0, "knob": true }
  ]
}
```

Units are key widths (1u = one alphanumeric key). `usage` is the HID usage id
from page 0x07 — it ties a drawn key to the statistics and, later, to per-key
colour. Leave it out for keys that emit no usage, such as Fn or the knob.

Boards without a layout still work; effect previews fall back to a generic grid.

## 5. Send it back

Open a pull request with the profile (and layout) plus one line in the PR
describing what you verified on hardware: lighting, screen, measured
resolution. Please do not mark `verified: true` for anything you have not seen
with your own eyes — other people will trust that flag.
