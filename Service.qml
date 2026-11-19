import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

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
    ]
  })

  property var layoutsConfig: defaultLayoutsConfig
  readonly property int cardW: Number(layoutsConfig.cardW) || 84
  readonly property int cardH: Number(layoutsConfig.cardH) || 52
  readonly property int cardGap: Number(layoutsConfig.cardGap) || 10
  readonly property int pillPadX: Number(layoutsConfig.padX) || 14
  readonly property int pillPadY: Number(layoutsConfig.padY) || 12
  readonly property int topMargin: Number(layoutsConfig.topMargin) || 10
  readonly property var layouts: Array.isArray(layoutsConfig.layouts) ? layoutsConfig.layouts : defaultLayoutsConfig.layouts

  readonly property string statePath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/omarchy-windaase-snap.json"
  property var snapState: ({ open: false, mode: "drag", monitor: "", card: -1, zone: -1, px: 0, py: 0, pw: 0, ph: 0, addr: "", border: 2, titlebar: 30 })

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
          layouts: parsed.layouts
        }
        return
      }
    } catch (e) {}
    root.layoutsConfig = root.defaultLayoutsConfig
  }

  function validAddress(addr) {
    var s = String(addr || "").trim()
    var m = /^(?:0[xX])?([0-9a-fA-F]{1,20})$/.exec(s)
    return m ? ("0x" + m[1]) : ""
  }

  function emptyState() {
    return { open: false, mode: "drag", monitor: "", card: -1, zone: -1, px: 0, py: 0, pw: 0, ph: 0, addr: "", border: 2, titlebar: 30 }
  }

  function parseState(raw) {
    try {
      var parsed = JSON.parse(String(raw || ""))
      if (parsed && typeof parsed === "object") {
        root.snapState = {
          open: !!parsed.open,
          mode: parsed.mode === "click" ? "click" : "drag",
          monitor: String(parsed.monitor || ""),
          card: typeof parsed.card === "number" ? parsed.card : -1,
          zone: typeof parsed.zone === "number" ? parsed.zone : -1,
          px: Number(parsed.px) || 0,
          py: Number(parsed.py) || 0,
          pw: Number(parsed.pw) || 0,
          ph: Number(parsed.ph) || 0,
          addr: validAddress(parsed.addr),
          border: typeof parsed.border === "number" ? Math.max(0, parsed.border) : 2,
          titlebar: typeof parsed.titlebar === "number" ? Math.max(0, parsed.titlebar) : 30
        }
        return
      }
    } catch (e) {}
    root.snapState = emptyState()
  }

  function closeState() {
    root.snapState = emptyState()
    var tmpPath = root.statePath + ".tmp"
    Util.execDetached("printf '{\"open\":false}\\n' > " + Util.shellQuote(tmpPath) + " && mv -f " + Util.shellQuote(tmpPath) + " " + Util.shellQuote(root.statePath))
  }

  Component.onCompleted: {
    root.loadLayouts(layoutsFile.text())
    Quickshell.execDetached(["bash", "-c", "[ -f " + Util.shellQuote(root.statePath) + " ] || printf '{\"open\":false}\\n' > " + Util.shellQuote(root.statePath)])
    Qt.callLater(function() { stateFile.reload() })
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

        property int clickHoverCard: -1
        property int clickHoverZone: -1

        onActiveOnScreenChanged: {
          if (!activeOnScreen) {
            clickHoverCard = -1
            clickHoverZone = -1
          }
        }

        function computeZoneRect(z) {
          var res = monitor && monitor.lastIpcObject && monitor.lastIpcObject.reserved ? monitor.lastIpcObject.reserved : [0, 0, 0, 0]
          var rLeft = res[0] || 0
          var rTop = res[1] || 0
          var rRight = res[2] || 0
          var rBottom = res[3] || 0
          var gapOut = 8
          var gapIn = 8
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
          var addr = root.validAddress(root.snapState.addr)
          var target = addr ? ("window = \"address:" + addr + "\"") : ""
          var monX = monitor ? monitor.x : 0
          var monY = monitor ? monitor.y : 0
          var res = monitor && monitor.lastIpcObject && monitor.lastIpcObject.reserved ? monitor.lastIpcObject.reserved : [0, 0, 0, 0]
          var rLeft = res[0] || 0
          var rTop = res[1] || 0
          var rRight = res[2] || 0
          var rBottom = res[3] || 0
          var rect = z.max
            ? { x: rLeft, y: rTop, w: screen.width - rLeft - rRight, h: screen.height - rTop - rBottom }
            : computeZoneRect(z)
          var border = root.snapState.border
          var titlebar = root.snapState.titlebar
          var cw = Math.max(120, rect.w - border * 2)
          var ch = Math.max(120, rect.h - border * 2 - titlebar)
          var cx = monX + rect.x + border
          var cy = monY + rect.y + border + titlebar
          var steps = []
          steps.push("hl.dsp.window.fullscreen({ mode = \"maximized\", action = \"unset\"" + (target ? (", " + target) : "") + " })")
          steps.push("hl.dsp.window.resize({ x = " + cw + ", y = " + ch + ", relative = false" + (target ? (", " + target) : "") + " })")
          steps.push("hl.dsp.window.move({ x = " + cx + ", y = " + cy + ", relative = false" + (target ? (", " + target) : "") + " })")
          steps.push("hl.dsp.window.alter_zorder({ mode = \"top\"" + (target ? (", " + target) : "") + " })")
          var command = steps.map(function(s) { return "hyprctl dispatch " + Util.shellQuote(s) }).join(" && ")
          root.closeState()
          Util.execDetached(command)
        }

        readonly property var previewRect: {
          if (!activeOnScreen) return { visible: false, x: 0, y: 0, w: 0, h: 0 }
          if (isClick) {
            if (clickHoverCard >= 0 && clickHoverZone >= 0 && root.layouts[clickHoverCard] && root.layouts[clickHoverCard][clickHoverZone]) {
              var z = root.layouts[clickHoverCard][clickHoverZone]
              var r = computeZoneRect(z)
              return { visible: true, x: r.x, y: r.y, w: r.w, h: r.h }
            }
            return { visible: false, x: 0, y: 0, w: 0, h: 0 }
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
        WlrLayershell.keyboardFocus: isClick ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0

        anchors {
          top: true
          bottom: true
          left: true
          right: true
        }

        mask: Region {
          item: win.isClick ? pillContainer : null
        }

        HyprlandFocusGrab {
          active: win.isClick
          windows: [win]
          onCleared: root.closeState()
        }

        Item {
          anchors.fill: parent
          focus: win.isClick
          Keys.onEscapePressed: root.closeState()

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
            y: win.activeOnScreen ? root.topMargin : -height - 12
            visible: opacity > 0
            opacity: win.activeOnScreen ? 1 : 0
            scale: win.activeOnScreen ? 1 : 0.96

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
                        ? (win.clickHoverCard === cardItem.cardIdx && win.clickHoverZone === index)
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
                          win.clickHoverCard = cardItem.cardIdx
                          win.clickHoverZone = zoneTile.index
                        }
                        onExited: {
                          if (win.clickHoverCard === cardItem.cardIdx && win.clickHoverZone === zoneTile.index) {
                            win.clickHoverCard = -1
                            win.clickHoverZone = -1
                          }
                        }
                        onClicked: win.applyZoneFromClick(zoneTile.modelData)
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
