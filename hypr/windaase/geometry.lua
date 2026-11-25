-- Shared monitor work-area math, frame insets, and multi-monitor placement/rescue
-- helpers for Omarchy-windaase. Pure math helpers run standalone under plain Lua.

local layouts_config = require("hypr.windaase.layouts_config")

local M = {}

-- Hyprland's Lua API exposes windows and monitors as sol2 userdata rather than plain tables.
local function is_object(v)
  local t = type(v)
  return t == "table" or t == "userdata"
end

local function is_active_monitor(m)
  return is_object(m)
    and m.disabled ~= true
    and m.is_mirror ~= true
    and type(m.name) == "string"
    and m.name ~= ""
end

local function overlap_len(a1, a2, b1, b2)
  return math.max(0, math.min(a2, b2) - math.max(a1, b1))
end

local function clamp_num(val, lo, hi)
  if val < lo then
    return lo
  end
  if val > hi then
    return hi
  end
  return val
end

function M.monitor_logical_size(m)
  local scale = (m and m.scale) or 1
  if scale <= 0 then
    scale = 1
  end
  local w = math.floor(m.width / scale)
  local h = math.floor(m.height / scale)
  if ((m.transform or 0) % 2) == 1 then
    w, h = h, w
  end
  return w, h
end

function M.get_monitor_at(cx, cy)
  if not hl then
    return nil, 0, 0
  end
  local first_active = nil
  for _, m in ipairs(hl.get_monitors()) do
    if is_active_monitor(m) then
      if not first_active then
        first_active = m
      end
      local w, h = M.monitor_logical_size(m)
      local mx, my = m.x or 0, m.y or 0
      if cx >= mx and cx < mx + w and cy >= my and cy < my + h then
        return m, w, h
      end
    end
  end
  local am = hl.get_active_monitor()
  if is_active_monitor(am) then
    local w, h = M.monitor_logical_size(am)
    return am, w, h
  end
  if first_active then
    local w, h = M.monitor_logical_size(first_active)
    return first_active, w, h
  end
  return nil, 0, 0
end

function M.get_work_area(m, gap_out, gap_in)
  if not m or not m.width then
    return nil
  end
  local w, h = M.monitor_logical_size(m)
  local res = m.reserved or {}
  local r_left = res.left or res[1] or 0
  local r_top = res.top or res[2] or 0
  local r_right = res.right or res[3] or 0
  local r_bottom = res.bottom or res[4] or 0
  local left = (m.x or 0) + r_left
  local top = (m.y or 0) + r_top
  local right = (m.x or 0) + w - r_right
  local bottom = (m.y or 0) + h - r_bottom
  local go = gap_out or 8
  local gi = gap_in or 8

  return {
    x = left + go,
    y = top + go,
    w = right - left - go * 2,
    h = bottom - top - go * 2,
    gap = gi,
    max_x = left,
    max_y = top,
    max_w = right - left,
    max_h = bottom - top,
    edge_left = left,
    edge_top = top,
    edge_right = (m.x or 0) + w,
    edge_bottom = (m.y or 0) + h,
  }
end

function M.zone_rect_in_area(area, z)
  local x1 = area.x + math.floor(z.rx * (area.w + area.gap) + 0.5)
  local x2 = area.x + math.floor((z.rx + z.rw) * (area.w + area.gap) + 0.5) - area.gap
  local y1 = area.y + math.floor(z.ry * (area.h + area.gap) + 0.5)
  local y2 = area.y + math.floor((z.ry + z.rh) * (area.h + area.gap) + 0.5) - area.gap
  return { x = x1, y = y1, w = x2 - x1, h = y2 - y1 }
end

function M.has_floating_workspace_tag(window)
  if not window then
    return false
  end
  local tags = window.tags
  if type(tags) == "table" then
    for _, tag in ipairs(tags) do
      if tag == "omarchy-floating-workspace" then
        return true
      end
    end
    return false
  end
  return hl ~= nil and hl.plugin ~= nil and hl.plugin.hyprbars ~= nil
end

local cached_insets = nil
local cached_insets_hl = nil

function M.invalidate_frame_insets_cache()
  cached_insets = nil
  cached_insets_hl = nil
end

