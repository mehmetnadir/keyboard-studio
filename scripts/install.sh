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

# Keep TCC, the sandbox container and LaunchServices in agreement. If they
# disagree — which happens when a container is removed by hand, or an app is
# re-signed repeatedly — the app exits at launch with no crash report and no
# log entry. Resetting costs a permission prompt; not resetting costs an hour.
tccutil reset All dev.keyboardstudio.app >/dev/null 2>&1 || true
rm -rf "$HOME/Library/Containers/dev.keyboardstudio.app" 2>/dev/null || true
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
[ -x "$LSREGISTER" ] && "$LSREGISTER" -f "$DEST" >/dev/null 2>&1 || true

echo "Installed: $DEST"
echo "Open it from Applications, or:  open -a 'Keyboard Studio'"
