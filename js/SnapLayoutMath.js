// Pure Snap Layouts geometry, keyboard navigation, Snap Assist filtering, and Snap Group detection.

var DEFAULT_LAYOUTS_CONFIG = {
  cardW: 84,
  cardH: 52,
  cardGap: 10,
  padX: 14,
  padY: 12,
  topMargin: 10,
  layouts: [
    [
      { rx: 0, ry: 0, rw: 0.5, rh: 1.0, max: false },
      { rx: 0.5, ry: 0, rw: 0.5, rh: 1.0, max: false }
    ],
    [
      { rx: 0, ry: 0, rw: 0.65, rh: 1.0, max: false },
      { rx: 0.65, ry: 0, rw: 0.35, rh: 1.0, max: false }
    ],
    [
      { rx: 0, ry: 0, rw: 0.5, rh: 1.0, max: false },
      { rx: 0.5, ry: 0, rw: 0.5, rh: 0.5, max: false },
      { rx: 0.5, ry: 0.5, rw: 0.5, rh: 0.5, max: false }
    ],
    [
      { rx: 0, ry: 0, rw: 0.3333333, rh: 1.0, max: false },
      { rx: 0.3333333, ry: 0, rw: 0.3333333, rh: 1.0, max: false },
      { rx: 0.6666667, ry: 0, rw: 0.3333333, rh: 1.0, max: false }
    ],
    [
      { rx: 0, ry: 0, rw: 0.5, rh: 0.5, max: false },
      { rx: 0.5, ry: 0, rw: 0.5, rh: 0.5, max: false },
      { rx: 0, ry: 0.5, rw: 0.5, rh: 0.5, max: false },
      { rx: 0.5, ry: 0.5, rw: 0.5, rh: 0.5, max: false }
    ],
    [
      { rx: 0, ry: 0, rw: 1.0, rh: 1.0, max: true }
    ]
  ],
  ultrawideLayout: [
    { rx: 0, ry: 0, rw: 0.25, rh: 1.0, max: false },
    { rx: 0.25, ry: 0, rw: 0.5, rh: 1.0, max: false },
    { rx: 0.75, ry: 0, rw: 0.25, rh: 1.0, max: false }
  ]
}

function isArrayLike(val) {
  return Boolean(val && typeof val === "object" && typeof val.length === "number")
}

function _normalizeAddress(value) {
  var s = String(value === undefined || value === null ? "" : value).trim()
  if (!s) return ""
  var m = /^(?:0[xX])?([0-9a-fA-F]{1,20})$/.exec(s)
  return m ? ("0x" + m[1]) : ""
}

function parseLayoutsConfig(raw) {
  try {
    var parsed = JSON.parse(String(raw || ""))
    if (parsed && Array.isArray(parsed.layouts) && parsed.layouts.length > 0) {
      return {
        cardW: Number(parsed.cardW) || DEFAULT_LAYOUTS_CONFIG.cardW,
        cardH: Number(parsed.cardH) || DEFAULT_LAYOUTS_CONFIG.cardH,
        cardGap: Number(parsed.cardGap) || DEFAULT_LAYOUTS_CONFIG.cardGap,
        padX: Number(parsed.padX) || DEFAULT_LAYOUTS_CONFIG.padX,
        padY: Number(parsed.padY) || DEFAULT_LAYOUTS_CONFIG.padY,
        topMargin: Number(parsed.topMargin) || DEFAULT_LAYOUTS_CONFIG.topMargin,
        layouts: parsed.layouts,
        ultrawideLayout: (Array.isArray(parsed.ultrawideLayout) && parsed.ultrawideLayout.length > 0)
          ? parsed.ultrawideLayout
          : DEFAULT_LAYOUTS_CONFIG.ultrawideLayout
      }
    }
  } catch (e) {}
  return DEFAULT_LAYOUTS_CONFIG
}

