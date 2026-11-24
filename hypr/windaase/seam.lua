-- Coupled Snap Resize seam-graph solver and edge-detection helpers.
-- Pure math functions run standalone under plain Lua for tests.

local M = {}

local DEFAULT_SPLIT_PRESETS = { 0.25, 0.35, 0.50, 0.65, 0.75 }

function M.detect_resize_edge(prev_outer, cur_outer)
  if not prev_outer or not cur_outer then
    return nil, nil
  end
  local dx1 = cur_outer.x - prev_outer.x
  local dx2 = (cur_outer.x + cur_outer.w) - (prev_outer.x + prev_outer.w)
  local dy1 = cur_outer.y - prev_outer.y
  local dy2 = (cur_outer.y + cur_outer.h) - (prev_outer.y + prev_outer.h)
  local dw = cur_outer.w - prev_outer.w
  local dh = cur_outer.h - prev_outer.h

  if math.abs(dw) >= 2 and math.abs(dh) <= 2 and math.abs(dy1) <= 2 and math.abs(dy2) <= 2 then
    if math.abs(dx1) <= 2 and math.abs(dx2) >= 2 then
      return "right", "x"
    elseif math.abs(dx2) <= 2 and math.abs(dx1) >= 2 then
      return "left", "x"
    end
  elseif math.abs(dh) >= 2 and math.abs(dw) <= 2 and math.abs(dx1) <= 2 and math.abs(dx2) <= 2 then
    if math.abs(dy1) <= 2 and math.abs(dy2) >= 2 then
      return "bottom", "y"
    elseif math.abs(dy2) <= 2 and math.abs(dy1) >= 2 then
      return "top", "y"
    end
  end
  return nil, nil
end

local function project_rect(rect, axis)
  if axis == "x" then
    return rect.x, rect.x + rect.w, rect.y, rect.y + rect.h
  end
  return rect.y, rect.y + rect.h, rect.x, rect.x + rect.w
end

local function overlap_len(a1, a2, b1, b2)
  return math.max(0, math.min(a2, b2) - math.max(a1, b1))
end

