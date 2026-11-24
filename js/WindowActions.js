// Pure Hyprland toplevel normalization and self-contained hyprctl dispatch builders.

var MINIMIZED_WORKSPACE = "special:minimized"
var MINIMIZE_TAG_PREFIXES = [
  "omarchy-minimized-from-",
  "omarchy-showdesktop-",
  "omarchy-minimize-others-"
]
var _TRANSIENT_MINIMIZE_TAG_RE = /^omarchy-(?:minimized-from|showdesktop|minimize-others)-[0-9]+$/
var _MINIMIZED_FROM_TAG_RE = /^omarchy-minimized-from-[0-9]+$/

function isArrayLike(val) {
  return Boolean(val && typeof val === "object" && typeof val.length === "number")
}

function isMinimizedWorkspace(name) {
  return String(name || "") === MINIMIZED_WORKSPACE
}

function normalizeAddress(value) {
  var s = String(value === undefined || value === null ? "" : value).trim()
  if (!s) return ""
  var m = /^(?:0[xX])?([0-9a-fA-F]{1,20})$/.exec(s)
  return m ? ("0x" + m[1]) : ""
}

function _lookupProfile(normAddr, windowProfiles) {
  if (!normAddr || !windowProfiles || typeof windowProfiles !== "object") return null
  return windowProfiles[normAddr.toLowerCase()] || windowProfiles[normAddr] || null
}

function normalizeToplevelWindow(tl, opts) {
  if (!tl) return null
  var cfg = opts || {}
  var wl = tl.wayland || null
  if (cfg.requireWayland !== false && !wl) return null
  if (wl && wl.parent) return null
  var ipc = tl.lastIpcObject || {}
  if (cfg.skipUnmapped && ipc.mapped === false) return null

  var appId = (wl && wl.appId)
    ? String(wl.appId)
    : (ipc["class"] ? String(ipc["class"]) : (ipc.initialClass ? String(ipc.initialClass) : ""))
  if (cfg.requireAppId !== false && !appId) return null

  var entry = (appId && typeof cfg.resolveEntry === "function") ? cfg.resolveEntry(appId) : null
  var appKey = entry && entry.id ? entry.id : appId
  var appName = (entry && entry.name) ? entry.name : (appKey || appId)

  var ws = tl.workspace || null
  var wsName = (ws && ws.name) ? String(ws.name) : (ipc.workspace && ipc.workspace.name ? String(ipc.workspace.name) : "")
  var wsId = (ws && typeof ws.id === "number")
    ? Number(ws.id)
    : ((ipc.workspace && ipc.workspace.id !== undefined) ? Number(ipc.workspace.id) : -1)
  if (!isFinite(wsId)) wsId = -1

  var winMon = tl.monitor || (ws ? ws.monitor : null)
  var monitorName = winMon && winMon.name ? String(winMon.name) : ""

  var rawTags = ipc.tags
  var cleanTags = []
  if (isArrayLike(rawTags)) {
    for (var ti = 0; ti < rawTags.length; ti++) {
      cleanTags.push(String(rawTags[ti]))
    }
  }

  var address = tl.address || ipc.address || ""
  var normAddr = normalizeAddress(address)
  var minimized = isMinimizedWorkspace(wsName)
  var activated = !!(wl && wl.activated)
  var floating = !!ipc.floating
  var fullscreenNum = ipc.fullscreen ? Number(ipc.fullscreen) : (wl && wl.fullscreen ? 1 : 0)
  var pinned = !!ipc.pinned
  var title = (wl && wl.title) ? String(wl.title) : (ipc.title ? String(ipc.title) : appName)
  var urgent = !!(normAddr && cfg.urgentAddresses && cfg.urgentAddresses[normAddr.toLowerCase()] && !(activated && !minimized))

  var at = isArrayLike(ipc.at) ? ipc.at : []
  var size = isArrayLike(ipc.size) ? ipc.size : []
  var iconSource = (typeof cfg.resolveIcon === "function") ? cfg.resolveIcon(entry, appKey || appId) : ""

  return {
    key: appKey,
    appKey: appKey,
    hasEntry: !!entry && !entry.noDisplay,
    appName: appName,
    title: title,
    iconSource: iconSource,
    activated: activated,
    workspaceId: wsId,
    monitorName: monitorName,
    minimized: minimized,
    floating: floating,
    fullscreen: fullscreenNum > 0,
    pinned: pinned,
    urgent: urgent,
    address: address,
    x: Number(at[0]),
    y: Number(at[1]),
    w: Number(size[0]),
    h: Number(size[1]),
    tags: cleanTags,
    profile: _lookupProfile(normAddr, cfg.windowProfiles),
    toplevel: wl
  }
}

