# Keyboard Studio

Native, open-source macOS companion for the **Attack Shark K86** keyboard.
No Windows software, no VM, no cloud — talks straight to the keyboard over USB HID.

**Status: early development.** Working today: `kstudio` CLI (RGB, side strips,
TFT screen upload). Coming next: SwiftUI app with privacy-first typing
statistics (lifetime key counts, monthly champions, streaks) and more.

## Install (from source)

```sh
git clone <this repository>
cd keyboard-studio
swift build -c release
.build/release/kstudio info
```

Requirements: macOS 14+, Xcode 16+ toolchain. Zero third-party dependencies.

## Usage

Connect the K86 with its USB cable (back switches: **Mac + USB**). Settings are
written to the keyboard's own memory — they persist when you switch back to
Bluetooth or 2.4 GHz.

```sh
kstudio info                     # firmware + connection status
kstudio color 9b59b6             # main light: solid color (hex or name)
kstudio effect wave --speed 4    # one of 20 effects, rainbow by default
kstudio side cyan                # side light strips
kstudio screen photo.png         # 128x128 TFT screen: image
kstudio screen animation.gif     # ...or animated GIF (up to 30 frames)
kstudio leds off                 # LED master switch
```

## Privacy (for the upcoming stats features)

Typing statistics will be **counters only** — how many times each key was
pressed per day, and active minutes. No key sequences, no text, no per-key
timestamps. Data never leaves your Mac; the app has no network access. The
SQLite schema will be documented here so anyone can audit the stored data.

## Credits

- Protocol: [shark-k86-mac](https://github.com/RaphaelCaputo2/shark-k86-mac)
  by Raphael Caputo (MIT) — ported to Swift.
- Protocol research: [Reverse engineering the Attack Shark keyboard
  protocol](https://dnim.dev/blog/royuan-keyboard-protocol).
- Not affiliated with or endorsed by Attack Shark or ROYUAN.

## License

MIT — see [LICENSE](LICENSE).
