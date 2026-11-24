// Pure 2D monitor arrangement, logical sizing, magnetic snapping, and scale helpers.

function isArrayLike(val) {
  return Boolean(val && typeof val === "object" && typeof val.length === "number")
}

function _gcdInt(a, b) {
  var x = Math.abs(Math.round(Number(a) || 0))
  var y = Math.abs(Math.round(Number(b) || 0))
  while (y) {
    var t = x % y
    x = y
    y = t
  }
  return x
}

function _formatScaleStr(n) {
  var val = Number(n)
  if (!isFinite(val) || val <= 0) return "1"
  return String(Number(val.toFixed(4)))
}

function cleanMonitorScale(scale, width, height) {
  var requested = Number(scale)
  var w = Math.round(Number(width) || 0)
  var h = Math.round(Number(height) || 0)
  if (!isFinite(requested) || requested <= 0 || w <= 0 || h <= 0) return "1"

  var divisor = _gcdInt(w * 120, h * 120)
  if (divisor <= 0) return _formatScaleStr(requested)
  var units = Math.max(1, Math.round(requested * 120))
  if (units > divisor) units = divisor
  while (divisor % units !== 0) units++
  return _formatScaleStr(units / 120)
}

function availableMonitorScales(width, height, currentScale) {
  var base = ["1", "1.25", "1.5", "1.6", "1.75", "2", "2.5", "3"]
  var cur = Number(currentScale)
  if (isFinite(cur) && cur > 0) base.push(_formatScaleStr(cur))

  var byValue = {}
  for (var i = 0; i < base.length; i++) {
    var req = Number(base[i])
    var effStr = cleanMonitorScale(req, width, height)
    var eff = Number(effStr)
    if (!isFinite(eff) || eff <= 0) continue
    var dist = Math.abs(req - eff)
    if (!byValue[effStr] || dist < byValue[effStr].dist) {
      byValue[effStr] = {
        value: effStr,
        scale: eff,
        label: Math.round(eff * 100) + "%",
        dist: dist
      }
    }
  }

  var list = []
  var keys = Object.keys(byValue)
  for (var k = 0; k < keys.length; k++) {
    var entry = byValue[keys[k]]
    list.push({ value: entry.value, scale: entry.scale, label: entry.label })
  }
  list.sort(function(a, b) { return a.scale - b.scale })
  return list
}

function parseMonitorMode(modeStr, fallbackW, fallbackH, fallbackHz) {
  var fw = Math.max(320, Math.round(Number(fallbackW) || 1920))
  var fh = Math.max(200, Math.round(Number(fallbackH) || 1080))
  var fhz = Number(fallbackHz)
  if (!isFinite(fhz) || fhz <= 0) fhz = 60

  var raw = String(modeStr === undefined || modeStr === null ? "" : modeStr).trim()
  if (!raw || raw.toLowerCase() === "preferred") {
    return { mode: "preferred", width: fw, height: fh, hz: fhz }
  }

  var m = /^(\d{3,5})x(\d{3,5})(?:@(\d+(?:\.\d+)?))?(?:hz)?$/i.exec(raw)
  if (!m) {
    return { mode: "preferred", width: fw, height: fh, hz: fhz }
  }
  var mw = Math.max(320, parseInt(m[1], 10))
  var mh = Math.max(200, parseInt(m[2], 10))
  var mhzStr = m[3] ? m[3] : String(Number(fhz.toFixed(2)))
  var mhz = Number(mhzStr)
  if (!isFinite(mhz) || mhz <= 0) mhz = fhz
  return {
    mode: mw + "x" + mh + "@" + mhzStr,
    width: mw,
    height: mh,
    hz: mhz
  }
}

function monitorLogicalSizeForSpec(m) {
  if (!m || typeof m !== "object") return { w: 1920, h: 1080 }
  var parsed = parseMonitorMode(m.mode, m.width, m.height, m.refreshRate)
  var scale = Number(m.scale)
  if (!isFinite(scale) || scale <= 0) scale = 1
  var w = Math.max(120, Math.floor(parsed.width / scale))
  var h = Math.max(120, Math.floor(parsed.height / scale))
  var tr = ((Math.round(Number(m.transform) || 0) % 4) + 4) % 4
  if (tr % 2 === 1) {
    var tmp = w
    w = h
    h = tmp
  }
  return { w: w, h: h }
}

function _axisGap(a1, a2, b1, b2) {
  return Math.max(0, Math.max(a1, b1) - Math.min(a2, b2))
}

