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

# Ad-hoc signature: enough for TCC to remember the app across launches.
# Re-signing changes the identity, so macOS may ask for permission again.
codesign --force --deep --sign - "$APP"

echo "Built: $APP"
echo "Run:   open '$APP'"
