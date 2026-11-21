// Pure data/model helpers for the Omarchy-windaase taskbar widget.

var MINIMIZED_WORKSPACE = "special:minimized"

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
  var list = Array.isArray(pinnedList) ? pinnedList : []
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
  if (!Array.isArray(items) || fromIndex < 0 || toIndex < 0
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
  if (!tags || typeof tags.length !== "number") return -1
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

function complementaryZone(zone) {
  if (!zone || zone.max === true) return null
  var rx = Number(zone.rx) || 0
  var ry = Number(zone.ry) || 0
  var rw = Number(zone.rw) || 0
  var rh = Number(zone.rh) || 0
  if (Math.abs(ry) > 0.02 || rh < 0.98) return null
  if (rw <= 0.15 || rw >= 0.85) return null
  var round6 = function(n) { return Math.round(n * 1000000) / 1000000 }
  if (Math.abs(rx) <= 0.02) {
    return { rx: round6(rw), ry: 0, rw: round6(1 - rw), rh: 1.0, max: false }
  }
  if (Math.abs((rx + rw) - 1.0) <= 0.02) {
    return { rx: 0, ry: 0, rw: round6(rx), rh: 1.0, max: false }
  }
  return null
}

function _zoneCenter(z) {
  var rx = Number(z && z.rx) || 0
  var ry = Number(z && z.ry) || 0
  var rw = Number(z && z.rw) || 0
  var rh = Number(z && z.rh) || 0
  return { cx: rx + rw / 2, cy: ry + rh / 2, rx: rx, ry: ry, rw: rw, rh: rh }
}

function _edgeZoneInCard(card, fromEdge, targetCy) {
  if (!Array.isArray(card) || card.length === 0) return 0
  var bestIdx = 0
  var bestScore = Infinity
  for (var i = 0; i < card.length; i++) {
    var m = _zoneCenter(card[i])
    var primary = fromEdge === "left" ? m.cx : (1 - m.cx)
    var dy = Math.abs(m.cy - targetCy)
    var score = primary * 10 + dy
    if (score < bestScore) {
      bestScore = score
      bestIdx = i
    }
  }
  return bestIdx
}

function nextSnapZone(layouts, cardIdx, zoneIdx, direction) {
  var list = Array.isArray(layouts) ? layouts : []
  if (list.length === 0) return { card: -1, zone: -1 }
  var dir = String(direction || "").toLowerCase()
  var c = typeof cardIdx === "number" ? cardIdx : -1
  var z = typeof zoneIdx === "number" ? zoneIdx : -1
  if (c < 0 || c >= list.length || !Array.isArray(list[c]) || list[c].length === 0) {
    return { card: 0, zone: 0 }
  }
  if (z < 0 || z >= list[c].length) z = 0

  if (dir === "tab" || dir === "backtab") {
    var delta = dir === "tab" ? 1 : -1
    var nz = z + delta
    var nc = c
    if (nz >= list[nc].length) {
      nc = (nc + 1) % list.length
      nz = 0
    } else if (nz < 0) {
      nc = (nc - 1 + list.length) % list.length
      nz = Math.max(0, list[nc].length - 1)
    }
    return { card: nc, zone: nz }
  }

  var card = list[c]
  var cur = _zoneCenter(card[z])

  if (dir === "left" || dir === "right") {
    var bestSame = -1
    var bestDist = Infinity
    for (var i = 0; i < card.length; i++) {
      if (i === z) continue
      var cand = _zoneCenter(card[i])
      var overlapsY = Math.min(cur.ry + cur.rh, cand.ry + cand.rh) > Math.max(cur.ry, cand.ry) + 0.01
      if (!overlapsY) continue
      var dx = dir === "right" ? (cand.cx - cur.cx) : (cur.cx - cand.cx)
      if (dx <= 0.02) continue
      var score = dx + Math.abs(cand.cy - cur.cy) * 2
      if (score < bestDist) {
        bestDist = score
        bestSame = i
      }
    }
    if (bestSame >= 0) return { card: c, zone: bestSame }

    var step = dir === "right" ? 1 : -1
    var nextC = (c + step + list.length) % list.length
    var nextZ = _edgeZoneInCard(list[nextC], dir === "right" ? "left" : "right", cur.cy)
    return { card: nextC, zone: nextZ }
  }

  if (dir === "up" || dir === "down") {
    var bestV = -1
    var bestVScore = Infinity
    for (var k = 0; k < card.length; k++) {
      if (k === z) continue
      var vc = _zoneCenter(card[k])
      var overlapsX = Math.min(cur.rx + cur.rw, vc.rx + vc.rw) > Math.max(cur.rx, vc.rx) + 0.01
      if (!overlapsX) continue
      var dy = dir === "down" ? (vc.cy - cur.cy) : (cur.cy - vc.cy)
      if (dy <= 0.02) continue
      var vscore = dy + Math.abs(vc.cx - cur.cx) * 2
      if (vscore < bestVScore) {
        bestVScore = vscore
        bestV = k
      }
    }
    if (bestV >= 0) return { card: c, zone: bestV }
  }

  return { card: c, zone: z }
}

function jumpToSnapCard(layouts, cardNumber, currentCard, currentZone) {
  var list = Array.isArray(layouts) ? layouts : []
  var targetCard = Number(cardNumber) - 1
  if (!isFinite(targetCard) || targetCard < 0 || targetCard >= list.length) return null
  var card = list[targetCard]
  if (!Array.isArray(card) || card.length === 0) return null
  if (targetCard === currentCard) {
    var nextZ = (typeof currentZone === "number" && currentZone >= 0) ? ((currentZone + 1) % card.length) : 0
    return { card: targetCard, zone: nextZ }
  }
  return { card: targetCard, zone: 0 }
}

function filterSnapAssistCandidates(windows, snappedAddr, workspaceId) {
  var list = windows || []
  var excludeAddr = normalizeAddress(snappedAddr).toLowerCase()
  var ws = Number(workspaceId)
  var out = []
  for (var i = 0; i < list.length; i++) {
    var win = list[i]
    if (!win) continue
    if (win.minimized === true) continue
    if (win.floating === false) continue
    if (win.fullscreen) continue
    if (ws >= 1 && win.workspaceId !== ws) continue
    var addr = normalizeAddress(win.address).toLowerCase()
    if (!addr || (excludeAddr && addr === excludeAddr)) continue
    out.push(win)
  }
  return out
}

function isValidProfileDir(dir) {
  if (typeof dir !== "string") return false
  var trimmed = dir.trim()
  if (!trimmed || trimmed.length > 64) return false
  if (trimmed === "." || trimmed === "..") return false
  if (/[\/\\\x00-\x1f\x7f]/.test(dir)) return false
  return true
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

function browserProfileSpec(appKey, homeDir) {
  var home = String(homeDir || "").replace(/\/+$/, "")
  var key = normalizeId(appKey).toLowerCase()
  if (!home || !key) return null

  var chromiumMap = {
    "google-chrome": { dir: home + "/.config/google-chrome", defaultBin: "/usr/bin/google-chrome-stable" },
    "chromium": { dir: home + "/.config/chromium", defaultBin: "chromium" },
    "brave-browser": { dir: home + "/.config/BraveSoftware/Brave-Browser", defaultBin: "brave" },
    "brave": { dir: home + "/.config/BraveSoftware/Brave-Browser", defaultBin: "brave" },
    "vivaldi-stable": { dir: home + "/.config/vivaldi", defaultBin: "vivaldi-stable" },
    "vivaldi": { dir: home + "/.config/vivaldi", defaultBin: "vivaldi-stable" },
    "vivaldi-snapshot": { dir: home + "/.config/vivaldi-snapshot", defaultBin: "vivaldi-snapshot" },
    "microsoft-edge": { dir: home + "/.config/microsoft-edge", defaultBin: "microsoft-edge-stable" },
    "microsoft-edge-stable": { dir: home + "/.config/microsoft-edge", defaultBin: "microsoft-edge-stable" },
    "microsoft-edge-beta": { dir: home + "/.config/microsoft-edge-beta", defaultBin: "microsoft-edge-beta" },
    "microsoft-edge-dev": { dir: home + "/.config/microsoft-edge-dev", defaultBin: "microsoft-edge-dev" }
  }
  if (chromiumMap[key]) {
    return {
      family: "chromium",
      dir: chromiumMap[key].dir,
      stateFile: chromiumMap[key].dir + "/Local State",
      fallbackStateFile: "",
      defaultBin: chromiumMap[key].defaultBin
    }
  }

  var firefoxFallback = home + "/.config/mozilla/firefox/profiles.ini"
  var geckoMap = {
    "firefox": { dir: home + "/.mozilla/firefox", fallbackStateFile: firefoxFallback, defaultBin: "firefox" },
    "org.mozilla.firefox": { dir: home + "/.mozilla/firefox", fallbackStateFile: firefoxFallback, defaultBin: "firefox" },
    "firefox-developer-edition": { dir: home + "/.mozilla/firefox", fallbackStateFile: firefoxFallback, defaultBin: "firefox-developer-edition" },
    "firefox-nightly": { dir: home + "/.mozilla/firefox", fallbackStateFile: firefoxFallback, defaultBin: "firefox-nightly" },
    "zen": { dir: home + "/.zen", fallbackStateFile: "", defaultBin: "zen-browser" },
    "zen-browser": { dir: home + "/.zen", fallbackStateFile: "", defaultBin: "zen-browser" },
    "zen-beta": { dir: home + "/.zen", fallbackStateFile: "", defaultBin: "zen-browser" },
    "zen-alpha": { dir: home + "/.zen", fallbackStateFile: "", defaultBin: "zen-browser" },
    "zen-twilight": { dir: home + "/.zen", fallbackStateFile: "", defaultBin: "zen-browser" },
    "app.zen_browser.zen": { dir: home + "/.zen", fallbackStateFile: "", defaultBin: "zen-browser" },
    "io.github.zen_browser.zen": { dir: home + "/.zen", fallbackStateFile: "", defaultBin: "zen-browser" }
  }
  if (geckoMap[key]) {
    return {
      family: "gecko",
      dir: geckoMap[key].dir,
      stateFile: geckoMap[key].dir + "/profiles.ini",
      fallbackStateFile: geckoMap[key].fallbackStateFile,
      defaultBin: geckoMap[key].defaultBin
    }
  }

  return null
}

function browserProfileConfigDir(appKey, homeDir) {
  var spec = browserProfileSpec(appKey, homeDir)
  return spec ? spec.dir : ""
}

function parseChromeProfiles(rawJson, browserDirPath) {
  var parsed
  try {
    parsed = JSON.parse(String(rawJson || ""))
  } catch (e) {
    return []
  }
  if (!parsed || !parsed.profile || !parsed.profile.info_cache) return []
  var infoCache = parsed.profile.info_cache
  if (typeof infoCache !== "object" || Array.isArray(infoCache)) return []

  var baseDir = browserDirPath ? String(browserDirPath).replace(/\/+$/, "") : ""
  var profiles = []
  var dirs = Object.keys(infoCache)
  for (var i = 0; i < dirs.length; i++) {
    var dir = dirs[i]
    if (dir === "System Profile" || dir === "Guest Profile") continue
    if (!isValidProfileDir(dir)) continue
    var info = infoCache[dir]
    if (!info || typeof info !== "object") continue
    if (info.is_ephemeral === true || info.is_omitted_from_profile_list === true) continue

    var name = String(info.name || info.shortcut_name || info.gaia_name || dir)
      .replace(/[\r\n\t]+/g, " ")
      .trim()
      .slice(0, 64) || dir
    var email = String(info.user_name || "")
      .replace(/[\r\n\t]+/g, " ")
      .trim()
      .slice(0, 96)
    var picFile = String(info.gaia_picture_file_name || info.edge_picture_file_name || info.avatar_picture_file_name || "").trim()
    var picturePath = (baseDir && isValidProfileDir(picFile))
      ? (baseDir + "/" + dir + "/" + picFile)
      : ""
    var initial = name.charAt(0).toUpperCase() || "?"

    profiles.push({
      dir: dir,
      name: name,
      email: email,
      picturePath: picturePath,
      initial: initial
    })
  }

  function sortKey(dir) {
    if (dir === "Default") return { rank: 0, num: 0, lower: "" }
    var m = /^Profile (\d+)$/.exec(dir)
    if (m) return { rank: 1, num: parseInt(m[1], 10), lower: "" }
    return { rank: 2, num: 0, lower: dir.toLowerCase() }
  }

  profiles.sort(function(a, b) {
    var ka = sortKey(a.dir)
    var kb = sortKey(b.dir)
    if (ka.rank !== kb.rank) return ka.rank - kb.rank
    if (ka.rank === 1 && ka.num !== kb.num) return ka.num - kb.num
    if (ka.lower !== kb.lower) return ka.lower < kb.lower ? -1 : 1
    return a.dir < b.dir ? -1 : (a.dir > b.dir ? 1 : 0)
  })

  return profiles.slice(0, 32)
}

function parseGeckoProfiles(rawIni, browserDirPath) {
  var lines = String(rawIni || "").split(/\r?\n/)
  var current = ""
  var sections = {}
  var sectionOrder = []

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line || line.charAt(0) === "#" || line.charAt(0) === ";") continue
    var secMatch = /^\[([^\]]+)\]$/.exec(line)
    if (secMatch) {
      current = secMatch[1].trim()
      if (!sections[current]) {
        sections[current] = {}
        sectionOrder.push(current)
      }
      continue
    }
    if (!current) continue
    var eq = line.indexOf("=")
    if (eq <= 0) continue
    var k = line.slice(0, eq).trim().toLowerCase()
    var v = line.slice(eq + 1).trim()
    sections[current][k] = v
  }

  var installDefaults = {}
  for (var s = 0; s < sectionOrder.length; s++) {
    var secName = sectionOrder[s]
    if (/^install/i.test(secName) && sections[secName]["default"]) {
      installDefaults[sections[secName]["default"]] = true
    }
  }

  var profiles = []
  var seenNames = {}
  for (var p = 0; p < sectionOrder.length; p++) {
    var pName = sectionOrder[p]
    if (!/^profile\d*$/i.test(pName)) continue
    var sec = sections[pName]
    var rawName = String(sec.name || "").replace(/[\r\n\t]+/g, " ").trim()
    var rawPath = String(sec.path || "").replace(/[\r\n\t]+/g, "").trim()
    if (!rawName || !rawPath || /[\x00-\x1f\x7f]/.test(rawPath)) continue
    if (!isValidProfileDir(rawName) || rawName.charAt(0) === "-") continue

    var isRelative = sec.isrelative === undefined ? "1" : String(sec.isrelative).trim()
    if (isRelative !== "0") {
      if (rawPath.charAt(0) === "/" || /[\\]/.test(rawPath) || /(?:^|\/)\.\.(?:\/|$)/.test(rawPath)) continue
    } else if (/(?:^|[\\/])\.\.(?:[\\/]|$)/.test(rawPath)) {
      continue
    }

    var cleanName = rawName.slice(0, 64)
    var dedupKey = cleanName.toLowerCase()
    if (seenNames[dedupKey]) continue
    seenNames[dedupKey] = true

    profiles.push({
      dir: cleanName,
      name: cleanName,
      email: "",
      picturePath: "",
      initial: cleanName.charAt(0).toUpperCase() || "?",
      _isDefault: !!installDefaults[rawPath] || sec["default"] === "1"
    })
  }

  profiles.sort(function(a, b) {
    if (a._isDefault !== b._isDefault) return a._isDefault ? -1 : 1
    var la = a.name.toLowerCase()
    var lb = b.name.toLowerCase()
    if (la !== lb) return la < lb ? -1 : 1
    return a.name < b.name ? -1 : (a.name > b.name ? 1 : 0)
  })

  return profiles.slice(0, 32).map(function(prof) {
    return {
      dir: prof.dir,
      name: prof.name,
      email: prof.email,
      picturePath: prof.picturePath,
      initial: prof.initial
    }
  })
}

