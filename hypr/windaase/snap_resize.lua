-- Coupled Snap Group resizing for Hyprland floating workspaces:
--   * Keyboard: Super + Alt + Left/Right/Up/Down steps snapped split ratios
--   * Mouse:    Border/gap drag on any snapped edge resizes all coupled panes together

local geometry = require("hypr.windaase.geometry")
local runtime = require("hypr.windaase.runtime")
local seam = require("hypr.windaase.seam")

local M = {}

local options = {
  snap_resize = true,
  aero_snap = true,
  gap_out = 8,
  gap_in = 8,
}

local write_state_fn = nil
local suppress_fn = nil

local last_geom_by_addr = {}
local active_resize = nil
local flash_seq = 0
local resize_seq = 0
local destroy_hook_registered = false

local function set_window_no_anim(addrs, enable)
  if type(addrs) ~= "table" then
    return
  end
  local val = enable and "1" or "unset"
  for _, addr in ipairs(addrs) do
    if addr and addr ~= "" then
      pcall(hl.dispatch, hl.dsp.window.set_prop({ prop = "no_anim", value = val, window = "address:" .. addr }))
    end
  end
end

local function unset_inactive_no_anim(addrs)
  if type(addrs) ~= "table" then
    return
  end
  local active_set = {}
  if active_resize then
    if active_resize.group and active_resize.group.driver_addr then
      active_set[active_resize.group.driver_addr] = true
    end
    for _, a in ipairs(active_resize.partner_addrs or {}) do
      active_set[a] = true
    end
  end
  local to_unset = {}
  for _, addr in ipairs(addrs) do
    if addr and addr ~= "" and not active_set[addr] then
      to_unset[#to_unset + 1] = addr
    end
  end
  if #to_unset > 0 then
    set_window_no_anim(to_unset, false)
  end
end

local function place_rect(w, rect, border, titlebar)
  if not w or not rect then
    return
  end
  local b = tonumber(border) or 2
  local tb = tonumber(titlebar) or 0
  local cx = math.floor(rect.x + b + 0.5)
  local cy = math.floor(rect.y + b + tb + 0.5)
  local cw = math.max(120, math.floor(rect.w - b * 2 + 0.5))
  local ch = math.max(120, math.floor(rect.h - b * 2 - tb + 0.5))
  pcall(hl.dispatch, hl.dsp.window.resize({ x = cw, y = ch, relative = false, window = w }))
  pcall(hl.dispatch, hl.dsp.window.move({ x = cx, y = cy, relative = false, window = w }))
end

local function driver_raw_seam(outer, edge, gap)
  if not outer then
    return nil
  end
  if edge == "right" then
    return outer.x + outer.w
  elseif edge == "left" then
    return outer.x - gap
  elseif edge == "bottom" then
    return outer.y + outer.h
  elseif edge == "top" then
    return outer.y - gap
  end
  return nil
end

local function record_geom(addr, outer, border, titlebar, ws_id, mon_name)
  if not addr or not outer then
    return
  end
  last_geom_by_addr[addr] = {
    x = outer.x,
    y = outer.y,
    w = outer.w,
    h = outer.h,
    border = border,
    titlebar = titlebar,
    ws_id = ws_id,
    mon_name = mon_name,
  }
end

local function collect_workspace_descriptors(ws_id, mon_name, use_snapshot)
  local descriptors = {}
  local win_by_addr = {}
  if not ws_id or ws_id < 1 then
    return descriptors, win_by_addr
  end

  for _, w in ipairs(hl.get_workspace_windows(tostring(ws_id))) do
    if w.address and w.mapped ~= false and w.floating and (w.fullscreen or 0) == 0 then
      local w_mon = w.monitor and w.monitor.name or ""
      if mon_name == "" or w_mon == "" or w_mon == mon_name then
        local prev = use_snapshot and last_geom_by_addr[w.address] or nil
        local border, titlebar, outer
        if prev and prev.ws_id == ws_id and prev.mon_name == w_mon then
          border = prev.border
          titlebar = prev.titlebar
          outer = { x = prev.x, y = prev.y, w = prev.w, h = prev.h }
        else
          border, titlebar = geometry.get_window_frame_insets(w)
          outer = geometry.window_outer_rect(w, border, titlebar)
        end
        if outer then
          descriptors[#descriptors + 1] = {
            addr = w.address,
            outer = outer,
            focus_history_id = w.focus_history_id,
            border = border,
            titlebar = titlebar,
          }
          win_by_addr[w.address] = w
        end
      end
    end
  end

  return descriptors, win_by_addr
end

local function emit_resize_overlay(mon_name, mon_x, mon_y, axis, divider_rect, pct1, pct2)
  if not write_state_fn or not divider_rect then
    return
  end
  write_state_fn({
    open = true,
    mode = "resize",
    monitor = mon_name or "",
    card = -1,
    zone = -1,
    px = math.floor(divider_rect.x - (mon_x or 0) + 0.5),
    py = math.floor(divider_rect.y - (mon_y or 0) + 0.5),
    pw = math.max(1, math.floor(divider_rect.w + 0.5)),
    ph = math.max(1, math.floor(divider_rect.h + 0.5)),
    axis = axis or "x",
    p1 = pct1 or 50,
    p2 = pct2 or 50,
  })
end

local function flash_resize_overlay(mon_name, mon_x, mon_y, axis, divider_rect, pct1, pct2)
  flash_seq = flash_seq + 1
  local seq = flash_seq
  emit_resize_overlay(mon_name, mon_x, mon_y, axis, divider_rect, pct1, pct2)
  runtime.timer(function()
    if seq ~= flash_seq or active_resize ~= nil then
      return
    end
    if write_state_fn then
      write_state_fn({ open = false })
    end
  end, { type = "oneshot", timeout = 650 })
end

function M.is_active()
  return active_resize ~= nil
end

function M.clear_flash()
  flash_seq = flash_seq + 1
end

function M.snapshot_workspace(cur)
  if active_resize ~= nil or not cur or not cur.workspace or not cur.workspace.id then
    return
  end
  local ws_id = tonumber(cur.workspace.id) or -1
  if ws_id < 1 then
    return
  end

  local seen = {}
  for _, w in ipairs(hl.get_workspace_windows(tostring(ws_id))) do
    if w.address and w.mapped ~= false and w.floating and (w.fullscreen or 0) == 0 then
      local border, titlebar = geometry.get_window_frame_insets(w)
      local outer = geometry.window_outer_rect(w, border, titlebar)
      if outer then
        local mon_name = w.monitor and w.monitor.name or ""
        record_geom(w.address, outer, border, titlebar, ws_id, mon_name)
        seen[w.address] = true
      end
    end
  end

  for addr, entry in pairs(last_geom_by_addr) do
    if entry.ws_id == ws_id and not seen[addr] then
      last_geom_by_addr[addr] = nil
    end
  end
end

function M.try_begin_mouse_resize(cur, c)
  if active_resize ~= nil or not options.snap_resize or options.aero_snap == false then
    return false
  end
  if not cur or not cur.workspace or not cur.workspace.id then
    return false
  end

  local ws_id = tonumber(cur.workspace.id) or -1
  if ws_id < 1 then
    return false
  end
  local cur_mon = cur.monitor or hl.get_active_monitor()
  local cur_mon_name = cur_mon and cur_mon.name or ""

  for _, w in ipairs(hl.get_workspace_windows(tostring(ws_id))) do
    if w.address and w.mapped ~= false and w.floating and (w.fullscreen or 0) == 0 then
      local w_mon = w.monitor or cur_mon
      local w_mon_name = w_mon and w_mon.name or ""
      local prev = last_geom_by_addr[w.address]
      if prev and prev.ws_id == ws_id and prev.mon_name == w_mon_name and (cur_mon_name == "" or w_mon_name == cur_mon_name) then
        local cur_outer = geometry.window_outer_rect(w, prev.border, prev.titlebar)
        local edge, axis = seam.detect_resize_edge(prev, cur_outer)
        if edge and axis then
          local descriptors, win_by_addr = collect_workspace_descriptors(ws_id, w_mon_name, true)
          local area = w_mon and geometry.get_work_area(w_mon, options.gap_out, options.gap_in) or nil
          local group = seam.find_seam_group(descriptors, w.address, edge, options.gap_in, area)
          if group then
            local partner_addrs = {}
            for _, b in ipairs(group.before_list) do
              if b.addr ~= group.driver_addr then
                partner_addrs[#partner_addrs + 1] = b.addr
              end
            end
            for _, a in ipairs(group.after_list) do
              if a.addr ~= group.driver_addr then
                partner_addrs[#partner_addrs + 1] = a.addr
              end
            end

            flash_seq = flash_seq + 1
            resize_seq = resize_seq + 1
            set_window_no_anim(partner_addrs, true)

            local raw_seam = driver_raw_seam(cur_outer, edge, group.gap) or group.seam
            local res = seam.compute_seam_rects(group, raw_seam)
            if res then
              for _, p in ipairs(res.placements) do
                if not p.is_driver then
                  local pw = win_by_addr[p.addr] or hl.get_window("address:" .. p.addr)
                  place_rect(pw, p.rect, p.border, p.titlebar)
                end
              end
            end

            local mx = w_mon and w_mon.x or 0
            local my = w_mon and w_mon.y or 0
            active_resize = {
              group = group,
              ws_id = ws_id,
              mon_name = w_mon_name,
              mon_x = mx,
              mon_y = my,
              last_seam = res and res.seam or group.seam,
              last_driver_edge = raw_seam,
              last_cx = c and c.x or 0,
              last_cy = c and c.y or 0,
              detached_ticks = 0,
              partner_addrs = partner_addrs,
              driver_border = prev.border,
              driver_titlebar = prev.titlebar,
            }

            if res then
              emit_resize_overlay(w_mon_name, mx, my, group.axis, res.divider_rect, res.pct1, res.pct2)
            end
            return true
          end
        end
      end
    end
  end

  return false
end

function M.tick_active_resize(c)
  local st = active_resize
  if not st then
    return
  end

  local driver = hl.get_window("address:" .. st.group.driver_addr)
  if not driver or not driver.floating or (driver.fullscreen or 0) ~= 0 then
    M.finish_active_resize()
    return
  end

  local outer = geometry.window_outer_rect(driver, st.driver_border, st.driver_titlebar)
  local raw_seam = driver_raw_seam(outer, st.group.edge, st.group.gap)
  if not raw_seam then
    M.finish_active_resize()
    return
  end

  local edge_moved = math.abs(raw_seam - (st.last_driver_edge or raw_seam)) >= 1
  if edge_moved then
    st.last_driver_edge = raw_seam
    st.detached_ticks = 0
  elseif c then
    local cur_moved = math.abs(c.x - st.last_cx) >= 4 or math.abs(c.y - st.last_cy) >= 4
    local edge_pos = (st.group.driver_side == "before") and raw_seam or (raw_seam + st.group.gap)
    local cur_axis_pos = (st.group.axis == "x") and c.x or c.y
    if cur_moved and math.abs(cur_axis_pos - edge_pos) > 48 then
      st.detached_ticks = st.detached_ticks + 1
      if st.detached_ticks >= 4 then
        M.finish_active_resize()
        return
      end
    end
  end

  if c then
    st.last_cx = c.x
    st.last_cy = c.y
  end

  local res = seam.compute_seam_rects(st.group, raw_seam)
  if not res then
    return
  end

  if res.seam ~= st.last_seam then
    st.last_seam = res.seam
    for _, p in ipairs(res.placements) do
      if not p.is_driver then
        local pw = hl.get_window("address:" .. p.addr)
        place_rect(pw, p.rect, p.border, p.titlebar)
      end
    end
    emit_resize_overlay(st.mon_name, st.mon_x, st.mon_y, st.group.axis, res.divider_rect, res.pct1, res.pct2)
  end
end

local function check_and_reconcile_minimums(st, target_seam)
  local group = st.group
  local res = seam.compute_seam_rects(group, target_seam)
  if not res then
    return
  end

  local min_req = group.min_seam
  local max_req = group.max_seam
  local axis = group.axis

  for _, p in ipairs(res.placements) do
    local w = hl.get_window("address:" .. p.addr)
    if w and w.floating and (w.fullscreen or 0) == 0 then
      local actual = geometry.window_outer_rect(w, p.border, p.titlebar)
      if actual then
        local actual_len = (axis == "x") and actual.w or actual.h
        local target_len = (axis == "x") and p.rect.w or p.rect.h
        if actual_len > target_len + 4 then
          if p.side == "before" then
            local p1 = (axis == "x") and p.rect.x or p.rect.y
            if p1 + actual_len > min_req then
              min_req = p1 + actual_len
            end
          else
            local p2 = (axis == "x") and (p.rect.x + p.rect.w) or (p.rect.y + p.rect.h)
            local limit = p2 - group.gap - actual_len
            if limit < max_req then
              max_req = limit
            end
          end
        end
      end
    end
  end

  local final_seam = target_seam
  if min_req <= max_req then
    if final_seam < min_req then
      final_seam = min_req
    elseif final_seam > max_req then
      final_seam = max_req
    end
  end

  if final_seam ~= target_seam then
    local adj = seam.compute_seam_rects(group, final_seam)
    if adj then
      for _, p in ipairs(adj.placements) do
        local pw = hl.get_window("address:" .. p.addr)
        place_rect(pw, p.rect, p.border, p.titlebar)
        record_geom(p.addr, p.rect, p.border, p.titlebar, st.ws_id, st.mon_name)
      end
    end
  end
end

function M.finish_active_resize()
  local st = active_resize
  if not st then
    return
  end
  active_resize = nil
  flash_seq = flash_seq + 1
  resize_seq = resize_seq + 1

  if suppress_fn then
    suppress_fn(4)
  end
  if write_state_fn then
    write_state_fn({ open = false })
  end

  local driver = hl.get_window("address:" .. st.group.driver_addr)
  local raw_seam = st.last_seam
  local driver_outer = nil
  if driver and driver.floating and (driver.fullscreen or 0) == 0 then
    driver_outer = geometry.window_outer_rect(driver, st.driver_border, st.driver_titlebar)
    local live_seam = driver_raw_seam(driver_outer, st.group.edge, st.group.gap)
    if live_seam then
      raw_seam = live_seam
    end
  end

  local res = seam.compute_seam_rects(st.group, raw_seam)
  local no_anim_all = {}
  for _, a in ipairs(st.partner_addrs) do
    no_anim_all[#no_anim_all + 1] = a
  end

  if res then
    for _, p in ipairs(res.placements) do
      if not p.is_driver then
        local pw = hl.get_window("address:" .. p.addr)
        place_rect(pw, p.rect, p.border, p.titlebar)
        record_geom(p.addr, p.rect, p.border, p.titlebar, st.ws_id, st.mon_name)
      elseif driver and driver.floating and driver_outer then
        local drifted = math.abs(driver_outer.x - p.rect.x) >= 1
          or math.abs(driver_outer.y - p.rect.y) >= 1
          or math.abs(driver_outer.w - p.rect.w) >= 1
          or math.abs(driver_outer.h - p.rect.h) >= 1
        if drifted or math.floor(raw_seam + 0.5) ~= res.seam then
          no_anim_all[#no_anim_all + 1] = st.group.driver_addr
          set_window_no_anim({ st.group.driver_addr }, true)
          place_rect(driver, p.rect, p.border, p.titlebar)
        end
        record_geom(p.addr, p.rect, p.border, p.titlebar, st.ws_id, st.mon_name)
      end
    end
  end

  local settled_seam = res and res.seam or st.last_seam
  local seq = resize_seq
  local expected_gen = runtime.generation()
  if runtime.is_live_compositor() then
    hl.timer(function()
      if expected_gen ~= runtime.generation() then
        set_window_no_anim(no_anim_all, false)
        return
      end
      if seq ~= resize_seq or active_resize ~= nil then
        unset_inactive_no_anim(no_anim_all)
        return
      end
      check_and_reconcile_minimums(st, settled_seam)
      set_window_no_anim(no_anim_all, false)
      local cur = hl.get_active_window()
      if cur then
        M.snapshot_workspace(cur)
      end
    end, { type = "oneshot", timeout = 60 })
  end
end

function M.resize_by_keyboard(direction, axis)
  local dir_char
  if axis == "y" then
    dir_char = (direction < 0) and "u" or "d"
  else
    axis = "x"
    dir_char = (direction < 0) and "l" or "r"
  end

  local w = hl.get_active_window()
  if not w or not w.floating then
    hl.dispatch(hl.dsp.window.move({ into_group = dir_char }))
    return
  end
  if (w.fullscreen or 0) ~= 0 then
    return
  end

  local ws_id = (w.workspace and tonumber(w.workspace.id)) or -1
  if ws_id < 1 then
    return
  end
  local m = w.monitor or hl.get_active_monitor()
  if not m then
    return
  end
  local mon_name = m.name or ""
  local area = geometry.get_work_area(m, options.gap_out, options.gap_in)
  if not area then
    return
  end

  local descriptors, win_by_addr = collect_workspace_descriptors(ws_id, mon_name, false)
  local res = seam.resolve_keyboard_snap_resize(descriptors, w.address, area, options.gap_in, direction, axis)
  if not res then
    return
  end

  resize_seq = resize_seq + 1
  if suppress_fn then
    suppress_fn(6)
  end
  for _, p in ipairs(res.placements) do
    local pw = win_by_addr[p.addr] or hl.get_window("address:" .. p.addr)
    place_rect(pw, p.rect, p.border, p.titlebar)
    record_geom(p.addr, p.rect, p.border, p.titlebar, ws_id, mon_name)
  end
  flash_resize_overlay(mon_name, m.x or 0, m.y or 0, res.axis, res.divider_rect, res.pct1, res.pct2)
end

function M.setup(opts, write_state_cb, suppress_cb)
  options.snap_resize = opts.snap_resize ~= false
  options.aero_snap = opts.aero_snap ~= false
  options.gap_out = opts.gap_out or 8
  options.gap_in = opts.gap_in or 8
  write_state_fn = write_state_cb
  suppress_fn = suppress_cb

  if active_resize ~= nil then
    set_window_no_anim(active_resize.partner_addrs, false)
  end
  active_resize = nil
  last_geom_by_addr = {}
  flash_seq = flash_seq + 1
  resize_seq = resize_seq + 1

  if runtime.is_live_compositor() and not destroy_hook_registered then
    destroy_hook_registered = true
    hl.on("window.destroy", function(window)
      if not window or not window.address then
        return
      end
      last_geom_by_addr[window.address] = nil
      if active_resize and active_resize.group and active_resize.group.driver_addr == window.address then
        M.finish_active_resize()
      end
    end)
  end

  if options.aero_snap and options.snap_resize then
    runtime.rebind_fn(
      "SUPER + ALT + LEFT",
      "Resize snap divider left (or move into group)",
      function() M.resize_by_keyboard(-1, "x") end,
      'snap_resize(-1, "x")'
    )
    runtime.rebind_fn(
      "SUPER + ALT + RIGHT",
      "Resize snap divider right (or move into group)",
      function() M.resize_by_keyboard(1, "x") end,
      'snap_resize(1, "x")'
    )
    runtime.rebind_fn(
      "SUPER + ALT + UP",
      "Resize snap divider up (or move into group)",
      function() M.resize_by_keyboard(-1, "y") end,
      'snap_resize(-1, "y")'
    )
    runtime.rebind_fn(
      "SUPER + ALT + DOWN",
      "Resize snap divider down (or move into group)",
      function() M.resize_by_keyboard(1, "y") end,
      'snap_resize(1, "y")'
    )
  end
end

return M
