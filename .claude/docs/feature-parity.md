# Feature parity — what we have, what competitors have

Status 2026-08-24. "Protocol known" means the wire format is in hand;
"verified" means it was round-tripped on real hardware.

## Where we stand

| Capability | Keyboard Studio | VIA/VIAL | Razer / Corsair | Note |
|---|---|---|---|---|
| RGB effects, whole board | ✅ 19, animated hover previews | ✅ | ✅ | Ours previews motion before applying |
| Side light strips | ✅ | — | ✅ | |
| **Per-key painting** | ✅ brush, groups, flash-stored | ✅ | ✅ | Ours reads the LED map from the device |
| TFT screen images / GIF | ✅ | — | — | Almost nobody has this |
| Stats on the keyboard's screen | ✅ | — | — | Nobody has this |
| Now playing on the screen | ✅ 3 sources | — | partial | Vendor apps do Spotify only, if at all |
| Lighting follows the music | ✅ colour from album art | — | ✅ audio-reactive | Theirs is real-time; ours cannot be, see below |
| Typing statistics | ✅ | — | — | Vendors shipped this and killed it |
| Knob configuration | 🟡 reads live bindings | ✅ | ✅ | Write blocked, see below |
| **Key remapping** | 🟡 UI + macOS catalogue, write blocked | ✅ core | ✅ | |
| **Macros** | ❌ | ✅ | ✅ | Firmware has 50 slots |
| **Layers (Fn)** | ❌ | ✅ | partial | Firmware: 128 slots per layer |
| Onboard profiles | ❌ | ✅ | ✅ | Board has 3 |
| App-aware switching | ❌ | — | ✅ | NSWorkspace makes this straightforward |
| Debounce / polling rate | ❌ | ✅ | ✅ | Protocol likely supports it; unexplored |
| Firmware update | ❌ | ✅ | ✅ | Deliberately out of scope — bricking risk |
| Multi-keyboard | ✅ JSON profiles | ✅ definitions | vendor-locked | |
| Native macOS | ✅ | ⚠️ web/Electron | ⚠️ Windows-first | ckb-next dropped macOS in 2020 |
| Open source | ✅ MIT | ✅ GPL | ❌ | |

## The three real gaps

**1. Macros, layers, remapping, knob assignment — all one blocker.**
Every one of these is a keymap write, and the write command is not proven.
Six packet layouts were tried on hardware against an unassigned slot; none took
effect, and nothing broke. Until it is solved, four features stay read-only.
This is the single highest-value thing left to crack.

**2. Onboard profiles.** The board holds three. Switching between them is
probably a small command, and unlike the keymap it is likely a single byte —
worth probing next, since it is cheap and independent of the write problem.

**3. App-aware switching.** Nothing blocks this: `NSWorkspace` reports the
frontmost app, and we can already set lighting. It is unbuilt, not impossible.

## Where we are ahead

The screen is the big one — images, GIFs, live statistics, now playing — and no
vendor app on macOS does any of it. Typing statistics is a category vendors
abandoned. And the whole thing is native, open source, and works on keyboards
sold under six different brands rather than one.

## What we cannot match, and why

Real-time audio visualisation. Razer and Corsair stream frames at 30 fps to
firmware built for it. This board's lighting commands wedge the control
endpoint if pushed past roughly one or two a second, and per-key colour writes
flash with a ten-second floor. A beat-synced strobe is not a feature we have
not built; it is one the hardware refuses. What we do instead is give each
track a colour — from its album art where the player hands it over locally.

## Device settings — protocol mapped (2026-08-24)

From the vendor's own client, with the safe/dangerous split verified against
our probe output.

| Setting | Read | Write | Notes |
|---|---|---|---|
| Active profile | `[0x85]` → byte 1 | `[0x05, n]` | 3 profiles; ours reads 0 |
| Debounce | `[0x81]` → byte 2 | `[0x11, 0, ms]` | 0–10 ms for this board |
| Sleep timers | `[0x92]` | `[0x12]` + four LE16 | seconds; 60–3600, 0 = never |
| Win/Mac | `[0x86]` → byte 2 bit 1 | — | read-only; the physical switch drives it |
| Polling rate | — | — | not exposed on this model |

Confirmed against hardware: `0x85` returns profile 0, and `0x86` byte 2 is
`0x02` — bit 1 set — which matches the board being in Mac mode. Key maps and
Fn maps are per-profile; lighting, debounce and sleep are global.

**The screen is 240 x 135**, stated in the vendor's device record for id 1168.
The 128 x 128 we inherited from the reference implementation was wrong.

### Dangerous commands — now blocked in code

The protocol puts destructive operations next to harmless ones: factory reset
is `0x02`, and a full flash erase is `0xAC` — inside the 0x80+ range that
otherwise holds only reads, and it blocks for ~55 seconds. Our old probe swept
0x80–0x8F blindly, which came within four opcodes of it.

`DangerousCommands` now refuses these at the transport, which is the one place
every raw command passes through. The probe uses a verified-safe list instead
of a range. Four tests cover it.

## Order of work

1. ~~Crack the keymap write~~ — done
2. Enable knob assignment and key remapping writes in the UI
3. Macros (`0x16`, ids 0...49) and the Fn layer (`0x15`)
4. Onboard profile switching (`0x05`)
5. ~~App-aware lighting~~ — done
6. Screen gallery: bundled CC0 art plus a community repo

Also worth acting on: the vendor registry lists this board's panel as
**240 x 135**, not the 128 x 128 we inherited from the reference
implementation. Worth testing with `kstudio screen --bands --size 240x135`.
