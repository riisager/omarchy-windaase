import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Commons as Commons

// Circular browser profile avatar with MultiEffect mask and initial fallback.
Item {
  id: root

  property string picturePath: ""
  property string initial: "?"
  property color fallbackColor: Commons.Color.accent
  property real fallbackOpacity: 1.0
  property color initialColor: Commons.Color.background
  property real pixelSize: Math.max(8, Math.round(Style.space(16) * 0.56))
  property int borderWidth: 0
  property color borderColor: "transparent"

  Rectangle {
    id: avatarMask
    anchors.fill: parent
    radius: width / 2
    color: "white"
    visible: false
    layer.enabled: avatarImg.visible
  }

  Item {
    anchors.fill: parent
    visible: avatarImg.status !== Image.Ready

    Rectangle {
      anchors.fill: parent
      radius: width / 2
      color: root.fallbackColor
      opacity: root.fallbackOpacity
    }

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: root.initial || "?"
      color: root.initialColor
      font.family: Style.font.family
      font.pixelSize: root.pixelSize
      font.bold: true
    }
  }

  Image {
    id: avatarImg
    anchors.fill: parent
    source: root.picturePath ? Util.fileUrl(root.picturePath) : ""
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

  Rectangle {
    anchors.fill: parent
    visible: root.borderWidth > 0
    radius: width / 2
    color: "transparent"
    border.width: root.borderWidth
    border.color: root.borderColor
  }
}
