#!/bin/bash
# Updates Keyboard Studio from the repository: pull, test, build, install.
#
# The app itself contains no networking code and this script keeps it that way —
# git does the fetching, outside the app. That preserves the promise in
# PRIVACY.md, which users are invited to verify with grep.
#
# Signing matters here as much as building. macOS ties permissions to a code
# identity, so an update signed with a different identity arrives as a
# different app: Input Monitoring is revoked and typing statistics silently
# stop. bundle.sh picks up a Developer ID certificate when the machine has one,
# which keeps the identity stable across updates.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "==> Fetching"
before="$(git rev-parse HEAD)"
git pull --ff-only
after="$(git rev-parse HEAD)"

if [ "$before" = "$after" ]; then
  echo "Already up to date ($(git rev-parse --short HEAD))."
  if [ "${1:-}" != "--force" ]; then
    echo "Pass --force to rebuild and reinstall anyway."
    exit 0
  fi
else
  echo
  echo "==> Changes"
  git --no-pager log --oneline "$before..$after" | head -20
fi

echo
echo "==> Testing"
# A failed test stops the install rather than replacing a working app with a
# broken one. set -e handles the exit; the message explains why it stopped.
if ! swift test 2>&1 | tail -3; then
  echo
  echo "Tests failed — not installing. The app in /Applications is untouched."
  exit 1
fi

echo
echo "==> Installing"
"$ROOT/scripts/install.sh"

echo
echo "Updated to $(git rev-parse --short HEAD)."
echo "Quit and reopen Keyboard Studio to run the new version."
