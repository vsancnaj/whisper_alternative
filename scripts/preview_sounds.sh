#!/usr/bin/env bash
# Play every sound in the sounds folder so you can pick your favourites.
# Usage: scripts/preview_sounds.sh [folder]   (default: the repo's sounds/)
set -euo pipefail
DIR="${1:-$(cd "$(dirname "$0")/.." && pwd)/sounds}"
for f in "$DIR"/*.{wav,aiff,mp3,m4a}; do
  [ -e "$f" ] || continue
  name="$(basename "${f%.*}")"
  printf '▶ %s\n' "$name"
  afplay "$f"
  sleep 0.4
done
echo
echo "Set your picks in ~/.config/whisper-alternative/config.json:"
echo '  "start_sound": "sparkle_musicbox",  "stop_sound": "sparkle_close"'
