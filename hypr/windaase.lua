-- Omarchy-windaase: Windows-style window management & ergonomics for Hyprland.
-- Usage in ~/.config/hypr/hyprland.lua:
--   require("hypr.windaase").setup()

local geometry = require("hypr.windaase.geometry")
local snap = require("hypr.windaase.snap")
local snap_layouts = require("hypr.windaase.snap_layouts")
local snap_resize = require("hypr.windaase.snap_resize")
local focus = require("hypr.windaase.focus")
local show_desktop = require("hypr.windaase.show_desktop")

local M = {}

local DEFAULTS = {
  aero_snap = true,
  snap_layouts = true,
  snap_assist = true,
  snap_resize = true,
  ultrawide_layout = false,
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

  snap.setup(
    opts,
    function(ticks)
      snap_layouts.suppress(ticks)
    end,
    function(window, m, zone_spec)
      snap_layouts.schedule_assist(window, m, zone_spec)
    end
  )

  snap_layouts.setup(opts)
  snap_resize.setup(opts, snap_layouts.write_state, snap_layouts.suppress)

  if opts.hover_scroll then
    focus.setup()
  end

  if opts.shortcuts then
    o.bind("ALT + F4", "Close window", hl.dsp.window.close())
    o.bind("SUPER + D", "Show desktop", show_desktop.toggle)
    o.bind("SUPER + E", "File manager", { omarchy = "nautilus" })
    o.rebind("SUPER + ALT + SPACE", "Apps", "omarchy-shell riisager.windaase apps")
    o.rebind("SUPER + Home", "Minimize other windows (or restore tiled width)", function()
      local w = hl.get_active_window()
      if w and w.floating then
        show_desktop.toggle_minimize_others()
      else
        hl.exec_cmd("omarchy-hyprland-window-width restore")
      end
    end)
    o.bind("SUPER + ALT + P", "Toggle always on top", function()
      local w = hl.get_active_window()
      if not w then
        return
      end
      if not w.floating and not w.pinned then
        hl.dispatch(hl.dsp.window.float({ action = "on", window = w }))
      end
      hl.dispatch(hl.dsp.window.pin({ window = w }))
      if not w.pinned then
        hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", window = w }))
      end
    end)
  end
end

M.snap = snap.apply_snap
M.snap_resize = snap_resize.resize_by_keyboard
M.move_to_monitor = snap.move_to_monitor
M.show_desktop = show_desktop.toggle
M.minimize_others = show_desktop.toggle_minimize_others
M.toggle_snap_layouts = snap_layouts.toggle_click_overlay

return M
