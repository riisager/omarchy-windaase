-- Windows-style Aero Snap, soft-maximize (without Hyprland's fullscreen=1 click lock),
-- and automatic z-order raising when focusing floating windows.

local geometry = require("hypr.windaase.geometry")

local M = {}

local snap_restore_geom = {}
local snap_current_zone = {}
local last_normal_geom = {}

local options = {
  aero_snap = true,
  soft_maximize = true,
  auto_raise = true,
  gap_out = 8,
  gap_in = 8,
}

local on_before_snap = nil

local function work_area_for_window(window)
  local m = (window and window.monitor) or hl.get_active_monitor()
  return geometry.get_work_area(m, options.gap_out, options.gap_in)
end

function M.is_soft_maximized(window, area)
  if not window then
    return false
  end
  if snap_current_zone[window.address] == "maximize" then
    return true
  end
  if area and (window.fullscreen or 0) == 0 then
    return window.size.x >= area.max_w - 24 and window.size.y >= area.max_h - 60
  end
  return false
end

function M.record_normal_geom(window)
  if not window or not window.floating or (window.fullscreen or 0) ~= 0 then
    return
  end
  if not M.is_soft_maximized(window, work_area_for_window(window)) then
    last_normal_geom[window.address] = {
      x = window.at.x,
      y = window.at.y,
      w = window.size.x,
      h = window.size.y,
    }
  end
end

function M.clear_restore_state(addr)
  if addr then
    snap_current_zone[addr] = nil
    snap_restore_geom[addr] = nil
  end
end

function M.apply_snap(window, zone)
  if not window or not window.floating then
    return false
  end

  local area = work_area_for_window(window)
  if not area then
    return false
  end

  if on_before_snap then
    on_before_snap(6)
  end

  local addr = window.address

  if zone == "maximize" then
    if not snap_restore_geom[addr] then
      if (window.fullscreen or 0) == 0 and not M.is_soft_maximized(window, area) then
        snap_restore_geom[addr] = { x = window.at.x, y = window.at.y, w = window.size.x, h = window.size.y }
      elseif last_normal_geom[addr] then
        snap_restore_geom[addr] = last_normal_geom[addr]
      end
    end

    if options.soft_maximize then
      if (window.fullscreen or 0) == 1 then
        hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "unset", window = window }))
      end
      geometry.place_window_in_outer_rect(window, area.max_x, area.max_y, area.max_w, area.max_h)
      hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", window = window }))
    elseif (window.fullscreen or 0) ~= 1 then
      hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "set", window = window }))
    end

    snap_current_zone[addr] = "maximize"
    return true
  end

  if zone == "restore" then
    if (window.fullscreen or 0) ~= 0 then
      hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "unset", window = window }))
    end
    local saved = snap_restore_geom[addr] or last_normal_geom[addr]
    if saved then
      hl.dispatch(hl.dsp.window.resize({ x = saved.w, y = saved.h, relative = false, window = window }))
      hl.dispatch(hl.dsp.window.move({ x = saved.x, y = saved.y, relative = false, window = window }))
    else
      hl.dispatch(hl.dsp.window.resize({
        x = math.min(1100, math.floor(area.w * 0.68)),
        y = math.min(760, math.floor(area.h * 0.75)),
        relative = false,
        window = window,
      }))
      hl.dispatch(hl.dsp.window.center({ window = window }))
    end
    snap_restore_geom[addr] = nil
    snap_current_zone[addr] = nil
    hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", window = window }))
    return true
  end

  if (window.fullscreen or 0) ~= 0 then
    hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "unset", window = window }))
  elseif not snap_restore_geom[addr] then
    snap_restore_geom[addr] = { x = window.at.x, y = window.at.y, w = window.size.x, h = window.size.y }
  end

  local half_w = math.floor((area.w - area.gap) / 2)
  local half_h = math.floor((area.h - area.gap) / 2)
  local tx, ty, tw, th = area.x, area.y, area.w, area.h

  if zone == "left" then
    tw = half_w
  elseif zone == "right" then
    tx = area.x + half_w + area.gap
    tw = half_w
  elseif zone == "top" then
    th = half_h
  elseif zone == "bottom" then
    ty = area.y + half_h + area.gap
    th = half_h
  elseif zone == "top-left" then
    tw, th = half_w, half_h
  elseif zone == "top-right" then
    tx = area.x + half_w + area.gap
    tw, th = half_w, half_h
  elseif zone == "bottom-left" then
    ty = area.y + half_h + area.gap
    tw, th = half_w, half_h
  elseif zone == "bottom-right" then
    tx = area.x + half_w + area.gap
    ty = area.y + half_h + area.gap
    tw, th = half_w, half_h
  end

  geometry.place_window_in_outer_rect(window, tx, ty, tw, th)
  hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", window = window }))
  snap_current_zone[addr] = zone
  return true
