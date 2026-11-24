import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "TaskbarModel.js" as TaskbarModel

// Selected monitor property form: enable switch, scale presets, orientation, and mode.
Rectangle {
  id: root

  required property var strings
  property var selectedMonitor: null
  property int enabledCount: 0
  property bool selectedCanToggleEnabled: false
  property var selectedScaleOptions: []
  property string selectedCleanScale: "1"
  property var selectedModeOptions: []
  property bool interactive: true
  readonly property bool dropdownOpen: resolutionDropdown.popupOpen

  signal enabledToggled(bool enabled)
  signal scaleSelected(var scaleVal)
  signal transformSelected(int transformVal)
  signal modeSelected(string modeVal)
  signal dropdownClosed()

  visible: !!root.selectedMonitor
  implicitHeight: inspectorCol.implicitHeight + Style.spacing.md * 2
  height: implicitHeight
  radius: Style.cornerRadius
  color: Util.alpha(Commons.Color.menu.text, 0.03)
  border.width: 1
  border.color: Util.alpha(Commons.Color.menu.border, 0.5)

  Column {
    id: inspectorCol
    readonly property real labelWidth: Style.space(164)
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.spacing.md
    spacing: Style.spacing.sm

    RowLayout {
      width: parent.width
      spacing: Style.spacing.sm

      Rectangle {
        width: Style.space(24)
        height: Style.space(24)
        radius: width / 2
        color: Util.alpha(Commons.Color.accent, 0.2)
        border.width: 1
        border.color: Commons.Color.accent

        Text {
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: root.selectedMonitor ? Commons.I18n.formatNumber(root.selectedMonitor.number || 1) : ""
          color: Commons.Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }

      Column {
        Layout.fillWidth: true
        spacing: 1

        Text {
          width: parent.width
          textFormat: Text.PlainText
          elide: Text.ElideRight
          text: root.selectedMonitor
            ? TaskbarModel.sanitizePlainLabel(
                (root.selectedMonitor.name || "") + " · " + (root.selectedMonitor.model || ""),
                64
              )
            : ""
          color: Commons.Color.menu.text
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          elide: Text.ElideRight
          visible: text !== ""
          text: root.selectedMonitor && root.selectedMonitor.clamshellLocked
            ? root.strings.t("display.clamshellHint")
            : ((root.selectedMonitor && root.selectedMonitor.enabled && root.enabledCount <= 1)
                ? root.strings.t("display.lastDisplayHint")
                : TaskbarModel.sanitizePlainLabel(
                    root.selectedMonitor ? (root.selectedMonitor.description || "") : "",
                    72
                  ))
          color: Commons.Color.menu.text
          opacity: 0.65
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      Text {
        textFormat: Text.PlainText
        text: root.strings.t("display.enableDisplay")
        color: Commons.Color.menu.text
        opacity: root.selectedCanToggleEnabled ? 1.0 : 0.5
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }

      ToggleSwitch {
        checked: !!(root.selectedMonitor && root.selectedMonitor.enabled !== false)
        interactive: root.selectedCanToggleEnabled && root.interactive
        opacity: root.selectedCanToggleEnabled ? 1.0 : 0.45
        trackHeight: 18
        foreground: Commons.Color.menu.text
        accent: Commons.Color.accent
        onToggled: root.enabledToggled(!(root.selectedMonitor && root.selectedMonitor.enabled !== false))
      }
    }

    // Scale presets
    RowLayout {
      width: parent.width
      spacing: Style.spacing.md
      visible: !!(root.selectedMonitor && root.selectedMonitor.enabled !== false)

      Text {
        Layout.preferredWidth: inspectorCol.labelWidth
        Layout.alignment: Qt.AlignTop
        Layout.topMargin: Style.space(4)
        textFormat: Text.PlainText
        text: root.strings.t("display.scale")
        color: Commons.Color.menu.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Flow {
        Layout.fillWidth: true
        spacing: Style.spacing.xs

        Repeater {
          model: root.selectedScaleOptions

          delegate: Button {
            required property var modelData
            text: TaskbarModel.sanitizePlainLabel(modelData.label, 24)
            bordered: true
            focusable: false
            selected: String(modelData.value) === root.selectedCleanScale
            foreground: Commons.Color.menu.text
            background: Commons.Color.menu.background
            accent: Commons.Color.accent
            fontSize: Style.font.caption
            horizontalPadding: Style.spacing.sm
            verticalPadding: Style.space(4)
            onClicked: root.scaleSelected(modelData.value)
          }
        }
      }
    }

    // Orientation (0 / 90 / 180 / 270)
    RowLayout {
      width: parent.width
      spacing: Style.spacing.md
      visible: !!(root.selectedMonitor && root.selectedMonitor.enabled !== false)

      Text {
        Layout.preferredWidth: inspectorCol.labelWidth
        Layout.alignment: Qt.AlignTop
        Layout.topMargin: Style.space(4)
        textFormat: Text.PlainText
        text: root.strings.t("display.orientation")
        color: Commons.Color.menu.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Flow {
        Layout.fillWidth: true
        spacing: Style.spacing.xs

        Repeater {
          model: [
            { value: "0", label: root.strings.t("display.rot0") },
            { value: "1", label: root.strings.t("display.rot90") },
            { value: "2", label: root.strings.t("display.rot180") },
            { value: "3", label: root.strings.t("display.rot270") }
          ]

          delegate: Button {
            required property var modelData
            readonly property string curTr: root.selectedMonitor ? String(root.selectedMonitor.transform || 0) : "0"
            text: TaskbarModel.sanitizePlainLabel(modelData.label, 32)
            bordered: true
            focusable: false
            selected: modelData.value === curTr
            foreground: Commons.Color.menu.text
            background: Commons.Color.menu.background
            accent: Commons.Color.accent
            fontSize: Style.font.caption
            horizontalPadding: Style.spacing.sm
            verticalPadding: Style.space(4)
            onClicked: root.transformSelected(Number(modelData.value))
          }
        }
      }
    }

    // Resolution & Refresh Rate dropdown
    RowLayout {
      width: parent.width
      spacing: Style.spacing.md
      visible: !!(root.selectedMonitor && root.selectedMonitor.enabled !== false)

      Text {
        Layout.preferredWidth: inspectorCol.labelWidth
        Layout.alignment: Qt.AlignVCenter
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        textFormat: Text.PlainText
        text: root.strings.t("display.resolution")
        color: Commons.Color.menu.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Dropdown {
        id: resolutionDropdown
        Layout.fillWidth: true
        showLabel: false
        foreground: Commons.Color.menu.text
        background: Commons.Color.menu.background
        popupBorder: Commons.Color.menu.border
        accent: Commons.Color.accent
        options: root.selectedModeOptions
        value: root.selectedMonitor ? String(root.selectedMonitor.mode || "preferred") : "preferred"
        onPopupOpenChanged: {
          if (!popupOpen) root.dropdownClosed()
        }
        onChanged: function(val) { root.modeSelected(val) }
      }
    }
  }
}
