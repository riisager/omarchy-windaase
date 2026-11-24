import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "TaskbarModel.js" as TaskbarModel
import "js/MonitorLayout.js" as MonitorLayout

// Interactive 2D physical monitor arrangement canvas with magnetic edge snapping
// and disabled-display chips at bottom-left. LTR coordinates preserved regardless of RTL.
Rectangle {
  id: canvasFrame

  required property var strings
  property var draftMonitors: []
  property var disabledMonitors: []
  property string selectedKey: ""
  property int enabledCount: 0
  property bool interactive: true

  property string draggingKey: ""
  property var dragProjection: null
  property point dragStartPoint: Qt.point(0, 0)
  property int dragStartLogicalX: 0
  property int dragStartLogicalY: 0
  property int dragPreviewX: 0
  property int dragPreviewY: 0
  property bool dragSnappedX: false
  property bool dragSnappedY: false

  readonly property bool dragging: draggingKey !== ""
  readonly property var canvasProjection: MonitorLayout.computeCanvasProjection(
    canvasFrame.draftMonitors,
    Math.max(320, canvasArea.width),
    Math.max(180, canvasArea.height),
    Style.space(28)
  )
  readonly property var activeProjection: (canvasFrame.draggingKey !== "" && canvasFrame.dragProjection)
    ? canvasFrame.dragProjection
    : canvasFrame.canvasProjection

  signal monitorSelected(string matchKey)
  signal monitorMoved(string matchKey, int newX, int newY)

  function cancelDrag() {
    canvasFrame.draggingKey = ""
    canvasFrame.dragProjection = null
    canvasFrame.dragSnappedX = false
    canvasFrame.dragSnappedY = false
  }

  LayoutMirroring.enabled: false
  radius: Style.cornerRadius
  color: Util.alpha(Commons.Color.menu.text, 0.04)
  border.width: Math.max(1, Style.normalBorderWidth)
  border.color: Util.alpha(Commons.Color.menu.border, 0.7)
  clip: true

  Item {
    id: canvasArea
    anchors.fill: parent

    Repeater {
      model: canvasFrame.draftMonitors

      delegate: Rectangle {
        id: monBox
        required property int index
        required property var modelData

        readonly property string monKey: String(modelData.matchKey || modelData.name || "")
        readonly property bool isDraggingMe: canvasFrame.draggingKey === monKey
        readonly property bool isSelected: canvasFrame.selectedKey === monKey
        readonly property bool isSnapping: isDraggingMe && (canvasFrame.dragSnappedX || canvasFrame.dragSnappedY)
        readonly property var proj: canvasFrame.activeProjection
        readonly property real posX: isDraggingMe ? canvasFrame.dragPreviewX : Number(modelData.x || 0)
        readonly property real posY: isDraggingMe ? canvasFrame.dragPreviewY : Number(modelData.y || 0)
        readonly property real logW: Math.max(120, Number(modelData.logicalW || 1920))
        readonly property real logH: Math.max(120, Number(modelData.logicalH || 1080))

        visible: modelData.enabled !== false
        x: Math.round(proj.originX + posX * proj.scale)
        y: Math.round(proj.originY + posY * proj.scale)
        width: Math.max(Style.space(52), Math.round(logW * proj.scale))
        height: Math.max(Style.space(36), Math.round(logH * proj.scale))
        z: isDraggingMe ? 10 : (isSelected ? 5 : 1)
        radius: Math.max(Style.space(6), Style.cornerRadius)
        color: isSelected
          ? Util.alpha(Commons.Color.accent, 0.22)
          : (monMouse.containsMouse ? Style.hoverFill : Util.alpha(Commons.Color.menu.background, 0.92))
        border.width: (isSelected || isSnapping) ? 2 : 1
        border.color: (isSelected || isSnapping)
          ? Commons.Color.accent
          : Util.alpha(Commons.Color.menu.border, 0.9)

        Behavior on x {
          enabled: canvasFrame.draggingKey === ""
          NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic }
        }
        Behavior on y {
          enabled: canvasFrame.draggingKey === ""
          NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic }
        }
        Behavior on color { ColorAnimation { duration: Style.duration(90) } }

        Column {
          anchors.centerIn: parent
          width: Math.max(Style.space(28), monBox.width - Style.spacing.sm * 2)
          spacing: Style.space(2)

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            textFormat: Text.PlainText
            text: Commons.I18n.formatNumber(modelData.number || (monBox.index + 1))
            color: isSelected ? Commons.Color.accent : Commons.Color.menu.text
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            elide: Text.ElideRight
            visible: monBox.height >= Style.space(64)
            text: TaskbarModel.sanitizePlainLabel(modelData.model || modelData.name || "", 32)
            color: Commons.Color.menu.text
            opacity: 0.85
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            elide: Text.ElideRight
            visible: monBox.height >= Style.space(86)
            text: Commons.I18n.formatNumber(Math.round(monBox.logW)) + " × " + Commons.I18n.formatNumber(Math.round(monBox.logH))
            color: Commons.Color.menu.text
            opacity: 0.62
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }

        MouseArea {
          id: monMouse
          anchors.fill: parent
          hoverEnabled: true
          enabled: canvasFrame.interactive
          cursorShape: canvasFrame.draggingKey === monBox.monKey ? Qt.ClosedHandCursor : Qt.OpenHandCursor

          onPressed: function(mouse) {
            canvasFrame.monitorSelected(monBox.monKey)
            if (canvasFrame.enabledCount <= 1) return
            var pt = monMouse.mapToItem(canvasArea, mouse.x, mouse.y)
            canvasFrame.dragProjection = canvasFrame.canvasProjection
            canvasFrame.dragStartPoint = pt
            canvasFrame.dragStartLogicalX = Math.round(Number(monBox.modelData.x) || 0)
            canvasFrame.dragStartLogicalY = Math.round(Number(monBox.modelData.y) || 0)
            canvasFrame.dragPreviewX = canvasFrame.dragStartLogicalX
            canvasFrame.dragPreviewY = canvasFrame.dragStartLogicalY
            canvasFrame.dragSnappedX = false
            canvasFrame.dragSnappedY = false
            canvasFrame.draggingKey = monBox.monKey
          }

          onPositionChanged: function(mouse) {
            if (!pressed || canvasFrame.draggingKey !== monBox.monKey || !canvasFrame.dragProjection) return
            var pt = monMouse.mapToItem(canvasArea, mouse.x, mouse.y)
            var sc = Math.max(0.01, canvasFrame.dragProjection.scale)
            var rawX = Math.round(canvasFrame.dragStartLogicalX + (pt.x - canvasFrame.dragStartPoint.x) / sc)
            var rawY = Math.round(canvasFrame.dragStartLogicalY + (pt.y - canvasFrame.dragStartPoint.y) / sc)
            var margin = Style.space(6)
            var minLogX = Math.round((margin - canvasFrame.dragProjection.originX) / sc)
            var maxLogX = Math.round((Math.max(margin, canvasArea.width - monBox.width - margin) - canvasFrame.dragProjection.originX) / sc)
            var minLogY = Math.round((margin - canvasFrame.dragProjection.originY) / sc)
            var maxLogY = Math.round((Math.max(margin, canvasArea.height - monBox.height - margin) - canvasFrame.dragProjection.originY) / sc)
            rawX = Math.max(minLogX, Math.min(maxLogX, rawX))
            rawY = Math.max(minLogY, Math.min(maxLogY, rawY))
            var others = []
            var all = canvasFrame.draftMonitors || []
            for (var i = 0; i < all.length; i++) {
              var o = all[i]
              if (!o || o.enabled === false || String(o.matchKey) === monBox.monKey) continue
              others.push({ x: o.x, y: o.y, w: o.logicalW, h: o.logicalH, enabled: true })
            }
            var snapped = MonitorLayout.snapMonitorRect(
              { x: rawX, y: rawY, w: monBox.logW, h: monBox.logH },
              others,
              72
            )
            canvasFrame.dragPreviewX = snapped.x
            canvasFrame.dragPreviewY = snapped.y
            canvasFrame.dragSnappedX = snapped.snappedX
            canvasFrame.dragSnappedY = snapped.snappedY
          }

          function finishDrag() {
            if (canvasFrame.draggingKey !== monBox.monKey) return
            var finalX = canvasFrame.dragPreviewX
            var finalY = canvasFrame.dragPreviewY
            canvasFrame.cancelDrag()
            canvasFrame.monitorMoved(monBox.monKey, finalX, finalY)
          }

          onReleased: finishDrag()
          onCanceled: finishDrag()
        }
      }
    }

    // Disabled connected monitors bar at bottom-left of canvas
    Row {
      visible: canvasFrame.disabledMonitors.length > 0
      anchors.left: parent.left
      anchors.bottom: parent.bottom
      anchors.margins: Style.spacing.sm
      spacing: Style.spacing.xs
      z: 20

      Repeater {
        model: canvasFrame.disabledMonitors

        delegate: Rectangle {
          id: disChip
          required property var modelData
          readonly property string monKey: String(modelData.matchKey || modelData.name || "")
          readonly property bool isSelected: canvasFrame.selectedKey === monKey

          implicitWidth: disText.implicitWidth + Style.spacing.sm * 2
          implicitHeight: disText.implicitHeight + Style.space(6)
          radius: Style.cornerRadius
          color: isSelected
            ? Util.alpha(Commons.Color.accent, 0.18)
            : Util.alpha(Commons.Color.menu.background, 0.9)
          border.width: isSelected ? 2 : 1
          border.color: isSelected ? Commons.Color.accent : Util.alpha(Commons.Color.menu.border, 0.7)

          Text {
            id: disText
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: Commons.I18n.formatNumber(modelData.number || 0) + " · "
              + TaskbarModel.sanitizePlainLabel(modelData.name || "", 20) + " · "
              + (modelData.clamshellLocked ? canvasFrame.strings.t("display.clamshellTag") : canvasFrame.strings.t("display.disabledTag"))
            color: Commons.Color.menu.text
            opacity: 0.85
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: canvasFrame.monitorSelected(disChip.monKey)
          }
        }
      }
    }
  }
}
