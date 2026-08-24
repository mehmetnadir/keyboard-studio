# Feature parity — what we have, what competitors have

Status 2026-08-24. "Protocol known" means we have the wire format; "verified"
means it was round-tripped on real hardware.

| Capability | Keyboard Studio | VIA/VIAL | Razer / Corsair | Notes |
|---|---|---|---|---|
| RGB effects (whole board) | ✅ 19 effects, animated hover previews | ✅ | ✅ | Ours previews motion before applying |
| Side light strips | ✅ | — | ✅ | |
| Per-key colour | 🟡 protocol known, UI pending | ✅ | ✅ | Flash-backed stored pattern, ~10 s cadence — not a live canvas |
| TFT screen images / GIF | ✅ | — | — | Almost nobody has this |
| Stats on the keyboard's screen | ✅ | — | — | No other product does this |
| Typing statistics | ✅ | — | — | Vendors shipped and killed it; only standalone apps have it |
| Knob configuration | 🟡 reads live assignments; write pending | ✅ (encoders) | ✅ | Slots verified: 96 / 97 |
| **Key remapping** | ❌ | ✅ core feature | ✅ | Read works; write opcode 0x09 unverified |
| **Macros** | ❌ | ✅ | ✅ | Firmware has 50 slots; slot type 0x09 |
| **Layers (Fn)** | ❌ | ✅ | partial | Firmware: 128 slots per layer |
| Onboard profiles | ❌ | ✅ | ✅ | Board has 3 |
| App-aware switching | ❌ | — | ✅ | NSWorkspace makes this easy |
| Multi-keyboard support | ✅ data-driven profiles | ✅ definitions | vendor-locked | |
| Native macOS | ✅ | ⚠️ web/Electron | ⚠️ Windows-first | ckb-next dropped macOS in 2020 |
| Open source | ✅ MIT | ✅ GPL | ❌ | |

## The honest summary

Where we lead: the screen, typing statistics, stats-on-device, native macOS,
and an effect gallery that actually animates.

Where we are behind, and it is the part users notice most: **remapping, macros
and layers**. These are the heart of VIA/VIAL and every vendor app, and we have
none of them yet.

## Why remapping is not shipped yet

Reading the keymap works and is verified — `kstudio keymap` decodes it. Writing
is the gap:

- The write opcode is `0x09`, but its packet layout is not confirmed on
  hardware, and this protocol family reuses opcodes across lineages: `0x09` is
  the keymap on one, a lighting option byte on another.
- A wrong slot silently remaps a real key. The recovery path (restore factory
  keymap) is itself unverified.

So the read path is live and the write path stays closed until it is proven on
hardware — with the safest possible first test: the knob's press slot, which is
currently unassigned, so a mistake there breaks nothing.

## Keymap write — six shapes tried, none worked (2026-08-24)

Tested on hardware against the knob's press slot (98, page 6 index 2), which is
unassigned, with the whole page backed up first. Nothing changed, so nothing
broke — but nothing wrote either:

| Shape | Result |
|---|---|
| whole page, data at byte 3, bit7 | no change |
| single slot `[0x09, 0, page, index] + 4 bytes`, bit7 | no change |
| single slot by global index, bit7 | no change |
| whole page, data at byte 8 (screen-style), bit7 | no change |
| single slot, bit8 (lighting-style) | no change |
| global slot, bit8 | no change |

Still to try, roughly in order of likelihood:

1. **The read may be stale rather than the write failing.** `GET_USERPIC` is
   documented as returning data that does not reflect writes; the keymap read
   may behave the same. Re-open the device — or replug it — before reading back,
   and test by feel (does the knob mute?) rather than by read-back alone.
2. **An unlock or begin/commit step.** Many boards in this family gate writes
   behind a mode change, and commit them with a separate save command.
3. **A different opcode.** `0x09` is `SET_KEYMATRIX` on the yc500 lineage per
   the vendor bundle, but that mapping is from a catalogue, not measured here.
4. Reading the vendor WebHID bundle's own keymap writer, which is the
   licence-clean primary source for the exact byte layout.

Until one of these lands, remapping, macros and knob assignment stay read-only.
`kstudio keymap --test-write` re-runs the experiment safely.

## Order of work

1. Verify the keymap write — six shapes failed, see above for what is left
2. Knob assignment (write) — smallest useful surface, blocked on the above
3. Key remapping page — the canvas and the shortcut catalogue already exist
4. Macros (50 slots, needs a recorder UI)
5. Layers, then onboard profiles
6. Per-key painting UI (protocol ready, cadence-limited)
