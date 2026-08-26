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

## Finding the screen size

A panel accepts any frame size without complaining, so "it looks full" is not
evidence. Work through these in order; stop at the first one that answers.

**1. Ask the device.**

```sh
kstudio screen --query
```

Some boards report their own resolution and need nothing else. The vendor's own
client does not hardcode a size either — it starts at zero and fills in the
reply to `GetDisplayParam`. If your board answers, put those numbers in the
profile and you are done.

**2. Check width and rotation by eye.**

```sh
kstudio screen --orient --size 240x135
```

Vertical stripes plus four differently coloured corners. Stripes lean when the
width is wrong, corners land in the wrong places when the frame is rotated or
transposed, and a missing edge means the device is cropping.

**3. Sweep candidates.**

```sh
kstudio screen --sweep
```

Shows each candidate size as a differently tinted frame of vertical stripes.
Straight stripes mean that width is right; the colour tells you which candidate
you are looking at. Edit `Screen.candidateSizes` to change the list.

**4. Read the size off a ruler.**

```sh
kstudio screen --ruler-width
kstudio screen --ruler-height
```

Each sends a frame deliberately larger than the panel, marked with coloured
bars at known positions. The device clips what does not fit, so the last colour
still visible names the width (or height) in a single look.

Both rulers exist because they measure different things. This project encodes
column-major, so a wrong *height* slides columns sideways without tilting a
vertical line — vertical stripes can measure width but never height. Horizontal
bars are what a height error shows up in.

### What a wrong size looks like

| On the panel | Cause |
|---|---|
| Image drifts further sideways with each row | Width larger than the panel: rows overflow into the next |
| Fills only part of the screen, striped | Frame encoded at a different size than it is sent as |
| Correct but with black bars left and right | Not a bug — `--fit` preserves the source's proportions; use the default crop to fill |
| A few black pixels along one edge | Profile is a little short of the real panel; adjust and save |

Once you know the numbers, set them in Settings → Screen and press "save as
verified" so updates keep them.
