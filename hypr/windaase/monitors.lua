-- Automatic dock-profile application for Hyprland monitor hotplug & reload.

local M = {}

local hooks_registered = false
local apply_seq = 0

local function shell_quote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function helper_script_path()
  local home = os.getenv("HOME") or ""
  if home == "" then
    return nil
  end
  return home .. "/.config/omarchy/plugins/riisager.windaase/windaase-config.py"
end

function M.apply_profile()
  local helper = helper_script_path()
  if not helper then
    return false
  end
  local f = io.open(helper, "r")
  if not f then
    return false
  end
  f:close()
  hl.exec_cmd("python3 " .. shell_quote(helper) .. " monitors-apply")
  return true
end

local function schedule_apply()
  apply_seq = apply_seq + 1
  local seq = apply_seq
  hl.timer(function()
    if seq == apply_seq then
      M.apply_profile()
    end
  end, { type = "oneshot", timeout = 150 })
end

function M.setup(_opts)
  if not hooks_registered then
    hooks_registered = true
    hl.on("hyprland.start", schedule_apply)
    hl.on("config.reloaded", schedule_apply)
    hl.on("monitor.added", schedule_apply)
    hl.on("monitor.removed", schedule_apply)
  end

  schedule_apply()
end

return M
