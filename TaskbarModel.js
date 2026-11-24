// Core taskbar model, settings state, urgency, and formatting helpers for Omarchy-windaase.

var MINIMIZED_WORKSPACE = "special:minimized"

function isArrayLike(val) {
  return Boolean(val && typeof val === "object" && typeof val.length === "number")
}

function isMinimizedWorkspace(name) {
  return String(name || "") === MINIMIZED_WORKSPACE
}

function normalizeId(value) {
  var id = String(value || "").trim()
  if (id.slice(-8) === ".desktop") id = id.slice(0, -8)
  return id
}

function normalizeAddress(value) {
  var s = String(value === undefined || value === null ? "" : value).trim()
  if (!s) return ""
  var m = /^(?:0[xX])?([0-9a-fA-F]{1,20})$/.exec(s)
  return m ? ("0x" + m[1]) : ""
}

function isDockWindow(window) {
  if (!window || !window.key) return false
  if (window.minimized === true) return true
  return window.hasEntry === true && window.workspaceId >= 1
}

function collectTerminalEntries(entries) {
  var values = isArrayLike(entries) ? entries : []
  var out = []
  for (var i = 0; i < values.length; i++) {
    var entry = values[i]
    if (!entry) continue
    if (entry.runInTerminal || String(entry.execString || "").indexOf("--app-id=") >= 0) {
      out.push({
        id: entry.id,
        execString: entry.execString,
        command: entry.command,
        runInTerminal: !!entry.runInTerminal
      })
    }
  }
  return out
}

function claimingEntryId(appId, entries) {
  var id = String(appId || "")
  if (!id) return ""
  var list = entries || []
  var flag = "--app-id=" + id
  for (var i = 0; i < list.length; i++) {
    var words = String(list[i].execString || "").split(/\s+/)
    if (words.indexOf(flag) >= 0) return list[i].id
  }
  if (id.indexOf("org.omarchy.") !== 0) return ""
  var command = id.slice("org.omarchy.".length)
  for (var j = 0; j < list.length; j++) {
    var program = String((list[j].command || [])[0] || "")
    if (list[j].runInTerminal && program.slice(program.lastIndexOf("/") + 1) === command) return list[j].id
  }
  return ""
}

// Preserves first-seen order of windows across focus/workspace changes so
// uncombined taskbar icons keep a predictable slot order.
function stabilizeWindows(windows, orderState) {
  var list = windows || []
  if (!orderState || typeof orderState !== "object") return list.slice()
  if (typeof orderState.seq !== "number") orderState.seq = 0
  if (!orderState.byAddr || typeof orderState.byAddr !== "object") orderState.byAddr = {}

  var active = {}
  for (var i = 0; i < list.length; i++) {
    var id = String(list[i] && list[i].address ? list[i].address : "")
    if (id) {
      active[id] = true
      if (orderState.byAddr[id] === undefined) {
        orderState.byAddr[id] = ++orderState.seq
      }
    }
  }

  var known = Object.keys(orderState.byAddr)
  for (var k = 0; k < known.length; k++) {
    if (!active[known[k]]) delete orderState.byAddr[known[k]]
  }

  var indexed = list.map(function(win, idx) {
    var addr = String(win && win.address ? win.address : "")
    var rank = addr && orderState.byAddr[addr] !== undefined ? orderState.byAddr[addr] : Number.MAX_SAFE_INTEGER
    return { win: win, rank: rank, idx: idx }
  })
  indexed.sort(function(a, b) {
    if (a.rank !== b.rank) return a.rank - b.rank
    return a.idx - b.idx
  })
  return indexed.map(function(entry) { return entry.win })
}

