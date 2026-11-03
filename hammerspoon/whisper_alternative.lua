-- Whisper Alternative — Hammerspoon hotkeys for local voice dictation.
--
-- Installed by install.sh into ~/.hammerspoon/ and loaded from init.lua with:
--     whisperAlternative = require("whisper_alternative")
-- (global on purpose: a local table would be garbage-collected and the
--  menu bar icon would vanish).
--
-- Nothing to edit here. Hotkeys, languages and sounds live in
-- ~/.config/whisper-alternative/config.json. After editing it, reload
-- Hammerspoon (menu bar icon > Reload Config, or `hs -c "hs.reload()"`).

local M = {}

local APP_DIR = os.getenv("WHISPER_ALT_DIR") or (os.getenv("HOME") .. "/.config/whisper-alternative")
local CONFIG = APP_DIR .. "/config.json"
local SCRIPT = APP_DIR .. "/dictate.py"
local PYTHON = "/usr/bin/python3"

local config = hs.json.read(CONFIG)
if not config then
  hs.alert.show("Whisper Alternative: cannot read " .. CONFIG)
  return M
end

-- "ctrl+shift+e" -> {"ctrl","shift"}, "e"
local function parseHotkey(str)
  local parts = {}
  for p in string.gmatch(string.lower(str), "[^+]+") do parts[#parts + 1] = p end
  local key = table.remove(parts)
  return parts, key
end

local lastTrigger = {}
-- Retain running tasks: an hs.task that goes out of scope can be
-- garbage-collected mid-run, which kills the child process tree (and cuts
-- the start sound short).
local runningTasks = {}

local function runDictation(mode)
  local now = hs.timer.secondsSinceEpoch()
  if lastTrigger[mode] and (now - lastTrigger[mode]) < 1.0 then return end
  lastTrigger[mode] = now

  local task
  task = hs.task.new(PYTHON, function() runningTasks[task] = nil end, {SCRIPT, mode})
  runningTasks[task] = true
  task:start()
end

local bound = 0
for name, mode in pairs(config.modes or {}) do
  if mode.enabled ~= false and mode.hotkey and mode.hotkey ~= "" then
    local mods, key = parseHotkey(mode.hotkey)
    local ok, err = pcall(function()
      hs.hotkey.bind(mods, key, function() runDictation(name) end)
    end)
    if ok then
      bound = bound + 1
    else
      hs.alert.show("Whisper Alternative: bad hotkey for " .. name .. " (" .. tostring(mode.hotkey) .. ")")
    end
  end
end

if config.menubar_icon and config.menubar_icon ~= "" then
  M.menubar = hs.menubar.new()
  M.menubar:setTitle(config.menubar_icon)
  M.menubar:setTooltip("Whisper Alternative: " .. bound .. " dictation hotkeys")
end

hs.notify.new({
  title = "Whisper Alternative",
  informativeText = bound .. " dictation hotkey(s) loaded",
}):send()

return M
