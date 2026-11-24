import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "TaskbarModel.js" as TaskbarModel
import "js/SnapLayoutMath.js" as SnapLayoutMath

// Per-screen overlay for Snap Layouts pill bar, preview rect, Snap Assist, and Snap Resize divider.
Variants {
  id: root

  required property var strings
  required property var snapState
  property var layouts: SnapLayoutMath.DEFAULT_LAYOUTS_CONFIG.layouts
  property int cardW: 84
  property int cardH: 52
  property int cardGap: 10
  property int pillPadX: 14
  property int pillPadY: 12
  property int topMargin: 10
  property var resolveAssistCandidates: null

  signal closeRequested()
  signal applyZoneRequested(var zone, string monitorName)
  signal applyAssistRequested(var candidate)

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

      readonly property int activeAssistWsId: root.snapState.ws >= 1
        ? root.snapState.ws
        : (monitor && monitor.activeWorkspace ? Number(monitor.activeWorkspace.id) : -1)
      readonly property var assistCandidates: (win.isAssist && typeof root.resolveAssistCandidates === "function")
        ? root.resolveAssistCandidates(root.snapState.addr, win.activeAssistWsId)
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
          root.closeRequested()
        }
      }

      onIsAssistChanged: {
        if (win.isAssist) {
          Qt.callLater(function() { if (win) win.closeAssistIfEmpty() })
        }
      }

      onAssistCandidatesChanged: {
        if (win.isAssist && assistCandidates.length === 0) {
          Qt.callLater(function() { if (win) win.closeAssistIfEmpty() })
        }
      }

      function computeZoneRect(z) {
        var res = monitor && monitor.lastIpcObject && monitor.lastIpcObject.reserved ? monitor.lastIpcObject.reserved : [0, 0, 0, 0]
        return SnapLayoutMath.computeZoneRect(
          z,
          screen.width,
          screen.height,
          res,
          root.snapState.go,
          root.snapState.gi
        )
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
        onCleared: if (win.isClick) root.closeRequested()
      }

      Item {
        id: snapKeyCatcher
        anchors.fill: parent
        focus: win.clickInteractive

        Keys.onPressed: function(event) {
          if (!win.clickInteractive) return
          if (event.key === Qt.Key_Escape) {
            root.closeRequested()
            event.accepted = true
            return
          }

          var rkey = Util.readingKey(event)

          if (win.isClick) {
            if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
              var jumped = SnapLayoutMath.jumpToSnapCard(root.layouts, event.key - Qt.Key_1 + 1, win.clickSelectedCard, win.clickSelectedZone)
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
              var moved = SnapLayoutMath.nextSnapZone(root.layouts, win.clickSelectedCard, win.clickSelectedZone, dir)
              win.clickSelectedCard = moved.card
              win.clickSelectedZone = moved.zone
              event.accepted = true
              return
            }

            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
              var cIdx = win.clickSelectedCard
              var zIdx = win.clickSelectedZone
              if (cIdx >= 0 && zIdx >= 0 && root.layouts[cIdx] && root.layouts[cIdx][zIdx]) {
                root.applyZoneRequested(root.layouts[cIdx][zIdx], win.monitorName)
              }
              event.accepted = true
              return
            }

            if (event.key === Qt.Key_Backspace || (event.text && event.text.length > 0 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127)) {
              root.closeRequested()
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
                      onClicked: root.applyZoneRequested(zoneTile.modelData, win.monitorName)
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

          strings: root.strings
          candidates: win.assistCandidates
          maxWidth: Math.max(Style.space(280), Math.min(Style.space(520), root.snapState.pw - Style.space(28)))
          maxHeight: Math.max(Style.space(220), Math.min(Style.space(420), root.snapState.ph - Style.space(28)))
          x: Math.round(Math.max(Style.space(12), Math.min(win.width - width - Style.space(12), root.snapState.px + (root.snapState.pw - width) / 2)))
          y: Math.round(Math.max(Style.space(12), Math.min(win.height - height - Style.space(12), root.snapState.py + (root.snapState.ph - height) / 2)))
          visible: shown || opacity > 0
          opacity: shown ? 1 : 0
          scale: shown ? 1 : 0.97

          Behavior on opacity { NumberAnimation { duration: Style.duration(140); easing.type: Easing.OutCubic } }
          Behavior on scale { NumberAnimation { duration: Style.duration(140); easing.type: Easing.OutCubic } }

          onWindowPicked: function(cand) { root.applyAssistRequested(cand) }
          onCloseRequested: root.closeRequested()
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