function computeZoneRect(z, screenW, screenH, reserved, gapOut, gapIn) {
  var res = isArrayLike(reserved) ? reserved : [0, 0, 0, 0]
  var rLeft = Number(res[0]) || 0
  var rTop = Number(res[1]) || 0
  var rRight = Number(res[2]) || 0
  var rBottom = Number(res[3]) || 0
  var go = gapOut !== undefined ? Number(gapOut) : 8
  var gi = gapIn !== undefined ? Number(gapIn) : 8
  var ax = rLeft + go
  var ay = rTop + go
  var aw = Number(screenW) - rLeft - rRight - go * 2
  var ah = Number(screenH) - rTop - rBottom - go * 2
  var x1 = ax + Math.round(z.rx * (aw + gi))
  var x2 = ax + Math.round((z.rx + z.rw) * (aw + gi)) - gi
  var y1 = ay + Math.round(z.ry * (ah + gi))
  var y2 = ay + Math.round((z.ry + z.rh) * (ah + gi)) - gi
  return { x: x1, y: y1, w: x2 - x1, h: y2 - y1, max: !!z.max }
}

function _zoneCenter(z) {
  var rx = Number(z && z.rx) || 0
  var ry = Number(z && z.ry) || 0
  var rw = Number(z && z.rw) || 0
  var rh = Number(z && z.rh) || 0
  return { cx: rx + rw / 2, cy: ry + rh / 2, rx: rx, ry: ry, rw: rw, rh: rh }
}

function _edgeZoneInCard(card, fromEdge, targetCy) {
  if (!isArrayLike(card) || card.length === 0) return 0
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
  var list = isArrayLike(layouts) ? layouts : []
  if (list.length === 0) return { card: -1, zone: -1 }
  var dir = String(direction || "").toLowerCase()
  var c = typeof cardIdx === "number" ? cardIdx : -1
  var z = typeof zoneIdx === "number" ? zoneIdx : -1
  if (c < 0 || c >= list.length || !isArrayLike(list[c]) || list[c].length === 0) {
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
  var list = isArrayLike(layouts) ? layouts : []
  var targetCard = Number(cardNumber) - 1
  if (!isFinite(targetCard) || targetCard < 0 || targetCard >= list.length) return null
  var card = list[targetCard]
  if (!isArrayLike(card) || card.length === 0) return null
  if (targetCard === currentCard) {
    var nextZ = (typeof currentZone === "number" && currentZone >= 0) ? ((currentZone + 1) % card.length) : 0
    return { card: targetCard, zone: nextZ }
  }
  return { card: targetCard, zone: 0 }
}

function filterSnapAssistCandidates(windows, snappedAddr, workspaceId) {
  var list = isArrayLike(windows) ? windows : []
  var excludeAddr = _normalizeAddress(snappedAddr).toLowerCase()
  var ws = Number(workspaceId)
  var out = []
  for (var i = 0; i < list.length; i++) {
    var win = list[i]
    if (!win) continue
    if (win.minimized === true) continue
    if (win.floating === false) continue
    if (win.fullscreen) continue
    if (ws >= 1 && win.workspaceId !== ws) continue
    var addr = _normalizeAddress(win.address).toLowerCase()
    if (!addr || (excludeAddr && addr === excludeAddr)) continue
    out.push(win)
  }
  return out
}

function detectSnapGroups(allWindows, targetWindows) {
  if (!isArrayLike(allWindows) || !isArrayLike(targetWindows) || targetWindows.length === 0) {
    return []
  }

  var candidates = []
  var byAddr = {}
  for (var i = 0; i < allWindows.length; i++) {
    var w = allWindows[i]
    if (!w || w.floating !== true || w.minimized || w.fullscreen) continue
    if (!(Number(w.workspaceId) >= 1)) continue
    var addr = _normalizeAddress(w.address).toLowerCase()
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
    var startAddr = _normalizeAddress(tw.address).toLowerCase()
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
    DEFAULT_LAYOUTS_CONFIG: DEFAULT_LAYOUTS_CONFIG,
    isArrayLike: isArrayLike,
    parseLayoutsConfig: parseLayoutsConfig,
    computeZoneRect: computeZoneRect,
    nextSnapZone: nextSnapZone,
    jumpToSnapCard: jumpToSnapCard,
    filterSnapAssistCandidates: filterSnapAssistCandidates,
    detectSnapGroups: detectSnapGroups
  }
}
