#!/usr/bin/env bash
# Remove Whisper Alternative. Keeps Homebrew packages and Hammerspoon itself.
set -euo pipefail
APP_DIR="${WHISPER_ALT_DIR:-$HOME/.config/whisper-alternative}"
HS_DIR="${HAMMERSPOON_DIR:-$HOME/.hammerspoon}"
rm -rf "$APP_DIR" /tmp/whisper-alternative "$HS_DIR/whisper_alternative.lua"
if [ -f "$HS_DIR/init.lua" ]; then
  sed -i '' '/-- Whisper Alternative (local voice dictation)/d;/require("whisper_alternative")/d' "$HS_DIR/init.lua"
fi
if [ "${WA_SKIP_BREW:-0}" != 1 ] && command -v hs >/dev/null 2>&1; then hs -c "hs.reload()" >/dev/null 2>&1 || true; fi
echo "Removed. To also remove the tools: brew uninstall whisper-cpp sox && brew uninstall --cask hammerspoon"
