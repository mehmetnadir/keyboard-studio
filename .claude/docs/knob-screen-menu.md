# The knob's on-screen menu

**Corrected 2026-08-26. The original conclusion below was wrong in the way
that mattered.**

The menu cannot be turned *off* — that part holds, and the evidence for it is
still worth keeping. But it can be **stepped past**, and the way to do it is
documented by the vendor:

> **Fn + knob press** — switches between screen operation and volume control.
> — Attack Shark K86 manual

The knob has two firmware modes. In screen mode, turning it walks the settings
menu; in volume mode, turning it does what its keymap slots say. Confirmed on
hardware: after Fn + press, turning the knob changes the volume and the menu
stays away.

## What the original investigation got wrong

It asked "which command disables this menu?", searched exhaustively, found
nothing, and concluded the behaviour was immovable. Both steps were sound; the
question was not. The control is not a command at all — it is a key
combination the firmware handles by itself, so no amount of reading the
protocol would ever have surfaced it. The manual answered in one line what a
full opcode sweep could not.

Worth remembering when the next "the protocol has no way to do X" appears: the
protocol is not the only interface the hardware has.

Two other combinations from the same manual, neither of them in any client:

| Keys | Effect |
|---|---|
| Fn + knob press | Screen operation ↔ volume control |
| Fn + 1 / 2 / 3 | Bluetooth profile 1 / 2 / 3 |
| Fn + Backspace | Battery percentage on the number row |
| Fn + Esc, 3 seconds | Factory reset |

## Where the mode is kept

Not in `SET_KBOPTION`: reading it before and after a mode change returns the
same bytes (`00 02 00 …`). So there is no bit to write, and the mode cannot be
set from software — Fn + press is the only way in. Assigning `Wheel Swap`
(firmware action 14) to a knob slot is not needed for this and the slot is
better spent on something else.

---

*Original findings below. Everything about the command surface still stands;
only the conclusion drawn from it was wrong.*

**Verdict on a command to disable it: none exists.**

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
