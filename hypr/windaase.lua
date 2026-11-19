-- Omarchy-windaase: Windows-style window management & ergonomics for Hyprland.
-- Usage in ~/.config/hypr/hyprland.lua:
--   require("hypr.windaase").setup()

local geometry = require("hypr.windaase.geometry")
local snap = require("hypr.windaase.snap")
local snap_layouts = require("hypr.windaase.snap_layouts")
local focus = require("hypr.windaase.focus")
local show_desktop = require("hypr.windaase.show_desktop")

local M = {}

local DEFAULTS = {
  aero_snap = true,
  snap_layouts = true,
  soft_maximize = true,
  auto_raise = true,
  hover_scroll = true,
  shortcuts = true,
  gap_out = 8,
  gap_in = 8,
}

local function load_user_config()
  local home = os.getenv("HOME") or ""
  if home == "" then
    return nil
  end
  local f = io.open(home .. "/.config/omarchy/windaase.json", "r")
  if not f then
    return nil
  end
  local raw = f:read("*a")
  f:close()
  local ok, parsed = pcall(geometry.decode_json, raw)
  if ok and type(parsed) == "table" then
    return parsed
  end
  return nil
end

local function merge_opts(user_opts)
  local opts = {}
  for k, v in pairs(DEFAULTS) do
    opts[k] = v
  end
  local disk_opts = load_user_config()
  if type(disk_opts) == "table" then
    for k, v in pairs(disk_opts) do
      if DEFAULTS[k] ~= nil and type(v) == type(DEFAULTS[k]) then
        opts[k] = v
      end
    end
  end
  if type(user_opts) == "table" then
    for k, v in pairs(user_opts) do
      opts[k] = v
    end
  end
  return opts
end

function M.setup(user_opts)
  local opts = merge_opts(user_opts)

  snap.setup(opts, function(ticks)
    snap_layouts.suppress(ticks)
  end)

  snap_layouts.setup(opts)

  if opts.hover_scroll then
    focus.setup()
  end

  if opts.shortcuts then
    o.bind("ALT + F4", "Close window", hl.dsp.window.close())
    o.bind("SUPER + D", "Show desktop", show_desktop.toggle)
    o.bind("SUPER + E", "File manager", { omarchy = "nautilus" })
    o.rebind("SUPER + ALT + SPACE", "Apps", "omarchy-shell riisager.windaase apps")
  end
end

M.snap = snap.apply_snap
M.show_desktop = show_desktop.toggle
M.toggle_snap_layouts = snap_layouts.toggle_click_overlay

return M