// Pinned apps appear first in pin order, followed by unpinned running apps.
// Apps listed in uncombinedKeys render one taskbar item per open window.
function buildItems(pinned, windows, uncombinedKeys) {
  var items = []
  var uncombined = {}
  var uncombinedList = uncombinedKeys || []
  for (var u = 0; u < uncombinedList.length; u++) {
    var uk = normalizeId(uncombinedList[u])
    if (uk) uncombined[uk] = true
  }

  var windowsByApp = {}
  for (var i = 0; i < (windows || []).length; i++) {
    var win = windows[i]
    if (!isDockWindow(win)) continue
    if (!windowsByApp[win.key]) windowsByApp[win.key] = []
    windowsByApp[win.key].push(win)
  }

  var handled = {}
  var pinnedList = pinned || []
  for (var p = 0; p < pinnedList.length; p++) {
    var appId = normalizeId(pinnedList[p])
    if (!appId || handled[appId]) continue
    handled[appId] = true
    var wins = windowsByApp[appId] || []
    if (uncombined[appId]) {
      if (wins.length === 0) {
        items.push({ key: appId, appKey: appId, pinned: true, split: false, windows: [] })
      } else {
        for (var wi = 0; wi < wins.length; wi++) {
          var w = wins[wi]
          var winAddr = String(w.address || "")
          items.push({
            key: appId + "::" + (winAddr || ("idx" + wi)),
            appKey: appId,
            pinned: true,
            split: true,
            windows: [w]
          })
        }
      }
    } else {
      items.push({ key: appId, appKey: appId, pinned: true, split: false, windows: wins })
    }
  }

  var unpinnedByKey = {}
  for (var j = 0; j < (windows || []).length; j++) {
    var w2 = windows[j]
    if (!isDockWindow(w2) || handled[w2.key]) continue
    if (uncombined[w2.key]) {
      var uAddr = String(w2.address || "")
      items.push({
        key: w2.key + "::" + (uAddr || ("u" + j)),
        appKey: w2.key,
        pinned: false,
        split: true,
        windows: [w2]
      })
    } else {
      if (!unpinnedByKey[w2.key]) {
        unpinnedByKey[w2.key] = { key: w2.key, appKey: w2.key, pinned: false, split: false, windows: [] }
        items.push(unpinnedByKey[w2.key])
      }
      unpinnedByKey[w2.key].windows.push(w2)
    }
  }

  return items
}

function computeDropIndex(fromIndex, delta, stride, count) {
  if (!(count > 0)) return 0
  var step = Math.round(Number(delta || 0) / Math.max(1, Number(stride) || 1))
  return Math.max(0, Math.min(count - 1, Number(fromIndex || 0) + step))
}

function _cloneOrderState(orderState) {
  var next = {
    seq: (orderState && typeof orderState.seq === "number") ? orderState.seq : 0,
    byAddr: {}
  }
  var src = (orderState && orderState.byAddr && typeof orderState.byAddr === "object") ? orderState.byAddr : {}
  var keys = Object.keys(src)
  for (var i = 0; i < keys.length; i++) {
    next.byAddr[keys[i]] = src[keys[i]]
  }
  return next
}

function _reassignRanks(orderState, orderedAddrs) {
  if (!orderedAddrs || orderedAddrs.length < 2) return null
  var next = _cloneOrderState(orderState)
  var ranks = []
  var i
  for (i = 0; i < orderedAddrs.length; i++) {
    var a = orderedAddrs[i]
    if (next.byAddr[a] === undefined) {
      next.byAddr[a] = ++next.seq
    }
    ranks.push(next.byAddr[a])
  }
  ranks.sort(function(x, y) { return x - y })
  for (i = 0; i < orderedAddrs.length; i++) {
    next.byAddr[orderedAddrs[i]] = ranks[i]
  }
  return next
}

function _normalizedPins(pinnedList) {
  var out = []
  var seen = {}
  var list = isArrayLike(pinnedList) ? pinnedList : []
  for (var i = 0; i < list.length; i++) {
    var id = normalizeId(list[i])
    if (id && !seen[id]) {
      seen[id] = true
      out.push(id)
    }
  }
  return out
}

function _arraysEqual(a, b) {
  if (a.length !== b.length) return false
  for (var i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) return false
  }
  return true
}

