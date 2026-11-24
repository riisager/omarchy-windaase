-- Event-driven drag monitor for Windows 11 top-edge Snap Layouts and
-- edge-drag snapping, plus Super+Z click overlay toggle.

local geometry = require("hypr.windaase.geometry")
local snap = require("hypr.windaase.snap")
local snap_resize = require("hypr.windaase.snap_resize")

local M = {}

local snap_state_path = (os.getenv("XDG_RUNTIME_DIR") or os.getenv("XDG_CACHE_HOME") or ((os.getenv("HOME") or ".") .. "/.cache")) .. "/omarchy-windaase-snap.json"
local last_snap_json = ""
local layouts_cfg = nil
local gap_out = 8
local gap_in = 8
local snap_layouts_enabled = true
local snap_assist_enabled = true
local aero_snap_enabled = true
local ultrawide_enabled = false
local assist_seq = 0
local pending_assist = nil

local mouse_drag_state = nil
local prev_sample = nil
local suppress_snap_ticks = 0
local monitor_running = false
local monitor_token = 0
local hooks_registered = false
local mouse_binds = {}

local function bind_alive(kb)
  return kb ~= nil and tostring(kb) ~= "HL.Keybind(expired)"
end

local function read_snap_state_raw()
  local f = io.open(snap_state_path, "r")
  if not f then
    return ""
  end
  local raw = f:read("*a") or ""
  f:close()
  return raw
end

local function write_snap_state(tbl)
  local payload
  if not tbl or not tbl.open then
    payload = '{"open":false}\n'
  else
    local uw_flag = (tbl.uw ~= nil) and tbl.uw or ultrawide_enabled
    local assist_flag = (tbl.assist ~= nil) and tbl.assist or snap_assist_enabled
    payload = string.format(
      '{"open":true,"mode":"%s","monitor":"%s","card":%d,"zone":%d,"px":%d,"py":%d,"pw":%d,"ph":%d,"addr":"%s","border":%d,"titlebar":%d,"ws":%d,"uw":%s,"assist":%s,"go":%d,"gi":%d,"axis":"%s","p1":%d,"p2":%d}\n',
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
      tbl.titlebar or 30,
      tbl.ws or -1,
      uw_flag and "true" or "false",
      assist_flag and "true" or "false",
      tbl.go or gap_out,
      tbl.gi or gap_in,
      geometry.json_escape(tbl.axis or "x"),
      tbl.p1 or 50,
      tbl.p2 or 50
    )
  end

  local is_dedup_mode = tbl and tbl.open and (tbl.mode == nil or tbl.mode == "drag" or tbl.mode == "resize")
  if is_dedup_mode and payload == last_snap_json then
    return
  end
  last_snap_json = payload

  local tmp = snap_state_path .. ".lua.tmp"
  local f = io.open(tmp, "w")
  if f then
    f:write(payload)
    f:close()
    os.rename(tmp, snap_state_path)
  end
end

M.write_state = write_snap_state

local function cancel_assist_only()
  if pending_assist ~= nil then
    pending_assist = nil
    assist_seq = assist_seq + 1
    write_snap_state({ open = false })
  end
end

function M.cancel_overlay()
  assist_seq = assist_seq + 1
  pending_assist = nil
  snap_resize.clear_flash()
  write_snap_state({ open = false })
end

function M.suppress(ticks)
  local n = tonumber(ticks) or 6
  if n > suppress_snap_ticks then
    suppress_snap_ticks = n
  end
  assist_seq = assist_seq + 1
  pending_assist = nil
  snap_resize.clear_flash()
  local raw = read_snap_state_raw()
  if raw:find('"open":true') and (raw:find('"mode":"assist"') or raw:find('"mode":"click"') or raw:find('"mode":"resize"')) then
    write_snap_state({ open = false })
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
  local picked_mon = st.snap_open and ((st.snap_mon_name and hl.get_monitor(st.snap_mon_name)) or st.snap_mon) or nil
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
    if ly <= 48 or win_top <= 36 then
      assist_seq = assist_seq + 1
      st.snap_open = true
      st.snap_mon = m
      st.snap_mon_name = m.name
    end
  elseif st.snap_mon and m.name ~= st.snap_mon.name and (ly <= 48 or win_top <= 36) then
    assist_seq = assist_seq + 1
    st.snap_mon = m
    st.snap_mon_name = m.name
  end

  if st.snap_open then
    if st.snap_mon and m.name == st.snap_mon.name and (ly <= py + ph + 72 or win_top <= 42) then
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
      st.snap_mon = nil
      st.snap_mon_name = nil
      st.snap_zone = nil
      write_snap_state({ open = false })
    end
  end
