-- Windows-style Aero Snap, soft-maximize (without Hyprland's fullscreen=1 click lock),
-- and automatic z-order raising when focusing floating windows.

local geometry = require("hypr.windaase.geometry")
local runtime = require("hypr.windaase.runtime")

local M = {}

local snap_restore_geom = {}
local snap_current_zone = {}
local snap_custom_zone = {}
local last_normal_geom = {}

local options = {
  aero_snap = true,
  soft_maximize = true,
  auto_raise = true,
  gap_out = 8,
  gap_in = 8,
}

local on_before_snap = nil
local on_after_snap = nil
local is_dragging_fn = nil
local rescue_seq = 0
local hooks_registered = false

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
    snap_custom_zone[addr] = nil
    snap_restore_geom[addr] = nil
  end
end

local function ensure_window_on_monitor(window, m)
  if not window or not m then
    return window
  end
  if not window.monitor or window.monitor.name ~= m.name then
    local addr = window.address
    hl.dispatch(hl.dsp.window.move({ monitor = m.name, window = window }))
    return (addr and hl.get_window("address:" .. addr)) or window
  end
  return window
end

function M.apply_snap(window, zone, target_mon)
  if not window or not window.floating then
    return false
  end

  local m = target_mon or (window and window.monitor) or hl.get_active_monitor()
  local area = geometry.get_work_area(m, options.gap_out, options.gap_in)
  if not m or not area then
    return false
  end

  if on_before_snap then
    on_before_snap(6)
  end

  local addr = window.address
  if zone ~= "restore" then
    window = ensure_window_on_monitor(window, m)
  end

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
    snap_custom_zone[addr] = nil
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
    snap_custom_zone[addr] = nil
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
  snap_custom_zone[addr] = nil
  if on_after_snap and (zone == "left" or zone == "right") then
    local zone_spec = zone == "left"
      and { rx = 0, ry = 0, rw = 0.5, rh = 1.0, max = false }
      or { rx = 0.5, ry = 0, rw = 0.5, rh = 1.0, max = false }
    on_after_snap(window, m, zone_spec)
  end
  return true
end

function M.apply_snap_zone(window, m, z, orig_geom, skip_after_snap)
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

  window = ensure_window_on_monitor(window, m)

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
    snap_custom_zone[addr] = nil
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
  snap_custom_zone[addr] = { rx = z.rx, ry = z.ry, rw = z.rw, rh = z.rh, max = z.max == true }
  if on_after_snap and not skip_after_snap then
    on_after_snap(window, m, z)
  end
  return true
end

function M.apply_edge_snap_for_drag(w, start, c)
  if not w or not w.floating or not c then
    return
  end
  local m = geometry.get_monitor_at(c.x, c.y)
  local area = m and geometry.get_work_area(m, options.gap_out, options.gap_in)
  if not m or not area then
    return
  end

  local zone = options.aero_snap
    and geometry.detect_drag_edge_zone(c.x, c.y, area, hl.get_monitors(), m.name)
    or nil

  if zone then
    if not snap_restore_geom[w.address] then
      snap_restore_geom[w.address] = {
        x = start.x,
        y = start.y,
        w = math.min(start.w, area.w),
        h = math.min(start.h, area.h),
      }
    end
    M.apply_snap(w, zone, m)
    return
  end

  M.clear_restore_state(w.address)
  local border, titlebar = geometry.get_window_frame_insets(w)
  local outer = geometry.window_outer_rect(w, border, titlebar)
  local clamped = geometry.clamp_free_drop_rect(outer, area)
  if clamped then
    if on_before_snap then
      on_before_snap(6)
    end
    w = ensure_window_on_monitor(w, m)
    geometry.place_window_in_outer_rect(w, clamped.x, clamped.y, clamped.w, clamped.h)
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

local function remap_restore_geom(addr, border, titlebar, src_area, dst_area)
  local saved = snap_restore_geom[addr]
  if not saved then
    return
  end
  local saved_outer = {
    x = saved.x - border,
    y = saved.y - border - titlebar,
    w = saved.w + border * 2,
    h = saved.h + border * 2 + titlebar,
  }
  local remapped_outer = nil
  if src_area then
    remapped_outer = geometry.map_rect_between_areas(saved_outer, src_area, dst_area, nil, nil)
  elseif geometry.rect_needs_rescue(saved_outer, dst_area) then
    remapped_outer = geometry.rescue_rect_to_area(saved_outer, dst_area, nil, nil, nil)
  end
  if remapped_outer then
    snap_restore_geom[addr] = {
      x = remapped_outer.x + border,
      y = remapped_outer.y + border + titlebar,
      w = math.max(120, remapped_outer.w - border * 2),
      h = math.max(120, remapped_outer.h - border * 2 - titlebar),
    }
  end
end

local function apply_relocated_state(addr, dst_rect, border, titlebar)
  if dst_rect.mode == "maximize" then
    snap_current_zone[addr] = "maximize"
    snap_custom_zone[addr] = nil
  elseif dst_rect.mode == "float" then
    last_normal_geom[addr] = {
      x = dst_rect.x + border,
      y = dst_rect.y + border + titlebar,
      w = math.max(120, dst_rect.w - border * 2),
      h = math.max(120, dst_rect.h - border * 2 - titlebar),
    }
  end
end

function M.move_to_monitor(window, direction)
  if not window or not window.floating then
    return false
  end

  local src_mon = window.monitor or hl.get_active_monitor()
  local dst_mon = geometry.pick_adjacent_monitor(hl.get_monitors(), src_mon and src_mon.name, direction)
  if not dst_mon or (src_mon and dst_mon.name == src_mon.name) then
    return false
  end

  if on_before_snap then
    on_before_snap(6)
  end

  local addr = window.address
  if (window.fullscreen or 0) == 2 then
    hl.dispatch(hl.dsp.window.move({ monitor = dst_mon.name, window = window }))
    return true
  end

  local src_area = geometry.get_work_area(src_mon, options.gap_out, options.gap_in)
  local dst_area = geometry.get_work_area(dst_mon, options.gap_out, options.gap_in)
  if not src_area or not dst_area then
    return false
  end

  local border, titlebar = geometry.get_window_frame_insets(window)
  local outer = geometry.window_outer_rect(window, border, titlebar)
  local zone_name = snap_current_zone[addr]
  if not zone_name and (M.is_soft_maximized(window, src_area) or (window.fullscreen or 0) == 1) then
    zone_name = "maximize"
  end
  local custom_zone = snap_custom_zone[addr]

  local dst_rect = geometry.map_rect_between_areas(outer, src_area, dst_area, zone_name, custom_zone)
  if not dst_rect then
    return false
  end

  remap_restore_geom(addr, border, titlebar, src_area, dst_area)

  if (window.fullscreen or 0) == 1 then
    hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "unset", window = window }))
  end

  hl.dispatch(hl.dsp.window.move({ monitor = dst_mon.name, window = window }))
  local moved = (addr and hl.get_window("address:" .. addr)) or window
  geometry.place_window_in_outer_rect(moved, dst_rect.x, dst_rect.y, dst_rect.w, dst_rect.h)
  hl.dispatch(hl.dsp.focus({ window = moved }))
  hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", window = moved }))

  apply_relocated_state(addr, dst_rect, border, titlebar)
  return true
