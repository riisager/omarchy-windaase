-- Shared geometry, monitor work-area math, frame insets, and layouts.json loader
-- for Omarchy-windaase. Pure math helpers run standalone under plain Lua for tests.

local M = {}

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
        }
      end
    end
  end

  return FALLBACK_LAYOUTS
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

return M
