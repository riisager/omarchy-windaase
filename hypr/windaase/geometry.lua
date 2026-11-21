-- Shared geometry, monitor work-area math, frame insets, and layouts.json loader
-- for Omarchy-windaase. Pure math helpers run standalone under plain Lua for tests.

local M = {}

local FALLBACK_ULTRAWIDE_LAYOUT = {
  { rx = 0, ry = 0, rw = 0.25, rh = 1.0, max = false },
  { rx = 0.25, ry = 0, rw = 0.5, rh = 1.0, max = false },
  { rx = 0.75, ry = 0, rw = 0.25, rh = 1.0, max = false },
}

local FALLBACK_LAYOUTS = {
  cardW = 84,
  cardH = 52,
  cardGap = 10,
  padX = 14,
  padY = 12,
  topMargin = 10,
  layouts = {
    { { rx = 0, ry = 0, rw = 0.5, rh = 1.0, max = false }, { rx = 0.5, ry = 0, rw = 0.5, rh = 1.0, max = false } },
    { { rx = 0, ry = 0, rw = 0.65, rh = 1.0, max = false }, { rx = 0.65, ry = 0, rw = 0.35, rh = 1.0, max = false } },
    { { rx = 0, ry = 0, rw = 0.5, rh = 1.0, max = false }, { rx = 0.5, ry = 0, rw = 0.5, rh = 0.5, max = false }, { rx = 0.5, ry = 0.5, rw = 0.5, rh = 0.5, max = false } },
    { { rx = 0, ry = 0, rw = 1 / 3, rh = 1.0, max = false }, { rx = 1 / 3, ry = 0, rw = 1 / 3, rh = 1.0, max = false }, { rx = 2 / 3, ry = 0, rw = 1 / 3, rh = 1.0, max = false } },
    { { rx = 0, ry = 0, rw = 0.5, rh = 0.5, max = false }, { rx = 0.5, ry = 0, rw = 0.5, rh = 0.5, max = false }, { rx = 0, ry = 0.5, rw = 0.5, rh = 0.5, max = false }, { rx = 0.5, ry = 0.5, rw = 0.5, rh = 0.5, max = false } },
    { { rx = 0, ry = 0, rw = 1.0, rh = 1.0, max = true } },
  },
  ultrawideLayout = FALLBACK_ULTRAWIDE_LAYOUT,
}