function reorderTaskbarItems(items, pinnedList, orderState, fromIndex, toIndex) {
  if (!isArrayLike(items) || fromIndex < 0 || toIndex < 0
      || fromIndex >= items.length || toIndex >= items.length || fromIndex === toIndex) {
    return null
  }
  var fromItem = items[fromIndex]
  var toItem = items[toIndex]
  if (!fromItem || !toItem) return null

  var fromApp = normalizeId(fromItem.appKey || fromItem.key)
  var toApp = normalizeId(toItem.appKey || toItem.key)

  // 1. Reorder split windows within the same uncombined app
  if (fromItem.split && toItem.split && fromApp && fromApp === toApp) {
    var splitAddrs = []
    var sFrom = -1
    var sTo = -1
    for (var s = 0; s < items.length; s++) {
      var si = items[s]
      if (!si || !si.split || normalizeId(si.appKey || si.key) !== fromApp) continue
      if (!si.windows || si.windows.length === 0) continue
      var sAddr = String(si.windows[0].address || "")
      if (!sAddr) continue
      if (s === fromIndex) sFrom = splitAddrs.length
      if (s === toIndex) sTo = splitAddrs.length
      splitAddrs.push(sAddr)
    }
    if (sFrom >= 0 && sTo >= 0 && sFrom !== sTo) {
      var movedSplit = splitAddrs.splice(sFrom, 1)[0]
      splitAddrs.splice(sTo, 0, movedSplit)
      var splitOrder = _reassignRanks(orderState, splitAddrs)
      return splitOrder ? { kind: "windows", orderState: splitOrder } : null
    }
    return null
  }

  // 2. Reorder pinned apps or pin an unpinned app at the target slot
  if (fromItem.pinned || toItem.pinned) {
    if (!fromApp || (toItem.pinned && fromApp === toApp)) return null
    var basePins = _normalizedPins(pinnedList)
    var nextPins = []
    for (var p = 0; p < basePins.length; p++) {
      if (basePins[p] !== fromApp) nextPins.push(basePins[p])
    }
    if (!toItem.pinned) {
      nextPins.push(fromApp)
    } else {
      var targetIdx = nextPins.indexOf(toApp)
      if (targetIdx < 0) nextPins.push(fromApp)
      else nextPins.splice(fromIndex < toIndex ? targetIdx + 1 : targetIdx, 0, fromApp)
    }
    if (_arraysEqual(basePins, nextPins)) return null
    return { kind: "pins", pinned: nextPins }
  }

  // 3. Reorder unpinned running apps in current window order
  var unpinnedGroups = []
  var gFrom = -1
  var gTo = -1
  for (var u = 0; u < items.length; u++) {
    var ui = items[u]
    if (!ui || ui.pinned) continue
    var addrs = []
    var uWins = ui.windows || []
    for (var w = 0; w < uWins.length; w++) {
      var wa = String(uWins[w] && uWins[w].address ? uWins[w].address : "")
      if (wa) addrs.push(wa)
    }
    if (addrs.length === 0) continue
    if (u === fromIndex) gFrom = unpinnedGroups.length
    if (u === toIndex) gTo = unpinnedGroups.length
    unpinnedGroups.push(addrs)
  }
  if (gFrom < 0 || gTo < 0 || gFrom === gTo) return null
  var movedGroup = unpinnedGroups.splice(gFrom, 1)[0]
  unpinnedGroups.splice(gTo, 0, movedGroup)
  var flatAddrs = []
  for (var f = 0; f < unpinnedGroups.length; f++) {
    for (var k = 0; k < unpinnedGroups[f].length; k++) {
      flatAddrs.push(unpinnedGroups[f][k])
    }
  }
  var unpinnedOrder = _reassignRanks(orderState, flatAddrs)
  return unpinnedOrder ? { kind: "windows", orderState: unpinnedOrder } : null
}

function normalizeWindowFilter(value) {
  var v = String(value === undefined || value === null ? "" : value).trim().toLowerCase()
  if (v === "workspace" || v === "monitor") return v
  return "all"
}

function minimizedOriginWorkspaceId(tags) {
  if (!isArrayLike(tags)) return -1
  for (var i = 0; i < tags.length; i++) {
    var m = /^omarchy-(?:minimized-from|showdesktop)-([1-9][0-9]*)$/.exec(String(tags[i] || ""))
    if (m) return parseInt(m[1], 10)
  }
  return -1
}

function filterWindowsByScope(windows, scope, activeWorkspaceId, activeMonitorName) {
  var list = windows || []
  var mode = normalizeWindowFilter(scope)
  if (mode === "all") return list.slice()
  var ws = Number(activeWorkspaceId)
  var mon = String(activeMonitorName || "")
  var out = []
  for (var i = 0; i < list.length; i++) {
    var win = list[i]
    if (!win) continue
    if (mode === "workspace") {
      if (!(ws >= 1)) {
        out.push(win)
        continue
      }
      if (win.minimized) {
        var originWs = minimizedOriginWorkspaceId(win.tags)
        if (originWs === ws || originWs < 0) out.push(win)
      } else if (win.workspaceId === ws) {
        out.push(win)
      }
    } else if (mode === "monitor") {
      if (!mon || !win.monitorName || String(win.monitorName) === mon) {
        out.push(win)
      }
    }
  }
  return out
}

