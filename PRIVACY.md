# Privacy

Keyboard Studio counts keystrokes. That is the same macOS permission a keylogger
asks for, so this document states exactly what the app does, what it refuses to
do, and how you can check both claims yourself.

## What is stored

Four aggregate tables, in one SQLite file on your Mac:

| Table | Contents | Example row |
|---|---|---|
| `daily_counts` | how many times each key was pressed, per day | `2026-08-24, 0x2C, 1843` |
| `daily_activity` | presses and active minutes, per day | `2026-08-24, 212, 9455` |
| `hourly_totals` | lifetime histogram over 24 hours | `14, 182304` |
| `meta` | schema version, first-seen date | `schema_version, 1` |

`active_minutes` counts minutes that saw at least one press. Which minutes those
were is never written down.

## What is never stored

- **The order of keystrokes.** Counters are incremented independently, so the
  stored data cannot reconstruct a word, a sentence, a password, or anything you
  typed. There is no buffer holding recent keys.
- **Text, characters, or clipboard contents.** The app records HID usage ids —
  physical key positions. Usage `0x04` is the key labelled "A" on QWERTY and "Q"
  on AZERTY; the app cannot tell which character it produced.
- **Per-keystroke timestamps.** Only the day and the hour bucket a press falls
  into, both as running totals.
- **Anything about other keyboards.** See below.

## Structural limits, not promises

These restrictions come from how the code is built, not from a policy we ask you
to trust:

1. **One device only.** `KeyMonitor` binds to the K86 by vendor and product id
   (`0x3151` / `0x4015`) through `IOHIDManagerSetDeviceMatching`. Presses on
   your built-in keyboard or any other keyboard never reach this process.
   `CGEventTap` — the API that sees everything — is deliberately not used, and
   the app would not work if it were, because it cannot tell devices apart.
2. **Keyboard usages only.** Only HID usage page `0x07` (Keyboard/Keypad) values
   are counted. Consumer keys, the knob and pointer usages are discarded.
3. **No network.** The app declares no network entitlement and contains no
   networking code. There is no telemetry, no crash reporting, no update ping.
4. **No sync.** The database is a plain file under
   `~/Library/Application Support/KeyboardStudio/`. Nothing copies it anywhere.

## Verify it yourself

```sh
# Read your own data — it is a normal SQLite file:
sqlite3 ~/Library/Application\ Support/KeyboardStudio/stats.sqlite .dump | head

# Confirm no outbound connections while the app runs:
lsof -i -a -p $(pgrep -f 'Keyboard Studio')     # expect no output

# Read the ~150 lines that touch keyboard input:
Sources/StatsCore/KeyMonitor.swift
```

## Delete your data

Quit the app, then `rm -rf ~/Library/Application\ Support/KeyboardStudio/`.
Nothing else is left behind except the macOS permission itself, which you can
revoke in System Settings → Privacy & Security → Input Monitoring.

## Permission

Counting requires Input Monitoring. macOS will ask once. Denying it disables the
statistics features; the lighting and screen features keep working, since those
talk to the keyboard over USB rather than reading input.
