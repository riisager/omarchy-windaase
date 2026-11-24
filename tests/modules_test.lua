-- Behavioral unit tests for stateful hypr.windaase Lua modules under a standalone hl/o mock.

local script_dir = debug.getinfo(1, "S").source:match("@(.*/)") or "./"
local repo_root = script_dir .. "../"
package.path = repo_root .. "?.lua;" .. package.path

local function make_harness()
  local state = {
    config = {
      ["general.border_size"] = 2,
      ["plugin.hyprbars.bar_height"] = 30,
      ["input.follow_mouse"] = 0,
    },
    get_config_calls = {},
    dispatches = {},
    exec_cmds = {},
    hooks = {},
    timers = {},
    binds = {},
    unbinds = {},
    rebinds = {},
    workspace_modes = {},
    windows = {},
    workspaces = { { id = 1, name = "1" } },
    monitors = { { id = 0, name = "DP-1", x = 0, y = 0, width = 1920, height = 1200, scale = 1, transform = 0 } },
    active_window = nil,
    active_workspace = { id = 1, name = "1" },
    active_monitor = nil,
  }
  state.active_monitor = state.monitors[1]

  local function record_dsp(kind, tbl)
    local copy = { _kind = kind }
    for k, v in pairs(tbl or {}) do
      copy[k] = v
    end
    return copy
  end

  local hl_mock = {
    dsp = {
      window = {
        tag = function(t) return record_dsp("window.tag", t) end,
        set_prop = function(t) return record_dsp("window.set_prop", t) end,
        move = function(t) return record_dsp("window.move", t) end,
        alter_zorder = function(t) return record_dsp("window.alter_zorder", t) end,
        float = function(t) return record_dsp("window.float", t) end,
        pin = function(t) return record_dsp("window.pin", t) end,
        resize = function(t) return record_dsp("window.resize", t) end,
        center = function(t) return record_dsp("window.center", t) end,
        fullscreen = function(t) return record_dsp("window.fullscreen", t) end,
        close = function(t) return record_dsp("window.close", t) end,
      },
      focus = function(t) return record_dsp("focus", t) end,
    },
    get_config = function(key)
      state.get_config_calls[key] = (state.get_config_calls[key] or 0) + 1
      return state.config[key]
    end,
    config = function(tbl)
      if type(tbl) == "table" and type(tbl.input) == "table" and tbl.input.follow_mouse ~= nil then
        state.config["input.follow_mouse"] = tbl.input.follow_mouse
      end
    end,
    dispatch = function(cmd)
      state.dispatches[#state.dispatches + 1] = cmd
    end,
    exec_cmd = function(cmd)
      state.exec_cmds[#state.exec_cmds + 1] = cmd
    end,
    on = function(ev, fn)
      state.hooks[ev] = state.hooks[ev] or {}
      state.hooks[ev][#state.hooks[ev] + 1] = fn
    end,
    timer = function(fn, opts)
      state.timers[#state.timers + 1] = { fn = fn, opts = opts }
    end,
    bind = function(keys, fn, opts)
      local kb = { keys = keys, fn = fn, opts = opts, enabled = true }
      function kb:set_enabled(val) self.enabled = val == true end
      state.binds[#state.binds + 1] = kb
      return kb
    end,
    unbind = function(keys)
      state.unbinds[#state.unbinds + 1] = keys
    end,
    get_windows = function()
      return state.windows
    end,
    get_workspace_windows = function(ws_str)
      local out = {}
      for _, w in ipairs(state.windows) do
        local wname = w.workspace and w.workspace.name or (w.workspace and tostring(w.workspace.id) or "")
        local wid = w.workspace and w.workspace.id and tostring(w.workspace.id) or ""
        if wname == tostring(ws_str) or wid == tostring(ws_str) then
          out[#out + 1] = w
        end
      end
      return out
    end,
    get_window = function(spec)
      local addr = tostring(spec or ""):match("^address:(.+)$")
      for _, w in ipairs(state.windows) do
        if w.address == addr then
          return w
        end
      end
      return nil
    end,
    get_workspaces = function()
      return state.workspaces
    end,
    get_active_window = function()
      return state.active_window
    end,
    get_active_workspace = function()
      return state.active_workspace
    end,
    get_monitors = function()
      return state.monitors
    end,
    get_monitor = function(name)
      for _, m in ipairs(state.monitors) do
        if m.name == name then
          return m
        end
      end
      return nil
    end,
    get_active_monitor = function()
      return state.active_monitor
    end,
    get_cursor_pos = function()
      return { x = 500, y = 500 }
    end,
  }

  local orig_workspace_mode_calls = 0
  local function base_workspace_mode(spec)
    orig_workspace_mode_calls = orig_workspace_mode_calls + 1
    state.workspace_modes[#state.workspace_modes + 1] = spec
  end

  local o_mock = {
    workspace_mode = base_workspace_mode,
    rebind = function(keys, desc, action, opts)
      state.rebinds[#state.rebinds + 1] = { keys = keys, desc = desc, action = action, opts = opts }
    end,
  }

  local function flush_timers()
    local batch = state.timers
    state.timers = {}
    for _, t in ipairs(batch) do
      t.fn()
    end
  end

  local function emit(ev, arg)
    for _, fn in ipairs(state.hooks[ev] or {}) do
      fn(arg)
    end
  end

  local function orig_mode_call_count()
    return orig_workspace_mode_calls
  end

  _G.hl = hl_mock
  _G.o = o_mock
  return state, flush_timers, emit, base_workspace_mode, orig_mode_call_count
end

-- 1. geometry.get_window_frame_insets caches config lookups until invalidated
do
  local state = make_harness()
  local geometry = require("hypr.windaase.geometry")
  geometry.invalidate_frame_insets_cache()

  local w_float = { floating = true, tags = { "omarchy-floating-workspace" } }
  local b1, tb1 = geometry.get_window_frame_insets(w_float)
  local b2, tb2 = geometry.get_window_frame_insets(w_float)
  assert(b1 == 2 and tb1 == 30 and b2 == 2 and tb2 == 30, "frame insets values mismatch")
  assert(state.get_config_calls["general.border_size"] == 1, "border_size should be cached across calls")
  assert(state.get_config_calls["plugin.hyprbars.bar_height"] == 1, "bar_height should be cached across calls")

  state.config["general.border_size"] = 4
  geometry.invalidate_frame_insets_cache()
  local b3 = geometry.get_window_frame_insets(w_float)
  assert(b3 == 4 and state.get_config_calls["general.border_size"] == 2, "invalidate_frame_insets_cache must refresh config")
end

-- 2. floating_only intercepts workspace_mode, locks Super+L, unbinds tiling keys, and restores cleanly
do
  local state, flush_timers, _, base_fn = make_harness()
  state.workspaces = { { id = 1, name = "1" }, { id = 2, name = "2" } }
  local floating_only = require("hypr.windaase.floating_only")

  floating_only.setup({ floating_only = true, shortcuts = true })
  assert(_G.o.workspace_mode ~= base_fn, "floating_only must wrap o.workspace_mode")

  local lock_rebound = false
  for _, rb in ipairs(state.rebinds) do
    if rb.keys == "SUPER + L" and rb.action == "omarchy-system-lock" then
      lock_rebound = true
    end
  end
  assert(lock_rebound, "floating_only must rebind SUPER + L to omarchy-system-lock")
  assert(#state.unbinds >= 5, "floating_only must unbind tiling/layout-switch keys")

  local prev_count = #state.workspace_modes
  _G.o.workspace_mode({ workspace = "2", mode = "dwindle" })
  assert(state.workspace_modes[prev_count + 1].mode == "floating", "non-floating workspace_mode call must coerce to floating")
  flush_timers()

  floating_only.setup({ floating_only = false })
  assert(_G.o.workspace_mode == base_fn, "disabling floating_only must restore original o.workspace_mode")
end

-- 3. show_desktop tags and minimizes open windows, then restores and strips transient tags
do
  local state = make_harness()
  local w1 = {
    address = "0x1111",
    floating = true,
    mapped = true,
    pinned = false,
    tags = {},
    workspace = { id = 1, name = "1" },
  }
  local w2 = {
    address = "0x2222",
    floating = true,
    mapped = true,
    pinned = true,
    tags = {},
    workspace = { id = 1, name = "1" },
  }
  state.windows = { w1, w2 }
  local show_desktop = require("hypr.windaase.show_desktop")

  -- First toggle minimizes w1 (skipping pinned w2)
  show_desktop.toggle()
  local tagged_show, moved_min = false, false
  for _, d in ipairs(state.dispatches) do
    if d._kind == "window.tag" and d.tag == "+omarchy-showdesktop-1" and d.window == w1 then
      tagged_show = true
    end
    if d._kind == "window.move" and d.workspace == "special:minimized" and d.window == w1 then
      moved_min = true
    end
    assert(d.window ~= w2, "pinned window must never be minimized by show_desktop")
  end
  assert(tagged_show and moved_min, "show_desktop must tag and minimize open non-pinned window")

  -- Simulate w1 now living on special:minimized with transient tags, then toggle back
  w1.workspace = { id = -99, name = "special:minimized" }
  w1.tags = { "omarchy-minimized-from-1", "omarchy-showdesktop-1" }
  state.dispatches = {}
  show_desktop.toggle()

  local stripped, restored = false, false
  for _, d in ipairs(state.dispatches) do
    if d._kind == "window.tag" and d.tag == "-omarchy-showdesktop-1" then
      stripped = true
    end
    if d._kind == "window.move" and d.workspace == "1" and d.window == w1 then
      restored = true
    end
  end
  assert(stripped and restored, "second toggle must strip transient tags and restore window to workspace 1")
end

-- 4. alt_tab steps through MRU windows, prunes closed windows, and commits cleanly
do
  local state, flush_timers, emit = make_harness()
  local rt_dir = os.getenv("XDG_RUNTIME_DIR") or "/tmp"
  local alttab_file = rt_dir .. "/omarchy-windaase-alttab.json"
  local w1 = { address = "0xaaaa", mapped = true, focus_history_id = 0, workspace = { id = 1, name = "1" }, monitor = state.monitors[1] }
  local w2 = { address = "0xbbbb", mapped = true, focus_history_id = 1, workspace = { id = 1, name = "1" }, monitor = state.monitors[1] }
  state.windows = { w1, w2 }
  state.active_window = w1

  local alt_tab = require("hypr.windaase.alt_tab")
  alt_tab.setup({ alt_tab = true })

  assert(alt_tab.step(1) == true, "alt_tab.step should start session with 2 windows")
  local f = assert(io.open(alttab_file, "r"), "expected alt_tab state json file")
  local raw = f:read("*a")
  f:close()
  assert(raw:find('"open":true') and raw:find('"selected":1'), "initial Alt+Tab forward should select 2nd MRU window (index 1)")

  -- Destroy second window while session open -> falls back to remaining window (index 0)
  emit("window.destroy", { address = "0xbbbb" })
  state.windows = { w1 }
  assert(alt_tab.commit(false) == true, "alt_tab.commit should succeed for remaining window")
  local f2 = assert(io.open(alttab_file, "r"))
  local closed_raw = f2:read("*a")
  f2:close()
  assert(closed_raw:find('"open":false'), "commit must close Alt+Tab state")
  os.remove(alttab_file)
  flush_timers()
end

-- 5. focus & monitors debounce coalescing
do
  local state, flush_timers, emit = make_harness()
  local focus = require("hypr.windaase.focus")
  focus.setup(true)
  assert(state.config["input.follow_mouse"] == 2, "focus.setup(true) must enable follow_mouse=2")
  state.config["input.follow_mouse"] = 0
  emit("workspace.active")
  flush_timers()
  assert(state.config["input.follow_mouse"] == 2, "workspace.active hook must restore follow_mouse=2")

  local monitors = require("hypr.windaase.monitors")
  state.monitors = {} -- triggers apply_profile path when any_monitor_enabled() is false without requiring profiles file on disk
  monitors.setup({})
  local baseline_timers = #state.timers
  emit("monitor.added")
  emit("monitor.removed")
  emit("monitor.added")
  assert(#state.timers >= baseline_timers + 3, "hotplug hooks should schedule debounced timers")
  -- Flush once: seq check ensures at most one apply call runs even across coalesced events
  local orig_exec_count = #state.exec_cmds
  flush_timers()
  assert(#state.exec_cmds <= orig_exec_count + 1, "debounced monitor hotplug must coalesce into at most 1 apply_profile call")
end

print("ALL LUA MODULE TESTS PASSED")