function sanitizeTooltipText(value, maxLen) {
  var limit = (typeof maxLen === "number" && maxLen > 0) ? Math.floor(maxLen) : 96
  var clean = String(value === undefined || value === null ? "" : value)
    .replace(/[\r\n\t]+/g, " ")
    .replace(/ {2,}/g, " ")
    .trim()
  if (clean.length > limit) {
    return clean.slice(0, Math.max(1, limit - 1)).replace(/\s+$/, "") + "…"
  }
  return clean
}

function sanitizePlainLabel(text, maxLen) {
  var safe = String(text === undefined || text === null ? "" : text)
    .replace(/[\x00-\x1F\x7F]+/g, " ")
    .replace(/</g, "\u2039")
    .replace(/>/g, "\u203A")
  return sanitizeTooltipText(safe, maxLen)
}

function resolveIconSize(slotSize, configuredIconSize, minSize) {
  var slot = Math.max(16, Math.round(Number(slotSize) || 26))
  var min = Math.max(12, Math.round(Number(minSize) || 14))
  var max = Math.max(min, slot - 6)
  var cfg = Number(configuredIconSize)
  if (isFinite(cfg) && cfg > 0) {
    return Math.max(min, Math.min(max, Math.round(cfg)))
  }
  return Math.max(min, Math.min(slot - 10, Math.round(slot * 0.65)))
}

var HYPR_SETTINGS_TOGGLES = [
  { key: "floating_only", labelKey: "settings.floatingOnly" },
  { key: "snap_layouts", labelKey: "settings.snapLayouts" },
  { key: "snap_assist", labelKey: "settings.snapAssist" },
  { key: "snap_resize", labelKey: "settings.snapResize" },
  { key: "aero_snap", labelKey: "settings.aeroSnap" },
  { key: "hover_scroll", labelKey: "settings.hoverScroll" },
  { key: "soft_maximize", labelKey: "settings.softMaximize" },
  { key: "auto_raise", labelKey: "settings.autoRaise" },
  { key: "shortcuts", labelKey: "settings.shortcuts" },
  { key: "alt_tab", labelKey: "settings.altTab" },
  { key: "ultrawide_layout", labelKey: "settings.ultrawideLayout" }
]

var HYPR_OPTION_KEYS = [
  "snap_layouts",
  "snap_assist",
  "snap_resize",
  "aero_snap",
  "floating_only",
  "hover_scroll",
  "soft_maximize",
  "auto_raise",
  "shortcuts",
  "alt_tab",
  "ultrawide_layout"
]

function defaultHyprSettings() {
  return {
    snap_layouts: true,
    snap_assist: true,
    snap_resize: true,
    aero_snap: true,
    floating_only: false,
    hover_scroll: true,
    soft_maximize: true,
    auto_raise: true,
    shortcuts: true,
    alt_tab: true,
    ultrawide_layout: false
  }
}

function parseHyprSettings(rawJson) {
  var out = defaultHyprSettings()
  try {
    var parsed = JSON.parse(String(rawJson || ""))
    if (parsed && typeof parsed === "object" && !isArrayLike(parsed)) {
      for (var i = 0; i < HYPR_OPTION_KEYS.length; i++) {
        var key = HYPR_OPTION_KEYS[i]
        if (typeof parsed[key] === "boolean") {
          out[key] = parsed[key]
        }
      }
    }
  } catch (e) {}
  return out
}

function buildUpdatedWidgetEntry(currentSettings, moduleName, patch) {
  var entry = {}
  var src = (currentSettings && typeof currentSettings === "object" && !isArrayLike(currentSettings)) ? currentSettings : {}
  for (var k in src) {
    if (Object.prototype.hasOwnProperty.call(src, k) && src[k] !== undefined) {
      entry[k] = isArrayLike(src[k]) ? Array.prototype.slice.call(src[k]) : src[k]
    }
  }
  if (patch && typeof patch === "object") {
    for (var pk in patch) {
      if (Object.prototype.hasOwnProperty.call(patch, pk)) {
        if (patch[pk] === undefined) delete entry[pk]
        else entry[pk] = isArrayLike(patch[pk]) ? Array.prototype.slice.call(patch[pk]) : patch[pk]
      }
    }
  }
  entry.id = String(moduleName || entry.id || "")
  if (entry.iconSize !== undefined) {
    var iconNum = Number(entry.iconSize)
    if (!isFinite(iconNum) || iconNum <= 0) delete entry.iconSize
    else entry.iconSize = Math.round(iconNum)
  }
  if (isArrayLike(entry.uncombine) && entry.uncombine.length === 0) {
    delete entry.uncombine
  }
  if (entry.windowFilter !== undefined) {
    var wf = normalizeWindowFilter(entry.windowFilter)
    if (wf === "all") delete entry.windowFilter
    else entry.windowFilter = wf
  }
  return entry
}

