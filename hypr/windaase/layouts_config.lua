-- Snap Layouts JSON decoder, layouts.json loader, hit-testing, and named zone
-- definitions for Omarchy-windaase. Pure functions run standalone under plain Lua.

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

return M
