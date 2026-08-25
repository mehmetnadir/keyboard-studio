#!/bin/bash
# Builds a release app and installs it to /Applications.
#
# Installing matters for more than tidiness: macOS ties permissions such as
# Input Monitoring to an app's identity and location, so a copy that keeps
# moving between build folders has to be re-approved each time.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="Keyboard Studio.app"
DEST="/Applications/$APP"

"$ROOT/scripts/bundle.sh" release

# Quit a running copy so the replacement is not fighting it for the device.
pkill -f "Keyboard Studio" 2>/dev/null || true
sleep 1

rm -rf "$DEST"
cp -R "$ROOT/build/$APP" "$DEST"

# Deliberately NOT resetting TCC here. An earlier version did, which threw away
# the user's Input Monitoring grant on every single install — the permission
# had to be given again after each update, and counting silently stopped in
# between. Re-register with LaunchServices only; that is harmless.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
[ -x "$LSREGISTER" ] && "$LSREGISTER" -f "$DEST" >/dev/null 2>&1 || true

echo "Installed: $DEST"
echo "Open it from Applications, or:  open -a 'Keyboard Studio'"
