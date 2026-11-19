-- Event-driven drag monitor for Windows 11 top-edge Snap Layouts and
-- edge-drag snapping, plus Super+Z click overlay toggle.

local geometry = require("hypr.windaase.geometry")
local snap = require("hypr.windaase.snap")

local M = {}

local snap_state_path = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/omarchy-windaase-snap.json"
local last_snap_json = ""
local layouts_cfg = nil
local gap_out = 8
local gap_in = 8
local snap_layouts_enabled = true

local mouse_drag_state = nil
local prev_sample = nil
local suppress_snap_ticks = 0
local monitor_running = false
local monitor_token = 0

function M.suppress(ticks)
  local n = tonumber(ticks) or 6
  if n > suppress_snap_ticks then
    suppress_snap_ticks = n
  end
end

local function write_snap_state(tbl)
  local payload
  if not tbl or not tbl.open then
    payload = '{"open":false}\n'
  else
    payload = string.format(
      '{"open":true,"mode":"%s","monitor":"%s","card":%d,"zone":%d,"px":%d,"py":%d,"pw":%d,"ph":%d,"addr":"%s","border":%d,"titlebar":%d}\n',
      geometry.json_escape(tbl.mode or "drag"),
      geometry.json_escape(tbl.monitor or ""),
      tbl.card or -1,
      tbl.zone or -1,
      tbl.px or 0,
      tbl.py or 0,
      tbl.pw or 0,
      tbl.ph or 0,
      geometry.json_escape(tbl.addr or ""),
      tbl.border or 2,
      tbl.titlebar or 30
    )
  end

  if payload == last_snap_json then
    return
  end
  last_snap_json = payload

  local tmp = snap_state_path .. ".tmp"
  local f = io.open(tmp, "w")
  if f then
    f:write(payload)
    f:close()
    os.rename(tmp, snap_state_path)
  end
end

local function finish_active_drag(cur, c)
  local st = mouse_drag_state
  mouse_drag_state = nil
  prev_sample = nil
  if not st then
    return
  end

  local picked_zone = st.snap_open and st.snap_zone or nil
  local picked_mon = st.snap_open and st.snap_mon or nil
  if st.snap_open then
    write_snap_state({ open = false })
  end

  if not cur or cur.address ~= st.addr or not cur.floating then
    return
  end

  if picked_zone and picked_mon then
    snap.apply_snap_zone(cur, picked_mon, picked_zone, { x = st.x, y = st.y, w = st.w, h = st.h })
  else
    snap.apply_edge_snap_for_drag(cur, st, c)
  end
end

local function update_drag_overlay(st, cur, c)
  if not snap_layouts_enabled then
    return
  end
  local m, mw = geometry.get_monitor_at(c.x, c.y)
  if not m then
    return
  end

  local lx = c.x - (m.x or 0)
  local ly = c.y - (m.y or 0)
  local win_top = cur.at.y - (m.y or 0)
  local ci, zi, z, _, py, _, ph = geometry.hit_test_snap_layouts(lx, ly, mw, layouts_cfg)

  if not st.snap_open then
    if ly <= 40 or win_top <= 36 then
      st.snap_open = true
      st.snap_mon = m
    end
  end

  if st.snap_open then
    if st.snap_mon and m.name == st.snap_mon.name and (ly <= py + ph + 56 or win_top <= 42) then
      st.snap_zone = z
      if z then
        local area = geometry.get_work_area(m, gap_out, gap_in)
        local r = geometry.zone_rect_in_area(area, z)
        write_snap_state({
          open = true,
          mode = "drag",
          monitor = m.name,
          card = ci,
          zone = zi,
          px = r.x - (m.x or 0),
          py = r.y - (m.y or 0),
          pw = r.w,
          ph = r.h,
        })
      else
        write_snap_state({
          open = true,
          mode = "drag",
          monitor = m.name,
          card = -1,
          zone = -1,
        })
      end
    else
      st.snap_open = false
      st.snap_zone = nil
      write_snap_state({ open = false })
    end
  end
end

