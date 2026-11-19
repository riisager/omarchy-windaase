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
  "aero_snap",
  "hover_scroll",
  "soft_maximize",
  "auto_raise",
  "shortcuts"
]

function defaultHyprSettings() {
  var out = {}
  for (var i = 0; i < HYPR_OPTION_KEYS.length; i++) {
    out[HYPR_OPTION_KEYS[i]] = true
  }
  return out
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
    parseChromeProfiles: parseChromeProfiles,
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
    formatTemplate: formatTemplate
  }
}