local function uncovered_length(c1, c2, intervals)
  if c2 <= c1 then
    return 0
  end
  if #intervals == 0 then
    return c2 - c1
  end
  local clipped = {}
  for _, iv in ipairs(intervals) do
    local s = math.max(c1, iv[1])
    local e = math.min(c2, iv[2])
    if e > s then
      clipped[#clipped + 1] = { s, e }
    end
  end
  if #clipped == 0 then
    return c2 - c1
  end
  table.sort(clipped, function(a, b) return a[1] < b[1] end)
  local covered = 0
  local cur_s, cur_e = clipped[1][1], clipped[1][2]
  for i = 2, #clipped do
    if clipped[i][1] <= cur_e then
      if clipped[i][2] > cur_e then
        cur_e = clipped[i][2]
      end
    else
      covered = covered + (cur_e - cur_s)
      cur_s, cur_e = clipped[i][1], clipped[i][2]
    end
  end
  covered = covered + (cur_e - cur_s)
  return math.max(0, (c2 - c1) - covered)
end

local function make_seam_node(win, axis)
  local p1, p2, c1, c2 = project_rect(win.outer, axis)
  return {
    addr = win.addr,
    outer = { x = win.outer.x, y = win.outer.y, w = win.outer.w, h = win.outer.h },
    border = tonumber(win.border) or 2,
    titlebar = tonumber(win.titlebar) or 0,
    focus_history_id = tonumber(win.focus_history_id) or 999999,
    p1 = p1,
    p2 = p2,
    c1 = c1,
    c2 = c2,
    c_len = math.max(0, c2 - c1),
  }
end

function M.find_seam_group(windows, driver_addr, edge, gap_in, _area)
  if type(windows) ~= "table" or not driver_addr or driver_addr == "" then
    return nil
  end
  if edge ~= "right" and edge ~= "left" and edge ~= "bottom" and edge ~= "top" then
    return nil
  end

  local axis = (edge == "right" or edge == "left") and "x" or "y"
  local driver_side = (edge == "right" or edge == "bottom") and "before" or "after"
  local min_pane = (axis == "x") and 240 or 180
  local gap = tonumber(gap_in) or 8
  local gap_tol = 12

  local driver_node = nil
  local cands = {}
  for idx, win in ipairs(windows) do
    if win and win.addr and win.outer and win.outer.w and win.outer.h then
      local node = make_seam_node(win, axis)
      node._order = idx
      if win.addr == driver_addr then
        driver_node = node
      else
        cands[#cands + 1] = node
      end
    end
  end

  if not driver_node or driver_node.c_len <= 0 then
    return nil
  end

  table.sort(cands, function(a, b)
    if a.focus_history_id ~= b.focus_history_id then
      return a.focus_history_id < b.focus_history_id
    end
    return a._order < b._order
  end)

  local before_list = {}
  local after_list = {}
  local before_intervals = {}
  local after_intervals = {}
  local selected = { [driver_addr] = true }

  local opp_matches = {}
  local opp_intervals = {}
  for _, cand in ipairs(cands) do
    if cand.c_len > 0 then
      local ov = overlap_len(driver_node.c1, driver_node.c2, cand.c1, cand.c2)
      local min_ov = math.max(40, math.min(driver_node.c_len, cand.c_len) * 0.5)
      if ov >= min_ov then
        local edge_ok = false
        if driver_side == "before" then
          edge_ok = cand.p1 >= driver_node.p2 - 4 and math.abs(cand.p1 - (driver_node.p2 + gap)) <= gap_tol
        else
          edge_ok = cand.p2 <= driver_node.p1 + 4 and math.abs(cand.p2 - (driver_node.p1 - gap)) <= gap_tol
        end
        if edge_ok and uncovered_length(cand.c1, cand.c2, opp_intervals) >= cand.c_len * 0.4 then
          opp_matches[#opp_matches + 1] = cand
          opp_intervals[#opp_intervals + 1] = { cand.c1, cand.c2 }
        end
      end
    end
  end

  if #opp_matches == 0 then
    return nil
  end

  local first_opp = opp_matches[1]
  local raw_gap = (driver_side == "before") and (first_opp.p1 - driver_node.p2) or (driver_node.p1 - first_opp.p2)
  local eff_gap = (math.abs(raw_gap - gap) <= 4) and gap or math.max(0, math.min(gap + 12, raw_gap))
  local seam = (driver_side == "before") and driver_node.p2 or (driver_node.p1 - eff_gap)

  if driver_side == "before" then
    before_list[1] = driver_node
    before_intervals[1] = { driver_node.c1, driver_node.c2 }
    for _, opp in ipairs(opp_matches) do
      if math.abs(opp.p1 - (seam + eff_gap)) <= 6 then
        after_list[#after_list + 1] = opp
        after_intervals[#after_intervals + 1] = { opp.c1, opp.c2 }
        selected[opp.addr] = true
      end
    end
    if #after_list == 0 then
      return nil
    end
  else
    after_list[1] = driver_node
    after_intervals[1] = { driver_node.c1, driver_node.c2 }
    for _, opp in ipairs(opp_matches) do
      if math.abs(opp.p2 - seam) <= 6 then
        before_list[#before_list + 1] = opp
        before_intervals[#before_intervals + 1] = { opp.c1, opp.c2 }
        selected[opp.addr] = true
      end
    end
    if #before_list == 0 then
      return nil
    end
  end

  local function current_cross_span()
    local sc1, sc2 = math.huge, -math.huge
    for _, b in ipairs(before_list) do
      if b.c1 < sc1 then sc1 = b.c1 end
      if b.c2 > sc2 then sc2 = b.c2 end
    end
    for _, a in ipairs(after_list) do
      if a.c1 < sc1 then sc1 = a.c1 end
      if a.c2 > sc2 then sc2 = a.c2 end
    end
    return sc1, sc2
  end

  local function fits_side(cand, side)
    if selected[cand.addr] or cand.c_len <= 0 then
      return false
    end
    if side == "before" then
      return math.abs(cand.p2 - seam) <= 6 and uncovered_length(cand.c1, cand.c2, before_intervals) >= cand.c_len * 0.4
    end
    return math.abs(cand.p1 - (seam + eff_gap)) <= 6 and uncovered_length(cand.c1, cand.c2, after_intervals) >= cand.c_len * 0.4
  end

  for _ = 1, 4 do
    local changed = false
    local span_c1, span_c2 = current_cross_span()

    for _, cand in ipairs(cands) do
      if not selected[cand.addr] and cand.c_len > 0 then
        local ov = overlap_len(span_c1, span_c2, cand.c1, cand.c2)
        if ov >= math.max(40, cand.c_len * 0.5) then
          if fits_side(cand, "before") then
            before_list[#before_list + 1] = cand
            before_intervals[#before_intervals + 1] = { cand.c1, cand.c2 }
            selected[cand.addr] = true
            changed = true
          elseif fits_side(cand, "after") then
            after_list[#after_list + 1] = cand
            after_intervals[#after_intervals + 1] = { cand.c1, cand.c2 }
            selected[cand.addr] = true
            changed = true
          end
        end
      end
    end

    -- 2x2 paired continuation across cross-axis gap
    span_c1, span_c2 = current_cross_span()
    local cross_tol = gap + 12
    for _, cand_b in ipairs(cands) do
      if fits_side(cand_b, "before") then
        local adj_below = cand_b.c1 >= span_c2 - 4 and cand_b.c1 <= span_c2 + cross_tol
        local adj_above = cand_b.c2 <= span_c1 + 4 and cand_b.c2 >= span_c1 - cross_tol
        if adj_below or adj_above then
          for _, cand_a in ipairs(cands) do
            if fits_side(cand_a, "after") and overlap_len(cand_b.c1, cand_b.c2, cand_a.c1, cand_a.c2) >= 40 then
              before_list[#before_list + 1] = cand_b
              before_intervals[#before_intervals + 1] = { cand_b.c1, cand_b.c2 }
              selected[cand_b.addr] = true
              after_list[#after_list + 1] = cand_a
              after_intervals[#after_intervals + 1] = { cand_a.c1, cand_a.c2 }
              selected[cand_a.addr] = true
              changed = true
              break
            end
          end
        end
      end
    end

    if not changed then
      break
    end
  end

  local min_seam = -math.huge
  local max_seam = math.huge
  local span_start = math.huge
  local span_end = -math.huge

  for _, b in ipairs(before_list) do
    if b.p1 + min_pane > min_seam then
      min_seam = b.p1 + min_pane
    end
    if b.p1 < span_start then
      span_start = b.p1
    end
  end
  for _, a in ipairs(after_list) do
    local lim = a.p2 - eff_gap - min_pane
    if lim < max_seam then
      max_seam = lim
    end
    if a.p2 > span_end then
      span_end = a.p2
    end
  end

  if min_seam > max_seam then
    return nil
  end

  local cross_start, cross_end = current_cross_span()
  return {
    axis = axis,
    edge = edge,
    driver_addr = driver_addr,
    driver_side = driver_side,
    seam = seam,
    gap = eff_gap,
    min_seam = min_seam,
    max_seam = max_seam,
    span_start = span_start,
    span_end = span_end,
    cross_start = cross_start,
    cross_end = cross_end,
    before_list = before_list,
    after_list = after_list,
  }
end

local function clamp_percentage(num, denom)
  if denom <= 0 then
    return 50, 50
  end
  local pct1 = math.max(1, math.min(99, math.floor((num / denom) * 100 + 0.5)))
  return pct1, 100 - pct1
end

local function rect_for_span(axis, p1, p2, c1, c2)
  if axis == "x" then
    return { x = p1, y = c1, w = p2 - p1, h = c2 - c1 }
  end
  return { x = c1, y = p1, w = c2 - c1, h = p2 - p1 }
end

function M.compute_seam_rects(group, new_seam)
  if type(group) ~= "table" then
    return nil
  end
  local seam = math.max(group.min_seam, math.min(group.max_seam, math.floor((tonumber(new_seam) or group.seam) + 0.5)))
  local placements = {}

  for _, b in ipairs(group.before_list or {}) do
    placements[#placements + 1] = {
      addr = b.addr,
      rect = rect_for_span(group.axis, b.p1, seam, b.c1, b.c2),
      border = b.border,
      titlebar = b.titlebar,
      side = "before",
      is_driver = b.addr == group.driver_addr,
    }
  end
  for _, a in ipairs(group.after_list or {}) do
    placements[#placements + 1] = {
      addr = a.addr,
      rect = rect_for_span(group.axis, seam + group.gap, a.p2, a.c1, a.c2),
      border = a.border,
      titlebar = a.titlebar,
      side = "after",
      is_driver = a.addr == group.driver_addr,
    }
  end

  local div_gap = math.max(1, group.gap)
  local divider_rect = (group.axis == "x")
    and { x = seam, y = group.cross_start, w = div_gap, h = math.max(1, group.cross_end - group.cross_start) }
    or { x = group.cross_start, y = seam, w = math.max(1, group.cross_end - group.cross_start), h = div_gap }

  local avail = (group.span_end - group.span_start) - group.gap
  local pct1, pct2 = clamp_percentage(seam - group.span_start, avail)

  return {
    seam = seam,
    placements = placements,
    divider_rect = divider_rect,
    pct1 = pct1,
    pct2 = pct2,
  }
end

local function pick_preset_seam(span_start, span_end, gap, cur_seam, min_seam, max_seam, direction, presets)
  local list = presets or DEFAULT_SPLIT_PRESETS
  local total = (span_end - span_start) + gap
  if total <= 0 or (direction ~= -1 and direction ~= 1) then
    return nil
  end
  local cur_r = (cur_seam + gap - span_start) / total
  local eps = 0.025

  if direction > 0 then
    for i = 1, #list do
      local p = list[i]
      if p > cur_r + eps then
        local cand = span_start + math.floor(p * total + 0.5) - gap
        if cand >= min_seam and cand <= max_seam then
          return cand
        end
      end
    end
  else
    for i = #list, 1, -1 do
      local p = list[i]
      if p < cur_r - eps then
        local cand = span_start + math.floor(p * total + 0.5) - gap
        if cand >= min_seam and cand <= max_seam then
          return cand
        end
      end
    end
  end
  return nil
end

function M.next_snap_split_seam(group, direction, presets)
  if type(group) ~= "table" then
    return nil
  end
  return pick_preset_seam(
    group.span_start,
    group.span_end,
    group.gap,
    group.seam,
    group.min_seam,
    group.max_seam,
    direction,
    presets
  )
end

function M.compute_solo_snap_resize(win_outer, area, direction, axis, presets)
  if not win_outer or not area or (axis ~= "x" and axis ~= "y") then
    return nil
  end
  local min_pane = (axis == "x") and 240 or 180
  local a_start = (axis == "x") and area.x or area.y
  local a_len = (axis == "x") and area.w or area.h
  local a_end = a_start + a_len
  local gap = tonumber(area.gap) or 8
  local p1, p2, c1, c2 = project_rect(win_outer, axis)

  if (p2 - p1) >= a_len - 32 then
    return nil
  end

  local touches_start = math.abs(p1 - a_start) <= 10
  local touches_end = math.abs(p2 - a_end) <= 10
  if touches_start == touches_end then
    return nil
  end

  local cur_seam = touches_start and p2 or (p1 - gap)
  local new_seam = pick_preset_seam(
    a_start,
    a_end,
    gap,
    cur_seam,
    a_start + min_pane,
    a_end - gap - min_pane,
    direction,
    presets
  )
  if not new_seam then
    return nil
  end

  local rect = touches_start
    and rect_for_span(axis, a_start, new_seam, c1, c2)
    or rect_for_span(axis, new_seam + gap, a_end, c1, c2)

  local div_gap = math.max(1, gap)
  local divider_rect = (axis == "x")
    and { x = new_seam, y = c1, w = div_gap, h = math.max(1, c2 - c1) }
    or { x = c1, y = new_seam, w = math.max(1, c2 - c1), h = div_gap }

  local pct1, pct2 = clamp_percentage(new_seam - a_start, a_len - gap)
  return {
    rect = rect,
    divider_rect = divider_rect,
    pct1 = pct1,
    pct2 = pct2,
  }
end

function M.resolve_keyboard_snap_resize(descriptors, driver_addr, area, gap_in, direction, axis, presets)
  if type(descriptors) ~= "table" or not driver_addr or driver_addr == "" or not area then
    return nil
  end
  if direction ~= -1 and direction ~= 1 then
    return nil
  end
  axis = (axis == "y") and "y" or "x"

  local edges = (axis == "x")
    and ((direction > 0) and { "right", "left" } or { "left", "right" })
    or ((direction > 0) and { "bottom", "top" } or { "top", "bottom" })

  local found_seam = false
  for _, edge in ipairs(edges) do
    local g = M.find_seam_group(descriptors, driver_addr, edge, gap_in, area)
    if g then
      found_seam = true
      local next_seam = M.next_snap_split_seam(g, direction, presets)
      if next_seam then
        local res = M.compute_seam_rects(g, next_seam)
        if res then
          return {
            kind = "seam",
            axis = g.axis,
            placements = res.placements,
            divider_rect = res.divider_rect,
            pct1 = res.pct1,
            pct2 = res.pct2,
          }
        end
      end
    end
  end

  if found_seam then
    return nil
  end

  local driver = nil
  for _, d in ipairs(descriptors) do
    if d and d.addr == driver_addr then
      driver = d
      break
    end
  end
  if not driver or not driver.outer then
    return nil
  end

  local solo = M.compute_solo_snap_resize(driver.outer, area, direction, axis, presets)
  if not solo then
    return nil
  end
  return {
    kind = "solo",
    axis = axis,
    placements = {
      {
        addr = driver.addr,
        rect = solo.rect,
        border = driver.border,
        titlebar = driver.titlebar,
        side = "solo",
        is_driver = true,
      },
    },
    divider_rect = solo.divider_rect,
    pct1 = solo.pct1,
    pct2 = solo.pct2,
  }
end

return M
