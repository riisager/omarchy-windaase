import QtQuick
import Quickshell.Hyprland
import Quickshell.Io
import "TaskbarModel.js" as TaskbarModel
import "js/BrowserProfiles.js" as BrowserProfiles

// Leader-elected background prober that resolves Chromium/Gecko profiles for running browser windows.
Item {
  id: tracker

  required property var widgetRoot
  property string configScriptPath: ""

  property var windowProfiles: ({})
  property var pendingProfileLaunch: null
  property var knownBrowserAddrs: ({})
  property var profileProbeRetries: ({})
  property var pendingProbeBatch: []
  property var lastProbedBatch: []
  property bool destroyed: false

  visible: false
  width: 0
  height: 0

  Timer {
    id: profileProbeTimer
    interval: 300
    onTriggered: tracker.runProbe()
  }

  Timer {
    id: profileRetryTimer
    interval: 2500
    onTriggered: tracker.runProbe()
  }

  Process {
    id: profileProbeProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: tracker.applyProbeOutput(text)
    }
  }

  Component.onDestruction: {
    tracker.destroyed = true
    profileProbeTimer.stop()
    profileRetryTimer.stop()
  }

  function recordLaunch(appKey, profileObj) {
    if (!appKey || !profileObj || !profileObj.dir) return
    tracker.pendingProfileLaunch = {
      appKey: String(appKey).toLowerCase(),
      dir: String(profileObj.dir),
      name: String(profileObj.name || profileObj.dir),
      initial: String(profileObj.initial || "?"),
      picturePath: String(profileObj.picturePath || ""),
      expiresAt: Date.now() + 12000
    }
  }

  function sync() {
    if (!tracker || tracker.destroyed || !tracker.widgetRoot) return
    var peers = tracker.widgetRoot.peerWidgets()
    if (peers.length > 0 && peers[0] !== tracker.widgetRoot) {
      profileProbeTimer.stop()
      profileRetryTimer.stop()
      var leader = peers[0]
      var leaderMap = (leader && leader.windowProfiles) ? leader.windowProfiles : ({})
      if (JSON.stringify(leaderMap) !== JSON.stringify(tracker.windowProfiles || {})) {
        tracker.windowProfiles = leaderMap
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
      var entry = tracker.widgetRoot.entryForAppId(wl.appId)
      var rawKey = entry ? entry.id : wl.appId
      var normKey = TaskbarModel.normalizeId(rawKey).toLowerCase()
      if (BrowserProfiles.browserProfileConfigDir(normKey, "x").length === 0) continue

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
      if (!tracker.knownBrowserAddrs[addr]) newAddrs[addr] = winObj
    }

    var nextProfiles = {}
    var profilesDirty = false
    var oldKeys = Object.keys(tracker.windowProfiles || {})
    for (var k = 0; k < oldKeys.length; k++) {
      var pk = oldKeys[k]
      if (nextKnown[pk]) nextProfiles[pk] = tracker.windowProfiles[pk]
      else profilesDirty = true
    }

    if (tracker.pendingProfileLaunch) {
      if (Date.now() > tracker.pendingProfileLaunch.expiresAt) {
        tracker.pendingProfileLaunch = null
      } else {
        var newKeys = Object.keys(newAddrs)
        for (var n = 0; n < newKeys.length; n++) {
          var nw = newAddrs[newKeys[n]]
          if (nw.appKey === tracker.pendingProfileLaunch.appKey) {
            nextProfiles[nw.address] = {
              dir: tracker.pendingProfileLaunch.dir,
              name: tracker.pendingProfileLaunch.name,
              initial: tracker.pendingProfileLaunch.initial,
              picturePath: tracker.pendingProfileLaunch.picturePath,
              confident: true
            }
            tracker.pendingProfileLaunch = null
            profilesDirty = true
            break
          }
        }
      }
    }

    var cleanedRetries = {}
    var rKeys = Object.keys(tracker.profileProbeRetries || {})
    for (var r = 0; r < rKeys.length; r++) {
      var rk = rKeys[r]
      if (activeRetryKeys[rk]) cleanedRetries[rk] = tracker.profileProbeRetries[rk]
    }
    tracker.profileProbeRetries = cleanedRetries
    tracker.knownBrowserAddrs = nextKnown

    if (profilesDirty) tracker.widgetRoot.syncProfilesToPeers(nextProfiles)

    var needProbe = []
    for (var b = 0; b < browserWins.length; b++) {
      var bw = browserWins[b]
      var existing = nextProfiles[bw.address]
      if (existing && existing.confident) continue
      var retryKey = bw.address + "|" + bw.title
      if ((tracker.profileProbeRetries[retryKey] || 0) < 3) {
        needProbe.push(bw)
      }
    }

    if (needProbe.length > 0) {
      tracker.pendingProbeBatch = needProbe
      if (!profileProbeTimer.running && !profileProbeProc.running) {
        profileProbeTimer.restart()
      }
    } else {
      tracker.pendingProbeBatch = []
      profileProbeTimer.stop()
      profileRetryTimer.stop()
    }
  }

  function runProbe() {
    if (!tracker || tracker.destroyed || !tracker.widgetRoot || !tracker.widgetRoot.isProfileLeader()
        || profileProbeProc.running || !tracker.configScriptPath) {
      return
    }
    var src = tracker.pendingProbeBatch || []
    var batch = []
    var nextRetries = Object.assign({}, tracker.profileProbeRetries || {})
    for (var i = 0; i < src.length; i++) {
      var item = src[i]
      var existing = tracker.windowProfiles ? tracker.windowProfiles[item.address] : null
      if (existing && existing.confident) continue
      var retryKey = item.address + "|" + item.title
      var count = nextRetries[retryKey] || 0
      if (count >= 3) continue
      nextRetries[retryKey] = count + 1
      batch.push(item)
    }
    tracker.profileProbeRetries = nextRetries
    if (batch.length === 0) return
    tracker.lastProbedBatch = batch
    profileProbeProc.command = ["python3", tracker.configScriptPath, "browser-window-profiles", JSON.stringify(batch)]
    profileProbeProc.running = true
  }

  function applyProbeOutput(rawText) {
    if (!tracker || tracker.destroyed || !tracker.widgetRoot || !tracker.widgetRoot.isProfileLeader()) return
    var res = BrowserProfiles.mergeProfileProbeOutput(rawText, tracker.windowProfiles)
    var merged = res.merged
    if (res.changed) tracker.widgetRoot.syncProfilesToPeers(merged)

    var batch = tracker.lastProbedBatch || []
    var probedAddrs = {}
    for (var j = 0; j < batch.length; j++) {
      var w = batch[j]
      probedAddrs[w.address] = true
      var entry = merged[w.address]
      if ((!entry || !entry.confident) && (tracker.profileProbeRetries[w.address + "|" + w.title] || 0) < 3) {
        profileRetryTimer.restart()
        break
      }
    }
    for (var k = 0; k < batch.length; k++) probedAddrs[batch[k].address] = true
    var pending = tracker.pendingProbeBatch || []
    for (var q = 0; q < pending.length; q++) {
      var pw = pending[q]
      if (probedAddrs[pw.address]) continue
      var pEntry = merged[pw.address]
      if ((!pEntry || !pEntry.confident) && (tracker.profileProbeRetries[pw.address + "|" + pw.title] || 0) < 3) {
        if (!profileProbeTimer.running) profileProbeTimer.restart()
        break
      }
    }
  }
}
