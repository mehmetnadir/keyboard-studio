# Keyboard Studio

Native, open-source macOS companion for the **Attack Shark K86** keyboard.
No Windows software, no VM, no cloud — talks straight to the keyboard over USB HID.

**Status: early development.** Working today: `kstudio` CLI — RGB, side strips,
TFT screen upload, and privacy-first typing statistics (lifetime counts, monthly
champions, streaks). Coming next: the SwiftUI app.

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

### Typing statistics

```sh
kstudio watch 60                 # count presses for 60s (asks for permission once)
kstudio stats                    # lifetime totals, streaks, peak hour, champions
```

Statistics work over any connection — cable, Bluetooth or 2.4 GHz.

## Privacy

Typing statistics are **counters only**: how many times each key was pressed per
day, active minutes, and a 24-hour histogram. The order of keystrokes is never
recorded, so the stored data cannot reconstruct anything you typed. Only the
K86 is counted — the app binds to one vendor/product id and never sees your
built-in keyboard. No network access, no sync, no telemetry.

Full details, the exact schema, and commands to verify these claims yourself:
[PRIVACY.md](PRIVACY.md).

## Credits

- Protocol: [shark-k86-mac](https://github.com/RaphaelCaputo2/shark-k86-mac)
  by Raphael Caputo (MIT) — ported to Swift.
- Protocol research: [Reverse engineering the Attack Shark keyboard
  protocol](https://dnim.dev/blog/royuan-keyboard-protocol).
- Not affiliated with or endorsed by Attack Shark or ROYUAN.

## License

MIT — see [LICENSE](LICENSE).
