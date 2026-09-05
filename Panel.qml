import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "gravey.omackup"
  ipcTarget: "gravey.omackup"
  manageIpc: false

  property string screen: "overview"
  property string previousScreen: "overview"
  property int destIndex: 0
  property int destKindIndex: 0
  property int sourceIndex: 0
  property int excludeIndex: 0
  property int mountIndex: 0
  property int dirIndex: 0
  property int snapIndex: 0
  property int entryIndex: 0
  property bool cursorActive: false
  property bool formFocused: false

  property string destName: ""
  property string destDisplay: ""
  property string destSchedule: "*-*-* 03:00:00"
  property string destPassword: ""
  property string destPreCommand: ""
  property string destRateLimitText: "0"
  property string usbPath: ""
  property string nasHost: ""
  property string nasUser: ""
  property string nasPath: ""
  property string cloudBackend: "s3"
  property string cloudBucket: ""
  property string cloudPrefix: "omackup"
  property string cloudKey: ""
  property string cloudSecret: ""
  property string cloudRegion: "us-east-1"
  property string excludeDraft: ""
  property string highlightExclude: ""
  property string editingExclude: ""
  property string editingExcludeDraft: ""
  property var excludeEditField: null
  property bool excludesExpanded: false
  property string restoreDest: ""
  property string restoreSnapshot: "latest"
  property string pendingDest: ""
  property string passwordCopyStatus: ""
  property string editingDestKind: ""
  property string editingDestRepo: ""
  property bool sourcesHelpOpen: false
  property bool excludesHelpOpen: false
  property int backupBarTick: 0

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color barWarning: "#E6B422"
  property real backupHue: 0
  readonly property bool barShowPercent: omackup.backupActive
  readonly property string barIconText: {
    if (!omackup.backupActive) return "󰁯"
    if (omackup.backupCalculating) return "…"
    return Math.round(Math.max(0, Math.min(1, omackup.backupPercent)) * 100) + "%"
  }
  readonly property color barIconColor: {
    if (omackup.backupActive) {
      if (omackup.colorfulBackupBar) return Qt.hsla(backupHue, 0.92, 0.56, 1)
      return barForeground
    }
    if (omackup.hasFailedBackup) return urgent
    if (omackup.hasUnbackedUp) return barWarning
    return omackup.destinations.length ? barForeground : Qt.darker(barForeground, 1.55)
  }
  readonly property string barIconTooltip: {
    if (omackup.backupActive) return omackup.backupProgressLabel || "Backing up…"
    if (omackup.hasFailedBackup) return omackup.statusDetail || omackup.statusText || "Backup failed"
    if (omackup.hasUnbackedUp) {
      var n = Number(omackup.pendingFiles || 0)
      return n === 1 ? "1 file needs backing up" : (n + " files need backing up")
    }
    return omackup.statusText || "Omackup"
  }
  readonly property var sharedOmackup: bar && bar.shell ? bar.shell.serviceFor(root.moduleName) : null
  readonly property var omackup: sharedOmackup || localOmackup
  readonly property var selectedDest: {
    if (omackup.destinations.length === 0) return null
    return omackup.destinations[Math.max(0, Math.min(destIndex, omackup.destinations.length - 1))]
  }
  readonly property string heroDetail: {
    if (screen === "overview" || screen === "sources" || screen === "destEdit" || screen === "settings") return ""
    return screenTitle()
  }

  function showScreen(name) {
    previousScreen = screen
    screen = name
    formFocused = false
    cursorActive = name === "overview" || name === "destKind" || name === "destUsb"
      || name === "restoreSnaps" || name === "restoreBrowse" || name === "sources"
    sourcesHelpOpen = false
    excludesHelpOpen = false
    if (panelFlick) panelFlick.contentY = 0
    if (name === "passwordWarn") passwordCopyStatus = ""
    if (name === "destUsb") scanUsbMounts()
    if (name === "sources") {
      omackup.beginSourcesEdit()
      omackup.ensureHomeTree()
    } else {
      if (omackup.sourcesEditing) omackup.cancelSourcesEdit()
      if (name !== "destUsb") {
        highlightExclude = ""
        editingExclude = ""
        editingExcludeDraft = ""
        excludeEditField = null
        excludesExpanded = false
      }
    }
  }

  function copyPassword() {
    var password = String(omackup.lastPassword || "")
    if (!password) return
    if (!omackup.copySensitive(password)) return
    passwordCopyStatus = "Copied · not saved to clipboard history"
    passwordCopyClear.restart()
  }

  function revealExclude(pattern) {
    var value = String(pattern || "")
    excludesExpanded = true
    highlightExclude = value
    editingExclude = value
    editingExcludeDraft = value
  }

  function beginEditExclude(pattern) {
    var value = String(pattern || "")
    excludesExpanded = true
    highlightExclude = value
    editingExclude = value
    editingExcludeDraft = value
  }

  function cancelEditExclude() {
    editingExclude = ""
    editingExcludeDraft = ""
    excludeEditField = null
    formFocused = false
    if (keyCatcher) keyCatcher.forceActiveFocus()
  }

  function commitEditExclude(oldPattern, newPattern) {
    var previous = String(oldPattern || "")
    var next = String(newPattern || "").trim()
    editingExclude = ""
    editingExcludeDraft = ""
    excludeEditField = null
    formFocused = false
    if (keyCatcher) keyCatcher.forceActiveFocus()
    if (!previous) return
    if (!next) {
      if (highlightExclude === previous) highlightExclude = ""
      omackup.removeExclude(previous)
      return
    }
    if (next === previous) {
      highlightExclude = previous
      return
    }
    highlightExclude = next
    omackup.replaceExclude(previous, next)
  }

  function dismissExcludeEditor() {
    if (editingExclude === "") return
    commitEditExclude(editingExclude, editingExcludeDraft)
  }

  function scrollToItem(item) {
    if (!panelFlick || !item) return
    Qt.callLater(function() {
      var pos = item.mapToItem(panelFlick.contentItem, 0, 0)
      var top = pos.y - Style.space(16)
      var bottom = pos.y + item.height + Style.space(16)
      var viewTop = panelFlick.contentY
      var viewBottom = viewTop + panelFlick.height
      if (top < viewTop) panelFlick.contentY = Math.max(0, top)
      else if (bottom > viewBottom) panelFlick.contentY = Math.max(0, Math.min(bottom - panelFlick.height, panelFlick.contentHeight - panelFlick.height))
    })
  }

  function goBack() {
    if (sourcesHelpOpen || excludesHelpOpen) {
      sourcesHelpOpen = false
      excludesHelpOpen = false
      return
    }
    if (screen === "overview") {
      root.close()
      return
    }
    if (screen === "settings") {
      showScreen("overview")
      return
    }
    if (screen === "sources") {
      omackup.cancelSourcesEdit()
      showScreen("overview")
      return
    }
    if (screen === "restoreBrowse") {
      showScreen("restoreSnaps")
      return
    }
    if (screen === "restoreSnaps" || screen === "passwordWarn" || screen === "destEdit") {
      showScreen("overview")
      return
    }
    if (screen === "destUsb" || screen === "destNas" || screen === "destCloud") {
      showScreen("destKind")
      return
    }
    showScreen("overview")
  }

  function cancelSources() {
    omackup.cancelSourcesEdit()
    showScreen("overview")
  }

  function saveSources() {
    if (!omackup.sourcesDirty || omackup.sourcesSaving || omackup.busy) return
    omackup.saveSourcesEdit(function(ok) {
      if (ok) showScreen("overview")
    })
  }

  function resetDestForm() {
    destName = ""
    destDisplay = ""
    destSchedule = "*-*-* 03:00:00"
    destPassword = ""
    destPreCommand = ""
    destRateLimitText = "0"
    usbPath = omackup.mounts.length ? String(omackup.mounts[0].path || "") : ""
    nasHost = ""
    nasUser = ""
    nasPath = "/backups/omackup"
    cloudBackend = "s3"
    cloudBucket = ""
    cloudPrefix = "omackup"
    cloudKey = ""
    cloudSecret = ""
    cloudRegion = "us-east-1"
  }

  function startAddDest() {
    resetDestForm()
    destKindIndex = 0
    showScreen("destKind")
  }

  function editSelectedDest() {
    if (!selectedDest) return
    startEditDest(selectedDest)
  }

  function backupSelectedDest() {
    if (!selectedDest) return
    runBackup(selectedDest.name)
  }

  function restoreSelectedDest() {
    if (!selectedDest) return
    startRestore(selectedDest.name)
  }

  function openSelectedDestKind() {
    if (destKindIndex === 1) showScreen("destNas")
    else if (destKindIndex === 2) showScreen("destCloud")
    else showScreen("destUsb")
  }

  function sourceRowAt(index) {
    if (!omackup.treeRows || index < 0 || index >= omackup.treeRows.count) return null
    return omackup.treeRows.get(index)
  }

  function handleTextKey(t) {
    var key = String(t || "").toLowerCase()
    if (screen !== "overview") return
    if (key === "e") editSelectedDest()
    else if (key === "b") backupSelectedDest()
    else if (key === "r") restoreSelectedDest()
    else if (key === "s") showScreen("sources")
    else if (key === "d") startAddDest()
  }

  function destRateLimitCliArgs() {
    var parsed = Model.parseRateLimit(destRateLimitText)
    if (!parsed.ok) {
      omackup.lastError = parsed.error
      return null
    }
    return ["--rate-limit-kibs", String(parsed.kibs)]
  }

  function persistSettings(values) {
    var entry = { id: root.moduleName }
    var existing
    for (existing in root.settings) {
      if (existing !== "id") entry[existing] = root.settings[existing]
    }
    var key
    for (key in values) entry[key] = values[key]
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
    Qt.callLater(function() { omackup.evaluateNotifications() })
  }

  function selectUsbMount(path) {
    usbPath = String(path || "")
  }

  function syncUsbSelection(mountList) {
    var list = mountList || omackup.mounts || []
    if (!list.length) {
      usbPath = ""
      mountIndex = 0
      return
    }
    var i
    for (i = 0; i < list.length; i++) {
      if (String(list[i].path || "") === usbPath) {
        mountIndex = i
        return
      }
    }
    usbPath = String(list[0].path || "")
    mountIndex = 0
  }

  function scanUsbMounts() {
    omackup.refreshMounts(function(list) {
      syncUsbSelection(list)
    })
  }

  function runBackup(name) {
    var dest = name || (selectedDest ? selectedDest.name : "")
    if (!dest) return
    var list = omackup.destinations || []
    var i
    for (i = 0; i < list.length; i++) {
      if (String(list[i].name) === String(dest)) {
        destIndex = i
        break
      }
    }
    if (screen !== "overview") showScreen("overview")
    omackup.backupNow(dest)
  }

  function startEditDest(dest) {
    if (!dest) return
    destName = String(dest.name || "")
    destDisplay = String(dest.display_name || dest.name || "")
    destSchedule = String(dest.schedule || "")
    destPreCommand = String(dest.pre_command || "")
    destRateLimitText = Model.formatRateLimitField(dest.rate_limit_kibs)
    editingDestKind = String(dest.kind || "usb")
    editingDestRepo = String(dest.repository || "")
    showScreen("destEdit")
  }

  function saveDestEdit() {
    if (!destName || !editingDestKind || !editingDestRepo) {
      omackup.lastError = "Destination is incomplete"
      return
    }
    var display = String(destDisplay || destName).trim() || destName
    var args = [
      "dest-add", "--name", destName, "--kind", editingDestKind, "--repository", editingDestRepo,
      "--display-name", display, "--schedule", destSchedule, "--pre-command", destPreCommand
    ]
    var limitArgs = root.destRateLimitCliArgs()
    if (!limitArgs) return
    args = args.concat(limitArgs)
    omackup.addDestination(args, function() {
      showScreen("overview")
    })
  }

  function removeEditedDest() {
    if (!destName) return
    omackup.removeDestination(destName, function() {
      showScreen("overview")
    })
  }

  function startRestore(name) {
    restoreDest = name || (selectedDest ? selectedDest.name : "")
    restoreSnapshot = "latest"
    if (!restoreDest) return
    if (!omackup.destIsReachable(restoreDest)) {
      omackup.lastError = "Destination is not reachable"
      return
    }
    omackup.loadSnapshots(restoreDest, function(items) {
      snapIndex = 0
      showScreen("restoreSnaps")
    })
  }

  function openSnapshot(snap) {
    restoreSnapshot = String(snap && (snap.id || snap.full_id) || "latest")
    omackup.loadListing(restoreDest, restoreSnapshot, "/", function() {
      entryIndex = 0
      showScreen("restoreBrowse")
    })
  }

  function destIdFromLabel(fallback) {
    var display = String(destDisplay || "").trim()
    if (!display) {
      omackup.lastError = "Label is required"
      return ""
    }
    var base = Model.destNameFromLabel(display)
    if (!base) base = Model.destNameFromLabel(fallback) || "dest"
    var used = {}
    var list = omackup.destinations || []
    var i
    for (i = 0; i < list.length; i++) used[String(list[i].name || "")] = true
    if (!used[base]) return base
    var n = 2
    while (used[base + "-" + n]) n += 1
    return base + "-" + n
  }

  function saveUsbDest() {
    if (!usbPath) {
      omackup.lastError = "Choose a USB drive first"
      return
    }
    var name = destIdFromLabel("usb")
    if (!name) return
    var repo = usbPath.replace(/\/+$/, "") + "/omackup"
    finishDest("usb", name, repo, destDisplay.trim(), [])
  }

  function saveNasDest() {
    if (!nasHost || !nasUser) {
      omackup.lastError = "Host and user are required"
      return
    }
    var name = destIdFromLabel("nas")
    if (!name) return
    var remote = nasPath.indexOf("/") === 0 ? nasPath : "/" + nasPath
    var repo = "sftp:" + nasUser + "@" + nasHost + ":" + remote
    finishDest("nas", name, repo, destDisplay.trim(), [])
  }

  function saveCloudDest() {
    if (!cloudBucket) {
      omackup.lastError = "Bucket is required"
      return
    }
    var name = destIdFromLabel(cloudBackend)
    if (!name) return
    var prefix = cloudPrefix || "omackup"
    var repo = cloudBackend === "b2" ? ("b2:" + cloudBucket + ":" + prefix) : ("s3:s3.amazonaws.com/" + cloudBucket + "/" + prefix)
    var envPairs = []
    if (cloudBackend === "b2") {
      if (cloudKey) envPairs.push("B2_ACCOUNT_ID=" + cloudKey)
      if (cloudSecret) envPairs.push("B2_ACCOUNT_KEY=" + cloudSecret)
    } else {
      if (cloudKey) envPairs.push("AWS_ACCESS_KEY_ID=" + cloudKey)
      if (cloudSecret) envPairs.push("AWS_SECRET_ACCESS_KEY=" + cloudSecret)
      if (cloudRegion) envPairs.push("AWS_DEFAULT_REGION=" + cloudRegion)
    }
    finishDest("cloud", name, repo, destDisplay.trim(), envPairs)
  }

  function finishDest(kind, name, repo, display, envPairs) {
    pendingDest = name
    var args = [
      "dest-add", "--name", name, "--kind", kind, "--repository", repo,
      "--display-name", display, "--schedule", destSchedule, "--pre-command", destPreCommand
    ]
    var limitArgs = root.destRateLimitCliArgs()
    if (!limitArgs) return
    args = args.concat(limitArgs)
    if (destPassword) args.push("--password", destPassword)
    omackup.addDestination(args, function() {
      function afterKey() {
        omackup.setEnv(name, envPairs, function() {
          omackup.initDest(name, function() {
            if (!destPassword) omackup.showKey(name)
            showScreen("passwordWarn")
          })
        })
      }
      if (destPassword) afterKey()
      else omackup.setKey(name, "", afterKey)
    })
  }

  function activateCursor() {
    if (screen === "overview") {
      if (omackup.destinations.length === 0) startAddDest()
      else backupSelectedDest()
    } else if (screen === "destKind") {
      openSelectedDestKind()
    } else if (screen === "destUsb") {
      var mounts = omackup.mounts || []
      if (!mounts.length) return
      var mount = mounts[Math.max(0, Math.min(mountIndex, mounts.length - 1))]
      if (mount) selectUsbMount(mount.path)
    } else if (screen === "destEdit") {
      saveDestEdit()
    } else if (screen === "passwordWarn") {
      showScreen("overview")
    } else if (screen === "sources") {
      var row = sourceRowAt(sourceIndex)
      if (row && row.path) omackup.includeItem(row.path)
    } else if (screen === "restoreSnaps" && omackup.snapshots.length) {
      openSnapshot(omackup.snapshots[Math.max(0, Math.min(snapIndex, omackup.snapshots.length - 1))])
    } else if (screen === "restoreBrowse" && omackup.listing.length) {
      var entry = omackup.listing[Math.max(0, Math.min(entryIndex, omackup.listing.length - 1))]
      if (entry && entry.type === "dir") omackup.loadListing(restoreDest, restoreSnapshot, entry.path)
      else if (entry) omackup.restorePath(restoreDest, restoreSnapshot, entry.path)
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function syncService() {
    if (sharedOmackup) sharedOmackup.settings = root.settings
  }

  onSettingsChanged: syncService()
  onSharedOmackupChanged: {
    syncService()
    if (sharedOmackup && opened) sharedOmackup.setPanelOpen(true)
  }

  onOpenedChanged: {
    if (omackup && omackup.setPanelOpen) omackup.setPanelOpen(opened)
    if (opened && omackup) {
      cursorActive = screen === "overview" || screen === "destKind" || screen === "destUsb"
        || screen === "restoreSnaps" || screen === "restoreBrowse" || screen === "sources"
      formFocused = false
      if (screen === "overview" && panelFlick) panelFlick.contentY = 0
      omackup.refresh()
      if (screen === "sources") {
        omackup.ensureHomeTree()
        omackup.refreshSelectionSize()
      }
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }
  }

  Timer {
    id: backupBarAnimTimer
    interval: 75
    repeat: true
    running: omackup.backupActive
    onTriggered: root.backupBarTick++
  }

  NumberAnimation {
    id: backupRgbAnim
    target: root
    property: "backupHue"
    from: 0
    to: 1
    duration: 8000
    loops: Animation.Infinite
    running: omackup.backupActive && omackup.colorfulBackupBar
  }

  Service {
    id: localOmackup
    dormant: true
    settings: root.settings
  }

  Component.onCompleted: syncService()
  Component.onDestruction: {
    if (opened && sharedOmackup && sharedOmackup.setPanelOpen)
      sharedOmackup.setPanelOpen(false)
  }

  Timer {
    id: passwordCopyClear
    interval: 2500
    onTriggered: root.passwordCopyStatus = ""
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { omackup.refresh(); return "ok" }
    function status(): string { return omackup.statusText }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    slotSize: root.barShowPercent && !(bar && bar.vertical)
      ? Math.max(Style.bar.iconSlot, Math.round(Style.font.caption * 3.6))
      : Style.bar.iconSlot
    opticalSize: root.barShowPercent
      ? Math.max(Style.bar.iconCanvas, Math.round(Style.font.caption * 3.4))
      : Style.bar.iconCanvas
    tooltipText: root.barIconTooltip
    iconComponent: Component {
      Item {
        Text {
          anchors.centerIn: parent
          text: root.barIconText
          color: root.barIconColor
          font.family: root.fontFamily
          font.pixelSize: root.barShowPercent ? Style.font.caption : Style.space(12)
          font.bold: root.barShowPercent
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) omackup.refresh()
      else if (buttonCode === Qt.MiddleButton && root.selectedDest)
        root.runBackup(root.selectedDest.name)
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.formFocused
      onMoveRequested: function(dx, dy) {
        root.cursorActive = true
        if (root.screen === "overview") {
          if (omackup.destinations.length) destIndex = Math.max(0, Math.min(omackup.destinations.length - 1, destIndex + dy))
        } else if (root.screen === "destKind") {
          destKindIndex = Math.max(0, Math.min(2, destKindIndex + dy))
        } else if (root.screen === "destUsb" && omackup.mounts.length) {
          mountIndex = Math.max(0, Math.min(omackup.mounts.length - 1, mountIndex + dy))
          root.selectUsbMount(omackup.mounts[mountIndex].path)
        } else if (root.screen === "sources" && omackup.treeRows.count) {
          if (dy !== 0) {
            sourceIndex = Math.max(0, Math.min(omackup.treeRows.count - 1, sourceIndex + dy))
          } else if (dx !== 0) {
            var row = root.sourceRowAt(sourceIndex)
            if (row && row.type === "dir") {
              if (dx > 0 && !row.expanded) omackup.toggleExpand(row.path)
              else if (dx < 0 && row.expanded) omackup.toggleExpand(row.path)
            }
          }
        } else if (root.screen === "restoreSnaps" && omackup.snapshots.length) {
          snapIndex = Math.max(0, Math.min(omackup.snapshots.length - 1, snapIndex + dy))
        } else if (root.screen === "restoreBrowse" && omackup.listing.length) {
          entryIndex = Math.max(0, Math.min(omackup.listing.length - 1, entryIndex + dy))
        }
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.goBack()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { root.handleTextKey(t) }

      MouseArea {
        anchors.fill: parent
        enabled: root.editingExclude !== ""
        z: 1000
        propagateComposedEvents: true
        onPressed: function(mouse) {
          var field = root.excludeEditField
          if (field) {
            var local = mapToItem(field, mouse.x, mouse.y)
            if (local.x >= 0 && local.y >= 0 && local.x <= field.width && local.y <= field.height) {
              mouse.accepted = false
              return
            }
          }
          root.dismissExcludeEditor()
          mouse.accepted = false
        }
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "Omackup"
            meta: ""
            detail: root.heroDetail
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                text: "󰁯"
                color: omackup.alert ? root.urgent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
            trailingControl: root.screen === "sources" ? sourcesTopActions
              : (root.screen === "destEdit" ? destEditTopActions
              : (root.screen === "settings" ? settingsBack
              : (root.screen === "overview" ? settingsGear : null)))
          }

          Text {
            visible: omackup.lastError !== "" || (!omackup.backupActive && omackup.actionStatus !== "")
            width: parent.width
            text: {
              if (omackup.backupActive && omackup.lastError !== "") return omackup.lastError
              if (omackup.actionStatus !== "") return omackup.actionStatus
              return omackup.lastError
            }
            color: omackup.lastError !== "" && (omackup.actionStatus === "" || omackup.backupActive) ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Loader {
            width: parent.width
            sourceComponent: {
              if (root.screen === "sources") return sourcesPage
              if (root.screen === "settings") return settingsPage
              if (root.screen === "destKind") return destKindPage
              if (root.screen === "destUsb") return destUsbPage
              if (root.screen === "destNas") return destNasPage
              if (root.screen === "destCloud") return destCloudPage
              if (root.screen === "destEdit") return destEditPage
              if (root.screen === "passwordWarn") return passwordPage
              if (root.screen === "restoreSnaps") return restoreSnapsPage
              if (root.screen === "restoreBrowse") return restoreBrowsePage
              return overviewPage
            }
          }
        }
      }

      Item {
        anchors.fill: parent
        visible: (root.sourcesHelpOpen || root.excludesHelpOpen) && root.screen === "sources"
        z: 2000

        Rectangle {
          anchors.fill: parent
          color: Util.alpha(Color.background, 0.72)
          MouseArea {
            anchors.fill: parent
            onClicked: {
              root.sourcesHelpOpen = false
              root.excludesHelpOpen = false
            }
          }
        }

        BorderSurface {
          width: Math.min(parent.width - Style.space(24), Style.space(360))
          anchors.top: parent.top
          anchors.right: parent.right
          anchors.topMargin: Style.space(4)
          anchors.rightMargin: Style.space(4)
          color: Color.background
          borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
          radius: Style.cornerRadius
          implicitHeight: sourcesHelpCol.implicitHeight + Style.space(24)

          MouseArea {
            anchors.fill: parent
            onClicked: {}
          }

          Column {
            id: sourcesHelpCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(12)
            spacing: Style.space(10)

            Row {
              width: parent.width
              spacing: Style.space(6)

              Text {
                width: parent.width - Style.space(28)
                text: root.excludesHelpOpen ? "Exclusion patterns" : "How selection works"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                wrapMode: Text.WordWrap
                anchors.verticalCenter: parent.verticalCenter
              }

              Button {
                text: ""
                iconText: "×"
                tooltipText: "Close"
                foreground: root.foreground
                horizontalPadding: Style.space(4)
                verticalPadding: Style.space(2)
                iconSize: Style.font.body
                onClicked: {
                  root.sourcesHelpOpen = false
                  root.excludesHelpOpen = false
                }
              }
            }

            Text {
              width: parent.width
              text: root.excludesHelpOpen
                ? "Open this section with the chevron. Add glob rules like **/node_modules or *.iso to skip matching paths everywhere in your selection.\n\nClick a dashed red name in the tree to jump to the pattern that matched it.\n\nReset defaults restores the built-in pattern list."
                : "Left click includes a file or folder.\n\nLeft click again removes it from the selection.\n\nRight click excludes it. That item stays out until you left-click it again."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }
          }
        }
      }
    }
  }

  function screenTitle() {
    if (screen === "sources") return "Sources"
    if (screen === "settings") return "Settings"
    if (screen === "destKind") return "Add destination"
    if (screen === "destUsb") return "USB drive"
    if (screen === "destNas") return "NAS"
    if (screen === "destCloud") return "Cloud"
    if (screen === "destEdit") return "Edit destination"
    if (screen === "passwordWarn") return "Save this password"
    if (screen === "restoreSnaps") return "Restore"
    if (screen === "restoreBrowse") return "Browse"
    return ""
  }

  component BackupAsciiBar: Item {
    id: barRoot
    property bool calculating: false
    property bool disconnected: false
    property real progress: 0
    property int tick: 0
    property color tone: "#ffffff"
    property color alertTone: "#E23D48"
    property bool colorful: true

    readonly property int blockCount: Math.max(14, Math.min(32, Math.floor(Math.max(width, Style.space(200)) / Style.space(6))))
    readonly property int filledBlocks: {
      if (disconnected && progress <= 0) return 1
      var floor = disconnected ? 0 : 0.02
      return Math.max(0, Math.min(blockCount, Math.ceil(Math.max(floor, progress) * blockCount)))
    }
    readonly property color emptyColor: Util.alpha(tone, 0.14)
    readonly property real blockWidth: width / Math.max(1, blockCount)
    readonly property real hueStepPerBlock: 0.035
    readonly property bool blinkOn: Math.floor(tick / 5) % 2 === 0

    function blockColor(index) {
      if (disconnected) {
        if (index >= filledBlocks) return emptyColor
        return blinkOn ? alertTone : Util.alpha(alertTone, 0.22)
      }
      if (index >= filledBlocks) return emptyColor
      if (!colorful) return tone
      var waveOffset = (tick * 0.002) % 1.0
      var hue = (0.05 + waveOffset + index * hueStepPerBlock) % 1.0
      return Qt.hsla(hue, 0.88, 0.52, 1)
    }

    height: Style.space(12)
    width: parent ? parent.width : Style.space(200)

    Row {
      anchors.fill: parent
      spacing: 0

      Repeater {
        model: barRoot.blockCount
        Rectangle {
          required property int index
          width: barRoot.blockWidth
          height: parent.height
          color: barRoot.blockColor(index)
        }
      }
    }

    CalculatingBarAnim {
      anchors.fill: parent
      active: barRoot.calculating
      blockCount: barRoot.blockCount
      tone: barRoot.tone
      emptyColor: barRoot.emptyColor
      colorful: barRoot.colorful
    }
  }

  component OverviewPage: Column {
    width: parent.width
    spacing: Style.space(12)

    Row {
      width: parent.width
      spacing: Style.space(8)

      Button {
        text: "Sources"
        foreground: root.foreground
        onClicked: root.showScreen("sources")
      }
    }

    Text {
      width: parent.width
      text: "↑↓ dest   e edit   b backup   r restore   s sources   d add dest"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    PanelSeparator { foreground: root.foreground }

    Item {
      width: parent.width
      height: Math.max(destinationsHeader.implicitHeight, addDestBtn.implicitHeight)

      PanelSectionHeader {
        id: destinationsHeader
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: "DESTINATIONS"
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Button {
        id: addDestBtn
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: "Add destination"
        foreground: root.foreground
        onClicked: root.startAddDest()
      }
    }

    Text {
      visible: omackup.destinations.length === 0
      width: parent.width
      text: omackup.resticInstalled ? "No destinations yet. Add a USB drive, NAS, or cloud bucket." : "Install restic with omarchy pkg add restic"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      wrapMode: Text.WordWrap
    }

    Column {
      width: parent.width
      spacing: Style.space(6)
      Repeater {
        model: omackup.destinations
        CursorSurface {
          id: destRow
          required property var modelData
          required property int index
          readonly property bool isBackingUp: omackup.backupActive && omackup.backupDest === modelData.name
          readonly property bool showBackupSuccess: !destRow.isBackingUp
            && omackup.backupSuccessDest === String(modelData.name)
          width: parent.width
          hasCursor: root.cursorActive && root.screen === "overview" && root.destIndex === index
          foreground: root.foreground
          implicitHeight: (destRow.isBackingUp ? backupDestCol.implicitHeight : idleDestCol.implicitHeight)
            + Style.spacing.rowPaddingX

          onHasCursorChanged: if (hasCursor) root.scrollToItem(destRow)

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: { root.cursorActive = true; root.destIndex = index }
            onClicked: { root.cursorActive = true; root.destIndex = index }
          }

          Column {
            id: idleDestCol
            visible: !destRow.isBackingUp
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            spacing: Style.space(6)

            Row {
              width: parent.width
              spacing: Style.space(10)

              Row {
                width: Math.max(80, parent.width - idleDestActionSlot.implicitWidth - Style.space(10))
                spacing: Style.space(8)

                Text {
                  text: Model.destGlyph(modelData.kind)
                  color: modelData.failed || modelData.overdue ? root.urgent : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.icon
                  anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                  width: Math.max(40, parent.width - Style.space(28))
                  spacing: Style.space(1)
                  anchors.verticalCenter: parent.verticalCenter

                  Row {
                    width: parent.width
                    spacing: Style.space(6)

                    Rectangle {
                      width: Style.space(8)
                      height: Style.space(8)
                      radius: width / 2
                      color: modelData.reachable === true ? "#3DDC84" : root.urgent
                      border.width: 1
                      border.color: Util.alpha(root.foreground, 0.25)
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                      width: Math.max(20, parent.width - Style.space(14))
                      text: modelData.display_name || modelData.name
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      elide: Text.ElideRight
                      anchors.verticalCenter: parent.verticalCenter
                    }
                  }
                  Text {
                    width: parent.width
                    text: modelData.reachable === false
                      ? (modelData.reachable_error || "Not reachable")
                      : Model.destMeta(modelData, omackup.use24HourTime)
                    color: modelData.reachable === false || modelData.failed || modelData.overdue ? root.urgent : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                  Text {
                    visible: Number(modelData.pending_files || 0) > 0 && modelData.reachable !== false
                    width: parent.width
                    text: Model.pendingLabel(modelData)
                    color: root.urgent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                  Text {
                    width: parent.width
                    text: Model.scheduleLabel(modelData.schedule)
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                  Text {
                    visible: Number(modelData.rate_limit_kibs || 0) > 0
                    width: parent.width
                    text: "Capped at " + Model.formatRateLimit(modelData.rate_limit_kibs)
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }
              }

              Item {
                id: idleDestActionSlot
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: destRow.showBackupSuccess ? backupSuccessLabel.implicitWidth : idleDestActions.implicitWidth
                implicitHeight: destRow.showBackupSuccess ? backupSuccessLabel.implicitHeight : idleDestActions.implicitHeight

                Row {
                  id: idleDestActions
                  visible: !destRow.showBackupSuccess
                  spacing: Style.space(4)
                  anchors.verticalCenter: parent.verticalCenter

                  Column {
                    id: destSecondaryActions
                    spacing: Style.space(4)
                    anchors.verticalCenter: parent.verticalCenter

                    Button {
                      width: Math.max(implicitWidth, idleEditBtn.implicitWidth)
                      text: "Restore"
                      foreground: root.foreground
                      fontSize: Style.font.caption
                      horizontalPadding: Style.space(8)
                      verticalPadding: Style.space(4)
                      enabled: !omackup.busy && modelData.reachable === true
                      opacity: enabled ? 1 : 0.4
                      onClicked: root.startRestore(modelData.name)
                    }

                    Button {
                      id: idleEditBtn
                      width: Math.max(implicitWidth, parent.children[0].implicitWidth)
                      text: "Edit"
                      foreground: root.foreground
                      fontSize: Style.font.caption
                      horizontalPadding: Style.space(8)
                      verticalPadding: Style.space(4)
                      enabled: !omackup.busy
                      onClicked: root.startEditDest(modelData)
                    }
                  }

                  Button {
                    text: "Backup"
                    foreground: root.foreground
                    bordered: true
                    fontSize: Style.font.body
                    horizontalPadding: Style.space(14)
                    verticalPadding: Style.space(8)
                    height: destSecondaryActions.implicitHeight
                    anchors.verticalCenter: parent.verticalCenter
                    enabled: !omackup.busy
                    opacity: enabled ? 1 : 0.4
                    onClicked: root.runBackup(modelData.name)
                  }
                }

                Text {
                  id: backupSuccessLabel
                  visible: destRow.showBackupSuccess
                  text: "Backup Successful"
                  color: "#3DDC84"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                  font.bold: true
                  anchors.verticalCenter: parent.verticalCenter
                }

                MouseArea {
                  visible: destRow.showBackupSuccess
                  anchors.fill: backupSuccessLabel
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: omackup.clearBackupSuccess()
                }
              }
            }
          }

          Column {
            id: backupDestCol
            visible: destRow.isBackingUp
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            spacing: Style.space(4)

            Row {
              width: parent.width
              spacing: Style.space(8)

              Text {
                text: Model.destGlyph(modelData.kind)
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.icon
                anchors.verticalCenter: parent.verticalCenter
              }

              Row {
                width: Math.max(40, parent.width - cancelBtn.implicitWidth - Style.space(36))
                spacing: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                  width: Style.space(8)
                  height: Style.space(8)
                  radius: width / 2
                  color: omackup.backupDisconnected || modelData.reachable !== true ? root.urgent : "#3DDC84"
                  border.width: 1
                  border.color: Util.alpha(root.foreground, 0.25)
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  width: Math.max(20, parent.width - Style.space(14))
                  text: modelData.display_name || modelData.name
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              Button {
                id: cancelBtn
                text: "Cancel"
                foreground: root.foreground
                bordered: true
                fontSize: Style.font.caption
                horizontalPadding: Style.space(10)
                verticalPadding: Style.space(4)
                anchors.verticalCenter: parent.verticalCenter
                onClicked: omackup.cancelBackup()
              }
            }

            Text {
              width: parent.width
              text: omackup.backupStatsLine
              color: omackup.backupDisconnected ? root.urgent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }

            BackupAsciiBar {
              width: parent.width
              calculating: omackup.backupCalculating
              disconnected: omackup.backupDisconnected
              progress: omackup.backupPercent
              tick: root.backupBarTick
              tone: root.foreground
              alertTone: root.urgent
              colorful: omackup.colorfulBackupBar
            }
          }
        }
      }
    }
  }

  component SourcesPage: Column {
    width: parent.width
    spacing: Style.space(12)

    Row {
      width: parent.width
      spacing: Style.space(6)

      Text {
        text: omackup.selectionSizeText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        wrapMode: Text.NoWrap
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        visible: omackup.selectionSizeLoading
        text: omackup.selectionSizeSpinner
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Text {
      visible: omackup.treeLoading && omackup.treeRows.count === 0
      width: parent.width
      text: "Reading your home folder…"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    Button {
      visible: !omackup.treeLoading && omackup.treeRows.count === 0
      text: "Load home folder"
      foreground: root.foreground
      onClicked: omackup.ensureHomeTree()
    }

    Item {
      width: parent.width
      height: Math.max(treeColumn.implicitHeight, treeRefreshBtn.implicitHeight)

      Column {
        id: treeColumn
        width: parent.width
        spacing: 0

        Repeater {
          model: omackup.treeRows
          TreeRow {
            required property int index
            required property string path
            required property string name
            required property string type
            required property int depth
            required property bool expanded
            required property bool hasChildren
            width: parent.width
            hasCursor: root.cursorActive && root.screen === "sources" && root.sourceIndex === index
            rowIndex: index
            node: ({
              path: path,
              name: name,
              type: type,
              depth: depth,
              expanded: expanded,
              hasChildren: hasChildren
            })
          }
        }
      }

      Row {
        anchors.top: parent.top
        anchors.right: parent.right
        z: 1
        spacing: Style.space(2)

        Button {
          text: ""
          iconText: "?"
          tooltipText: "How selection works"
          foreground: root.foreground
          horizontalPadding: Style.space(4)
          verticalPadding: Style.space(2)
          iconSize: Style.font.body
          selected: root.sourcesHelpOpen
          enabled: !omackup.sourcesSaving
          onClicked: {
            root.excludesHelpOpen = false
            root.sourcesHelpOpen = !root.sourcesHelpOpen
          }
        }

        Button {
          id: treeRefreshBtn
          text: ""
          iconText: "󰑐"
          iconSpinning: omackup.treeLoading
          tooltipText: "Reload the file tree"
          foreground: root.foreground
          horizontalPadding: Style.space(4)
          verticalPadding: Style.space(2)
          iconSize: Style.font.body
          enabled: !omackup.treeLoading && !omackup.sourcesSaving
          onClicked: omackup.refreshHomeTree()
        }
      }
    }

    PanelSeparator { foreground: root.foreground }

    Item {
      id: excludesHeader
      width: parent.width
      height: Math.max(Style.space(28), excludesHelpBtn.implicitHeight)

      CursorSurface {
        anchors.left: parent.left
        anchors.right: excludesHelpBtn.left
        anchors.rightMargin: Style.space(4)
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        foreground: root.foreground

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            root.excludesExpanded = !root.excludesExpanded
            if (!root.excludesExpanded) root.cancelEditExclude()
          }
        }

        Row {
          anchors.fill: parent
          anchors.leftMargin: Style.space(4)
          spacing: Style.space(6)

          Text {
            text: root.excludesExpanded ? "󰅀" : "󰅂"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            anchors.verticalCenter: parent.verticalCenter
          }

          PanelSectionHeader {
            text: "EXCLUSION PATTERNS"
            foreground: root.foreground
            fontFamily: root.fontFamily
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            visible: (omackup.draftExcludes || []).length > 0
            text: String((omackup.draftExcludes || []).length)
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            anchors.verticalCenter: parent.verticalCenter
          }
        }
      }

      Button {
        id: excludesHelpBtn
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: ""
        iconText: "?"
        tooltipText: "About exclusion patterns"
        foreground: root.foreground
        horizontalPadding: Style.space(4)
        verticalPadding: Style.space(2)
        iconSize: Style.font.body
        selected: root.excludesHelpOpen
        onClicked: {
          root.sourcesHelpOpen = false
          root.excludesHelpOpen = !root.excludesHelpOpen
        }
      }
    }

    Column {
      visible: root.excludesExpanded
      width: parent.width
      spacing: Style.space(12)

      Column {
        width: parent.width
        spacing: 0

        Repeater {
          model: omackup.draftExcludes
          ExcludeRuleRow {
            required property var modelData
            width: parent.width
            pattern: String(modelData || "")
          }
        }
      }

      TextField {
        width: parent.width
        placeholderText: "Pattern, e.g. **/node_modules"
        text: root.excludeDraft
        foreground: root.foreground
        enabled: !omackup.sourcesSaving
        onTextChanged: root.excludeDraft = text
        onActiveFocusChanged: root.formFocused = activeFocus
        onAccepted: {
          if (root.excludeDraft) omackup.addExclude(root.excludeDraft)
          root.excludeDraft = ""
          text = ""
        }
      }

      Row {
        spacing: Style.space(8)
        Button {
          text: "Add pattern"
          foreground: root.foreground
          enabled: root.excludeDraft !== "" && !omackup.sourcesSaving
          onClicked: {
            omackup.addExclude(root.excludeDraft)
            root.excludeDraft = ""
          }
        }
        Button {
          text: "Reset defaults"
          foreground: root.foreground
          enabled: !omackup.sourcesSaving
          onClicked: omackup.resetExcludes()
        }
      }
    }
  }

  component ExcludeRuleRow: CursorSurface {
    id: excludeRow
    property string pattern: ""
    property string draft: pattern
    readonly property bool focused: root.highlightExclude === pattern && pattern !== ""
    readonly property bool editing: root.editingExclude === pattern && pattern !== ""

    implicitHeight: editing ? Math.max(Style.space(28), editField.implicitHeight) : Style.space(24)
    foreground: root.foreground
    current: focused || editing

    onFocusedChanged: if (focused) root.scrollToItem(excludeRow)
    onEditingChanged: {
      if (editing) {
        draft = pattern
        root.editingExcludeDraft = pattern
        root.excludeEditField = editField
        Qt.callLater(function() {
          editField.forceActiveFocus()
          editField.selectAll()
          root.scrollToItem(excludeRow)
        })
      } else if (root.excludeEditField === editField) {
        root.excludeEditField = null
      }
    }
    onPatternChanged: if (!editing) draft = pattern

    Row {
      anchors.fill: parent
      anchors.leftMargin: Style.space(4)
      anchors.rightMargin: Style.space(2)
      spacing: Style.space(6)

      Text {
        visible: !excludeRow.editing
        width: Math.max(20, parent.width - Style.space(28))
        text: excludeRow.pattern
        color: excludeRow.focused ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
        anchors.verticalCenter: parent.verticalCenter

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.beginEditExclude(excludeRow.pattern)
        }
      }

      TextField {
        id: editField
        visible: excludeRow.editing
        width: Math.max(20, parent.width - Style.space(28))
        text: excludeRow.draft
        foreground: root.foreground
        font.pixelSize: Style.font.bodySmall
        horizontalPadding: Style.space(6)
        verticalPadding: Style.space(2)
        anchors.verticalCenter: parent.verticalCenter
        onTextChanged: {
          excludeRow.draft = text
          if (excludeRow.editing) root.editingExcludeDraft = text
        }
        onActiveFocusChanged: {
          root.formFocused = activeFocus
          if (!activeFocus && excludeRow.editing) {
            Qt.callLater(function() {
              if (root.editingExclude === excludeRow.pattern && !editField.activeFocus)
                root.commitEditExclude(excludeRow.pattern, excludeRow.draft)
            })
          }
        }
        onAccepted: root.commitEditExclude(excludeRow.pattern, excludeRow.draft)
        Keys.onEscapePressed: root.cancelEditExclude()
      }

      Button {
        text: ""
        iconText: "×"
        tooltipText: "Remove exclude"
        foreground: root.foreground
        horizontalPadding: Style.space(4)
        verticalPadding: Style.space(2)
        iconSize: Style.font.body
        onClicked: {
          if (root.editingExclude === excludeRow.pattern) root.cancelEditExclude()
          if (root.highlightExclude === excludeRow.pattern) root.highlightExclude = ""
          omackup.removeExclude(excludeRow.pattern)
        }
      }
    }
  }

  component TreeRow: CursorSurface {
    id: treeRow
    property var node: ({})
    property int rowIndex: 0
    readonly property string mark: Model.itemMark(node.path, omackup.draftSources, omackup.draftExcludePaths, omackup.homePath)
    readonly property string excludePattern: Model.matchingExcludePattern(node.path, node.type, omackup.draftExcludes, omackup.homePath)
    readonly property bool isDir: node.type === "dir"
    readonly property bool excluded: mark === "excluded"
    readonly property bool patternExcluded: !excluded && excludePattern !== ""
    readonly property bool included: mark === "included"
    readonly property color includeGreen: "#3DDC84"
    readonly property color excludeRed: root.urgent
    readonly property bool hidden: String(node.name || "").charAt(0) === "."
    readonly property color hiddenGrey: Qt.darker(root.foreground, 1.7)
    readonly property color labelColor: hidden ? hiddenGrey : ((excluded || patternExcluded) ? excludeRed : root.foreground)

    width: parent ? parent.width : implicitWidth
    foreground: root.foreground
    implicitHeight: Style.space(30)

    onHasCursorChanged: if (hasCursor) root.scrollToItem(treeRow)

    Row {
      anchors.fill: parent
      anchors.leftMargin: Style.space(4) + Style.space(14) * Number(treeRow.node.depth || 0)
      anchors.rightMargin: Style.space(28)
      spacing: Style.space(6)

      BorderSurface {
        id: checkbox
        width: Style.space(16)
        height: Style.space(16)
        radius: Math.max(2, Style.cornerRadius / 2)
        anchors.verticalCenter: parent.verticalCenter
        color: "transparent"
        borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)

        Text {
          anchors.centerIn: parent
          visible: treeRow.excluded || treeRow.included || treeRow.mark === "partial"
          text: treeRow.excluded ? "×" : (treeRow.included ? "✓" : "−")
          color: treeRow.excluded ? treeRow.excludeRed : treeRow.includeGreen
          font.family: root.fontFamily
          font.pixelSize: Math.round(checkbox.height * 0.85)
          font.bold: true
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton) {
              omackup.excludeItem(treeRow.node.path)
              return
            }
            omackup.includeItem(treeRow.node.path)
          }
        }
      }

      Item {
        width: Style.space(18)
        height: parent.height
        visible: treeRow.isDir

        Text {
          anchors.centerIn: parent
          visible: treeRow.node.hasChildren !== false
          text: treeRow.node.expanded ? "󰅀" : "󰅂"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        MouseArea {
          anchors.fill: parent
          enabled: treeRow.node.hasChildren !== false
          cursorShape: Qt.PointingHandCursor
          onClicked: omackup.toggleExpand(treeRow.node.path)
        }
      }

      Item {
        width: treeRow.isDir ? 0 : Style.space(18)
        height: 1
      }

      Item {
        id: labelBox
        width: Math.max(20, parent.width - Style.space(90))
        height: parent.height

        Row {
          id: nameRow
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(6)

          Text {
            text: Model.entryGlyph(treeRow.node)
            color: treeRow.labelColor
            font.family: root.fontFamily
            font.pixelSize: Style.font.icon
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            width: Math.min(implicitWidth, Math.max(20, labelBox.width - Style.space(22)))
            text: treeRow.node.name || ""
            color: treeRow.labelColor
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.strikeout: treeRow.excluded
            elide: Text.ElideRight
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        Canvas {
          id: dashCross
          x: 0
          y: Math.round((parent.height - nameRow.implicitHeight) / 2)
          width: Math.min(parent.width, nameRow.implicitWidth)
          height: Math.max(1, nameRow.implicitHeight)
          visible: treeRow.patternExcluded
          onWidthChanged: requestPaint()
          onHeightChanged: requestPaint()
          onVisibleChanged: requestPaint()
          onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            if (width < 2 || height < 2) return
            ctx.strokeStyle = treeRow.excludeRed
            ctx.lineWidth = 1.25
            ctx.lineCap = "round"
            function dashLine(x1, y1, x2, y2) {
              var dx = x2 - x1
              var dy = y2 - y1
              var len = Math.sqrt(dx * dx + dy * dy)
              if (len <= 0) return
              var ux = dx / len
              var uy = dy / len
              var pos = 0
              var draw = true
              ctx.beginPath()
              while (pos < len) {
                var next = Math.min(len, pos + (draw ? 3.5 : 2.5))
                if (draw) {
                  ctx.moveTo(x1 + ux * pos, y1 + uy * pos)
                  ctx.lineTo(x1 + ux * next, y1 + uy * next)
                }
                pos = next
                draw = !draw
              }
              ctx.stroke()
            }
            dashLine(0.5, 1.5, width - 0.5, height - 1.5)
            dashLine(width - 0.5, 1.5, 0.5, height - 1.5)
          }
        }
      }
    }

    MouseArea {
      id: labelMouse
      anchors.fill: parent
      anchors.leftMargin: Style.space(4) + Style.space(14) * Number(treeRow.node.depth || 0) + Style.space(40)
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onEntered: { root.cursorActive = true; root.sourceIndex = treeRow.rowIndex }
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) {
          omackup.excludeItem(treeRow.node.path)
          return
        }
        if (treeRow.patternExcluded) {
          root.revealExclude(treeRow.excludePattern)
          return
        }
        omackup.includeItem(treeRow.node.path)
      }

      PanelToolTip {
        visible: treeRow.patternExcluded && labelMouse.containsMouse
        text: "Excluded because it matches " + treeRow.excludePattern + "\nClick to view exclusion rule"
      }
    }
  }

  component SettingsPage: Column {
    width: parent.width
    spacing: Style.space(12)

    PanelSectionHeader {
      text: "APPEARANCE"
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    Toggle {
      width: parent.width
      label: "RGB loading bar"
      description: "Turn it off for a boring loading bar."
      foreground: root.foreground
      accent: Color.accent
      fontFamily: root.fontFamily
      checked: omackup.colorfulBackupBar
      onClicked: root.persistSettings({ colorfulBackupBar: !omackup.colorfulBackupBar })
    }

    Dropdown {
      width: parent.width
      label: "Time format"
      value: omackup.use24HourTime ? "24" : "12"
      options: Model.timeFormatOptions()
      foreground: root.foreground
      onChanged: function(value) {
        root.persistSettings({ use24HourTime: value === "24" })
      }
    }

    PanelSectionHeader {
      text: "WHEN TO NOTIFY"
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    Toggle {
      width: parent.width
      label: "Any unbacked-up file"
      description: "As soon as a selected file is new or changed."
      foreground: root.foreground
      accent: Color.accent
      fontFamily: root.fontFamily
      checked: omackup.notifyOnUnbackedUp
      onClicked: root.persistSettings({ notifyOnUnbackedUp: !omackup.notifyOnUnbackedUp })
    }

    Toggle {
      width: parent.width
      label: "Unbacked-up files older than…"
      description: "After changes have sat without a backup."
      foreground: root.foreground
      accent: Color.accent
      fontFamily: root.fontFamily
      checked: omackup.notifyOnStaleUnbackedUp
      onClicked: root.persistSettings({ notifyOnStaleUnbackedUp: !omackup.notifyOnStaleUnbackedUp })
    }

    Dropdown {
      visible: omackup.notifyOnStaleUnbackedUp
      width: parent.width
      label: "Notify after"
      value: String(omackup.staleUnbackedUpHours)
      options: Model.notifyAgeOptions()
      foreground: root.foreground
      onChanged: function(value) {
        var hours = parseInt(value, 10)
        if (!isFinite(hours) || hours <= 0) hours = 24
        root.persistSettings({ staleUnbackedUpHours: hours })
      }
    }

    Toggle {
      width: parent.width
      label: "Missed automatic backup"
      description: "When a scheduled backup did not run."
      foreground: root.foreground
      accent: Color.accent
      fontFamily: root.fontFamily
      checked: omackup.notifyOnMissedBackup
      onClicked: root.persistSettings({ notifyOnMissedBackup: !omackup.notifyOnMissedBackup })
    }
  }

  component DestEditPage: Column {
    width: parent.width
    spacing: Style.space(12)

    Text {
      width: parent.width
      text: Model.destGlyph(root.editingDestKind) + "  " + (root.destName || "")
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    LabeledField {
      label: "Label"
      placeholder: "Friendly name"
      text: root.destDisplay
      onChanged: root.destDisplay = value
    }

    Text {
      width: parent.width
      text: "Repository"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    Text {
      width: parent.width
      text: root.editingDestRepo || "(none)"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.WrapAnywhere
    }

    Dropdown {
      width: parent.width
      label: "Schedule"
      value: root.destSchedule
      options: Model.scheduleOptions()
      foreground: root.foreground
      onChanged: function(value) { root.destSchedule = value }
    }

    LabeledField {
      label: "Pre-command (optional)"
      placeholder: "Command to run before backup"
      text: root.destPreCommand
      onChanged: root.destPreCommand = value
    }

    LabeledField {
      label: "Rate limit (0 is unlimited)"
      placeholder: "10mb/s"
      text: root.destRateLimitText
      onChanged: root.destRateLimitText = value
    }

    PanelSeparator { foreground: root.foreground }

    Button {
      text: "Remove destination"
      foreground: root.urgent
      enabled: !omackup.busy
      onClicked: root.removeEditedDest()
    }
  }

  component DestKindPage: Column {
    width: parent.width
    spacing: Style.space(10)

    Button {
      text: "Back"
      foreground: root.foreground
      onClicked: root.showScreen("overview")
    }

    Text {
      width: parent.width
      text: "Where should the incremental backup live?"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      wrapMode: Text.WordWrap
    }

    Button {
      width: parent.width
      text: "USB / local drive"
      iconText: "󰕓"
      foreground: root.foreground
      leftAlign: true
      hasCursor: root.cursorActive && root.destKindIndex === 0
      selected: root.destKindIndex === 0
      onClicked: { root.destKindIndex = 0; root.showScreen("destUsb") }
    }
    Button {
      width: parent.width
      text: "NAS over SSH / SFTP"
      iconText: "󰒍"
      foreground: root.foreground
      leftAlign: true
      hasCursor: root.cursorActive && root.destKindIndex === 1
      selected: root.destKindIndex === 1
      onClicked: { root.destKindIndex = 1; root.showScreen("destNas") }
    }
    Button {
      width: parent.width
      text: "Cloud (S3 or Backblaze B2)"
      iconText: "󰅟"
      foreground: root.foreground
      leftAlign: true
      hasCursor: root.cursorActive && root.destKindIndex === 2
      selected: root.destKindIndex === 2
      onClicked: { root.destKindIndex = 2; root.showScreen("destCloud") }
    }
  }

  component DestUsbPage: Column {
    width: parent.width
    spacing: Style.space(10)

    Row {
      spacing: Style.space(8)

      Button {
        text: "Back"
        foreground: root.foreground
        onClicked: root.showScreen("destKind")
      }

      Button {
        text: omackup.mountsLoading ? "Scanning…" : "Rescan"
        iconText: "󰑐"
        iconSpinning: omackup.mountsLoading
        tooltipText: "Scan for attached USB drives"
        foreground: root.foreground
        enabled: !omackup.mountsLoading
        onClicked: root.scanUsbMounts()
      }
    }

    Text {
      width: parent.width
      text: "Attached USB and removable drives"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    Text {
      visible: omackup.mountsLoading && omackup.mounts.length === 0
      width: parent.width
      text: "Scanning for USB drives…"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      wrapMode: Text.WordWrap
    }

    Text {
      visible: !omackup.mountsLoading && omackup.mounts.length === 0
      width: parent.width
      text: "No USB drives found. Plug one in and mount it, then hit Rescan."
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      wrapMode: Text.WordWrap
    }

    Repeater {
      model: omackup.mounts
      Button {
        required property var modelData
        required property int index
        width: parent.width
        text: {
          var label = String(modelData.name || modelData.path || "Drive")
          var bits = []
          if (modelData.size) bits.push(String(modelData.size))
          if (modelData.fstype && modelData.fstype !== "unknown") bits.push(String(modelData.fstype))
          var meta = bits.length ? " · " + bits.join(" · ") : ""
          return label + meta + "\n" + String(modelData.path || "")
        }
        foreground: root.foreground
        selected: root.usbPath === modelData.path
        hasCursor: root.cursorActive && root.mountIndex === index
        leftAlign: true
        onClicked: {
          root.mountIndex = index
          root.selectUsbMount(modelData.path)
        }
      }
    }

    DestCommonFields {}

    Button {
      text: omackup.busy ? "Working…" : "Create USB destination"
      foreground: root.foreground
      enabled: !omackup.busy && root.usbPath !== "" && String(root.destDisplay || "").trim() !== ""
      onClicked: root.saveUsbDest()
    }
  }

  component DestNasPage: Column {
    width: parent.width
    spacing: Style.space(10)

    Button {
      text: "Back"
      foreground: root.foreground
      onClicked: root.showScreen("destKind")
    }

    LabeledField {
      label: "Host"
      placeholder: "nas.local"
      text: root.nasHost
      onChanged: root.nasHost = value
    }
    LabeledField {
      label: "User"
      placeholder: "backup"
      text: root.nasUser
      onChanged: root.nasUser = value
    }
    LabeledField {
      label: "Path"
      placeholder: "/volume1/backups/omackup"
      text: root.nasPath
      onChanged: root.nasPath = value
    }
    LabeledField {
      label: "Wake command (optional)"
      placeholder: "systemctl --user start wake-nas"
      text: root.destPreCommand
      onChanged: root.destPreCommand = value
    }

    DestCommonFields {}

    Button {
      text: omackup.busy ? "Working…" : "Create NAS destination"
      foreground: root.foreground
      enabled: !omackup.busy && root.nasHost !== "" && root.nasUser !== "" && String(root.destDisplay || "").trim() !== ""
      onClicked: root.saveNasDest()
    }
  }

  component DestCloudPage: Column {
    width: parent.width
    spacing: Style.space(10)

    Button {
      text: "Back"
      foreground: root.foreground
      onClicked: root.showScreen("destKind")
    }

    Dropdown {
      width: parent.width
      label: "Backend"
      value: root.cloudBackend
      options: Model.cloudBackends()
      foreground: root.foreground
      onChanged: function(value) { root.cloudBackend = value }
    }

    LabeledField {
      label: "Bucket"
      placeholder: "my-backup-bucket"
      text: root.cloudBucket
      onChanged: root.cloudBucket = value
    }
    LabeledField {
      label: "Prefix"
      placeholder: "omackup"
      text: root.cloudPrefix
      onChanged: root.cloudPrefix = value
    }
    LabeledField {
      label: root.cloudBackend === "b2" ? "keyID" : "Access key"
      placeholder: root.cloudBackend === "b2" ? "keyID" : "AKIA…"
      text: root.cloudKey
      onChanged: root.cloudKey = value
    }
    LabeledField {
      label: root.cloudBackend === "b2" ? "applicationKey" : "Secret key"
      placeholder: root.cloudBackend === "b2" ? "applicationKey" : "Secret"
      password: true
      text: root.cloudSecret
      onChanged: root.cloudSecret = value
    }
    LabeledField {
      visible: root.cloudBackend !== "b2"
      label: "Region"
      placeholder: "us-east-1"
      text: root.cloudRegion
      onChanged: root.cloudRegion = value
    }

    DestCommonFields {}

    Button {
      text: omackup.busy ? "Working…" : "Create cloud destination"
      foreground: root.foreground
      enabled: !omackup.busy && root.cloudBucket !== "" && String(root.destDisplay || "").trim() !== ""
      onClicked: root.saveCloudDest()
    }
  }

  component DestCommonFields: Column {
    width: parent.width
    spacing: Style.space(10)

    LabeledField {
      label: "Label"
      placeholder: "The drive in my bag"
      text: root.destDisplay
      onChanged: root.destDisplay = value
    }
    LabeledField {
      label: "Password (blank generates one)"
      placeholder: "Leave blank to generate"
      password: true
      text: root.destPassword
      onChanged: root.destPassword = value
    }
    Dropdown {
      width: parent.width
      label: "Schedule"
      value: root.destSchedule
      options: Model.scheduleOptions()
      foreground: root.foreground
      onChanged: function(value) { root.destSchedule = value }
    }

    LabeledField {
      label: "Rate limit (0 is unlimited)"
      placeholder: "10mb/s"
      text: root.destRateLimitText
      onChanged: root.destRateLimitText = value
    }
  }

  component PasswordPage: Column {
    width: parent.width
    spacing: Style.space(12)

    Text {
      width: parent.width
      text: "This password unlocks the backup. It is stored on this computer, but that copy dies with the machine. Save it in a password manager that lives somewhere else."
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      wrapMode: Text.WordWrap
    }

    CursorSurface {
      width: parent.width
      implicitHeight: passwordText.implicitHeight + Style.space(12)
      foreground: root.foreground
      bordered: true

      Column {
        anchors.fill: parent
        anchors.margins: Style.space(8)
        spacing: Style.space(4)

        Text {
          id: passwordText
          width: parent.width
          text: omackup.lastPassword || "(password already set)"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.WrapAnywhere
        }

        Text {
          width: parent.width
          text: root.passwordCopyStatus !== "" ? root.passwordCopyStatus : "Click to copy · skipped by clipboard history"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }

      MouseArea {
        anchors.fill: parent
        enabled: omackup.lastPassword !== ""
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.copyPassword()
      }
    }

    Text {
      width: parent.width
      text: omackup.lastWarning
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    Button {
      text: "I saved the password"
      foreground: root.foreground
      onClicked: root.showScreen("overview")
    }
    Button {
      text: "Show password again"
      foreground: root.foreground
      enabled: root.pendingDest !== ""
      onClicked: omackup.showKey(root.pendingDest)
    }
  }

  component RestoreSnapsPage: Column {
    width: parent.width
    spacing: Style.space(10)

    Button {
      text: "Back"
      foreground: root.foreground
      onClicked: root.showScreen("overview")
    }

    Text {
      visible: omackup.snapshots.length === 0
      width: parent.width
      text: omackup.busy ? "Reading snapshots…" : "No snapshots yet. Run a backup first."
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      wrapMode: Text.WordWrap
    }

    Repeater {
      model: omackup.snapshots
      CursorSurface {
        required property var modelData
        required property int index
        width: parent.width
        hasCursor: root.cursorActive && root.screen === "restoreSnaps" && root.snapIndex === index
        foreground: root.foreground
        implicitHeight: Style.space(36)
        onHasCursorChanged: if (hasCursor) root.scrollToItem(this)
        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: { root.cursorActive = true; root.snapIndex = index }
          onClicked: root.openSnapshot(modelData)
        }
        Column {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.space(10)
          Text {
            text: Model.snapshotLabel(modelData)
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
          Text {
            text: String(modelData.id || "")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }

  component RestoreBrowsePage: Column {
    width: parent.width
    spacing: Style.space(10)

    Row {
      spacing: Style.space(8)
      Button {
        text: "Back"
        foreground: root.foreground
        onClicked: root.showScreen("restoreSnaps")
      }
      Button {
        text: "Up"
        foreground: root.foreground
        enabled: omackup.listingPath !== "/" && omackup.listingPath !== ""
        onClicked: omackup.loadListing(root.restoreDest, root.restoreSnapshot, Model.parentPath(omackup.listingPath))
      }
      Button {
        text: "Restore this folder"
        foreground: root.foreground
        enabled: !omackup.busy
        onClicked: omackup.restorePath(root.restoreDest, root.restoreSnapshot, omackup.listingPath === "/" ? "" : omackup.listingPath)
      }
    }

    Text {
      width: parent.width
      text: omackup.listingPath || "/"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideMiddle
    }

    Repeater {
      model: omackup.listing
      CursorSurface {
        required property var modelData
        required property int index
        width: parent.width
        hasCursor: root.cursorActive && root.screen === "restoreBrowse" && root.entryIndex === index
        foreground: root.foreground
        implicitHeight: Style.space(32)
        onHasCursorChanged: if (hasCursor) root.scrollToItem(this)
        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: { root.cursorActive = true; root.entryIndex = index }
          onClicked: {
            if (modelData.type === "dir") omackup.loadListing(root.restoreDest, root.restoreSnapshot, modelData.path)
            else omackup.restorePath(root.restoreDest, root.restoreSnapshot, modelData.path)
          }
        }
        Row {
          anchors.fill: parent
          anchors.leftMargin: Style.space(8)
          anchors.rightMargin: Style.space(8)
          spacing: Style.space(8)
          Text {
            text: Model.entryGlyph(modelData)
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.icon
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            width: parent.width - Style.space(80)
            text: modelData.name
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            visible: modelData.type !== "dir"
            text: Model.formatBytes(modelData.size)
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            anchors.verticalCenter: parent.verticalCenter
          }
        }
      }
    }
  }

  component LabeledField: Column {
    property string label: ""
    property string placeholder: ""
    property string text: ""
    property bool password: false
    signal changed(string value)

    width: parent.width
    spacing: Style.spacing.labelGap

    Text {
      visible: label !== ""
      text: label
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }
    TextField {
      id: field
      width: parent.width
      placeholderText: placeholder
      password: parent.password
      foreground: root.foreground
      onTextEdited: parent.changed(text)
      onActiveFocusChanged: {
        root.formFocused = activeFocus
        if (activeFocus && text !== parent.text) text = parent.text
      }

      Binding {
        target: field
        property: "text"
        value: field.parent.text
        when: !field.activeFocus
      }
    }
  }

  Component { id: settingsGear
    Button {
      text: ""
      iconText: "󰒓"
      tooltipText: "Settings"
      foreground: root.foreground
      horizontalPadding: Style.space(4)
      verticalPadding: Style.space(2)
      iconSize: Style.font.body
      onClicked: root.showScreen("settings")
    }
  }
  Component { id: settingsBack
    Button {
      text: "Back"
      foreground: root.foreground
      onClicked: root.showScreen("overview")
    }
  }
  Component { id: sourcesTopActions
    Row {
      spacing: Style.space(8)

      Button {
        text: "Cancel"
        foreground: root.foreground
        enabled: !omackup.sourcesSaving
        onClicked: root.cancelSources()
      }

      Button {
        text: omackup.sourcesSaving ? "Saving…" : "Save"
        foreground: root.foreground
        enabled: omackup.sourcesDirty && !omackup.sourcesSaving && !omackup.busy
        onClicked: root.saveSources()
      }
    }
  }
  Component { id: destEditTopActions
    Row {
      spacing: Style.space(8)

      Button {
        text: "Cancel"
        foreground: root.foreground
        enabled: !omackup.busy
        onClicked: root.showScreen("overview")
      }

      Button {
        text: omackup.busy ? "Saving…" : "Save"
        foreground: root.foreground
        enabled: !omackup.busy
        onClicked: root.saveDestEdit()
      }
    }
  }
  Component { id: overviewPage; OverviewPage { width: column.width } }
  Component { id: settingsPage; SettingsPage { width: column.width } }
  Component { id: sourcesPage; SourcesPage { width: column.width } }
  Component { id: destKindPage; DestKindPage { width: column.width } }
  Component { id: destEditPage; DestEditPage { width: column.width } }
  Component { id: destUsbPage; DestUsbPage { width: column.width } }
  Component { id: destNasPage; DestNasPage { width: column.width } }
  Component { id: destCloudPage; DestCloudPage { width: column.width } }
  Component { id: passwordPage; PasswordPage { width: column.width } }
  Component { id: restoreSnapsPage; RestoreSnapsPage { width: column.width } }
  Component { id: restoreBrowsePage; RestoreBrowsePage { width: column.width } }
}
