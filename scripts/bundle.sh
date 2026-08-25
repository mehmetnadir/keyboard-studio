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

# SwiftPM keeps localizations in its own resource bundle, which Bundle.module
# looks for next to the executable.
for bundle in "$ROOT/.build/$CONFIG"/*.bundle; do
  [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/MacOS/"
done

cp "$ROOT/Resources/icon/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# SwiftUI resolves Text("key") against the MAIN bundle, not the package's
# resource bundle — so the .lproj folders have to live in Contents/Resources
# too, or every label renders as its raw key.
for lproj in "$ROOT/Sources/KeyboardStudioApp/Resources"/*.lproj; do
  [ -d "$lproj" ] && cp -R "$lproj" "$APP/Contents/Resources/"
done

# Sign with a Developer ID when one is available, falling back to ad-hoc.
#
# This is not cosmetic. An ad-hoc signature gets a fresh code identity on every
# build, so macOS treats each install as a different app and asks for Input
# Monitoring again — and the permission granted to the previous build is dead.
# A real certificate keeps the identity stable across rebuilds, so the grant
# survives. It is also what allows the App Sandbox to work at all: macOS will
# not create a container for an ad-hoc signed app.
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
  | grep -m1 'Developer ID Application' \
  | sed -E 's/.*"(.*)".*/\1/')"
if [ -z "$IDENTITY" ]; then
  IDENTITY="-"
  echo "No Developer ID found — signing ad-hoc. macOS will ask for permissions"
  echo "again after every rebuild; that is a property of ad-hoc signing."
else
  echo "Signing as: $IDENTITY"
fi

# --deep is deliberately not used (Apple discourages it), so nested bundles are
# signed first, innermost outwards — an unsigned nested bundle would make the
# outer signature invalid.
for nested in "$APP/Contents/MacOS"/*.bundle; do
  [ -e "$nested" ] && codesign --force --sign "$IDENTITY" "$nested"
done

codesign --force --options runtime \
  --entitlements "$ROOT/Resources/KeyboardStudio.entitlements" \
  --sign "$IDENTITY" "$APP"

codesign --verify --strict "$APP" && echo "Signature verified" 

echo "Built: $APP"
echo "Run:   open '$APP'"
echo
echo "Verify there is no networking:"
echo "  grep -rn 'URLSession\\|Network\\.' Sources/   # expect no matches"