-- Minimal self-contained JSON decoder (handles objects, arrays, strings, numbers, bools, null).
function M.decode_json(str)
  if type(str) ~= "string" then
    return nil, "expected string"
  end

  local pos = 1
  local len = #str

  local function skip_ws()
    local next_pos = str:find("[^ \t\r\n]", pos)
    pos = next_pos or (len + 1)
  end

  local parse_value

  local function parse_string()
    pos = pos + 1
    local out = {}
    while pos <= len do
      local ch = str:sub(pos, pos)
      if ch == '"' then
        pos = pos + 1
        return table.concat(out)
      elseif ch == "\\" then
        local esc = str:sub(pos + 1, pos + 1)
        if esc == "" then
          return nil, "unterminated escape"
        elseif esc == '"' or esc == "\\" or esc == "/" then
          table.insert(out, esc)
          pos = pos + 2
        elseif esc == "b" then
          table.insert(out, "\b")
          pos = pos + 2
        elseif esc == "f" then
          table.insert(out, "\f")
          pos = pos + 2
        elseif esc == "n" then
          table.insert(out, "\n")
          pos = pos + 2
        elseif esc == "r" then
          table.insert(out, "\r")
          pos = pos + 2
        elseif esc == "t" then
          table.insert(out, "\t")
          pos = pos + 2
        elseif esc == "u" then
          local hex = str:sub(pos + 2, pos + 5)
          if #hex < 4 or not hex:match("^[0-9a-fA-F]+$") then
            return nil, "invalid unicode escape"
          end
          local code = tonumber(hex, 16)
          if code < 128 then
            table.insert(out, string.char(code))
          elseif code < 2048 then
            table.insert(out, string.char(192 + math.floor(code / 64), 128 + (code % 64)))
          else
            table.insert(out, string.char(224 + math.floor(code / 4096), 128 + (math.floor(code / 64) % 64), 128 + (code % 64)))
          end
          pos = pos + 6
        else
          return nil, "invalid escape: " .. esc
        end
      else
        table.insert(out, ch)
        pos = pos + 1
      end
    end
    return nil, "unterminated string"
  end

  local function parse_number()
    local s, e = str:find("^-?%d+", pos)
    if not s then
      return nil, "invalid number at " .. pos
    end
    local _, fe = str:find("^%.%d+", e + 1)
    if fe then e = fe end
    local _, ee = str:find("^[eE][+-]?%d+", e + 1)
    if ee then e = ee end
    local num = tonumber(str:sub(s, e))
    if not num then
      return nil, "invalid number syntax at " .. pos
    end
    pos = e + 1
    return num
  end

  local function parse_array()
    pos = pos + 1
    skip_ws()
    local arr = {}
    if str:sub(pos, pos) == "]" then
      pos = pos + 1
      return arr
    end
    local idx = 0
    while pos <= len do
      local val, err = parse_value()
      if err then
        return nil, err
      end
      idx = idx + 1
      arr[idx] = val
      skip_ws()
      local ch = str:sub(pos, pos)
      if ch == "]" then
        pos = pos + 1
        return arr
      elseif ch == "," then
        pos = pos + 1
        skip_ws()
      else
        return nil, "expected ',' or ']' at " .. pos
      end
    end
    return nil, "unterminated array"
  end

  local function parse_object()
    pos = pos + 1
    skip_ws()
    local obj = {}
    if str:sub(pos, pos) == "}" then
      pos = pos + 1
      return obj
    end
    while pos <= len do
      if str:sub(pos, pos) ~= '"' then
        return nil, "expected string key at " .. pos
      end
      local key, kerr = parse_string()
      if kerr then
        return nil, kerr
      end
      skip_ws()
      if str:sub(pos, pos) ~= ":" then
        return nil, "expected ':' at " .. pos
      end
      pos = pos + 1
      skip_ws()
      local val, verr = parse_value()
      if verr then
        return nil, verr
      end
      obj[key] = val
      skip_ws()
      local ch = str:sub(pos, pos)
      if ch == "}" then
        pos = pos + 1
        return obj
      elseif ch == "," then
        pos = pos + 1
        skip_ws()
      else
        return nil, "expected ',' or '}' at " .. pos
      end
    end
    return nil, "unterminated object"
  end

  parse_value = function()
    skip_ws()
    if pos > len then
      return nil, "unexpected end of JSON"
    end
    local ch = str:sub(pos, pos)
    if ch == '"' then
      return parse_string()
    elseif ch == "{" then
      return parse_object()
    elseif ch == "[" then
      return parse_array()
    elseif ch == "t" and str:sub(pos, pos + 3) == "true" then
      pos = pos + 4
      return true
    elseif ch == "f" and str:sub(pos, pos + 4) == "false" then
      pos = pos + 5
      return false
    elseif ch == "n" and str:sub(pos, pos + 3) == "null" then
      pos = pos + 4
      return nil
    elseif ch == "-" or (ch >= "0" and ch <= "9") then
      return parse_number()
    end
    return nil, "unexpected token at " .. pos
  end

  local res, err = parse_value()
  if err then
    return nil, err
  end
  skip_ws()
  if pos <= len then
    return nil, "trailing characters at " .. pos
  end
  return res
end