function buildRestoreDispatchPlan(windows, activeWorkspaceId) {
  var list = isArrayLike(windows) ? windows : []
  var ws = Number(activeWorkspaceId)
  var beforeSteps = []
  var afterSteps = []
  var lastTarget = ""

  for (var i = 0; i < list.length; i++) {
    var win = list[i]
    if (!win) continue
    var address = normalizeAddress(win.address)
    if (!address) continue
    var target = "window = \"address:" + address + "\""
    if (win.minimized) {
      if (!(ws >= 1)) continue
      var tags = isArrayLike(win.tags) ? win.tags : []
      for (var j = 0; j < tags.length; j++) {
        var tag = String(tags[j] || "")
        if (_TRANSIENT_MINIMIZE_TAG_RE.test(tag)) {
          beforeSteps.push("hl.dsp.window.tag({ tag = \"-" + tag + "\", " + target + " })")
        }
      }
      beforeSteps.push("hl.dsp.window.set_prop({ prop = \"no_anim\", value = \"1\", " + target + " })")
      beforeSteps.push("hl.dsp.window.move({ workspace = \"" + ws + "\", " + target + " })")
      afterSteps.push("hl.dsp.window.set_prop({ prop = \"no_anim\", value = \"unset\", " + target + " })")
    }
    if (lastTarget && lastTarget !== target) {
      beforeSteps.push("hl.dsp.window.alter_zorder({ mode = \"top\", " + lastTarget + " })")
    }
    lastTarget = target
  }

  if (lastTarget) {
    beforeSteps.push("hl.dsp.focus({ " + lastTarget + " })")
    beforeSteps.push("hl.dsp.window.alter_zorder({ mode = \"top\", " + lastTarget + " })")
  }

  return { beforeSteps: beforeSteps, afterSteps: afterSteps }
}

