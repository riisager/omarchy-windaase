import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "TaskbarModel.js" as TaskbarModel
import "js/AppSearch.js" as AppSearch
import "js/BrowserProfiles.js" as BrowserProfiles
import "js/SnapLayoutMath.js" as SnapLayoutMath
import "js/WindowActions.js" as WindowActions

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
  readonly property int profileBadgeSize: Math.max(Style.space(11), Math.min(Style.space(16), Math.round(root.iconSize * 0.52)))
  readonly property real slotStride: root.slotSize + (root.tallBar ? Style.space(3) : Style.space(2))
  readonly property real idleOpacity: 0.85
  readonly property var uncombinedApps: root.setting("uncombine", [])
  readonly property bool showAppsButton: root.setting("showAppsButton", true)
  readonly property string windowFilter: TaskbarModel.normalizeWindowFilter(root.setting("windowFilter", "all"))
  readonly property bool hoverPreview: root.setting("hoverPreview", true)
  readonly property var barMonitor: {
    var win = root.QsWindow ? root.QsWindow.window : null
    var scr = win ? win.screen : null
    return scr ? Hyprland.monitorFor(scr) : Hyprland.focusedMonitor
  }
  readonly property string barMonitorName: root.barMonitor && root.barMonitor.name ? String(root.barMonitor.name) : ""
  readonly property int barActiveWorkspaceId: root.barMonitor && root.barMonitor.activeWorkspace ? Number(root.barMonitor.activeWorkspace.id) : -1

  property var defaultPinnedList: []
  property var userPinnedList: null
  readonly property var pinnedList: root.userPinnedList !== null ? root.userPinnedList : root.defaultPinnedList

  property var activeBrowserSpec: null
  property string activeBrowserStateFile: ""
  property var browserProfiles: []
  property alias windowProfiles: profileTracker.windowProfiles
  property var urgentAddresses: ({})
  property var windowOrderState: ({ seq: 0, byAddr: {} })
  property int dragIndex: -1
  property int dropIndex: -1
  property real dragOffset: 0
  readonly property bool draggingItem: dragIndex >= 0
  property bool animateShifts: true
  property bool _destroyed: false
  onDraggingItemChanged: if (draggingItem) root.closePopouts()

  property string pickerKey: ""
  property Item pickerAnchor: null
  property string pickerTriggerMode: "click"
  property string hoveredSlotKey: ""
  property string hoverPreviewPendingKey: ""
  property Item hoverPreviewPendingAnchor: null
  property string menuKey: ""
  property Item menuAnchor: null
  property bool settingsOpen: false
  property Item settingsAnchor: null
  property bool twoLineClock: false
  property var hyprSettings: TaskbarModel.defaultHyprSettings()
  property bool companionInstalled: false
  property bool hasLocalInstaller: false
  property bool nautilusMenuInstalled: false
  readonly property string nautilusExtMarker: "# Managed by Omarchy-windåse (riisager.windaase)"
  readonly property string companionInstallCmd: root.hasLocalInstaller
    ? "~/.config/omarchy/plugins/riisager.windaase/install.sh"
    : "git clone https://github.com/riisager/omarchy-windaase.git && ./omarchy-windaase/install.sh"
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
    id: companionLuaFile
    path: Commons.Color.home + "/.config/hypr/windaase.lua"
    watchChanges: true
    blockLoading: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.companionInstalled = String(text() || "").length > 0
    onLoadFailed: root.companionInstalled = false
  }

  FileView {
    id: localInstallerFile
    path: String(Qt.resolvedUrl("install.sh")).replace(/^file:\/\//, "")
    watchChanges: false
    blockLoading: true
    printErrors: false
    onLoaded: root.hasLocalInstaller = String(text() || "").length > 0
    onLoadFailed: root.hasLocalInstaller = false
  }

  FileView {
    id: nautilusMenuFile
    path: Commons.Color.home + "/.local/share/nautilus-python/extensions/windaase_context_menu.py"
    watchChanges: true
    blockLoading: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.nautilusMenuInstalled = String(text() || "").indexOf(root.nautilusExtMarker) >= 0
    onLoadFailed: root.nautilusMenuInstalled = false
  }

  FileView {
    id: browserStateFile
    path: root.activeBrowserStateFile
    watchChanges: false
    blockLoading: true
    printErrors: false
    onLoaded: {
      if (root.activeBrowserSpec) {
        root.browserProfiles = BrowserProfiles.parseBrowserProfiles(text(), root.activeBrowserSpec)
      }
    }
    onLoadFailed: {
      if (root.activeBrowserSpec && root.activeBrowserSpec.fallbackStateFile
          && root.activeBrowserStateFile !== root.activeBrowserSpec.fallbackStateFile) {
        root.activeBrowserStateFile = root.activeBrowserSpec.fallbackStateFile
        browserStateFile.reload()
        return
      }
      root.browserProfiles = []
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event ? String(event.name) : ""
      var dataFirst = event && event.data ? String(event.data).split(",")[0] : ""
      if (name === "fullscreen" || name === "configreloaded" || name === "pin") {
        Hyprland.refreshToplevels()
      }
      if (name === "configreloaded") {
        companionLuaFile.reload()
      }
      if (name === "urgent") {
        var activeAddr = ""
        var toplevels = Hyprland.toplevels.values
        for (var i = 0; i < toplevels.length; i++) {
          var tl = toplevels[i]
          if (tl && tl.wayland && tl.wayland.activated) {
            var ws = tl.workspace
            var isMin = !!ws && TaskbarModel.isMinimizedWorkspace(ws.name)
            if (!isMin) {
              activeAddr = tl.address || ""
              break
            }
          }
        }
        root.urgentAddresses = TaskbarModel.markWindowUrgent(root.urgentAddresses, dataFirst, activeAddr)
      } else if (name === "activewindowv2" || name === "closewindow") {
        root.urgentAddresses = TaskbarModel.clearWindowUrgent(root.urgentAddresses, dataFirst)
      }
    }
  }

  readonly property var terminalEntries: TaskbarModel.collectTerminalEntries(DesktopEntries.applications.values)

  function entryForAppId(appId) {
    var entry = DesktopEntries.heuristicLookup(appId)
    if (entry) return entry
    var id = TaskbarModel.claimingEntryId(appId, root.terminalEntries)
    return id ? DesktopEntries.byId(id) : null
  }

  function iconSourceFor(entry, fallbackId) {
    return TaskbarModel.resolveIconSource(
      entry,
      fallbackId,
      function(name) { return Quickshell.iconPath(name, true) },
      function(p) { return Util.fileUrl(p) }
    )
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
      var normWin = WindowActions.normalizeToplevelWindow(toplevels[i], {
        resolveEntry: root.entryForAppId,
        windowProfiles: root.windowProfiles,
        urgentAddresses: root.urgentAddresses
      })
      if (normWin) windows.push(normWin)
    }

    var orderedWindows = TaskbarModel.stabilizeWindows(windows, root.windowOrderState)
    var scopedWindows = TaskbarModel.filterWindowsByScope(
      orderedWindows,
      root.windowFilter,
      root.barActiveWorkspaceId,
      root.barMonitorName
    )
    var uncombined = TaskbarModel.isArrayLike(root.uncombinedApps) ? root.uncombinedApps : []
    return TaskbarModel.buildItems(pinned, scopedWindows, uncombined)
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

  BrowserProfileTracker {
    id: profileTracker
    widgetRoot: root
    configScriptPath: root.configScriptPath
  }

  Timer {
    id: hoverOpenTimer
    interval: (root.pickerKey.length > 0 && root.pickerTriggerMode === "hover") ? 70 : 300
    onTriggered: {
      if (!root || root._destroyed) return
      if (!root.hoverPreview || root.draggingItem || root.menuKey.length > 0 || root.settingsOpen) return
      if (root.pickerKey.length > 0 && root.pickerTriggerMode !== "hover") return
      if (root.bar && root.bar.activePopout && root.bar.activePopout !== pickerOwner) return
      var key = root.hoverPreviewPendingKey
      var anchor = root.hoverPreviewPendingAnchor
      if (!key || !anchor) return
      var item = root.itemFor(key)
      if (!item || !item.windows || item.windows.length === 0) return
      root.openPicker(key, anchor, "hover")
    }
  }

  Timer {
    id: hoverCloseTimer
    interval: 260
    onTriggered: {
      if (!root || root._destroyed) return
      if (root.pickerKey.length > 0 && root.pickerTriggerMode === "hover" && !pickerCard.containsMouse && root.hoveredSlotKey !== root.pickerKey) {
        root.pickerKey = ""
        root.pickerTriggerMode = "click"
      }
    }
  }

  function refreshNautilusMenuState() {
    nautilusMenuFile.reload()
  }

  Process {
    id: nautilusMenuProc
    onExited: function(exitCode) {
      var peers = root.peerWidgets()
      if (peers && peers.length > 0) {
        for (var i = 0; i < peers.length; i++) {
          if (peers[i] && typeof peers[i].refreshNautilusMenuState === "function") {
            peers[i].refreshNautilusMenuState()
          }
        }
      } else {
        root.refreshNautilusMenuState()
      }
      if (exitCode === 0) settingsCard.nautilusRestartNeeded = true
    }
  }

  function syncUrgentAddresses() {
    if (!root || root._destroyed) return
    var existing = root.urgentAddresses || {}
    var existingKeys = Object.keys(existing).sort()
    if (existingKeys.length === 0) return
    var allWins = []
    var toplevels = Hyprland.toplevels.values
    for (var i = 0; i < toplevels.length; i++) {
      var tl = toplevels[i]
      if (!tl || !tl.wayland) continue
      var ws = tl.workspace
      allWins.push({
        address: tl.address,
        activated: !!tl.wayland.activated,
        minimized: !!ws && TaskbarModel.isMinimizedWorkspace(ws.name)
      })
    }
    var pruned = TaskbarModel.pruneUrgentWindows(existing, allWins)
    var nextKeys = Object.keys(pruned).sort()
    if (nextKeys.join(",") !== existingKeys.join(",")) {
      root.urgentAddresses = pruned
    }
  }

  onBarChanged: Qt.callLater(function() { if (root && !root._destroyed) root.syncBrowserProfiles() })
  onItemsChanged: {
    if (!root || root._destroyed) return
    syncItemModel()
    Qt.callLater(function() { if (root && !root._destroyed) root.syncBrowserProfiles() })
    Qt.callLater(function() { if (root && !root._destroyed) root.syncUrgentAddresses() })
  }
  Component.onCompleted: {
    var userRaw = userShellFile.text()
    root.defaultPinnedList = TaskbarModel.extractPinnedList(defaultShellFile.text()) || []
    root.userPinnedList = TaskbarModel.extractPinnedList(userRaw)
    root.twoLineClock = TaskbarModel.isTwoLineClockFormat(userRaw)
    root.hyprSettings = TaskbarModel.parseHyprSettings(hyprSettingsFile.text())
    root.companionInstalled = String(companionLuaFile.text() || "").length > 0
    root.hasLocalInstaller = String(localInstallerFile.text() || "").length > 0
    root.nautilusMenuInstalled = String(nautilusMenuFile.text() || "").indexOf(root.nautilusExtMarker) >= 0
    syncItemModel()
    syncBrowserProfiles()
  }
  Component.onDestruction: {
    root._destroyed = true
    hoverOpenTimer.stop()
    hoverCloseTimer.stop()
    root.closePopouts()
  }

  function peerWidgets() {
    if (!root || root._destroyed) return []
    if (root.bar && typeof root.bar.moduleWidgets === "function") {
      var list = root.bar.moduleWidgets(root.moduleName)
      if (TaskbarModel.isArrayLike(list) && list.length > 0) return list
    }
    return [root]
  }

  function isProfileLeader() {
    var peers = root.peerWidgets()
    return peers.length === 0 || peers[0] === root
  }

  function syncProfilesToPeers(nextMap) {
    var peers = root.peerWidgets()
    for (var i = 0; i < peers.length; i++) {
      var peer = peers[i]
      if (peer && peer.windowProfiles !== undefined) {
        peer.windowProfiles = nextMap
      }
    }
  }

  function recordProfileLaunch(appKey, profileObj) {
    profileTracker.recordLaunch(appKey, profileObj)
  }

  function syncBrowserProfiles() {
    profileTracker.sync()
  }

  function syncItemModel() {
    var keys = root.items.map(function(item) { return item.key })
    var same = itemModel.count === keys.length
    if (same) {
      for (var k = 0; k < keys.length; k++) {
        if (itemModel.get(k).key !== keys[k]) { same = false; break }
      }
    }
    if (same) return
    if (root.draggingItem) root.endItemDrag()
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
    return root.iconSourceFor(entryFor(item), item ? (item.appKey || item.key) : "")
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
    var argv = AppSearch.launchArgvForEntry(entryFor(item))
    if (argv.length > 0) Util.execArgv(argv)
  }

  function browserBinaryForItem(item) {
    var appKey = item ? TaskbarModel.normalizeId(item.appKey || item.key).toLowerCase() : ""
    var entry = entryFor(item)
    if (entry && entry.command && entry.command.length > 0) {
      var bin = String(entry.command[0] || "").trim()
      if (bin) return bin
    }
    var spec = BrowserProfiles.browserProfileSpec(appKey, "x")
    return spec ? spec.defaultBin : ""
  }

  function launchBrowserProfile(item, profileDir) {
    var dir = String(profileDir || "").trim()
    var bin = browserBinaryForItem(item)
    if (!bin) return
    var appKey = item ? TaskbarModel.normalizeId(item.appKey || item.key).toLowerCase() : ""
    var spec = BrowserProfiles.browserProfileSpec(appKey, Commons.Color.home)
    var argv = BrowserProfiles.browserProfileLaunchArgv(bin, dir, spec)
    if (argv.length === 0) return
    var matched = null
    for (var i = 0; i < root.browserProfiles.length; i++) {
      if (root.browserProfiles[i].dir === dir) {
        matched = root.browserProfiles[i]
        break
      }
    }
    if (appKey && matched) {
      var peers = root.peerWidgets()
      var leader = peers.length > 0 ? peers[0] : root
      if (leader && typeof leader.recordProfileLaunch === "function") {
        leader.recordProfileLaunch(appKey, matched)
      }
    }
    Util.execArgv(argv)
  }

  // Uses hyprctl dispatch directly (not hypr.windaase) so shell-only Marketplace installs stay self-contained.
  function restoreWindows(windows) {
    if (!windows || windows.length === 0) return
    if (windows.length === 1 && !TaskbarModel.normalizeAddress(windows[0] && windows[0].address)) {
      if (windows[0] && windows[0].toplevel) windows[0].toplevel.activate()
      return
    }
    var monitor = Hyprland.focusedMonitor
    var workspace = monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1
    var plan = WindowActions.buildRestoreDispatchPlan(windows, workspace)
    var command = WindowActions.formatRestoreShellCommand(plan, Util.shellQuote)
    if (command) Util.execDetached(command)
  }

  function bringForward(window) {
    if (window) root.restoreWindows([window])
  }

  function minimizeWindows(windows) {
    var monitor = Hyprland.focusedMonitor
    var activeWs = monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1
    var steps = WindowActions.buildMinimizeDispatchSteps(windows, activeWs)
    var command = WindowActions.formatDispatchChain(steps, Util.shellQuote)
    if (command) Util.execDetached(command)
  }

  function minimizeWindow(window) {
    minimizeWindows(window ? [window] : [])
  }

  function minimizeAll(item) {
    minimizeWindows(item && item.windows ? item.windows : [])
  }

  function restoreAll(item) {
    if (!item || !item.windows) return
    var mins = []
    for (var i = 0; i < item.windows.length; i++) {
      if (item.windows[i] && item.windows[i].minimized) mins.push(item.windows[i])
    }
    root.restoreWindows(mins)
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

  function togglePinWindow(window) {
    var command = WindowActions.formatDispatchChain(WindowActions.buildTogglePinDispatchSteps(window), Util.shellQuote)
    if (command) Util.execDetached(command)
  }

  function collectSnapGroupsForItem(item) {
    if (!item || !TaskbarModel.isArrayLike(item.windows) || item.windows.length === 0) return []
    var toplevels = Hyprland.toplevels.values
    var allWins = []
    for (var i = 0; i < toplevels.length; i++) {
      var win = WindowActions.normalizeToplevelWindow(toplevels[i], {
        skipUnmapped: true,
        resolveEntry: root.entryForAppId,
        resolveIcon: root.iconSourceFor,
        windowProfiles: root.windowProfiles
      })
      if (win) allWins.push(win)
    }
    return SnapLayoutMath.detectSnapGroups(allWins, item.windows)
  }

  function bringGroupForward(group) {
    var command = WindowActions.formatDispatchChain(WindowActions.buildBringGroupForwardSteps(group), Util.shellQuote)
    if (command) Util.execDetached(command)
  }

  function quitItem(item) {
    if (!item || !item.windows) return
    var wins = item.windows.slice()
    for (var i = 0; i < wins.length; i++) {
      if (wins[i].toplevel) wins[i].toplevel.close()
    }
  }

  function syncPinnedToPeers(nextPins) {
    var peers = root.peerWidgets()
    for (var i = 0; i < peers.length; i++) {
      var peer = peers[i]
      if (peer && peer.userPinnedList !== undefined) {
        peer.userPinnedList = nextPins
      }
    }
  }

  function syncWindowOrderToPeers(nextOrder) {
    var peers = root.peerWidgets()
    for (var i = 0; i < peers.length; i++) {
      var peer = peers[i]
      if (peer && peer.windowOrderState !== undefined) {
        peer.windowOrderState = nextOrder
      }
    }
  }

  function endItemDrag() {
    root.animateShifts = false
    root.dragIndex = -1
    root.dropIndex = -1
    root.dragOffset = 0
    Qt.callLater(function() { if (root && !root._destroyed) root.animateShifts = true })
  }

  function moveTaskbarItem(fromIdx, toIdx) {
    var res = TaskbarModel.reorderTaskbarItems(root.items, root.pinnedList, root.windowOrderState, fromIdx, toIdx)
    if (!res) return
    if (res.kind === "pins" && TaskbarModel.isArrayLike(res.pinned) && res.pinned.length > 0) {
      root.syncPinnedToPeers(res.pinned)
      Util.execArgv(["omarchy-dock", "pinned"].concat(res.pinned))
    } else if (res.kind === "windows" && res.orderState) {
      root.syncWindowOrderToPeers(res.orderState)
    }
  }

  function setPinned(key, pinned) {
    if (!key) return
    Util.execArgv(["omarchy-dock", pinned ? "pin" : "unpin", String(key)])
  }

  function cancelHoverPreview() {
    hoverOpenTimer.stop()
    hoverCloseTimer.stop()
    root.hoverPreviewPendingKey = ""
    root.hoverPreviewPendingAnchor = null
  }

  function clearPendingHoverForKey(slotKey) {
    if (root.hoverPreviewPendingKey === slotKey) {
      hoverOpenTimer.stop()
      root.hoverPreviewPendingKey = ""
      root.hoverPreviewPendingAnchor = null
    }
  }

  function scheduleHoverPreview(key, slot) {
    if (!root.hoverPreview || root.draggingItem || root.menuKey.length > 0 || root.settingsOpen) return
    if (root.pickerKey.length > 0 && root.pickerTriggerMode !== "hover") return
    if (root.bar && root.bar.activePopout && root.bar.activePopout !== pickerOwner) return
    hoverCloseTimer.stop()
    if (root.pickerKey === key && root.pickerTriggerMode === "hover") {
      hoverOpenTimer.stop()
      root.hoverPreviewPendingKey = ""
      root.hoverPreviewPendingAnchor = null
      return
    }
    root.hoverPreviewPendingKey = key
    root.hoverPreviewPendingAnchor = slot
    hoverOpenTimer.restart()
  }

  function scheduleHoverClose() {
    if (root.pickerKey.length === 0 || root.pickerTriggerMode !== "hover") return
    if (pickerCard.containsMouse || root.hoveredSlotKey === root.pickerKey) return
    hoverCloseTimer.restart()
  }

  function closePopouts() {
    root.cancelHoverPreview()
    root.pickerKey = ""
    root.pickerTriggerMode = "click"
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
    root.cancelHoverPreview()
    root.pickerKey = ""
    root.pickerTriggerMode = "click"
    root.menuKey = ""
    companionLuaFile.reload()
    localInstallerFile.reload()
    nautilusMenuFile.reload()
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

  function openDisplaySettings() {
    root.closePopouts()
    Qt.callLater(function() {
      var res = Commons.IpcRegistry.call("riisager.windaase", "displays", [])
      if (!res || !res.ran) {
        Util.execArgv(["omarchy-shell", "riisager.windaase", "displays"])
      }
    })
  }

  function openPicker(key, slot, mode) {
    hoverOpenTimer.stop()
    hoverCloseTimer.stop()
    root.hoverPreviewPendingKey = ""
    root.hoverPreviewPendingAnchor = null
    root.settingsOpen = false
    root.menuKey = ""
    root.pickerTriggerMode = (mode === "hover") ? "hover" : "click"
    root.pickerKey = key
    root.pickerAnchor = slot
    if (root.bar) root.bar.hideTooltip(slot)
  }

  function openMenu(key, slot) {
    root.cancelHoverPreview()
    var targetItem = root.itemFor(key)
    var appKey = targetItem ? (targetItem.appKey || targetItem.key) : ""
    var spec = BrowserProfiles.browserProfileSpec(appKey, Commons.Color.home)
    if (spec) {
      root.activeBrowserSpec = spec
      root.activeBrowserStateFile = spec.stateFile
      browserStateFile.reload()
      var raw = browserStateFile.text()
      if (!raw && spec.fallbackStateFile) {
        root.activeBrowserStateFile = spec.fallbackStateFile
        browserStateFile.reload()
        raw = browserStateFile.text()
      }
      root.browserProfiles = BrowserProfiles.parseBrowserProfiles(raw, spec)
    } else {
      root.activeBrowserSpec = null
      root.activeBrowserStateFile = ""
      root.browserProfiles = []
    }
    root.settingsOpen = false
    root.pickerKey = ""
    root.pickerTriggerMode = "click"
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

    AppsLauncherSlot {
      id: appsSlot
      taskbar: root
      strings: strings
    }

    Repeater {
      id: itemRepeater
      model: itemModel

      delegate: TaskbarSlot {
        taskbar: root
        dragSpace: layoutGrid
        totalSlots: itemRepeater.count
        strings: strings
      }
    }
  }

  QtObject {
    id: pickerOwner
    function close() {
      root.cancelHoverPreview()
      root.pickerKey = ""
      root.pickerTriggerMode = "click"
    }
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
    triggerMode: root.pickerTriggerMode
    open: root.pickerKey.length > 0 && !!targetItem && targetItem.windows.length > 0
    strings: strings
    item: targetItem
    snapGroups: (open && targetItem) ? root.collectSnapGroupsForItem(targetItem) : []
    fallbackLabel: targetItem ? root.labelFor(targetItem) : ""
    appIconSource: targetItem ? root.iconFor(targetItem) : ""

    onContainsMouseChanged: {
      if (containsMouse) hoverCloseTimer.stop()
      else root.scheduleHoverClose()
    }
    onWindowActivated: function(win) { root.activateWindow(win) }
    onWindowClosed: function(win) { root.closeWindow(win) }
    onWindowPinToggled: function(win) { root.togglePinWindow(win) }
    onSnapGroupActivated: function(grp) { root.bringGroupForward(grp) }
  }

  AppMenuCard {
    id: menuCard

    readonly property var targetItem: root.menuKey.length > 0 ? root.itemFor(root.menuKey) : null
    readonly property string targetAppKey: targetItem ? (targetItem.appKey || targetItem.key) : ""
    readonly property bool isBrowser: !!BrowserProfiles.browserProfileSpec(targetAppKey, Commons.Color.home)
    readonly property var pinTarget: TaskbarModel.targetWindowForPin(targetItem)

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
    canTogglePin: !!pinTarget
    isPinnedOnTop: !!(pinTarget && pinTarget.pinned)
    splitWindows: TaskbarModel.isAppUncombined(root.uncombinedApps, targetAppKey)
    showProfiles: isBrowser && root.browserProfiles.length > 0
    browserProfiles: root.browserProfiles

    onProfileLaunched: function(dir) { root.launchBrowserProfile(targetItem, dir) }
    onNewWindowRequested: root.launch(targetItem)
    onMinimizeRequested: root.minimizeAll(targetItem)
    onRestoreRequested: root.restoreAll(targetItem)
    onPinOnTopToggled: {
      if (pinTarget) root.togglePinWindow(pinTarget)
    }
    onPinToggled: function(pinned) { root.setPinned(targetAppKey, pinned) }
    onSplitWindowsToggled: root.updateWidgetSettings({
      uncombine: TaskbarModel.toggleUncombineApp(root.uncombinedApps, targetAppKey)
    })
    onCloseRequested: root.quitItem(targetItem)
    onDisplaySettingsRequested: {
      root.openDisplaySettings()
    }
    onSettingsRequested: {
      var anchor = root.menuAnchor || root
      Qt.callLater(function() { if (root && !root._destroyed) root.openSettings(anchor) })
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
    windowFilter: root.windowFilter
    showAppsButton: root.showAppsButton
    twoLineClock: root.twoLineClock
    hyprSettings: root.hyprSettings
    companionInstalled: root.companionInstalled
    companionInstallCmd: root.companionInstallCmd
    nautilusMenuInstalled: root.nautilusMenuInstalled

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
    onWindowFilterRequested: function(scope) {
      root.updateWidgetSettings({ windowFilter: TaskbarModel.normalizeWindowFilter(scope) })
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
    onCopyInstallCommandRequested: {
      Util.execArgv(["wl-copy", "--", root.companionInstallCmd])
    }
    onNautilusMenuToggled: function(enabled) {
      if (!root.configScriptPath || nautilusMenuProc.running) return
      nautilusMenuProc.command = ["python3", root.configScriptPath, "nautilus-menu", enabled ? "on" : "off"]
      nautilusMenuProc.running = true
    }
    onRestartFilesRequested: {
      Util.execArgv(["nautilus", "-q"])
    }
    onDisplaySetupRequested: {
      root.openDisplaySettings()
    }
  }
}