function parseBrowserProfiles(rawText, spec) {
  if (!spec || typeof spec !== "object") return []
  if (spec.family === "gecko") return parseGeckoProfiles(rawText, spec.dir)
  return parseChromeProfiles(rawText, spec.dir)
}

function browserProfileLaunchArgv(bin, profileId, spec) {
  var cmd = String(bin || "").trim()
  var prof = String(profileId || "").trim()
  if (!cmd || !isValidProfileDir(prof)) return []
  if (spec && spec.family === "gecko") {
    if (prof.charAt(0) === "-") return []
    return ["uwsm-app", "--", cmd, "-P", prof]
  }
  return ["uwsm-app", "--", cmd, "--profile-directory=" + prof]
}

function lookupWindowProfile(address, windowProfiles) {
  if (!windowProfiles || typeof windowProfiles !== "object") return null
  var norm = normalizeAddress(address)
  if (!norm) return null
  return windowProfiles[norm.toLowerCase()] || windowProfiles[norm] || null
}

function profileBadgeForItem(item, windowProfiles) {
  if (!item || !Array.isArray(item.windows) || item.windows.length === 0) return null
  var first = lookupWindowProfile(item.windows[0].address, windowProfiles) || item.windows[0].profile || null
  if (!first || !first.dir) return null
  for (var i = 1; i < item.windows.length; i++) {
    var cur = lookupWindowProfile(item.windows[i].address, windowProfiles) || item.windows[i].profile || null
    if (!cur || cur.dir !== first.dir) return null
  }
  return first
}

