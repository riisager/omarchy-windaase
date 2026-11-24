-- Shared lifecycle, dry-run detection, and Omarchy keybindings-menu helpers
-- for hypr.windaase Lua modules.

local M = {}

function M.bump_generation()
  local next_gen = (tonumber(_G.__omarchy_windaase_gen) or 0) + 1
  _G.__omarchy_windaase_gen = next_gen
  return next_gen
end

function M.generation()
  return tonumber(_G.__omarchy_windaase_gen) or 0
end

-- Returns false under omarchy-menu-keybindings' `lua -E` noop stub so dry-run
-- scans still collect shortcuts without mutating live IPC state or timers.
function M.is_live_compositor()
  if not hl or type(hl.timer) ~= "function" or type(hl.get_monitors) ~= "function" then
    return false
  end
  if type(hl.get_config) == "function"
    and hl.get_config("general.border_size") == nil
    and hl.get_config("input.follow_mouse") == nil then
    return false
  end
  return true
end

function M.timer(fn, opts)
  if type(fn) ~= "function" or not M.is_live_compositor() then
    return false
  end
  local expected_gen = M.generation()
  hl.timer(function()
    if expected_gen ~= M.generation() then
      return
    end
    fn()
  end, opts)
  return true
end

function M.shell_quote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- Registers a Lua callback shortcut with Omarchy's keybindings menu command
-- table so invoking it from Super+K dispatches through `hyprctl eval`.
function M.rebind_fn(keys, description, fn, windaase_call, opts)
  if type(o) ~= "table" then
    return
  end
  if type(o.bind_commands) == "table" and type(windaase_call) == "string" and windaase_call ~= "" then
    o.bind_commands[fn] = "hyprctl eval " .. M.shell_quote('require("hypr.windaase").' .. windaase_call)
  end
  if type(o.rebind) == "function" then
    o.rebind(keys, description, fn, opts)
  end
end

return M
