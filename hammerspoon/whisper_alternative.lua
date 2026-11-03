-- Whisper Alternative — Hammerspoon hotkeys for local voice dictation.
--
-- Installed by install.sh into ~/.hammerspoon/ and loaded from init.lua with:
--     whisperAlternative = require("whisper_alternative")
-- (global on purpose: a local table would be garbage-collected and the
--  menu bar icon would vanish).
--
-- Nothing to edit here. Hotkeys, languages and sounds live in
-- ~/.config/whisper-alternative/config.json. After editing it, reload
-- Hammerspoon (Hammerspoon menu bar icon > Reload Config, or quit and reopen Hammerspoon).

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
  for p in string.gmatch(string.lower((str:gsub("%s", ""))), "[^+]+") do parts[#parts + 1] = p end
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
  task = hs.task.new(PYTHON, function(exitCode, _, stdErr)
    runningTasks[task] = nil
    if exitCode ~= 0 then
      -- Surface failures instead of a silent "hotkey does nothing".
      local msg = (stdErr or ""):gsub("%s+$", ""):match("([^\n]*)$") or ""
      hs.alert.show("Whisper Alternative failed" .. (msg ~= "" and (": " .. msg) or ". See /tmp/whisper-alternative/dictate.log"), 6)
    end
  end, {SCRIPT, mode})
  runningTasks[task] = true
  task:start()
end

local bound = 0
local seenHotkeys = {}
for name, mode in pairs(config.modes or {}) do
  if mode.enabled ~= false and mode.hotkey and mode.hotkey ~= "" then
    local mods, key = parseHotkey(mode.hotkey)
    local combo = table.concat(mods, "+") .. "+" .. tostring(key)
    if seenHotkeys[combo] then
      hs.alert.show("Whisper Alternative: " .. name .. " and " .. seenHotkeys[combo] .. " share the hotkey " .. mode.hotkey, 6)
    end
    seenHotkeys[combo] = seenHotkeys[combo] or name
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