end

function M.apply_snap_zone(window, m, z, orig_geom)
  if not window or not window.floating or not m or not z then
    return false
  end

  if on_before_snap then
    on_before_snap(6)
  end

  local addr = window.address
  if orig_geom and not snap_restore_geom[addr] then
    snap_restore_geom[addr] = orig_geom
  elseif not snap_restore_geom[addr] and (window.fullscreen or 0) == 0 then
    snap_restore_geom[addr] = { x = window.at.x, y = window.at.y, w = window.size.x, h = window.size.y }
  end

  if z.max then
    if options.soft_maximize then
      if (window.fullscreen or 0) ~= 0 then
        hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "unset", window = window }))
      end
      local area = geometry.get_work_area(m, options.gap_out, options.gap_in)
      geometry.place_window_in_outer_rect(window, area.max_x, area.max_y, area.max_w, area.max_h)
      hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", window = window }))
    elseif (window.fullscreen or 0) ~= 1 then
      hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "set", window = window }))
    end
    snap_current_zone[addr] = "maximize"
    return true
  end

  if (window.fullscreen or 0) ~= 0 then
    hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "unset", window = window }))
  end
  local area = geometry.get_work_area(m, options.gap_out, options.gap_in)
  local rect = geometry.zone_rect_in_area(area, z)
  geometry.place_window_in_outer_rect(window, rect.x, rect.y, rect.w, rect.h)
  hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", window = window }))
  snap_current_zone[addr] = "custom"
  return true
end

function M.apply_edge_snap_for_drag(w, start, c)
  if not w or not w.floating or not c then
    return
  end
  local area = work_area_for_window(w)
  if not area then
    return
  end

  local edge_margin = 16
  local corner_margin = 80

  local near_left = c.x <= area.edge_left + edge_margin
  local near_right = c.x >= area.edge_right - edge_margin
  local near_top = c.y <= area.edge_top + edge_margin
  local in_top_corner = c.y <= area.edge_top + corner_margin
  local in_bottom_corner = c.y >= area.edge_bottom - corner_margin
  local in_left_corner = c.x <= area.edge_left + corner_margin
  local in_right_corner = c.x >= area.edge_right - corner_margin

  local zone = nil
  if (near_left and in_top_corner) or (near_top and in_left_corner) then
    zone = "top-left"
  elseif (near_right and in_top_corner) or (near_top and in_right_corner) then
    zone = "top-right"
  elseif near_left and in_bottom_corner then
    zone = "bottom-left"
  elseif near_right and in_bottom_corner then
    zone = "bottom-right"
  elseif near_left then
    zone = "left"
  elseif near_right then
    zone = "right"
  elseif near_top then
    zone = "maximize"
  end

  if zone then
    if not snap_restore_geom[w.address] then
      snap_restore_geom[w.address] = { x = start.x, y = start.y, w = start.w, h = start.h }
    end
    M.apply_snap(w, zone)
  else
    M.clear_restore_state(w.address)
  end
end

local function convert_native_maximize(addr)
  local target = nil
  for _, w in ipairs(hl.get_windows()) do
    if w.address == addr then
      target = w
      break
    end
  end
  if not target or not target.floating or (target.fullscreen or 0) ~= 1 then
    return
  end
  if not geometry.has_floating_workspace_tag(target) then
    return
  end

  local was_soft_max = M.is_soft_maximized(target, work_area_for_window(target))
  if on_before_snap then
    on_before_snap(6)
  end
  hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "unset", window = target }))

  if was_soft_max then
    M.apply_snap(target, "restore")
  else
    if not snap_restore_geom[addr] and last_normal_geom[addr] then
      snap_restore_geom[addr] = last_normal_geom[addr]
    end
    M.apply_snap(target, "maximize")
  end
