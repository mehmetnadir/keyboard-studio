# Privacy

Keyboard Studio counts keystrokes. That is the same macOS permission a keylogger
asks for, so this document states exactly what the app does, what it refuses to
do, and how you can check both claims yourself.

## What is stored

Four aggregate tables, in one SQLite file on your Mac:

| Table | Contents | Example row |
|---|---|---|
| `daily_counts` | how many times each key was pressed, per day | `2026-08-24, 0x2C, 1843` |
| `daily_activity` | active minutes and presses, per day | `2026-08-24, 212, 9455` |
| `hourly_totals` | lifetime histogram over 24 hours | `14, 182304` |
| `meta` | schema version, first-seen date | `schema_version, 1` |

`active_minutes` counts minutes that saw at least one press. Which minutes those
were is never written down.

## The honest version of the claim

A key code is close to a character: on a US layout, one particular code always
means "A". So the protection here is not that the app sees something harmless —
it is that **the app never builds a sequence**.

Counters are incremented independently and stored as a fixed-size histogram.
There is no row per keystroke, no array, no ring buffer, nothing with an order
in it. A histogram cannot reconstruct text, because it throws away the order,
and order is where the meaning lives.

What that still leaks, stated plainly: an aggregate histogram reveals *how* you
type — letter-frequency patterns could hint at which language you write in, and
an unusual count on a rare key is visible. It cannot reveal *what* you wrote.

## What is never stored

- **The order of keystrokes.** See above. There is no buffer holding recent keys.
- **Text, characters, or clipboard contents.** The app records HID usage ids —
  physical key positions. Usage `0x04` is the key labelled "A" on QWERTY and "Q"
  on AZERTY; the app cannot tell which character it produced.
- **Per-keystroke timestamps.** Only the day and the hour bucket a press falls
  into, both as running totals.
- **Anything about other keyboards.** See below.

## Structural limits, not promises

These restrictions come from how the code is built, not from a policy we ask you
to trust:

1. **One device only.** `KeyMonitor` binds to a single keyboard by vendor and
   product id (taken from its device profile) through
   `IOHIDManagerSetDeviceMatching`. Presses on your built-in keyboard, or any
   keyboard other than the one being tracked, never reach this process.
   `CGEventTap` — the API most keystroke tools use — is deliberately not used:
   it sees every keyboard at once and cannot tell devices apart, so it could
   not honour this limit even in principle.
2. **Keyboard usages only.** Only HID usage page `0x07` (Keyboard/Keypad) values
   are counted. Consumer keys, the knob and pointer usages are discarded.
3. **No network — enforced by the kernel.** The app runs in the App Sandbox and
   deliberately omits `com.apple.security.network.client`, so macOS refuses any
   outbound connection it might attempt. It also contains no networking code.
   There is no telemetry, no crash reporting, no update ping.
4. **No sync.** The database is a plain file under
   `~/Library/Application Support/KeyboardStudio/`, created with `0700`
   permissions. Nothing copies it anywhere.
5. **`first_seen` is a date, not a timestamp.** The only time-like value stored
   anywhere is the day you first used the app.
6. **Password fields are protected by macOS, not by us.** When any app enables
   secure event input — AppKit password fields, Safari, Chrome and Firefox all
   do — the system stops delivering keyboard events to every observer on the
   machine. We do not *choose* to skip your password; macOS refuses to hand it
   over. The app also checks the flag itself and shows "Paused — macOS is
   protecting your input", so you can watch it happen.

## Verify it yourself

```sh
# Read your own data — it is a normal SQLite file:
sqlite3 ~/Library/Application\ Support/KeyboardStudio/stats.sqlite .dump | head

# Confirm the signed app has no network permission (expect 0):
codesign -d --entitlements - '/Applications/Keyboard Studio.app' | grep -c network.client

# Confirm no outbound connections while it runs:
lsof -i -a -p $(pgrep -f 'Keyboard Studio')     # expect no output

# Confirm the source contains no networking at all (expect no matches):
grep -rn 'URLSession\|Network\.\|CFSocket' Sources/

# Confirm characters are never resolved from a key press (expect no matches):
grep -rn 'UnicodeString\|UCKeyTranslate\|NSEvent' Sources/StatsCore/

# Read the one file that touches keyboard input (~250 lines):
Sources/StatsCore/KeyMonitor.swift
```

One caveat worth stating plainly: `StatsCore` is also published as a library,
and `KeyMonitor` offers an opt-in per-press callback for live UI. It carries a
usage id with no timing, it is disabled unless a caller passes
`enableLiveCallback: true`, and the app never enables it — but if you build on
the library, that callback is the one place order could be observed.

## Delete your data

Quit the app, then `rm -rf ~/Library/Application\ Support/KeyboardStudio/`.
Nothing else is left behind except the macOS permission itself, which you can
revoke in System Settings → Privacy & Security → Input Monitoring.

## Permission

Counting requires Input Monitoring. macOS will ask once. Denying it disables the
statistics features; the lighting and screen features keep working, since those
talk to the keyboard over USB rather than reading input.