function _axisOverlap(a1, a2, b1, b2) {
  return Math.min(a2, b2) - Math.max(a1, b1)
}

function snapMonitorRect(movingRect, otherRects, threshold) {
  if (!movingRect || typeof movingRect !== "object") {
    return { x: 0, y: 0, snappedX: false, snappedY: false }
  }
  var thresh = (typeof threshold === "number" && threshold >= 0) ? threshold : 72
  var mx = Math.round(Number(movingRect.x) || 0)
  var my = Math.round(Number(movingRect.y) || 0)
  var mw = Math.max(120, Math.round(Number(movingRect.w) || 1920))
  var mh = Math.max(120, Math.round(Number(movingRect.h) || 1080))

  var bestX = mx
  var bestXDist = thresh + 1
  var snappedX = false
  var bestY = my
  var bestYDist = thresh + 1
  var snappedY = false

  var others = isArrayLike(otherRects) ? otherRects : []
  for (var i = 0; i < others.length; i++) {
    var o = others[i]
    if (!o || o.enabled === false) continue
    var ox = Math.round(Number(o.x) || 0)
    var oy = Math.round(Number(o.y) || 0)
    var ow = Math.max(120, Math.round(Number(o.w || o.logicalW) || 1920))
    var oh = Math.max(120, Math.round(Number(o.h || o.logicalH) || 1080))

    var yGap = _axisGap(my, my + mh, oy, oy + oh)
    if (yGap <= thresh * 2) {
      var xCandidates = [
        ox + ow,
        ox - mw,
        ox,
        ox + ow - mw,
        ox + Math.round((ow - mw) / 2)
      ]
      for (var xi = 0; xi < xCandidates.length; xi++) {
        var dx = Math.abs(xCandidates[xi] - mx)
        if (dx <= thresh && dx < bestXDist) {
          bestXDist = dx
          bestX = xCandidates[xi]
          snappedX = true
        }
      }
    }

    var xGap = _axisGap(mx, mx + mw, ox, ox + ow)
    if (xGap <= thresh * 2) {
      var yCandidates = [
        oy + oh,
        oy - mh,
        oy,
        oy + oh - mh,
        oy + Math.round((oh - mh) / 2)
      ]
      for (var yi = 0; yi < yCandidates.length; yi++) {
        var dy = Math.abs(yCandidates[yi] - my)
        if (dy <= thresh && dy < bestYDist) {
          bestYDist = dy
          bestY = yCandidates[yi]
          snappedY = true
        }
      }
    }
  }

  return { x: bestX, y: bestY, snappedX: snappedX, snappedY: snappedY }
}

function _cloneShallow(obj) {
  var copy = {}
  if (!obj || typeof obj !== "object") return copy
  var keys = Object.keys(obj)
  for (var i = 0; i < keys.length; i++) copy[keys[i]] = obj[keys[i]]
  return copy
}

function _rectsStrictlyOverlap(a, b) {
  return _axisOverlap(a.x, a.x + a.w, b.x, b.x + b.w) > 0
    && _axisOverlap(a.y, a.y + a.h, b.y, b.y + b.h) > 0
}

function _rectsShareEdge(a, b) {
  var xo = _axisOverlap(a.x, a.x + a.w, b.x, b.x + b.w)
  var yo = _axisOverlap(a.y, a.y + a.h, b.y, b.y + b.h)
  var xg = _axisGap(a.x, a.x + a.w, b.x, b.x + b.w)
  var yg = _axisGap(a.y, a.y + a.h, b.y, b.y + b.h)
  return (xg === 0 && yo >= 1) || (yg === 0 && xo >= 1)
}

function _resolveMonitorOverlaps(rects) {
  for (var pass = 0; pass < 32; pass++) {
    var movedAny = false
    for (var i = 0; i < rects.length; i++) {
      for (var j = i + 1; j < rects.length; j++) {
        var a = rects[i]
        var b = rects[j]
        if (!_rectsStrictlyOverlap(a, b)) continue
        var shifts = [
          { dx: a.x - b.w - b.x, dy: 0 },
          { dx: a.x + a.w - b.x, dy: 0 },
          { dx: 0, dy: a.y - b.h - b.y },
          { dx: 0, dy: a.y + a.h - b.y }
        ]
        var best = shifts[0]
        var bestCost = Math.abs(best.dx) + Math.abs(best.dy)
        for (var s = 1; s < shifts.length; s++) {
          var cost = Math.abs(shifts[s].dx) + Math.abs(shifts[s].dy)
          if (cost < bestCost) {
            bestCost = cost
            best = shifts[s]
          }
        }
        b.x += best.dx
        b.y += best.dy
        movedAny = true
      }
    }
    if (!movedAny) break
  }
}

