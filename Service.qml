import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import "TaskbarModel.js" as TaskbarModel
import "js/SnapLayoutMath.js" as SnapLayoutMath
import "js/WindowActions.js" as WindowActions

Item {
  id: root

  property var shell: null
  property var manifest: null

  property var hyprSettings: TaskbarModel.defaultHyprSettings()
  readonly property bool ultrawideLayout: root.hyprSettings.ultrawide_layout === true

  property var layoutsConfig: SnapLayoutMath.DEFAULT_LAYOUTS_CONFIG
  readonly property int cardW: Number(layoutsConfig.cardW) || 84
  readonly property int cardH: Number(layoutsConfig.cardH) || 52
  readonly property int cardGap: Number(layoutsConfig.cardGap) || 10
  readonly property int pillPadX: Number(layoutsConfig.padX) || 14
  readonly property int pillPadY: Number(layoutsConfig.padY) || 12
  readonly property int topMargin: Number(layoutsConfig.topMargin) || 10
  readonly property var baseLayouts: TaskbarModel.isArrayLike(layoutsConfig.layouts) ? layoutsConfig.layouts : SnapLayoutMath.DEFAULT_LAYOUTS_CONFIG.layouts
  readonly property bool effectiveUltrawide: (root.snapState.open && root.snapState.uw !== null && root.snapState.uw !== undefined)
    ? root.snapState.uw
    : root.ultrawideLayout
  readonly property var layouts: (root.effectiveUltrawide && TaskbarModel.isArrayLike(layoutsConfig.ultrawideLayout) && layoutsConfig.ultrawideLayout.length > 0)
    ? root.baseLayouts.concat([layoutsConfig.ultrawideLayout])
    : root.baseLayouts

  readonly property string statePath: (Quickshell.env("XDG_RUNTIME_DIR") || Quickshell.env("XDG_CACHE_HOME") || (Commons.Color.home + "/.cache")) + "/omarchy-windaase-snap.json"
  property var snapState: emptyState()

  readonly property string altTabStatePath: (Quickshell.env("XDG_RUNTIME_DIR") || Quickshell.env("XDG_CACHE_HOME") || (Commons.Color.home + "/.cache")) + "/omarchy-windaase-alttab.json"
  property var altTabState: emptyAltTabState()

  property bool identifyActive: false
  property var identifyMap: ({})

  Commons.Translations {
    id: serviceStrings
    directory: Qt.resolvedUrl("i18n")
  }

  readonly property var terminalEntries: TaskbarModel.collectTerminalEntries(DesktopEntries.applications.values)

  function entryForAppId(appId) {
    var entry = DesktopEntries.heuristicLookup(appId)
    if (entry) return entry
    var id = TaskbarModel.claimingEntryId(appId, root.terminalEntries)
    return id ? DesktopEntries.byId(id) : null
  }

  function iconSourceFor(entry, fallbackId) {
    return TaskbarModel.resolveIconSource(
      entry,
      fallbackId,
      function(name) { return Quickshell.iconPath(name, true) },
      function(p) { return Util.fileUrl(p) }
    )
  }

  function collectAssistCandidates(snappedAddr, workspaceId) {
    var list = []
    var toplevels = Hyprland.toplevels.values
    for (var i = 0; i < toplevels.length; i++) {
      var win = WindowActions.normalizeToplevelWindow(toplevels[i], {
        skipUnmapped: true,
        resolveEntry: root.entryForAppId,
        resolveIcon: root.iconSourceFor
      })
      if (win) list.push(win)
    }
    return SnapLayoutMath.filterSnapAssistCandidates(list, snappedAddr, workspaceId)
  }

  function loadLayouts(raw) {
    root.layoutsConfig = SnapLayoutMath.parseLayoutsConfig(raw)
  }

  function validAddress(addr) {
    return TaskbarModel.normalizeAddress(addr)
  }

  function emptyState() {
    return { open: false, mode: "drag", monitor: "", card: -1, zone: -1, px: 0, py: 0, pw: 0, ph: 0, addr: "", border: 2, titlebar: 30, ws: -1, uw: null, assist: null, go: 8, gi: 8, axis: "x", p1: 50, p2: 50 }
  }

  function parseState(raw) {
    try {
      var parsed = JSON.parse(String(raw || ""))
      if (parsed && typeof parsed === "object") {
        var mode = parsed.mode === "assist"
          ? "assist"
          : (parsed.mode === "click" ? "click" : (parsed.mode === "resize" ? "resize" : "drag"))
        root.snapState = {
          open: !!parsed.open,
          mode: mode,
          monitor: String(parsed.monitor || ""),
          card: typeof parsed.card === "number" ? parsed.card : -1,
          zone: typeof parsed.zone === "number" ? parsed.zone : -1,
          px: Number(parsed.px) || 0,
          py: Number(parsed.py) || 0,
          pw: Number(parsed.pw) || 0,
          ph: Number(parsed.ph) || 0,
          addr: validAddress(parsed.addr),
          border: typeof parsed.border === "number" ? Math.max(0, parsed.border) : 2,
          titlebar: typeof parsed.titlebar === "number" ? Math.max(0, parsed.titlebar) : 30,
          ws: typeof parsed.ws === "number" ? parsed.ws : -1,
          uw: typeof parsed.uw === "boolean" ? parsed.uw : null,
          assist: typeof parsed.assist === "boolean" ? parsed.assist : null,
          go: typeof parsed.go === "number" ? Math.max(0, Math.round(parsed.go)) : 8,
          gi: typeof parsed.gi === "number" ? Math.max(0, Math.round(parsed.gi)) : 8,
          axis: parsed.axis === "y" ? "y" : "x",
          p1: typeof parsed.p1 === "number" ? Math.max(1, Math.min(99, Math.round(parsed.p1))) : 50,
          p2: typeof parsed.p2 === "number" ? Math.max(1, Math.min(99, Math.round(parsed.p2))) : 50
        }
        return
      }
    } catch (e) {}
    root.snapState = emptyState()
  }

  function closeState() {
    root.snapState = emptyState()
    Util.execArgv(["hyprctl", "eval", "require(\"hypr.windaase\").cancel_snap_overlay()"])
  }

  function applyZoneFromClick(z, monitorName) {
    if (!z) {
      root.closeState()
      return
    }
    var rx = Number(z.rx)
    var ry = Number(z.ry)
    var rw = Number(z.rw)
    var rh = Number(z.rh)
    if (!isFinite(rx) || !isFinite(ry) || !isFinite(rw) || !isFinite(rh)) {
      root.closeState()
      return
    }
    var addr = root.validAddress(root.snapState.addr)
    var safeMon = /^[A-Za-z0-9_.:-]{1,64}$/.test(monitorName) ? monitorName : ""
    // Clear open state before Hyprland shifts focus so HyprlandFocusGrab doesn't emit a redundant cancel.
    root.snapState = emptyState()
    Util.execArgv([
      "hyprctl",
      "eval",
      "require(\"hypr.windaase\").apply_click_zone(\"" + addr + "\", \"" + safeMon + "\", " + rx + ", " + ry + ", " + rw + ", " + rh + ", " + (z.max ? "true" : "false") + ")"
    ])
  }

  function applyAssistWindow(candidate) {
    var targetAddr = candidate ? root.validAddress(candidate.address) : ""
    if (!targetAddr) {
      root.closeState()
      return
    }
    root.snapState = emptyState()
    Util.execArgv([
      "hyprctl",
      "eval",
      "require(\"hypr.windaase\").apply_assist_addr(\"" + targetAddr + "\")"
    ])
  }

  function emptyAltTabState() {
    return { open: false, monitor: "", selected: 0, addrs: [] }
  }

  function parseAltTabState(raw) {
    try {
      var parsed = JSON.parse(String(raw || ""))
      if (parsed && typeof parsed === "object") {
        var cleanAddrs = []
        var rawAddrs = TaskbarModel.isArrayLike(parsed.addrs) ? parsed.addrs : []
        for (var i = 0; i < rawAddrs.length; i++) {
          var na = root.validAddress(rawAddrs[i])
          if (na) cleanAddrs.push(na)
        }
        var sel = typeof parsed.selected === "number" ? Math.round(parsed.selected) : 0
        if (cleanAddrs.length === 0) sel = 0
        else sel = Math.max(0, Math.min(cleanAddrs.length - 1, sel))
        root.altTabState = {
          open: !!parsed.open && cleanAddrs.length > 0,
          monitor: String(parsed.monitor || ""),
          selected: sel,
          addrs: cleanAddrs
        }
        return
      }
    } catch (e) {}
    root.altTabState = emptyAltTabState()
  }

  // Alt+Tab is only opened by hypr.windaase, so routing close/commit through hyprctl eval keeps session state atomic with Alt release.
  function closeAltTab() {
    root.altTabState = emptyAltTabState()
    Util.execArgv(["hyprctl", "eval", "require(\"hypr.windaase\").alt_tab_cancel()"])
  }

  function collectAltTabWindows(addrs) {
    if (!TaskbarModel.isArrayLike(addrs) || addrs.length === 0) return []
    var toplevels = Hyprland.toplevels.values
    var byAddr = {}
    for (var i = 0; i < toplevels.length; i++) {
      var tl = toplevels[i]
      if (!tl) continue
      var norm = root.validAddress(tl.address || (tl.lastIpcObject && tl.lastIpcObject.address)).toLowerCase()
      if (norm) byAddr[norm] = tl
    }

    var out = []
    for (var j = 0; j < addrs.length; j++) {
      var addr = root.validAddress(addrs[j])
      if (!addr) continue
      var tlMatch = byAddr[addr.toLowerCase()]
      if (!tlMatch) continue
      var normWin = WindowActions.normalizeToplevelWindow(tlMatch, {
        requireWayland: false,
        requireAppId: false,
        resolveEntry: root.entryForAppId,
        resolveIcon: root.iconSourceFor
      })
      if (normWin) out.push(normWin)
    }
    return out
  }

  function activateAltTabWindow(win) {
    var addr = win ? root.validAddress(win.address) : ""
    if (!addr) {
      root.closeAltTab()
      return
    }
    root.altTabState = emptyAltTabState()
    Util.execArgv(["hyprctl", "eval", "require(\"hypr.windaase\").alt_tab_commit_addr(\"" + addr + "\")"])
  }

  function showMonitorIdentify(items) {
    Hyprland.refreshMonitors()
    var next = {}
    var count = TaskbarModel.isArrayLike(items) ? items.length : 0
    for (var i = 0; i < count; i++) {
      var it = items[i]
      if (it && it.name) next[String(it.name)] = it
    }
    root.identifyMap = next
    root.identifyActive = Object.keys(next).length > 0
    if (root.identifyActive) identifyTimer.restart()
  }

  Timer {
    id: identifyTimer
    interval: 3500
    repeat: false
    onTriggered: root.identifyActive = false
  }

  Component.onCompleted: {
    root.loadLayouts(layoutsFile.text())
    root.hyprSettings = TaskbarModel.parseHyprSettings(hyprSettingsFile.text())
    Quickshell.execDetached(["bash", "-c", "[ -f " + Util.shellQuote(root.statePath) + " ] || printf '{\"open\":false}\\n' > " + Util.shellQuote(root.statePath) + "; [ -f " + Util.shellQuote(root.altTabStatePath) + " ] || printf '{\"open\":false}\\n' > " + Util.shellQuote(root.altTabStatePath)])
    Qt.callLater(function() {
      stateFile.reload()
      altTabStateFile.reload()
    })
  }

  Component.onDestruction: {
    identifyTimer.stop()
    root.identifyActive = false
    root.snapState = emptyState()
    root.altTabState = emptyAltTabState()
  }

  FileView {
    id: hyprSettingsFile
    path: Commons.Color.home + "/.config/omarchy/windaase.json"
    watchChanges: true
    blockLoading: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.hyprSettings = TaskbarModel.parseHyprSettings(text())
    onLoadFailed: root.hyprSettings = TaskbarModel.defaultHyprSettings()
  }

  FileView {
    id: layoutsFile
    path: String(Qt.resolvedUrl("layouts.json")).replace(/^file:\/\//, "")
    watchChanges: true
    blockLoading: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.loadLayouts(text())
    onLoadFailed: {}
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parseState(text())
    onLoadFailed: {}
  }

  FileView {
    id: altTabStateFile
    path: root.altTabStatePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parseAltTabState(text())
    onLoadFailed: {}
  }

  AppGrid {
    id: appGrid
  }

  DisplaySettingsModal {
    id: displayModal
    onIdentifyRequested: function(items) { root.showMonitorIdentify(items) }
  }

  ShellIpc {
    target: "riisager.windaase"

    function apps(): void {
      displayModal.close()
      if (root.snapState.open) root.closeState()
      if (root.altTabState.open) root.closeAltTab()
      appGrid.toggle()
    }

    function settings(): void {
      Commons.IpcRegistry.call("riisager.windaase.bar", "toggleSettings", [])
    }

    function displays(): void {
      appGrid.close()
      if (root.snapState.open) root.closeState()
      if (root.altTabState.open) root.closeAltTab()
      displayModal.toggle()
    }

    function identify(): void {
      if (displayModal.liveMonitors && displayModal.liveMonitors.length > 0) {
        displayModal.triggerIdentify()
        return
      }
      var list = []
      var screens = Quickshell.screens || []
      for (var i = 0; i < screens.length; i++) {
        var s = screens[i]
        if (!s || !s.name) continue
        list.push({
          name: String(s.name),
          number: i + 1,
          label: TaskbarModel.sanitizePlainLabel(String(s.name), 48),
          detail: (s.width > 0 && s.height > 0)
            ? (Commons.I18n.formatNumber(Math.round(s.width)) + " × " + Commons.I18n.formatNumber(Math.round(s.height)))
            : ""
        })
      }
      root.showMonitorIdentify(list)
    }
  }

  SnapOverlayWindow {
    strings: serviceStrings
    snapState: root.snapState
    layouts: root.layouts
    cardW: root.cardW
    cardH: root.cardH
    cardGap: root.cardGap
    pillPadX: root.pillPadX
    pillPadY: root.pillPadY
    topMargin: root.topMargin
    resolveAssistCandidates: root.collectAssistCandidates
    onCloseRequested: root.closeState()
    onApplyZoneRequested: function(zone, monName) { root.applyZoneFromClick(zone, monName) }
    onApplyAssistRequested: function(cand) { root.applyAssistWindow(cand) }
  }

  AltTabOverlayWindow {
    strings: serviceStrings
    altTabState: root.altTabState
    resolveAltTabWindows: root.collectAltTabWindows
    onCloseRequested: root.closeAltTab()
    onWindowPicked: function(w) { root.activateAltTabWindow(w) }
  }

  MonitorIdentifyOverlay {
    identifyActive: root.identifyActive
    identifyMap: root.identifyMap
  }
}
