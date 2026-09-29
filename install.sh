#!/usr/bin/env bash
#
# Installs Improvements:
#   - builds the app
#   - removes the old standalone HighFive agent (this app replaces it)
#   - copies the app to /Applications (or ~/Applications if that isn't writable)
#   - registers it as a login item and launches it
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="Improvements"

if [ -w /Applications ]; then
  DEST="/Applications/$APP_NAME.app"
else
  DEST="$HOME/Applications/$APP_NAME.app"
fi
OTHER_DEST="$HOME/Applications/$APP_NAME.app"

LEGACY_AGENT="$HOME/Library/LaunchAgents/com.ranbam.highfive.plist"
LEGACY_APP="$HOME/Applications/HighFive.app"

"$ROOT/build.sh"

# Remove a previous install from the other location, so the login item and the
# running copy always point at one bundle.
if [ "$DEST" != "$OTHER_DEST" ] && [ -d "$OTHER_DEST" ]; then
  echo "==> Removing the previous copy at $OTHER_DEST"
  "$OTHER_DEST/Contents/MacOS/$APP_NAME" --unregister-login 2>/dev/null || true
  rm -rf "$OTHER_DEST"
fi

if [ -f "$LEGACY_AGENT" ] || [ -d "$LEGACY_APP" ]; then
  echo "==> Removing old standalone HighFive (replaced by this app)"
  launchctl bootout "gui/$(id -u)/com.ranbam.highfive" 2>/dev/null || true
  rm -f "$LEGACY_AGENT"
  rm -rf "$LEGACY_APP"
fi

echo "==> Installing to $DEST"
rm -rf "$DEST"
cp -R "$ROOT/build/$APP_NAME.app" "$DEST"

echo "==> Registering login item"
"$DEST/Contents/MacOS/$APP_NAME" --register-login || true

echo "==> Launching"
open "$DEST"

echo
echo "==> Installed and running."
echo "    No permissions needed. Turn augments on in the window that just opened."
echo "    Logs: ~/Library/Logs/Improvements.log"
