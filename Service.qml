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
  readonly property bool snapAssistEnabled: root.hyprSettings.snap_assist !== false
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
  property int _writeSeq: 0

  Commons.Translations {
    id: serviceStrings
    directory: Qt.resolvedUrl("i18n")
  }

  readonly property var terminalEntries: {
    var values = DesktopEntries.applications.values
    var out = []
    for (var i = 0; i < values.length; i++) {
      var entry = values[i]
      if (entry.runInTerminal || String(entry.execString || "").indexOf("--app-id=") >= 0) {
        out.push({
          id: entry.id,
          execString: entry.execString,
          command: entry.command,
          runInTerminal: entry.runInTerminal
        })
      }
    }
    return out
  }

  function entryForAppId(appId) {
    var entry = DesktopEntries.heuristicLookup(appId)
    if (entry) return entry
    var id = TaskbarModel.claimingEntryId(appId, root.terminalEntries)
    return id ? DesktopEntries.byId(id) : null
  }

  function iconSourceFor(entry, fallbackId) {
    var raw = entry && entry.icon ? entry.icon : String(fallbackId || "")
    var value = String(raw || "")
    if (value.length === 0) return Quickshell.iconPath("application-x-executable", true)
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    var themed = Quickshell.iconPath(value, true)
    if (themed && themed.length > 0) return themed
    return Quickshell.iconPath("application-x-executable", true)
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
      var floating = ipc.floating !== undefined ? !!ipc.floating : true
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

  function writeStateFile(obj) {
    var payload = JSON.stringify(obj)
    root._writeSeq += 1
    var tmpPath = root.statePath + ".qml." + root._writeSeq + ".tmp"
    Util.execDetached("printf '%s\\n' " + Util.shellQuote(payload) + " > " + Util.shellQuote(tmpPath) + " && mv -f " + Util.shellQuote(tmpPath) + " " + Util.shellQuote(root.statePath))
  }

  function closeState() {
    root.snapState = emptyState()
    root.writeStateFile({ open: false })
  }

  Component.onCompleted: {
    root.loadLayouts(layoutsFile.text())
    root.hyprSettings = TaskbarModel.parseHyprSettings(hyprSettingsFile.text())
    Quickshell.execDetached(["bash", "-c", "[ -f " + Util.shellQuote(root.statePath) + " ] || printf '{\"open\":false}\\n' > " + Util.shellQuote(root.statePath)])
    Qt.callLater(function() { stateFile.reload() })
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

  AppGrid {
    id: appGrid
  }

  ShellIpc {
    target: "riisager.windaase"

    function apps(): void {
      appGrid.toggle()
    }

    function settings(): void {
      Commons.IpcRegistry.call("riisager.windaase.bar", "toggleSettings", [])
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
        readonly property bool isInteractive: isClick || isAssist

        property int clickSelectedCard: -1
        property int clickSelectedZone: -1
        property int assistSelectedIndex: 0

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
            assistSelectedIndex = 0
            Qt.callLater(win.closeAssistIfEmpty)
          }
        }

        onAssistCandidatesChanged: {
          if (win.isAssist) {
            if (assistCandidates.length === 0) Qt.callLater(win.closeAssistIfEmpty)
            else if (assistSelectedIndex >= assistCandidates.length) assistSelectedIndex = assistCandidates.length - 1
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

        function placeAddressInRect(targetAddr, rect, focusTarget) {
          var addr = root.validAddress(targetAddr)
          var target = addr ? ("window = \"address:" + addr + "\"") : ""
          var monX = monitor ? monitor.x : 0
          var monY = monitor ? monitor.y : 0
          var border = root.snapState.border
          var titlebar = root.snapState.titlebar
          var cw = Math.round(Math.max(120, rect.w - border * 2))
          var ch = Math.round(Math.max(120, rect.h - border * 2 - titlebar))
          var cx = Math.round(monX + rect.x + border)
          var cy = Math.round(monY + rect.y + border + titlebar)
          var steps = []
          steps.push("hl.dsp.window.fullscreen({ mode = \"maximized\", action = \"unset\"" + (target ? (", " + target) : "") + " })")
          steps.push("hl.dsp.window.resize({ x = " + cw + ", y = " + ch + ", relative = false" + (target ? (", " + target) : "") + " })")
          steps.push("hl.dsp.window.move({ x = " + cx + ", y = " + cy + ", relative = false" + (target ? (", " + target) : "") + " })")
          if (focusTarget && target) steps.push("hl.dsp.focus({ " + target + " })")
          steps.push("hl.dsp.window.alter_zorder({ mode = \"top\"" + (target ? (", " + target) : "") + " })")
          return steps.map(function(s) { return "hyprctl dispatch " + Util.shellQuote(s) }).join(" && ")
        }

        function applyZoneFromClick(z) {
          var addr = root.validAddress(root.snapState.addr)
          var res = monitor && monitor.lastIpcObject && monitor.lastIpcObject.reserved ? monitor.lastIpcObject.reserved : [0, 0, 0, 0]
          var rLeft = res[0] || 0
          var rTop = res[1] || 0
          var rRight = res[2] || 0
          var rBottom = res[3] || 0
          var rect = z.max
            ? { x: rLeft, y: rTop, w: screen.width - rLeft - rRight, h: screen.height - rTop - rBottom }
            : computeZoneRect(z)
          var command = placeAddressInRect(addr, rect, false)

          var assistAllowed = (root.snapState.assist !== null && root.snapState.assist !== undefined)
            ? root.snapState.assist
            : root.snapAssistEnabled
          var comp = (!z.max && assistAllowed) ? TaskbarModel.complementaryZone(z) : null
          var wsId = win.activeAssistWsId
          var candidates = (comp && wsId >= 1) ? root.collectAssistCandidates(addr, wsId) : []
          if (comp && candidates.length > 0) {
            var compRect = computeZoneRect(comp)
            var nextState = {
              open: true,
              mode: "assist",
              monitor: win.monitorName,
              card: -1,
              zone: -1,
              px: compRect.x,
              py: compRect.y,
              pw: compRect.w,
              ph: compRect.h,
              addr: addr,
              border: root.snapState.border,
              titlebar: root.snapState.titlebar,
              ws: wsId,
              uw: root.effectiveUltrawide,
              assist: assistAllowed,
              go: root.snapState.go,
              gi: root.snapState.gi
            }
            root.snapState = nextState
            root.writeStateFile(nextState)
          } else {
            root.closeState()
          }
          Util.execDetached(command)
        }

        function applyAssistWindow(candidate) {
          var targetAddr = candidate ? root.validAddress(candidate.address) : ""
          if (!targetAddr) {
            root.closeState()
            return
          }
          var rect = {
            x: root.snapState.px,
            y: root.snapState.py,
            w: root.snapState.pw,
            h: root.snapState.ph
          }
          var command = placeAddressInRect(targetAddr, rect, true)
          root.closeState()
          Util.execDetached(command)
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

        // Stays mapped with an empty mask when closed (0 ms appear latency, always click-through during drag)
        visible: true
        color: "transparent"
        WlrLayershell.namespace: "omarchy-windaase-snap"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: win.isInteractive ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0

        anchors {
          top: true
          bottom: true
          left: true
          right: true
        }

        mask: Region {
          item: win.isAssist ? assistCard : (win.isClick ? pillContainer : null)
        }

        HyprlandFocusGrab {
          active: win.isInteractive
          windows: [win]
          onCleared: if (win.isInteractive) root.closeState()
        }

        Item {
          anchors.fill: parent
          focus: win.isInteractive

          Keys.onPressed: function(event) {
            if (!win.isInteractive) return
            if (event.key === Qt.Key_Escape) {
              root.closeState()
              event.accepted = true
              return
            }

            var rkey = Util.readingKey(event)

            if (win.isAssist) {
              var count = win.assistCandidates.length
              if (count === 0) {
                root.closeState()
                event.accepted = true
                return
              }
              var cols = assistCard.columns
              if (rkey === Qt.Key_Left || event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
                win.assistSelectedIndex = (win.assistSelectedIndex - 1 + count) % count
                event.accepted = true
              } else if (rkey === Qt.Key_Right || event.key === Qt.Key_Tab) {
                win.assistSelectedIndex = (win.assistSelectedIndex + 1) % count
                event.accepted = true
              } else if (event.key === Qt.Key_Up) {
                if (win.assistSelectedIndex - cols >= 0) win.assistSelectedIndex -= cols
                event.accepted = true
              } else if (event.key === Qt.Key_Down) {
                if (win.assistSelectedIndex + cols < count) win.assistSelectedIndex += cols
                event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                win.applyAssistWindow(win.assistCandidates[win.assistSelectedIndex])
                event.accepted = true
              }
              return
            }

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
              }
            }
          }

          // Live desktop snap preview box
          Rectangle {
            id: previewBox
            visible: opacity > 0
            opacity: win.previewRect.visible ? 1 : 0
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

            readonly property int cols: root.layouts.length
            readonly property int contentW: cols * root.cardW + Math.max(0, cols - 1) * root.cardGap
            readonly property int contentH: root.cardH

            width: contentW + root.pillPadX * 2 + contentLeftInset + contentRightInset - padding * 2
            height: contentH + root.pillPadY * 2 + contentTopInset + contentBottomInset - padding * 2
            x: Math.round((win.width - width) / 2)
            y: (win.activeOnScreen && !win.isAssist && !win.isResize) ? root.topMargin : -height - 12
            visible: (win.activeOnScreen && !win.isAssist && !win.isResize) || opacity > 0
            opacity: (win.activeOnScreen && !win.isAssist && !win.isResize) ? 1 : 0
            scale: (win.activeOnScreen && !win.isAssist && !win.isResize) ? 1 : 0.96

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

            readonly property bool shown: win.isAssist && win.assistCandidates.length > 0

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

            onHoveredIndexChanged: function(idx) { win.assistSelectedIndex = idx }
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

            visible: win.isResize || opacity > 0
            opacity: win.isResize ? 1 : 0

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
}
