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

  property string draggingKey: ""
  property var dragProjection: null
  property point dragStartPoint: Qt.point(0, 0)
  property int dragStartLogicalX: 0
  property int dragStartLogicalY: 0
  property int dragPreviewX: 0
  property int dragPreviewY: 0
  property bool dragSnappedX: false
  property bool dragSnappedY: false

  property bool confirmPending: false
  property int confirmSeconds: 15
  property var revertSnapshot: []

  onConfirmPendingChanged: {
    if (root.opened) {
      Qt.callLater(function() { if (root && root.opened && !resolutionDropdown.popupOpen && keyCatcher) keyCatcher.forceActiveFocus() })
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
  readonly property bool isDirty: TaskbarModel.monitorsStateChanged(root.draftMonitors, root.liveMonitors)

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

  readonly property var canvasProjection: TaskbarModel.computeCanvasProjection(
    root.draftMonitors,
    Math.max(320, canvasArea.width),
    Math.max(180, canvasArea.height),
    Style.space(28)
  )
  readonly property var activeProjection: (root.draggingKey !== "" && root.dragProjection)
    ? root.dragProjection
    : root.canvasProjection

  readonly property var selectedScaleOptions: {
    var m = root.selectedMonitor
    if (!m) return []
    return TaskbarModel.availableMonitorScales(m.width, m.height, m.scale)
  }

  readonly property string selectedCleanScale: {
    var m = root.selectedMonitor
    if (!m) return "1"
    return TaskbarModel.cleanMonitorScale(m.scale, m.width, m.height)
  }

  readonly property var selectedModeOptions: {
    var m = root.selectedMonitor
    if (!m) return []
    var avail = Array.isArray(m.availableModes) ? m.availableModes : []
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
    root.draggingKey = ""
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
    root.draggingKey = ""
    root.opened = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function cloneMonitorsList(src) {
    var out = []
    var list = Array.isArray(src) ? src : []
    for (var i = 0; i < list.length; i++) {
      var m = list[i]
      if (!m || typeof m !== "object") continue
      var copy = {}
      var keys = Object.keys(m)
      for (var k = 0; k < keys.length; k++) copy[keys[k]] = m[keys[k]]
      var sz = TaskbarModel.monitorLogicalSizeForSpec(copy)
      copy.logicalW = sz.w
      copy.logicalH = sz.h
      out.push(copy)
    }
    return out
  }

  function applyStatusPayload(raw) {
    try {
      var parsed = JSON.parse(String(raw || ""))
      if (!parsed || typeof parsed !== "object" || !Array.isArray(parsed.monitors)) return
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
    root.draggingKey = ""
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
      ? TaskbarModel.normalizeMonitorLayout(next, targetKey)
      : next
  }

  function setSelectedEnabled(enabled) {
    if (!root.selectedMonitor || !root.selectedCanToggleEnabled) return
    root.updateSelectedField(function(m) { m.enabled = !!enabled }, true)
  }

  function setSelectedScale(scaleVal) {
    var m = root.selectedMonitor
    if (!m) return
    var clean = Number(TaskbarModel.cleanMonitorScale(scaleVal, m.width, m.height))
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
      var parsed = TaskbarModel.parseMonitorMode(item.mode, item.width, item.height, item.refreshRate)
      item.width = parsed.width
      item.height = parsed.height
      item.refreshRate = parsed.hz
      item.scale = Number(TaskbarModel.cleanMonitorScale(item.scale, parsed.width, parsed.height))
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
    root.draggingKey = ""
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
    if (Array.isArray(root.revertSnapshot) && root.revertSnapshot.length > 0) {
      argList.push(JSON.stringify({ monitors: root.revertSnapshot }))
    }
    revertProc.command = argList
    revertProc.running = true
  }

  property bool closeOnRevert: false

  function triggerIdentify() {
    var list = []
    var src = root.draftMonitors || []
    for (var i = 0; i < src.length; i++) {
      var m = src[i]
      if (!m || m.enabled === false) continue
      list.push({
        name: String(m.name || ""),
        number: Number(m.number) || (i + 1),
        label: TaskbarModel.sanitizePlainLabel((m.name || "") + (m.model ? (" · " + m.model) : ""), 48)
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
      if (root.opened && !root.confirmPending && !root.busy && root.draggingKey === "") {
        root.loadStatus(false)
      }
    }
  }

  Connections {
    target: Quickshell
    function onScreensChanged() {
      if (root.opened && !root.confirmPending && !root.busy && root.draggingKey === "") {
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
          root.revertSnapshot = (res && Array.isArray(res.revert)) ? res.revert : []
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
      if (contentReady && root.opened && !resolutionDropdown.popupOpen) {
        Qt.callLater(function() { if (root && root.opened && !resolutionDropdown.popupOpen && keyCatcher) keyCatcher.forceActiveFocus() })
      }
    }
    onContentRevealedChanged: {
      if (contentRevealed && root.opened && !resolutionDropdown.popupOpen) {
        Qt.callLater(function() { if (root && root.opened && !resolutionDropdown.popupOpen && keyCatcher) keyCatcher.forceActiveFocus() })
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
          if (resolutionDropdown.popupOpen) return
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

        // Physical 2D monitor canvas (LTR spatial coordinates preserved regardless of UI RTL)
        Rectangle {
          id: canvasFrame
          width: parent.width
          height: Math.round(Math.max(Style.space(150), Math.min(Style.space(240), overlay.height * 0.32)))
          LayoutMirroring.enabled: false
          radius: Style.cornerRadius
          color: Util.alpha(Commons.Color.menu.text, 0.04)
          border.width: Math.max(1, Style.normalBorderWidth)
          border.color: Util.alpha(Commons.Color.menu.border, 0.7)
          clip: true

          Item {
            id: canvasArea
            anchors.fill: parent

            Repeater {
              model: root.draftMonitors

              delegate: Rectangle {
                id: monBox
                required property int index
                required property var modelData

                readonly property string monKey: String(modelData.matchKey || modelData.name || "")
                readonly property bool isDraggingMe: root.draggingKey === monKey
                readonly property bool isSelected: root.selectedKey === monKey
                readonly property bool isSnapping: isDraggingMe && (root.dragSnappedX || root.dragSnappedY)
                readonly property var proj: root.activeProjection
                readonly property real posX: isDraggingMe ? root.dragPreviewX : Number(modelData.x || 0)
                readonly property real posY: isDraggingMe ? root.dragPreviewY : Number(modelData.y || 0)
                readonly property real logW: Math.max(120, Number(modelData.logicalW || 1920))
                readonly property real logH: Math.max(120, Number(modelData.logicalH || 1080))

                visible: modelData.enabled !== false
                x: Math.round(proj.originX + posX * proj.scale)
                y: Math.round(proj.originY + posY * proj.scale)
                width: Math.max(Style.space(52), Math.round(logW * proj.scale))
                height: Math.max(Style.space(36), Math.round(logH * proj.scale))
                z: isDraggingMe ? 10 : (isSelected ? 5 : 1)
                radius: Math.max(Style.space(6), Style.cornerRadius)
                color: isSelected
                  ? Util.alpha(Commons.Color.accent, 0.22)
                  : (monMouse.containsMouse ? Style.hoverFill : Util.alpha(Commons.Color.menu.background, 0.92))
                border.width: (isSelected || isSnapping) ? 2 : 1
                border.color: (isSelected || isSnapping)
                  ? Commons.Color.accent
                  : Util.alpha(Commons.Color.menu.border, 0.9)

                Behavior on x {
                  enabled: root.draggingKey === ""
                  NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic }
                }
                Behavior on y {
                  enabled: root.draggingKey === ""
                  NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic }
                }
                Behavior on color { ColorAnimation { duration: Style.duration(90) } }

                Column {
                  anchors.centerIn: parent
                  width: Math.max(Style.space(28), monBox.width - Style.spacing.sm * 2)
                  spacing: Style.space(2)

                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    textFormat: Text.PlainText
                    text: Commons.I18n.formatNumber(modelData.number || (monBox.index + 1))
                    color: isSelected ? Commons.Color.accent : Commons.Color.menu.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.subtitle
                    font.bold: true
                  }

                  Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    visible: monBox.height >= Style.space(64)
                    text: TaskbarModel.sanitizePlainLabel(modelData.model || modelData.name || "", 32)
                    color: Commons.Color.menu.text
                    opacity: 0.85
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }

                  Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    visible: monBox.height >= Style.space(86)
                    text: Commons.I18n.formatNumber(Math.round(monBox.logW)) + " × " + Commons.I18n.formatNumber(Math.round(monBox.logH))
                    color: Commons.Color.menu.text
                    opacity: 0.62
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }
                }

                MouseArea {
                  id: monMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  enabled: !root.confirmPending && !root.busy
                  cursorShape: root.draggingKey === monBox.monKey ? Qt.ClosedHandCursor : Qt.OpenHandCursor

                  onPressed: function(mouse) {
                    root.selectedKey = monBox.monKey
                    if (root.enabledCount <= 1) return
                    var pt = monMouse.mapToItem(canvasArea, mouse.x, mouse.y)
                    root.dragProjection = root.canvasProjection
                    root.dragStartPoint = pt
                    root.dragStartLogicalX = Math.round(Number(monBox.modelData.x) || 0)
                    root.dragStartLogicalY = Math.round(Number(monBox.modelData.y) || 0)
                    root.dragPreviewX = root.dragStartLogicalX
                    root.dragPreviewY = root.dragStartLogicalY
                    root.dragSnappedX = false
                    root.dragSnappedY = false
                    root.draggingKey = monBox.monKey
                  }

                  onPositionChanged: function(mouse) {
                    if (!pressed || root.draggingKey !== monBox.monKey || !root.dragProjection) return
                    var pt = monMouse.mapToItem(canvasArea, mouse.x, mouse.y)
                    var sc = Math.max(0.01, root.dragProjection.scale)
                    var rawX = Math.round(root.dragStartLogicalX + (pt.x - root.dragStartPoint.x) / sc)
                    var rawY = Math.round(root.dragStartLogicalY + (pt.y - root.dragStartPoint.y) / sc)
                    var margin = Style.space(6)
                    var minLogX = Math.round((margin - root.dragProjection.originX) / sc)
                    var maxLogX = Math.round((Math.max(margin, canvasArea.width - monBox.width - margin) - root.dragProjection.originX) / sc)
                    var minLogY = Math.round((margin - root.dragProjection.originY) / sc)
                    var maxLogY = Math.round((Math.max(margin, canvasArea.height - monBox.height - margin) - root.dragProjection.originY) / sc)
                    rawX = Math.max(minLogX, Math.min(maxLogX, rawX))
                    rawY = Math.max(minLogY, Math.min(maxLogY, rawY))
                    var others = []
                    var all = root.draftMonitors || []
                    for (var i = 0; i < all.length; i++) {
                      var o = all[i]
                      if (!o || o.enabled === false || String(o.matchKey) === monBox.monKey) continue
                      others.push({ x: o.x, y: o.y, w: o.logicalW, h: o.logicalH, enabled: true })
                    }
                    var snapped = TaskbarModel.snapMonitorRect(
                      { x: rawX, y: rawY, w: monBox.logW, h: monBox.logH },
                      others,
                      72
                    )
                    root.dragPreviewX = snapped.x
                    root.dragPreviewY = snapped.y
                    root.dragSnappedX = snapped.snappedX
                    root.dragSnappedY = snapped.snappedY
                  }

                  function finishDrag() {
                    if (root.draggingKey !== monBox.monKey) return
                    var finalX = root.dragPreviewX
                    var finalY = root.dragPreviewY
                    root.draggingKey = ""
                    root.dragProjection = null
                    root.dragSnappedX = false
                    root.dragSnappedY = false

                    var next = root.cloneMonitorsList(root.draftMonitors)
                    for (var i = 0; i < next.length; i++) {
                      if (String(next[i].matchKey) === monBox.monKey) {
                        next[i].x = finalX
                        next[i].y = finalY
                        break
                      }
                    }
                    root.draftMonitors = TaskbarModel.normalizeMonitorLayout(next, monBox.monKey)
                  }

                  onReleased: finishDrag()
                  onCanceled: finishDrag()
                }
              }
            }

            // Disabled connected monitors bar at bottom-left of canvas
            Row {
              visible: root.disabledMonitors.length > 0
              anchors.left: parent.left
              anchors.bottom: parent.bottom
              anchors.margins: Style.spacing.sm
              spacing: Style.spacing.xs
              z: 20

              Repeater {
                model: root.disabledMonitors

                delegate: Rectangle {
                  id: disChip
                  required property var modelData
                  readonly property string monKey: String(modelData.matchKey || modelData.name || "")
                  readonly property bool isSelected: root.selectedKey === monKey

                  implicitWidth: disText.implicitWidth + Style.spacing.sm * 2
                  implicitHeight: disText.implicitHeight + Style.space(6)
                  radius: Style.cornerRadius
                  color: isSelected
                    ? Util.alpha(Commons.Color.accent, 0.18)
                    : Util.alpha(Commons.Color.menu.background, 0.9)
                  border.width: isSelected ? 2 : 1
                  border.color: isSelected ? Commons.Color.accent : Util.alpha(Commons.Color.menu.border, 0.7)

                  Text {
                    id: disText
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: Commons.I18n.formatNumber(modelData.number || 0) + " · "
                      + TaskbarModel.sanitizePlainLabel(modelData.name || "", 20) + " · "
                      + (modelData.clamshellLocked ? strings.t("display.clamshellTag") : strings.t("display.disabledTag"))
                    color: Commons.Color.menu.text
                    opacity: 0.85
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.selectedKey = disChip.monKey
                  }
                }
              }
            }
          }
        }

        // Selected monitor details & controls
        Rectangle {
          visible: !!root.selectedMonitor
          width: parent.width
          implicitHeight: inspectorCol.implicitHeight + Style.spacing.md * 2
          height: implicitHeight
          radius: Style.cornerRadius
          color: Util.alpha(Commons.Color.menu.text, 0.03)
          border.width: 1
          border.color: Util.alpha(Commons.Color.menu.border, 0.5)

          Column {
            id: inspectorCol
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
                        (root.selectedMonitor.name || "") + " — " + (root.selectedMonitor.model || ""),
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
                    ? strings.t("display.clamshellHint")
                    : ((root.selectedMonitor && root.selectedMonitor.enabled && root.enabledCount <= 1)
                        ? strings.t("display.lastDisplayHint")
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
                text: strings.t("display.enableDisplay")
                color: Commons.Color.menu.text
                opacity: root.selectedCanToggleEnabled ? 1.0 : 0.5
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }

              ToggleSwitch {
                checked: !!(root.selectedMonitor && root.selectedMonitor.enabled !== false)
                interactive: root.selectedCanToggleEnabled && !root.confirmPending && !root.busy
                opacity: root.selectedCanToggleEnabled ? 1.0 : 0.45
                trackHeight: 18
                foreground: Commons.Color.menu.text
                accent: Commons.Color.accent
                onToggled: root.setSelectedEnabled(!(root.selectedMonitor && root.selectedMonitor.enabled !== false))
              }
            }

            // Scale presets
            RowLayout {
              width: parent.width
              spacing: Style.spacing.md
              visible: !!(root.selectedMonitor && root.selectedMonitor.enabled !== false)

              Text {
                Layout.preferredWidth: Style.space(130)
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: Style.space(4)
                textFormat: Text.PlainText
                text: strings.t("display.scale")
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
                    onClicked: root.setSelectedScale(modelData.value)
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
                Layout.preferredWidth: Style.space(130)
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: Style.space(4)
                textFormat: Text.PlainText
                text: strings.t("display.orientation")
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
                    { value: "0", label: strings.t("display.rot0") },
                    { value: "1", label: strings.t("display.rot90") },
                    { value: "2", label: strings.t("display.rot180") },
                    { value: "3", label: strings.t("display.rot270") }
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
                    onClicked: root.setSelectedTransform(Number(modelData.value))
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
                Layout.preferredWidth: Style.space(130)
                textFormat: Text.PlainText
                text: strings.t("display.resolution")
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
                  if (!popupOpen && root.opened) {
                    Qt.callLater(function() { if (root && root.opened && !resolutionDropdown.popupOpen && keyCatcher) keyCatcher.forceActiveFocus() })
                  }
                }
                onChanged: function(val) { root.setSelectedMode(val) }
              }
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
