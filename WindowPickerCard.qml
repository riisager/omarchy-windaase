import QtQuick
import QtQuick.Layouts
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "TaskbarModel.js" as TaskbarModel

// Windows 11-style taskbar preview popup with live window thumbnails.
PopupCard {
  id: root

  required property var strings
  property var item: null
  property string fallbackLabel: ""
  property string appIconSource: ""

  signal windowActivated(var win)
  signal windowClosed(var win)

  readonly property var windows: root.item && root.item.windows ? root.item.windows : []
  readonly property bool verticalBar: !!root.bar && root.bar.vertical
  readonly property int tileW: Style.space(220)
  readonly property int tileGap: Style.spacing.sm
  readonly property int thumbW: tileW - Style.spacing.sm * 2
  readonly property int thumbH: Style.space(118)
  readonly property int headerH: Style.space(24)
  readonly property int tileH: Style.spacing.xs + headerH + Style.spacing.xs + thumbH + Style.spacing.sm
  readonly property int horizontalInset: padding * 2 + Border.left(borderSpec) + Border.right(borderSpec)
  readonly property int count: Math.max(1, root.windows.length)
  readonly property int desiredContentW: root.verticalBar ? tileW : (count * tileW + Math.max(0, count - 1) * tileGap)
  readonly property int desiredContentH: root.verticalBar ? (count * tileH + Math.max(0, count - 1) * tileGap) : tileH

  function refreshAnchor() {
    if (root.open && root.anchor && typeof root.anchor.updateAnchor === "function") {
      Qt.callLater(function() {
        if (root.open && root.anchor) root.anchor.updateAnchor()
      })
    }
  }

  onOpenChanged: {
    if (open) {
      previewFlickable.contentX = 0
      previewFlickable.contentY = 0
      refreshAnchor()
    }
  }
  onItemChanged: {
    previewFlickable.contentX = 0
    previewFlickable.contentY = 0
    refreshAnchor()
  }
  onAnchorItemChanged: refreshAnchor()
  onContentWidthChanged: refreshAnchor()
  onContentHeightChanged: refreshAnchor()
  onWindowsChanged: if (root.open && windows.length === 0) Qt.callLater(root.close)

  padding: Style.spacing.sm
  contentWidth: root.fittedContentWidth(desiredContentW + horizontalInset)
  contentHeight: root.fittedContentHeight(desiredContentH)

  Flickable {
    id: previewFlickable
    anchors.fill: parent
    contentWidth: previewGrid.implicitWidth
    contentHeight: previewGrid.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    WheelHandler {
      acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
      enabled: !root.verticalBar && previewFlickable.contentWidth > previewFlickable.width
      onWheel: function(event) {
        var maxX = Math.max(0, previewFlickable.contentWidth - previewFlickable.width)
        var delta = Math.abs(event.pixelDelta.x) > Math.abs(event.pixelDelta.y)
          ? (event.pixelDelta.x !== 0 ? -event.pixelDelta.x : -event.angleDelta.y / 2)
          : (event.pixelDelta.y !== 0 ? -event.pixelDelta.y : -event.angleDelta.y / 2)
        previewFlickable.contentX = Math.max(0, Math.min(maxX, previewFlickable.contentX + delta))
      }
    }

    Grid {
      id: previewGrid
      columns: root.verticalBar ? 1 : Math.max(1, root.windows.length)
      columnSpacing: root.tileGap
      rowSpacing: root.tileGap

      Repeater {
        model: root.windows

        delegate: Rectangle {
          id: previewTile
          required property var modelData

          readonly property bool isActive: !modelData.minimized && !!modelData.toplevel && !!modelData.toplevel.activated
          readonly property bool tileHovered: tileMouse.containsMouse || closeMouse.containsMouse
          readonly property var winProfile: modelData.profile || null
          readonly property var captureToplevel: modelData && modelData.toplevel ? modelData.toplevel : null
          readonly property bool canLiveCapture: root.open && !!captureToplevel && !modelData.minimized
          readonly property string baseTitle: TaskbarModel.formatWindowTooltipWithProfile(
            modelData.title || root.fallbackLabel,
            winProfile
          )
          readonly property string winTitle: modelData.minimized
            ? TaskbarModel.formatTemplate(root.strings.t("taskbar.minimizedPrefix"), baseTitle)
            : baseTitle

          width: root.tileW
          height: root.tileH
          radius: Math.max(Style.space(6), Style.cornerRadius)
          color: tileHovered ? Style.hoverFill : (isActive ? Style.selectedFill : "transparent")
          border.width: 1
          border.color: tileHovered ? Commons.Color.accent : (isActive ? Style.normalBorderColor : Util.alpha(Commons.Color.popups.border, 0.6))

          Behavior on color { ColorAnimation { duration: Style.duration(90) } }

          MouseArea {
            id: tileMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.windowActivated(previewTile.modelData)
              root.close()
            }
          }

          RowLayout {
            id: headerRow
            anchors.top: parent.top
            anchors.topMargin: Style.spacing.xs
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Style.spacing.sm
            anchors.rightMargin: Style.spacing.sm
            height: root.headerH
            spacing: Style.spacing.xs

            Item {
              Layout.preferredWidth: Style.space(16)
              Layout.preferredHeight: Style.space(16)
              Layout.alignment: Qt.AlignVCenter
              opacity: previewTile.modelData.minimized ? 0.65 : 1.0

              ProfileAvatar {
                anchors.fill: parent
                visible: !!previewTile.winProfile
                picturePath: previewTile.winProfile ? (previewTile.winProfile.picturePath || "") : ""
                initial: previewTile.winProfile ? (previewTile.winProfile.initial || "?") : ""
                pixelSize: Math.max(8, Math.round(Style.space(16) * 0.56))
                borderWidth: 1
                borderColor: previewTile.isActive ? Commons.Color.accent : Commons.Color.popups.border
              }

              Image {
                anchors.fill: parent
                visible: !previewTile.winProfile
                source: root.appIconSource
                sourceSize: Qt.size(Style.space(32), Style.space(32))
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                mipmap: true
              }
            }

            Text {
              Layout.fillWidth: true
              Layout.alignment: Qt.AlignVCenter
              elide: Text.ElideRight
              textFormat: Text.PlainText
              text: previewTile.winTitle
              color: Commons.Color.popups.text
              opacity: previewTile.modelData.minimized ? 0.72 : 1.0
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: previewTile.isActive
            }

            Text {
              Layout.alignment: Qt.AlignVCenter
              visible: !previewTile.modelData.minimized && previewTile.modelData.workspaceId >= 1
              textFormat: Text.PlainText
              text: TaskbarModel.formatTemplate(
                root.strings.t("taskbar.workspaceBadge"),
                Commons.I18n.formatNumber(previewTile.modelData.workspaceId)
              )
              color: Commons.Color.popups.text
              opacity: 0.55
              font.family: Style.font.family
              font.pixelSize: Math.max(9, Style.font.caption - 1)
            }

            Rectangle {
              id: closeBtn
              Layout.preferredWidth: Style.space(20)
              Layout.preferredHeight: Style.space(20)
              Layout.alignment: Qt.AlignVCenter
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
                onClicked: root.windowClosed(previewTile.modelData)
              }
            }
          }

          Rectangle {
            id: thumbBox
            anchors.top: headerRow.bottom
            anchors.topMargin: Style.spacing.xs
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.thumbW
            height: root.thumbH
            radius: Math.max(Style.space(4), Math.round(Style.cornerRadius * 0.75))
            clip: true
            color: Util.alpha(Commons.Color.popups.text, 0.06)
            border.width: 1
            border.color: previewTile.isActive ? Util.alpha(Commons.Color.accent, 0.55) : Util.alpha(Commons.Color.popups.border, 0.45)

            Image {
              anchors.centerIn: parent
              width: Style.space(34)
              height: Style.space(34)
              sourceSize: Qt.size(Style.space(68), Style.space(68))
              source: root.appIconSource
              fillMode: Image.PreserveAspectFit
              asynchronous: true
              smooth: true
              mipmap: true
              opacity: previewTile.modelData.minimized ? 0.55 : 0.85
              visible: !liveLoader.hasLiveFrame
            }

            Loader {
              id: liveLoader
              anchors.centerIn: parent
              active: previewTile.canLiveCapture
              readonly property bool hasLiveFrame: !!item && !!item.hasContent

              sourceComponent: Component {
                ScreencopyView {
                  captureSource: previewTile.captureToplevel
                  live: previewTile.canLiveCapture
                  paintCursor: false
                  constraintSize: Qt.size(thumbBox.width, thumbBox.height)
                  opacity: hasContent ? 1.0 : 0.0

                  Behavior on opacity { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }
                }
              }
            }
          }
        }
      }
    }
  }
}
