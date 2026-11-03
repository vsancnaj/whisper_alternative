#!/usr/bin/env bash
# Remove Whisper Alternative. Keeps Homebrew packages and Hammerspoon itself.
#   scripts/uninstall.sh          asks before deleting
#   scripts/uninstall.sh --yes    no questions
set -euo pipefail
APP_DIR="${WHISPER_ALT_DIR:-$HOME/.config/whisper-alternative}"
HS_DIR="${HAMMERSPOON_DIR:-$HOME/.hammerspoon}"
STATE_DIR="${WHISPER_ALT_STATE:-/tmp/whisper-alternative}"
if [ "${1:-}" != "--yes" ]; then
  echo "This deletes $APP_DIR (your config, any sounds you added and the downloaded models)"
  echo "and removes the Whisper Alternative line from $HS_DIR/init.lua."
  read -r -p "Continue? [y/N] " ans </dev/tty
  case "$ans" in y|Y|yes|YES) ;; *) echo "Cancelled."; exit 0 ;; esac
fi
rm -rf "${APP_DIR:?}" "${STATE_DIR:?}" "${HS_DIR:?}/whisper_alternative.lua"
if [ -f "$HS_DIR/init.lua" ]; then
  sed -i '' '/-- Whisper Alternative (local voice dictation)/d;/require("whisper_alternative")/d' "$HS_DIR/init.lua"
fi
if [ "${WA_SKIP_BREW:-0}" != 1 ] && command -v hs >/dev/null 2>&1; then hs -c "hs.reload()" >/dev/null 2>&1 || true; fi
echo "Removed. Now click the Hammerspoon menu bar icon > Reload Config (or quit and reopen it)."
echo "To also remove the tools: brew uninstall whisper-cpp sox && brew uninstall --cask hammerspoon"
