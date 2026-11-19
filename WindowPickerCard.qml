import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "TaskbarModel.js" as TaskbarModel

// Upward window-picker popup for grouped taskbar applications.
PopupCard {
  id: root

  required property var strings
  property var item: null
  property string fallbackLabel: ""

  signal windowActivated(var win)
  signal windowClosed(var win)

  readonly property var windows: root.item && root.item.windows ? root.item.windows : []
  onWindowsChanged: if (root.open && windows.length === 0) Qt.callLater(root.close)

  padding: Style.spacing.sm
  contentWidth: root.fittedContentWidth(Style.space(290))
  contentHeight: root.fittedContentHeight(Math.min(Style.space(220), pickerColumn.implicitHeight))

  Flickable {
    anchors.fill: parent
    contentHeight: pickerColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: pickerColumn
      width: parent.width
      spacing: Style.space(2)

      Repeater {
        model: root.windows

        delegate: Rectangle {
          id: pickerRow
          required property var modelData
          readonly property bool isActive: !modelData.minimized && !!modelData.toplevel && !!modelData.toplevel.activated
          readonly property string baseTitle: modelData.title || root.fallbackLabel
          readonly property string winTitle: modelData.minimized
            ? TaskbarModel.formatTemplate(root.strings.t("taskbar.minimizedPrefix"), baseTitle)
            : baseTitle

          width: pickerColumn.width
          height: Style.spacing.popupRowHeight
          radius: Style.cornerRadius
          color: pickerRowMouse.containsMouse ? Style.hoverFill : (isActive ? Style.selectedFill : "transparent")

          Rectangle {
            id: winDot
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.sm
            width: Style.space(6)
            height: Style.space(6)
            radius: width / 2
            color: pickerRow.isActive ? Commons.Color.accent : Commons.Color.popups.text
            opacity: pickerRow.modelData.minimized ? 0.35 : (pickerRow.isActive ? 1.0 : 0.7)
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: winDot.right
            anchors.leftMargin: Style.spacing.sm
            anchors.right: wsBadge.left
            anchors.rightMargin: Style.spacing.xs
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: pickerRow.winTitle
            color: Commons.Color.popups.text
            opacity: pickerRow.modelData.minimized ? 0.7 : 1.0
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.bold: pickerRow.isActive
          }

          Text {
            id: wsBadge
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: closeBtn.left
            anchors.rightMargin: Style.spacing.xs
            visible: !pickerRow.modelData.minimized && pickerRow.modelData.workspaceId >= 1
            textFormat: Text.PlainText
            text: TaskbarModel.formatTemplate(
              root.strings.t("taskbar.workspaceBadge"),
              Commons.I18n.formatNumber(pickerRow.modelData.workspaceId)
            )
            color: Commons.Color.popups.text
            opacity: 0.5
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          MouseArea {
            id: pickerRowMouse
            anchors.left: parent.left
            anchors.right: closeBtn.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.windowActivated(pickerRow.modelData)
              root.close()
            }
          }

          Rectangle {
            id: closeBtn
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.xs
            width: Style.space(20)
            height: Style.space(20)
            radius: Style.cornerRadius
            color: closeMouse.containsMouse ? Style.hoverFill : "transparent"

            Text {
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: "×"
              color: Commons.Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }

            MouseArea {
              id: closeMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.windowClosed(pickerRow.modelData)
            }
          }
        }
      }
    }
  }
}