function formatDispatchChain(steps, shellQuoteFn) {
  if (!isArrayLike(steps) || steps.length === 0) return ""
  var quote = typeof shellQuoteFn === "function" ? shellQuoteFn : function(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
  var cmds = []
  for (var i = 0; i < steps.length; i++) {
    cmds.push("hyprctl dispatch " + quote(steps[i]))
  }
  return cmds.join(" && ")
}

function formatRestoreShellCommand(plan, shellQuoteFn) {
  if (!plan || !isArrayLike(plan.beforeSteps) || plan.beforeSteps.length === 0) return ""
  var quote = typeof shellQuoteFn === "function" ? shellQuoteFn : function(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
  var command = formatDispatchChain(plan.beforeSteps, quote)
  if (isArrayLike(plan.afterSteps) && plan.afterSteps.length > 0) {
    var cleanup = []
    for (var i = 0; i < plan.afterSteps.length; i++) {
      cleanup.push("hyprctl dispatch " + quote(plan.afterSteps[i]))
    }
    command += "; sleep 0.4; " + cleanup.join("; ")
  }
  return command
}

function buildMinimizeDispatchSteps(windows, activeWorkspaceId) {
  var list = isArrayLike(windows) ? windows : []
  var activeWs = Number(activeWorkspaceId)
  var steps = []
  var focusWs = -1

  for (var i = 0; i < list.length; i++) {
    var win = list[i]
    if (!win || win.minimized) continue
    var address = normalizeAddress(win.address)
    if (!address) continue
    var ws = (win.workspaceId >= 1) ? Number(win.workspaceId) : activeWs
    if (!(ws >= 1)) continue
    focusWs = ws
    var target = "window = \"address:" + address + "\""
    var tags = isArrayLike(win.tags) ? win.tags : []
    for (var t = 0; t < tags.length; t++) {
      var tag = String(tags[t] || "")
      if (_MINIMIZED_FROM_TAG_RE.test(tag) && tag !== ("omarchy-minimized-from-" + ws)) {
        steps.push("hl.dsp.window.tag({ tag = \"-" + tag + "\", " + target + " })")
      }
    }
    steps.push("hl.dsp.window.tag({ tag = \"+omarchy-minimized-from-" + ws + "\", " + target + " })")
    steps.push("hl.dsp.window.move({ workspace = \"special:minimized\", follow = false, " + target + " })")
  }

  if (steps.length > 0 && focusWs >= 1) {
    steps.push("hl.dsp.focus({ workspace = \"" + focusWs + "\" })")
  }
  return steps
}

function buildTogglePinDispatchSteps(window) {
  if (!window) return []
  var address = normalizeAddress(window.address)
  if (!address) return []
  var target = "window = \"address:" + address + "\""
  var steps = []
  if (!window.floating && !window.pinned) {
    steps.push("hl.dsp.window.float({ action = \"on\", " + target + " })")
  }
  steps.push("hl.dsp.window.pin({ " + target + " })")
  if (!window.pinned) {
    steps.push("hl.dsp.window.alter_zorder({ mode = \"top\", " + target + " })")
  }
  return steps
}

function buildBringGroupForwardSteps(group) {
  if (!group || !isArrayLike(group.members) || group.members.length < 2) return []
  var steps = []
  if (group.workspaceId >= 1) {
    steps.push("hl.dsp.focus({ workspace = \"" + group.workspaceId + "\" })")
  }
  var focusAddr = normalizeAddress(group.focusAddr).toLowerCase()
  var resolvedFocus = ""
  for (var i = 0; i < group.members.length; i++) {
    var mWin = group.members[i] && group.members[i].window ? group.members[i].window : null
    var mAddr = mWin ? normalizeAddress(mWin.address) : ""
    if (!mAddr) continue
    if (focusAddr && mAddr.toLowerCase() === focusAddr) {
      resolvedFocus = mAddr
      continue
    }
    steps.push("hl.dsp.window.alter_zorder({ mode = \"top\", window = \"address:" + mAddr + "\" })")
  }
  if (!resolvedFocus && group.members[0] && group.members[0].window) {
    resolvedFocus = normalizeAddress(group.members[0].window.address)
  }
  if (resolvedFocus) {
    var target = "window = \"address:" + resolvedFocus + "\""
    steps.push("hl.dsp.focus({ " + target + " })")
    steps.push("hl.dsp.window.alter_zorder({ mode = \"top\", " + target + " })")
  }
  return steps
}

if (typeof module !== "undefined") {
  module.exports = {
    MINIMIZED_WORKSPACE: MINIMIZED_WORKSPACE,
    MINIMIZE_TAG_PREFIXES: MINIMIZE_TAG_PREFIXES,
    isArrayLike: isArrayLike,
    isMinimizedWorkspace: isMinimizedWorkspace,
    normalizeAddress: normalizeAddress,
    normalizeToplevelWindow: normalizeToplevelWindow,
    buildRestoreDispatchPlan: buildRestoreDispatchPlan,
    formatDispatchChain: formatDispatchChain,
    formatRestoreShellCommand: formatRestoreShellCommand,
    buildMinimizeDispatchSteps: buildMinimizeDispatchSteps,
    buildTogglePinDispatchSteps: buildTogglePinDispatchSteps,
    buildBringGroupForwardSteps: buildBringGroupForwardSteps
  }
}