end

local function tick(expected_token)
  if expected_token ~= monitor_token then
    return
  end

  local cur = hl.get_active_window()
  local c = hl.get_cursor_pos()

  if snap_resize.is_active() then
    snap_resize.tick_active_resize(c)
    prev_sample = nil
    hl.timer(function() tick(expected_token) end, { type = "oneshot", timeout = 16 })
    return
  end

  if suppress_snap_ticks > 0 then
    suppress_snap_ticks = suppress_snap_ticks - 1
    prev_sample = nil
    if suppress_snap_ticks == 0 and cur and cur.floating and (cur.fullscreen or 0) == 0 then
      snap_resize.snapshot_workspace(cur)
    end
    hl.timer(function() tick(expected_token) end, { type = "oneshot", timeout = 80 })
    return
  end

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
    local cur_moved = math.abs(dcx) >= 2 or math.abs(dcy) >= 2

    if win_moved then
      st.detached_ticks = 0
      st.last_wx = cur.at.x
      st.last_wy = cur.at.y
      st.last_cx = c.x
      st.last_cy = c.y
      st.drop_cx = c.x
      st.drop_cy = c.y
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
        st.drop_cx = c.x
        st.drop_cy = c.y
        update_drag_overlay(st, cur, c)
      else
        st.detached_ticks = (st.detached_ticks or 0) + 1
        st.last_cx = c.x
        st.last_cy = c.y
        if st.detached_ticks >= 2 then
          finish_active_drag(cur, { x = st.drop_cx or c.x, y = st.drop_cy or c.y })
          hl.timer(function() tick(expected_token) end, { type = "oneshot", timeout = 80 })
          return
        end
      end
    elseif (st.detached_ticks or 0) > 0 then
      finish_active_drag(cur, { x = st.drop_cx or c.x, y = st.drop_cy or c.y })
      hl.timer(function() tick(expected_token) end, { type = "oneshot", timeout = 80 })
      return
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

  if snap_resize.try_begin_mouse_resize(cur, c) then
    prev_sample = nil
    hl.timer(function() tick(expected_token) end, { type = "oneshot", timeout = 16 })
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
      pending_assist = nil
      assist_seq = assist_seq + 1
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
        drop_cx = c.x,
        drop_cy = c.y,
        detached_ticks = 0,
        snap_open = false,
        snap_mon = nil,
        snap_mon_name = nil,
        snap_zone = nil,
      }
      update_drag_overlay(mouse_drag_state, cur, c)
      hl.timer(function() tick(expected_token) end, { type = "oneshot", timeout = 25 })
      return
    end
  end

  snap_resize.snapshot_workspace(cur)

  prev_sample = {
    addr = cur.address,
    x = cur.at.x,
    y = cur.at.y,
    w = cur.size.x,
    h = cur.size.y,
    cx = c.x,
    cy = c.y,
  }

  hl.timer(function() tick(expected_token) end, { type = "oneshot", timeout = 80 })
end

local function ensure_monitor_running()
  if not aero_snap_enabled and not snap_layouts_enabled then
    return
  end
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

local function has_assist_candidate(ws_id, exclude_addr)
  for _, other in ipairs(hl.get_workspace_windows(tostring(ws_id))) do
    if other.address ~= exclude_addr
      and other.mapped ~= false
      and other.floating
      and (other.fullscreen or 0) == 0 then
      return true
    end
  end
  return false
end

