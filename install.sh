#!/usr/bin/env bash
# Whisper Alternative — one-command installer for macOS.
#
#   ./install.sh                 interactive (asks hotkeys, languages, sounds)
#   ./install.sh --yes           accept all defaults, no questions
#   ./install.sh --config my.json  use a config you prepared (see config.example.json)
#   ./install.sh --check         only run diagnostics
#   ./install.sh --no-download   do not download Whisper models (testing)
#
# Safe to re-run: it never overwrites an existing config.json unless --config is given,
# and it never re-downloads a model that is already there.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="${WHISPER_ALT_DIR:-$HOME/.config/whisper-alternative}"
HS_DIR="${HAMMERSPOON_DIR:-$HOME/.hammerspoon}"
MODEL_BASE_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main"

YES=0; CONFIG_SRC=""; CHECK_ONLY=0; NO_DOWNLOAD=0
while [ $# -gt 0 ]; do
  case "$1" in
    --yes|-y) YES=1 ;;
    --config) CONFIG_SRC="$2"; shift ;;
    --check) CHECK_ONLY=1 ;;
    --no-download) NO_DOWNLOAD=1 ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
  shift
done

say()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
ask()  { # ask VAR "prompt" "default"
  local var="$1" prompt="$2" def="$3" ans
  if [ "$YES" = 1 ]; then printf -v "$var" '%s' "$def"; return; fi
  read -r -p "$prompt [$def]: " ans </dev/tty
  printf -v "$var" '%s' "${ans:-$def}"
}

[ "$(uname)" = "Darwin" ] || { echo "This only runs on macOS."; exit 1; }

if [ "$CHECK_ONLY" = 1 ]; then
  WHISPER_ALT_DIR="$APP_DIR" /usr/bin/python3 "$APP_DIR/dictate.py" --check
  exit $?
fi

# 1. Dependencies -------------------------------------------------------------
say "1/5  Dependencies"
# Homebrew may be installed but not on PATH yet (fresh Macs, Apple Silicon or Intel).
for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
  if ! command -v brew >/dev/null 2>&1 && [ -x "$b" ]; then eval "$("$b" shellenv)"; fi
done
if [ "${WA_SKIP_BREW:-0}" != 1 ] && ! command -v brew >/dev/null 2>&1; then
  cat <<MSG
Homebrew is not installed. Open Terminal, paste this line, press Enter, and
follow the prompts (it asks for your Mac password):

  /bin/bash -c "\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

When it finishes, run the "Next steps" commands it prints (they add Homebrew to
your PATH), then come back and run:

  cd "$REPO_DIR" && ./install.sh
MSG
  exit 1
fi
if [ "${WA_SKIP_BREW:-0}" != 1 ]; then
  brew list whisper-cpp >/dev/null 2>&1 || brew install whisper-cpp
  brew list sox         >/dev/null 2>&1 || brew install sox
  [ -d /Applications/Hammerspoon.app ] || brew install --cask hammerspoon
fi
WHISPER_CLI="$(command -v whisper-cli || echo /opt/homebrew/bin/whisper-cli)"
SOX_BIN="$(command -v sox || echo /opt/homebrew/bin/sox)"
echo "  whisper-cli: $WHISPER_CLI"
echo "  sox:         $SOX_BIN"

# 2. App files ----------------------------------------------------------------
say "2/5  Copying files to $APP_DIR"
mkdir -p "$APP_DIR/models" "$APP_DIR/sounds"
cp "$REPO_DIR/dictate.py" "$APP_DIR/dictate.py"
cp -n "$REPO_DIR/sounds/"* "$APP_DIR/sounds/" 2>/dev/null || true  # never overwrite sounds you changed
chmod +x "$APP_DIR/dictate.py"

# 3. Config -------------------------------------------------------------------
say "3/5  Configuration"
CONFIG="$APP_DIR/config.json"
if [ -n "$CONFIG_SRC" ]; then
  [ "$(cd "$(dirname "$CONFIG_SRC")" && pwd)/$(basename "$CONFIG_SRC")" = "$CONFIG" ] || cp "$CONFIG_SRC" "$CONFIG"
  echo "  Using $CONFIG_SRC"
  # The example config hard-codes Apple Silicon paths: point them at the real binaries.
  WHISPER_CLI="$WHISPER_CLI" SOX_BIN="$SOX_BIN" /usr/bin/python3 - "$CONFIG" <<'PY'
