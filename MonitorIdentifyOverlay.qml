import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Brief click-through screen number badges rendered when clicking "Identify".
Variants {
  id: root

  property bool identifyActive: false
  property var identifyMap: ({})

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