end

-- Reposition a floating window that is stranded off-screen (e.g. after dock/undock or sleep) onto its active monitor.
function M.rescue_window(window, monitors_opt, rescue_opts)
  if not window or not window.address or not window.floating then
    return false
  end
  if window.mapped == false or window.hidden == true or (window.fullscreen or 0) == 2 then
    return false
  end
  local ws = window.workspace
  if ws then
    local ws_name = type(ws.name) == "string" and ws.name or ""
    local ws_id = tonumber(ws.id)
    if ws_name:match("^special:") or (ws_id and ws_id < 1) then
      return false
    end
  end
  if is_dragging_fn and is_dragging_fn() then
    return false
  end

  local monitors = monitors_opt or hl.get_monitors()
  local dst_mon = geometry.resolve_active_monitor_for_window(window, monitors, hl.get_active_monitor())
  if not dst_mon then
    return false
  end
  local dst_area = geometry.get_work_area(dst_mon, options.gap_out, options.gap_in)
  if not dst_area then
    return false
  end

  local border, titlebar = geometry.get_window_frame_insets(window)
  local outer = geometry.window_outer_rect(window, border, titlebar)
  local check_oversize = not (rescue_opts and rescue_opts.only_unreachable)
  if not outer or not geometry.rect_needs_rescue(outer, dst_area, check_oversize) then
    return false
  end

  local addr = window.address
  local src_mon = geometry.find_containing_monitor(outer, monitors, dst_mon.name)
  local src_area = src_mon and geometry.get_work_area(src_mon, options.gap_out, options.gap_in) or nil
  local zone_name = snap_current_zone[addr]
  if not zone_name and (window.fullscreen or 0) == 1 then
    zone_name = "maximize"
  end
  local dst_rect = geometry.rescue_rect_to_area(outer, dst_area, zone_name, snap_custom_zone[addr], src_area)
  if not dst_rect then
    return false
  end

  if on_before_snap then
    local act = hl.get_active_window()
    if act and act.address == addr then
      on_before_snap(6)
    end
  end

  remap_restore_geom(addr, border, titlebar, src_area, dst_area)

  local need_monitor_move = not window.monitor or window.monitor.name ~= dst_mon.name
  local ws_id = ws and tonumber(ws.id) or -1
  local ws_mon = (ws and ws.monitor and ws.monitor.name) or ""
  local target_ws_id = (ws_id >= 1 and ws_mon == dst_mon.name) and ws_id
    or (dst_mon.active_workspace and tonumber(dst_mon.active_workspace.id))
    or -1
  local function move_window_silent(w_target)
    if target_ws_id >= 1 then
      hl.dispatch(hl.dsp.window.move({ workspace = tostring(target_ws_id), follow = false, window = w_target }))
    else
      hl.dispatch(hl.dsp.window.move({ monitor = dst_mon.name, window = w_target }))
    end
  end

  if (window.fullscreen or 0) == 1 then
    if not options.soft_maximize then
      if need_monitor_move then
        move_window_silent(window)
        return true
      end
      return false
    end
    hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "unset", window = window }))
  end

  if need_monitor_move then
    move_window_silent(window)
  end

  local target = hl.get_window("address:" .. addr) or window
  geometry.place_window_in_outer_rect(target, dst_rect.x, dst_rect.y, dst_rect.w, dst_rect.h)
  apply_relocated_state(addr, dst_rect, border, titlebar)
  return true
