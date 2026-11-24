// Pure Chromium and Gecko multi-profile parsing, launch argv, and badge helpers.

function _isArrayLike(val) {
  return Boolean(val && typeof val === "object" && typeof val.length === "number")
}

function _normalizeId(value) {
  var id = String(value || "").trim()
  if (id.slice(-8) === ".desktop") id = id.slice(0, -8)
  return id
}

function _normalizeAddress(value) {
  var s = String(value === undefined || value === null ? "" : value).trim()
  if (!s) return ""
  var m = /^(?:0[xX])?([0-9a-fA-F]{1,20})$/.exec(s)
  return m ? ("0x" + m[1]) : ""
}

function isValidProfileDir(dir) {
  if (typeof dir !== "string") return false
  var trimmed = dir.trim()
  if (!trimmed || trimmed.length > 64) return false
  if (trimmed === "." || trimmed === "..") return false
  if (/[\/\\\x00-\x1f\x7f]/.test(dir)) return false
  return true
}

function browserProfileSpec(appKey, homeDir) {
  var home = String(homeDir || "").replace(/\/+$/, "")
  var key = _normalizeId(appKey).toLowerCase()
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
  if (typeof infoCache !== "object" || _isArrayLike(infoCache)) return []

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
  var norm = _normalizeAddress(address)
  if (!norm) return null
  return windowProfiles[norm.toLowerCase()] || windowProfiles[norm] || null
}

function profileBadgeForItem(item, windowProfiles) {
  if (!item || !_isArrayLike(item.windows) || item.windows.length === 0) return null
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

function mergeProfileProbeOutput(rawText, currentProfiles) {
  var parsed = null
  try {
    parsed = JSON.parse(String(rawText || "{}"))
  } catch (e) {
    parsed = null
  }
  var merged = Object.assign({}, currentProfiles || {})
  var changed = false
  if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
    var addrs = Object.keys(parsed)
    for (var i = 0; i < addrs.length; i++) {
      var norm = _normalizeAddress(addrs[i]).toLowerCase()
      var incoming = parsed[addrs[i]]
      if (!norm || !incoming || typeof incoming !== "object" || !incoming.dir) continue
      var cur = merged[norm]
      if (cur && cur.confident) continue
      if (!cur || cur.dir !== incoming.dir || cur.name !== incoming.name
          || cur.picturePath !== incoming.picturePath || !!cur.confident !== !!incoming.confident) {
        merged[norm] = incoming
        changed = true
      }
    }
  }
  return { merged: merged, changed: changed }
}

if (typeof module !== "undefined") {
  module.exports = {
    isValidProfileDir: isValidProfileDir,
    browserProfileSpec: browserProfileSpec,
    browserProfileConfigDir: browserProfileConfigDir,
    parseChromeProfiles: parseChromeProfiles,
    parseGeckoProfiles: parseGeckoProfiles,
    parseBrowserProfiles: parseBrowserProfiles,
    browserProfileLaunchArgv: browserProfileLaunchArgv,
    lookupWindowProfile: lookupWindowProfile,
    profileBadgeForItem: profileBadgeForItem,
    formatWindowTooltipWithProfile: formatWindowTooltipWithProfile,
    mergeProfileProbeOutput: mergeProfileProbeOutput
  }
}