import json, os, sys
c = json.load(open(sys.argv[1]))
for key, env in (("whisper_cli", "WHISPER_CLI"), ("sox", "SOX_BIN")):
    if not os.access(os.path.expanduser(c.get(key, "")), os.X_OK) and os.access(os.environ[env], os.X_OK):
        c[key] = os.environ[env]
        print(f"  {key} -> {c[key]}")
json.dump(c, open(sys.argv[1], "w"), indent=2, ensure_ascii=False)
PY
elif [ -f "$CONFIG" ]; then
  echo "  Keeping your existing $CONFIG (edit it to change hotkeys/languages/sounds)"
else
  SOUNDS="$(cd "$APP_DIR/sounds" && ls | sed 's/\.[^.]*$//' | tr '\n' ' ')"
  echo "  Sounds available: $SOUNDS"
  echo "  (preview them any time with: scripts/preview_sounds.sh)"
  echo "  Type a name from the list, a macOS sound (Tink, Pop, Glass ...), or 'none' for silence."
  ask START_SOUND "  Sound when recording starts" "sparkle_musicbox"
  ask STOP_SOUND  "  Sound when recording stops"  "sparkle_close"
  fix_sound() { # fix_sound VAR default: 'none' -> silence, unknown name -> default
    local v="${!1}"
    if [ "$(echo "$v" | tr 'A-Z' 'a-z')" = "none" ]; then printf -v "$1" '%s' ""; return; fi
    if ls "$APP_DIR/sounds/" | sed 's/\.[^.]*$//' | grep -qx "$v" || [ -f "/System/Library/Sounds/$v.aiff" ]; then return; fi
    echo "  '$v' is not a known sound, using $2 instead"; printf -v "$1" '%s' "$2"
  }
  fix_sound START_SOUND sparkle_musicbox
  fix_sound STOP_SOUND sparkle_close
  echo
  echo "  Hotkeys are written like ctrl+e, alt+cmd+d, ctrl+shift+s. Type 'none' to skip a mode."
  ask HK_EN   "  Hotkey for English dictation" "ctrl+e"
  ask LANGS   "  Other languages, comma-separated Whisper codes (es, de, fr, nl, it, pt, ja ...) or 'none'" "es"
  declare -a EXTRA=()
  if [ "$LANGS" != "none" ]; then
    for code in $(echo "$LANGS" | tr ',' ' '); do
      code="$(echo "$code" | tr -d ' ' | tr 'A-Z' 'a-z')"; [ -n "$code" ] || continue
      case "$code" in
        es) def="ctrl+s" ;; de) def="alt+cmd+d" ;; nl) def="alt+cmd+n" ;; fr) def="alt+cmd+f" ;;
        it) def="alt+cmd+i" ;; pt) def="alt+cmd+p" ;; *) def="alt+cmd+${code:0:1}" ;;
      esac
      ask hk "  Hotkey for '$code'" "$def"
      EXTRA+=("$code=$hk")
    done
  fi
  ask HK_AUTO "  Hotkey for auto-detect language (mixes languages in one take)" "ctrl+t"
  ask SIZE    "  Model size: base (fast, ~150 MB) or small (more accurate, ~500 MB)" "base"
  ask ICON    "  Menu bar icon (any character, or 'none')" "♥"

  START_SOUND="$START_SOUND" STOP_SOUND="$STOP_SOUND" HK_EN="$HK_EN" HK_AUTO="$HK_AUTO" \
  SIZE="$SIZE" ICON="$ICON" EXTRA="${EXTRA[*]:-}" WHISPER_CLI="$WHISPER_CLI" SOX_BIN="$SOX_BIN" \
  APP_DIR="$APP_DIR" /usr/bin/python3 - "$CONFIG" <<'PY'
import json, os, sys
e = os.environ
size = "small" if e["SIZE"].strip().lower().startswith("s") else "base"
modes = {}
if e["HK_EN"].lower() != "none":
    modes["english"] = {"hotkey": e["HK_EN"], "language": "en", "model": f"ggml-{size}.en.bin"}
names = {"es": "spanish", "de": "german", "fr": "french", "nl": "dutch", "it": "italian",
         "pt": "portuguese", "ja": "japanese", "zh": "chinese", "ko": "korean", "ru": "russian"}
for pair in e["EXTRA"].split():
    code, hk = pair.split("=", 1)
    if hk.lower() != "none":
        modes[names.get(code, code)] = {"hotkey": hk, "language": code, "model": f"ggml-{size}.bin"}
if e["HK_AUTO"].lower() != "none":
    modes["auto"] = {"hotkey": e["HK_AUTO"], "language": "auto", "model": f"ggml-{size}.bin"}
