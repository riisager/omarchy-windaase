import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Right-click context menu for taskbar items (profiles, window actions, split & settings).
PopupCard {
  id: root

  required property var strings
  property var item: null
  property string appKey: ""
  property bool hasEntry: false
  property bool running: false
  property bool allMinimized: false
  property bool splitWindows: false
  property bool showProfiles: false
  property var browserProfiles: []

  signal profileLaunched(string profileDir)
  signal newWindowRequested()
  signal minimizeRequested()
  signal restoreRequested()
  signal pinToggled(bool pinned)
  signal splitWindowsToggled()
  signal closeRequested()
  signal settingsRequested()

  onOpenChanged: if (open) menuFlickable.contentY = 0

  padding: Style.spacing.sm
  contentWidth: root.fittedContentWidth(root.showProfiles ? Style.space(260) : Style.space(230))
  contentHeight: root.fittedContentHeight(Math.min(Style.space(420), menuColumn.implicitHeight))

  Flickable {
    id: menuFlickable
    anchors.fill: parent
    contentHeight: menuColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: menuColumn
      width: menuFlickable.width

      Item {
        visible: root.showProfiles
        width: menuColumn.width
        height: visible ? Style.space(22) : 0

        Text {
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.controlPaddingX
          textFormat: Text.PlainText
          text: root.strings.t("taskbar.openProfile")
          color: Commons.Color.popups.text
          opacity: 0.6
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      Repeater {
        model: root.showProfiles ? root.browserProfiles : []

        delegate: Rectangle {
          id: profileRow
          required property var modelData

          width: menuColumn.width
          height: Style.spacing.popupRowHeight
          radius: Style.cornerRadius
          color: profileMouse.containsMouse ? Style.hoverFill : "transparent"

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.spacing.sm
            anchors.rightMargin: Style.spacing.sm
            spacing: Style.spacing.sm

            Item {
              Layout.preferredWidth: Style.space(18)
              Layout.preferredHeight: Style.space(18)

              Rectangle {
                id: avatarMask
                anchors.fill: parent
                radius: width / 2
                color: "white"
                visible: false
                layer.enabled: true
              }

              Item {
                anchors.fill: parent
                visible: avatarImg.status !== Image.Ready

                Rectangle {
                  anchors.fill: parent
                  radius: width / 2
                  color: Commons.Color.accent
                  opacity: 0.25
                }

                Text {
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: profileRow.modelData.initial
                  color: Commons.Color.popups.text
                  font.family: Style.font.family
                  font.pixelSize: Math.max(9, Style.font.caption)
                  font.bold: true
                }
              }

              Image {
                id: avatarImg
                anchors.fill: parent
                source: profileRow.modelData.picturePath ? Util.fileUrl(profileRow.modelData.picturePath) : ""
                sourceSize: Qt.size(Style.space(36), Style.space(36))
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                smooth: true
                mipmap: true
                visible: status === Image.Ready
                layer.enabled: visible
                layer.smooth: true
                layer.effect: MultiEffect {
                  maskEnabled: true
                  maskSource: avatarMask
                  maskThresholdMin: 0.3
                  maskSpreadAtMin: 0.3
                }
              }
            }

            Text {
              textFormat: Text.PlainText
              text: profileRow.modelData.name
              elide: Text.ElideRight
              Layout.fillWidth: true
              Layout.minimumWidth: Style.space(60)
              color: Commons.Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }

            Text {
              textFormat: Text.PlainText
              visible: profileRow.modelData.email.length > 0 && profileRow.modelData.email !== profileRow.modelData.name
              text: profileRow.modelData.email
              elide: Text.ElideRight
              Layout.maximumWidth: Style.space(125)
              color: Commons.Color.popups.text
              opacity: 0.55
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }

          MouseArea {
            id: profileMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.profileLaunched(profileRow.modelData.dir)
              root.close()
            }
          }
        }
      }

      Item {
        visible: root.showProfiles
        width: menuColumn.width
        height: visible ? Style.space(9) : 0

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.leftMargin: Style.spacing.sm
          anchors.rightMargin: Style.spacing.sm
          height: Math.max(1, Style.spacing.hairline)
          color: Commons.Color.popups.text
          opacity: 0.15
        }
      }

      TaskMenuRow {
        visible: root.hasEntry && root.running
        text: root.strings.t("taskbar.newWindow")
        onTriggered: root.newWindowRequested()
      }

      TaskMenuRow {
        visible: root.running && !root.allMinimized
        text: root.strings.t("taskbar.minimize")
        onTriggered: root.minimizeRequested()
      }

      TaskMenuRow {
        visible: root.running && root.allMinimized
        text: root.strings.t("taskbar.restore")
        onTriggered: root.restoreRequested()
      }

      TaskMenuRow {
        visible: root.hasEntry
        text: root.item && root.item.pinned ? root.strings.t("taskbar.unpin") : root.strings.t("taskbar.pin")
        onTriggered: root.pinToggled(!(root.item && root.item.pinned))
      }

      TaskMenuRow {
        visible: root.hasEntry
        text: root.strings.t("taskbar.splitWindows")
        checked: root.splitWindows
        onTriggered: root.splitWindowsToggled()
      }

      TaskMenuRow {
        visible: root.running
        text: (root.item && root.item.windows.length === 1) ? root.strings.t("taskbar.closeWindow") : root.strings.t("taskbar.closeAll")
        onTriggered: root.closeRequested()
      }

      Item {
        width: menuColumn.width
        height: Style.space(9)

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.leftMargin: Style.spacing.sm
          anchors.rightMargin: Style.spacing.sm
          height: Math.max(1, Style.spacing.hairline)
          color: Commons.Color.popups.text
          opacity: 0.15
        }
      }

      TaskMenuRow {
        text: root.strings.t("taskbar.settings")
        onTriggered: root.settingsRequested()
      }
    }
  }

  component TaskMenuRow: Rectangle {
    id: menuRow

    property string text: ""
    property bool checked: false
    signal triggered()

    width: parent ? parent.width : 0
    height: visible ? Style.spacing.popupRowHeight : 0
    radius: Style.cornerRadius
    color: rowMouse.containsMouse ? Style.hoverFill : "transparent"

    Text {
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.controlPaddingX
      anchors.right: checkMark.visible ? checkMark.left : parent.right
      anchors.rightMargin: Style.spacing.controlPaddingX
      textFormat: Text.PlainText
      elide: Text.ElideRight
      text: menuRow.text
      color: Commons.Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    Text {
      id: checkMark
      visible: menuRow.checked
      anchors.verticalCenter: parent.verticalCenter
      anchors.right: parent.right
      anchors.rightMargin: Style.spacing.controlPaddingX
      textFormat: Text.PlainText
      text: "✓"
      color: Commons.Color.accent
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        menuRow.triggered()
        root.close()
      }
    }
  }
}