function normalizeMonitorLayout(monitors, movedKey) {
  var src = isArrayLike(monitors) ? monitors : []
  var out = []
  var movedNorm = String(movedKey || "")
  var enabledRects = []

  for (var i = 0; i < src.length; i++) {
    var item = _cloneShallow(src[i])
    var sz = monitorLogicalSizeForSpec(item)
    item.logicalW = sz.w
    item.logicalH = sz.h
    item.x = Math.round(Number(item.x) || 0)
    item.y = Math.round(Number(item.y) || 0)
    out.push(item)
    if (item.enabled !== false) {
      var key = String(item.matchKey || item.name || ("m" + i))
      enabledRects.push({
        ref: item,
        x: item.x,
        y: item.y,
        w: sz.w,
        h: sz.h,
        isMoved: movedNorm !== "" && (key === movedNorm || String(item.name || "") === movedNorm)
      })
    }
  }

  if (enabledRects.length === 0) return out

  // Keep un-moved monitors earlier so the actively dragged monitor yields around anchors.
  enabledRects.sort(function(a, b) {
    if (a.isMoved !== b.isMoved) return a.isMoved ? 1 : -1
    if (a.x !== b.x) return a.x - b.x
    return a.y - b.y
  })

  _resolveMonitorOverlaps(enabledRects)

  // Connect all enabled monitors into one gapless edge-sharing cluster.
  var cluster = [enabledRects[0]]
  var remaining = enabledRects.slice(1)

  while (remaining.length > 0) {
    var attachedIdx = -1
    for (var r = 0; r < remaining.length; r++) {
      for (var c = 0; c < cluster.length; c++) {
        if (_rectsShareEdge(cluster[c], remaining[r])) {
          attachedIdx = r
          break
        }
      }
      if (attachedIdx >= 0) break
    }

    if (attachedIdx >= 0) {
      cluster.push(remaining.splice(attachedIdx, 1)[0])
      continue
    }

    var bestR = 0
    var bestDx = 0
    var bestDy = 0
    var bestScore = Infinity
    for (var rr = 0; rr < remaining.length; rr++) {
      var b = remaining[rr]
      for (var cc = 0; cc < cluster.length; cc++) {
        var a = cluster[cc]
        var xo = _axisOverlap(a.x, a.x + a.w, b.x, b.x + b.w)
        var yo = _axisOverlap(a.y, a.y + a.h, b.y, b.y + b.h)

        var candShifts = []
        var syHoriz = 0
        if (yo < 1) {
          syHoriz = (b.y + b.h / 2 < a.y + a.h / 2) ? (a.y + 1 - (b.y + b.h)) : (a.y + a.h - 1 - b.y)
          var snapTop = a.y - b.y
          if (Math.abs(snapTop) < Math.abs(syHoriz) + 40) syHoriz = snapTop
        }
        candShifts.push({
          dx: (b.x + b.w / 2 < a.x + a.w / 2) ? (a.x - b.w - b.x) : (a.x + a.w - b.x),
          dy: syHoriz
        })

        var sxVert = 0
        if (xo < 1) {
          sxVert = (b.x + b.w / 2 < a.x + a.w / 2) ? (a.x + 1 - (b.x + b.w)) : (a.x + a.w - 1 - b.x)
          var snapLeft = a.x - b.x
          if (Math.abs(snapLeft) < Math.abs(sxVert) + 40) sxVert = snapLeft
        }
        candShifts.push({
          dx: sxVert,
          dy: (b.y + b.h / 2 < a.y + a.h / 2) ? (a.y - b.h - b.y) : (a.y + a.h - b.y)
        })

        for (var cs = 0; cs < candShifts.length; cs++) {
          var cand = { x: b.x + candShifts[cs].dx, y: b.y + candShifts[cs].dy, w: b.w, h: b.h }
          var collides = false
          for (var chk = 0; chk < cluster.length; chk++) {
            if (_rectsStrictlyOverlap(cand, cluster[chk])) {
              collides = true
              break
            }
          }
          var dist = Math.hypot(candShifts[cs].dx, candShifts[cs].dy) + (collides ? 100000 : 0)
          if (dist < bestScore) {
            bestScore = dist
            bestR = rr
            bestDx = candShifts[cs].dx
            bestDy = candShifts[cs].dy
          }
        }
      }
    }

    var target = remaining.splice(bestR, 1)[0]
    target.x += Math.round(bestDx)
    target.y += Math.round(bestDy)
    cluster.push(target)
    _resolveMonitorOverlaps(cluster)
  }

  var minX = enabledRects[0].x
  var minY = enabledRects[0].y
  for (var k = 1; k < enabledRects.length; k++) {
    if (enabledRects[k].x < minX) minX = enabledRects[k].x
    if (enabledRects[k].y < minY) minY = enabledRects[k].y
  }

  for (var u = 0; u < enabledRects.length; u++) {
    var rec = enabledRects[u]
    rec.ref.x = Math.round(rec.x - minX)
    rec.ref.y = Math.round(rec.y - minY)
  }

  return out
}