end

function M.setup(opts, before_snap_cb)
  options.aero_snap = opts.aero_snap ~= false
  options.soft_maximize = opts.soft_maximize ~= false
  options.auto_raise = opts.auto_raise ~= false
  options.gap_out = opts.gap_out or 8
  options.gap_in = opts.gap_in or 8
  on_before_snap = before_snap_cb

  hl.on("window.destroy", function(window)
    if not window or not window.address then
      return
    end
    snap_restore_geom[window.address] = nil
    snap_current_zone[window.address] = nil
    last_normal_geom[window.address] = nil
  end)

  if options.auto_raise then
    hl.on("window.active", function(window)
      if not window or not window.floating or window.pinned then
        return
      end
      if (window.fullscreen or 0) ~= 0 then
        return
      end
      hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", window = window }))
    end)
  end

  if options.soft_maximize then
    hl.on("window.fullscreen", function(window)
      if not window or not window.floating or (window.fullscreen or 0) ~= 1 then
        return
      end
      local addr = window.address
      hl.timer(function()
        convert_native_maximize(addr)
      end, { type = "oneshot", timeout = 5 })
    end)

    hl.timer(function()
      for _, w in ipairs(hl.get_windows()) do
        if w.floating and (w.fullscreen or 0) == 1 and geometry.has_floating_workspace_tag(w) then
          convert_native_maximize(w.address)
        end
      end
    end, { type = "oneshot", timeout = 100 })
  end

  if not options.aero_snap then
    return
  end

  o.rebind("SUPER + LEFT", "Snap window left (or focus left)", function()
    local w = hl.get_active_window()
    if w and w.floating then
      local cur = snap_current_zone[w.address]
      if cur == "top" then
        M.apply_snap(w, "top-left")
      elseif cur == "bottom" then
        M.apply_snap(w, "bottom-left")
      elseif cur == "right" then
        M.apply_snap(w, "restore")
      else
        M.apply_snap(w, "left")
      end
    else
      hl.dispatch(hl.dsp.focus({ direction = "l" }))
    end
  end)

  o.rebind("SUPER + RIGHT", "Snap window right (or focus right)", function()
    local w = hl.get_active_window()
    if w and w.floating then
      local cur = snap_current_zone[w.address]
      if cur == "top" then
        M.apply_snap(w, "top-right")
      elseif cur == "bottom" then
        M.apply_snap(w, "bottom-right")
      elseif cur == "left" then
        M.apply_snap(w, "restore")
      else
        M.apply_snap(w, "right")
      end
    else
      hl.dispatch(hl.dsp.focus({ direction = "r" }))
    end
  end)

  o.rebind("SUPER + UP", "Maximize / snap window up (or focus up)", function()
    local w = hl.get_active_window()
    if w and w.floating then
      local cur = snap_current_zone[w.address]
      if cur == "left" then
        M.apply_snap(w, "top-left")
      elseif cur == "right" then
        M.apply_snap(w, "top-right")
      elseif cur == "bottom-left" then
        M.apply_snap(w, "left")
      elseif cur == "bottom-right" then
        M.apply_snap(w, "right")
      else
        M.apply_snap(w, "maximize")
      end
    else
      hl.dispatch(hl.dsp.focus({ direction = "u" }))
    end
  end)

  o.rebind("SUPER + DOWN", "Restore / snap window down (or focus down)", function()
    local w = hl.get_active_window()
    if w and w.floating then
      local cur = snap_current_zone[w.address]
      if (w.fullscreen or 0) ~= 0 or M.is_soft_maximized(w, work_area_for_window(w)) then
        M.apply_snap(w, "restore")
      elseif cur == "top-left" then
        M.apply_snap(w, "left")
      elseif cur == "top-right" then
        M.apply_snap(w, "right")
      elseif cur == "left" then
        M.apply_snap(w, "bottom-left")
      elseif cur == "right" then
        M.apply_snap(w, "bottom-right")
      elseif cur then
        M.apply_snap(w, "restore")
      else
        hl.exec_cmd("omarchy-hyprland-window-minimize")
      end
    else
      hl.dispatch(hl.dsp.focus({ direction = "d" }))
    end
  end)
end

return M
