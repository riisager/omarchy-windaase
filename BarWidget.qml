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
  property var browserProfiles: []
  property var windowProfiles: ({})
  property var pendingProfileLaunch: null
  property var knownBrowserAddrs: ({})
  property var profileProbeRetries: ({})
  property var pendingProbeBatch: []
  property var lastProbedBatch: []
  property var windowOrderState: ({ seq: 0, byAddr: {} })
  property int dragIndex: -1
  property int dropIndex: -1
  property real dragOffset: 0
  readonly property bool draggingItem: dragIndex >= 0
  property bool animateShifts: true
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
    id: browserStateFile
    path: root.activeBrowserSpec ? root.activeBrowserSpec.stateFile : ""
    watchChanges: false
    blockLoading: true
    printErrors: false
    onLoaded: {
      if (root.activeBrowserSpec) {
        root.browserProfiles = TaskbarModel.parseBrowserProfiles(text(), root.activeBrowserSpec)
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
      if (name === "configreloaded") {
        companionLuaFile.reload()
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
      var appKey = entry ? entry.id : toplevel.appId
      var workspace = toplevels[i].workspace
      var winMon = toplevels[i].monitor || (workspace ? workspace.monitor : null)
      var rawTags = toplevels[i].lastIpcObject && toplevels[i].lastIpcObject.tags ? toplevels[i].lastIpcObject.tags : []
      var cleanTags = []
      for (var ti = 0; ti < rawTags.length; ti++) {
        cleanTags.push(String(rawTags[ti]))
      }
      var normAddr = TaskbarModel.normalizeAddress(toplevels[i].address)
      windows.push({
        key: appKey,
        hasEntry: !!entry && !entry.noDisplay,
        title: toplevel.title || (entry ? entry.name : toplevel.appId),
        activated: !!toplevel.activated,
        workspaceId: workspace ? workspace.id : -1,
        monitorName: winMon && winMon.name ? String(winMon.name) : "",
        minimized: !!workspace && TaskbarModel.isMinimizedWorkspace(workspace.name),
        address: toplevels[i].address,
        tags: cleanTags,
        profile: normAddr ? TaskbarModel.lookupWindowProfile(normAddr, root.windowProfiles) : null,
        toplevel: toplevel
      })
    }

    var orderedWindows = TaskbarModel.stabilizeWindows(windows, root.windowOrderState)
    var scopedWindows = TaskbarModel.filterWindowsByScope(
      orderedWindows,
      root.windowFilter,
      root.barActiveWorkspaceId,
      root.barMonitorName
    )
    var uncombined = Array.isArray(root.uncombinedApps) ? root.uncombinedApps : []
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

  Timer {
    id: profileProbeTimer
    interval: 300
    onTriggered: root.runProfileProbe()
  }

  Timer {
    id: profileRetryTimer
    interval: 2500
    onTriggered: root.runProfileProbe()
  }

  Timer {
    id: hoverOpenTimer
    interval: (root.pickerKey.length > 0 && root.pickerTriggerMode === "hover") ? 70 : 300
    onTriggered: {
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
      if (root.pickerKey.length > 0 && root.pickerTriggerMode === "hover" && !pickerCard.containsMouse && root.hoveredSlotKey !== root.pickerKey) {
        root.pickerKey = ""
        root.pickerTriggerMode = "click"
      }
    }
  }

  Process {
    id: profileProbeProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyProfileProbeOutput(text)
    }
  }

  onBarChanged: syncBrowserProfiles()
  onItemsChanged: {
    syncItemModel()
    syncBrowserProfiles()
  }
  Component.onCompleted: {
    var userRaw = userShellFile.text()
    root.defaultPinnedList = TaskbarModel.extractPinnedList(defaultShellFile.text()) || []
    root.userPinnedList = TaskbarModel.extractPinnedList(userRaw)
    root.twoLineClock = TaskbarModel.isTwoLineClockFormat(userRaw)
    root.hyprSettings = TaskbarModel.parseHyprSettings(hyprSettingsFile.text())
    root.companionInstalled = String(companionLuaFile.text() || "").length > 0
    root.hasLocalInstaller = String(localInstallerFile.text() || "").length > 0
    syncItemModel()
    syncBrowserProfiles()
  }

  function peerWidgets() {
    if (root.bar && typeof root.bar.moduleWidgets === "function") {
      var list = root.bar.moduleWidgets(root.moduleName)
      if (Array.isArray(list) && list.length > 0) return list
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
    if (!appKey || !profileObj || !profileObj.dir) return
    root.pendingProfileLaunch = {
      appKey: String(appKey).toLowerCase(),
      dir: String(profileObj.dir),
      name: String(profileObj.name || profileObj.dir),
      initial: String(profileObj.initial || "?"),
      picturePath: String(profileObj.picturePath || ""),
      expiresAt: Date.now() + 12000
    }
  }

  function syncBrowserProfiles() {
    var peers = root.peerWidgets()
    if (peers.length > 0 && peers[0] !== root) {
      profileProbeTimer.stop()
      profileRetryTimer.stop()
      var leader = peers[0]
      var leaderMap = (leader && leader.windowProfiles) ? leader.windowProfiles : ({})
      if (JSON.stringify(leaderMap) !== JSON.stringify(root.windowProfiles || {})) {
        root.windowProfiles = leaderMap
      }
      return
    }

    var toplevels = Hyprland.toplevels.values
    var browserWins = []
    var nextKnown = {}
    var activeRetryKeys = {}
    var newAddrs = {}

    for (var i = 0; i < toplevels.length; i++) {
      var tl = toplevels[i]
      var wl = tl ? tl.wayland : null
      if (!wl || !wl.appId || wl.parent) continue
      var entry = root.entryForAppId(wl.appId)
      var rawKey = entry ? entry.id : wl.appId
      var normKey = TaskbarModel.normalizeId(rawKey).toLowerCase()
      if (TaskbarModel.browserProfileConfigDir(normKey, "x").length === 0) continue

      var addr = TaskbarModel.normalizeAddress(tl.address).toLowerCase()
      if (!addr) continue
      var ipc = tl.lastIpcObject || {}
      var winObj = {
        address: addr,
        appKey: normKey,
        pid: ipc.pid ? Number(ipc.pid) : 0,
        title: String(wl.title || ""),
        initialTitle: String(ipc.initialTitle || ""),
        activated: !!wl.activated
      }
      browserWins.push(winObj)
      nextKnown[addr] = true
      activeRetryKeys[addr + "|" + winObj.title] = true
      if (!root.knownBrowserAddrs[addr]) newAddrs[addr] = winObj
    }

    var nextProfiles = {}
    var profilesDirty = false
    var oldKeys = Object.keys(root.windowProfiles || {})
    for (var k = 0; k < oldKeys.length; k++) {
      var pk = oldKeys[k]
      if (nextKnown[pk]) nextProfiles[pk] = root.windowProfiles[pk]
      else profilesDirty = true
    }

    if (root.pendingProfileLaunch) {
      if (Date.now() > root.pendingProfileLaunch.expiresAt) {
        root.pendingProfileLaunch = null
      } else {
        var newKeys = Object.keys(newAddrs)
        for (var n = 0; n < newKeys.length; n++) {
          var nw = newAddrs[newKeys[n]]
          if (nw.appKey === root.pendingProfileLaunch.appKey) {
            nextProfiles[nw.address] = {
              dir: root.pendingProfileLaunch.dir,
              name: root.pendingProfileLaunch.name,
              initial: root.pendingProfileLaunch.initial,
              picturePath: root.pendingProfileLaunch.picturePath,
              confident: true
            }
            root.pendingProfileLaunch = null
            profilesDirty = true
            break
          }
        }
      }
    }

    var cleanedRetries = {}
    var rKeys = Object.keys(root.profileProbeRetries || {})
    for (var r = 0; r < rKeys.length; r++) {
      var rk = rKeys[r]
      if (activeRetryKeys[rk]) cleanedRetries[rk] = root.profileProbeRetries[rk]
    }
    root.profileProbeRetries = cleanedRetries
    root.knownBrowserAddrs = nextKnown

    if (profilesDirty) root.syncProfilesToPeers(nextProfiles)

    var needProbe = []
    for (var b = 0; b < browserWins.length; b++) {
      var bw = browserWins[b]
      var existing = nextProfiles[bw.address]
      if (existing && existing.confident) continue
      var retryKey = bw.address + "|" + bw.title
      if ((root.profileProbeRetries[retryKey] || 0) < 3) {
        needProbe.push(bw)
      }
    }

    if (needProbe.length > 0) {
      root.pendingProbeBatch = needProbe
      if (!profileProbeTimer.running && !profileProbeProc.running) {
        profileProbeTimer.restart()
      }
    } else {
      root.pendingProbeBatch = []
      profileProbeTimer.stop()
      profileRetryTimer.stop()
    }
  }

  function runProfileProbe() {
    if (!root.isProfileLeader() || profileProbeProc.running || !root.configScriptPath) return
    var src = root.pendingProbeBatch || []
    var batch = []
    var nextRetries = Object.assign({}, root.profileProbeRetries || {})
    for (var i = 0; i < src.length; i++) {
      var item = src[i]
      var existing = root.windowProfiles ? root.windowProfiles[item.address] : null
      if (existing && existing.confident) continue
      var retryKey = item.address + "|" + item.title
      var count = nextRetries[retryKey] || 0
      if (count >= 3) continue
      nextRetries[retryKey] = count + 1
      batch.push(item)
    }
    root.profileProbeRetries = nextRetries
    if (batch.length === 0) return
    root.lastProbedBatch = batch
    profileProbeProc.command = ["python3", root.configScriptPath, "browser-window-profiles", JSON.stringify(batch)]
    profileProbeProc.running = true
  }

  function applyProfileProbeOutput(rawText) {
    if (!root.isProfileLeader()) return
    var parsed = null
    try {
      parsed = JSON.parse(String(rawText || "{}"))
    } catch (e) {
      parsed = null
    }
    var merged = Object.assign({}, root.windowProfiles || {})
    var changed = false
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
      var addrs = Object.keys(parsed)
      for (var i = 0; i < addrs.length; i++) {
        var norm = TaskbarModel.normalizeAddress(addrs[i]).toLowerCase()
        var incoming = parsed[addrs[i]]
        if (!norm || !incoming || typeof incoming !== "object" || !incoming.dir) continue
        var cur = merged[norm]
        if (cur && cur.confident) continue
        if (!cur || cur.dir !== incoming.dir || cur.name !== incoming.name
            || cur.picturePath !== incoming.picturePath || !!cur.confident !== !!incoming.confident) {
          merged[norm] = incoming
          changed = true
        }
      }
    }
    if (changed) root.syncProfilesToPeers(merged)

    var batch = root.lastProbedBatch || []
    for (var j = 0; j < batch.length; j++) {
      var w = batch[j]
      var entry = merged[w.address]
      if ((!entry || !entry.confident) && (root.profileProbeRetries[w.address + "|" + w.title] || 0) < 3) {
        profileRetryTimer.restart()
        break
      }
    }
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
    var spec = TaskbarModel.browserProfileSpec(appKey, "x")
    return spec ? spec.defaultBin : ""
  }

  function launchBrowserProfile(item, profileDir) {
    var dir = String(profileDir || "").trim()
    var bin = browserBinaryForItem(item)
    if (!bin) return
    var appKey = item ? TaskbarModel.normalizeId(item.appKey || item.key).toLowerCase() : ""
    var spec = TaskbarModel.browserProfileSpec(appKey, Commons.Color.home)
    var argv = TaskbarModel.browserProfileLaunchArgv(bin, dir, spec)
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
    Qt.callLater(function() { root.animateShifts = true })
  }

  function moveTaskbarItem(fromIdx, toIdx) {
    var res = TaskbarModel.reorderTaskbarItems(root.items, root.pinnedList, root.windowOrderState, fromIdx, toIdx)
    if (!res) return
    if (res.kind === "pins" && Array.isArray(res.pinned) && res.pinned.length > 0) {
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
    var spec = TaskbarModel.browserProfileSpec(appKey, Commons.Color.home)
    if (spec) {
      root.activeBrowserSpec = spec
      browserStateFile.reload()
      root.browserProfiles = TaskbarModel.parseBrowserProfiles(browserStateFile.text(), spec)
    } else {
      root.activeBrowserSpec = null
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

    // 3x3 All Apps launcher icon modeled after Omarchy's built-in dock AppsSlot
    Item {
      id: appsSlot

      readonly property bool hovered: appsMouse.containsMouse
      property var registeredBar: null
      property int heldButtons: Qt.NoButton
      readonly property real pressScale: ((appsMouse.pressedButtons | appsSlot.heldButtons) & Qt.LeftButton) ? 0.9 : 1.0

      function triggerPress(button) {
        if (root.bar) root.bar.hideTooltip(appsSlot)
        if (button === Qt.RightButton) {
          if (root.settingsOpen) root.closePopouts()
          else root.openSettings(appsSlot)
          return
        }
        if (button === Qt.LeftButton) {
          root.closePopouts()
          root.toggleAppGrid()
        }
      }

      function syncClickRegistration() {
        if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(appsSlot)
        registeredBar = root.bar
        if (registeredBar && registeredBar.registerClickTarget) registeredBar.registerClickTarget(appsSlot)
      }

      visible: root.showAppsButton
      Layout.preferredWidth: root.showAppsButton ? root.slotSize : 0
      Layout.preferredHeight: root.showAppsButton ? root.slotSize : 0

      onVisibleChanged: if (!visible && root.bar) root.bar.hideTooltip(appsSlot)
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
        scale: (appsSlot.hovered ? 1.1 : 1.0) * appsSlot.pressScale

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
          if (root.pickerKey.length > 0 && root.pickerTriggerMode === "hover") {
            root.closePopouts()
          }
          if (root.bar && root.pickerKey.length === 0 && root.menuKey.length === 0 && !root.settingsOpen) {
            root.bar.showTooltip(appsSlot, TaskbarModel.sanitizeTooltipText(strings.t("taskbar.apps"), 96))
          }
        }
        onExited: if (root.bar) root.bar.hideTooltip(appsSlot)
        onClicked: function(event) { appsSlot.triggerPress(event.button) }
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
        readonly property var profileBadge: TaskbarModel.profileBadgeForItem(modelData, root.windowProfiles)
        readonly property bool lifted: root.dragIndex === index
        readonly property bool hovered: slotMouse.containsMouse && !root.draggingItem

        property var registeredBar: null
        property int heldButtons: Qt.NoButton
        onHeldButtonsChanged: if (heldButtons !== Qt.NoButton) root.cancelHoverPreview()
        readonly property real pressScale: (!taskSlot.lifted && ((slotMouse.pressedButtons | taskSlot.heldButtons) & Qt.LeftButton)) ? 0.9 : 1.0

        function triggerPress(button) {
          if (root.bar) root.bar.hideTooltip(taskSlot)
          if (!taskSlot.modelData) return
          if (button === Qt.RightButton) {
            if (root.menuKey === taskSlot.key) root.closePopouts()
            else root.openMenu(taskSlot.key, taskSlot)
            return
          }
          if (button === Qt.MiddleButton) {
            root.closePopouts()
            root.launch(taskSlot.modelData)
            return
          }
          if (button !== Qt.LeftButton) return
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
          if (root.pickerKey === taskSlot.key && root.pickerTriggerMode === "click") root.closePopouts()
          else root.openPicker(taskSlot.key, taskSlot, "click")
        }

        function syncClickRegistration() {
          if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(taskSlot)
          registeredBar = root.bar
          if (registeredBar && registeredBar.registerClickTarget) registeredBar.registerClickTarget(taskSlot)
        }

        z: taskSlot.lifted ? 2 : 0
        Layout.preferredWidth: root.slotSize
        Layout.preferredHeight: root.slotSize

        Connections {
          target: root
          function onBarChanged() { taskSlot.syncClickRegistration() }
        }
        Component.onCompleted: syncClickRegistration()
        Component.onDestruction: {
          if (root.hoveredSlotKey === taskSlot.key) root.hoveredSlotKey = ""
          if (root.hoverPreviewPendingAnchor === taskSlot) root.cancelHoverPreview()
          if (root.pickerAnchor === taskSlot) {
            root.pickerKey = ""
            root.pickerAnchor = null
            root.pickerTriggerMode = "click"
          }
          if (taskSlot.lifted) root.endItemDrag()
          if (root.bar) root.bar.hideTooltip(taskSlot)
          if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(taskSlot)
        }

        Item {
          id: slotVisual
          anchors.fill: parent

          readonly property real targetShift: !root.draggingItem
            ? 0
            : taskSlot.lifted
              ? root.dragOffset
              : (root.dragIndex < taskSlot.index && taskSlot.index <= root.dropIndex)
                ? -root.slotStride
                : (root.dropIndex <= taskSlot.index && taskSlot.index < root.dragIndex)
                  ? root.slotStride
                  : 0
          property real displayedShift: targetShift

          Behavior on displayedShift {
            enabled: root.animateShifts && root.draggingItem && !taskSlot.lifted
            NumberAnimation { duration: Style.duration(150); easing.type: Easing.OutCubic }
          }

          scale: taskSlot.lifted ? 1.08 : 1.0
          Behavior on scale { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }

          transform: Translate {
            x: root.vertical ? 0 : slotVisual.displayedShift
            y: root.vertical ? slotVisual.displayedShift : 0
          }

          Rectangle {
            anchors.centerIn: parent
            width: root.slotSize - root.pillInset
            height: root.slotSize - root.pillInset
            radius: Math.max(Style.space(4), Style.cornerRadius)
            color: (taskSlot.focused || taskSlot.lifted) ? Style.selectedFill : (taskSlot.hovered ? Style.hoverFill : "transparent")
            border.width: (taskSlot.focused || taskSlot.lifted) ? 1 : 0
            border.color: taskSlot.lifted ? Commons.Color.accent : (taskSlot.focused ? Style.normalBorderColor : "transparent")

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
            scale: (taskSlot.hovered ? 1.1 : 1.0) * taskSlot.pressScale

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

          // Browser profile avatar badge in bottom-right corner
          Rectangle {
            id: profileBadgeContainer
            visible: !!taskSlot.profileBadge
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: root.tallBar ? Style.space(2) : Style.space(1)
            anchors.bottomMargin: root.vertical ? Style.space(2) : (root.indicatorMargin + root.indicatorThickness + 1)
            width: root.profileBadgeSize + 2
            height: root.profileBadgeSize + 2
            radius: width / 2
            color: Commons.Color.bar.background
            border.width: 1
            border.color: Util.alpha(Commons.Color.popups.border, 0.7)
            opacity: taskSlot.allMinimized ? 0.78 : 1.0

            ProfileAvatar {
              anchors.centerIn: parent
              width: root.profileBadgeSize - 2
              height: root.profileBadgeSize - 2
              picturePath: taskSlot.profileBadge ? (taskSlot.profileBadge.picturePath || "") : ""
              initial: taskSlot.profileBadge ? (taskSlot.profileBadge.initial || "?") : ""
              pixelSize: Math.max(7, Math.round(root.profileBadgeSize * 0.58))
            }
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
        }

        MouseArea {
          id: slotMouse
          anchors.fill: parent
          hoverEnabled: true
          preventStealing: true
          cursorShape: taskSlot.lifted ? Qt.ClosedHandCursor : Qt.PointingHandCursor
          acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

          property point pressPoint
          property int dragButton: Qt.NoButton
          property bool didDrag: false

          onEntered: {
            root.hoveredSlotKey = taskSlot.key
            if (root.hoverPreview && taskSlot.windowCount > 0) {
              root.scheduleHoverPreview(taskSlot.key, taskSlot)
            } else if (root.pickerKey.length > 0 && root.pickerTriggerMode === "hover") {
              root.closePopouts()
            }
            if ((!root.hoverPreview || taskSlot.windowCount === 0) && !root.draggingItem && root.bar && root.pickerKey.length === 0 && root.menuKey.length === 0 && !root.settingsOpen) {
              var rawLabel = ""
              if (taskSlot.modelData && taskSlot.modelData.split && taskSlot.windowCount === 1) {
                var w = taskSlot.modelData.windows[0]
                var baseTitle = (w.toplevel && w.toplevel.title) ? w.toplevel.title : (w.title || taskSlot.appLabel)
                var rawTitle = TaskbarModel.formatWindowTooltipWithProfile(baseTitle, taskSlot.profileBadge || w.profile)
                rawLabel = w.minimized
                  ? TaskbarModel.formatTemplate(strings.t("taskbar.minimizedPrefix"), rawTitle)
                  : rawTitle
              } else {
                var baseSummary = taskSlot.windowCount > 1
                  ? TaskbarModel.formatTemplate(
                      strings.t("taskbar.windowCount"),
                      taskSlot.appLabel,
                      Commons.I18n.formatNumber(taskSlot.windowCount)
                    )
                  : taskSlot.appLabel
                rawLabel = TaskbarModel.formatWindowTooltipWithProfile(baseSummary, taskSlot.profileBadge)
              }
              root.bar.showTooltip(taskSlot, TaskbarModel.sanitizeTooltipText(rawLabel, 96))
            }
          }
          onExited: {
            if (root.hoveredSlotKey === taskSlot.key) root.hoveredSlotKey = ""
            if (root.hoverPreviewPendingKey === taskSlot.key) {
              hoverOpenTimer.stop()
              root.hoverPreviewPendingKey = ""
              root.hoverPreviewPendingAnchor = null
            }
            root.scheduleHoverClose()
            if (root.bar) root.bar.hideTooltip(taskSlot)
          }

          onPressed: function(event) {
            slotMouse.didDrag = false
            slotMouse.dragButton = Qt.NoButton
            if (event.button === Qt.RightButton || event.button === Qt.MiddleButton) {
              slotMouse.dragButton = event.button
              slotMouse.pressPoint = taskSlot.mapToItem(layoutGrid, event.x, event.y)
            }
          }

          onPositionChanged: function(event) {
            if (slotMouse.dragButton === Qt.NoButton || !(slotMouse.pressedButtons & slotMouse.dragButton)) return
            var pt = taskSlot.mapToItem(layoutGrid, event.x, event.y)
            var delta = root.vertical ? (pt.y - slotMouse.pressPoint.y) : (pt.x - slotMouse.pressPoint.x)
            if (!root.draggingItem) {
              if (Math.abs(delta) < Style.space(6)) return
              slotMouse.didDrag = true
              if (root.bar) root.bar.hideTooltip(taskSlot)
              root.closePopouts()
              root.dropIndex = taskSlot.index
              root.dragIndex = taskSlot.index
            }
            if (!taskSlot.lifted) return
            var minOffset = -taskSlot.index * root.slotStride
            var maxOffset = Math.max(0, itemRepeater.count - 1 - taskSlot.index) * root.slotStride
            root.dragOffset = Math.max(minOffset, Math.min(maxOffset, delta))
            root.dropIndex = TaskbarModel.computeDropIndex(taskSlot.index, root.dragOffset, root.slotStride, itemRepeater.count)
          }

          onReleased: function(event) {
            slotMouse.dragButton = Qt.NoButton
            if (!taskSlot.lifted) return
            var from = root.dragIndex
            var to = root.dropIndex
            slotMouse.didDrag = true
            Qt.callLater(function() { slotMouse.didDrag = false })
            root.endItemDrag()
            root.moveTaskbarItem(from, to)
          }

          onCanceled: {
            slotMouse.dragButton = Qt.NoButton
            slotMouse.didDrag = false
            if (taskSlot.lifted) root.endItemDrag()
          }

          onClicked: function(event) {
            if (slotMouse.didDrag && event.button !== Qt.LeftButton) {
              slotMouse.didDrag = false
              return
            }
            taskSlot.triggerPress(event.button)
          }
        }
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
    fallbackLabel: targetItem ? root.labelFor(targetItem) : ""
    appIconSource: targetItem ? root.iconFor(targetItem) : ""

    onContainsMouseChanged: {
      if (containsMouse) hoverCloseTimer.stop()
      else root.scheduleHoverClose()
    }
    onWindowActivated: function(win) { root.activateWindow(win) }
    onWindowClosed: function(win) { root.closeWindow(win) }
  }

  AppMenuCard {
    id: menuCard

    readonly property var targetItem: root.menuKey.length > 0 ? root.itemFor(root.menuKey) : null
    readonly property string targetAppKey: targetItem ? (targetItem.appKey || targetItem.key) : ""
    readonly property bool isBrowser: !!TaskbarModel.browserProfileSpec(targetAppKey, Commons.Color.home)

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
    windowFilter: root.windowFilter
    showAppsButton: root.showAppsButton
    twoLineClock: root.twoLineClock
    hyprSettings: root.hyprSettings
    companionInstalled: root.companionInstalled
    companionInstallCmd: root.companionInstallCmd

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
  }
}
