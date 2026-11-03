#!/usr/bin/env python3
"""Whisper Alternative — local, offline voice dictation for macOS.

Flow:  hotkey (Hammerspoon) -> this script -> sox records the mic
       -> hotkey again -> whisper.cpp transcribes -> text pasted at the cursor

Usage:
    dictate.py <mode>      toggle recording for a mode defined in config.json
    dictate.py --check     verify dependencies, models, sounds and config
    dictate.py --list      print the configured modes and their hotkeys

Everything runs on your Mac. No audio ever leaves the machine.
Only the Python standard library is used (works with the macOS-bundled python3).
"""

import json
import os
import subprocess
import sys
import threading
import time
import urllib.request

# --- Locations -------------------------------------------------------------
# Override with WHISPER_ALT_DIR when testing from a clone.
APP_DIR = os.path.expanduser(
    os.environ.get("WHISPER_ALT_DIR", "~/.config/whisper-alternative")
)
CONFIG_FILE = os.path.join(APP_DIR, "config.json")

STATE_DIR = "/tmp/whisper-alternative"
AUDIO_FILE = os.path.join(STATE_DIR, "recording.wav")
PID_FILE = os.path.join(STATE_DIR, "sox.pid")
TIME_FILE = os.path.join(STATE_DIR, "start_time")
MODE_FILE = os.path.join(STATE_DIR, "mode")
LOG_FILE = os.path.join(STATE_DIR, "dictate.log")

DEFAULTS = {
    "whisper_cli": "/opt/homebrew/bin/whisper-cli",
    "sox": "/opt/homebrew/bin/sox",
    "models_dir": "~/.config/whisper-alternative/models",
    "sounds_dir": "~/.config/whisper-alternative/sounds",
    "start_sound": "sparkle_musicbox",
    "stop_sound": "sparkle_close",
    "min_record_seconds": 1.0,
    "mic_gain_db": 20,
    "menubar_icon": "♥",
    "modes": {},
}

GENERATE_PROMPT = (
    "The user spoke these instructions. Follow them exactly and create "
    "the requested content. Return ONLY the final content, nothing else."
)


# --- Helpers ---------------------------------------------------------------
def log(msg):
    os.makedirs(STATE_DIR, exist_ok=True)
    with open(LOG_FILE, "a") as f:
        f.write(f"{time.strftime('%H:%M:%S')} {msg}\n")


def load_config():
    if not os.path.exists(CONFIG_FILE):
        sys.exit(f"config.json not found at {CONFIG_FILE}. Run install.sh first.")
    with open(CONFIG_FILE) as f:
        cfg = json.load(f)
    merged = dict(DEFAULTS)
    merged.update(cfg)
    merged["models_dir"] = os.path.expanduser(merged["models_dir"])
    merged["sounds_dir"] = os.path.expanduser(merged["sounds_dir"])
    return merged


def model_path(cfg, mode):
    return os.path.join(cfg["models_dir"], mode["model"])


def find_sound(cfg, name):
    """Custom sounds in sounds_dir win over macOS system sounds."""
    if not name:
        return None
    for ext in ("", ".wav", ".aiff", ".mp3", ".m4a"):
        candidate = os.path.join(cfg["sounds_dir"], name + ext)
        if os.path.isfile(candidate):
            return candidate
    system = f"/System/Library/Sounds/{name}.aiff"
    return system if os.path.isfile(system) else None


