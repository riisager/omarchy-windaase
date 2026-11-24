import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "TaskbarModel.js" as TaskbarModel
import "js/BrowserProfiles.js" as BrowserProfiles

// Individual pinned or running taskbar app button with drag reorder, indicator bar,
// profile badge, window counter, urgency dot, and hover preview triggers.
Item {
  id: taskSlot

  required property int index
  required property string key
  required property var taskbar
  required property var dragSpace
  required property int totalSlots
  required property var strings

  readonly property var modelData: taskbar.itemFor(key)
  readonly property int windowCount: modelData ? modelData.windows.length : 0
  readonly property bool focused: taskbar.isItemFocused(modelData)
  readonly property bool urgent: !focused && TaskbarModel.isItemUrgent(modelData, taskbar.urgentAddresses)
  readonly property bool allMinimized: taskbar.isItemAllMinimized(modelData)
  readonly property string appLabel: modelData ? taskbar.labelFor(modelData) : key
  readonly property var profileBadge: BrowserProfiles.profileBadgeForItem(modelData, taskbar.windowProfiles)
  readonly property bool lifted: taskbar.dragIndex === index
  readonly property bool hovered: slotMouse.containsMouse && !taskbar.draggingItem

  property var registeredBar: null
  property int heldButtons: Qt.NoButton
  onHeldButtonsChanged: if (heldButtons !== Qt.NoButton && taskbar) taskbar.cancelHoverPreview()
  readonly property real pressScale: (!taskSlot.lifted && ((slotMouse.pressedButtons | taskSlot.heldButtons) & Qt.LeftButton)) ? 0.9 : 1.0

  function triggerPress(button) {
    if (taskbar.bar) taskbar.bar.hideTooltip(taskSlot)
    if (!taskSlot.modelData) return
    if (button === Qt.RightButton) {
      if (taskbar.menuKey === taskSlot.key) taskbar.closePopouts()
      else taskbar.openMenu(taskSlot.key, taskSlot)
      return
    }
    if (button === Qt.MiddleButton) {
      taskbar.closePopouts()
      taskbar.launch(taskSlot.modelData)
      return
    }
    if (button !== Qt.LeftButton) return
    if (taskSlot.windowCount === 0) {
      taskbar.closePopouts()
      taskbar.launch(taskSlot.modelData)
      return
    }
    if (taskSlot.windowCount === 1) {
      taskbar.closePopouts()
      taskbar.activateWindow(taskSlot.modelData.windows[0])
      return
    }
    if (taskbar.pickerKey === taskSlot.key && taskbar.pickerTriggerMode === "click") taskbar.closePopouts()
    else taskbar.openPicker(taskSlot.key, taskSlot, "click")
  }

  function syncClickRegistration() {
    if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(taskSlot)
    registeredBar = taskbar.bar
    if (registeredBar && registeredBar.registerClickTarget) registeredBar.registerClickTarget(taskSlot)
  }

  z: taskSlot.lifted ? 2 : 0
  Layout.preferredWidth: taskbar.slotSize
  Layout.preferredHeight: taskbar.slotSize

  Connections {
    target: taskSlot.taskbar
    function onBarChanged() { taskSlot.syncClickRegistration() }
  }
  Component.onCompleted: syncClickRegistration()
  Component.onDestruction: {
    if (taskbar && !taskbar._destroyed) {
      if (taskbar.hoveredSlotKey === taskSlot.key) taskbar.hoveredSlotKey = ""
      if (taskbar.hoverPreviewPendingAnchor === taskSlot) taskbar.cancelHoverPreview()
      if (taskbar.pickerAnchor === taskSlot) {
        taskbar.pickerKey = ""
        taskbar.pickerAnchor = null
        taskbar.pickerTriggerMode = "click"
      }
      if (taskSlot.lifted) taskbar.endItemDrag()
      if (taskbar.bar) taskbar.bar.hideTooltip(taskSlot)
    }
    if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(taskSlot)
  }

  Item {
    id: slotVisual
    anchors.fill: parent

    readonly property real targetShift: !taskSlot.taskbar.draggingItem
      ? 0
      : taskSlot.lifted
        ? taskSlot.taskbar.dragOffset
        : (taskSlot.taskbar.dragIndex < taskSlot.index && taskSlot.index <= taskSlot.taskbar.dropIndex)
          ? -taskSlot.taskbar.slotStride
          : (taskSlot.taskbar.dropIndex <= taskSlot.index && taskSlot.index < taskSlot.taskbar.dragIndex)
            ? taskSlot.taskbar.slotStride
            : 0
    property real displayedShift: targetShift

    Behavior on displayedShift {
      enabled: taskSlot.taskbar.animateShifts && taskSlot.taskbar.draggingItem && !taskSlot.lifted
      NumberAnimation { duration: Style.duration(150); easing.type: Easing.OutCubic }
    }

    scale: taskSlot.lifted ? 1.08 : 1.0
    Behavior on scale { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }

    transform: Translate {
      x: taskSlot.taskbar.vertical ? 0 : slotVisual.displayedShift
      y: taskSlot.taskbar.vertical ? slotVisual.displayedShift : 0
    }

    Rectangle {
      anchors.centerIn: parent
      width: taskSlot.taskbar.slotSize - taskSlot.taskbar.pillInset
      height: taskSlot.taskbar.slotSize - taskSlot.taskbar.pillInset
      radius: Math.max(Style.space(4), Style.cornerRadius)
      color: (taskSlot.focused || taskSlot.lifted)
        ? Style.selectedFill
        : (taskSlot.urgent
          ? Util.alpha(Commons.Color.urgent, 0.24)
          : (taskSlot.hovered ? Style.hoverFill : "transparent"))
      border.width: (taskSlot.focused || taskSlot.lifted || taskSlot.urgent) ? 1 : 0
      border.color: taskSlot.lifted
        ? Commons.Color.accent
        : (taskSlot.urgent
          ? Commons.Color.urgent
          : (taskSlot.focused ? Style.normalBorderColor : "transparent"))

      Behavior on color { ColorAnimation { duration: Style.duration(150) } }
    }

    Image {
      anchors.centerIn: parent
      anchors.verticalCenterOffset: taskSlot.taskbar.vertical ? 0 : (taskSlot.taskbar.tallBar ? -1 : 0)
      width: taskSlot.taskbar.iconSize
      height: taskSlot.taskbar.iconSize
      sourceSize: Qt.size(taskSlot.taskbar.iconSize * 2, taskSlot.taskbar.iconSize * 2)
      source: taskSlot.modelData ? taskSlot.taskbar.iconFor(taskSlot.modelData) : ""
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      smooth: true
      mipmap: true
      opacity: taskSlot.windowCount > 0 ? (taskSlot.allMinimized ? 0.65 : 1.0) : taskSlot.taskbar.idleOpacity
      scale: (taskSlot.hovered ? 1.1 : 1.0) * taskSlot.pressScale

      Behavior on scale { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }
    }

    // Windows 11-style active/open/urgent indicator bar
    Rectangle {
      readonly property int indicatorLength: (taskSlot.focused || taskSlot.urgent)
        ? Math.round(taskSlot.taskbar.slotSize * 0.42)
        : (taskSlot.windowCount > 1 ? Math.round(taskSlot.taskbar.slotSize * 0.28) : Math.round(taskSlot.taskbar.slotSize * 0.16))

      visible: taskSlot.windowCount > 0
      width: taskSlot.taskbar.vertical ? taskSlot.taskbar.indicatorThickness : indicatorLength
      height: taskSlot.taskbar.vertical ? indicatorLength : taskSlot.taskbar.indicatorThickness
      radius: Math.max(1, Math.round(taskSlot.taskbar.indicatorThickness / 2))
      color: taskSlot.urgent
        ? Commons.Color.urgent
        : (taskSlot.focused ? Commons.Color.accent : (taskSlot.taskbar.bar ? taskSlot.taskbar.bar.barForeground : Commons.Color.bar.text))
      opacity: (taskSlot.focused || taskSlot.urgent) ? 1.0 : (taskSlot.allMinimized ? 0.45 : 0.8)
      anchors.horizontalCenter: taskSlot.taskbar.vertical ? undefined : parent.horizontalCenter
      anchors.bottom: taskSlot.taskbar.vertical ? undefined : parent.bottom
      anchors.bottomMargin: taskSlot.taskbar.vertical ? 0 : taskSlot.taskbar.indicatorMargin
      anchors.verticalCenter: taskSlot.taskbar.vertical ? parent.verticalCenter : undefined
      anchors.left: (taskSlot.taskbar.bar && taskSlot.taskbar.bar.position === "left") ? parent.left : undefined
      anchors.leftMargin: (taskSlot.taskbar.bar && taskSlot.taskbar.bar.position === "left") ? taskSlot.taskbar.indicatorMargin : 0
      anchors.right: (taskSlot.taskbar.bar && taskSlot.taskbar.bar.position === "right") ? parent.right : undefined
      anchors.rightMargin: (taskSlot.taskbar.bar && taskSlot.taskbar.bar.position === "right") ? taskSlot.taskbar.indicatorMargin : 0

      Behavior on width { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }
    }

    // Browser profile avatar badge in bottom-right corner
    Rectangle {
      id: profileBadgeContainer
      visible: !!taskSlot.profileBadge
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.rightMargin: taskSlot.taskbar.tallBar ? Style.space(2) : Style.space(1)
      anchors.bottomMargin: taskSlot.taskbar.vertical ? Style.space(2) : (taskSlot.taskbar.indicatorMargin + taskSlot.taskbar.indicatorThickness + 1)
      width: taskSlot.taskbar.profileBadgeSize + 2
      height: taskSlot.taskbar.profileBadgeSize + 2
      radius: width / 2
      color: Commons.Color.bar.background
      border.width: 1
      border.color: Util.alpha(Commons.Color.popups.border, 0.7)
      opacity: taskSlot.allMinimized ? 0.78 : 1.0

      ProfileAvatar {
        anchors.centerIn: parent
        width: taskSlot.taskbar.profileBadgeSize - 2
        height: taskSlot.taskbar.profileBadgeSize - 2
        picturePath: taskSlot.profileBadge ? (taskSlot.profileBadge.picturePath || "") : ""
        initial: taskSlot.profileBadge ? (taskSlot.profileBadge.initial || "?") : ""
        pixelSize: Math.max(7, Math.round(taskSlot.taskbar.profileBadgeSize * 0.58))
      }
    }

    // Window count badge when 2+ windows are open
    Rectangle {
      visible: taskSlot.windowCount > 1
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.topMargin: taskSlot.taskbar.tallBar ? Style.space(2) : Style.space(1)
      anchors.rightMargin: taskSlot.taskbar.tallBar ? Style.space(2) : Style.space(1)
      width: Math.max(taskSlot.taskbar.badgeSize, countTxt.implicitWidth + Style.space(4))
      height: taskSlot.taskbar.badgeSize
      radius: height / 2
      color: taskSlot.focused ? Commons.Color.accent : Commons.Color.popups.background
      border.width: 1
      border.color: Commons.Color.popups.border

      Text {
        id: countTxt
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: Commons.I18n.formatNumber(taskSlot.windowCount)
        color: taskSlot.focused ? Commons.Color.background : Commons.Color.popups.text
        font.family: Style.font.family
        font.pixelSize: taskSlot.taskbar.tallBar ? Math.max(8, Style.font.caption - 1) : Math.max(7, Style.font.caption - 2)
        font.bold: true
      }
    }

    // Urgency notification dot in top-left corner
    Rectangle {
      visible: taskSlot.urgent
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.topMargin: Style.space(2)
      anchors.leftMargin: Style.space(2)
      width: Style.space(6)
      height: Style.space(6)
      radius: width / 2
      color: Commons.Color.urgent
    }
  }

  MouseArea {
    id: slotMouse
    anchors.fill: parent
    hoverEnabled: true
    preventStealing: true
    cursorShape: taskSlot.lifted ? Qt.ClosedHandCursor : Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

    property point pressPoint
    property int dragButton: Qt.NoButton
    property bool didDrag: false

    onEntered: {
      taskSlot.taskbar.hoveredSlotKey = taskSlot.key
      if (taskSlot.taskbar.hoverPreview && taskSlot.windowCount > 0) {
        taskSlot.taskbar.scheduleHoverPreview(taskSlot.key, taskSlot)
      } else if (taskSlot.taskbar.pickerKey.length > 0 && taskSlot.taskbar.pickerTriggerMode === "hover") {
        taskSlot.taskbar.closePopouts()
      }
      if ((!taskSlot.taskbar.hoverPreview || taskSlot.windowCount === 0)
          && !taskSlot.taskbar.draggingItem
          && taskSlot.taskbar.bar
          && taskSlot.taskbar.pickerKey.length === 0
          && taskSlot.taskbar.menuKey.length === 0
          && !taskSlot.taskbar.settingsOpen) {
        var rawLabel = ""
        if (taskSlot.modelData && taskSlot.modelData.split && taskSlot.windowCount === 1) {
          var w = taskSlot.modelData.windows[0]
          var baseTitle = (w.toplevel && w.toplevel.title) ? w.toplevel.title : (w.title || taskSlot.appLabel)
          var rawTitle = BrowserProfiles.formatWindowTooltipWithProfile(baseTitle, taskSlot.profileBadge || w.profile)
          rawLabel = w.minimized
            ? TaskbarModel.formatTemplate(taskSlot.strings.t("taskbar.minimizedPrefix"), rawTitle)
            : rawTitle
        } else {
          var baseSummary = taskSlot.windowCount > 1
            ? TaskbarModel.formatTemplate(
                taskSlot.strings.t("taskbar.windowCount"),
                taskSlot.appLabel,
                Commons.I18n.formatNumber(taskSlot.windowCount)
              )
            : taskSlot.appLabel
          rawLabel = BrowserProfiles.formatWindowTooltipWithProfile(baseSummary, taskSlot.profileBadge)
        }
        taskSlot.taskbar.bar.showTooltip(taskSlot, TaskbarModel.sanitizeTooltipText(rawLabel, 96))
      }
    }
    onExited: {
      if (taskSlot.taskbar.hoveredSlotKey === taskSlot.key) taskSlot.taskbar.hoveredSlotKey = ""
      taskSlot.taskbar.clearPendingHoverForKey(taskSlot.key)
      taskSlot.taskbar.scheduleHoverClose()
      if (taskSlot.taskbar.bar) taskSlot.taskbar.bar.hideTooltip(taskSlot)
    }

    onPressed: function(event) {
      slotMouse.didDrag = false
      slotMouse.dragButton = Qt.NoButton
      if (event.button === Qt.RightButton || event.button === Qt.MiddleButton) {
        slotMouse.dragButton = event.button
        slotMouse.pressPoint = taskSlot.mapToItem(taskSlot.dragSpace, event.x, event.y)
      }
    }

    onPositionChanged: function(event) {
      if (slotMouse.dragButton === Qt.NoButton || !(slotMouse.pressedButtons & slotMouse.dragButton)) return
      var pt = taskSlot.mapToItem(taskSlot.dragSpace, event.x, event.y)
      var delta = taskSlot.taskbar.vertical ? (pt.y - slotMouse.pressPoint.y) : (pt.x - slotMouse.pressPoint.x)
      if (!taskSlot.taskbar.draggingItem) {
        if (Math.abs(delta) < Style.space(6)) return
        slotMouse.didDrag = true
        if (taskSlot.taskbar.bar) taskSlot.taskbar.bar.hideTooltip(taskSlot)
        taskSlot.taskbar.closePopouts()
        taskSlot.taskbar.dropIndex = taskSlot.index
        taskSlot.taskbar.dragIndex = taskSlot.index
      }
      if (!taskSlot.lifted) return
      var minOffset = -taskSlot.index * taskSlot.taskbar.slotStride
      var maxOffset = Math.max(0, taskSlot.totalSlots - 1 - taskSlot.index) * taskSlot.taskbar.slotStride
      taskSlot.taskbar.dragOffset = Math.max(minOffset, Math.min(maxOffset, delta))
      taskSlot.taskbar.dropIndex = TaskbarModel.computeDropIndex(
        taskSlot.index,
        taskSlot.taskbar.dragOffset,
        taskSlot.taskbar.slotStride,
        taskSlot.totalSlots
      )
    }

    onReleased: function(event) {
      slotMouse.dragButton = Qt.NoButton
      if (!taskSlot.lifted) return
      var from = taskSlot.taskbar.dragIndex
      var to = taskSlot.taskbar.dropIndex
      slotMouse.didDrag = true
      Qt.callLater(function() { if (slotMouse) slotMouse.didDrag = false })
      taskSlot.taskbar.endItemDrag()
      taskSlot.taskbar.moveTaskbarItem(from, to)
    }

    onCanceled: {
      slotMouse.dragButton = Qt.NoButton
      slotMouse.didDrag = false
      if (taskSlot.lifted) taskSlot.taskbar.endItemDrag()
    }

    onClicked: function(event) {
      if (slotMouse.didDrag && event.button !== Qt.LeftButton) {
        slotMouse.didDrag = false
        return
      }
      taskSlot.triggerPress(event.button)
    }
  }
}