function formatWindowTooltipWithProfile(title, profile) {
  var t = String(title === undefined || title === null ? "" : title)
  var pName = profile && profile.name ? String(profile.name).trim() : ""
  if (!pName) return t
  return t ? (pName + " \u00b7 " + t) : pName
}

function parseHiddenEntryIds(rawText) {
  var map = {}
  var lines = String(rawText || "").split(/\r?\n/)
  for (var i = 0; i < lines.length; i++) {
    var id = normalizeId(lines[i])
    if (id.length > 0) map[id] = true
  }
  return map
}

function entryName(entry) {
  return String((entry && entry.name) || (entry && entry.id) || "")
}

function _keywordText(entry) {
  try {
    if (entry && entry.keywords) {
      if (typeof entry.keywords.join === "function") return entry.keywords.join(" ")
      if (typeof entry.keywords.length === "number") {
        var parts = []
        for (var i = 0; i < entry.keywords.length; i++) parts.push(String(entry.keywords[i] || ""))
        return parts.join(" ")
      }
    }
  } catch (e) {}
  return ""
}

function _entrySearchText(entry) {
  if (!entry) return ""
  return [entry.name, entry.genericName, entry.comment, _keywordText(entry), entry.id].join(" ").toLowerCase()
}

function _entryAcronym(entry) {
  var raw = [entry && entry.name, entry && entry.genericName, _keywordText(entry), entry && entry.id].join(" ")
  var wordText = String(raw || "")
    .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
    .replace(/[._:/\\-]+/g, " ")
    .toLowerCase()
  var tokens = wordText.split(/[^a-z0-9]+/)
  var out = ""
  for (var i = 0; i < tokens.length; i++) {
    if (tokens[i]) out += tokens[i].charAt(0)
  }
  return out
}

