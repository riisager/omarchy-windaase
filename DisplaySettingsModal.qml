import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "TaskbarModel.js" as TaskbarModel
import "js/MonitorLayout.js" as MonitorLayout

// Visual Windows 11-style multi-monitor layout editor with magnetic snap,
// dock-profile persistence, hardware Identify overlay, and 15s revert safety.
Item {
  id: root

  property bool opened: false
  property bool busy: false
  property bool profileSaved: false
  property bool clamshellClosed: false
  property string profileId: ""
  property string errorText: ""
  property bool preserveErrorOnLoad: false

  property var liveMonitors: []
  property var draftMonitors: []
  property string selectedKey: ""

  property bool confirmPending: false
  property int confirmSeconds: 15
  property var revertSnapshot: []

  onConfirmPendingChanged: {
    if (root.opened) {
      Qt.callLater(function() { if (root && root.opened && !monitorInspector.dropdownOpen && keyCatcher) keyCatcher.forceActiveFocus() })
    }
  }

  Component.onDestruction: {
    confirmTimer.stop()
    monitorSyncTimer.stop()
    monitorHotplugRefreshTimer.stop()
    root.opened = false
  }

  signal identifyRequested(var items)

  readonly property string configScriptPath: String(Qt.resolvedUrl("windaase-config.py")).replace(/^file:\/\//, "")
  readonly property bool isDirty: MonitorLayout.monitorsStateChanged(root.draftMonitors, root.liveMonitors)

  readonly property var selectedMonitor: {
    var list = root.draftMonitors || []
    for (var i = 0; i < list.length; i++) {
      if (String(list[i].matchKey) === root.selectedKey) return list[i]
    }
    return list.length > 0 ? list[0] : null
  }

  readonly property int enabledCount: {
    var list = root.draftMonitors || []
    var c = 0
    for (var i = 0; i < list.length; i++) {
      if (list[i] && list[i].enabled !== false) c++
    }
    return c
  }

  readonly property var disabledMonitors: {
    var list = root.draftMonitors || []
    var out = []
    for (var i = 0; i < list.length; i++) {
      if (list[i] && list[i].enabled === false) out.push(list[i])
    }
    return out
  }

  readonly property var selectedScaleOptions: {
    var m = root.selectedMonitor
    if (!m) return []
    return MonitorLayout.availableMonitorScales(m.width, m.height, m.scale)
  }

  readonly property string selectedCleanScale: {
    var m = root.selectedMonitor
    if (!m) return "1"
    return MonitorLayout.cleanMonitorScale(m.scale, m.width, m.height)
  }

  readonly property var selectedModeOptions: {
    var m = root.selectedMonitor
    if (!m) return []
    var avail = (m.availableModes && typeof m.availableModes.length === "number") ? m.availableModes : []
    var prefHint = avail.length > 0 ? avail[0] : (m.liveMode || "")
    var out = [{
      value: "preferred",
      label: TaskbarModel.sanitizePlainLabel(
        TaskbarModel.formatTemplate(strings.t("display.modePreferred"), prefHint),
        64
      )
    }]
    var seen = { "preferred": true }
    for (var i = 0; i < avail.length; i++) {
      var modeStr = String(avail[i] || "").trim()
      if (!modeStr || seen[modeStr]) continue
      seen[modeStr] = true
      out.push({
        value: modeStr,
        label: TaskbarModel.sanitizePlainLabel(modeStr, 48)
      })
    }
    return out
  }

  readonly property bool selectedCanToggleEnabled: {
    var m = root.selectedMonitor
    if (!m) return false
    if (m.clamshellLocked) return false
    if (m.enabled !== false && root.enabledCount <= 1) return false
    return true
  }

  Commons.Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

  function open() {
    if (root.opened) return
    root.errorText = ""
    root.preserveErrorOnLoad = false
    root.confirmPending = false
    monitorCanvas.cancelDrag()
    root.opened = true
    root.loadStatus(false)
  }

  function close() {
    if (!root.opened) return
    if (root.confirmPending) {
      root.revertChanges(true)
      return
    }
    monitorHotplugRefreshTimer.stop()
    monitorCanvas.cancelDrag()
    root.opened = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function cloneMonitorsList(src) {
    var out = []
    var list = (src && typeof src.length === "number") ? src : []
    for (var i = 0; i < list.length; i++) {
      var m = list[i]
      if (!m || typeof m !== "object") continue
      var copy = {}
      var keys = Object.keys(m)
      for (var k = 0; k < keys.length; k++) copy[keys[k]] = m[keys[k]]
      var sz = MonitorLayout.monitorLogicalSizeForSpec(copy)
      copy.logicalW = sz.w
      copy.logicalH = sz.h
      out.push(copy)
    }
    return out
  }

  function applyStatusPayload(raw) {
    try {
      var parsed = JSON.parse(String(raw || ""))
      if (!parsed || typeof parsed !== "object" || !MonitorLayout.isArrayLike(parsed.monitors)) return
      root.profileId = String(parsed.profileId || "")
      root.profileSaved = !!parsed.profileSaved
      root.clamshellClosed = !!parsed.clamshellClosed
      root.liveMonitors = root.cloneMonitorsList(parsed.monitors)
      root.draftMonitors = root.cloneMonitorsList(parsed.monitors)
      var hasSelected = false
      for (var i = 0; i < root.draftMonitors.length; i++) {
        if (String(root.draftMonitors[i].matchKey) === root.selectedKey) {
          hasSelected = true
          break
        }
      }
      if (!hasSelected && root.draftMonitors.length > 0) {
        var focused = null
        for (var j = 0; j < root.draftMonitors.length; j++) {
          if (root.draftMonitors[j].focused) {
            focused = root.draftMonitors[j]
            break
          }
        }
        root.selectedKey = String((focused || root.draftMonitors[0]).matchKey || "")
      }
      if (!root.preserveErrorOnLoad) {
        root.errorText = ""
      }
      root.preserveErrorOnLoad = false
    } catch (e) {}
  }

  function loadStatus(preserveError) {
    if (statusProc.running) return
    root.preserveErrorOnLoad = !!preserveError
    statusOutput.text = ""
    statusProc.command = ["python3", root.configScriptPath, "monitors-status"]
    statusProc.running = true
  }

  function resetDraft() {
    if (root.confirmPending || root.busy) return
    monitorCanvas.cancelDrag()
    root.errorText = ""
    root.draftMonitors = root.cloneMonitorsList(root.liveMonitors)
  }

  function updateSelectedField(patchFn, normalizeAfter) {
    if (root.confirmPending || root.busy || !root.selectedMonitor) return
    var next = root.cloneMonitorsList(root.draftMonitors)
    var targetKey = String(root.selectedMonitor.matchKey)
    for (var i = 0; i < next.length; i++) {
      if (String(next[i].matchKey) === targetKey) {
        patchFn(next[i])
        break
      }
    }
    root.draftMonitors = normalizeAfter
      ? MonitorLayout.normalizeMonitorLayout(next, targetKey)
      : next
  }

  function setSelectedEnabled(enabled) {
    if (!root.selectedMonitor || !root.selectedCanToggleEnabled) return
    root.updateSelectedField(function(m) { m.enabled = !!enabled }, true)
  }

  function setSelectedScale(scaleVal) {
    var m = root.selectedMonitor
    if (!m) return
    var clean = Number(MonitorLayout.cleanMonitorScale(scaleVal, m.width, m.height))
    if (!isFinite(clean) || clean <= 0) return
    root.updateSelectedField(function(item) { item.scale = clean }, true)
  }

  function setSelectedTransform(trVal) {
    var tr = ((Math.round(Number(trVal) || 0) % 4) + 4) % 4
    root.updateSelectedField(function(item) { item.transform = tr }, true)
  }

  function setSelectedMode(modeVal) {
    root.updateSelectedField(function(item) {
      item.mode = String(modeVal || "preferred")
      var parsed = MonitorLayout.parseMonitorMode(item.mode, item.width, item.height, item.refreshRate)
      item.width = parsed.width
      item.height = parsed.height
      item.refreshRate = parsed.hz
      item.scale = Number(MonitorLayout.cleanMonitorScale(item.scale, parsed.width, parsed.height))
    }, true)
  }

  function payloadJsonFromDraft() {
    var list = []
    var src = root.draftMonitors || []
    for (var i = 0; i < src.length; i++) {
      var m = src[i]
      list.push({
        name: String(m.name || ""),
        matchKey: String(m.matchKey || ""),
        enabled: m.enabled !== false,
        mode: String(m.mode || "preferred"),
        x: Math.round(Number(m.x) || 0),
        y: Math.round(Number(m.y) || 0),
        scale: Number(m.scale) || 1.0,
        transform: ((Math.round(Number(m.transform) || 0) % 4) + 4) % 4
      })
    }
    return JSON.stringify({ monitors: list })
  }

  function applyDraftPreview() {
    if (!root.isDirty || root.busy || root.confirmPending) return
    monitorCanvas.cancelDrag()
    root.errorText = ""
    previewOutput.text = ""
    root.busy = true
    previewProc.command = ["python3", root.configScriptPath, "monitors-preview", root.payloadJsonFromDraft()]
    previewProc.running = true
  }

  function commitChanges() {
    if (!root.confirmPending || root.busy) return
    confirmTimer.stop()
    root.confirmPending = false
    commitOutput.text = ""
    root.busy = true
    commitProc.command = ["python3", root.configScriptPath, "monitors-commit", root.payloadJsonFromDraft()]
    commitProc.running = true
  }

  function revertChanges(closeAfter) {
    confirmTimer.stop()
    root.confirmPending = false
    if (revertProc.running) return
    revertOutput.text = ""
    root.closeOnRevert = !!closeAfter
    root.busy = true
    var argList = ["python3", root.configScriptPath, "monitors-revert"]
    if (root.revertSnapshot && typeof root.revertSnapshot.length === "number" && root.revertSnapshot.length > 0) {
      argList.push(JSON.stringify({ monitors: root.revertSnapshot }))
    }
    revertProc.command = argList
    revertProc.running = true
  }

  property bool closeOnRevert: false

  function triggerIdentify() {
    var list = []
    var src = (root.liveMonitors && root.liveMonitors.length > 0) ? root.liveMonitors : (root.draftMonitors || [])
    for (var i = 0; i < src.length; i++) {
      var m = src[i]
      if (!m || m.enabled === false) continue
      var logW = Math.round(Number(m.logicalW) || Number(m.width) || 0)
      var logH = Math.round(Number(m.logicalH) || Number(m.height) || 0)
      list.push({
        name: String(m.name || ""),
        number: Number(m.number) || (i + 1),
        label: TaskbarModel.sanitizePlainLabel((m.name || "") + (m.model ? (" · " + m.model) : ""), 48),
        detail: (logW > 0 && logH > 0)
          ? (Commons.I18n.formatNumber(logW) + " × " + Commons.I18n.formatNumber(logH))
          : ""
      })
    }
    root.identifyRequested(list)
  }

  Timer {
    id: confirmTimer
    interval: 1000
    repeat: true
    onTriggered: {
      if (!root.confirmPending) {
        confirmTimer.stop()
        return
      }
      root.confirmSeconds = Math.max(0, root.confirmSeconds - 1)
      if (root.confirmSeconds <= 0) {
        root.revertChanges(false)
      }
    }
  }

  Timer {
    id: monitorSyncTimer
    interval: 250
    repeat: false
    onTriggered: Hyprland.refreshMonitors()
  }

  Timer {
    id: monitorHotplugRefreshTimer
    interval: 350
    repeat: false
    onTriggered: {
      if (root.opened && !root.confirmPending && !root.busy && !monitorCanvas.dragging) {
        root.loadStatus(false)
      }
    }
  }

  Connections {
    target: Quickshell
    function onScreensChanged() {
      if (root.opened && !root.confirmPending && !root.busy && !monitorCanvas.dragging) {
        monitorHotplugRefreshTimer.restart()
      }
    }
  }

  QtObject { id: statusOutput; property string text: "" }
  QtObject { id: previewOutput; property string text: "" }
  QtObject { id: commitOutput; property string text: "" }
  QtObject { id: revertOutput; property string text: "" }

  Process {
    id: statusProc
    stdout: SplitParser { onRead: function(line) { statusOutput.text += line + "\n" } }
    onExited: function(code) {
      if (code === 0) root.applyStatusPayload(statusOutput.text)
      else root.preserveErrorOnLoad = false
    }
  }

  Process {
    id: previewProc
    stdout: SplitParser { onRead: function(line) { previewOutput.text += line + "\n" } }
    onExited: function(code) {
      root.busy = false
      Hyprland.refreshMonitors()
      monitorSyncTimer.restart()
      if (code === 0) {
        try {
          var res = JSON.parse(previewOutput.text)
          root.revertSnapshot = (res && MonitorLayout.isArrayLike(res.revert)) ? res.revert : []
          if (!root.opened) {
            root.revertChanges(false)
            return
          }
          root.confirmSeconds = 15
          root.confirmPending = true
          confirmTimer.restart()
          return
        } catch (e) {}
      }
      root.errorText = strings.t("display.applyError")
      root.confirmPending = false
      root.loadStatus(true)
    }
  }

  Process {
    id: commitProc
    stdout: SplitParser { onRead: function(line) { commitOutput.text += line + "\n" } }
    onExited: function(code) {
      root.busy = false
      root.revertSnapshot = []
      Hyprland.refreshMonitors()
      monitorSyncTimer.restart()
      if (code === 0) {
        root.preserveErrorOnLoad = false
        root.applyStatusPayload(commitOutput.text)
      } else {
        root.errorText = strings.t("display.applyError")
        root.loadStatus(true)
      }
    }
  }

  Process {
    id: revertProc
    stdout: SplitParser { onRead: function(line) { revertOutput.text += line + "\n" } }
    onExited: function(code) {
      root.busy = false
      root.revertSnapshot = []
      Hyprland.refreshMonitors()
      monitorSyncTimer.restart()
      if (code === 0) {
        root.preserveErrorOnLoad = false
        root.applyStatusPayload(revertOutput.text)
      } else {
        root.errorText = strings.t("display.applyError")
        root.loadStatus(true)
      }
      if (root.closeOnRevert) {
        root.closeOnRevert = false
        root.opened = false
      }
    }
  }

  OverlayWindow {
    id: overlay
    shown: root.opened
    WlrLayershell.namespace: "omarchy-windaase-displays"
    // Avoid holding an exclusive compositor keyboard grab if hotplug/scale changes hide the window.
    shownKeyboardFocus: (root.opened && overlay.contentRevealed) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onContentReadyChanged: {
      if (contentReady && root.opened && !monitorInspector.dropdownOpen) {
        Qt.callLater(function() { if (root && root.opened && !monitorInspector.dropdownOpen && keyCatcher) keyCatcher.forceActiveFocus() })
      }
    }
    onContentRevealedChanged: {
      if (contentRevealed && root.opened && !monitorInspector.dropdownOpen) {
        Qt.callLater(function() { if (root && root.opened && !monitorInspector.dropdownOpen && keyCatcher) keyCatcher.forceActiveFocus() })
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
        if (!root.confirmPending) root.close()
      }
    }

    BorderSurface {
      id: card

      width: Math.min(Math.max(Style.space(420), overlay.width - Style.space(48)), Style.space(760))
      height: Math.min(
        Math.max(Style.space(320), overlay.height - Style.space(48)),
        mainCol.implicitHeight + card.contentTopInset + card.contentBottomInset
      )
      anchors.centerIn: parent
      radius: Math.max(Style.space(10), Style.cornerRadius)
      color: Commons.Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Commons.Color.menu.border, Math.max(1, Style.normalBorderWidth))
      padding: Style.spacing.panelPadding

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: {}
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (monitorInspector.dropdownOpen) return
          if (root.confirmPending) {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.commitChanges()
              event.accepted = true
            } else if (event.key === Qt.Key_Escape) {
              root.revertChanges(false)
              event.accepted = true
            }
            return
          }
          if (event.key === Qt.Key_Escape) {
            root.close()
            event.accepted = true
          }
        }
      }

      Column {
        id: mainCol
        x: card.contentLeftInset
        y: card.contentTopInset
        width: card.width - card.contentLeftInset - card.contentRightInset
        spacing: Style.spacing.md

        // Header bar: Title, dock profile status badge, Identify, Refresh, Close
        RowLayout {
          width: parent.width
          spacing: Style.spacing.sm

          Text {
            textFormat: Text.PlainText
            text: strings.t("display.title")
            color: Commons.Color.menu.text
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }

          Rectangle {
            visible: root.profileId !== ""
            radius: Math.max(Style.space(6), Style.cornerRadius)
            color: root.profileSaved
              ? Util.alpha(Commons.Color.accent, 0.14)
              : Util.alpha(Commons.Color.menu.text, 0.08)
            border.width: 1
            border.color: root.profileSaved
              ? Util.alpha(Commons.Color.accent, 0.45)
              : Util.alpha(Commons.Color.menu.border, 0.5)
            implicitWidth: profileBadgeText.implicitWidth + Style.spacing.sm * 2
            implicitHeight: profileBadgeText.implicitHeight + Style.space(4)

            Text {
              id: profileBadgeText
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: root.profileSaved ? strings.t("display.profileSaved") : strings.t("display.profileUnsaved")
              color: root.profileSaved ? Commons.Color.accent : Commons.Color.menu.text
              opacity: root.profileSaved ? 1.0 : 0.78
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }

          Item { Layout.fillWidth: true }

          Button {
            text: TaskbarModel.sanitizePlainLabel(strings.t("display.identify"), 32)
            bordered: true
            focusable: false
            enabled: root.enabledCount > 0
            opacity: enabled ? 1.0 : 0.45
            foreground: Commons.Color.menu.text
            background: Commons.Color.menu.background
            accent: Commons.Color.accent
            fontSize: Style.font.caption
            horizontalPadding: Style.spacing.sm
            verticalPadding: Style.space(4)
            onClicked: root.triggerIdentify()
          }

          Button {
            text: TaskbarModel.sanitizePlainLabel(strings.t("display.refresh"), 32)
            bordered: true
            focusable: false
            enabled: !root.busy && !root.confirmPending
            opacity: enabled ? 1.0 : 0.45
            foreground: Commons.Color.menu.text
            background: Commons.Color.menu.background
            accent: Commons.Color.accent
            fontSize: Style.font.caption
            horizontalPadding: Style.spacing.sm
            verticalPadding: Style.space(4)
            onClicked: root.loadStatus(false)
          }

          Button {
            text: "\u2715"
            bordered: true
            focusable: false
            foreground: Commons.Color.menu.text
            background: Commons.Color.menu.background
            accent: Commons.Color.accent
            fontSize: Style.font.caption
            horizontalPadding: Style.spacing.sm
            verticalPadding: Style.space(4)
            onClicked: root.close()
          }
        }

        MonitorCanvas {
          id: monitorCanvas
          width: parent.width
          height: Math.round(Math.max(Style.space(150), Math.min(Style.space(240), overlay.height * 0.32)))
          strings: strings
          draftMonitors: root.draftMonitors
          disabledMonitors: root.disabledMonitors
          selectedKey: root.selectedKey
          enabledCount: root.enabledCount
          interactive: !root.confirmPending && !root.busy
          onMonitorSelected: function(matchKey) { root.selectedKey = matchKey }
          onMonitorMoved: function(matchKey, newX, newY) {
            var next = root.cloneMonitorsList(root.draftMonitors)
            for (var i = 0; i < next.length; i++) {
              if (String(next[i].matchKey) === matchKey) {
                next[i].x = newX
                next[i].y = newY
                break
              }
            }
            root.draftMonitors = MonitorLayout.normalizeMonitorLayout(next, matchKey)
          }
        }

        MonitorInspector {
          id: monitorInspector
          width: parent.width
          strings: strings
          selectedMonitor: root.selectedMonitor
          enabledCount: root.enabledCount
          selectedCanToggleEnabled: root.selectedCanToggleEnabled
          selectedScaleOptions: root.selectedScaleOptions
          selectedCleanScale: root.selectedCleanScale
          selectedModeOptions: root.selectedModeOptions
          interactive: !root.confirmPending && !root.busy
          onEnabledToggled: function(en) { root.setSelectedEnabled(en) }
          onScaleSelected: function(val) { root.setSelectedScale(val) }
          onTransformSelected: function(tr) { root.setSelectedTransform(tr) }
          onModeSelected: function(val) { root.setSelectedMode(val) }
          onDropdownClosed: {
            if (root.opened) {
              Qt.callLater(function() { if (root && root.opened && !monitorInspector.dropdownOpen && keyCatcher) keyCatcher.forceActiveFocus() })
            }
          }
        }

        // Inline error banner when applying or reverting display rules fails
        Rectangle {
          visible: root.errorText !== ""
          width: parent.width
          implicitHeight: errorBannerText.implicitHeight + Style.spacing.sm * 2
          height: implicitHeight
          radius: Style.cornerRadius
          color: Util.alpha(Commons.Color.urgent, 0.14)
          border.width: 1
          border.color: Util.alpha(Commons.Color.urgent, 0.55)

          Text {
            id: errorBannerText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Style.spacing.sm
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: root.errorText
            color: Commons.Color.urgent
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }

        // Footer actions: coordinates readout, Reset, Apply
        RowLayout {
          width: parent.width
          spacing: Style.spacing.sm

          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            elide: Text.ElideRight
            text: root.selectedMonitor
              ? TaskbarModel.formatTemplate(
                  strings.t("display.positionReadout"),
                  Commons.I18n.formatNumber(Math.round(Number(root.selectedMonitor.x) || 0)),
                  Commons.I18n.formatNumber(Math.round(Number(root.selectedMonitor.y) || 0))
                )
              : ""
            color: Commons.Color.menu.text
            opacity: 0.72
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          Button {
            text: TaskbarModel.sanitizePlainLabel(strings.t("display.reset"), 32)
            bordered: true
            focusable: false
            enabled: root.isDirty && !root.busy && !root.confirmPending
            opacity: enabled ? 1.0 : 0.45
            foreground: Commons.Color.menu.text
            background: Commons.Color.menu.background
            accent: Commons.Color.accent
            fontSize: Style.font.body
            onClicked: root.resetDraft()
          }

          Button {
            text: TaskbarModel.sanitizePlainLabel(strings.t("display.apply"), 32)
            bordered: true
            selected: root.isDirty
            focusable: false
            enabled: root.isDirty && !root.busy && !root.confirmPending
            opacity: enabled ? 1.0 : 0.45
            foreground: Commons.Color.menu.text
            background: Commons.Color.menu.background
            accent: Commons.Color.accent
            fontSize: Style.font.body
            onClicked: root.applyDraftPreview()
          }
        }
      }

      // Windows-style 15-second keep-changes / auto-revert confirmation overlay
      Rectangle {
        visible: root.confirmPending
        anchors.fill: parent
        z: 30
        color: Commons.Color.menu.scrim

        MouseArea { anchors.fill: parent; onClicked: {} }

        BorderSurface {
          id: confirmCard
          width: Math.min(parent.width - Style.space(32), Style.space(400))
          height: confirmCol.implicitHeight + confirmCard.contentTopInset + confirmCard.contentBottomInset
          anchors.centerIn: parent
          radius: Math.max(Style.space(8), Style.cornerRadius)
          color: Commons.Color.menu.background
          borderSpec: Border.flat(Commons.Color.accent, Math.max(1, Style.normalBorderWidth))
          padding: Style.spacing.panelPadding

          Column {
            id: confirmCol
            x: confirmCard.contentLeftInset
            y: confirmCard.contentTopInset
            width: confirmCard.width - confirmCard.contentLeftInset - confirmCard.contentRightInset
            spacing: Style.spacing.md

            Text {
              width: parent.width
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              text: strings.t("display.confirmTitle")
              color: Commons.Color.menu.text
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              text: TaskbarModel.formatTemplate(
                strings.t("display.confirmCountdown"),
                Commons.I18n.formatNumber(root.confirmSeconds)
              )
              color: Commons.Color.menu.text
              opacity: 0.78
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }

            RowLayout {
              width: parent.width
              spacing: Style.spacing.sm

              Item { Layout.fillWidth: true }

              Button {
                text: TaskbarModel.sanitizePlainLabel(strings.t("display.revert"), 32)
                bordered: true
                focusable: false
                foreground: Commons.Color.menu.text
                background: Commons.Color.menu.background
                accent: Commons.Color.accent
                fontSize: Style.font.body
                onClicked: root.revertChanges(false)
              }

              Button {
                text: TaskbarModel.sanitizePlainLabel(strings.t("display.keepChanges"), 32)
                bordered: true
                selected: true
                focusable: false
                foreground: Commons.Color.menu.text
                background: Commons.Color.menu.background
                accent: Commons.Color.accent
                fontSize: Style.font.body
                onClicked: root.commitChanges()
              }
            }
          }
        }
      }
    }
  }
}