modes["generate"] = {"enabled": False, "hotkey": "alt+cmd+g", "language": "en",
                     "model": f"ggml-{size}.en.bin",
                     "ollama_url": "http://localhost:11434/api/generate",
                     "ollama_model": "qwen2.5:0.5b"}
cfg = {
    "whisper_cli": e["WHISPER_CLI"], "sox": e["SOX_BIN"],
    "models_dir": os.path.join(e["APP_DIR"], "models"),
    "sounds_dir": os.path.join(e["APP_DIR"], "sounds"),
    "start_sound": e["START_SOUND"], "stop_sound": e["STOP_SOUND"],
    "menubar_icon": "" if e["ICON"].lower() == "none" else e["ICON"],
    "min_record_seconds": 1.0, "mic_gain_db": 20, "modes": modes,
}
seen = {}
for name, m in modes.items():
    if m.get("enabled", True) and m["hotkey"] in seen:
        print(f"  WARNING: '{name}' and '{seen[m['hotkey']]}' share hotkey {m['hotkey']}; edit config.json")
    seen.setdefault(m["hotkey"], name)
with open(sys.argv[1], "w") as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False); f.write("\n")
print(f"  Wrote {sys.argv[1]}")
PY
fi

# 4. Models -------------------------------------------------------------------
say "4/5  Whisper models"
MODELS_DIR="$(/usr/bin/python3 -c "import json,os;print(os.path.expanduser(json.load(open('$CONFIG')).get('models_dir','$APP_DIR/models')))")"
mkdir -p "$MODELS_DIR"
NEEDED="$(/usr/bin/python3 -c "
import json; c=json.load(open('$CONFIG'))
print(' '.join(sorted({m['model'] for m in c['modes'].values() if m.get('enabled',True)})))")"
for m in $NEEDED; do
  if [ -f "$MODELS_DIR/$m" ]; then
    echo "  $m already present"
  else
    if [ "$NO_DOWNLOAD" = 1 ]; then echo "  Skipping $m (--no-download)"; continue; fi
    echo "  Downloading $m (this can take a few minutes) ..."
    PART="${MODELS_DIR:?}/${m:?}.part"
    curl -fL --progress-bar -o "$PART" "$MODEL_BASE_URL/$m" \
      || { rm -f "$PART"; echo "  Download of $m failed. Check your internet connection and run ./install.sh again."; exit 1; }
    if [ "$(wc -c < "$PART")" -lt 10000000 ]; then
      rm -f "$PART"; echo "  $m downloaded incompletely. Run ./install.sh again."; exit 1
    fi
    mv "$PART" "$MODELS_DIR/$m"
  fi
done

# 5. Hammerspoon --------------------------------------------------------------
say "5/5  Hammerspoon hotkeys"
mkdir -p "$HS_DIR"
cp "$REPO_DIR/hammerspoon/whisper_alternative.lua" "$HS_DIR/whisper_alternative.lua"
INIT="$HS_DIR/init.lua"
touch "$INIT"
if ! grep -q 'require("whisper_alternative")' "$INIT"; then
  printf '\n-- Whisper Alternative (local voice dictation)\nwhisperAlternative = require("whisper_alternative")\n' >> "$INIT"
  echo "  Added require line to $INIT"
else
  echo "  $INIT already loads whisper_alternative"
fi
if [ "${WA_SKIP_BREW:-0}" != 1 ]; then
  open -a Hammerspoon 2>/dev/null || true
  sleep 1
  if command -v hs >/dev/null 2>&1; then hs -c "hs.reload()" >/dev/null 2>&1 || true; fi
fi

say "Diagnostics"
WHISPER_ALT_DIR="$APP_DIR" /usr/bin/python3 "$APP_DIR/dictate.py" --check || true

cat <<'MSG'

If Hammerspoon was already running, load the new hotkeys now: click its menu bar
icon (or open the app) and choose "Reload Config".

Three macOS permissions are asked the first time (one-off). Click Allow on each:
  1. Accessibility: System Settings > Privacy & Security > Accessibility > enable Hammerspoon
     (lets it listen for hotkeys).
  2. Microphone: press your dictation hotkey once; macOS asks to let Hammerspoon use the microphone.
  3. Automation: the first time text is pasted, macOS asks whether Hammerspoon may control
     "System Events". Click OK, otherwise the text stays on the clipboard but is not pasted.

Then: press the hotkey, hear the start sound, talk, press it again, see the text appear.
Change anything later in ~/.config/whisper-alternative/config.json and reload Hammerspoon.
MSG
