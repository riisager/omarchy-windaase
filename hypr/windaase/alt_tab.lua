-- Windows-style MRU Alt+Tab window switcher backend for Hyprland + Quickshell.
-- Holds focus order via Hyprland's window list and commits on Alt key release.

local layouts_config = require("hypr.windaase.layouts_config")
local runtime = require("hypr.windaase.runtime")
local show_desktop = require("hypr.windaase.show_desktop")

local M = {}

local function is_object(v)
  local t = type(v)
  return t == "table" or t == "userdata"
end

function M.order_windows(windows, active_addr)
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

local state_path = (os.getenv("XDG_RUNTIME_DIR") or os.getenv("XDG_CACHE_HOME") or ((os.getenv("HOME") or ".") .. "/.cache"))
  .. "/omarchy-windaase-alttab.json"

local session = nil
local commit_seq = 0
local transient_binds = {}
local release_binds = {}
local destroy_hook_registered = false
local active_hook_registered = false

local function bind_alive(kb)
  return kb ~= nil and tostring(kb) ~= "HL.Keybind(expired)"
end

local function write_state(tbl)
  if not runtime.is_live_compositor() then
    return
  end
  local payload
  if not tbl or not tbl.open then
    payload = '{"open":false}\n'
  else
    local encoded_addrs = {}
    for _, addr in ipairs(tbl.addrs or {}) do
      encoded_addrs[#encoded_addrs + 1] = '"' .. layouts_config.json_escape(addr) .. '"'
    end
    local sel0 = math.max(0, (tonumber(tbl.selected) or 1) - 1)
    payload = string.format(
      '{"open":true,"monitor":"%s","selected":%d,"addrs":[%s]}\n',
      layouts_config.json_escape(tbl.monitor or ""),
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

local TRANSIENT_KEYS = {
  { keys = "Escape", action = function() M.cancel() end },
  { keys = "LEFT", action = function() M.step(-1) end },
  { keys = "UP", action = function() M.step(-1) end },
  { keys = "RIGHT", action = function() M.step(1) end },
  { keys = "DOWN", action = function() M.step(1) end },
  { keys = "RETURN", action = function() M.commit() end },
}

local RELEASE_KEYS = { "Alt_L", "Alt_R" }
-- Transparent and non-consuming so Omarchy's ALT+Alt_R dictation hold/release keeps working.
local RELEASE_OPTS = { release = true, transparent = true, ignore_mods = true, non_consuming = true }

local function set_session_binds_enabled(enabled)
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

  for _, sym in ipairs(RELEASE_KEYS) do
    local kb = release_binds[sym]
    if enabled and not bind_alive(kb) then
      kb = hl.bind(sym, function() M.commit(true) end, RELEASE_OPTS)
      release_binds[sym] = kb
    end
    if bind_alive(kb) then
      kb:set_enabled(enabled)
    end
  end
end

function M.step(delta)
  delta = tonumber(delta) or 1
  commit_seq = commit_seq + 1
  if session and not read_state_open() then
    session = nil
    set_session_binds_enabled(false)
  end
  if not session then
    local active = hl.get_active_window()
    local active_addr = active and active.address or ""
    local ordered = M.order_windows(hl.get_windows(), active_addr)
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
    set_session_binds_enabled(true)
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

  session.selected = M.step_index(session.selected, #session.addrs, delta)
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
  commit_seq = commit_seq + 1
  set_session_binds_enabled(false)
  write_state({ open = false })
end

local function activate_addr(addr, monitor_name)
  if type(addr) ~= "string" or not addr:match("^0x[0-9a-fA-F]+$") then
    return false
  end

  local w = hl.get_window("address:" .. addr)
  if not w then
    return false
  end

  local ws = w.workspace
  local ws_name = ws and ws.name or ""
  if ws_name == "special:minimized" then
    local m = (monitor_name and monitor_name ~= "" and hl.get_monitor(monitor_name)) or hl.get_active_monitor()
    local target_ws = m and m.active_workspace and tonumber(m.active_workspace.id) or -1
    if target_ws < 1 then
      local aws = hl.get_active_workspace()
      target_ws = aws and tonumber(aws.id) or -1
    end
    if target_ws >= 1 then
      show_desktop.restore_windows({ w }, target_ws)
    end
  end

  hl.dispatch(hl.dsp.focus({ window = "address:" .. addr }))
  hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", window = "address:" .. addr }))
  return true
end

function M.commit(defer_focus)
  if not session then
    return false
  end
  local s = session
  session = nil
  commit_seq = commit_seq + 1
  set_session_binds_enabled(false)

  if not read_state_open() then
    return false
  end
  write_state({ open = false })

  local target_addr = s.addrs[s.selected]
  local target_mon = s.monitor
  if type(target_addr) ~= "string" or not target_addr:match("^0x[0-9a-fA-F]+$") then
    return false
  end

  if defer_focus then
    -- Defer focus past Alt key-release processing so the newly focused Wayland client does not receive a stuck Alt modifier.
    local seq = commit_seq
    runtime.timer(function()
      if seq ~= commit_seq or session ~= nil then
        return
      end
      activate_addr(target_addr, target_mon)
    end, { type = "oneshot", timeout = 10 })
    return true
  end

  return activate_addr(target_addr, target_mon)
end

-- Direct MRU window switch for non-held menu invocations (Super+K keybindings menu).
function M.menu_switch(delta)
  M.cancel()
  local active = hl.get_active_window()
  local active_addr = active and active.address or ""
  local ordered = M.order_windows(hl.get_windows(), active_addr)
  if #ordered == 0 then
    return false
  end
  local mon = hl.get_active_monitor() or (active and active.monitor)
  local mon_name = (mon and mon.name) or ""
  local idx = 1
  if #ordered >= 2 then
    idx = (tonumber(delta) or 1) < 0 and #ordered or 2
  end
  return activate_addr(ordered[idx].address, mon_name)
end

function M.commit_addr(addr)
  local monitor_name = session and session.monitor or ""
  session = nil
  commit_seq = commit_seq + 1
  set_session_binds_enabled(false)
  write_state({ open = false })

  return activate_addr(addr, monitor_name)
end

function M.setup(opts)
  session = nil
  commit_seq = commit_seq + 1
  set_session_binds_enabled(false)
  write_state({ open = false })

  if opts and opts.alt_tab == false then
    return
  end

  runtime.rebind_fn(
    "ALT + TAB",
    "Switch to next window",
    function() M.step(1) end,
    "alt_tab_menu_switch(1)",
    { repeating = true }
  )
  runtime.rebind_fn(
    "ALT + SHIFT + TAB",
    "Switch to previous window",
    function() M.step(-1) end,
    "alt_tab_menu_switch(-1)",
    { repeating = true }
  )

  if not runtime.is_live_compositor() then
    return
  end

  for _, sym in ipairs(RELEASE_KEYS) do
    if not bind_alive(release_binds[sym]) then
      release_binds[sym] = hl.bind(sym, function() M.commit(true) end, RELEASE_OPTS)
    end
    if bind_alive(release_binds[sym]) then
      release_binds[sym]:set_enabled(false)
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

  if not active_hook_registered then
    active_hook_registered = true
    local function cancel_if_open()
      if session then
        M.cancel()
      end
    end
    hl.on("window.active", cancel_if_open)
    hl.on("workspace.active", cancel_if_open)
    hl.on("monitor.added", cancel_if_open)
    hl.on("monitor.removed", cancel_if_open)
    hl.on("monitor.layout_changed", cancel_if_open)
  end
end

return M