function _termMatches(entry, term) {
  if (!term) return true
  var name = entryName(entry).toLowerCase()
  var id = String((entry && entry.id) || "").toLowerCase()
  if (name.indexOf(term) >= 0) return true
  if (id.indexOf(term) >= 0) return true
  if (_entrySearchText(entry).indexOf(term) >= 0) return true
  return term.length <= 5 && _entryAcronym(entry).indexOf(term) >= 0
}

function _allTermsMatch(entry, query) {
  var terms = String(query || "").toLowerCase().trim().split(/\s+/)
  for (var i = 0; i < terms.length; i++) {
    if (terms[i] && !_termMatches(entry, terms[i])) return false
  }
  return true
}

function _fuzzyScore(entry, query) {
  var q = String(query || "").trim().toLowerCase()
  if (!q) return 0
  if (!_allTermsMatch(entry, q)) return -1

  var name = entryName(entry).toLowerCase()
  var id = String((entry && entry.id) || "").toLowerCase()
  var haystack = _entrySearchText(entry)
  var directName = name.indexOf(q)
  var directId = id.indexOf(q)
  if (directName === 0) return 10000 - name.length
  if (directId === 0) return 9500 - id.length
  if (directName > 0) return 8000 - directName * 10 - name.length
  if (directId > 0) return 7600 - directId * 10 - id.length

  var hayIndex = haystack.indexOf(q)
  if (hayIndex >= 0) return 6000 - hayIndex

  var acronym = _entryAcronym(entry)
  var acronymIndex = acronym.indexOf(q)
  if (acronymIndex === 0) return 5000 - acronym.length
  if (acronymIndex > 0) return 4600 - acronymIndex * 10 - acronym.length

  return 4000 - name.length
}

