import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "TaskbarModel.js" as TaskbarModel

// Native Omarchy settings popup for taskbar sizing/layout and Hyprland toggles.
PopupCard {
  id: root

  required property var strings
  property int barSize: 26
  property int iconSize: 16
  property real configuredIconSize: 0
  property bool showAppsButton: true
  property bool twoLineClock: false
  property var hyprSettings: ({})

  signal barHeightRequested(int px)
  signal iconSizeRequested(int px)
  signal barPositionRequested(string pos)
  signal twoLineClockToggled(bool enabled)
  signal showAppsButtonToggled(bool enabled)
  signal hyprOptionToggled(string key, bool enabled)

  readonly property int maxIconPx: Math.max(16, root.barSize - 6)
  readonly property bool isAutoIcon: Number(root.configuredIconSize) <= 0
  readonly property int activeIconValue: isAutoIcon ? root.iconSize : Math.round(Number(root.configuredIconSize))

  padding: Style.spacing.popupPadding
  contentWidth: root.fittedContentWidth(Style.space(320))
  contentHeight: root.fittedContentHeight(Math.min(Style.space(520), settingsColumn.implicitHeight))

  Flickable {
    anchors.fill: parent
    contentWidth: width
    contentHeight: settingsColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: settingsColumn
      width: parent.width
      spacing: Style.spacing.sm

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.strings.t("settings.title")
        color: Commons.Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
        font.bold: true
        elide: Text.ElideRight
      }

      PanelSeparator {
        foreground: Commons.Color.popups.text
      }

      PanelSectionHeader {
        width: parent.width
        text: root.strings.t("settings.sectionTaskbar")
        foreground: Commons.Color.popups.text
      }

      // Bar height presets + fine slider
      RowLayout {
        width: parent.width
        spacing: Style.spacing.sm

        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: root.strings.t("settings.barHeight")
          color: Commons.Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          text: TaskbarModel.formatTemplate(
            root.strings.t("settings.pxValue"),
            Commons.I18n.formatNumber(Math.round(barHeightSlider.liveValue))
          )
          color: Commons.Color.popups.text
          opacity: 0.75
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      ButtonGroup {
        width: parent.width
        focusable: false
        foreground: Commons.Color.popups.text
        background: Commons.Color.popups.background
        accent: Commons.Color.accent
        fontSize: Style.font.caption
        options: [
          { value: "26", label: Commons.I18n.formatNumber(26) },
          { value: "34", label: Commons.I18n.formatNumber(34) },
          { value: "40", label: Commons.I18n.formatNumber(40) },
          { value: "46", label: Commons.I18n.formatNumber(46) }
        ]
        value: String(Math.round(root.barSize))
        onChanged: function(val) {
          var px = parseInt(val, 10)
          if (isFinite(px)) root.barHeightRequested(px)
        }
      }

      PanelSlider {
        id: barHeightSlider
        width: parent.width
        bar: root.bar
        minimum: 26
        maximum: 56
        step: 2
        integer: true
        value: Math.max(26, Math.min(56, Math.round(root.barSize)))
        trackColor: Style.selectedFillFor(Commons.Color.popups.text, Commons.Color.accent)
        fillColor: Commons.Color.accent
        knobColor: Commons.Color.popups.text
        tickColor: Commons.Color.popups.background
        onReleased: function(v) { root.barHeightRequested(Math.round(v)) }
      }

      // Icon size slider + Auto reset pill
      RowLayout {
        width: parent.width
        spacing: Style.spacing.sm

        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: root.strings.t("settings.iconSize")
          color: Commons.Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          text: (root.isAutoIcon && !iconSizeSlider.dragging)
            ? TaskbarModel.formatTemplate(
                root.strings.t("settings.autoValue"),
                Commons.I18n.formatNumber(root.iconSize)
              )
            : TaskbarModel.formatTemplate(
                root.strings.t("settings.pxValue"),
                Commons.I18n.formatNumber(Math.round(iconSizeSlider.liveValue))
              )
          color: Commons.Color.popups.text
          opacity: 0.75
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Button {
          text: root.strings.t("settings.auto")
          selected: root.isAutoIcon
          bordered: true
          focusable: false
          foreground: Commons.Color.popups.text
          background: Commons.Color.popups.background
          accent: Commons.Color.accent
          fontSize: Style.font.caption
          horizontalPadding: Style.spacing.sm
          verticalPadding: Style.space(2)
          onClicked: root.iconSizeRequested(0)
        }
      }

      PanelSlider {
        id: iconSizeSlider
        width: parent.width
        bar: root.bar
        minimum: 14
        maximum: root.maxIconPx
        step: 2
        integer: true
        value: Math.max(14, Math.min(root.maxIconPx, root.activeIconValue))
        trackColor: Style.selectedFillFor(Commons.Color.popups.text, Commons.Color.accent)
        fillColor: Commons.Color.accent
        knobColor: Commons.Color.popups.text
        tickColor: Commons.Color.popups.background
        onReleased: function(v) { root.iconSizeRequested(Math.round(v)) }
      }

      // Bar position
      RowLayout {
        width: parent.width
        spacing: Style.spacing.sm

        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: root.strings.t("settings.barPosition")
          color: Commons.Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        ButtonGroup {
          focusable: false
          foreground: Commons.Color.popups.text
          background: Commons.Color.popups.background
          accent: Commons.Color.accent
          fontSize: Style.font.caption
          options: [
            { value: "bottom", label: root.strings.t("settings.posBottom") },
            { value: "top", label: root.strings.t("settings.posTop") }
          ]
          value: root.bar ? String(root.bar.position || "bottom") : "bottom"
          onChanged: function(val) { root.barPositionRequested(val) }
        }
      }

      SettingToggleRow {
        label: root.strings.t("settings.twoLineClock")
        checked: root.twoLineClock
        onToggled: root.twoLineClockToggled(!root.twoLineClock)
      }

      SettingToggleRow {
        label: root.strings.t("settings.showAppsButton")
        checked: root.showAppsButton
        onToggled: root.showAppsButtonToggled(!root.showAppsButton)
      }

      PanelSeparator {
        foreground: Commons.Color.popups.text
      }

      PanelSectionHeader {
        width: parent.width
        text: root.strings.t("settings.sectionWindows")
        foreground: Commons.Color.popups.text
      }

      Repeater {
        model: [
          { key: "snap_layouts", labelKey: "settings.snapLayouts" },
          { key: "aero_snap", labelKey: "settings.aeroSnap" },
          { key: "hover_scroll", labelKey: "settings.hoverScroll" },
          { key: "soft_maximize", labelKey: "settings.softMaximize" },
          { key: "auto_raise", labelKey: "settings.autoRaise" },
          { key: "shortcuts", labelKey: "settings.shortcuts" }
        ]

        delegate: SettingToggleRow {
          required property var modelData
          readonly property bool isEnabled: !root.hyprSettings || root.hyprSettings[modelData.key] !== false

          label: root.strings.t(modelData.labelKey)
          checked: isEnabled
          onToggled: root.hyprOptionToggled(modelData.key, !isEnabled)
        }
      }
    }
  }

  component SettingToggleRow: Rectangle {
    id: toggleRow

    property string label: ""
    property bool checked: false
    signal toggled()

    width: parent ? parent.width : 0
    height: Math.max(Style.space(28), Style.spacing.popupRowHeight)
    radius: Style.cornerRadius
    color: rowMouse.containsMouse ? Style.hoverFill : "transparent"

    Text {
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.xs
      anchors.right: sw.left
      anchors.rightMargin: Style.spacing.sm
      textFormat: Text.PlainText
      text: toggleRow.label
      elide: Text.ElideRight
      color: Commons.Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    ToggleSwitch {
      id: sw
      anchors.verticalCenter: parent.verticalCenter
      anchors.right: parent.right
      anchors.rightMargin: Style.spacing.xs
      checked: toggleRow.checked
      trackHeight: 18
      interactive: false
      cursorRing: false
      foreground: Commons.Color.popups.text
      accent: Commons.Color.accent
    }

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: toggleRow.toggled()
    }
  }
}
