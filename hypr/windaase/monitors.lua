-- Automatic dock-profile application for Hyprland monitor hotplug & reload.

local runtime = require("hypr.windaase.runtime")

local M = {}

local hooks_registered = false
local apply_seq = 0

local function helper_script_path()
  local home = os.getenv("HOME") or ""
  if home == "" then
    return nil
  end
  return home .. "/.config/omarchy/plugins/riisager.windaase/windaase-config.py"
end

local function profiles_db_exists()
  local home = os.getenv("HOME") or ""
  if home == "" then
    return false
  end
  local f = io.open(home .. "/.config/omarchy/windaase-monitors.json", "r")
  if not f then
    return false
  end
  f:close()
  return true
end

local function any_monitor_enabled()
  return #(hl.get_monitors() or {}) > 0
end

function M.apply_profile()
  if not profiles_db_exists() and any_monitor_enabled() then
    return false
  end
  local helper = helper_script_path()
  if not helper then
    return false
  end
  local f = io.open(helper, "r")
  if not f then
    return false
  end
  f:close()
  hl.exec_cmd("python3 " .. runtime.shell_quote(helper) .. " monitors-apply")
  return true
end

local function schedule_apply(delay_ms)
  apply_seq = apply_seq + 1
  local seq = apply_seq
  runtime.timer(function()
    if seq == apply_seq then
      M.apply_profile()
    end
  end, { type = "oneshot", timeout = delay_ms or 350 })
end

function M.setup(_opts)
  if not runtime.is_live_compositor() then
    return
  end
  if not hooks_registered then
    hooks_registered = true
    hl.on("hyprland.start", function() schedule_apply(350) end)
    hl.on("monitor.added", function() schedule_apply(650) end)
    hl.on("monitor.removed", function() schedule_apply(650) end)
  end

  schedule_apply(350)
end

return M