end

function M.rescue_offscreen_windows()
  if is_dragging_fn and is_dragging_fn() then
    return 0
  end
  local prev_active = hl.get_active_window()
  local prev_addr = prev_active and prev_active.address or nil
  local monitors = hl.get_monitors()
  local rescued = 0
  for _, w in ipairs(hl.get_windows()) do
    if M.rescue_window(w, monitors) then
      rescued = rescued + 1
    end
  end
  if rescued > 0 and prev_addr then
    local cur_active = hl.get_active_window()
    if (not cur_active or cur_active.address ~= prev_addr) and hl.get_window("address:" .. prev_addr) then
      hl.dispatch(hl.dsp.focus({ window = "address:" .. prev_addr }))
    end
  end
  return rescued
end

local function schedule_rescue()
  rescue_seq = rescue_seq + 1
  local seq = rescue_seq
  runtime.timer(function()
    if seq == rescue_seq then
      M.rescue_offscreen_windows()
    end
  end, { type = "oneshot", timeout = 300 })
  runtime.timer(function()
    if seq == rescue_seq then
      M.rescue_offscreen_windows()
    end
  end, { type = "oneshot", timeout = 1100 })
end

function M.key_snap(dir)
  local w = hl.get_active_window()
  if not w or not w.floating then
    local focus_dir = ({ left = "l", right = "r", up = "u", down = "d" })[dir]
    if focus_dir then
      hl.dispatch(hl.dsp.focus({ direction = focus_dir }))
    end
    return
  end

  local cur = snap_current_zone[w.address]
  if dir == "left" then
    if cur == "top" then
      M.apply_snap(w, "top-left")
    elseif cur == "bottom" then
      M.apply_snap(w, "bottom-left")
    elseif cur == "right" then
      M.apply_snap(w, "restore")
    else
      M.apply_snap(w, "left")
    end
  elseif dir == "right" then
    if cur == "top" then
      M.apply_snap(w, "top-right")
    elseif cur == "bottom" then
      M.apply_snap(w, "bottom-right")
    elseif cur == "left" then
      M.apply_snap(w, "restore")
    else
      M.apply_snap(w, "right")
    end
  elseif dir == "up" then
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
  elseif dir == "down" then
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
  end