function isAppUncombined(uncombinedApps, appKey) {
  var target = normalizeId(appKey).toLowerCase()
  if (!target || !isArrayLike(uncombinedApps)) return false
  for (var i = 0; i < uncombinedApps.length; i++) {
    if (normalizeId(uncombinedApps[i]).toLowerCase() === target) return true
  }
  return false
}

function toggleUncombineApp(uncombinedApps, appKey) {
  var raw = normalizeId(appKey)
  var target = raw.toLowerCase()
  var list = isArrayLike(uncombinedApps) ? uncombinedApps : []
  var out = []
  var seen = {}
  var existed = false
  for (var i = 0; i < list.length; i++) {
    var norm = normalizeId(list[i])
    var low = norm.toLowerCase()
    if (!low) continue
    if (target && low === target) {
      existed = true
      continue
    }
    if (!seen[low]) {
      seen[low] = true
      out.push(norm)
    }
  }
  if (raw && !existed) {
    out.push(raw)
  }
  return out
}

function isTwoLineClockFormat(rawShellJson) {
  try {
    var parsed = JSON.parse(String(rawShellJson || ""))
    var layout = parsed && parsed.bar && parsed.bar.layout
    if (!layout || typeof layout !== "object") return false
    for (var section in layout) {
      var items = layout[section]
      if (!Array.isArray(items)) continue
      for (var i = 0; i < items.length; i++) {
        var entry = items[i]
        if (entry && entry.id === "omarchy.clock") {
          return typeof entry.format === "string" && entry.format.indexOf("\n") >= 0
        }
      }
    }
  } catch (e) {}
  return false
}

function extractPinnedList(rawJson) {
  try {
    var parsed = JSON.parse(String(rawJson || ""))
    if (parsed && parsed.dock && Array.isArray(parsed.dock.pinned)) {
      return parsed.dock.pinned
    }
  } catch (e) {}
  return null
}

function formatTemplate(template, arg1, arg2) {
  var text = String(template === undefined || template === null ? "" : template)
  if (arg1 !== undefined) {
    var s1 = arg1 === null ? "" : String(arg1)
    text = text.split("%1").join(s1)
  }
  if (arg2 !== undefined) {
    var s2 = arg2 === null ? "" : String(arg2)
    text = text.split("%2").join(s2)
  }
  return text
}

function _cloneBoolMap(src) {
  var out = {}
  if (!src || typeof src !== "object" || isArrayLike(src)) return out
  var keys = Object.keys(src)
  for (var i = 0; i < keys.length; i++) {
    var k = keys[i]
    if (src[k]) out[k] = true
  }
  return out
}

function markWindowUrgent(urgentMap, rawAddr, activeAddr) {
  var next = _cloneBoolMap(urgentMap)
  var addr = normalizeAddress(rawAddr).toLowerCase()
  var active = normalizeAddress(activeAddr).toLowerCase()
  if (addr && addr !== active) {
    next[addr] = true
  }
  return next
}

function clearWindowUrgent(urgentMap, rawAddr) {
  var next = _cloneBoolMap(urgentMap)
  var addr = normalizeAddress(rawAddr).toLowerCase()
  if (addr && next[addr]) {
    delete next[addr]
  }
  return next
}

function pruneUrgentWindows(urgentMap, windows) {
  var src = _cloneBoolMap(urgentMap)
  var keys = Object.keys(src)
  if (keys.length === 0) return {}
  var byAddr = {}
  var list = isArrayLike(windows) ? windows : []
  for (var i = 0; i < list.length; i++) {
    var w = list[i]
    if (!w) continue
    var addr = normalizeAddress(w.address).toLowerCase()
    if (addr) byAddr[addr] = w
  }
  var next = {}
  for (var k = 0; k < keys.length; k++) {
    var key = keys[k]
    var win = byAddr[key]
    if (win && !(win.activated && !win.minimized)) {
      next[key] = true
    }
  }
  return next
}

