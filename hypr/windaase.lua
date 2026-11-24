-- Omarchy-windaase: Windows-style window management & ergonomics for Hyprland.
-- Usage in ~/.config/hypr/hyprland.lua:
--   require("hypr.windaase").setup()

local geometry = require("hypr.windaase.geometry")
local snap = require("hypr.windaase.snap")
local snap_layouts = require("hypr.windaase.snap_layouts")
local snap_resize = require("hypr.windaase.snap_resize")
local focus = require("hypr.windaase.focus")
local show_desktop = require("hypr.windaase.show_desktop")
local alt_tab = require("hypr.windaase.alt_tab")
local monitors = require("hypr.windaase.monitors")
local floating_only = require("hypr.windaase.floating_only")

local M = {}

local DEFAULTS = {
  aero_snap = true,
  snap_layouts = true,
  snap_assist = true,
  snap_resize = true,
  ultrawide_layout = false,
  floating_only = false,
  soft_maximize = true,
  auto_raise = true,
  hover_scroll = true,
  shortcuts = true,
  alt_tab = true,
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
    end,
    snap_layouts.is_dragging
  )

  snap_layouts.setup(opts)
  snap_resize.setup(opts, snap_layouts.write_state, snap_layouts.suppress)
  alt_tab.setup(opts)
  floating_only.setup(opts)
  focus.setup(opts.hover_scroll ~= false)
  monitors.setup(opts)

  if opts.shortcuts then
    o.rebind("ALT + F4", "Close window", hl.dsp.window.close())
    o.rebind("SUPER + D", "Show desktop", show_desktop.toggle)
    o.rebind("SUPER + P", "Display setup", "omarchy-shell riisager.windaase displays")
    o.rebind("SUPER + E", "File manager", { omarchy = "nautilus" })
    o.rebind("SUPER + ALT + SPACE", "Apps", "omarchy-shell riisager.windaase apps")
    o.rebind("SUPER + Home", "Minimize other windows (or restore tiled width)", function()
      local w = hl.get_active_window()
      if w and w.floating then
        show_desktop.toggle_minimize_others()
      else
        hl.exec_cmd("omarchy-hyprland-window-width restore")
      end
    end)
    o.rebind("SUPER + ALT + P", "Toggle always on top", function()
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
M.rescue_offscreen_windows = snap.rescue_offscreen_windows
M.show_desktop = show_desktop.toggle
M.minimize_others = show_desktop.toggle_minimize_others
M.toggle_snap_layouts = snap_layouts.toggle_click_overlay
M.cancel_snap_overlay = snap_layouts.cancel_overlay
M.apply_click_zone = snap_layouts.apply_click_zone
M.apply_assist_addr = snap_layouts.apply_assist_addr
M.alt_tab_step = alt_tab.step
M.alt_tab_commit = alt_tab.commit
M.alt_tab_commit_addr = alt_tab.commit_addr
M.alt_tab_cancel = alt_tab.cancel

return M