end

function M.key_move_to_monitor(dir)
  local w = hl.get_active_window()
  if w and w.floating then
    M.move_to_monitor(w, dir)
  else
    hl.dispatch(hl.dsp.window.swap({ direction = dir }))
  end
end

function M.setup(opts, before_snap_cb, after_snap_cb, is_dragging_cb)
  options.aero_snap = opts.aero_snap ~= false
  options.soft_maximize = opts.soft_maximize ~= false
  options.auto_raise = opts.auto_raise ~= false
  options.gap_out = opts.gap_out or 8
  options.gap_in = opts.gap_in or 8
  on_before_snap = before_snap_cb
  on_after_snap = after_snap_cb
  is_dragging_fn = is_dragging_cb

  if runtime.is_live_compositor() then
    if not hooks_registered then
      hooks_registered = true

      hl.on("window.destroy", function(window)
        if not window or not window.address then
          return
        end
        snap_restore_geom[window.address] = nil
        snap_current_zone[window.address] = nil
        snap_custom_zone[window.address] = nil
        last_normal_geom[window.address] = nil
      end)

      hl.on("window.active", function(window)
        if not window or not window.floating then
          return
        end
        if (window.fullscreen or 0) ~= 2 and M.rescue_window(window, nil, { only_unreachable = true }) then
          window = (window.address and hl.get_window("address:" .. window.address)) or window
        end
        if not options.auto_raise or window.pinned or (window.fullscreen or 0) ~= 0 then
          return
        end
        hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", window = window }))
      end)

      hl.on("window.fullscreen", function(window)
        if not options.soft_maximize then
          return
        end
        if not window or not window.floating or (window.fullscreen or 0) ~= 1 then
          return
        end
        local addr = window.address
        runtime.timer(function()
          convert_native_maximize(addr)
        end, { type = "oneshot", timeout = 5 })
      end)

      hl.on("monitor.added", schedule_rescue)
      hl.on("monitor.removed", schedule_rescue)
      hl.on("monitor.layout_changed", schedule_rescue)
      hl.on("workspace.move_to_monitor", schedule_rescue)
      hl.on("window.move_to_workspace", function(window)
        local addr = window and window.address
        if not addr then
          return
        end
        runtime.timer(function()
          local cur = hl.get_window("address:" .. addr)
          if cur then
            M.rescue_window(cur)
          end
        end, { type = "oneshot", timeout = 30 })
      end)
    end

    schedule_rescue()

    if options.soft_maximize then
      runtime.timer(function()
        for _, w in ipairs(hl.get_windows()) do
          if w.floating and (w.fullscreen or 0) == 1 and geometry.has_floating_workspace_tag(w) then
            convert_native_maximize(w.address)
          end
        end
      end, { type = "oneshot", timeout = 100 })
    end
  end

  if not options.aero_snap then
    return
  end

  runtime.rebind_fn("SUPER + LEFT", "Snap window left (or focus left)", function() M.key_snap("left") end, 'key_snap("left")')
  runtime.rebind_fn("SUPER + RIGHT", "Snap window right (or focus right)", function() M.key_snap("right") end, 'key_snap("right")')
  runtime.rebind_fn("SUPER + UP", "Maximize / snap window up (or focus up)", function() M.key_snap("up") end, 'key_snap("up")')
  runtime.rebind_fn("SUPER + DOWN", "Restore / snap window down (or focus down)", function() M.key_snap("down") end, 'key_snap("down")')
  runtime.rebind_fn("SUPER + SHIFT + LEFT", "Move window to left monitor (or swap left)", function() M.key_move_to_monitor("l") end, 'key_move_to_monitor("l")')
  runtime.rebind_fn("SUPER + SHIFT + RIGHT", "Move window to right monitor (or swap right)", function() M.key_move_to_monitor("r") end, 'key_move_to_monitor("r")')
end

return M
