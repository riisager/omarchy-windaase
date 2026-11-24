import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import "TaskbarModel.js" as TaskbarModel

// Per-screen backdrop and switcher card host for Alt+Tab live-thumbnail window switching.
Variants {
  id: root

  required property var strings
  required property var altTabState
  property var resolveAltTabWindows: null

  signal closeRequested()
  signal windowPicked(var win)

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
      readonly property var altWindows: (altWin.activeOnScreen && typeof root.resolveAltTabWindows === "function")
        ? root.resolveAltTabWindows(root.altTabState.addrs)
        : []
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
          onClicked: root.closeRequested()
        }

        AltTabSwitcher {
          anchors.centerIn: parent
          strings: root.strings
          windows: altWin.altWindows
          selectedIndex: altWin.selectedAltIndex
          active: altWin.activeOnScreen
          maxWidth: Math.max(Style.space(260), altWin.width - Style.space(64))
          maxHeight: Math.max(Style.space(220), altWin.height - Style.space(96))
          scale: altWin.shown ? 1 : 0.96

          Behavior on scale { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }

          onWindowPicked: function(w) { root.windowPicked(w) }
        }
      }
    }
  }
}
