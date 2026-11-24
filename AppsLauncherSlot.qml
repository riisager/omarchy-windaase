import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "TaskbarModel.js" as TaskbarModel

// 3x3 All Apps launcher icon modeled after Omarchy's built-in dock AppsSlot.
Item {
  id: appsSlot

  required property var taskbar
  required property var strings

  readonly property bool hovered: appsMouse.containsMouse
  property var registeredBar: null
  property int heldButtons: Qt.NoButton
  readonly property real pressScale: ((appsMouse.pressedButtons | appsSlot.heldButtons) & Qt.LeftButton) ? 0.9 : 1.0

  function triggerPress(button) {
    if (taskbar.bar) taskbar.bar.hideTooltip(appsSlot)
    if (button === Qt.RightButton) {
      if (taskbar.settingsOpen) taskbar.closePopouts()
      else taskbar.openSettings(appsSlot)
      return
    }
    if (button === Qt.LeftButton) {
      taskbar.closePopouts()
      taskbar.toggleAppGrid()
    }
  }

  function syncClickRegistration() {
    if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(appsSlot)
    registeredBar = taskbar.bar
    if (registeredBar && registeredBar.registerClickTarget) registeredBar.registerClickTarget(appsSlot)
  }

  visible: taskbar.showAppsButton
  Layout.preferredWidth: taskbar.showAppsButton ? taskbar.slotSize : 0
  Layout.preferredHeight: taskbar.showAppsButton ? taskbar.slotSize : 0

  onVisibleChanged: if (!visible && taskbar && taskbar.bar) taskbar.bar.hideTooltip(appsSlot)
  Connections {
    target: appsSlot.taskbar
    function onBarChanged() { appsSlot.syncClickRegistration() }
  }
  Component.onCompleted: syncClickRegistration()
  Component.onDestruction: {
    if (taskbar && !taskbar._destroyed && taskbar.bar) taskbar.bar.hideTooltip(appsSlot)
    if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(appsSlot)
  }

  Rectangle {
    anchors.centerIn: parent
    width: appsSlot.taskbar.slotSize - appsSlot.taskbar.pillInset
    height: appsSlot.taskbar.slotSize - appsSlot.taskbar.pillInset
    radius: Math.max(Style.space(4), Style.cornerRadius)
    color: appsSlot.hovered ? Style.hoverFill : "transparent"

    Behavior on color { ColorAnimation { duration: Style.duration(120) } }
  }

  Item {
    anchors.centerIn: parent
    width: appsSlot.taskbar.appsIconSize
    height: appsSlot.taskbar.appsIconSize
    opacity: appsSlot.hovered ? 1.0 : appsSlot.taskbar.idleOpacity
    scale: (appsSlot.hovered ? 1.1 : 1.0) * appsSlot.pressScale

    Behavior on scale { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }

    Grid {
      readonly property int square: Math.max(2, Math.round(appsSlot.taskbar.appsIconSize * 0.22))

      anchors.centerIn: parent
      columns: 3
      spacing: Math.max(1, Math.round(appsSlot.taskbar.appsIconSize * 0.1))

      Repeater {
        model: 9

        delegate: Rectangle {
          width: parent.square
          height: parent.square
          radius: Math.max(1, Math.round(parent.square * 0.2))
          color: appsSlot.taskbar.bar ? appsSlot.taskbar.bar.barForeground : Commons.Color.bar.text
        }
      }
    }
  }

  MouseArea {
    id: appsMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton

    onEntered: {
      if (appsSlot.taskbar.pickerKey.length > 0 && appsSlot.taskbar.pickerTriggerMode === "hover") {
        appsSlot.taskbar.closePopouts()
      }
      if (appsSlot.taskbar.bar && appsSlot.taskbar.pickerKey.length === 0 && appsSlot.taskbar.menuKey.length === 0 && !appsSlot.taskbar.settingsOpen) {
        appsSlot.taskbar.bar.showTooltip(appsSlot, TaskbarModel.sanitizeTooltipText(appsSlot.strings.t("taskbar.apps"), 96))
      }
    }
    onExited: if (appsSlot.taskbar.bar) appsSlot.taskbar.bar.hideTooltip(appsSlot)
    onClicked: function(event) { appsSlot.triggerPress(event.button) }
  }
}
