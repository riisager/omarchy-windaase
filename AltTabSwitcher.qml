import QtQuick
import QtQuick.Layouts
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "TaskbarModel.js" as TaskbarModel

// Windows-style Alt+Tab live-thumbnail window switcher card.
BorderSurface {
  id: root

  required property var strings
  property var windows: []
  property int selectedIndex: 0
  property bool active: false
  property real maxWidth: Style.space(1160)
  property real maxHeight: Style.space(620)

  signal windowPicked(var win)

  readonly property int tileW: Style.space(204)
  readonly property int tileGap: Style.spacing.sm
  readonly property int thumbW: tileW - Style.spacing.sm * 2
  readonly property int thumbH: Style.space(112)
  readonly property int headerH: Style.space(22)
  readonly property int tileH: Style.spacing.xs + headerH + Style.spacing.xs + thumbH + Style.spacing.sm
  readonly property int chromeW: contentLeftInset + contentRightInset
  readonly property int chromeH: contentTopInset + contentBottomInset
  readonly property int maxColsByWidth: Math.max(
    1,
    Math.floor((root.maxWidth - root.chromeW + root.tileGap) / (root.tileW + root.tileGap))
  )
  readonly property int columns: Math.max(
    1,
    Math.min(5, Math.min(maxColsByWidth, Math.max(1, root.windows.length)))
  )
  readonly property int rowCount: Math.max(1, Math.ceil(Math.max(1, root.windows.length) / root.columns))
  readonly property int gridW: root.columns * root.tileW + Math.max(0, root.columns - 1) * root.tileGap
  readonly property int gridH: root.rowCount * root.tileH + Math.max(0, root.rowCount - 1) * root.tileGap
  readonly property int captionH: Style.space(22)
  readonly property int visibleGridH: Math.min(
    Math.max(root.tileH, root.maxHeight - root.chromeH - root.captionH - Style.spacing.sm),
    root.gridH
  )
  readonly property var selectedWindow: (root.selectedIndex >= 0 && root.selectedIndex < root.windows.length)
    ? root.windows[root.selectedIndex]
    : null
  readonly property string selectedCaption: {
    var w = root.selectedWindow
    if (!w) return ""
    var base = String(w.title || w.appName || "")
    return w.minimized ? TaskbarModel.formatTemplate(root.strings.t("taskbar.minimizedPrefix"), base) : base
  }

  function scrollToSelected() {
    if (root.selectedIndex < 0 || root.windows.length === 0) return
    var row = Math.floor(root.selectedIndex / Math.max(1, root.columns))
    var topY = row * (root.tileH + root.tileGap)
    var bottomY = topY + root.tileH
    var maxY = Math.max(0, switcherFlickable.contentHeight - switcherFlickable.height)
    if (topY < switcherFlickable.contentY) {
      switcherFlickable.contentY = Math.max(0, topY)
    } else if (bottomY > switcherFlickable.contentY + switcherFlickable.height) {
      switcherFlickable.contentY = Math.min(maxY, bottomY - switcherFlickable.height)
    }
  }

  onActiveChanged: {
    if (!active) switcherFlickable.contentY = 0
    else Qt.callLater(root.scrollToSelected)
  }
  onSelectedIndexChanged: root.scrollToSelected()

  LayoutMirroring.enabled: Commons.I18n.rightToLeft
  LayoutMirroring.childrenInherit: true

  padding: Style.spacing.popupPadding
  width: Math.min(root.maxWidth, Math.max(root.tileW + root.chromeW, root.gridW + root.chromeW))
  height: Math.min(root.maxHeight, root.visibleGridH + root.captionH + Style.spacing.sm + root.chromeH)
  radius: Math.max(Style.space(10), Style.cornerRadius)
  color: Commons.Color.popups.background
  borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Style.normalBorderWidth)

  Column {
    x: root.contentLeftInset
    y: root.contentTopInset
    width: root.width - root.chromeW
    spacing: Style.spacing.sm

    Flickable {
      id: switcherFlickable
      width: parent.width
      height: root.visibleGridH
      contentWidth: width
      contentHeight: switcherGrid.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Grid {
        id: switcherGrid
        anchors.horizontalCenter: parent.horizontalCenter
        columns: root.columns
        columnSpacing: root.tileGap
        rowSpacing: root.tileGap

        Repeater {
          model: root.windows

          delegate: Rectangle {
            id: tile
            required property int index
            required property var modelData

            readonly property bool selected: root.selectedIndex === index
            readonly property bool tileHovered: tileMouse.containsMouse
            readonly property bool canLiveCapture: root.active && !!modelData.toplevel && !modelData.minimized
            readonly property string baseTitle: String(modelData.title || modelData.appName || "")
            readonly property string displayTitle: modelData.minimized
              ? TaskbarModel.formatTemplate(root.strings.t("taskbar.minimizedPrefix"), baseTitle)
              : baseTitle

            width: root.tileW
            height: root.tileH
            radius: Math.max(Style.space(6), Style.cornerRadius)
            color: selected ? Style.selectedFill : (tileHovered ? Style.hoverFill : "transparent")
            border.width: selected ? 2 : 1
            border.color: selected
              ? Commons.Color.accent
              : (tileHovered ? Style.normalBorderColor : Util.alpha(Commons.Color.popups.border, 0.55))

            Behavior on color { ColorAnimation { duration: Style.duration(90) } }

            MouseArea {
              id: tileMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.windowPicked(tile.modelData)
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

              Image {
                Layout.preferredWidth: Style.space(16)
                Layout.preferredHeight: Style.space(16)
                Layout.alignment: Qt.AlignVCenter
                sourceSize: Qt.size(Style.space(32), Style.space(32))
                source: tile.modelData.iconSource || ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                mipmap: true
                opacity: tile.modelData.minimized ? 0.65 : 1.0
              }

              Text {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                textFormat: Text.PlainText
                elide: Text.ElideRight
                text: tile.displayTitle
                color: Commons.Color.popups.text
                opacity: tile.modelData.minimized ? 0.72 : 1.0
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: tile.selected
              }

              Rectangle {
                visible: !!tile.modelData.pinned
                Layout.preferredWidth: Style.space(6)
                Layout.preferredHeight: Style.space(6)
                Layout.alignment: Qt.AlignVCenter
                radius: width / 2
                color: Commons.Color.accent
              }

              Text {
                Layout.alignment: Qt.AlignVCenter
                visible: !tile.modelData.minimized && tile.modelData.workspaceId >= 1
                textFormat: Text.PlainText
                text: TaskbarModel.formatTemplate(
                  root.strings.t("taskbar.workspaceBadge"),
                  Commons.I18n.formatNumber(tile.modelData.workspaceId)
                )
                color: Commons.Color.popups.text
                opacity: 0.55
                font.family: Style.font.family
                font.pixelSize: Math.max(9, Style.font.caption - 1)
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
              border.color: tile.selected
                ? Util.alpha(Commons.Color.accent, 0.55)
                : Util.alpha(Commons.Color.popups.border, 0.4)

              Image {
                anchors.centerIn: parent
                width: Style.space(34)
                height: Style.space(34)
                sourceSize: Qt.size(Style.space(68), Style.space(68))
                source: tile.modelData.iconSource || ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                mipmap: true
                opacity: tile.modelData.minimized ? 0.55 : 0.85
                visible: !liveLoader.hasLiveFrame
              }

              Loader {
                id: liveLoader
                anchors.centerIn: parent
                active: tile.canLiveCapture
                readonly property bool hasLiveFrame: !!item && !!item.hasContent

                sourceComponent: Component {
                  ScreencopyView {
                    captureSource: tile.modelData.toplevel
                    live: tile.canLiveCapture
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

    Text {
      width: parent.width
      height: root.captionH
      verticalAlignment: Text.AlignVCenter
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      elide: Text.ElideMiddle
      text: root.selectedCaption
      color: Commons.Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      font.bold: true
    }
  }
}