function computeCanvasProjection(monitors, canvasW, canvasH, padPx) {
  var cw = Math.max(160, Number(canvasW) || 640)
  var ch = Math.max(120, Number(canvasH) || 240)
  var pad = (typeof padPx === "number" && padPx >= 0) ? padPx : 36
  var list = isArrayLike(monitors) ? monitors : []

  var minX = Infinity
  var minY = Infinity
  var maxX = -Infinity
  var maxY = -Infinity
  var hasEnabled = false

  for (var i = 0; i < list.length; i++) {
    var m = list[i]
    if (!m || m.enabled === false) continue
    var sz = monitorLogicalSizeForSpec(m)
    var x = Math.round(Number(m.x) || 0)
    var y = Math.round(Number(m.y) || 0)
    if (x < minX) minX = x
    if (y < minY) minY = y
    if (x + sz.w > maxX) maxX = x + sz.w
    if (y + sz.h > maxY) maxY = y + sz.h
    hasEnabled = true
  }

  if (!hasEnabled) {
    minX = 0
    minY = 0
    maxX = 1920
    maxY = 1200
  }

  var bboxW = Math.max(1, maxX - minX)
  var bboxH = Math.max(1, maxY - minY)
  var availW = Math.max(80, cw - pad * 2)
  var availH = Math.max(60, ch - pad * 2)
  var spanW = bboxW + Math.max(800, bboxW * 0.22)
  var spanH = bboxH + Math.max(500, bboxH * 0.22)
  var scale = Math.max(0.025, Math.min(0.14, Math.min(availW / spanW, availH / spanH)))

  var offsetX = (cw - bboxW * scale) / 2 - minX * scale
  var offsetY = (ch - bboxH * scale) / 2 - minY * scale

  return {
    scale: scale,
    originX: offsetX,
    originY: offsetY,
    bboxW: bboxW,
    bboxH: bboxH,
    minX: minX,
    minY: minY
  }
}

function monitorsStateChanged(draft, baseline) {
  var a = isArrayLike(draft) ? draft : []
  var b = isArrayLike(baseline) ? baseline : []
  if (a.length !== b.length) return true

  var byKey = {}
  for (var i = 0; i < b.length; i++) {
    var bm = b[i]
    if (!bm) continue
    var bk = String(bm.matchKey || bm.name || i)
    byKey[bk] = bm
  }

  for (var j = 0; j < a.length; j++) {
    var am = a[j]
    if (!am) return true
    var ak = String(am.matchKey || am.name || j)
    var ref = byKey[ak]
    if (!ref) return true
    if ((am.enabled !== false) !== (ref.enabled !== false)) return true
    if (Math.round(Number(am.x) || 0) !== Math.round(Number(ref.x) || 0)) return true
    if (Math.round(Number(am.y) || 0) !== Math.round(Number(ref.y) || 0)) return true
    var ta = ((Math.round(Number(am.transform) || 0) % 4) + 4) % 4
    var tb = ((Math.round(Number(ref.transform) || 0) % 4) + 4) % 4
    if (ta !== tb) return true
    if (String(am.mode || "preferred") !== String(ref.mode || "preferred")) return true
    if (Math.abs((Number(am.scale) || 1) - (Number(ref.scale) || 1)) > 0.002) return true
  }
  return false
}

if (typeof module !== "undefined") {
  module.exports = {
    isArrayLike: isArrayLike,
    cleanMonitorScale: cleanMonitorScale,
    availableMonitorScales: availableMonitorScales,
    parseMonitorMode: parseMonitorMode,
    monitorLogicalSizeForSpec: monitorLogicalSizeForSpec,
    snapMonitorRect: snapMonitorRect,
    normalizeMonitorLayout: normalizeMonitorLayout,
    computeCanvasProjection: computeCanvasProjection,
    monitorsStateChanged: monitorsStateChanged
  }
}
