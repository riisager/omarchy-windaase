-- Windows-style MRU Alt+Tab window switcher backend for Hyprland + Quickshell.
-- Holds focus order via Hyprland's window list and commits on Alt key release.

local geometry = require("hypr.windaase.geometry")

local M = {}

local state_path = (os.getenv("XDG_RUNTIME_DIR") or os.getenv("XDG_CACHE_HOME") or ((os.getenv("HOME") or ".") .. "/.cache"))
  .. "/omarchy-windaase-alttab.json"

local session = nil
local transient_binds = {}
local release_binds = {}
local destroy_hook_registered = false

local function bind_alive(kb)
  return kb ~= nil and tostring(kb) ~= "HL.Keybind(expired)"
end

local function write_state(tbl)
  local payload
  if not tbl or not tbl.open then
    payload = '{"open":false}\n'
  else
    local encoded_addrs = {}
    for _, addr in ipairs(tbl.addrs or {}) do
      encoded_addrs[#encoded_addrs + 1] = '"' .. geometry.json_escape(addr) .. '"'
    end
    local sel0 = math.max(0, (tonumber(tbl.selected) or 1) - 1)
    payload = string.format(
      '{"open":true,"monitor":"%s","selected":%d,"addrs":[%s]}\n',
      geometry.json_escape(tbl.monitor or ""),
      sel0,
      table.concat(encoded_addrs, ",")
    )
  end

  local tmp = state_path .. ".lua.tmp"
  local f = io.open(tmp, "w")
  if f then
    f:write(payload)
    f:close()
    os.rename(tmp, state_path)
  end
end

local function read_state_open()
  local f = io.open(state_path, "r")
  if not f then
    return false
  end
  local raw = f:read("*a") or ""
  f:close()
  return raw:find('"open":true') ~= nil
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

local TRANSIENT_KEYS = {
  { keys = "Escape", action = function() M.cancel() end },
  { keys = "LEFT", action = function() M.step(-1) end },
  { keys = "UP", action = function() M.step(-1) end },
  { keys = "RIGHT", action = function() M.step(1) end },
  { keys = "DOWN", action = function() M.step(1) end },
  { keys = "RETURN", action = function() M.commit() end },
}

local function set_transient_binds_enabled(enabled)
  for _, spec in ipairs(TRANSIENT_KEYS) do
    local kb = transient_binds[spec.keys]
    if enabled and not bind_alive(kb) then
      kb = hl.bind(spec.keys, spec.action, { ignore_mods = true })
      transient_binds[spec.keys] = kb
    end
    if bind_alive(kb) then
      kb:set_enabled(enabled)
    end
  end
end

function M.step(delta)
  delta = tonumber(delta) or 1
  if not session then
    local active = hl.get_active_window()
    local active_addr = active and active.address or ""
    local ordered = geometry.order_alttab_windows(hl.get_windows(), active_addr)
    if #ordered == 0 then
      return false
    end

    local mon = hl.get_active_monitor() or (active and active.monitor)
    local mon_name = (mon and mon.name) or ""
    local addrs = {}
    local by_addr = {}
    for _, w in ipairs(ordered) do
      addrs[#addrs + 1] = w.address
      by_addr[w.address] = true
    end

    local initial_sel = 1
    if #addrs >= 2 then
      initial_sel = (delta < 0) and #addrs or 2
    end

    session = {
      monitor = mon_name,
      addrs = addrs,
      by_addr = by_addr,
      selected = initial_sel,
    }
    set_transient_binds_enabled(true)
    write_state({
      open = true,
      monitor = session.monitor,
      selected = session.selected,
      addrs = session.addrs,
    })
    return true
  end

  if #session.addrs == 0 then
    M.cancel()
    return false
  end

  session.selected = geometry.step_index(session.selected, #session.addrs, delta)
  write_state({
    open = true,
    monitor = session.monitor,
    selected = session.selected,
    addrs = session.addrs,
  })
  return true
end

function M.cancel()
  session = nil
  set_transient_binds_enabled(false)
  write_state({ open = false })
end

function M.commit()
  if not session then
    return false
  end
  local s = session
  session = nil
  set_transient_binds_enabled(false)

  if not read_state_open() then
    return false
  end
  write_state({ open = false })

  local addr = s.addrs[s.selected]
  if not addr or addr == "" then
    return false
  end

  local w = hl.get_window("address:" .. addr)
  if not w then
    return false
  end

  local ws = w.workspace
  local ws_name = ws and ws.name or ""
  if ws_name == "special:minimized" then
    local m = (s.monitor ~= "" and hl.get_monitor(s.monitor)) or hl.get_active_monitor()
    local target_ws = m and m.active_workspace and tonumber(m.active_workspace.id) or -1
    if target_ws < 1 then
      local aws = hl.get_active_workspace()
      target_ws = aws and tonumber(aws.id) or -1
    end
    if target_ws >= 1 then
      hl.dispatch(hl.dsp.window.set_prop({ prop = "no_anim", value = "1", window = "address:" .. addr }))
      strip_transient_tags(w)
      hl.dispatch(hl.dsp.window.move({ workspace = tostring(target_ws), window = "address:" .. addr }))
      hl.timer(function()
        pcall(hl.dispatch, hl.dsp.window.set_prop({ prop = "no_anim", value = "unset", window = "address:" .. addr }))
      end, { type = "oneshot", timeout = 400 })
    end
  end

  hl.dispatch(hl.dsp.focus({ window = "address:" .. addr }))
  hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", window = "address:" .. addr }))
  return true
end

function M.setup(opts)
  session = nil
  set_transient_binds_enabled(false)
  write_state({ open = false })

  if opts and opts.alt_tab == false then
    for _, kb in pairs(release_binds) do
      if bind_alive(kb) then
        kb:set_enabled(false)
      end
    end
    return
  end

  o.rebind("ALT + TAB", "Switch to next window", function() M.step(1) end, { repeating = true })
  o.rebind("ALT + SHIFT + TAB", "Switch to previous window", function() M.step(-1) end, { repeating = true })

  local release_opts = { release = true, transparent = true, ignore_mods = true, non_consuming = true }
  for _, sym in ipairs({ "Alt_L", "Alt_R" }) do
    if not bind_alive(release_binds[sym]) then
      release_binds[sym] = hl.bind(sym, function() M.commit() end, release_opts)
    end
    if bind_alive(release_binds[sym]) then
      release_binds[sym]:set_enabled(true)
    end
  end

  if not destroy_hook_registered then
    destroy_hook_registered = true
    hl.on("window.destroy", function(window)
      if not session or not window or not window.address then
        return
      end
      if not session.by_addr[window.address] then
        return
      end
      session.by_addr[window.address] = nil
      local next_addrs = {}
      for _, a in ipairs(session.addrs) do
        if a ~= window.address then
          next_addrs[#next_addrs + 1] = a
        end
      end
      if #next_addrs == 0 then
        M.cancel()
        return
      end
      session.addrs = next_addrs
      if session.selected > #next_addrs then
        session.selected = #next_addrs
      elseif session.selected < 1 then
        session.selected = 1
      end
      write_state({
        open = true,
        monitor = session.monitor,
        selected = session.selected,
        addrs = session.addrs,
      })
    end)
  end
end

return M
