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

## Order of work

1. Verify the keymap write on the unassigned knob press slot
2. Knob assignment (write) — smallest useful surface
3. Key remapping page — the layout canvas already exists
4. Macros (50 slots, needs a recorder UI)
5. Layers, then onboard profiles
6. Per-key painting UI (protocol ready, cadence-limited)
