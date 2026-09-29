#!/usr/bin/env bash
#
# Removes Improvements: the login item, the app, its settings and its log.
# Safe to run more than once, and it cleans up either install location.
#
set -euo pipefail

APP_NAME="Improvements"
LOCATIONS=("/Applications/$APP_NAME.app" "$HOME/Applications/$APP_NAME.app")
SUPPORT="$HOME/Library/Application Support/Improvements"
LOG="$HOME/Library/Logs/Improvements.log"

for DEST in "${LOCATIONS[@]}"; do
  [ -d "$DEST" ] || continue

  if [ -x "$DEST/Contents/MacOS/$APP_NAME" ]; then
    "$DEST/Contents/MacOS/$APP_NAME" --unregister-login 2>/dev/null || true
  fi

  # Stop only our own copy, matched by its full path.
  PID="$(pgrep -f "$DEST/Contents/MacOS/$APP_NAME" | head -1 || true)"
  if [ -n "${PID:-}" ]; then
    kill "$PID" 2>/dev/null || true
  fi

  rm -rf "$DEST"
done

rm -rf "$SUPPORT"
rm -f "$LOG"

echo "==> Removed Improvements."