function filterAndSortApps(entries, query, hiddenMap) {
  var list = entries || []
  var hidden = hiddenMap || {}
  var q = String(query || "").trim()
  var rows = []

  for (var i = 0; i < list.length; i++) {
    var entry = list[i]
    if (!entry || entry.noDisplay === true) continue
    var normId = normalizeId(entry.id)
    if (normId && hidden[normId] === true) continue
    var name = entryName(entry)
    if (!name) continue
    var score = _fuzzyScore(entry, q)
    if (score < 0) continue
    rows.push({
      entry: entry,
      score: score,
      key: name.toLowerCase(),
      idKey: normId.toLowerCase()
    })
  }

  rows.sort(function(a, b) {
    if (q && a.score !== b.score) return b.score - a.score
    if (a.key !== b.key) return a.key < b.key ? -1 : 1
    if (a.idKey !== b.idKey) return a.idKey < b.idKey ? -1 : 1
    return 0
  })

  return rows.map(function(row) { return row.entry })
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

var HYPR_OPTION_KEYS = [
  "snap_layouts",
  "snap_assist",
  "snap_resize",
  "aero_snap",
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
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
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
  var src = (currentSettings && typeof currentSettings === "object" && !Array.isArray(currentSettings)) ? currentSettings : {}
  for (var k in src) {
    if (Object.prototype.hasOwnProperty.call(src, k) && src[k] !== undefined) {
      entry[k] = Array.isArray(src[k]) ? src[k].slice() : src[k]
    }
  }
  if (patch && typeof patch === "object") {
    for (var pk in patch) {
      if (Object.prototype.hasOwnProperty.call(patch, pk)) {
        if (patch[pk] === undefined) delete entry[pk]
        else entry[pk] = Array.isArray(patch[pk]) ? patch[pk].slice() : patch[pk]
      }
    }
  }
  entry.id = String(moduleName || entry.id || "")
  if (entry.iconSize !== undefined) {
    var iconNum = Number(entry.iconSize)
    if (!isFinite(iconNum) || iconNum <= 0) delete entry.iconSize
    else entry.iconSize = Math.round(iconNum)
  }
  if (Array.isArray(entry.uncombine) && entry.uncombine.length === 0) {
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
  if (!target || !Array.isArray(uncombinedApps)) return false
  for (var i = 0; i < uncombinedApps.length; i++) {
    if (normalizeId(uncombinedApps[i]).toLowerCase() === target) return true
  }
  return false
}

function toggleUncombineApp(uncombinedApps, appKey) {
  var raw = normalizeId(appKey)
  var target = raw.toLowerCase()
  var list = Array.isArray(uncombinedApps) ? uncombinedApps : []
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

function launchArgvForEntry(entry) {
  var id = entry ? String(entry.id || "").trim() : ""
  if (!id) return []
  if (entry.runInTerminal) {
    var cmd = []
    var rawCmd = entry.command || []
    for (var i = 0; i < rawCmd.length; i++) {
      var word = String(rawCmd[i] || "")
      if (word && !/^%[a-zA-Z]$/.test(word)) {
        cmd.push(word)
      }
    }
    if (cmd.length > 0) {
      return ["omarchy-launch-tui"].concat(cmd)
    }
  }
  var launchId = id.slice(-8) === ".desktop" ? id : (id + ".desktop")
  return ["uwsm-app", "--", "gtk-launch", launchId]
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
  if (!src || typeof src !== "object" || Array.isArray(src)) return out
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
  var list = Array.isArray(windows) ? windows : []
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
  if (!item || !Array.isArray(item.windows)) return false
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
  if (!item || !Array.isArray(item.windows)) return null
  var firstVisible = null
  for (var i = 0; i < item.windows.length; i++) {
    var win = item.windows[i]
    if (!win || win.minimized) continue
    if (!firstVisible) firstVisible = win
    if ((win.toplevel && win.toplevel.activated) || win.activated === true) return win
  }
  return firstVisible
}

function detectSnapGroups(allWindows, targetWindows) {
  if (!Array.isArray(allWindows) || !Array.isArray(targetWindows) || targetWindows.length === 0) {
    return []
  }

  var candidates = []
  var byAddr = {}
  for (var i = 0; i < allWindows.length; i++) {
    var w = allWindows[i]
    if (!w || w.floating !== true || w.minimized || w.fullscreen) continue
    if (!(Number(w.workspaceId) >= 1)) continue
    var addr = normalizeAddress(w.address).toLowerCase()
    if (!addr || byAddr[addr]) continue
    var wx = Number(w.x)
    var wy = Number(w.y)
    var ww = Number(w.w)
    var wh = Number(w.h)
    if (!isFinite(wx) || !isFinite(wy) || !isFinite(ww) || !isFinite(wh)) continue
    if (ww < 120 || wh < 120) continue
    var node = {
      normAddr: addr,
      workspaceId: Number(w.workspaceId),
      monitorName: String(w.monitorName || ""),
      x: wx,
      y: wy,
      w: ww,
      h: wh,
      window: w
    }
    byAddr[addr] = candidates.length
    candidates.push(node)
  }

  if (candidates.length < 2) return []

  var adj = []
  for (var n = 0; n < candidates.length; n++) adj.push([])

  for (var aIdx = 0; aIdx < candidates.length; aIdx++) {
    var a = candidates[aIdx]
    for (var bIdx = aIdx + 1; bIdx < candidates.length; bIdx++) {
      var b = candidates[bIdx]
      if (a.workspaceId !== b.workspaceId || a.monitorName !== b.monitorName) continue

      var ix1 = Math.max(a.x, b.x)
      var iy1 = Math.max(a.y, b.y)
      var ix2 = Math.min(a.x + a.w, b.x + b.w)
      var iy2 = Math.min(a.y + a.h, b.y + b.h)
      var interArea = (ix2 > ix1 && iy2 > iy1) ? ((ix2 - ix1) * (iy2 - iy1)) : 0
      var minArea = Math.min(a.w * a.h, b.w * b.h)
      if (interArea >= 0.05 * minArea) continue

      var vOverlap = Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y)
      var hGap = Math.max(b.x - (a.x + a.w), a.x - (b.x + b.w))
      var horizAdj = vOverlap >= 0.40 * Math.max(a.h, b.h) && hGap >= -4 && hGap <= 36

      var hOverlap = Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x)
      var vGap = Math.max(b.y - (a.y + a.h), a.y - (b.y + b.h))
      var vertAdj = hOverlap >= 0.40 * Math.max(a.w, b.w) && vGap >= -4 && vGap <= 64

      if (horizAdj || vertAdj) {
        adj[aIdx].push(bIdx)
        adj[bIdx].push(aIdx)
      }
    }
  }

  var groups = []
  var seenGroups = {}

  for (var t = 0; t < targetWindows.length; t++) {
    var tw = targetWindows[t]
    if (!tw) continue
    var startAddr = normalizeAddress(tw.address).toLowerCase()
    if (!startAddr || byAddr[startAddr] === undefined) continue
    var startIdx = byAddr[startAddr]
    if (adj[startIdx].length === 0) continue

    var visited = {}
    var queue = [startIdx]
    visited[startIdx] = true
    var comp = []
    while (queue.length > 0) {
      var cur = queue.shift()
      comp.push(candidates[cur])
      var nbrs = adj[cur]
      for (var j = 0; j < nbrs.length; j++) {
        var nextIdx = nbrs[j]
        if (!visited[nextIdx]) {
          visited[nextIdx] = true
          queue.push(nextIdx)
        }
      }
    }

    if (comp.length < 2 || comp.length > 4) continue

    var minX = comp[0].x
    var minY = comp[0].y
    var maxX = comp[0].x + comp[0].w
    var maxY = comp[0].y + comp[0].h
    var sumArea = 0
    var addrList = []
    for (var m = 0; m < comp.length; m++) {
      var cm = comp[m]
      if (cm.x < minX) minX = cm.x
      if (cm.y < minY) minY = cm.y
      if (cm.x + cm.w > maxX) maxX = cm.x + cm.w
      if (cm.y + cm.h > maxY) maxY = cm.y + cm.h
      sumArea += cm.w * cm.h
      addrList.push(cm.normAddr)
    }

    var bboxW = maxX - minX
    var bboxH = maxY - minY
    if (bboxW < 600 || bboxH < 360) continue
    if (sumArea / (bboxW * bboxH) < 0.72) continue

    addrList.sort()
    var groupId = addrList.join("|")
    if (seenGroups[groupId]) continue
    seenGroups[groupId] = true

    comp.sort(function(p, q) {
      if (p.y !== q.y) return p.y - q.y
      if (p.x !== q.x) return p.x - q.x
      return p.normAddr < q.normAddr ? -1 : (p.normAddr > q.normAddr ? 1 : 0)
    })

    var members = comp.map(function(node) {
      return {
        window: node.window,
        rx: (node.x - minX) / bboxW,
        ry: (node.y - minY) / bboxH,
        rw: node.w / bboxW,
        rh: node.h / bboxH
      }
    })

    groups.push({
      id: groupId,
      workspaceId: comp[0].workspaceId,
      focusAddr: startAddr,
      members: members
    })
  }

  return groups
}

if (typeof module !== "undefined") {
  module.exports = {
    MINIMIZED_WORKSPACE: MINIMIZED_WORKSPACE,
    isMinimizedWorkspace: isMinimizedWorkspace,
    normalizeId: normalizeId,
    normalizeAddress: normalizeAddress,
    isDockWindow: isDockWindow,
    claimingEntryId: claimingEntryId,
    stabilizeWindows: stabilizeWindows,
    buildItems: buildItems,
    computeDropIndex: computeDropIndex,
    reorderTaskbarItems: reorderTaskbarItems,
    normalizeWindowFilter: normalizeWindowFilter,
    minimizedOriginWorkspaceId: minimizedOriginWorkspaceId,
    filterWindowsByScope: filterWindowsByScope,
    complementaryZone: complementaryZone,
    nextSnapZone: nextSnapZone,
    jumpToSnapCard: jumpToSnapCard,
    filterSnapAssistCandidates: filterSnapAssistCandidates,
    isValidProfileDir: isValidProfileDir,
    sanitizeTooltipText: sanitizeTooltipText,
    browserProfileSpec: browserProfileSpec,
    browserProfileConfigDir: browserProfileConfigDir,
    parseChromeProfiles: parseChromeProfiles,
    parseGeckoProfiles: parseGeckoProfiles,
    parseBrowserProfiles: parseBrowserProfiles,
    browserProfileLaunchArgv: browserProfileLaunchArgv,
    lookupWindowProfile: lookupWindowProfile,
    profileBadgeForItem: profileBadgeForItem,
    formatWindowTooltipWithProfile: formatWindowTooltipWithProfile,
    parseHiddenEntryIds: parseHiddenEntryIds,
    entryName: entryName,
    filterAndSortApps: filterAndSortApps,
    resolveIconSize: resolveIconSize,
    HYPR_OPTION_KEYS: HYPR_OPTION_KEYS,
    defaultHyprSettings: defaultHyprSettings,
    parseHyprSettings: parseHyprSettings,
    buildUpdatedWidgetEntry: buildUpdatedWidgetEntry,
    isAppUncombined: isAppUncombined,
    toggleUncombineApp: toggleUncombineApp,
    isTwoLineClockFormat: isTwoLineClockFormat,
    extractPinnedList: extractPinnedList,
    launchArgvForEntry: launchArgvForEntry,
    formatTemplate: formatTemplate,
    markWindowUrgent: markWindowUrgent,
    clearWindowUrgent: clearWindowUrgent,
    pruneUrgentWindows: pruneUrgentWindows,
    isItemUrgent: isItemUrgent,
    targetWindowForPin: targetWindowForPin,
    detectSnapGroups: detectSnapGroups
  }
}