function isItemUrgent(item, urgentMap) {
  if (!item || !isArrayLike(item.windows)) return false
  for (var i = 0; i < item.windows.length; i++) {
    var win = item.windows[i]
    if (!win) continue
    if (win.activated && !win.minimized) continue
    if (win.urgent === true) return true
    var addr = normalizeAddress(win.address).toLowerCase()
    if (addr && urgentMap && urgentMap[addr]) return true
  }
  return false
}

function targetWindowForPin(item) {
  if (!item || !isArrayLike(item.windows)) return null
  var firstVisible = null
  for (var i = 0; i < item.windows.length; i++) {
    var win = item.windows[i]
    if (!win || win.minimized) continue
    if (!firstVisible) firstVisible = win
    if ((win.toplevel && win.toplevel.activated) || win.activated === true) return win
  }
  return firstVisible
}

function resolveIconSource(entry, fallbackId, iconPathFn, fileUrlFn) {
  var raw = entry && entry.icon ? entry.icon : String(fallbackId || "")
  var value = String(raw || "")
  var lookupIcon = typeof iconPathFn === "function" ? iconPathFn : function() { return "" }
  var toFileUrl = typeof fileUrlFn === "function" ? fileUrlFn : function(p) { return "file://" + p }
  if (value.length === 0) return lookupIcon("application-x-executable") || ""
  if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
  if (value.charAt(0) === "/") return toFileUrl(value)
  var themed = lookupIcon(value)
  if (themed && themed.length > 0) return themed
  return lookupIcon("application-x-executable") || ""
}

function resolveSelectedWindowIndex(windows, selectedAddr, fallbackIndex) {
  if (!isArrayLike(windows) || windows.length === 0) return -1
  var target = normalizeAddress(selectedAddr).toLowerCase()
  if (target) {
    for (var i = 0; i < windows.length; i++) {
      var w = windows[i]
      if (w && normalizeAddress(w.address).toLowerCase() === target) return i
    }
  }
  var idx = Math.round(Number(fallbackIndex) || 0)
  return Math.max(0, Math.min(windows.length - 1, idx))
}

if (typeof module !== "undefined") {
  var _core = {
    MINIMIZED_WORKSPACE: MINIMIZED_WORKSPACE,
    isArrayLike: isArrayLike,
    isMinimizedWorkspace: isMinimizedWorkspace,
    normalizeId: normalizeId,
    normalizeAddress: normalizeAddress,
    isDockWindow: isDockWindow,
    collectTerminalEntries: collectTerminalEntries,
    claimingEntryId: claimingEntryId,
    stabilizeWindows: stabilizeWindows,
    buildItems: buildItems,
    computeDropIndex: computeDropIndex,
    reorderTaskbarItems: reorderTaskbarItems,
    normalizeWindowFilter: normalizeWindowFilter,
    minimizedOriginWorkspaceId: minimizedOriginWorkspaceId,
    filterWindowsByScope: filterWindowsByScope,
    sanitizeTooltipText: sanitizeTooltipText,
    sanitizePlainLabel: sanitizePlainLabel,
    resolveIconSize: resolveIconSize,
    HYPR_SETTINGS_TOGGLES: HYPR_SETTINGS_TOGGLES,
    HYPR_OPTION_KEYS: HYPR_OPTION_KEYS,
    defaultHyprSettings: defaultHyprSettings,
    parseHyprSettings: parseHyprSettings,
    buildUpdatedWidgetEntry: buildUpdatedWidgetEntry,
    isAppUncombined: isAppUncombined,
    toggleUncombineApp: toggleUncombineApp,
    isTwoLineClockFormat: isTwoLineClockFormat,
    extractPinnedList: extractPinnedList,
    formatTemplate: formatTemplate,
    markWindowUrgent: markWindowUrgent,
    clearWindowUrgent: clearWindowUrgent,
    pruneUrgentWindows: pruneUrgentWindows,
    isItemUrgent: isItemUrgent,
    targetWindowForPin: targetWindowForPin,
    resolveIconSource: resolveIconSource,
    resolveSelectedWindowIndex: resolveSelectedWindowIndex
  }
  if (typeof require === "function") {
    module.exports = Object.assign(
      _core,
      require("./js/MonitorLayout.js"),
      require("./js/BrowserProfiles.js"),
      require("./js/SnapLayoutMath.js"),
      require("./js/AppSearch.js"),
      require("./js/WindowActions.js")
    )
  } else {
    module.exports = _core
  }
}