def play_sound(cfg, name, wait=False):
    """afplay is a child process: if this script exits while it is still
    playing, the sound is cut off. Pass wait=True on the start path."""
    path = find_sound(cfg, name)
    if not path:
        return
    proc = subprocess.Popen(
        ["afplay", path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    if wait:
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()


# --- Recording -------------------------------------------------------------
def start_recording(cfg, mode_name):
    os.makedirs(STATE_DIR, exist_ok=True)
    if os.path.exists(AUDIO_FILE):
        os.remove(AUDIO_FILE)

    cmd = [cfg["sox"], "-d", "-r", "16000", "-c", "1", "-b", "16", AUDIO_FILE]
    if cfg.get("mic_gain_db"):
        cmd += ["gain", str(cfg["mic_gain_db"])]
    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    with open(PID_FILE, "w") as f:
        f.write(str(proc.pid))
    with open(TIME_FILE, "w") as f:
        f.write(str(time.time()))
    with open(MODE_FILE, "w") as f:
        f.write(mode_name)

    log(f"Recording started ({mode_name}), PID={proc.pid}")
    play_sound(cfg, cfg["start_sound"], wait=True)


def stop_recording():
    if not os.path.exists(PID_FILE):
        return False
    with open(PID_FILE) as f:
        pid = int(f.read().strip())
    try:
        os.kill(pid, 2)  # SIGINT lets sox flush and close the WAV cleanly
        for _ in range(30):
            try:
                os.kill(pid, 0)
                time.sleep(0.1)
            except ProcessLookupError:
                break
    except ProcessLookupError:
        pass
    os.remove(PID_FILE)
    return os.path.exists(AUDIO_FILE)


# --- Transcription ---------------------------------------------------------
def transcribe(cfg, mode):
    out_base = os.path.join(STATE_DIR, "transcript")
    cmd = [
        cfg["whisper_cli"],
        "-m", model_path(cfg, mode),
        "-f", AUDIO_FILE,
        "--no-timestamps",
        "--output-txt",
        "--output-file", out_base,
    ]
    lang = mode.get("language", "auto")
    if lang != "auto":
        cmd += ["-l", lang]
    if mode.get("prompt"):
        cmd += ["--prompt", mode["prompt"]]

    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        log(f"whisper-cli failed: {result.stderr[-400:]}")

    txt = out_base + ".txt"
    if os.path.exists(txt):
        with open(txt) as f:
            text = f.read().strip()
        return text.replace("[BLANK_AUDIO]", "").strip()
    return ""


def ollama_generate(mode, prompt):
    url = mode.get("ollama_url", "http://localhost:11434/api/generate")
    data = json.dumps({
        "model": mode["ollama_model"],
        "prompt": prompt,
        "system": mode.get("system_prompt", GENERATE_PROMPT),
        "stream": False,
        "options": {"temperature": 0},
    }).encode()
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.loads(resp.read().decode()).get("response", "").strip() or prompt
    except Exception as e:  # Ollama not running / model missing: paste the raw text
        log(f"Ollama error: {e}")
        return prompt


def paste_text(text):
    proc = subprocess.Popen(["pbcopy"], stdin=subprocess.PIPE)
    proc.communicate(text.encode())
    time.sleep(0.1)
    subprocess.run(
        ["osascript", "-e",
         'tell application "System Events" to keystroke "v" using command down'],
        capture_output=True,
    )


# --- Toggle ----------------------------------------------------------------
def toggle(cfg, mode_name):
    modes = cfg["modes"]
    if mode_name not in modes:
        sys.exit(f"Unknown mode '{mode_name}'. Known: {', '.join(modes)}")

    if not os.path.exists(PID_FILE):
        start_recording(cfg, mode_name)
        return

    # Second press: stop and transcribe with the mode that STARTED the recording.
    if os.path.exists(TIME_FILE):
        with open(TIME_FILE) as f:
            elapsed = time.time() - float(f.read().strip())
        if elapsed < float(cfg["min_record_seconds"]):
            log(f"Too short ({elapsed:.1f}s), ignoring stop")
            return
    if os.path.exists(MODE_FILE):
        with open(MODE_FILE) as f:
            started_with = f.read().strip()
        if started_with in modes:
            mode_name = started_with
    mode = modes[mode_name]

    play_sound(cfg, cfg["stop_sound"])
    if not stop_recording():
        log("No audio file found")
        return

    text = transcribe(cfg, mode)
    if not text:
        log("No speech detected")
        return

    if mode.get("ollama_model"):
        text = ollama_generate(mode, text)

    paste_text(text)
    log(f"Pasted ({mode_name}): {text[:100]}")


# --- Diagnostics -----------------------------------------------------------
def check():
    ok = True

    def row(good, label, detail=""):
        nonlocal ok
        ok = ok and good
        print(f"  {'OK ' if good else 'MISSING'}  {label}  {detail}")

    print(f"Config: {CONFIG_FILE}")
    if not os.path.exists(CONFIG_FILE):
        print("  MISSING  config.json (run install.sh)")
        return 1
    cfg = load_config()
    row(os.access(cfg["whisper_cli"], os.X_OK), "whisper-cli", cfg["whisper_cli"])
    row(os.access(cfg["sox"], os.X_OK), "sox", cfg["sox"])
    row(os.path.isdir("/Applications/Hammerspoon.app"), "Hammerspoon.app")
    row(find_sound(cfg, cfg["start_sound"]) is not None, "start sound", cfg["start_sound"])
    row(find_sound(cfg, cfg["stop_sound"]) is not None, "stop sound", cfg["stop_sound"])
    print("Modes:")
    for name, mode in cfg["modes"].items():
        if mode.get("enabled") is False:
            print(f"  off      {name} (disabled)")
            continue
        p = model_path(cfg, mode)
        row(os.path.isfile(p), f"{name:12s} {mode.get('hotkey', '-'):12s}",
            f"lang={mode.get('language', 'auto')} model={mode['model']}")
    print("\nAll good." if ok else "\nSomething is missing. See README > Troubleshooting.")
    return 0 if ok else 1


def list_modes():
    cfg = load_config()
    for name, mode in cfg["modes"].items():
        state = "" if mode.get("enabled", True) else "  (disabled)"
        print(f"{mode.get('hotkey', '-'):12s} {name:12s} {mode.get('language', 'auto')}{state}")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    arg = sys.argv[1]
    if arg == "--check":
        sys.exit(check())
    if arg == "--list":
        list_modes()
        return
    toggle(load_config(), arg.lower())


if __name__ == "__main__":
    main()
