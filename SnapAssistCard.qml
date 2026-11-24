import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Windows 11-style Snap Assist card showing candidate windows for the remaining zone.
BorderSurface {
  id: root

  required property var strings
  property var candidates: []
  property int selectedIndex: -1
  property real maxWidth: Style.space(520)
  property real maxHeight: Style.space(420)

  signal windowPicked(var candidate)
  signal hoveredIndexChanged(int idx)
  signal closeRequested()

  onSelectedIndexChanged: {
    if (selectedIndex < 0 || root.candidates.length === 0) return
    var row = Math.floor(selectedIndex / Math.max(1, root.columns))
    var topY = row * (root.tileH + root.tileGap)
    var bottomY = topY + root.tileH
    var maxY = Math.max(0, assistFlickable.contentHeight - assistFlickable.height)
    if (topY < assistFlickable.contentY) {
      assistFlickable.contentY = Math.max(0, topY)
    } else if (bottomY > assistFlickable.contentY + assistFlickable.height) {
      assistFlickable.contentY = Math.min(maxY, bottomY - assistFlickable.height)
    }
  }

  readonly property int columns: (root.candidates.length >= 2 && root.maxWidth >= Style.space(420)) ? 2 : 1
  readonly property int rowCount: Math.max(1, Math.ceil(root.candidates.length / root.columns))
  readonly property int tileGap: Style.spacing.sm
  readonly property int tileW: root.columns === 2 ? Style.space(220) : Style.space(280)
  readonly property int tileH: Style.space(58)
  readonly property int gridW: root.columns * root.tileW + Math.max(0, root.columns - 1) * root.tileGap
  readonly property int gridH: root.rowCount * root.tileH + Math.max(0, root.rowCount - 1) * root.tileGap
  readonly property int headerH: headerRow.implicitHeight + Style.spacing.xs + hintText.implicitHeight
  readonly property int chromeW: contentLeftInset + contentRightInset
  readonly property int chromeH: contentTopInset + contentBottomInset
  readonly property int visibleGridH: Math.min(Math.max(root.tileH, root.maxHeight - chromeH - headerH - Style.spacing.md), gridH)

  LayoutMirroring.enabled: Commons.I18n.rightToLeft
  LayoutMirroring.childrenInherit: true

  padding: Style.spacing.popupPadding
  width: Math.min(root.maxWidth, Math.max(Style.space(280), gridW + chromeW))
  height: Math.min(root.maxHeight, visibleGridH + headerH + Style.spacing.md + chromeH)
  radius: Math.max(Style.space(10), Style.cornerRadius)
  color: Commons.Color.popups.background
  borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Style.normalBorderWidth)

  Column {
    id: contentCol
    x: root.contentLeftInset
    y: root.contentTopInset
    width: root.width - root.chromeW
    spacing: Style.spacing.sm

    Column {
      width: parent.width
      spacing: Style.space(2)

      RowLayout {
        id: headerRow
        width: parent.width
        spacing: Style.spacing.sm

        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: root.strings.t("snapAssist.title")
          color: Commons.Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
          font.bold: true
          elide: Text.ElideRight
        }

        Rectangle {
          width: Style.space(22)
          height: Style.space(22)
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
            onClicked: root.closeRequested()
          }
        }
      }

      Text {
        id: hintText
        width: parent.width
        textFormat: Text.PlainText
        text: root.strings.t("snapAssist.hint")
        color: Commons.Color.popups.text
        opacity: 0.65
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    Flickable {
      id: assistFlickable
      width: parent.width
      height: root.visibleGridH
      contentWidth: width
      contentHeight: candidateGrid.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Grid {
        id: candidateGrid
        width: parent.width
        columns: root.columns
        columnSpacing: root.tileGap
        rowSpacing: root.tileGap

        Repeater {
          model: root.candidates

          delegate: Rectangle {
            id: candidateTile
            required property int index
            required property var modelData

            readonly property bool selected: root.selectedIndex === index
            readonly property bool hovered: tileMouse.containsMouse
            readonly property real cardWidth: root.columns === 1
              ? candidateGrid.width
              : Math.floor((candidateGrid.width - root.tileGap) / 2)

            width: cardWidth
            height: root.tileH
            radius: Math.max(Style.space(6), Style.cornerRadius)
            color: selected ? Style.selectedFill : (hovered ? Style.hoverFill : "transparent")
            border.width: 1
            border.color: selected ? Commons.Color.accent : (hovered ? Style.normalBorderColor : Commons.Color.popups.border)

            Behavior on color { ColorAnimation { duration: Style.duration(90) } }

            RowLayout {
              anchors.fill: parent
              anchors.margins: Style.spacing.sm
              spacing: Style.spacing.sm

              Image {
                Layout.preferredWidth: Style.space(28)
                Layout.preferredHeight: Style.space(28)
                Layout.alignment: Qt.AlignVCenter
                sourceSize: Qt.size(Style.space(56), Style.space(56))
                source: candidateTile.modelData.iconSource || ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                mipmap: true
              }

              Column {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: Style.space(2)

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: candidateTile.modelData.appName || ""
                  color: Commons.Color.popups.text
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: candidateTile.modelData.title || ""
                  color: Commons.Color.popups.text
                  opacity: 0.72
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }
            }

            MouseArea {
              id: tileMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: root.hoveredIndexChanged(candidateTile.index)
              onClicked: root.windowPicked(candidateTile.modelData)
            }
          }
        }
      }
    }
  }
}