function M.schedule_assist(window, m, snapped_zone)
  if not snap_assist_enabled or not window or not m then
    return
  end
  local comp = geometry.complementary_zone(snapped_zone)
  if not comp then
    return
  end

  local ws = (window.workspace and window.workspace.id and window.workspace) or hl.get_active_workspace()
  local ws_id = ws and tonumber(ws.id) or -1
  if ws_id < 1 then
    return
  end

  local exclude_addr = window.address
  if not has_assist_candidate(ws_id, exclude_addr) then
    return
  end

  assist_seq = assist_seq + 1
  snap_resize.clear_flash()
  local seq = assist_seq
  local mon_name = m.name
  local area = geometry.get_work_area(m, gap_out, gap_in)
  if not area then
    return
  end
  local rect = geometry.zone_rect_in_area(area, comp)
  local px = rect.x - (m.x or 0)
  local py = rect.y - (m.y or 0)
  local pw = rect.w
  local ph = rect.h
  local border, titlebar = geometry.get_window_frame_insets(window)

  hl.timer(function()
    if seq ~= assist_seq then
      return
    end
    if not has_assist_candidate(ws_id, exclude_addr) then
      return
    end
    pending_assist = {
      monitor = mon_name or "",
      zone = comp,
      snapped_addr = exclude_addr or "",
      rect = { x = rect.x, y = rect.y, w = rect.w, h = rect.h },
    }
    write_snap_state({
      open = true,
      mode = "assist",
      monitor = mon_name,
      card = -1,
      zone = -1,
      px = px,
      py = py,
      pw = pw,
      ph = ph,
      addr = exclude_addr or "",
      border = border,
      titlebar = titlebar,
      ws = ws_id,
    })
  end, { type = "oneshot", timeout = 40 })
end

function M.toggle_click_overlay()
  assist_seq = assist_seq + 1
  pending_assist = nil
  snap_resize.clear_flash()
  local raw = read_snap_state_raw()
  if raw:find('"open":true') and (raw:find('"mode":"click"') or raw:find('"mode":"assist"')) then
    write_snap_state({ open = false })
    return
  end

  local w = hl.get_active_window()
  if not w or not w.floating then
    return
  end
  local m = w.monitor or hl.get_active_monitor()
  if not m then
    return
  end

  local ws = (w.workspace and w.workspace.id and w.workspace) or hl.get_active_workspace()
  local ws_id = ws and tonumber(ws.id) or -1
  local border, titlebar = geometry.get_window_frame_insets(w)
  write_snap_state({
    open = true,
    mode = "click",
    monitor = m.name,
    card = -1,
    zone = -1,
    addr = w.address or "",
    border = border,
    titlebar = titlebar,
    ws = ws_id,
  })
end

function M.apply_click_zone(addr, mon_name, rx, ry, rw, rh, is_max)
  rx = tonumber(rx)
  ry = tonumber(ry)
  rw = tonumber(rw)
  rh = tonumber(rh)
  if not rx or not ry or not rw or not rh
    or rx < 0 or rx >= 1 or ry < 0 or ry >= 1
    or rw <= 0 or rw > 1 or rh <= 0 or rh > 1 then
    M.cancel_overlay()
    return false
  end

  local w = (type(addr) == "string" and addr:match("^0x[0-9a-fA-F]+$") and hl.get_window("address:" .. addr))
    or hl.get_active_window()
  if not w or not w.floating then
    M.cancel_overlay()
    return false
  end

  local m = (type(mon_name) == "string" and mon_name ~= "" and hl.get_monitor(mon_name))
    or w.monitor
    or hl.get_active_monitor()
  M.cancel_overlay()
  if not m then
    return false
  end

  local ok = snap.apply_snap_zone(w, m, { rx = rx, ry = ry, rw = rw, rh = rh, max = (is_max == true) }, nil, false)
  if ok then
    hl.dispatch(hl.dsp.focus({ window = w }))
  end
  return ok
end

