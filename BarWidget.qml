import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "TaskbarModel.js" as TaskbarModel

BarWidget {
  id: root
  moduleName: "riisager.windaase"

  readonly property int slotSize: Math.max(Style.space(22), root.barSize)
  readonly property int iconSize: Math.max(Style.space(14), root.slotSize - Style.space(10))
  readonly property real idleOpacity: 0.85
  readonly property var uncombinedApps: root.setting("uncombine", [])

  property var defaultPinnedList: []
  property var userPinnedList: null
  readonly property var pinnedList: root.userPinnedList !== null ? root.userPinnedList : root.defaultPinnedList

  property string activeBrowserDir: ""
  property var browserProfiles: []
  property var windowOrderState: ({ seq: 0, byAddr: {} })

  property string pickerKey: ""
  property Item pickerAnchor: null
  property string menuKey: ""
  property Item menuAnchor: null

  implicitWidth: root.vertical ? root.barSize : layoutGrid.implicitWidth
  implicitHeight: root.vertical ? layoutGrid.implicitHeight : root.barSize

  Commons.Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

  function extractPinned(raw) {
    try {
      var parsed = JSON.parse(String(raw || ""))
      if (parsed && parsed.dock && Array.isArray(parsed.dock.pinned)) {
        return parsed.dock.pinned
      }
    } catch (e) {}
    return null
  }

  FileView {
    id: defaultShellFile
    path: (Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy") + "/config/omarchy/shell.json"
    watchChanges: false
    blockLoading: true
    printErrors: false
    onLoaded: root.defaultPinnedList = root.extractPinned(text()) || []
    onLoadFailed: root.defaultPinnedList = []
  }

  FileView {
    id: userShellFile
    path: Commons.Color.home + "/.config/omarchy/shell.json"
    watchChanges: true
    blockLoading: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.userPinnedList = root.extractPinned(text())
    onLoadFailed: root.userPinnedList = null
  }

  FileView {
    id: browserStateFile
    path: root.activeBrowserDir ? (root.activeBrowserDir + "/Local State") : ""
    watchChanges: false
    blockLoading: true
    printErrors: false
    onLoaded: {
      if (root.activeBrowserDir) {
        root.browserProfiles = TaskbarModel.parseChromeProfiles(text(), root.activeBrowserDir)
      }
    }
    onLoadFailed: root.browserProfiles = []
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event ? String(event.name) : ""
      if (name === "fullscreen" || name === "configreloaded") {
        Hyprland.refreshToplevels()
      }
    }
  }

  readonly property var terminalEntries: {
    var values = DesktopEntries.applications.values
    var out = []
    for (var i = 0; i < values.length; i++) {
      var entry = values[i]
      if (entry.runInTerminal || String(entry.execString || "").indexOf("--app-id=") >= 0) {
        out.push({
          id: entry.id,
          execString: entry.execString,
          command: entry.command,
          runInTerminal: entry.runInTerminal
        })
      }
    }
    return out
  }

  function entryForAppId(appId) {
    var entry = DesktopEntries.heuristicLookup(appId)
    if (entry) return entry
    var id = TaskbarModel.claimingEntryId(appId, root.terminalEntries)
    return id ? DesktopEntries.byId(id) : null
  }

  readonly property var items: {
    var appsRevision = DesktopEntries.applications.values.length
    var pinned = (root.pinnedList || []).map(function(id) {
      return TaskbarModel.normalizeId(id)
    }).filter(function(id) {
      return !!DesktopEntries.byId(id)
    })

    var windows = []
    var toplevels = Hyprland.toplevels.values
    for (var i = 0; i < toplevels.length; i++) {
      var toplevel = toplevels[i].wayland
      if (!toplevel || !toplevel.appId || toplevel.parent) continue
      var entry = root.entryForAppId(toplevel.appId)
      var workspace = toplevels[i].workspace
      var rawTags = toplevels[i].lastIpcObject && toplevels[i].lastIpcObject.tags ? toplevels[i].lastIpcObject.tags : []
      var cleanTags = []
      for (var ti = 0; ti < rawTags.length; ti++) {
        cleanTags.push(String(rawTags[ti]))
      }
      windows.push({
        key: entry ? entry.id : toplevel.appId,
        hasEntry: !!entry && !entry.noDisplay,
        title: toplevel.title || (entry ? entry.name : toplevel.appId),
        activated: !!toplevel.activated,
        workspaceId: workspace ? workspace.id : -1,
        minimized: !!workspace && TaskbarModel.isMinimizedWorkspace(workspace.name),
        address: toplevels[i].address,
        tags: cleanTags,
        toplevel: toplevel
      })
    }

    var orderedWindows = TaskbarModel.stabilizeWindows(windows, root.windowOrderState)
    var uncombined = Array.isArray(root.uncombinedApps) ? root.uncombinedApps : []
    return TaskbarModel.buildItems(pinned, orderedWindows, uncombined)
  }

  readonly property var itemsByKey: {
    var byKey = {}
    for (var i = 0; i < root.items.length; i++) byKey[root.items[i].key] = root.items[i]
    return byKey
  }

  function itemFor(key) {
    return root.itemsByKey[key] || null
  }

  ListModel { id: itemModel }

  onItemsChanged: syncItemModel()
  Component.onCompleted: {
    root.defaultPinnedList = root.extractPinned(defaultShellFile.text()) || []
    root.userPinnedList = root.extractPinned(userShellFile.text())
    syncItemModel()
  }

  function syncItemModel() {
    var keys = root.items.map(function(item) { return item.key })
    for (var i = 0; i < keys.length; i++) {
      if (i < itemModel.count && itemModel.get(i).key === keys[i]) continue
      var found = -1
      for (var j = i + 1; j < itemModel.count; j++) {
        if (itemModel.get(j).key === keys[i]) { found = j; break }
      }
      if (found >= 0) itemModel.move(found, i, 1)
      else itemModel.insert(i, { key: keys[i] })
    }
    if (itemModel.count > keys.length) itemModel.remove(keys.length, itemModel.count - keys.length)
  }

  function entryFor(item) {
    return item ? DesktopEntries.byId(item.appKey || item.key) : null
  }

  function iconFor(item) {
    var entry = entryFor(item)
    var icon = entry && entry.icon ? entry.icon : (item ? (item.appKey || item.key) : "")
    var value = String(icon || "")
    if (value.length === 0) return Quickshell.iconPath("application-x-executable", true)
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    var themed = Quickshell.iconPath(value, true)
    if (themed && themed.length > 0) return themed
    return Quickshell.iconPath("application-x-executable", true)
  }

  function labelFor(item) {
    var entry = entryFor(item)
    return entry && entry.name ? entry.name : (item ? (item.appKey || item.key) : "")
  }

  function isItemFocused(item) {
    if (!item || !item.windows) return false
    for (var i = 0; i < item.windows.length; i++) {
      var w = item.windows[i]
      if (!w.minimized && w.toplevel && w.toplevel.activated) return true
    }
    return false
  }

  function isItemAllMinimized(item) {
    if (!item || !item.windows || item.windows.length === 0) return false
    for (var i = 0; i < item.windows.length; i++) {
      if (!item.windows[i].minimized) return false
    }
    return true
  }

  function launch(item) {
    var entry = entryFor(item)
    if (!entry) return
    if (entry.runInTerminal) {
      var cmd = (entry.command || []).filter(function(word) {
        return !/^%[a-zA-Z]$/.test(String(word))
      })
      if (cmd.length > 0) {
        Util.execDetached("omarchy-launch-tui " + cmd.map(function(w) { return Util.shellQuote(w) }).join(" "))
        return
      }
    }
    Util.execDetached("uwsm-app -- gtk-launch " + Util.shellQuote(entry.id + ".desktop"))
  }

  function browserBinaryForItem(item) {
    var appKey = item ? TaskbarModel.normalizeId(item.appKey || item.key).toLowerCase() : ""
    var entry = entryFor(item)
    if (entry && entry.command && entry.command.length > 0) {
      var bin = String(entry.command[0] || "").trim()
      if (bin) return bin
    }
    if (appKey === "google-chrome") return "/usr/bin/google-chrome-stable"
    if (appKey === "chromium") return "chromium"
    if (appKey === "brave-browser" || appKey === "brave") return "brave"
    return ""
  }

  function launchBrowserProfile(item, profileDir) {
    var dir = String(profileDir || "").trim()
    if (!TaskbarModel.isValidProfileDir(dir)) return
    var bin = browserBinaryForItem(item)
    if (!bin) return
    Util.execDetached("uwsm-app -- " + Util.shellQuote(bin) + " --profile-directory=" + Util.shellQuote(dir))
  }

  function bringForward(window) {
    if (!window) return
    var address = TaskbarModel.normalizeAddress(window.address)
    if (!address) {
      if (window.toplevel) window.toplevel.activate()
      return
    }
    var target = "window = \"address:" + address + "\""
    var steps = []
    var after = []
    if (window.minimized) {
      var monitor = Hyprland.focusedMonitor
      var workspace = monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1
      if (!(workspace >= 1)) return
      var tags = window.tags || []
      for (var i = 0; i < tags.length; i++) {
        var tag = String(tags[i] || "")
        if (/^omarchy-(minimized-from|showdesktop)-[0-9]+$/.test(tag)) {
          steps.push("hl.dsp.window.tag({ tag = \"-" + tag + "\", " + target + " })")
        }
      }
      steps.push("hl.dsp.window.set_prop({ prop = \"no_anim\", value = \"1\", " + target + " })")
      steps.push("hl.dsp.window.move({ workspace = \"" + workspace + "\", " + target + " })")
      after.push("hl.dsp.window.set_prop({ prop = \"no_anim\", value = \"unset\", " + target + " })")
    }
    steps.push("hl.dsp.focus({ " + target + " })")
    steps.push("hl.dsp.window.alter_zorder({ mode = \"top\", " + target + " })")
    var dispatch = function(step) { return "hyprctl dispatch " + Util.shellQuote(step) }
    var command = steps.map(dispatch).join(" && ")
    if (after.length > 0) command += "; sleep 0.4; " + after.map(dispatch).join("; ")
    Util.execDetached(command)
  }

  function minimizeWindows(windows) {
    if (!windows || windows.length === 0) return
    var steps = []
    var focusWs = -1
    var monitor = Hyprland.focusedMonitor
    var activeWs = monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1
    for (var i = 0; i < windows.length; i++) {
      var win = windows[i]
      if (!win || win.minimized) continue
      var address = TaskbarModel.normalizeAddress(win.address)
      if (!address) continue
      var ws = (win.workspaceId >= 1) ? win.workspaceId : activeWs
      if (!(ws >= 1)) continue
      focusWs = ws
      var target = "window = \"address:" + address + "\""
      var tags = win.tags || []
      for (var t = 0; t < tags.length; t++) {
        var tag = String(tags[t] || "")
        if (/^omarchy-minimized-from-[0-9]+$/.test(tag) && tag !== ("omarchy-minimized-from-" + ws)) {
          steps.push("hl.dsp.window.tag({ tag = \"-" + tag + "\", " + target + " })")
        }
      }
      steps.push("hl.dsp.window.tag({ tag = \"+omarchy-minimized-from-" + ws + "\", " + target + " })")
      steps.push("hl.dsp.window.move({ workspace = \"special:minimized\", follow = false, " + target + " })")
    }
    if (steps.length === 0) return
    if (focusWs >= 1) steps.push("hl.dsp.focus({ workspace = \"" + focusWs + "\" })")
    var command = steps.map(function(step) { return "hyprctl dispatch " + Util.shellQuote(step) }).join(" && ")
    Util.execDetached(command)
  }

  function minimizeWindow(window) {
    minimizeWindows(window ? [window] : [])
  }

  function minimizeAll(item) {
    minimizeWindows(item && item.windows ? item.windows : [])
  }

  function restoreAll(item) {
    if (!item || !item.windows) return
    for (var i = 0; i < item.windows.length; i++) {
      if (item.windows[i].minimized) root.bringForward(item.windows[i])
    }
  }

  function activateWindow(window) {
    if (!window) return
    var monitor = Hyprland.focusedMonitor
    var wsId = monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1
    if (window.toplevel && window.toplevel.activated && !window.minimized && window.workspaceId === wsId) {
      root.minimizeWindow(window)
    } else {
      root.bringForward(window)
    }
  }

  function closeWindow(window) {
    if (window && window.toplevel) window.toplevel.close()
  }

  function quitItem(item) {
    if (!item || !item.windows) return
    var wins = item.windows.slice()
    for (var i = 0; i < wins.length; i++) {
      if (wins[i].toplevel) wins[i].toplevel.close()
    }
  }

  function setPinned(key, pinned) {
    if (!key) return
    Util.execDetached("omarchy-dock " + (pinned ? "pin " : "unpin ") + Util.shellQuote(key))
  }

  function closePopouts() {
    root.pickerKey = ""
    root.menuKey = ""
  }

  function openPicker(key, slot) {
    root.menuKey = ""
    root.pickerKey = key
    root.pickerAnchor = slot
    if (root.bar) root.bar.hideTooltip(slot)
  }

  function openMenu(key, slot) {
    var targetItem = root.itemFor(key)
    var appKey = targetItem ? (targetItem.appKey || targetItem.key) : ""
    var dir = TaskbarModel.browserProfileConfigDir(appKey, Commons.Color.home)
    if (dir) {
      root.activeBrowserDir = dir
      browserStateFile.reload()
      root.browserProfiles = TaskbarModel.parseChromeProfiles(browserStateFile.text(), dir)
    } else {
      root.activeBrowserDir = ""
      root.browserProfiles = []
    }
    root.pickerKey = ""
    root.menuKey = key
    root.menuAnchor = slot
    if (root.bar) root.bar.hideTooltip(slot)
  }

  GridLayout {
    id: layoutGrid
    columns: root.vertical ? 1 : itemRepeater.count + 1
    rows: root.vertical ? itemRepeater.count + 1 : 1
    columnSpacing: root.vertical ? 0 : Style.space(2)
    rowSpacing: root.vertical ? Style.space(2) : 0

    // Subtle 1px divider separating omarchy.workspaces from the taskbar apps
    Item {
      Layout.preferredWidth: root.vertical ? root.slotSize : Style.space(8)
      Layout.preferredHeight: root.vertical ? Style.space(8) : root.slotSize

      Rectangle {
        anchors.centerIn: parent
        width: root.vertical ? Math.round(root.slotSize * 0.6) : Math.max(1, Style.spacing.hairline)
        height: root.vertical ? Math.max(1, Style.spacing.hairline) : Math.round(root.slotSize * 0.55)
        color: root.bar ? root.bar.barForeground : Commons.Color.bar.text
        opacity: 0.22
      }
    }

    Repeater {
      id: itemRepeater
      model: itemModel

      delegate: Item {
        id: taskSlot

        required property int index
        required property string key

        readonly property var modelData: root.itemFor(key)
        readonly property int windowCount: modelData ? modelData.windows.length : 0
        readonly property bool focused: root.isItemFocused(modelData)
        readonly property bool allMinimized: root.isItemAllMinimized(modelData)
        readonly property string appLabel: modelData ? root.labelFor(modelData) : key
        readonly property bool hovered: slotMouse.containsMouse

        property var registeredBar: null

        function syncClickRegistration() {
          if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(taskSlot)
          registeredBar = root.bar
          if (registeredBar && registeredBar.registerClickTarget) registeredBar.registerClickTarget(taskSlot)
        }

        Layout.preferredWidth: root.slotSize
        Layout.preferredHeight: root.slotSize

        Connections {
          target: root
          function onBarChanged() { taskSlot.syncClickRegistration() }
        }
        Component.onCompleted: syncClickRegistration()
        Component.onDestruction: {
          if (root.bar) root.bar.hideTooltip(taskSlot)
          if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(taskSlot)
        }

        Rectangle {
          anchors.centerIn: parent
          width: root.slotSize - Style.space(2)
          height: root.slotSize - Style.space(2)
          radius: Math.max(Style.space(4), Style.cornerRadius)
          color: taskSlot.focused ? Style.selectedFill : (taskSlot.hovered ? Style.hoverFill : "transparent")
          border.width: taskSlot.focused ? 1 : 0
          border.color: taskSlot.focused ? Style.normalBorderColor : "transparent"

          Behavior on color { ColorAnimation { duration: Style.duration(120) } }
        }

        Image {
          anchors.centerIn: parent
          width: root.iconSize
          height: root.iconSize
          sourceSize: Qt.size(root.iconSize * 2, root.iconSize * 2)
          source: taskSlot.modelData ? root.iconFor(taskSlot.modelData) : ""
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          smooth: true
          mipmap: true
          opacity: taskSlot.windowCount > 0 ? (taskSlot.allMinimized ? 0.65 : 1.0) : root.idleOpacity
          scale: taskSlot.hovered ? 1.1 : 1.0

          Behavior on scale { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }
        }

        // Windows 11-style active/open indicator bar
        Rectangle {
          visible: taskSlot.windowCount > 0
          width: root.vertical ? Style.space(2) : (taskSlot.focused ? Style.space(12) : (taskSlot.windowCount > 1 ? Style.space(8) : Style.space(5)))
          height: root.vertical ? (taskSlot.focused ? Style.space(12) : (taskSlot.windowCount > 1 ? Style.space(8) : Style.space(5))) : Style.space(2)
          radius: Style.space(1)
          color: taskSlot.focused ? Commons.Color.accent : (root.bar ? root.bar.barForeground : Commons.Color.bar.text)
          opacity: taskSlot.focused ? 1.0 : (taskSlot.allMinimized ? 0.45 : 0.8)
          anchors.horizontalCenter: root.vertical ? undefined : parent.horizontalCenter
          anchors.bottom: root.vertical ? undefined : parent.bottom
          anchors.bottomMargin: root.vertical ? 0 : Style.space(1)
          anchors.verticalCenter: root.vertical ? parent.verticalCenter : undefined
          anchors.left: (root.bar && root.bar.position === "left") ? parent.left : undefined
          anchors.leftMargin: (root.bar && root.bar.position === "left") ? Style.space(1) : 0
          anchors.right: (root.bar && root.bar.position === "right") ? parent.right : undefined
          anchors.rightMargin: (root.bar && root.bar.position === "right") ? Style.space(1) : 0

          Behavior on width { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }
        }

        // Window count badge when 2+ windows are open
        Rectangle {
          visible: taskSlot.windowCount > 1
          anchors.top: parent.top
          anchors.right: parent.right
          anchors.topMargin: Style.space(1)
          anchors.rightMargin: Style.space(1)
          width: Math.max(Style.space(10), countTxt.implicitWidth + Style.space(3))
          height: Style.space(10)
          radius: height / 2
          color: taskSlot.focused ? Commons.Color.accent : Commons.Color.popups.background
          border.width: 1
          border.color: Commons.Color.popups.border

          Text {
            id: countTxt
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: Commons.I18n.formatNumber(taskSlot.windowCount)
            color: taskSlot.focused ? Commons.Color.background : Commons.Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Math.max(7, Style.font.caption - 2)
            font.bold: true
          }
        }

        MouseArea {
          id: slotMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

          onEntered: {
            if (root.bar && root.pickerKey.length === 0 && root.menuKey.length === 0) {
              var rawLabel = ""
              if (taskSlot.modelData && taskSlot.modelData.split && taskSlot.windowCount === 1) {
                var w = taskSlot.modelData.windows[0]
                var rawTitle = (w.toplevel && w.toplevel.title) ? w.toplevel.title : (w.title || taskSlot.appLabel)
                rawLabel = w.minimized ? strings.t("taskbar.minimizedPrefix").arg(rawTitle) : rawTitle
              } else {
                rawLabel = taskSlot.windowCount > 1
                  ? strings.t("taskbar.windowCount").arg(taskSlot.appLabel).arg(Commons.I18n.formatNumber(taskSlot.windowCount))
                  : taskSlot.appLabel
              }
              root.bar.showTooltip(taskSlot, TaskbarModel.sanitizeTooltipText(rawLabel, 96))
            }
          }
          onExited: if (root.bar) root.bar.hideTooltip(taskSlot)

          onClicked: function(event) {
            if (!taskSlot.modelData) return
            if (event.button === Qt.RightButton) {
              if (root.menuKey === taskSlot.key) root.closePopouts()
              else root.openMenu(taskSlot.key, taskSlot)
              return
            }
            if (event.button === Qt.MiddleButton) {
              root.closePopouts()
              root.launch(taskSlot.modelData)
              return
            }
            if (taskSlot.windowCount === 0) {
              root.closePopouts()
              root.launch(taskSlot.modelData)
              return
            }
            if (taskSlot.windowCount === 1) {
              root.closePopouts()
              root.activateWindow(taskSlot.modelData.windows[0])
              return
            }
            if (root.pickerKey === taskSlot.key) root.closePopouts()
            else root.openPicker(taskSlot.key, taskSlot)
          }
        }
      }
    }
  }

  QtObject {
    id: pickerOwner
    function close() { root.pickerKey = "" }
  }

  QtObject {
    id: menuOwner
    function close() { root.menuKey = "" }
  }

  PopupCard {
    id: pickerCard

    readonly property var item: root.pickerKey.length > 0 ? root.itemFor(root.pickerKey) : null
    readonly property var windows: item && item.windows ? item.windows : []
    onWindowsChanged: if (root.pickerKey.length > 0 && windows.length === 0) Qt.callLater(pickerOwner.close)

    anchorItem: root.pickerAnchor || root
    owner: pickerOwner
    bar: root.bar
    open: root.pickerKey.length > 0 && windows.length > 0
    padding: Style.spacing.sm
    contentWidth: pickerCard.fittedContentWidth(Style.space(290))
    contentHeight: pickerCard.fittedContentHeight(Math.min(Style.space(220), pickerColumn.implicitHeight))

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
          model: pickerCard.windows

          delegate: Rectangle {
            id: pickerRow
            required property var modelData
            readonly property bool isActive: !modelData.minimized && !!modelData.toplevel && !!modelData.toplevel.activated
            readonly property string baseTitle: modelData.title || (pickerCard.item ? root.labelFor(pickerCard.item) : "")
            readonly property string winTitle: modelData.minimized
              ? strings.t("taskbar.minimizedPrefix").arg(baseTitle)
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
              text: strings.t("taskbar.workspaceBadge").arg(Commons.I18n.formatNumber(pickerRow.modelData.workspaceId))
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
                root.activateWindow(pickerRow.modelData)
                pickerOwner.close()
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
                onClicked: root.closeWindow(pickerRow.modelData)
              }
            }
          }
        }
      }
    }
  }

  PopupCard {
    id: menuCard

    readonly property var item: root.menuKey.length > 0 ? root.itemFor(root.menuKey) : null
    readonly property string appKey: item ? (item.appKey || item.key) : ""
    readonly property bool hasEntry: !!item && !!root.entryFor(item)
    readonly property bool running: !!item && item.windows.length > 0
    readonly property bool isBrowser: TaskbarModel.browserProfileConfigDir(appKey, Commons.Color.home).length > 0
    readonly property bool showProfiles: isBrowser && root.browserProfiles.length > 0

    anchorItem: root.menuAnchor || root
    owner: menuOwner
    bar: root.bar
    open: root.menuKey.length > 0 && !!item
    onOpenChanged: if (open) menuFlickable.contentY = 0
    padding: Style.spacing.sm
    contentWidth: menuCard.fittedContentWidth(menuCard.showProfiles ? Style.space(260) : Style.space(180))
    contentHeight: menuCard.fittedContentHeight(Math.min(Style.space(420), menuColumn.implicitHeight))

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
          visible: menuCard.showProfiles
          width: menuColumn.width
          height: visible ? Style.space(22) : 0

          Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.controlPaddingX
            textFormat: Text.PlainText
            text: strings.t("taskbar.openProfile")
            color: Commons.Color.popups.text
            opacity: 0.6
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }

        Repeater {
          model: menuCard.showProfiles ? root.browserProfiles : []

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
                root.launchBrowserProfile(menuCard.item, profileRow.modelData.dir)
                menuOwner.close()
              }
            }
          }
        }

        Item {
          visible: menuCard.showProfiles
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
          visible: menuCard.hasEntry && menuCard.running
          text: strings.t("taskbar.newWindow")
          onTriggered: root.launch(menuCard.item)
        }

        TaskMenuRow {
          visible: menuCard.running && !root.isItemAllMinimized(menuCard.item)
          text: strings.t("taskbar.minimize")
          onTriggered: root.minimizeAll(menuCard.item)
        }

        TaskMenuRow {
          visible: menuCard.running && root.isItemAllMinimized(menuCard.item)
          text: strings.t("taskbar.restore")
          onTriggered: root.restoreAll(menuCard.item)
        }

        TaskMenuRow {
          visible: menuCard.hasEntry
          text: menuCard.item && menuCard.item.pinned ? strings.t("taskbar.unpin") : strings.t("taskbar.pin")
          onTriggered: root.setPinned(menuCard.appKey, !menuCard.item.pinned)
        }

        TaskMenuRow {
          visible: menuCard.running
          text: (menuCard.item && menuCard.item.windows.length === 1) ? strings.t("taskbar.closeWindow") : strings.t("taskbar.closeAll")
          onTriggered: root.quitItem(menuCard.item)
        }
      }
    }
  }

  component TaskMenuRow: Rectangle {
    id: menuRow

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
      text: menuRow.text
      color: Commons.Color.popups.text
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
        menuOwner.close()
      }
    }
  }
}
