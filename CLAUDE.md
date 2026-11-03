# Whisper Alternative — guide for AI assistants

This repo is a local, offline voice-dictation tool for macOS: a Hammerspoon hotkey
runs `dictate.py`, which records the microphone with sox, transcribes with
whisper.cpp, and pastes the text at the cursor. Read `README.md` for the human
view. This file tells you how to install, configure and debug it for a user.

## File map

| File | Role | Edit? |
|---|---|---|
| `install.sh` | installer: Homebrew deps, copies files, writes config, downloads models, wires Hammerspoon | rarely |
| `dictate.py` | the whole runtime (stdlib only, must run on macOS `/usr/bin/python3` 3.9) | for behaviour changes |
| `hammerspoon/whisper_alternative.lua` | reads `config.json`, binds one hotkey per mode | for hotkey mechanics only |
| `config.example.json` | documented template for `~/.config/whisper-alternative/config.json` | keep in sync with `dictate.py` |
| `sounds/*.wav` | start/stop cues (all under 2 s) | add, do not remove |
| `scripts/preview_sounds.sh`, `scripts/uninstall.sh` | helpers | |
| `docs/workflow.svg` | README diagram | |

Installed locations: `~/.config/whisper-alternative/` (config, script, models, sounds),
`~/.hammerspoon/whisper_alternative.lua`, one `require` line in `~/.hammerspoon/init.lua`,
runtime state and log in `/tmp/whisper-alternative/`.

## Setting it up for a user

1. **Ask these questions first** (one message, give the defaults):
   - Which hotkey for English? (default `ctrl+e`)
   - Which other languages, and a hotkey for each? (default Spanish on `ctrl+s`; format `ctrl+x`, `alt+cmd+x`, `ctrl+shift+x`)
   - An auto-detect hotkey for mixed-language speech? (default `ctrl+t`)
   - Start and stop sound? List `sounds/` names, offer to play them with `scripts/preview_sounds.sh` (default `sparkle_musicbox` / `sparkle_close`). The user can also supply their own file.
   - Model size: `base` (fast) or `small` (more accurate)?
2. **Write a config** from `config.example.json` with their answers and run
   `./install.sh --config /path/to/their.json`. Or run `./install.sh --yes` for all defaults.
   Never run `./install.sh` without a flag in a non-interactive session: it reads from `/dev/tty`.
3. Run `./install.sh --check` (equivalent to `~/.config/whisper-alternative/dictate.py --check`) and show the output.
4. Tell the user the two one-time permissions: Accessibility for Hammerspoon
   (System Settings → Privacy & Security → Accessibility) and Microphone (macOS prompts on the first hotkey press). You cannot grant these for them.
5. Ask them to click into a text field, press the hotkey, speak, press again, and confirm text appeared.

Re-running `install.sh` is safe: it keeps an existing `config.json` and skips models already downloaded.

## Changing things later

Everything is in `~/.config/whisper-alternative/config.json`; after editing, reload Hammerspoon
(`hs -c "hs.reload()"`, or Hammerspoon menu bar icon → Reload Config if the `hs` CLI is not installed).

- New language: add a mode `{"hotkey": ..., "language": "<whisper code>", "model": "ggml-base.bin"}`. Non-English needs a model without `.en`. Then `./install.sh --yes` to fetch a missing model.
- New sound: copy the file into `~/.config/whisper-alternative/sounds/`, set `start_sound`/`stop_sound` to its name without extension. macOS system sound names (`Tink`, `Pop`) also work. Empty string disables.
- Disable a mode without deleting it: `"enabled": false`.
- Generate mode (speech → local Ollama LLM → paste) ships disabled; it needs `ollama serve` and the model in `ollama_model`. If Ollama is unreachable the raw transcript is pasted.

## Debugging

- `dictate.py --check` reports every missing binary, model or sound.
- `dictate.py --list` prints modes and hotkeys as configured.
- `/tmp/whisper-alternative/dictate.log` has one line per start, stop, paste and error.
- To test transcription without the mic: `say -o /tmp/t.aiff "testing" && sox /tmp/t.aiff -r 16000 -c 1 -b 16 /tmp/whisper-alternative/recording.wav`, then call `dictate.transcribe()` from Python with the loaded config.
- `WHISPER_ALT_DIR=/some/dir` makes both `dictate.py` and `install.sh` use another app directory (useful for testing without touching the user's real setup). `HAMMERSPOON_DIR` does the same for the Lua side; `WA_SKIP_BREW=1` skips Homebrew and the Hammerspoon reload.
- Hotkey fires but nothing happens: Hammerspoon lacks Accessibility. Sound plays but no text: microphone permission, or `whisper-cli` error in the log.
- The second hotkey press transcribes with the mode that *started* the recording (stored in `/tmp/whisper-alternative/mode`), so pressing a different language's hotkey to stop is harmless.

## Rules

- Keep `dictate.py` standard-library only; the macOS-bundled Python 3.9 must run it.
- Never commit model files (`*.bin` is gitignored); `install.sh` downloads them from `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/<name>`.
- Configuration belongs in `config.json`, never hard-coded in the Lua or Python.
- Do not edit a user's `~/.hammerspoon/init.lua` beyond the single `require` line.
