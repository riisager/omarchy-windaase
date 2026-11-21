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
    if tag:match("^omarchy%-minimized%-from%-%d+$")
      or tag:match("^omarchy%-showdesktop%-%d+$")
      or tag:match("^omarchy%-minimize%-others%-%d+$") then
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

function M.toggle_minimize_others()
  local active = hl.get_active_window()
  if not active or not active.floating then
    return false
  end

  local ws = (active.workspace and active.workspace.id and active.workspace) or hl.get_active_workspace()
  local ws_id = ws and tonumber(ws.id) or -1
  if ws_id < 1 then
    return false
  end

  local ws_str = tostring(ws_id)
  local min_tag = "omarchy-minimized-from-" .. ws_str
  local others_tag = "omarchy-minimize-others-" .. ws_str

  local others = {}
  for _, w in ipairs(hl.get_workspace_windows(ws_str)) do
    if w.address ~= active.address and (w.mapped ~= false) and not w.pinned then
      table.insert(others, w)
    end
  end

  if #others > 0 then
    for _, w in ipairs(others) do
      strip_transient_tags(w)
      hl.dispatch(hl.dsp.window.tag({ tag = "+" .. min_tag, window = w }))
      hl.dispatch(hl.dsp.window.tag({ tag = "+" .. others_tag, window = w }))
      hl.dispatch(hl.dsp.window.move({ workspace = "special:minimized", follow = false, window = w }))
    end
    hl.dispatch(hl.dsp.focus({ window = active }))
    hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", window = active }))
    return true
  end

  local to_restore = {}
  for _, w in ipairs(hl.get_workspace_windows("special:minimized")) do
    if has_tag(w, others_tag) then
      table.insert(to_restore, w)
    end
  end

  if #to_restore == 0 then
    return false
  end

  for _, w in ipairs(to_restore) do
    hl.dispatch(hl.dsp.window.set_prop({ prop = "no_anim", value = "1", window = w }))
    strip_transient_tags(w)
    hl.dispatch(hl.dsp.window.move({ workspace = ws_str, window = w }))
  end

  hl.dispatch(hl.dsp.focus({ window = active }))
  hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", window = active }))

  hl.timer(function()
    for _, w in ipairs(to_restore) do
      pcall(hl.dispatch, hl.dsp.window.set_prop({ prop = "no_anim", value = "unset", window = w }))
    end
  end, { type = "oneshot", timeout = 400 })
  return true
end

return M
