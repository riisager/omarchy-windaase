// Pure application filtering, fuzzy scoring, and launch command helpers for AppGrid.

function _normalizeId(value) {
  var id = String(value || "").trim()
  if (id.slice(-8) === ".desktop") id = id.slice(0, -8)
  return id
}

function parseHiddenEntryIds(rawText) {
  var map = {}
  var lines = String(rawText || "").split(/\r?\n/)
  for (var i = 0; i < lines.length; i++) {
    var id = _normalizeId(lines[i])
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
    var normId = _normalizeId(entry.id)
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

if (typeof module !== "undefined") {
  module.exports = {
    parseHiddenEntryIds: parseHiddenEntryIds,
    entryName: entryName,
    filterAndSortApps: filterAndSortApps,
    launchArgvForEntry: launchArgvForEntry
  }
}
