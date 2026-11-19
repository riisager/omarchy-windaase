-- Pure in-process Windows-style Show Desktop toggle (Super+D).
-- Minimizes all non-pinned windows on the active workspace, or restores them
-- without animation and strips transient minimize tags cleanly.

local M = {}

local function has_tag(window, target)
  for _, tag in ipairs(window.tags or {}) do
    if tag == target then
      return true
    end
  end
  return false
end

local function strip_transient_tags(window)
  for _, tag in ipairs(window.tags or {}) do
    if tag:match("^omarchy%-minimized%-from%-%d+$") or tag:match("^omarchy%-showdesktop%-%d+$") then
      hl.dispatch(hl.dsp.window.tag({ tag = "-" .. tag, window = window }))
    end
  end
end

function M.toggle()
  local ws = hl.get_active_workspace()
  if not ws or not ws.id or ws.id < 1 then
    return
  end

  local ws_str = tostring(ws.id)
  local show_tag = "omarchy-showdesktop-" .. ws_str
  local min_tag = "omarchy-minimized-from-" .. ws_str

  local open_windows = {}
  for _, w in ipairs(hl.get_workspace_windows(ws_str)) do
    if (w.mapped ~= false) and not w.pinned then
      table.insert(open_windows, w)
    end
  end

  if #open_windows > 0 then
    for _, w in ipairs(open_windows) do
      strip_transient_tags(w)
      hl.dispatch(hl.dsp.window.tag({ tag = "+" .. min_tag, window = w }))
      hl.dispatch(hl.dsp.window.tag({ tag = "+" .. show_tag, window = w }))
      hl.dispatch(hl.dsp.window.move({ workspace = "special:minimized", follow = false, window = w }))
    end
    hl.dispatch(hl.dsp.focus({ workspace = ws_str }))
    return
  end

  local minimized = hl.get_workspace_windows("special:minimized")
  local to_restore = {}
  for _, w in ipairs(minimized) do
    if has_tag(w, show_tag) then
      table.insert(to_restore, w)
    end
  end
  if #to_restore == 0 then
    for _, w in ipairs(minimized) do
      if has_tag(w, min_tag) then
        table.insert(to_restore, w)
      end
    end
  end

  if #to_restore == 0 then
    return
  end

  for _, w in ipairs(to_restore) do
    hl.dispatch(hl.dsp.window.set_prop({ prop = "no_anim", value = "1", window = w }))
    strip_transient_tags(w)
    hl.dispatch(hl.dsp.window.move({ workspace = ws_str, window = w }))
  end

  hl.timer(function()
    for _, w in ipairs(to_restore) do
      pcall(hl.dispatch, hl.dsp.window.set_prop({ prop = "no_anim", value = "unset", window = w }))
    end
  end, { type = "oneshot", timeout = 400 })
end

return M
