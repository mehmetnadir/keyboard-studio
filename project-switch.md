# project-switch — keyboard-studio

[STATE: GREENFIELD] — day 1, core library + CLI first, SwiftUI app next.

## Departments
- K86Kit (HID transport + ROYUAN protocol): `Sources/K86Kit/`
- CLI: `Sources/kstudio/`
- StatsCore: not created yet (Faz 2)
- App: not created yet (Faz 3)

## Docs
- Design + decisions log: `.claude/docs/2026-08-24-keyboard-studio-design.md`
- No `.claude/docs/INDEX.md` yet (no archive).

## Notes
- Protocol reference clone lives in session scratchpad only — never vendored.
- Config requires USB cable; stats (future) work over any transport.