function M.get_window_frame_insets(window)
  if not cached_insets or cached_insets_hl ~= hl then
    local border = 2
    local bar_h = 30
    if hl and hl.get_config then
      local ok_b, b = pcall(hl.get_config, "general.border_size")
      if ok_b and tonumber(b) then
        border = tonumber(b)
      end
      local ok_h, h = pcall(hl.get_config, "plugin.hyprbars.bar_height")
      if not ok_h or not tonumber(h) then
        ok_h, h = pcall(hl.get_config, "plugin:hyprbars:bar_height")
      end
      if ok_h and tonumber(h) then
        bar_h = tonumber(h)
      end
    end
    cached_insets = { border = border, bar_h = bar_h }
    cached_insets_hl = hl
  end

  local titlebar = (window and window.floating and M.has_floating_workspace_tag(window))
    and cached_insets.bar_h
    or 0

  return cached_insets.border, titlebar
end

function M.place_window_in_outer_rect(window, tx, ty, tw, th)
  local border, titlebar = M.get_window_frame_insets(window)
  local cx = tx + border
  local cy = ty + border + titlebar
  local cw = math.max(120, tw - border * 2)
  local ch = math.max(120, th - border * 2 - titlebar)
  hl.dispatch(hl.dsp.window.resize({ x = cw, y = ch, relative = false, window = window }))
  hl.dispatch(hl.dsp.window.move({ x = cx, y = cy, relative = false, window = window }))
end

function M.window_outer_rect(w, border, titlebar)
  if not w or not w.at or not w.size then
    return nil
  end
  local b = tonumber(border) or 2
  local tb = tonumber(titlebar) or 0
  return {
    x = w.at.x - b,
    y = w.at.y - b - tb,
    w = w.size.x + b * 2,
    h = w.size.y + b * 2 + tb,
  }
end