function M.load_layouts_config(search_paths)
  local home = os.getenv("HOME") or ""
  local candidates = search_paths or {
    home .. "/.config/omarchy/plugins/riisager.windaase/layouts.json",
    home .. "/.config/hypr/windaase/layouts.json",
  }

  for _, path in ipairs(candidates) do
    local f = io.open(path, "r")
    if f then
      local raw = f:read("*a")
      f:close()
      local parsed = M.decode_json(raw)
      if type(parsed) == "table" and type(parsed.layouts) == "table" and #parsed.layouts > 0 then
        return {
          cardW = tonumber(parsed.cardW) or FALLBACK_LAYOUTS.cardW,
          cardH = tonumber(parsed.cardH) or FALLBACK_LAYOUTS.cardH,
          cardGap = tonumber(parsed.cardGap) or FALLBACK_LAYOUTS.cardGap,
          padX = tonumber(parsed.padX) or FALLBACK_LAYOUTS.padX,
          padY = tonumber(parsed.padY) or FALLBACK_LAYOUTS.padY,
          topMargin = tonumber(parsed.topMargin) or FALLBACK_LAYOUTS.topMargin,
          layouts = parsed.layouts,
          ultrawideLayout = (type(parsed.ultrawideLayout) == "table" and #parsed.ultrawideLayout > 0)
            and parsed.ultrawideLayout
            or FALLBACK_ULTRAWIDE_LAYOUT,
        }
      end
    end
  end

  return FALLBACK_LAYOUTS
end

function M.resolve_layouts_config(cfg, include_ultrawide)
  local base = cfg or FALLBACK_LAYOUTS
  local resolved_layouts = {}
  for _, card in ipairs(base.layouts or FALLBACK_LAYOUTS.layouts) do
    resolved_layouts[#resolved_layouts + 1] = card
  end
  if include_ultrawide == true then
    local uw = base.ultrawideLayout or FALLBACK_ULTRAWIDE_LAYOUT
    if type(uw) == "table" and #uw > 0 then
      resolved_layouts[#resolved_layouts + 1] = uw
    end
  end
  return {
    cardW = base.cardW or FALLBACK_LAYOUTS.cardW,
    cardH = base.cardH or FALLBACK_LAYOUTS.cardH,
    cardGap = base.cardGap or FALLBACK_LAYOUTS.cardGap,
    padX = base.padX or FALLBACK_LAYOUTS.padX,
    padY = base.padY or FALLBACK_LAYOUTS.padY,
    topMargin = base.topMargin or FALLBACK_LAYOUTS.topMargin,
    layouts = resolved_layouts,
    ultrawideLayout = base.ultrawideLayout or FALLBACK_ULTRAWIDE_LAYOUT,
  }
end

local function round6(n)
  return math.floor(n * 1000000 + 0.5) / 1000000
end

function M.complementary_zone(z)
  if type(z) ~= "table" or z.max == true then
    return nil
  end
  local rx = tonumber(z.rx) or 0
  local ry = tonumber(z.ry) or 0
  local rw = tonumber(z.rw) or 0
  local rh = tonumber(z.rh) or 0
  if math.abs(ry) > 0.02 or rh < 0.98 then
    return nil
  end
  if rw <= 0.15 or rw >= 0.85 then
    return nil
  end
  if math.abs(rx) <= 0.02 then
    return { rx = round6(rw), ry = 0, rw = round6(1 - rw), rh = 1.0, max = false }
  end
  if math.abs((rx + rw) - 1.0) <= 0.02 then
    return { rx = 0, ry = 0, rw = round6(rx), rh = 1.0, max = false }
  end
  return nil
end

function M.json_escape(s)
  return tostring(s or ""):gsub("\\", "\\\\"):gsub('"', '\\"')
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
  for _, m in ipairs(hl.get_monitors()) do
    local w, h = M.monitor_logical_size(m)
    local mx, my = m.x or 0, m.y or 0
    if cx >= mx and cx < mx + w and cy >= my and cy < my + h then
      return m, w, h
    end
  end
  local am = hl.get_active_monitor()
  if am then
    local w, h = M.monitor_logical_size(am)
    return am, w, h
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

function M.hit_test_snap_layouts(lx, ly, mw, cfg)
  local c = cfg or FALLBACK_LAYOUTS
  local layouts = c.layouts
  local cols = #layouts
  local card_w = c.cardW
  local card_h = c.cardH
  local card_gap = c.cardGap
  local pad_x = c.padX
  local pad_y = c.padY
  local top_margin = c.topMargin

  local content_w = cols * card_w + math.max(0, cols - 1) * card_gap
  local pill_w = content_w + pad_x * 2 + 2
  local pill_h = card_h + pad_y * 2 + 2
  local pill_x = math.floor((mw - pill_w) / 2)
  local pill_y = top_margin
  local start_x = pill_x + 1 + pad_x
  local start_y = pill_y + 1 + pad_y

  for ci, card in ipairs(layouts) do
    local cx = start_x + (ci - 1) * (card_w + card_gap)
    local cy = start_y
    if lx >= cx and lx <= cx + card_w and ly >= cy and ly <= cy + card_h then
      for zi, z in ipairs(card) do
        local tx = cx + math.floor(z.rx * card_w + 0.5)
        local ty = cy + math.floor(z.ry * card_h + 0.5)
        local tw = math.floor(z.rw * card_w + 0.5)
        local th = math.floor(z.rh * card_h + 0.5)
        if lx >= tx and lx <= tx + tw and ly >= ty and ly <= ty + th then
          return ci - 1, zi - 1, z, pill_x, pill_y, pill_w, pill_h
        end
      end
    end
  end

  return -1, -1, nil, pill_x, pill_y, pill_w, pill_h
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

function M.get_window_frame_insets(window)
  local border = 2
  if hl and hl.get_config then
    local ok_b, b = pcall(hl.get_config, "general.border_size")
    if ok_b and tonumber(b) then
      border = tonumber(b)
    end
  end

  local titlebar = 0
  if window and window.floating and M.has_floating_workspace_tag(window) then
    local bar_h = 30
    if hl and hl.get_config then
      local ok_h, h = pcall(hl.get_config, "plugin.hyprbars.bar_height")
      if not ok_h or not tonumber(h) then
        ok_h, h = pcall(hl.get_config, "plugin:hyprbars:bar_height")
      end
      if ok_h and tonumber(h) then
        bar_h = tonumber(h)
      end
    end
    titlebar = bar_h
  end

  return border, titlebar
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

local DEFAULT_SPLIT_PRESETS = { 0.25, 0.35, 0.50, 0.65, 0.75 }

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

local NAMED_ZONE_SPECS = {
  left = { rx = 0, ry = 0, rw = 0.5, rh = 1.0, max = false },
  right = { rx = 0.5, ry = 0, rw = 0.5, rh = 1.0, max = false },
  top = { rx = 0, ry = 0, rw = 1.0, rh = 0.5, max = false },
  bottom = { rx = 0, ry = 0.5, rw = 1.0, rh = 0.5, max = false },
  ["top-left"] = { rx = 0, ry = 0, rw = 0.5, rh = 0.5, max = false },
  ["top-right"] = { rx = 0.5, ry = 0, rw = 0.5, rh = 0.5, max = false },
  ["bottom-left"] = { rx = 0, ry = 0.5, rw = 0.5, rh = 0.5, max = false },
  ["bottom-right"] = { rx = 0.5, ry = 0.5, rw = 0.5, rh = 0.5, max = false },
  maximize = { rx = 0, ry = 0, rw = 1.0, rh = 1.0, max = true },
}

function M.named_zone_spec(zone_name)
  if type(zone_name) ~= "string" then
    return nil
  end
  local spec = NAMED_ZONE_SPECS[zone_name]
  if not spec then
    return nil
  end
  return {
    rx = spec.rx,
    ry = spec.ry,
    rw = spec.rw,
    rh = spec.rh,
    max = spec.max,
  }
end

local function is_object(v)
  local t = type(v)
  return t == "table" or t == "userdata"
end

function M.pick_adjacent_monitor(monitors, current_name, direction)
  if not is_object(monitors) or type(current_name) ~= "string" or current_name == "" then
    return nil
  end
  local active = {}
  for _, m in ipairs(monitors) do
    if is_object(m) and m.disabled ~= true and m.is_mirror ~= true and type(m.name) == "string" and m.name ~= "" then
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

local function clamp_num(val, lo, hi)
  if val < lo then
    return lo
  end
  if val > hi then
    return hi
  end
  return val
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

  local spec = (type(custom_zone) == "table" and custom_zone) or M.named_zone_spec(zone_name)
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

function M.order_alttab_windows(windows, active_addr)
  if not is_object(windows) then
    return {}
  end

  local open_list = {}
  local min_list = {}
  local active_low = type(active_addr) == "string" and active_addr:lower() or ""

  for _, w in ipairs(windows) do
    if is_object(w) and w.mapped ~= false and type(w.address) == "string" and w.address ~= "" then
      local ws = w.workspace
      local ws_id = (ws and tonumber(ws.id)) or -1
      local ws_name = (ws and tostring(ws.name or "")) or ""
      if ws_name == "special:minimized" then
        min_list[#min_list + 1] = w
      elseif ws_id >= 1 then
        open_list[#open_list + 1] = w
      end
    end
  end

  table.sort(open_list, function(a, b)
    local a_active = (active_low ~= "" and a.address:lower() == active_low) and 0 or 1
    local b_active = (active_low ~= "" and b.address:lower() == active_low) and 0 or 1
    if a_active ~= b_active then
      return a_active < b_active
    end
    local af = tonumber(a.focus_history_id) or 999999
    local bf = tonumber(b.focus_history_id) or 999999
    if af ~= bf then
      return af < bf
    end
    return a.address < b.address
  end)

  table.sort(min_list, function(a, b)
    local af = tonumber(a.focus_history_id) or 999999
    local bf = tonumber(b.focus_history_id) or 999999
    if af ~= bf then
      return af < bf
    end
    return a.address < b.address
  end)

  local ordered = {}
  for _, w in ipairs(open_list) do
    ordered[#ordered + 1] = w
  end
  for _, w in ipairs(min_list) do
    ordered[#ordered + 1] = w
  end
  return ordered
end

function M.step_index(current, count, delta)
  local n = tonumber(count) or 0
  if n <= 0 then
    return 0
  end
  local cur = tonumber(current) or 1
  local step = tonumber(delta) or 0
  return ((cur - 1 + step) % n) + 1
end

return M
