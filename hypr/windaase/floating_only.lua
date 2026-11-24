-- Optional floating-only lockdown for Windows-style workflows:
--   * Keeps all workspaces in Omarchy's floating mode (including accidental bar icon clicks)
--   * Rebinds Super+L to lock screen (Win+L) and unbinds tiling/layout-switch keys
-- Fully reversible on reload when floating_only = false.

local M = {}

local enabled = false
local orig_workspace_mode = nil
local hooks_registered = false
local sync_seq = 0

local function shell_quote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function helper_script_path()
  local home = os.getenv("HOME") or ""
  if home == "" then
    return nil
  end
  local path = home .. "/.config/omarchy/plugins/riisager.windaase/windaase-config.py"
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  f:close()
  return path
end

local function schedule_sync_workspace_state(ws_id)
  sync_seq = sync_seq + 1
  local seq = sync_seq
  local target_ws = ws_id ~= nil and tostring(ws_id) or nil
  hl.timer(function()
    if not enabled or seq ~= sync_seq then
      return
    end
    local helper = helper_script_path()
    if not helper then
      return
    end
    local cmd = "python3 " .. shell_quote(helper) .. " enforce-floating-workspace"
    if target_ws and target_ws:match("^[1-9][0-9]*$") then
      cmd = cmd .. " " .. shell_quote(target_ws)
    end
    hl.exec_cmd(cmd)
  end, { type = "oneshot", timeout = 150 })
end

local function ensure_workspace_floating(ws_id)
  local n = tonumber(ws_id)
  if not orig_workspace_mode or not n or n < 1 then
    return
  end
  pcall(orig_workspace_mode, { workspace = tostring(n), mode = "floating" })
end

local function install_workspace_mode_guard()
  if type(o) ~= "table" or type(o.workspace_mode) ~= "function" then
    return
  end
  if orig_workspace_mode == nil then
    orig_workspace_mode = o.workspace_mode
  end
  o.workspace_mode = function(spec)
    if not enabled or type(spec) ~= "table" then
      return orig_workspace_mode(spec)
    end
    if spec.default ~= nil and spec.default ~= "floating" then
      orig_workspace_mode({ default = "floating" })
      schedule_sync_workspace_state(nil)
      return
    end
    if spec.workspace ~= nil and spec.mode ~= nil and spec.mode ~= "floating" then
      local ws_id = tostring(spec.workspace)
      orig_workspace_mode({ workspace = ws_id, mode = "floating" })
      schedule_sync_workspace_state(ws_id)
      return
    end
    return orig_workspace_mode(spec)
  end
end

local function restore_workspace_mode()
  if type(o) == "table" and orig_workspace_mode ~= nil then
    o.workspace_mode = orig_workspace_mode
  end
end

function M.setup(opts)
  enabled = type(opts) == "table" and opts.floating_only == true
  if not enabled then
    restore_workspace_mode()
    return
  end

  install_workspace_mode_guard()

  if orig_workspace_mode ~= nil then
    pcall(orig_workspace_mode, { default = "floating" })
    for _, ws in ipairs(hl.get_workspaces() or {}) do
      ensure_workspace_floating(ws and ws.id)
    end
  end

  if not hooks_registered then
    hooks_registered = true
    hl.on("workspace.active", function(workspace)
      if not enabled then
        return
      end
      local ws_id = workspace and workspace.id
      if ws_id == nil then
        local active = hl.get_active_workspace()
        ws_id = active and active.id
      end
      ensure_workspace_floating(ws_id)
    end)
  end

  -- Windows-style Win+L locks screen; disable accidental tiling/layout-switch keys.
  o.rebind("SUPER + L", "Lock system", "omarchy-system-lock")
  local tiling_binds = {
    "SUPER + ALT + L",
    "SUPER + T",
    "SUPER + J",
    "SUPER + CTRL + F",
    "SUPER + G",
  }
  if type(opts) == "table" and opts.shortcuts == false then
    tiling_binds[#tiling_binds + 1] = "SUPER + P"
  end
  for _, keys in ipairs(tiling_binds) do
    pcall(hl.unbind, keys)
  end
end

return M