function M.apply_assist_addr(target_addr)
  local pa = pending_assist
  M.cancel_overlay()
  if not pa or type(target_addr) ~= "string" or not target_addr:match("^0x[0-9a-fA-F]+$") then
    return false
  end

  local w = hl.get_window("address:" .. target_addr)
  if not w or not w.floating then
    return false
  end

  local m = (pa.monitor ~= "" and hl.get_monitor(pa.monitor)) or w.monitor or hl.get_active_monitor()
  if not m then
    return false
  end

  local ok = snap.apply_snap_zone(w, m, pa.zone, nil, true)
  hl.dispatch(hl.dsp.focus({ window = "address:" .. target_addr }))
  hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", window = "address:" .. target_addr }))
  return ok
end

function M.setup(opts)
  ultrawide_enabled = opts.ultrawide_layout == true
  layouts_cfg = geometry.resolve_layouts_config(geometry.load_layouts_config(), ultrawide_enabled)
  gap_out = opts.gap_out or 8
  gap_in = opts.gap_in or 8
  aero_snap_enabled = opts.aero_snap ~= false
  snap_layouts_enabled = opts.snap_layouts ~= false
  snap_assist_enabled = opts.snap_assist ~= false

  monitor_token = monitor_token + 1
  monitor_running = false
  mouse_drag_state = nil
  prev_sample = nil
  pending_assist = nil
  assist_seq = assist_seq + 1
  snap_resize.clear_flash()
  write_snap_state({ open = false })

  if not hooks_registered then
    hooks_registered = true
    local function wake_later()
      hl.timer(ensure_monitor_running, { type = "oneshot", timeout = 10 })
    end
    local function cancel_assist_and_wake()
      cancel_assist_only()
      wake_later()
    end

    hl.on("window.active", function(window)
      if pending_assist and (not window or window.address ~= pending_assist.snapped_addr) then
        cancel_assist_only()
      end
      ensure_monitor_running()
    end)
    hl.on("window.open", cancel_assist_and_wake)
    hl.on("window.fullscreen", wake_later)
    hl.on("workspace.active", cancel_assist_and_wake)
    hl.on("monitor.focused", cancel_assist_and_wake)
    hl.on("monitor.added", M.cancel_overlay)
    hl.on("monitor.removed", M.cancel_overlay)
    hl.on("monitor.layout_changed", M.cancel_overlay)
  end

  local release_opts = { release = true, transparent = true, ignore_mods = true, non_consuming = true }
  local drag_watch = aero_snap_enabled or snap_layouts_enabled
  if drag_watch and not bind_alive(mouse_binds["mouse:272"]) then
    mouse_binds["mouse:272"] = hl.bind("mouse:272", function()
      if snap_resize.is_active() then
        snap_resize.finish_active_resize()
        prev_sample = nil
        return
      end
      if not mouse_drag_state then
        if pending_assist then
          local c = hl.get_cursor_pos()
          local r = pending_assist.rect
          if c and r and (c.x < r.x - 16 or c.x > r.x + r.w + 16 or c.y < r.y - 16 or c.y > r.y + r.h + 16) then
            cancel_assist_only()
          end
        end
        return
      end
      local cur = hl.get_active_window()
      local c = hl.get_cursor_pos()
      finish_active_drag(cur, c)
    end, release_opts)
  end
  if bind_alive(mouse_binds["mouse:272"]) then
    mouse_binds["mouse:272"]:set_enabled(drag_watch)
  end

  local resize_watch = aero_snap_enabled and opts.snap_resize ~= false
  if resize_watch and not bind_alive(mouse_binds["mouse:273"]) then
    mouse_binds["mouse:273"] = hl.bind("mouse:273", function()
      if snap_resize.is_active() then
        snap_resize.finish_active_resize()
        prev_sample = nil
      end
    end, release_opts)
  end
  if bind_alive(mouse_binds["mouse:273"]) then
    mouse_binds["mouse:273"]:set_enabled(resize_watch)
  end

  if drag_watch then
    ensure_monitor_running()
  end

  if snap_layouts_enabled then
    o.rebind("SUPER + Z", "Snap Layouts", M.toggle_click_overlay)
  end
end

function M.is_dragging()
  return mouse_drag_state ~= nil or snap_resize.is_active()
end

return M
