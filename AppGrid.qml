import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "TaskbarModel.js" as TaskbarModel

// Self-contained all-apps grid overlay for Omarchy-windåse.
// Type to filter, arrows to navigate, Enter to launch, right-click for actions.
Item {
  id: root

  property bool opened: false
  property var menuEntry: null
  property point menuPoint
  property var uninstallEntry: null
  property string filterText: ""
  property int selectedIndex: 0
  property var apps: []
  property bool appsStale: false

  readonly property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
  property var configuredHidden: ({})
  property var desktopHidden: ({})
  property var iconIndex: ({})
  property var pendingIconIndex: ({})

  property var defaultPinnedList: []
  property var userPinnedList: null
  readonly property var pinnedList: root.userPinnedList !== null ? root.userPinnedList : root.defaultPinnedList

  readonly property int iconSize: Math.round(56 * Style.fontScale)
  readonly property int labelHeight: Math.ceil(labelMetrics.height) * 2
  readonly property int cellGutter: Style.spacing.sm
  readonly property int cellPadding: Style.spacing.lg
  readonly property int cellWidth: Math.round(iconSize * 2.2)
  readonly property int cellHeight: cellPadding * 2 + iconSize + Style.spacing.md + labelHeight
  readonly property int maxColumns: 7
  readonly property int visibleRows: 4
  readonly property int borderWidth: Math.max(1, Style.space(2))
  readonly property int contentMargin: Style.spacing.panelPadding
  readonly property int inset: contentMargin + borderWidth
  readonly property int headerHeight: Math.max(Style.space(36), Style.font.heading + Style.spacing.controlPaddingY * 2)
  readonly property int headerSpacing: Style.spacing.xl
  readonly property int footerSpacing: Style.spacing.md
  readonly property int footerSeparatorHeight: Math.max(1, Style.spacing.hairline)
  readonly property int footerHeight: Math.max(Style.space(34), Style.font.body + Style.spacing.controlPaddingY * 2)
  readonly property int screenMargin: Style.space(40)

  readonly property int cardWidth: Math.min(panel.width - screenMargin * 2, maxColumns * cellWidth + inset * 2)
  readonly property int columns: Math.max(1, Math.floor((cardWidth - inset * 2) / cellWidth))
  readonly property int gridWidth: columns * cellWidth
  readonly property int cardHeight: Math.min(
    panel.height - screenMargin * 2,
    inset * 2 + headerHeight + headerSpacing + visibleRows * cellHeight + footerSpacing + footerSeparatorHeight + Style.spacing.sm + footerHeight
  )

  Commons.Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

  FontMetrics {
    id: labelMetrics
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.body
  }

  function isPinned(id) {
    var norm = TaskbarModel.normalizeId(id)
    if (!norm) return false
    var pins = root.pinnedList || []
    for (var i = 0; i < pins.length; i++) {
      if (TaskbarModel.normalizeId(pins[i]) === norm) return true
    }
    return false
  }

  function setPinned(id, pinned) {
    var norm = TaskbarModel.normalizeId(id)
    if (!norm) return
    Util.execArgv(["omarchy-dock", pinned ? "pin" : "unpin", norm])
  }

  function combinedHiddenMap() {
    var merged = {}
    var cfg = root.configuredHidden || {}
    var dsk = root.desktopHidden || {}
    for (var k in cfg) {
      if (cfg[k]) merged[k] = true
    }
    for (var j in dsk) {
      if (dsk[j]) merged[j] = true
    }
    return merged
  }

  function refreshIcons() {
    if (!iconIndexScan.running) iconIndexScan.running = true
  }

  function iconSource(icon) {
    var value = String(icon || "")
    if (value.length === 0) return Quickshell.iconPath("application-x-executable", true)
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    var found = root.iconIndex[value]
    if (found) return Util.fileUrl(found)
    var themed = Quickshell.iconPath(value, true)
    if (themed && themed.length > 0) return themed
    return Quickshell.iconPath("application-x-executable", true)
  }

  function hiddenEntryScanCommand() {
    var desktop = [
      Quickshell.env("XDG_CURRENT_DESKTOP"),
      Quickshell.env("XDG_SESSION_DESKTOP"),
      Quickshell.env("DESKTOP_SESSION")
    ].filter(function(v) { return String(v || "").length > 0 }).join(":")
    var script = root.omarchyPath + "/shell/services/hidden-entries.sh"
    return "[ -x " + Util.shellQuote(script) + " ] && " + Util.shellQuote(script) + " " + Util.shellQuote(desktop)
  }

  function iconIndexScanCommand() {
    return [
      'dirs="$HOME/.icons $HOME/.local/share/icons";',
      'IFS=":"; for d in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do dirs="$dirs $d/icons"; done; unset IFS;',
      '{',
      '  for base in $dirs; do',
      '    [[ -d $base ]] && find "$base" \\( -path "*/apps/*" -o -path "*/devices/*" \\) \\( -name "*.svg" -o -name "*.png" \\) 2>/dev/null;',
      '  done;',
      '  find /usr/share/pixmaps -maxdepth 1 \\( -name "*.svg" -o -name "*.png" \\) 2>/dev/null;',
      '} | awk \'/\\.svg$/ { print; next } { png[++n] = $0 } END { for (i = 1; i <= n; i++) print png[i] }\''
    ].join(' ')
  }

  function indexIconLine(line) {
    var value = String(line || "").trim()
    if (value.length === 0) return
    var slash = value.lastIndexOf("/")
    var file = slash >= 0 ? value.slice(slash + 1) : value
    var dot = file.lastIndexOf(".")
    var name = dot > 0 ? file.slice(0, dot) : file
    if (name.length > 0 && root.pendingIconIndex[name] === undefined) {
      root.pendingIconIndex[name] = value
    }
  }

  function open() {
    root.selectedIndex = 0
    root.refreshIcons()
    if (root.appsStale || root.filterText !== "" || root.apps.length === 0) {
      root.filterText = ""
      root.rebuild()
    } else {
      grid.positionViewAtBeginning()
    }
    root.opened = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
    root.uninstallEntry = null
    root.menuEntry = null
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function rebuild() {
    root.appsStale = false
    var values = DesktopEntries.applications.values || []
    root.apps = TaskbarModel.filterAndSortApps(values, root.filterText, root.combinedHiddenMap())
    root.selectedIndex = Math.max(0, Math.min(root.selectedIndex, root.apps.length - 1))
    grid.positionViewAtBeginning()
  }

  function setFilter(text) {
    root.filterText = text
    root.selectedIndex = 0
    root.rebuild()
  }

  function select(delta) {
    if (root.apps.length === 0) return
    root.selectedIndex = Math.max(0, Math.min(root.apps.length - 1, root.selectedIndex + delta))
    grid.positionViewAtIndex(root.selectedIndex, GridView.Contain)
  }

  function launchEntry(entry) {
    var argv = TaskbarModel.launchArgvForEntry(entry)
    if (argv.length > 0) Util.execArgv(argv)
  }

  function launch(index) {
    var entry = root.apps[index]
    if (!entry) return
    root.close()
    root.launchEntry(entry)
  }

  function openMenu(entry, point) {
    root.menuEntry = entry
    root.menuPoint = point
  }

  function requestUninstall(entry) {
    if (!entry) return
    root.menuEntry = null
    uninstallConfirm.selectedIndex = 1
    root.uninstallEntry = entry
  }

  function cancelUninstall() {
    root.uninstallEntry = null
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function confirmUninstall() {
    var entry = root.uninstallEntry
    root.uninstallEntry = null
    root.close()
    if (!entry) return
    var id = TaskbarModel.normalizeId(entry.id)
    if (!id) return
    var name = TaskbarModel.entryName(entry) || id
    Util.execArgv([root.omarchyPath + "/bin/omarchy-remove-launcher-entry", id, name])
  }

  FileView {
    id: defaultShellFile
    path: root.omarchyPath + "/config/omarchy/shell.json"
    watchChanges: false
    blockLoading: true
    printErrors: false
    onLoaded: root.defaultPinnedList = TaskbarModel.extractPinnedList(text()) || []
    onLoadFailed: root.defaultPinnedList = []
  }

  FileView {
    id: userShellFile
    path: Commons.Color.home + "/.config/omarchy/shell.json"
    watchChanges: true
    blockLoading: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.userPinnedList = TaskbarModel.extractPinnedList(text())
    onLoadFailed: root.userPinnedList = null
  }

  FileView {
    id: launcherHidesFile
    path: root.omarchyPath + "/default/omarchy/launcher.hides"
    watchChanges: true
    blockLoading: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      root.configuredHidden = TaskbarModel.parseHiddenEntryIds(text())
      if (root.opened) root.rebuild()
      else root.appsStale = true
    }
    onLoadFailed: root.configuredHidden = ({})
  }

  QtObject {
    id: hiddenEntryOutput
    property string text: ""
  }

  // Always use non-login bash (-c) so scanning does not re-touch ~/.local/share.
  Process {
    id: hiddenEntryScan
    command: ["bash", "-c", root.hiddenEntryScanCommand()]
    stdout: SplitParser {
      onRead: function(line) { hiddenEntryOutput.text += line + "\n" }
    }
    onStarted: hiddenEntryOutput.text = ""
    onExited: {
      root.desktopHidden = TaskbarModel.parseHiddenEntryIds(hiddenEntryOutput.text)
      if (root.opened) root.rebuild()
      else root.appsStale = true
    }
  }

  Process {
    id: iconIndexScan
    command: ["bash", "-c", root.iconIndexScanCommand()]
    stdout: SplitParser {
      onRead: function(line) { root.indexIconLine(line) }
    }
    onStarted: root.pendingIconIndex = ({})
    onExited: root.iconIndex = root.pendingIconIndex
  }

  Timer {
    id: iconIndexDebounce
    interval: 750
    onTriggered: if (!iconIndexScan.running) iconIndexScan.running = true
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() {
      hiddenEntryScan.running = true
      iconIndexDebounce.restart()
      if (root.opened) root.rebuild()
      else root.appsStale = true
    }
  }

  Component.onCompleted: {
    hiddenEntryScan.running = true
    iconIndexScan.running = true
  }

  OverlayWindow {
    id: panel
    shown: root.opened
    WlrLayershell.namespace: "omarchy-windaase-apps"

    onContentReadyChanged: {
      if (contentReady && root.opened) {
        Qt.callLater(function() { keyCatcher.forceActiveFocus() })
      }
    }

    Rectangle {
      anchors.fill: parent
      color: Commons.Color.menu.scrim
      opacity: root.opened ? 1 : 0

      Behavior on opacity {
        NumberAnimation { duration: Style.duration(150); easing.type: Easing.OutCubic }
      }
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: {
        if (root.menuEntry) root.menuEntry = null
        else root.close()
      }
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      anchors.centerIn: parent
      radius: Style.cornerRadius
      color: Commons.Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Commons.Color.menu.border, root.borderWidth)
      padding: root.contentMargin

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: root.menuEntry = null
      }

      ConfirmDialog {
        id: uninstallConfirm

        anchors.fill: parent
        opened: !!root.uninstallEntry
        z: 10
        message: TaskbarModel.formatTemplate(
          strings.t("appGrid.uninstallConfirm"),
          TaskbarModel.entryName(root.uninstallEntry)
        )
        confirmText: strings.t("appGrid.uninstall")
        background: Commons.Color.menu.background
        foreground: Commons.Color.menu.text
        scrim: Commons.Color.menu.scrim
        selectedBackground: Commons.Color.menu.selectedBackground
        selectedText: Commons.Color.menu.selectedText
        fontFamily: Style.font.menuFamily
        cornerRadius: Style.cornerRadius
        onCanceled: root.cancelUninstall()
        onConfirmed: root.confirmUninstall()
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (root.uninstallEntry) {
            if (uninstallConfirm.handleKey(event)) event.accepted = true
            return
          }
          if (event.key === Qt.Key_Delete) {
            root.requestUninstall(root.apps[root.selectedIndex])
          } else if (event.key === Qt.Key_Escape) {
            if (root.menuEntry) root.menuEntry = null
            else if (root.filterText) root.setFilter("")
            else root.close()
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
          } else if (Util.readingKey(event) === Qt.Key_Left) {
            root.select(-1)
          } else if (Util.readingKey(event) === Qt.Key_Right) {
            root.select(1)
          } else if (event.key === Qt.Key_Up) {
            root.select(-root.columns)
          } else if (event.key === Qt.Key_Down) {
            root.select(root.columns)
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.launch(root.selectedIndex)
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
          } else {
            return
          }
          event.accepted = true
        }
      }

      Column {
        width: root.gridWidth
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: card.contentTopInset
        anchors.bottomMargin: card.contentBottomInset
        spacing: 0

        Rectangle {
          x: root.cellGutter
          width: parent.width - root.cellGutter * 2
          height: root.headerHeight
          radius: Style.cornerRadius
          color: Util.alpha(Commons.Color.menu.text, 0.06)

          Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Style.spacing.controlPaddingX
            anchors.rightMargin: Style.spacing.controlPaddingX
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.filterText || strings.t("appGrid.searchApps")
            color: Commons.Color.menu.text
            opacity: root.filterText ? 1 : 0.58
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
          }
        }

        Item { width: 1; height: root.headerSpacing }

        Item {
          width: parent.width
          height: Math.max(0, parent.height - root.headerHeight - root.headerSpacing - root.footerSpacing - root.footerSeparatorHeight - Style.spacing.sm - root.footerHeight)

          GridView {
            id: grid
            anchors.fill: parent
            model: root.apps
            clip: true
            cellWidth: root.cellWidth
            cellHeight: root.cellHeight
            boundsBehavior: Flickable.StopAtBounds

            delegate: Item {
              id: cell

              required property int index
              required property var modelData
              readonly property bool selected: index === root.selectedIndex

              width: root.cellWidth
              height: root.cellHeight

              Image {
                id: icon
                anchors.horizontalCenter: parent.horizontalCenter
                y: root.cellPadding
                width: root.iconSize
                height: root.iconSize
                sourceSize: Qt.size(root.iconSize * 2, root.iconSize * 2)
                source: root.iconSource(cell.modelData.icon)
                fillMode: Image.PreserveAspectFit
                asynchronous: false
                smooth: true
                mipmap: true
              }

              Rectangle {
                anchors.centerIn: label
                width: Math.min(cell.width - root.cellGutter * 2, label.contentWidth + Style.spacing.md * 2)
                height: label.contentHeight + Style.spacing.xs * 2
                radius: Style.cornerRadius
                color: cell.selected ? Commons.Color.menu.selectedBackground : "transparent"
              }

              Text {
                id: label
                anchors.top: icon.bottom
                anchors.topMargin: Style.spacing.md
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - (root.cellGutter + Style.spacing.md) * 2
                textFormat: Text.PlainText
                text: TaskbarModel.entryName(cell.modelData)
                color: cell.selected ? Commons.Color.menu.selectedText : Commons.Color.menu.text
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.body
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignTop
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onContainsMouseChanged: if (containsMouse) root.selectedIndex = cell.index
                onClicked: function(event) {
                  if (event.button === Qt.RightButton) {
                    root.openMenu(cell.modelData, cell.mapToItem(panel.contentItem, event.x, event.y))
                    return
                  }
                  root.menuEntry = null
                  root.launch(cell.index)
                }
              }
            }
          }

          Text {
            anchors.centerIn: parent
            visible: root.apps.length === 0
            textFormat: Text.PlainText
            text: TaskbarModel.formatTemplate(strings.t("appGrid.noAppsMatch"), root.filterText)
            color: Commons.Color.menu.text
            opacity: 0.7
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.title
          }
        }

        Item { width: 1; height: root.footerSpacing }

        Rectangle {
          x: root.cellGutter
          width: parent.width - root.cellGutter * 2
          height: root.footerSeparatorHeight
          color: Commons.Color.menu.text
          opacity: 0.14
        }

        Item { width: 1; height: Style.spacing.sm }

        RowLayout {
          x: root.cellGutter
          width: parent.width - root.cellGutter * 2
          height: root.footerHeight
          spacing: Style.spacing.sm

          Button {
            text: strings.t("appGrid.files")
            focusable: false
            bordered: false
            fontFamily: Style.font.menuFamily
            fontSize: Style.font.caption
            foreground: Commons.Color.menu.text
            background: "transparent"
            accent: Commons.Color.accent
            horizontalPadding: Style.spacing.sm
            verticalPadding: Style.space(4)
            onClicked: {
              root.close()
              Util.execArgv(["omarchy-launch-nautilus"])
            }
          }

          Button {
            text: strings.t("appGrid.settings")
            focusable: false
            bordered: false
            fontFamily: Style.font.menuFamily
            fontSize: Style.font.caption
            foreground: Commons.Color.menu.text
            background: "transparent"
            accent: Commons.Color.accent
            horizontalPadding: Style.spacing.sm
            verticalPadding: Style.space(4)
            onClicked: {
              root.close()
              Commons.IpcRegistry.call("riisager.windaase.bar", "toggleSettings", [])
            }
          }

          Item { Layout.fillWidth: true }

          Button {
            text: strings.t("appGrid.lock")
            focusable: false
            bordered: false
            fontFamily: Style.font.menuFamily
            fontSize: Style.font.caption
            foreground: Commons.Color.menu.text
            background: "transparent"
            accent: Commons.Color.accent
            horizontalPadding: Style.spacing.sm
            verticalPadding: Style.space(4)
            onClicked: {
              root.close()
              Util.execArgv(["omarchy-system-lock"])
            }
          }

          Button {
            text: strings.t("appGrid.power")
            focusable: false
            bordered: false
            fontFamily: Style.font.menuFamily
            fontSize: Style.font.caption
            foreground: Commons.Color.menu.text
            background: "transparent"
            accent: Commons.Color.accent
            horizontalPadding: Style.spacing.sm
            verticalPadding: Style.space(4)
            onClicked: {
              root.close()
              Util.execArgv(["omarchy-shell", "shell", "toggle", "omarchy.menu", "{\"menu\":\"system\"}"])
            }
          }
        }
      }
    }

    BorderSurface {
      id: menu

      readonly property var entry: root.menuEntry
      readonly property bool pinned: !!entry && root.isPinned(entry.id)

      visible: !!entry
      width: Math.max(Style.space(160), menuColumn.implicitWidth) + padding * 2
      height: menuColumn.implicitHeight + padding * 2
      x: LayoutMirroring.enabled
        ? Math.max(Style.gapsOut, root.menuPoint.x - width)
        : Math.min(root.menuPoint.x, panel.width - width - Style.gapsOut)
      y: Math.min(root.menuPoint.y, panel.height - height - Style.gapsOut)
      radius: Style.cornerRadius
      color: Commons.Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Style.normalBorderWidth)
      padding: Style.spacing.sm

      Column {
        id: menuColumn
        x: menu.contentLeftInset
        y: menu.contentTopInset
        width: menu.width - menu.contentLeftInset - menu.contentRightInset

        GridMenuRow {
          text: strings.t("appGrid.open")
          onTriggered: {
            var entry = menu.entry
            root.close()
            if (entry) root.launchEntry(entry)
          }
        }

        GridMenuRow {
          text: menu.pinned ? strings.t("taskbar.unpin") : strings.t("taskbar.pin")
          onTriggered: {
            if (menu.entry) root.setPinned(menu.entry.id, !menu.pinned)
            root.menuEntry = null
          }
        }

        GridMenuRow {
          text: strings.t("appGrid.uninstall")
          onTriggered: root.requestUninstall(menu.entry)
        }
      }
    }
  }

  component GridMenuRow: Rectangle {
    id: row

    property string text: ""
    signal triggered()

    width: parent ? parent.width : 0
    height: visible ? Style.spacing.popupRowHeight : 0
    radius: Style.cornerRadius
    color: rowMouse.containsMouse ? Style.hoverFill : "transparent"

    Text {
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.controlPaddingX
      textFormat: Text.PlainText
      text: row.text
      color: Commons.Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: row.triggered()
    }
  }
}
