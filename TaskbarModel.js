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

function browserProfileConfigDir(appKey, homeDir) {
  var home = String(homeDir || "").replace(/\/+$/, "")
  if (!home) return ""
  var key = normalizeId(appKey).toLowerCase()
  if (key === "google-chrome") return home + "/.config/google-chrome"
  if (key === "chromium") return home + "/.config/chromium"
  if (key === "brave-browser" || key === "brave") return home + "/.config/BraveSoftware/Brave-Browser"
  return ""
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
    var picFile = String(info.gaia_picture_file_name || "").trim()
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
    isValidProfileDir: isValidProfileDir,
    sanitizeTooltipText: sanitizeTooltipText,
    browserProfileConfigDir: browserProfileConfigDir,
    parseChromeProfiles: parseChromeProfiles
  }
}
