#!/bin/bash
# Builds Keyboard Studio.app from the SPM executable target.
#
# macOS grants Input Monitoring to a bundle identity, so the statistics
# features only work from a real .app — not from `swift run`.
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Keyboard Studio.app"
BINARY="$ROOT/.build/$CONFIG/KeyboardStudioApp"

cd "$ROOT"
swift build -c "$CONFIG" --product KeyboardStudioApp

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/Keyboard Studio"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Ad-hoc signature with the sandbox entitlements. --deep is deliberately not
# used (Apple discourages it); there is one binary and it is signed in place.
# Re-signing changes the identity, so macOS may ask for permission again.
codesign --force --options runtime \
  --entitlements "$ROOT/Resources/KeyboardStudio.entitlements" \
  --sign - "$APP"

echo "Built: $APP"
echo "Run:   open '$APP'"
echo
echo "Verify the sandbox denies networking:"
echo "  codesign -d --entitlements - '$APP' | grep -c network.client   # expect 0"
