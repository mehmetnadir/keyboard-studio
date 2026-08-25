# The knob's on-screen menu cannot be turned off

**Verdict: no. Not a "could not find it" — a searched-exhaustively no.**

Turning the knob opens the keyboard's own menu on its screen. While that menu
is up the knob navigates it and the volume bindings do nothing, even though
slots 96/97 are correctly set to volume down/up.

## What was searched

Against the vendor's own WebHID client (the licence-clean primary source):

- **All 76 `FEA_CMD_*` opcodes.** Nothing selects a screen page, suppresses an
  overlay, or rebinds the encoder.
- **The complete abstract device API — 142 members.** Its entire screen surface
  is: switch language, clear all images, sync clock, sync weather, sync system
  info, write image, and get/set screen menu. Nothing else exists.
- **Every bit of `SET_KBOPTION` (0x06).** bit0 win-key lock, bit1 mac/win, bit3
  WASD swap, bit4 main LED off, bit5 side LED off, bit6 keyboard mode, bit7
  keyboard lock; byte3 bit0 Fn matrix; byte4 power save. Bit2 unused. No screen
  bit anywhere.
- **The whole special-key action catalogue.** Exactly three OLED actions exist
  (`OLED_FontColor`, `OLED_BackColor`, `OLED_Confirm`). No menu toggle, no page
  next, no brightness.

## The two decisive findings

**`SET_MENU` (0x2F) exists but not on this keyboard.** Only one driver class
implements it, and that class declares `type: "dongle"`. Every device carrying
the matching capability flag is a wireless dongle, never a keyboard. And it is
not this menu regardless: its payload is `[0x2F, loop ? 1 : 0, interval]`, and
the vendor labels it *Playback Method / Press to Play / Loop / Image Interval* —
a slideshow setting for stored images.

**`SET_OLEDOPTION` (0x22) is not a settings command at all.** Its payload is
disk free/total, memory used/total, CPU percentage, CPU temperature and network
totals — a one-way telemetry feed for the screen's system-info widget. No menu
bit. The vendor app never even sends it to this board.

**The vendor's own app refuses to touch this knob.** In the K86's key-mapping
page, `AudioVolumeUp`, `AudioVolumeDown` and `AudioVolumeMute` are passed as an
explicit exclusion set, and the knob's labels are stripped from the SVG. The
device record has no `knobKeyCodes`. That is why the knob's slots had to be
found by reading the keymap rather than looked up.

So the menu is firmware behaviour layered on top of the encoder, invisible to
the configuration protocol. Only a firmware update from the vendor could change
it.

## What this research did give us

**The five `screen.layer` entries are five static-image slots, not pages.** The
layer is a parameter of the image write, not a display selector:

- handshake `0xA5`: byte 18 = layer index, 0-based
- image write `0x25`: byte 1 = layer, for a single static image

There is no command to display a given layer. Which means the on-screen menu is
very likely how a user picks between stored images — the menu is the selector
the protocol lacks. Annoying, but not purposeless.

We already pass a layer through `Screen.writeImage(_:at:layer:on:)`; it was
simply never exposed.

## Unverified lead, recorded and not acted on

One other board (`Bladesage Q5`) declares nine `knobKeyCodes` for a single
encoder — three left/press/right triples, the third being OLED colour actions.
That *reads like* one encoder with three firmware modes. If this board shares
that structure there may be further knob slots past 98. Untested, stated
nowhere in the code, and at best it would repoint the menu rather than silence
it — so it is not being pursued as a fix.