local function tick(expected_token)
  if expected_token ~= monitor_token then
    return
  end

  if suppress_snap_ticks > 0 then
    suppress_snap_ticks = suppress_snap_ticks - 1
    prev_sample = nil
    hl.timer(function() tick(expected_token) end, { type = "oneshot", timeout = 120 })
    return
  end

  local cur = hl.get_active_window()
  local c = hl.get_cursor_pos()

  if mouse_drag_state then
    local st = mouse_drag_state
    if not cur or not c or cur.address ~= st.addr or not cur.floating then
      if st.snap_open then
        write_snap_state({ open = false })
      end
      mouse_drag_state = nil
      prev_sample = nil
      monitor_running = false
      return
    end

    local dwx = cur.at.x - st.last_wx
    local dwy = cur.at.y - st.last_wy
    local dcx = c.x - st.last_cx
    local dcy = c.y - st.last_cy
    local win_moved = math.abs(dwx) >= 1 or math.abs(dwy) >= 1
    local cur_moved = math.abs(dcx) >= 3 or math.abs(dcy) >= 3

    if win_moved then
      st.detached_ticks = 0
      st.last_wx = cur.at.x
      st.last_wy = cur.at.y
      st.last_cx = c.x
      st.last_cy = c.y
      update_drag_overlay(st, cur, c)
    elseif cur_moved then
      local m, mw = geometry.get_monitor_at(c.x, c.y)
      local clamped_push = false
      if m then
        local mx, my = m.x or 0, m.y or 0
        local push_top = (cur.at.y <= my + 38) and (dcy <= 0) and (math.abs(dcx) < 3)
        local push_left = (cur.at.x <= mx + 4) and (dcx < 0) and (math.abs(dcy) < 3)
        local push_right = (cur.at.x + cur.size.x >= mx + mw - 4) and (dcx > 0) and (math.abs(dcy) < 3)
        clamped_push = push_top or push_left or push_right
      end
      if clamped_push then
        st.detached_ticks = 0
        st.last_cx = c.x
        st.last_cy = c.y
        update_drag_overlay(st, cur, c)
      else
        st.detached_ticks = (st.detached_ticks or 0) + 1
        st.last_cx = c.x
        st.last_cy = c.y
        if st.detached_ticks >= 2 then
          finish_active_drag(cur, c)
          hl.timer(function() tick(expected_token) end, { type = "oneshot", timeout = 120 })
          return
        end
      end
    end

    hl.timer(function() tick(expected_token) end, { type = "oneshot", timeout = 25 })
    return
  end

  -- Sleep completely (0 Hz) when no floating non-fullscreen window is active.
  if not cur or not c or not cur.floating or (cur.fullscreen or 0) ~= 0 then
    prev_sample = nil
    monitor_running = false
    return
  end

  snap.record_normal_geom(cur)

  if prev_sample and prev_sample.addr == cur.address then
    local same_size = math.abs(cur.size.x - prev_sample.w) <= 2 and math.abs(cur.size.y - prev_sample.h) <= 2
    local dwx = cur.at.x - prev_sample.x
    local dwy = cur.at.y - prev_sample.y
    local dcx = c.x - prev_sample.cx
    local dcy = c.y - prev_sample.cy
    local moved = math.abs(dwx) > 2 or math.abs(dwy) > 2
    local tracks_cursor = math.abs(dwx - dcx) <= 28 and math.abs(dwy - dcy) <= 28
    if same_size and moved and tracks_cursor then
      mouse_drag_state = {
        addr = cur.address,
        x = prev_sample.x,
        y = prev_sample.y,
        w = prev_sample.w,
        h = prev_sample.h,
        last_wx = cur.at.x,
        last_wy = cur.at.y,
        last_cx = c.x,
        last_cy = c.y,
        detached_ticks = 0,
        snap_open = false,
        snap_mon = nil,
        snap_zone = nil,
      }
      update_drag_overlay(mouse_drag_state, cur, c)
      hl.timer(function() tick(expected_token) end, { type = "oneshot", timeout = 25 })
      return
    end
  end

  prev_sample = {
    addr = cur.address,
    x = cur.at.x,
    y = cur.at.y,
    w = cur.size.x,
    h = cur.size.y,
    cx = c.x,
    cy = c.y,
  }

  hl.timer(function() tick(expected_token) end, { type = "oneshot", timeout = 120 })
end

local function ensure_monitor_running()
  local cur = hl.get_active_window()
  if not cur or not cur.floating or (cur.fullscreen or 0) ~= 0 then
    return
  end
  if monitor_running then
    return
  end
  monitor_running = true
  monitor_token = monitor_token + 1
  local token = monitor_token
  hl.timer(function() tick(token) end, { type = "oneshot", timeout = 50 })
end

function M.toggle_click_overlay()
  local w = hl.get_active_window()
  local m = (w and w.monitor) or hl.get_active_monitor()
  if not m then
    return
  end

  local f = io.open(snap_state_path, "r")
  local raw = f and f:read("*a") or ""
  if f then
    f:close()
  end
  if raw:find('"open":true') and raw:find('"mode":"click"') then
    write_snap_state({ open = false })
    return
  end

  local border, titlebar = geometry.get_window_frame_insets(w)
  write_snap_state({
    open = true,
    mode = "click",
    monitor = m.name,
    card = -1,
    zone = -1,
    addr = w and w.address or "",
    border = border,
    titlebar = titlebar,
  })
end

function M.setup(opts)
  layouts_cfg = geometry.load_layouts_config()
  gap_out = opts.gap_out or 8
  gap_in = opts.gap_in or 8
  snap_layouts_enabled = opts.snap_layouts ~= false

  monitor_token = monitor_token + 1
  monitor_running = false
  mouse_drag_state = nil
  prev_sample = nil
  write_snap_state({ open = false })

  if opts.aero_snap ~= false or snap_layouts_enabled then
    ensure_monitor_running()

    local function wake_later()
      hl.timer(ensure_monitor_running, { type = "oneshot", timeout = 10 })
    end

    hl.on("window.active", ensure_monitor_running)
    hl.on("window.open", wake_later)
    hl.on("window.fullscreen", wake_later)
    hl.on("workspace.active", wake_later)
    hl.on("monitor.focused", wake_later)

    hl.bind("mouse:272", function()
      if not mouse_drag_state then
        return
      end
      local cur = hl.get_active_window()
      local c = hl.get_cursor_pos()
      finish_active_drag(cur, c)
    end, { release = true, transparent = true, ignore_mods = true, non_consuming = true })
  end

  if snap_layouts_enabled then
    o.bind("SUPER + Z", "Snap Layouts", M.toggle_click_overlay)
  end
end

return M