function M.pick_adjacent_monitor(monitors, current_name, direction)
  if not is_object(monitors) or type(current_name) ~= "string" or current_name == "" then
    return nil
  end
  local active = {}
  for _, m in ipairs(monitors) do
    if is_active_monitor(m) then
      active[#active + 1] = m
    end
  end
  if #active < 2 then
    return nil
  end
  table.sort(active, function(a, b)
    local ax, bx = a.x or 0, b.x or 0
    if ax ~= bx then
      return ax < bx
    end
    local ay, by = a.y or 0, b.y or 0
    if ay ~= by then
      return ay < by
    end
    return tostring(a.name) < tostring(b.name)
  end)

  local cur_idx = nil
  for i, m in ipairs(active) do
    if m.name == current_name then
      cur_idx = i
      break
    end
  end
  if not cur_idx then
    return nil
  end

  local delta = (direction == "l" or direction == "left" or direction == -1) and -1 or 1
  local next_idx = ((cur_idx - 1 + delta) % #active) + 1
  return active[next_idx]
end

function M.map_rect_between_areas(outer, src_area, dst_area, zone_name, custom_zone)
  if not src_area or not dst_area then
    return nil
  end

  if zone_name == "maximize" or (type(custom_zone) == "table" and custom_zone.max) then
    return {
      x = dst_area.max_x,
      y = dst_area.max_y,
      w = dst_area.max_w,
      h = dst_area.max_h,
      mode = "maximize",
    }
  end

  local spec = (type(custom_zone) == "table" and custom_zone) or layouts_config.named_zone_spec(zone_name)
  if spec then
    local r = M.zone_rect_in_area(dst_area, spec)
    return {
      x = r.x,
      y = r.y,
      w = r.w,
      h = r.h,
      mode = "zone",
    }
  end

  if type(outer) ~= "table" then
    local fw = math.max(120, math.min(dst_area.w, math.floor(dst_area.w * 0.68)))
    local fh = math.max(120, math.min(dst_area.h, math.floor(dst_area.h * 0.75)))
    return {
      x = dst_area.x + math.floor((dst_area.w - fw) / 2),
      y = dst_area.y + math.floor((dst_area.h - fh) / 2),
      w = fw,
      h = fh,
      mode = "float",
    }
  end

  local tol = 10
  local full_h = math.abs(outer.y - src_area.y) <= tol
    and math.abs((outer.y + outer.h) - (src_area.y + src_area.h)) <= tol
  local full_w = math.abs(outer.x - src_area.x) <= tol
    and math.abs((outer.x + outer.w) - (src_area.x + src_area.w)) <= tol
  local at_left = math.abs(outer.x - src_area.x) <= tol
  local at_right = math.abs((outer.x + outer.w) - (src_area.x + src_area.w)) <= tol
  local at_top = math.abs(outer.y - src_area.y) <= tol
  local at_bottom = math.abs((outer.y + outer.h) - (src_area.y + src_area.h)) <= tol

  if (full_h and (at_left or at_right)) or (full_w and (at_top or at_bottom)) then
    local src_gap = src_area.gap or 0
    local span_w = math.max(1, src_area.w + src_gap)
    local span_h = math.max(1, src_area.h + src_gap)

    local rx = at_left and 0 or clamp_num((outer.x - src_area.x) / span_w, 0, 0.95)
    local rw = at_right and (1.0 - rx) or clamp_num((outer.w + src_gap) / span_w, 0.05, 1.0 - rx)
    local ry = at_top and 0 or clamp_num((outer.y - src_area.y) / span_h, 0, 0.95)
    local rh = at_bottom and (1.0 - ry) or clamp_num((outer.h + src_gap) / span_h, 0.05, 1.0 - ry)

    local r = M.zone_rect_in_area(dst_area, { rx = rx, ry = ry, rw = rw, rh = rh, max = false })
    return {
      x = r.x,
      y = r.y,
      w = r.w,
      h = r.h,
      mode = "zone",
    }
  end

  local fw = clamp_num(math.floor(outer.w + 0.5), 120, math.max(120, dst_area.w))
  local fh = clamp_num(math.floor(outer.h + 0.5), 120, math.max(120, dst_area.h))
  local max_src_dx = math.max(1, src_area.w - outer.w)
  local max_src_dy = math.max(1, src_area.h - outer.h)
  local rel_x = clamp_num((outer.x - src_area.x) / max_src_dx, 0, 1)
  local rel_y = clamp_num((outer.y - src_area.y) / max_src_dy, 0, 1)
  local max_dst_dx = math.max(0, dst_area.w - fw)
  local max_dst_dy = math.max(0, dst_area.h - fh)

  return {
    x = clamp_num(dst_area.x + math.floor(rel_x * max_dst_dx + 0.5), dst_area.x, dst_area.x + max_dst_dx),
    y = clamp_num(dst_area.y + math.floor(rel_y * max_dst_dy + 0.5), dst_area.y, dst_area.y + max_dst_dy),
    w = fw,
    h = fh,
    mode = "float",
  }
end

local function pick_active_from_candidate(cand, by_name, by_id, has_catalog)
  if not is_object(cand) then
    return nil
  end
  if has_catalog then
    if type(cand.name) == "string" and cand.name ~= "" and by_name[cand.name] then
      return by_name[cand.name]
    end
    if cand.id ~= nil and by_id[cand.id] then
      return by_id[cand.id]
    end
    return nil
  end
  if is_active_monitor(cand) then
    return cand
  end
  return nil
end

function M.resolve_active_monitor_for_window(window, monitors, active_mon)
  if not is_object(window) then
    return nil
  end
  local by_name = {}
  local by_id = {}
  local active_list = {}
  local has_catalog = is_object(monitors)
  if has_catalog then
    for _, m in ipairs(monitors) do
      if is_active_monitor(m) then
        by_name[m.name] = m
        if m.id ~= nil then
          by_id[m.id] = m
        end
        active_list[#active_list + 1] = m
      end
    end
  end

  local ws = window.workspace
  local ws_mon = is_object(ws) and ws.monitor or nil
  local resolved = pick_active_from_candidate(ws_mon, by_name, by_id, has_catalog)
  if resolved then
    return resolved
  end

  resolved = pick_active_from_candidate(window.monitor, by_name, by_id, has_catalog)
  if resolved then
    return resolved
  end

  local ws_id = is_object(ws) and tonumber(ws.id) or nil
  if ws_id then
    for _, m in ipairs(active_list) do
      if is_object(m.active_workspace) and tonumber(m.active_workspace.id) == ws_id then
        return m
      end
    end
  end

  resolved = pick_active_from_candidate(active_mon, by_name, by_id, has_catalog)
  if resolved then
    return resolved
  end

  return active_list[1]
end

function M.find_containing_monitor(outer, monitors, exclude_name)
  if type(outer) ~= "table" or not is_object(monitors) then
    return nil
  end
  local ow = tonumber(outer.w) or 0
  local oh = tonumber(outer.h) or 0
  if ow <= 0 or oh <= 0 then
    return nil
  end

  local cx = outer.x + ow / 2
  local cy = outer.y + oh / 2
  local best_m = nil
  local best_score = 0

  for _, m in ipairs(monitors) do
    if is_object(m) and m.width and m.is_mirror ~= true and m.name ~= exclude_name then
      local mw, mh = M.monitor_logical_size(m)
      local mx, my = m.x or 0, m.y or 0
      local ix = overlap_len(outer.x, outer.x + ow, mx, mx + mw)
      local iy = overlap_len(outer.y, outer.y + oh, my, my + mh)
      local overlap = ix * iy
      if overlap > 0 then
        local center_inside = (cx >= mx and cx < mx + mw and cy >= my and cy < my + mh)
        local score = overlap + (center_inside and 1e9 or 0)
        if score > best_score then
          best_score = score
          best_m = m
        end
      end
    end
  end

  return best_m
end

function M.rect_needs_rescue(outer, dst_area, check_oversize)
  if not is_object(outer) or not is_object(dst_area) then
    return false
  end
  check_oversize = (check_oversize ~= false)
  local ow = tonumber(outer.w) or 0
  local oh = tonumber(outer.h) or 0
  if ow <= 0 or oh <= 0 then
    return false
  end
  local ax = dst_area.max_x or dst_area.x or 0
  local ay = dst_area.max_y or dst_area.y or 0
  local aw = dst_area.max_w or dst_area.w or 0
  local ah = dst_area.max_h or dst_area.h or 0
  if aw <= 0 or ah <= 0 then
    return false
  end

  local vis_w = overlap_len(outer.x, outer.x + ow, ax, ax + aw)
  local vis_h = overlap_len(outer.y, outer.y + oh, ay, ay + ah)
  local grab_vis_h = overlap_len(outer.y, outer.y + math.min(oh, 36), ay, ay + ah)

  return vis_w < math.min(ow, 80)
    or vis_h < math.min(oh, 60)
    or grab_vis_h < math.min(oh, 24)
    or (check_oversize and (ow > aw + 12 or oh > ah + 12))
end

function M.detect_drag_edge_zone(cx, cy, area, monitors, mon_name)
  if type(cx) ~= "number" or type(cy) ~= "number" or not is_object(area) then
    return nil
  end
  if cx < area.edge_left - 2 or cx > area.edge_right + 2 or cy < area.edge_top - 2 or cy > area.edge_bottom + 2 then
    return nil
  end

  local has_left = false
  local has_right = false
  local has_top = false
  if is_object(monitors) then
    for _, o in ipairs(monitors) do
      if is_active_monitor(o) and o.name ~= mon_name then
        local ow, oh = M.monitor_logical_size(o)
        local ox, oy = o.x or 0, o.y or 0
        local y_shared = overlap_len(oy, oy + oh, area.edge_top, area.edge_bottom) > 0
        local x_shared = overlap_len(ox, ox + ow, area.edge_left, area.edge_right) > 0
        if y_shared and math.abs((ox + ow) - area.edge_left) <= 4 then
          has_left = true
        end
        if y_shared and math.abs(ox - area.edge_right) <= 4 then
          has_right = true
        end
        if x_shared and math.abs((oy + oh) - area.edge_top) <= 4 then
          has_top = true
        end
      end
    end
  end

  local left_margin = has_left and 10 or 24
  local right_margin = has_right and 10 or 24
  local top_margin = has_top and 10 or 24
  local corner_margin = 88

  local near_left = cx <= area.edge_left + left_margin
  local near_right = cx >= area.edge_right - right_margin
  local near_top = cy <= area.edge_top + top_margin
  local in_top_corner = cy <= area.edge_top + corner_margin
  local in_bottom_corner = cy >= area.edge_bottom - corner_margin
  local in_left_corner = cx <= area.edge_left + corner_margin
  local in_right_corner = cx >= area.edge_right - corner_margin

  if (near_left and in_top_corner) or (near_top and in_left_corner) then
    return "top-left"
  elseif (near_right and in_top_corner) or (near_top and in_right_corner) then
    return "top-right"
  elseif near_left and in_bottom_corner then
    return "bottom-left"
  elseif near_right and in_bottom_corner then
    return "bottom-right"
  elseif near_left then
    return "left"
  elseif near_right then
    return "right"
  elseif near_top then
    return "maximize"
  end
  return nil
end

function M.clamp_free_drop_rect(outer, area)
  if not is_object(outer) or not is_object(area) then
    return nil
  end
  local ow = tonumber(outer.w) or 0
  local oh = tonumber(outer.h) or 0
  if ow <= 0 or oh <= 0 then
    return nil
  end
  local ax = area.max_x or area.x or 0
  local ay = area.max_y or area.y or 0
  local aw = area.max_w or area.w or 0
  local ah = area.max_h or area.h or 0
  if aw <= 0 or ah <= 0 then
    return nil
  end

  local vis_w = overlap_len(outer.x, outer.x + ow, ax, ax + aw)
  local grab_top = outer.y
  local grab_bottom = outer.y + math.min(oh, 36)
  local grab_vis_h = overlap_len(grab_top, grab_bottom, ay, ay + ah)
  if ow <= aw + 4
    and oh <= ah + 4
    and outer.y >= ay - 4
    and grab_vis_h >= math.min(oh, 24)
    and grab_bottom <= (ay + ah - 24)
    and vis_w >= math.min(ow, 100) then
    return nil
  end

  local nw = (ow > aw + 4) and math.max(120, math.min(ow, area.w or aw)) or ow
  local nh = (oh > ah + 4) and math.max(120, math.min(oh, area.h or ah)) or oh
  local nx = clamp_num(math.floor(outer.x + 0.5), ax, ax + math.max(0, aw - nw))
  local ny = clamp_num(math.floor(outer.y + 0.5), ay, ay + math.max(0, ah - nh))
  return {
    x = nx,
    y = ny,
    w = math.floor(nw + 0.5),
    h = math.floor(nh + 0.5),
  }
end

local function is_soft_max_on_area(outer, area)
  if type(outer) ~= "table" or not is_object(area) then
    return false
  end
  local ax = area.max_x or area.x or 0
  local ay = area.max_y or area.y or 0
  local aw = area.max_w or area.w or 0
  local ah = area.max_h or area.h or 0
  return aw > 0
    and ah > 0
    and math.abs(outer.x - ax) <= 6
    and math.abs(outer.y - ay) <= 6
    and outer.w >= aw - 16
    and outer.h >= ah - 16
end

function M.rescue_rect_to_area(outer, dst_area, zone_name, custom_zone, src_area)
  if not is_object(dst_area) then
    return nil
  end
  if not zone_name and type(custom_zone) ~= "table" and is_soft_max_on_area(outer, src_area) then
    zone_name = "maximize"
  end
  if zone_name or type(custom_zone) == "table" or is_object(src_area) then
    return M.map_rect_between_areas(outer, src_area or dst_area, dst_area, zone_name, custom_zone)
  end

  local ow = is_object(outer) and tonumber(outer.w) or nil
  local oh = is_object(outer) and tonumber(outer.h) or nil
  if not ow or not oh or ow <= 0 or oh <= 0 then
    return M.map_rect_between_areas(nil, dst_area, dst_area, nil, nil)
  end

  local fw = clamp_num(math.floor(ow + 0.5), 120, math.max(120, dst_area.w))
  local fh = clamp_num(math.floor(oh + 0.5), 120, math.max(120, dst_area.h))
  local max_dx = math.max(0, dst_area.w - fw)
  local max_dy = math.max(0, dst_area.h - fh)

  local on_x = overlap_len(outer.x, outer.x + ow, dst_area.x, dst_area.x + dst_area.w) >= math.min(ow, 80)
  local on_y = overlap_len(outer.y, outer.y + oh, dst_area.y, dst_area.y + dst_area.h) >= math.min(oh, 60)
  local rx = on_x and clamp_num(math.floor(outer.x + 0.5), dst_area.x, dst_area.x + max_dx)
    or (dst_area.x + math.floor(max_dx / 2))
  local ry = on_y and clamp_num(math.floor(outer.y + 0.5), dst_area.y, dst_area.y + max_dy)
    or (dst_area.y + math.floor(max_dy / 2))

  return {
    x = rx,
    y = ry,
    w = fw,
    h = fh,
    mode = "float",
  }
end

function M.is_manageable_floating_window(w)
  if not is_object(w) or not w.floating then
    return false
  end
  if w.mapped == false or w.hidden == true or (w.fullscreen or 0) == 2 then
    return false
  end
  if w.size and ((tonumber(w.size.x) or 0) < 40 or (tonumber(w.size.y) or 0) < 40) then
    return false
  end
  if w.xwayland == true and (w.class == nil or w.class == "") and (w.title == nil or w.title == "") then
    return false
  end
  local ws = w.workspace
  if ws then
    local ws_name = type(ws.name) == "string" and ws.name or ""
    local ws_id = tonumber(ws.id)
    if ws_name:match("^special:") or (ws_id and ws_id < 1) then
      return false
    end
  end
  return true
end

function M.rect_overflows_area(outer, area, tol)
  if not is_object(outer) or not is_object(area) then
    return false
  end
  local ow = tonumber(outer.w) or 0
  local oh = tonumber(outer.h) or 0
  if ow <= 0 or oh <= 0 then
    return false
  end
  local ax = area.max_x or area.x or 0
  local ay = area.max_y or area.y or 0
  local aw = area.max_w or area.w or 0
  local ah = area.max_h or area.h or 0
  if aw <= 0 or ah <= 0 then
    return false
  end
  local t = tonumber(tol) or 4
  return outer.x < ax - t
    or outer.y < ay - t
    or (outer.x + ow) > (ax + aw + t)
    or (outer.y + oh) > (ay + ah + t)
end

function M.contain_rect_in_area(outer, area, zone_name)
  if not M.rect_overflows_area(outer, area, 4) then
    return nil
  end
  local ax = area.max_x or area.x or 0
  local ay = area.max_y or area.y or 0
  local aw = area.max_w or area.w or 0
  local ah = area.max_h or area.h or 0
  if zone_name == "maximize" then
    return {
      x = ax,
      y = ay,
      w = aw,
      h = ah,
      mode = "maximize",
    }
  end

  local ow = tonumber(outer.w) or 0
  local oh = tonumber(outer.h) or 0
  local work_x = area.x or ax
  local work_y = area.y or ay
  local work_w = area.w or aw
  local work_h = area.h or ah

  local nw = (ow > aw + 4)
    and clamp_num(math.floor(ow + 0.5), 120, math.max(120, work_w))
    or math.floor(ow + 0.5)
  local nh = (oh > ah + 4)
    and clamp_num(math.floor(oh + 0.5), 120, math.max(120, work_h))
    or math.floor(oh + 0.5)

  local x_overflows = outer.x < ax - 4 or (outer.x + ow) > (ax + aw + 4) or nw ~= math.floor(ow + 0.5)
  local y_overflows = outer.y < ay - 4 or (outer.y + oh) > (ay + ah + 4) or nh ~= math.floor(oh + 0.5)

  local nx = math.floor(outer.x + 0.5)
  if x_overflows then
    if nw <= work_w then
      nx = clamp_num(nx, work_x, work_x + math.max(0, work_w - nw))
    else
      nx = clamp_num(nx, ax, ax + math.max(0, aw - nw))
    end
  end

  local ny = math.floor(outer.y + 0.5)
  if y_overflows then
    if nh <= work_h then
      ny = clamp_num(ny, work_y, work_y + math.max(0, work_h - nh))
    else
      ny = clamp_num(ny, ay, ay + math.max(0, ah - nh))
    end
  end

  return {
    x = nx,
    y = ny,
    w = nw,
    h = nh,
    mode = "float",
  }
end

function M.is_interactive_edge_resize(prev_sample, cur_w, cur_c)
  if not is_object(prev_sample) or not is_object(cur_w) or not is_object(cur_c) then
    return false
  end
  if prev_sample.addr ~= cur_w.address or not cur_w.at or not cur_w.size then
    return false
  end
  if prev_sample.x == nil or prev_sample.y == nil or prev_sample.w == nil or prev_sample.h == nil or prev_sample.cx == nil or prev_sample.cy == nil then
    return false
  end
  if math.abs(cur_w.size.x - prev_sample.w) == 0 and math.abs(cur_w.size.y - prev_sample.h) == 0 then
    return false
  end
  local dcx = cur_c.x - prev_sample.cx
  local dcy = cur_c.y - prev_sample.cy
  if math.abs(dcx) < 1 and math.abs(dcy) < 1 then
    return false
  end

  local d_left = cur_w.at.x - prev_sample.x
  local d_right = (cur_w.at.x + cur_w.size.x) - (prev_sample.x + prev_sample.w)
  local d_top = cur_w.at.y - prev_sample.y
  local d_bottom = (cur_w.at.y + cur_w.size.y) - (prev_sample.y + prev_sample.h)

  local x_ok = (d_left == 0 and d_right == 0)
    or (math.abs(d_left - dcx) <= 32 and math.abs(d_right) <= 4)
    or (math.abs(d_right - dcx) <= 32 and math.abs(d_left) <= 4)
  local y_ok = (d_top == 0 and d_bottom == 0)
    or (math.abs(d_top - dcy) <= 32 and math.abs(d_bottom) <= 4)
    or (math.abs(d_bottom - dcy) <= 32 and math.abs(d_top) <= 4)
  return x_ok and y_ok
end

return M
