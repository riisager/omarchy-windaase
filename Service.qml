import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "TaskbarModel.js" as TaskbarModel

Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property var defaultLayoutsConfig: ({
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
  })

  property var hyprSettings: TaskbarModel.defaultHyprSettings()
  readonly property bool ultrawideLayout: root.hyprSettings.ultrawide_layout === true

  property var layoutsConfig: defaultLayoutsConfig
  readonly property int cardW: Number(layoutsConfig.cardW) || 84
  readonly property int cardH: Number(layoutsConfig.cardH) || 52
  readonly property int cardGap: Number(layoutsConfig.cardGap) || 10
  readonly property int pillPadX: Number(layoutsConfig.padX) || 14
  readonly property int pillPadY: Number(layoutsConfig.padY) || 12
  readonly property int topMargin: Number(layoutsConfig.topMargin) || 10
  readonly property var baseLayouts: Array.isArray(layoutsConfig.layouts) ? layoutsConfig.layouts : defaultLayoutsConfig.layouts
  readonly property bool effectiveUltrawide: (root.snapState.open && root.snapState.uw !== null && root.snapState.uw !== undefined)
    ? root.snapState.uw
    : root.ultrawideLayout
  readonly property var layouts: (root.effectiveUltrawide && Array.isArray(layoutsConfig.ultrawideLayout) && layoutsConfig.ultrawideLayout.length > 0)
    ? root.baseLayouts.concat([layoutsConfig.ultrawideLayout])
    : root.baseLayouts

  readonly property string statePath: (Quickshell.env("XDG_RUNTIME_DIR") || Quickshell.env("XDG_CACHE_HOME") || (Commons.Color.home + "/.cache")) + "/omarchy-windaase-snap.json"
  property var snapState: emptyState()

  readonly property string altTabStatePath: (Quickshell.env("XDG_RUNTIME_DIR") || Quickshell.env("XDG_CACHE_HOME") || (Commons.Color.home + "/.cache")) + "/omarchy-windaase-alttab.json"
  property var altTabState: emptyAltTabState()

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
      var tl = toplevels[i]
      if (!tl) continue
      var wl = tl.wayland || null
      if (wl && wl.parent) continue
      var ipc = tl.lastIpcObject || {}
      if (ipc.mapped === false) continue
      var appId = (wl && wl.appId) ? String(wl.appId) : (ipc["class"] ? String(ipc["class"]) : (ipc.initialClass ? String(ipc.initialClass) : ""))
      if (!appId) continue
      var entry = root.entryForAppId(appId)
      var ws = tl.workspace || null
      var wsName = (ws && ws.name) ? String(ws.name) : (ipc.workspace && ipc.workspace.name ? String(ipc.workspace.name) : "")
      var wsId = (ws && ws.id) ? Number(ws.id) : (ipc.workspace && ipc.workspace.id ? Number(ipc.workspace.id) : -1)
      var floating = !!ipc.floating
      var fullscreen = ipc.fullscreen ? Number(ipc.fullscreen) : (wl && wl.fullscreen ? 1 : 0)
      var appName = entry && entry.name ? entry.name : appId
      var title = (wl && wl.title) ? String(wl.title) : (ipc.title ? String(ipc.title) : appName)
      list.push({
        address: tl.address || ipc.address || "",
        workspaceId: wsId,
        minimized: TaskbarModel.isMinimizedWorkspace(wsName),
        floating: floating,
        fullscreen: fullscreen > 0,
        appName: appName,
        title: title,
        iconSource: root.iconSourceFor(entry, appId)
      })
    }
    return TaskbarModel.filterSnapAssistCandidates(list, snappedAddr, workspaceId)
  }

  function loadLayouts(raw) {
    try {
      var parsed = JSON.parse(String(raw || ""))
      if (parsed && Array.isArray(parsed.layouts) && parsed.layouts.length > 0) {
        root.layoutsConfig = {
          cardW: Number(parsed.cardW) || 84,
          cardH: Number(parsed.cardH) || 52,
          cardGap: Number(parsed.cardGap) || 10,
          padX: Number(parsed.padX) || 14,
          padY: Number(parsed.padY) || 12,
          topMargin: Number(parsed.topMargin) || 10,
          layouts: parsed.layouts,
          ultrawideLayout: (Array.isArray(parsed.ultrawideLayout) && parsed.ultrawideLayout.length > 0)
            ? parsed.ultrawideLayout
            : root.defaultLayoutsConfig.ultrawideLayout
        }
        return
      }
    } catch (e) {}
    root.layoutsConfig = root.defaultLayoutsConfig
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

  function emptyAltTabState() {
    return { open: false, monitor: "", selected: 0, addrs: [] }
  }

  function parseAltTabState(raw) {
    try {
      var parsed = JSON.parse(String(raw || ""))
      if (parsed && typeof parsed === "object") {
        var cleanAddrs = []
        var rawAddrs = Array.isArray(parsed.addrs) ? parsed.addrs : []
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
    if (!Array.isArray(addrs) || addrs.length === 0) return []
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
      var wl = tlMatch.wayland || null
      var ipc = tlMatch.lastIpcObject || {}
      var appId = (wl && wl.appId) ? String(wl.appId) : (ipc["class"] ? String(ipc["class"]) : (ipc.initialClass ? String(ipc.initialClass) : ""))
      var entry = appId ? root.entryForAppId(appId) : null
      var ws = tlMatch.workspace || null
      var wsName = (ws && ws.name) ? String(ws.name) : (ipc.workspace && ipc.workspace.name ? String(ipc.workspace.name) : "")
      var wsId = (ws && ws.id) ? Number(ws.id) : (ipc.workspace && ipc.workspace.id ? Number(ipc.workspace.id) : -1)
      var appName = (entry && entry.name) ? entry.name : appId
      var title = (wl && wl.title) ? String(wl.title) : (ipc.title ? String(ipc.title) : appName)
      out.push({
        address: addr,
        title: title,
        appName: appName,
        iconSource: root.iconSourceFor(entry, appId),
        workspaceId: wsId,
        minimized: TaskbarModel.isMinimizedWorkspace(wsName),
        pinned: !!ipc.pinned,
        toplevel: wl
      })
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

  Component.onCompleted: {
    root.loadLayouts(layoutsFile.text())
    root.hyprSettings = TaskbarModel.parseHyprSettings(hyprSettingsFile.text())
    Quickshell.execDetached(["bash", "-c", "[ -f " + Util.shellQuote(root.statePath) + " ] || printf '{\"open\":false}\\n' > " + Util.shellQuote(root.statePath) + "; [ -f " + Util.shellQuote(root.altTabStatePath) + " ] || printf '{\"open\":false}\\n' > " + Util.shellQuote(root.altTabStatePath)])
    Qt.callLater(function() {
      stateFile.reload()
      altTabStateFile.reload()
    })
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

  property bool identifyActive: false
  property var identifyMap: ({})

  function showMonitorIdentify(items) {
    Hyprland.refreshMonitors()
    var next = {}
    var count = (items && typeof items.length === "number") ? items.length : 0
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

  Component.onDestruction: {
    identifyTimer.stop()
    root.identifyActive = false
    root.snapState = emptyState()
    root.altTabState = emptyAltTabState()
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

  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: win
        required property var modelData
        screen: modelData

        readonly property var monitor: Hyprland.monitorFor(screen)
        readonly property string monitorName: monitor ? monitor.name : ""
        readonly property bool activeOnScreen: root.snapState.open && root.snapState.monitor === monitorName
        readonly property bool isClick: activeOnScreen && root.snapState.mode === "click"
        readonly property bool isAssist: activeOnScreen && root.snapState.mode === "assist"
        readonly property bool isResize: activeOnScreen && root.snapState.mode === "resize"
        readonly property bool surfaceReady: win.backingWindowVisible
          && !!screen
          && Math.abs(win.width - screen.width) <= 2
          && Math.abs(win.height - screen.height) <= 2
        readonly property bool clickInteractive: win.isClick && win.surfaceReady

        onBackingWindowVisibleChanged: {
          if (win.backingWindowVisible && win.clickInteractive) {
            Qt.callLater(function() { if (win && win.clickInteractive && snapKeyCatcher) snapKeyCatcher.forceActiveFocus() })
          }
        }
        onClickInteractiveChanged: {
          if (win.backingWindowVisible && win.clickInteractive) {
            Qt.callLater(function() { if (win && win.clickInteractive && snapKeyCatcher) snapKeyCatcher.forceActiveFocus() })
          }
        }

        property int clickSelectedCard: -1
        property int clickSelectedZone: -1
        property int assistSelectedIndex: -1

        readonly property int activeAssistWsId: root.snapState.ws >= 1
          ? root.snapState.ws
          : (monitor && monitor.activeWorkspace ? Number(monitor.activeWorkspace.id) : -1)
        readonly property var assistCandidates: win.isAssist
          ? root.collectAssistCandidates(root.snapState.addr, win.activeAssistWsId)
          : []

        onIsClickChanged: {
          if (win.isClick) {
            clickSelectedCard = 0
            clickSelectedZone = 0
          } else {
            clickSelectedCard = -1
            clickSelectedZone = -1
          }
        }

        function closeAssistIfEmpty() {
          if (win.isAssist && win.assistCandidates.length === 0) {
            root.closeState()
          }
        }

        onIsAssistChanged: {
          if (win.isAssist) {
            assistSelectedIndex = -1
            Qt.callLater(function() { if (win) win.closeAssistIfEmpty() })
          }
        }

        onAssistCandidatesChanged: {
          if (win.isAssist) {
            if (assistCandidates.length === 0) Qt.callLater(function() { if (win) win.closeAssistIfEmpty() })
            else if (assistSelectedIndex >= 0 && assistSelectedIndex >= assistCandidates.length) assistSelectedIndex = assistCandidates.length - 1
          }
        }

        function computeZoneRect(z) {
          var res = monitor && monitor.lastIpcObject && monitor.lastIpcObject.reserved ? monitor.lastIpcObject.reserved : [0, 0, 0, 0]
          var rLeft = res[0] || 0
          var rTop = res[1] || 0
          var rRight = res[2] || 0
          var rBottom = res[3] || 0
          var gapOut = root.snapState.go !== undefined ? root.snapState.go : 8
          var gapIn = root.snapState.gi !== undefined ? root.snapState.gi : 8
          var ax = rLeft + gapOut
          var ay = rTop + gapOut
          var aw = screen.width - rLeft - rRight - gapOut * 2
          var ah = screen.height - rTop - rBottom - gapOut * 2
          var x1 = ax + Math.round(z.rx * (aw + gapIn))
          var x2 = ax + Math.round((z.rx + z.rw) * (aw + gapIn)) - gapIn
          var y1 = ay + Math.round(z.ry * (ah + gapIn))
          var y2 = ay + Math.round((z.ry + z.rh) * (ah + gapIn)) - gapIn
          return { x: x1, y: y1, w: x2 - x1, h: y2 - y1, max: !!z.max }
        }

        function applyZoneFromClick(z) {
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
          var safeMon = /^[A-Za-z0-9_.:-]{1,64}$/.test(win.monitorName) ? win.monitorName : ""
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

        readonly property var previewRect: {
          if (!activeOnScreen || isResize) return { visible: false, x: 0, y: 0, w: 0, h: 0 }
          if (isClick) {
            if (clickSelectedCard >= 0 && clickSelectedZone >= 0 && root.layouts[clickSelectedCard] && root.layouts[clickSelectedCard][clickSelectedZone]) {
              var z = root.layouts[clickSelectedCard][clickSelectedZone]
              var r = computeZoneRect(z)
              return { visible: true, x: r.x, y: r.y, w: r.w, h: r.h }
            }
            return { visible: false, x: 0, y: 0, w: 0, h: 0 }
          }
          if (isAssist && root.snapState.pw > 0 && root.snapState.ph > 0) {
            return { visible: true, x: root.snapState.px, y: root.snapState.py, w: root.snapState.pw, h: root.snapState.ph }
          }
          if (root.snapState.card >= 0 && root.snapState.zone >= 0 && root.snapState.pw > 0 && root.snapState.ph > 0) {
            return { visible: true, x: root.snapState.px, y: root.snapState.py, w: root.snapState.pw, h: root.snapState.ph }
          }
          return { visible: false, x: 0, y: 0, w: 0, h: 0 }
        }

        // Map fullscreen layer surface only while active or fading out (0 idle VRAM/surfaces).
        visible: win.activeOnScreen || previewBox.opacity > 0 || pillContainer.opacity > 0 || assistCard.opacity > 0 || resizeOverlay.opacity > 0
        color: "transparent"
        WlrLayershell.namespace: "omarchy-windaase-snap"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: win.clickInteractive ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0

        anchors {
          top: true
          bottom: true
          left: true
          right: true
        }

        mask: Region {
          item: (win.isAssist && assistCard.shown) ? assistCard : ((win.isClick && pillContainer.shown) ? pillContainer : null)
        }

        HyprlandFocusGrab {
          active: win.clickInteractive && win.backingWindowVisible
          windows: [win]
          onCleared: if (win.isClick) root.closeState()
        }

        Item {
          id: snapKeyCatcher
          anchors.fill: parent
          focus: win.clickInteractive

          Keys.onPressed: function(event) {
            if (!win.clickInteractive) return
            if (event.key === Qt.Key_Escape) {
              root.closeState()
              event.accepted = true
              return
            }

            var rkey = Util.readingKey(event)

            if (win.isClick) {
              if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                var jumped = TaskbarModel.jumpToSnapCard(root.layouts, event.key - Qt.Key_1 + 1, win.clickSelectedCard, win.clickSelectedZone)
                if (jumped) {
                  win.clickSelectedCard = jumped.card
                  win.clickSelectedZone = jumped.zone
                }
                event.accepted = true
                return
              }

              var dir = ""
              if (rkey === Qt.Key_Left) dir = "left"
              else if (rkey === Qt.Key_Right) dir = "right"
              else if (event.key === Qt.Key_Up) dir = "up"
              else if (event.key === Qt.Key_Down) dir = "down"
              else if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) dir = "backtab"
              else if (event.key === Qt.Key_Tab) dir = "tab"

              if (dir.length > 0) {
                var moved = TaskbarModel.nextSnapZone(root.layouts, win.clickSelectedCard, win.clickSelectedZone, dir)
                win.clickSelectedCard = moved.card
                win.clickSelectedZone = moved.zone
                event.accepted = true
                return
              }

              if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                var cIdx = win.clickSelectedCard
                var zIdx = win.clickSelectedZone
                if (cIdx >= 0 && zIdx >= 0 && root.layouts[cIdx] && root.layouts[cIdx][zIdx]) {
                  win.applyZoneFromClick(root.layouts[cIdx][zIdx])
                }
                event.accepted = true
                return
              }

              if (event.key === Qt.Key_Backspace || (event.text && event.text.length > 0 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127)) {
                root.closeState()
              }
            }
          }

          // Live desktop snap preview box
          Rectangle {
            id: previewBox
            visible: opacity > 0
            opacity: (win.surfaceReady && win.previewRect.visible) ? 1 : 0
            x: win.previewRect.visible ? win.previewRect.x : Math.round(win.width / 2 - 100)
            y: win.previewRect.visible ? win.previewRect.y : root.topMargin + pillContainer.height + 16
            width: win.previewRect.visible ? win.previewRect.w : 200
            height: win.previewRect.visible ? win.previewRect.h : 120
            radius: Math.max(Style.space(8), Style.cornerRadius)
            color: Util.alpha(Commons.Color.accent, 0.16)
            border.width: Math.max(2, Style.space(2))
            border.color: Commons.Color.accent

            Behavior on opacity { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }
            Behavior on x { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }
          }

          // Top-center Snap Layouts pill bar
          BorderSurface {
            id: pillContainer

            readonly property bool shown: win.activeOnScreen && win.surfaceReady && !win.isAssist && !win.isResize
            readonly property int cols: root.layouts.length
            readonly property int contentW: cols * root.cardW + Math.max(0, cols - 1) * root.cardGap
            readonly property int contentH: root.cardH

            width: contentW + root.pillPadX * 2 + contentLeftInset + contentRightInset - padding * 2
            height: contentH + root.pillPadY * 2 + contentTopInset + contentBottomInset - padding * 2
            x: Math.round((win.width - width) / 2)
            y: shown ? root.topMargin : -height - 12
            visible: shown || opacity > 0
            opacity: shown ? 1 : 0
            scale: shown ? 1 : 0.96

            radius: Math.max(Style.space(10), Style.cornerRadius)
            color: Commons.Color.popups.background
            borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Style.normalBorderWidth)

            Behavior on y { NumberAnimation { duration: Style.duration(160); easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: Style.duration(140); easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: Style.duration(160); easing.type: Easing.OutCubic } }

            Row {
              x: pillContainer.contentLeftInset + root.pillPadX
              y: pillContainer.contentTopInset + root.pillPadY
              spacing: root.cardGap

              Repeater {
                model: root.layouts

                delegate: Item {
                  id: cardItem
                  required property int index
                  required property var modelData
                  readonly property int cardIdx: index

                  width: root.cardW
                  height: root.cardH

                  Repeater {
                    model: cardItem.modelData

                    delegate: Rectangle {
                      id: zoneTile
                      required property int index
                      required property var modelData

                      readonly property int pad: 2
                      readonly property bool isHot: win.isClick
                        ? (win.clickSelectedCard === cardItem.cardIdx && win.clickSelectedZone === index)
                        : (root.snapState.card === cardItem.cardIdx && root.snapState.zone === index)

                      x: Math.round(modelData.rx * root.cardW) + pad
                      y: Math.round(modelData.ry * root.cardH) + pad
                      width: Math.round(modelData.rw * root.cardW) - pad * 2
                      height: Math.round(modelData.rh * root.cardH) - pad * 2
                      radius: Math.max(Style.space(4), Math.round(Style.cornerRadius * 0.6))
                      color: isHot ? Commons.Color.accent : Style.hoverFill
                      border.width: 1
                      border.color: isHot ? Commons.Color.accent : Commons.Color.popups.border

                      Behavior on color { ColorAnimation { duration: Style.duration(90) } }

                      MouseArea {
                        anchors.fill: parent
                        enabled: win.isClick
                        hoverEnabled: win.isClick
                        cursorShape: Qt.PointingHandCursor
                        onEntered: {
                          win.clickSelectedCard = cardItem.cardIdx
                          win.clickSelectedZone = zoneTile.index
                        }
                        onClicked: win.applyZoneFromClick(zoneTile.modelData)
                      }
                    }
                  }
                }
              }
            }
          }

          // Windows 11-style Snap Assist card inside remaining space
          SnapAssistCard {
            id: assistCard

            readonly property bool shown: win.isAssist && win.surfaceReady && win.assistCandidates.length > 0

            strings: serviceStrings
            candidates: win.assistCandidates
            selectedIndex: win.assistSelectedIndex
            maxWidth: Math.max(Style.space(280), Math.min(Style.space(520), root.snapState.pw - Style.space(28)))
            maxHeight: Math.max(Style.space(220), Math.min(Style.space(420), root.snapState.ph - Style.space(28)))
            x: Math.round(Math.max(Style.space(12), Math.min(win.width - width - Style.space(12), root.snapState.px + (root.snapState.pw - width) / 2)))
            y: Math.round(Math.max(Style.space(12), Math.min(win.height - height - Style.space(12), root.snapState.py + (root.snapState.ph - height) / 2)))
            visible: shown || opacity > 0
            opacity: shown ? 1 : 0
            scale: shown ? 1 : 0.97

            Behavior on opacity { NumberAnimation { duration: Style.duration(140); easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: Style.duration(140); easing.type: Easing.OutCubic } }

            onWindowPicked: function(cand) { win.applyAssistWindow(cand) }
            onCloseRequested: root.closeState()
          }

          // Click-through Windows 11-style Snap Resize divider & live split ratio pill
          Item {
            id: resizeOverlay
            anchors.fill: parent

            property real divX: 0
            property real divY: 0
            property real divW: 8
            property real divH: 100
            property string divAxis: "x"
            property int shownP1: 50
            property int shownP2: 50

            function syncFromState() {
              if (!win.isResize) return
              divX = root.snapState.px
              divY = root.snapState.py
              divW = Math.max(1, root.snapState.pw)
              divH = Math.max(1, root.snapState.ph)
              divAxis = root.snapState.axis === "y" ? "y" : "x"
              shownP1 = root.snapState.p1
              shownP2 = root.snapState.p2
            }

            Connections {
              target: root
              function onSnapStateChanged() { resizeOverlay.syncFromState() }
            }
            Component.onCompleted: syncFromState()

            visible: (win.isResize && win.surfaceReady) || opacity > 0
            opacity: (win.isResize && win.surfaceReady) ? 1 : 0

            Behavior on opacity { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }

            Rectangle {
              readonly property bool isVert: resizeOverlay.divAxis !== "y"
              readonly property real thick: Math.max(3, Math.min(isVert ? resizeOverlay.divW : resizeOverlay.divH, Style.space(4)))

              x: isVert ? Math.round(resizeOverlay.divX + (resizeOverlay.divW - width) / 2) : Math.round(resizeOverlay.divX)
              y: isVert ? Math.round(resizeOverlay.divY) : Math.round(resizeOverlay.divY + (resizeOverlay.divH - height) / 2)
              width: isVert ? thick : Math.max(1, Math.round(resizeOverlay.divW))
              height: isVert ? Math.max(1, Math.round(resizeOverlay.divH)) : thick
              radius: Math.max(1, Math.round(thick / 2))
              color: Util.alpha(Commons.Color.accent, 0.55)
            }

            Rectangle {
              readonly property bool isVert: resizeOverlay.divAxis !== "y"

              width: isVert ? Style.space(6) : Style.space(44)
              height: isVert ? Style.space(44) : Style.space(6)
              x: Math.round(resizeOverlay.divX + (resizeOverlay.divW - width) / 2)
              y: Math.round(resizeOverlay.divY + (resizeOverlay.divH - height) / 2)
              radius: Math.min(width, height) / 2
              color: Commons.Color.accent
            }

            Rectangle {
              readonly property bool isVert: resizeOverlay.divAxis !== "y"
              readonly property real targetX: resizeOverlay.divX + (resizeOverlay.divW - width) / 2
              readonly property real targetY: isVert
                ? resizeOverlay.divY + resizeOverlay.divH / 2 - Style.space(22) - height - Style.space(8)
                : resizeOverlay.divY + (resizeOverlay.divH - height) / 2 - Style.space(18) - height

              width: ratioTxt.implicitWidth + Style.space(16)
              height: ratioTxt.implicitHeight + Style.space(8)
              x: Math.round(Math.max(Style.space(12), Math.min(win.width - width - Style.space(12), targetX)))
              y: Math.round(Math.max(Style.space(12), Math.min(win.height - height - Style.space(12), targetY)))
              radius: Math.max(Style.space(8), Style.cornerRadius)
              color: Commons.Color.popups.background
              border.width: Math.max(1, Style.normalBorderWidth)
              border.color: Commons.Color.popups.border

              Text {
                id: ratioTxt
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: Commons.I18n.formatNumber(resizeOverlay.shownP1) + "% · " + Commons.I18n.formatNumber(resizeOverlay.shownP2) + "%"
                color: Commons.Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }
          }
        }
      }
    }
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: altWin
        required property var modelData
        screen: modelData

        readonly property var monitor: Hyprland.monitorFor(screen)
        readonly property string monitorName: monitor ? monitor.name : ""
        readonly property bool activeOnScreen: root.altTabState.open && (
          root.altTabState.monitor !== ""
            ? root.altTabState.monitor === monitorName
            : (Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name === monitorName : screen === Quickshell.screens[0])
        )
        readonly property var altWindows: altWin.activeOnScreen ? root.collectAltTabWindows(root.altTabState.addrs) : []
        readonly property string selectedAltAddr: (root.altTabState.selected >= 0 && root.altTabState.selected < root.altTabState.addrs.length)
          ? root.altTabState.addrs[root.altTabState.selected]
          : ""
        readonly property int selectedAltIndex: TaskbarModel.resolveSelectedWindowIndex(
          altWin.altWindows,
          altWin.selectedAltAddr,
          root.altTabState.selected
        )
        readonly property bool surfaceReady: altWin.backingWindowVisible
          && !!screen
          && Math.abs(altWin.width - screen.width) <= 2
          && Math.abs(altWin.height - screen.height) <= 2
        readonly property bool shown: altWin.activeOnScreen && altWin.surfaceReady

        // Map fullscreen layer surface only while Alt+Tab is open or fading out (0 idle VRAM/surfaces).
        visible: altWin.activeOnScreen || altBackdrop.opacity > 0
        color: "transparent"
        WlrLayershell.namespace: "omarchy-windaase-alttab"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0

        anchors {
          top: true
          bottom: true
          left: true
          right: true
        }

        mask: Region {
          item: altWin.activeOnScreen ? altBackdrop : null
        }

        Item {
          id: altBackdrop
          anchors.fill: parent
          visible: altWin.shown || opacity > 0
          opacity: altWin.shown ? 1 : 0

          Behavior on opacity { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }

          Rectangle {
            anchors.fill: parent
            color: Commons.Color.menu.scrim
          }

          MouseArea {
            anchors.fill: parent
            onClicked: root.closeAltTab()
          }

          AltTabSwitcher {
            anchors.centerIn: parent
            strings: serviceStrings
            windows: altWin.altWindows
            selectedIndex: altWin.selectedAltIndex
            active: altWin.activeOnScreen
            maxWidth: Math.max(Style.space(260), altWin.width - Style.space(64))
            maxHeight: Math.max(Style.space(220), altWin.height - Style.space(96))
            scale: altWin.shown ? 1 : 0.96

            Behavior on scale { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }

            onWindowPicked: function(w) { root.activateAltTabWindow(w) }
          }
        }
      }
    }
  }

  // Brief click-through screen number badges rendered when clicking "Identify"
  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: idWin
        required property var modelData
        screen: modelData

        readonly property var mon: Hyprland.monitorFor(screen)
        readonly property string monName: (screen && screen.name)
          ? String(screen.name)
          : ((modelData && modelData.name) ? String(modelData.name) : (mon ? String(mon.name || "") : ""))
        readonly property var info: root.identifyMap[monName] || null
        readonly property bool activeOnScreen: root.identifyActive && !!info
        readonly property bool surfaceReady: idWin.backingWindowVisible
          && !!screen
          && Math.abs(idWin.width - screen.width) <= 2
          && Math.abs(idWin.height - screen.height) <= 2
        readonly property bool shown: idWin.activeOnScreen && idWin.surfaceReady
        readonly property int topInset: (mon && mon.lastIpcObject && mon.lastIpcObject.reserved)
          ? Math.max(0, Number(mon.lastIpcObject.reserved[1]) || 0)
          : 0

        // Map fullscreen layer surface only while identifying or fading out (0 idle VRAM/surfaces).
        visible: idWin.activeOnScreen || idBadge.opacity > 0
        color: "transparent"
        WlrLayershell.namespace: "omarchy-windaase-identify"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0

        anchors {
          top: true
          bottom: true
          left: true
          right: true
        }

        mask: Region {}

        Item {
          anchors.fill: parent

          BorderSurface {
            id: idBadge
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: idWin.topInset + Style.space(40)
            width: idRow.implicitWidth + Style.space(48)
            height: idRow.implicitHeight + Style.space(32)
            radius: Math.max(Style.space(12), Style.cornerRadius)
            color: Commons.Color.popups.background
            borderSpec: Border.flat(Commons.Color.accent, Math.max(2, Style.normalBorderWidth))
            opacity: idWin.shown ? 1 : 0
            scale: idWin.shown ? 1 : 0.94

            Behavior on opacity { NumberAnimation { duration: Style.duration(140); easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: Style.duration(140); easing.type: Easing.OutCubic } }

            Row {
              id: idRow
              anchors.centerIn: parent
              spacing: Style.spacing.lg

              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: idWin.info ? Commons.I18n.formatNumber(idWin.info.number || 1) : ""
                color: Commons.Color.accent
                font.family: Style.font.family
                font.pixelSize: Style.space(64)
                font.bold: true
              }

              Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Text {
                  textFormat: Text.PlainText
                  text: idWin.info ? String(idWin.info.label || idWin.monName) : ""
                  color: Commons.Color.popups.text
                  font.family: Style.font.family
                  font.pixelSize: Style.font.title
                  font.bold: true
                }

                Text {
                  visible: text !== ""
                  textFormat: Text.PlainText
                  text: idWin.info ? String(idWin.info.detail || "") : ""
                  color: Commons.Color.popups.text
                  opacity: 0.72
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }
              }
            }
          }
        }
      }
    }
  }
}
