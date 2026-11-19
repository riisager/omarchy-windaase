import QtQuick
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
  readonly property bool tallBar: root.slotSize >= Style.space(34)
  readonly property var configuredIconSize: root.setting("iconSize", 0)
  readonly property int iconSize: TaskbarModel.resolveIconSize(root.slotSize, root.configuredIconSize, Style.space(14))
  readonly property int appsIconSize: Math.min(root.iconSize, Style.space(22))
  readonly property int pillInset: root.tallBar ? Style.space(4) : Style.space(2)
  readonly property int indicatorThickness: root.tallBar ? Style.space(3) : Style.space(2)
  readonly property int indicatorMargin: root.tallBar ? Style.space(2) : Style.space(1)
  readonly property int badgeSize: root.tallBar ? Style.space(13) : Style.space(10)
  readonly property real idleOpacity: 0.85
  readonly property var uncombinedApps: root.setting("uncombine", [])
  readonly property bool showAppsButton: root.setting("showAppsButton", true)

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
  property bool settingsOpen: false
  property Item settingsAnchor: null
  property bool twoLineClock: false
  property var hyprSettings: TaskbarModel.defaultHyprSettings()
  readonly property string configScriptPath: String(Qt.resolvedUrl("windaase-config.py")).replace(/^file:\/\//, "")

  implicitWidth: root.vertical ? root.barSize : layoutGrid.implicitWidth
  implicitHeight: root.vertical ? layoutGrid.implicitHeight : root.barSize

  Commons.Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

  FileView {
    id: defaultShellFile
    path: (Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy") + "/config/omarchy/shell.json"
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
    onLoaded: {
      var raw = text()
      root.userPinnedList = TaskbarModel.extractPinnedList(raw)
      root.twoLineClock = TaskbarModel.isTwoLineClockFormat(raw)
    }
    onLoadFailed: {
      root.userPinnedList = null
      root.twoLineClock = false
    }
  }

  FileView {
    id: hyprSettingsFile
    path: Commons.Color.home + "/.config/omarchy/windaase.json"
    watchChanges: true
    blockLoading: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.hyprSettings = TaskbarModel.parseHyprSettings(text())
    onLoadFailed: root.hyprSettings = TaskbarModel.defaultHyprSettings()
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
    var userRaw = userShellFile.text()
    root.defaultPinnedList = TaskbarModel.extractPinnedList(defaultShellFile.text()) || []
    root.userPinnedList = TaskbarModel.extractPinnedList(userRaw)
    root.twoLineClock = TaskbarModel.isTwoLineClockFormat(userRaw)
    root.hyprSettings = TaskbarModel.parseHyprSettings(hyprSettingsFile.text())
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
    var argv = TaskbarModel.launchArgvForEntry(entryFor(item))
    if (argv.length > 0) Util.execArgv(argv)
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
    Util.execArgv(["uwsm-app", "--", bin, "--profile-directory=" + dir])
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
    Util.execArgv(["omarchy-dock", pinned ? "pin" : "unpin", String(key)])
  }

  function closePopouts() {
    root.pickerKey = ""
    root.menuKey = ""
    root.settingsOpen = false
  }

  function updateWidgetSettings(patch) {
    var entry = TaskbarModel.buildUpdatedWidgetEntry(root.settings, root.moduleName, patch)
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function") {
      root.bar.shell.updateEntryInline(root.moduleName, entry)
    }
  }

  function runConfigHelper(args) {
    if (!root.configScriptPath) return
    Util.execArgv(["python3", root.configScriptPath].concat(args))
  }

  function openSettings(slot) {
    root.pickerKey = ""
    root.menuKey = ""
    root.settingsAnchor = slot || (root.showAppsButton ? appsSlot : root)
    root.settingsOpen = true
    if (root.bar && root.settingsAnchor) root.bar.hideTooltip(root.settingsAnchor)
  }

  function toggleSettingsOnFocusedMonitor() {
    var monitor = Hyprland.focusedMonitor
    var win = root.QsWindow ? root.QsWindow.window : null
    var screenName = win && win.screen ? String(win.screen.name || "") : ""
    var focusedName = monitor ? String(monitor.name || "") : ""
    if (focusedName && screenName && focusedName !== screenName) return
    if (root.settingsOpen) {
      root.closePopouts()
    } else {
      root.openSettings(root.showAppsButton ? appsSlot : root)
    }
  }

  function toggleAppGrid() {
    var res = Commons.IpcRegistry.call("riisager.windaase", "apps", [])
    if (!res || !res.ran) {
      Util.execArgv(["omarchy-shell", "shell", "toggle", "omarchy.menu", "{\"menu\":\"apps\"}"])
    }
  }

  function openPicker(key, slot) {
    root.settingsOpen = false
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
    root.settingsOpen = false
    root.pickerKey = ""
    root.menuKey = key
    root.menuAnchor = slot
    if (root.bar) root.bar.hideTooltip(slot)
  }

  ShellIpc {
    target: "riisager.windaase.bar"

    function toggleSettings(): void {
      root.broadcast("toggleSettingsOnFocusedMonitor")
    }
  }

  GridLayout {
    id: layoutGrid
    columns: root.vertical ? 1 : itemRepeater.count + 1 + (root.showAppsButton ? 1 : 0)
    rows: root.vertical ? itemRepeater.count + 1 + (root.showAppsButton ? 1 : 0) : 1
    columnSpacing: root.vertical ? 0 : (root.tallBar ? Style.space(3) : Style.space(2))
    rowSpacing: root.vertical ? (root.tallBar ? Style.space(3) : Style.space(2)) : 0

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

    // 3x3 All Apps launcher icon modeled after Omarchy's built-in dock AppsSlot
    Item {
      id: appsSlot

      readonly property bool hovered: appsMouse.containsMouse
      property var registeredBar: null

      function syncClickRegistration() {
        if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(appsSlot)
        registeredBar = root.bar
        if (registeredBar && registeredBar.registerClickTarget) registeredBar.registerClickTarget(appsSlot)
      }

      visible: root.showAppsButton
      Layout.preferredWidth: root.showAppsButton ? root.slotSize : 0
      Layout.preferredHeight: root.showAppsButton ? root.slotSize : 0

      Connections {
        target: root
        function onBarChanged() { appsSlot.syncClickRegistration() }
      }
      Component.onCompleted: syncClickRegistration()
      Component.onDestruction: {
        if (root.bar) root.bar.hideTooltip(appsSlot)
        if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(appsSlot)
      }

      Rectangle {
        anchors.centerIn: parent
        width: root.slotSize - root.pillInset
        height: root.slotSize - root.pillInset
        radius: Math.max(Style.space(4), Style.cornerRadius)
        color: appsSlot.hovered ? Style.hoverFill : "transparent"

        Behavior on color { ColorAnimation { duration: Style.duration(120) } }
      }

      Item {
        anchors.centerIn: parent
        width: root.appsIconSize
        height: root.appsIconSize
        opacity: appsSlot.hovered ? 1.0 : root.idleOpacity
        scale: appsSlot.hovered ? 1.1 : 1.0

        Behavior on scale { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }

        Grid {
          readonly property int square: Math.max(2, Math.round(root.appsIconSize * 0.22))

          anchors.centerIn: parent
          columns: 3
          spacing: Math.max(1, Math.round(root.appsIconSize * 0.1))

          Repeater {
            model: 9

            delegate: Rectangle {
              width: parent.square
              height: parent.square
              radius: Math.max(1, Math.round(parent.square * 0.2))
              color: root.bar ? root.bar.barForeground : Commons.Color.bar.text
            }
          }
        }
      }

      MouseArea {
        id: appsMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        onEntered: {
          if (root.bar && root.pickerKey.length === 0 && root.menuKey.length === 0 && !root.settingsOpen) {
            root.bar.showTooltip(appsSlot, TaskbarModel.sanitizeTooltipText(strings.t("taskbar.apps"), 96))
          }
        }
        onExited: if (root.bar) root.bar.hideTooltip(appsSlot)
        onClicked: function(event) {
          if (root.bar) root.bar.hideTooltip(appsSlot)
          if (event.button === Qt.RightButton) {
            if (root.settingsOpen) root.closePopouts()
            else root.openSettings(appsSlot)
            return
          }
          root.closePopouts()
          root.toggleAppGrid()
        }
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
          width: root.slotSize - root.pillInset
          height: root.slotSize - root.pillInset
          radius: Math.max(Style.space(4), Style.cornerRadius)
          color: taskSlot.focused ? Style.selectedFill : (taskSlot.hovered ? Style.hoverFill : "transparent")
          border.width: taskSlot.focused ? 1 : 0
          border.color: taskSlot.focused ? Style.normalBorderColor : "transparent"

          Behavior on color { ColorAnimation { duration: Style.duration(120) } }
        }

        Image {
          anchors.centerIn: parent
          anchors.verticalCenterOffset: root.vertical ? 0 : (root.tallBar ? -1 : 0)
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
          readonly property int indicatorLength: taskSlot.focused
            ? Math.round(root.slotSize * 0.42)
            : (taskSlot.windowCount > 1 ? Math.round(root.slotSize * 0.28) : Math.round(root.slotSize * 0.16))

          visible: taskSlot.windowCount > 0
          width: root.vertical ? root.indicatorThickness : indicatorLength
          height: root.vertical ? indicatorLength : root.indicatorThickness
          radius: Math.max(1, Math.round(root.indicatorThickness / 2))
          color: taskSlot.focused ? Commons.Color.accent : (root.bar ? root.bar.barForeground : Commons.Color.bar.text)
          opacity: taskSlot.focused ? 1.0 : (taskSlot.allMinimized ? 0.45 : 0.8)
          anchors.horizontalCenter: root.vertical ? undefined : parent.horizontalCenter
          anchors.bottom: root.vertical ? undefined : parent.bottom
          anchors.bottomMargin: root.vertical ? 0 : root.indicatorMargin
          anchors.verticalCenter: root.vertical ? parent.verticalCenter : undefined
          anchors.left: (root.bar && root.bar.position === "left") ? parent.left : undefined
          anchors.leftMargin: (root.bar && root.bar.position === "left") ? root.indicatorMargin : 0
          anchors.right: (root.bar && root.bar.position === "right") ? parent.right : undefined
          anchors.rightMargin: (root.bar && root.bar.position === "right") ? root.indicatorMargin : 0

          Behavior on width { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }
        }

        // Window count badge when 2+ windows are open
        Rectangle {
          visible: taskSlot.windowCount > 1
          anchors.top: parent.top
          anchors.right: parent.right
          anchors.topMargin: root.tallBar ? Style.space(2) : Style.space(1)
          anchors.rightMargin: root.tallBar ? Style.space(2) : Style.space(1)
          width: Math.max(root.badgeSize, countTxt.implicitWidth + Style.space(4))
          height: root.badgeSize
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
            font.pixelSize: root.tallBar ? Math.max(8, Style.font.caption - 1) : Math.max(7, Style.font.caption - 2)
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
            if (root.bar && root.pickerKey.length === 0 && root.menuKey.length === 0 && !root.settingsOpen) {
              var rawLabel = ""
              if (taskSlot.modelData && taskSlot.modelData.split && taskSlot.windowCount === 1) {
                var w = taskSlot.modelData.windows[0]
                var rawTitle = (w.toplevel && w.toplevel.title) ? w.toplevel.title : (w.title || taskSlot.appLabel)
                rawLabel = w.minimized
                  ? TaskbarModel.formatTemplate(strings.t("taskbar.minimizedPrefix"), rawTitle)
                  : rawTitle
              } else {
                rawLabel = taskSlot.windowCount > 1
                  ? TaskbarModel.formatTemplate(
                      strings.t("taskbar.windowCount"),
                      taskSlot.appLabel,
                      Commons.I18n.formatNumber(taskSlot.windowCount)
                    )
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

  WindowPickerCard {
    id: pickerCard

    readonly property var targetItem: root.pickerKey.length > 0 ? root.itemFor(root.pickerKey) : null

    anchorItem: root.pickerAnchor || root
    owner: pickerOwner
    bar: root.bar
    open: root.pickerKey.length > 0 && !!targetItem && targetItem.windows.length > 0
    strings: strings
    item: targetItem
    fallbackLabel: targetItem ? root.labelFor(targetItem) : ""

    onWindowActivated: function(win) { root.activateWindow(win) }
    onWindowClosed: function(win) { root.closeWindow(win) }
  }

  AppMenuCard {
    id: menuCard

    readonly property var targetItem: root.menuKey.length > 0 ? root.itemFor(root.menuKey) : null
    readonly property string targetAppKey: targetItem ? (targetItem.appKey || targetItem.key) : ""
    readonly property bool isBrowser: TaskbarModel.browserProfileConfigDir(targetAppKey, Commons.Color.home).length > 0

    anchorItem: root.menuAnchor || root
    owner: menuOwner
    bar: root.bar
    open: root.menuKey.length > 0 && !!targetItem
    strings: strings
    item: targetItem
    appKey: targetAppKey
    hasEntry: !!targetItem && !!root.entryFor(targetItem)
    running: !!targetItem && targetItem.windows.length > 0
    allMinimized: root.isItemAllMinimized(targetItem)
    splitWindows: TaskbarModel.isAppUncombined(root.uncombinedApps, targetAppKey)
    showProfiles: isBrowser && root.browserProfiles.length > 0
    browserProfiles: root.browserProfiles

    onProfileLaunched: function(dir) { root.launchBrowserProfile(targetItem, dir) }
    onNewWindowRequested: root.launch(targetItem)
    onMinimizeRequested: root.minimizeAll(targetItem)
    onRestoreRequested: root.restoreAll(targetItem)
    onPinToggled: function(pinned) { root.setPinned(targetAppKey, pinned) }
    onSplitWindowsToggled: root.updateWidgetSettings({
      uncombine: TaskbarModel.toggleUncombineApp(root.uncombinedApps, targetAppKey)
    })
    onCloseRequested: root.quitItem(targetItem)
    onSettingsRequested: {
      var anchor = root.menuAnchor || root
      Qt.callLater(function() { root.openSettings(anchor) })
    }
  }

  QtObject {
    id: settingsOwner
    function close() { root.settingsOpen = false }
  }

  SettingsCard {
    id: settingsCard

    anchorItem: root.settingsAnchor || (root.showAppsButton ? appsSlot : root)
    owner: settingsOwner
    bar: root.bar
    open: root.settingsOpen
    strings: strings
    barSize: root.barSize
    iconSize: root.iconSize
    configuredIconSize: Number(root.configuredIconSize) || 0
    showAppsButton: root.showAppsButton
    twoLineClock: root.twoLineClock
    hyprSettings: root.hyprSettings

    onBarHeightRequested: function(px) {
      root.runConfigHelper(["bar-height", String(px)])
    }
    onIconSizeRequested: function(px) {
      root.updateWidgetSettings({ iconSize: px > 0 ? px : 0 })
    }
    onBarPositionRequested: function(pos) {
      if (pos === "top" || pos === "bottom") {
        Util.execArgv(["omarchy", "bar", "position", pos])
      }
    }
    onTwoLineClockToggled: function(enabled) {
      root.twoLineClock = enabled
      root.runConfigHelper(["two-line-clock", enabled ? "on" : "off"])
    }
    onShowAppsButtonToggled: function(enabled) {
      if (!enabled && root.settingsAnchor === appsSlot) {
        root.settingsAnchor = root
      }
      root.updateWidgetSettings({ showAppsButton: enabled })
    }
    onHyprOptionToggled: function(key, enabled) {
      var next = TaskbarModel.parseHyprSettings(JSON.stringify(root.hyprSettings))
      next[key] = enabled
      root.hyprSettings = next
      root.runConfigHelper(["hypr-set", key, enabled ? "true" : "false"])
    }
  }
}
