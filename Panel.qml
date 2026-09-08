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
  property string mainTab: "destinations"
  property int destIndex: 0
  property int destKindIndex: 0
  property int sourceIndex: 0
  property int excludeIndex: 0
  property int mountIndex: 0
  property int dirIndex: 0
  property bool cursorActive: false
  property bool formFocused: false

  property string destName: ""
  property string destDisplay: ""
  property bool destScheduleEnabled: false
  property string destScheduleKind: "daily"
  property string destScheduleMinutes: "60"
  property string destScheduleTimes: "300"
  property var destScheduleWeekdays: [true, false, false, false, false, false, false]
  property string destScheduleMonthDay: "1"
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
  property string pendingDest: ""
  property string passwordCopyStatus: ""
  property string editingDestKind: ""
  property string editingDestRepo: ""
  property bool sourcesHelpOpen: false
  property bool excludesHelpOpen: false
  property bool focusExcludeDraft: false
  property bool cancelConfirmOpen: false
  property string confirmKind: ""
  property string pendingRemoveExclude: ""
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
  readonly property bool onDestinationsTab: screen === "overview" && mainTab === "destinations"
  readonly property bool onFilesTab: screen === "overview" && mainTab === "files"
  readonly property bool onExclusionsTab: screen === "overview" && mainTab === "exclusions"
  readonly property bool onSourcesTab: onFilesTab || onExclusionsTab
  readonly property bool onSourcesFiles: onFilesTab
  readonly property bool onSourcesExclusions: onExclusionsTab
  readonly property var shortcutHints: {
    if (cancelConfirmOpen)
      return ["←→\u00A0choose", "enter\u00A0confirm", "esc\u00A0back"]
    if (onExclusionsTab && editingExclude !== "")
      return ["enter\u00A0save", "c\u00A0cancel"]
    if (formFocused) {
      if (onExclusionsTab) return ["enter\u00A0add", "esc\u00A0back"]
      return ["esc\u00A0back"]
    }
    if (sourcesHelpOpen || excludesHelpOpen)
      return ["?\u00A0close", "esc\u00A0back"]
    if (onDestinationsTab) {
      var destHints = ["d\u00A0dest", "f\u00A0files", "e\u00A0exclusions", "a\u00A0add"]
      if ((omackup.destinations || []).length) {
        destHints.push("↑↓\u00A0select")
        destHints.push("enter\u00A0edit")
        destHints.push("b\u00A0backup")
        destHints.push("r\u00A0restore")
      }
      if (omackup.backupActive || omackup.backupStarting) destHints.push("c\u00A0cancel")
      destHints.push("g\u00A0settings")
      return destHints
    }
    if (onFilesTab) {
      var fileHints = ["d\u00A0dest", "f\u00A0files", "e\u00A0exclusions"]
      if (omackup.treeRows && omackup.treeRows.count) {
        fileHints.push("↑↓\u00A0select")
        fileHints.push("←→\u00A0expand")
        fileHints.push("space\u00A0cycle")
      }
      fileHints.push("u\u00A0reload")
      fileHints.push("?\u00A0help")
      if (omackup.sourcesDirty) {
        fileHints.push("s\u00A0save")
        fileHints.push("c\u00A0cancel")
      }
      fileHints.push("g\u00A0settings")
      return fileHints
    }
    if (onExclusionsTab) {
      var exclusionHints = ["d\u00A0dest", "f\u00A0files", "e\u00A0exclusions", "a\u00A0add"]
      if ((omackup.draftExcludes || []).length) {
        exclusionHints.push("↑↓\u00A0select")
        exclusionHints.push("enter\u00A0edit")
        exclusionHints.push("r\u00A0remove")
      }
      exclusionHints.push("?\u00A0help")
      if (omackup.sourcesDirty) {
        exclusionHints.push("s\u00A0save")
        exclusionHints.push("c\u00A0cancel")
      }
      exclusionHints.push("g\u00A0settings")
      return exclusionHints
    }
    if (screen === "settings")
      return ["esc\u00A0back"]
    if (screen === "destKind")
      return ["↑↓\u00A0select", "enter\u00A0choose", "1\u00A0usb", "2\u00A0nas", "3\u00A0cloud", "esc\u00A0back"]
    if (screen === "destUsb")
      return ["↑↓\u00A0select", "enter\u00A0choose", "r\u00A0rescan", "s\u00A0create", "esc\u00A0back"]
    if (screen === "destEdit")
      return ["enter\u00A0save", "esc\u00A0back"]
    if (screen === "destNas" || screen === "destCloud")
      return ["enter\u00A0create", "esc\u00A0back"]
    if (screen === "passwordWarn")
      return ["c\u00A0copy", "s\u00A0show", "enter\u00A0done", "esc\u00A0back"]
    return []
  }
  readonly property string heroDetail: {
    if (screen === "overview" || screen === "destEdit" || screen === "settings") return ""
    return screenTitle()
  }

  function showScreen(name) {
    previousScreen = screen
    screen = name
    formFocused = false
    cursorActive = name === "overview" || name === "destKind" || name === "destUsb"
    sourcesHelpOpen = false
    excludesHelpOpen = false
    if (panelFlick) panelFlick.contentY = 0
    if (name === "passwordWarn") passwordCopyStatus = ""
    if (name === "destUsb") scanUsbMounts()
    if (name === "overview" && (mainTab === "files" || mainTab === "exclusions")) {
      if (!omackup.sourcesEditing) omackup.beginSourcesEdit()
      if (mainTab === "files") omackup.ensureHomeTree()
    } else if (name !== "overview") {
      dismissExcludeEditor()
      highlightExclude = ""
      editingExclude = ""
      editingExcludeDraft = ""
      excludeEditField = null
    }
  }

  function prepareSourcesTab(name) {
    if (!omackup.sourcesEditing) omackup.beginSourcesEdit()
    if (name === "files") {
      omackup.ensureHomeTree()
      omackup.refreshSelectionSize()
    } else if (name === "exclusions") {
      var list = omackup.draftExcludes || []
      if (excludeIndex >= list.length) excludeIndex = Math.max(0, list.length - 1)
      if (list.length) highlightExclude = String(list[excludeIndex] || "")
    }
  }

  function showTab(name) {
    if (name !== "destinations" && name !== "files" && name !== "exclusions") return
    if (screen !== "overview") showScreen("overview")
    if (mainTab === name) {
      if (name === "files" || name === "exclusions") prepareSourcesTab(name)
      return
    }
    mainTab = name
    formFocused = false
    cursorActive = true
    sourcesHelpOpen = false
    excludesHelpOpen = false
    if (panelFlick) panelFlick.contentY = 0
    if (name === "files" || name === "exclusions") {
      if (name === "files") dismissExcludeEditor()
      prepareSourcesTab(name)
    } else {
      dismissExcludeEditor()
    }
    if (keyCatcher) keyCatcher.forceActiveFocus()
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
    showTab("exclusions")
    selectExcludePattern(value)
    beginEditExclude(value)
  }

  function beginEditExclude(pattern) {
    var value = String(pattern || "")
    showTab("exclusions")
    selectExcludePattern(value)
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
    selectExcludePattern(next)
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

  function requestCancelBackup() {
    if (!omackup.backupActive && !omackup.backupStarting) return
    if (screen !== "overview") showScreen("overview")
    if (mainTab !== "destinations") showTab("destinations")
    openConfirm("cancelBackup")
  }

  function dismissCancelConfirm() {
    cancelConfirmOpen = false
    confirmKind = ""
    pendingRemoveExclude = ""
    if (keyCatcher) keyCatcher.forceActiveFocus()
  }

  function confirmCancelBackup() {
    cancelConfirmOpen = false
    confirmKind = ""
    omackup.cancelBackup()
    if (keyCatcher) keyCatcher.forceActiveFocus()
  }

  function openConfirm(kind) {
    sourcesHelpOpen = false
    excludesHelpOpen = false
    confirmKind = kind
    cancelConfirm.selectedIndex = 0
    cancelConfirmOpen = true
    Qt.callLater(function() {
      if (cancelConfirmKeys) cancelConfirmKeys.forceActiveFocus()
    })
  }

  function selectedExclude() {
    var list = omackup.draftExcludes || []
    if (!list.length) return ""
    return String(list[Math.max(0, Math.min(excludeIndex, list.length - 1))] || "")
  }

  function selectExcludePattern(pattern) {
    var value = String(pattern || "")
    var list = omackup.draftExcludes || []
    var i
    for (i = 0; i < list.length; i++) {
      if (String(list[i]) === value) {
        excludeIndex = i
        highlightExclude = value
        return
      }
    }
    highlightExclude = value
  }

  function editSelectedExclude() {
    var pattern = selectedExclude()
    if (!pattern) return
    showTab("exclusions")
    beginEditExclude(pattern)
  }

  function requestRemoveExclude(pattern) {
    var value = String(pattern || selectedExclude() || "")
    if (!value) return
    pendingRemoveExclude = value
    showTab("exclusions")
    selectExcludePattern(value)
    openConfirm("removeExclude")
  }

  function confirmRemoveExclude() {
    var value = String(pendingRemoveExclude || "")
    cancelConfirmOpen = false
    confirmKind = ""
    pendingRemoveExclude = ""
    if (value) {
      if (editingExclude === value) cancelEditExclude()
      if (highlightExclude === value) highlightExclude = ""
      omackup.removeExclude(value)
      var list = omackup.draftExcludes || []
      if (excludeIndex >= list.length) excludeIndex = Math.max(0, list.length - 1)
      if (list.length) highlightExclude = String(list[excludeIndex] || "")
    }
    if (keyCatcher) keyCatcher.forceActiveFocus()
  }

  function goBack() {
    if (cancelConfirmOpen) {
      dismissCancelConfirm()
      return
    }
    if (editingExclude !== "") {
      cancelEditExclude()
      return
    }
    if (sourcesHelpOpen || excludesHelpOpen) {
      sourcesHelpOpen = false
      excludesHelpOpen = false
      return
    }
    if (screen === "overview") {
      if (omackup.sourcesEditing) omackup.cancelSourcesEdit()
      root.close()
      return
    }
    if (screen === "settings") {
      showScreen("overview")
      return
    }
    if (screen === "passwordWarn" || screen === "destEdit") {
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
    if (onSourcesTab) omackup.beginSourcesEdit()
  }

  function saveSources() {
    if (!omackup.sourcesDirty || omackup.sourcesSaving || omackup.busy) return
    omackup.saveSourcesEdit(function(ok) {
      if (ok && onSourcesTab) omackup.beginSourcesEdit()
    })
  }

  function resetDestForm() {
    destName = ""
    destDisplay = ""
    applyScheduleToForm(null)
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

  function beginAddExclude() {
    showTab("exclusions")
    sourcesHelpOpen = false
    excludesHelpOpen = false
    focusExcludeDraft = false
    focusExcludeDraft = true
  }

  function toggleSourcesHelp() {
    excludesHelpOpen = false
    sourcesHelpOpen = !sourcesHelpOpen
  }

  function toggleExcludesHelp() {
    sourcesHelpOpen = false
    excludesHelpOpen = !excludesHelpOpen
  }

  function handleTextKey(t) {
    var key = String(t || "").toLowerCase()
    if (cancelConfirmOpen) return
    if (screen === "overview") {
      if (key === "d") { showTab("destinations"); return }
      if (key === "f") { showTab("files"); return }
      if (key === "e") { showTab("exclusions"); return }
      if (key === "g") { showScreen("settings"); return }
      if (key === "?" || key === "/") {
        if (onFilesTab) toggleSourcesHelp()
        else if (onExclusionsTab) toggleExcludesHelp()
        return
      }
      if (onDestinationsTab) {
        if (key === "a") startAddDest()
        else if (key === "b") backupSelectedDest()
        else if (key === "c") requestCancelBackup()
        else if (key === "r") restoreSelectedDest()
        return
      }
      if (onFilesTab) {
        if (key === "u") omackup.refreshHomeTree()
        else if (key === "s") saveSources()
        else if (key === "c") cancelSources()
        return
      }
      if (onExclusionsTab) {
        if (key === "a") beginAddExclude()
        else if (key === "r") requestRemoveExclude()
        else if (key === "s") saveSources()
        else if (key === "c") cancelSources()
      }
      return
    }
    if (screen === "destKind") {
      if (key === "1") { destKindIndex = 0; showScreen("destUsb") }
      else if (key === "2") { destKindIndex = 1; showScreen("destNas") }
      else if (key === "3") { destKindIndex = 2; showScreen("destCloud") }
      return
    }
    if (screen === "destUsb") {
      if (key === "r") scanUsbMounts()
      else if (key === "s") saveUsbDest()
      return
    }
    if (screen === "destNas" && key === "s") {
      saveNasDest()
      return
    }
    if (screen === "destCloud" && key === "s") {
      saveCloudDest()
      return
    }
    if (screen === "passwordWarn") {
      if (key === "c") copyPassword()
      else if (key === "s" && pendingDest) omackup.showKey(pendingDest)
      return
    }
  }

  function applyScheduleToForm(raw) {
    var spec = Model.parseSchedule(raw)
    destScheduleEnabled = spec.enabled === true
    destScheduleKind = spec.kind || "daily"
    destScheduleMinutes = String(spec.minutes || 60)
    destScheduleTimes = String(spec.times_text || "300")
    destScheduleWeekdays = spec.weekdays && spec.weekdays.length ? spec.weekdays.slice() : Model.defaultWeekdays()
    destScheduleMonthDay = String(spec.monthday || 1)
  }

  function destScheduleSpec() {
    return {
      enabled: destScheduleEnabled,
      kind: destScheduleKind,
      minutes: parseInt(destScheduleMinutes, 10) || 60,
      times_text: destScheduleTimes,
      weekdays: destScheduleWeekdays,
      monthday: parseInt(destScheduleMonthDay, 10) || 1
    }
  }

  function destScheduleCliValue() {
    var spec = destScheduleSpec()
    if (!spec.enabled) return ""
    var err = Model.scheduleError(spec)
    if (err) {
      omackup.lastError = err
      return null
    }
    return Model.scheduleToCli(spec)
  }

  function toggleScheduleWeekday(index) {
    var next = (destScheduleWeekdays || Model.defaultWeekdays()).slice()
    next[index] = !next[index]
    destScheduleWeekdays = next
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
    applyScheduleToForm(dest.schedule)
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
    var schedule = destScheduleCliValue()
    if (schedule === null) return
    var args = [
      "dest-add", "--name", destName, "--kind", editingDestKind, "--repository", editingDestRepo,
      "--display-name", display, "--schedule", schedule, "--pre-command", destPreCommand
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
    var dest = name || (selectedDest ? selectedDest.name : "")
    if (!dest) return
    omackup.openRestore(dest)
    if (omackup.restoreOpen) root.close()
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
    var schedule = destScheduleCliValue()
    if (schedule === null) return
    var args = [
      "dest-add", "--name", name, "--kind", kind, "--repository", repo,
      "--display-name", display, "--schedule", schedule, "--pre-command", destPreCommand
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
      if (onDestinationsTab) {
        editSelectedDest()
      } else if (onSourcesFiles) {
        var row = sourceRowAt(sourceIndex)
        if (row && row.path) {
          cursorActive = true
          omackup.cycleItem(row.path)
        }
      } else if (onSourcesExclusions) {
        editSelectedExclude()
      }
    } else if (screen === "destKind") {
      openSelectedDestKind()
    } else if (screen === "destNas") {
      saveNasDest()
    } else if (screen === "destCloud") {
      saveCloudDest()
    } else if (screen === "destUsb") {
      var mounts = omackup.mounts || []
      if (!mounts.length) return
      var mount = mounts[Math.max(0, Math.min(mountIndex, mounts.length - 1))]
      if (mount) selectUsbMount(mount.path)
    } else if (screen === "destEdit") {
      saveDestEdit()
    } else if (screen === "passwordWarn") {
      showScreen("overview")
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
    if (!opened) {
      cancelConfirmOpen = false
      confirmKind = ""
      pendingRemoveExclude = ""
      if (omackup && omackup.sourcesEditing) omackup.cancelSourcesEdit()
      return
    }
    if (omackup) {
      cursorActive = screen === "overview" || screen === "destKind" || screen === "destUsb"
      formFocused = false
      if (screen === "overview" && panelFlick) panelFlick.contentY = 0
      omackup.refresh()
      if (onSourcesTab) {
        if (!omackup.sourcesEditing) omackup.beginSourcesEdit()
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
    contentHeight: panel.fittedContentHeight(
      column.implicitHeight + (shortcutBar.visible ? Style.space(12) + shortcutBar.implicitHeight : 0),
      Style.space(620)
    )

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.formFocused || root.cancelConfirmOpen
      onMoveRequested: function(dx, dy) {
        root.cursorActive = true
        if (root.onDestinationsTab) {
          if (omackup.destinations.length) destIndex = Math.max(0, Math.min(omackup.destinations.length - 1, destIndex + dy))
        } else if (root.screen === "destKind") {
          destKindIndex = Math.max(0, Math.min(2, destKindIndex + dy))
        } else if (root.screen === "destUsb" && omackup.mounts.length) {
          mountIndex = Math.max(0, Math.min(omackup.mounts.length - 1, mountIndex + dy))
          root.selectUsbMount(omackup.mounts[mountIndex].path)
        } else if (root.onSourcesFiles && omackup.treeRows.count) {
          if (dy !== 0) {
            sourceIndex = Math.max(0, Math.min(omackup.treeRows.count - 1, sourceIndex + dy))
          } else if (dx !== 0) {
            var row = root.sourceRowAt(sourceIndex)
            if (row && row.type === "dir") {
              if (dx > 0 && !row.expanded) omackup.toggleExpand(row.path)
              else if (dx < 0 && row.expanded) omackup.toggleExpand(row.path)
            }
          }
        } else if (root.onSourcesExclusions) {
          var excludes = omackup.draftExcludes || []
          if (excludes.length && dy !== 0) {
            excludeIndex = Math.max(0, Math.min(excludes.length - 1, excludeIndex + dy))
            highlightExclude = String(excludes[excludeIndex] || "")
          }
        }
      }
      onActivateRequested: root.activateCursor()
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
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: shortcutBar.top
        anchors.bottomMargin: shortcutBar.visible ? Style.space(8) : 0
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
            trailingControl: root.screen === "destEdit" ? destEditTopActions
              : (root.screen === "settings" ? settingsBack
              : (root.screen === "overview" ? settingsGear : null))
          }

          Row {
            visible: root.screen === "overview"
            width: parent.width
            spacing: Style.space(8)

            Button {
              width: (parent.width - parent.spacing * 2) / 3
              text: "Destinations"
              foreground: root.foreground
              bordered: true
              selected: root.mainTab === "destinations"
              onClicked: root.showTab("destinations")
            }

            Button {
              width: (parent.width - parent.spacing * 2) / 3
              text: "Files"
              foreground: root.foreground
              bordered: true
              selected: root.mainTab === "files"
              onClicked: root.showTab("files")
            }

            Button {
              width: (parent.width - parent.spacing * 2) / 3
              text: "Exclusions"
              foreground: root.foreground
              bordered: true
              selected: root.mainTab === "exclusions"
              onClicked: root.showTab("exclusions")
            }
          }

          Item {
            visible: root.onSourcesTab
            width: parent.width
            height: visible ? sourcesTabActions.implicitHeight : 0

            Row {
              id: sourcesTabActions
              anchors.right: parent.right
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
              if (root.onFilesTab) return filesPage
              if (root.onExclusionsTab) return exclusionsPage
              if (root.screen === "settings") return settingsPage
              if (root.screen === "destKind") return destKindPage
              if (root.screen === "destUsb") return destUsbPage
              if (root.screen === "destNas") return destNasPage
              if (root.screen === "destCloud") return destCloudPage
              if (root.screen === "destEdit") return destEditPage
              if (root.screen === "passwordWarn") return passwordPage
              return overviewPage
            }
          }
        }
      }

      Flow {
        id: shortcutBar
        visible: root.shortcutHints.length > 0
        height: visible ? implicitHeight : 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        spacing: Style.space(12)

        Repeater {
          model: root.shortcutHints
          Text {
            required property string modelData
            text: modelData
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.NoWrap
          }
        }
      }

      Item {
        id: cancelConfirmKeys
        anchors.fill: parent
        visible: root.cancelConfirmOpen
        focus: root.cancelConfirmOpen
        z: 4000
        Keys.onPressed: function(event) {
          if (cancelConfirm.handleKey(event)) event.accepted = true
        }

        ConfirmDialog {
          id: cancelConfirm
          anchors.fill: parent
          opened: root.cancelConfirmOpen
          message: root.confirmKind === "removeExclude" ? "Remove this exclusion?" : "Cancel this backup?"
          cancelText: "No"
          confirmText: "Yes"
          foreground: root.foreground
          fontFamily: root.fontFamily
          onCanceled: root.dismissCancelConfirm()
          onConfirmed: {
            if (root.confirmKind === "removeExclude") root.confirmRemoveExclude()
            else root.confirmCancelBackup()
          }
        }
      }

      Item {
        anchors.fill: parent
        visible: (root.sourcesHelpOpen || root.excludesHelpOpen) && root.onSourcesTab
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
                ? "Add glob rules like **/node_modules or *.iso to skip matching paths everywhere in your selection.\n\nClick a dashed red name in the file tree to jump to the pattern that matched it.\n\nReset defaults restores the built-in pattern list."
                : "Left click includes a file or folder.\n\nLeft click again removes it from the selection.\n\nRight click excludes it. That item stays out until you left-click it again.\n\nSpace cycles off → included → excluded."
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
    if (screen === "settings") return "Settings"
    if (screen === "destKind") return "Add destination"
    if (screen === "destUsb") return "USB drive"
    if (screen === "destNas") return "NAS"
    if (screen === "destCloud") return "Cloud"
    if (screen === "destEdit") return "Edit destination"
    if (screen === "passwordWarn") return "Save this password"
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

    Item {
      width: parent.width
      height: addDestBtn.implicitHeight

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
          hasCursor: root.cursorActive && root.onDestinationsTab && root.destIndex === index
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
                    text: modelData.schedule_pending
                      ? "Backup pending — connect this destination"
                      : modelData.reachable === false
                        ? (modelData.reachable_error || "Not reachable")
                        : Model.destMeta(modelData, omackup.use24HourTime)
                    color: modelData.reachable === false || modelData.failed || modelData.overdue || modelData.schedule_pending ? root.urgent : root.dim
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
                    text: modelData.schedule_label || Model.scheduleLabel(modelData.schedule)
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
                onClicked: root.requestCancelBackup()
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

  component FilesPage: Column {
    width: parent.width
    spacing: Style.space(12)

    Item {
      width: parent.width
      height: Math.max(Style.space(28), treeRefreshBtn.implicitHeight)

      Row {
        anchors.left: parent.left
        anchors.right: filesHeaderActions.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(6)

        Text {
          text: omackup.selectionSizeText
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.NoWrap
          elide: Text.ElideRight
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          visible: omackup.selectionSizeLoading
          text: omackup.selectionSizeSpinner
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      Row {
        id: filesHeaderActions
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
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
          onClicked: root.toggleSourcesHelp()
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

    Column {
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
          hasCursor: root.cursorActive && root.onSourcesFiles && root.sourceIndex === index
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
  }

  component ExclusionsPage: Column {
    width: parent.width
    spacing: Style.space(12)

    Item {
      width: parent.width
      height: Math.max(Style.space(28), excludesHelpBtn.implicitHeight)

      Row {
        anchors.left: parent.left
        anchors.right: excludesHelpBtn.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(6)

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
        onClicked: root.toggleExcludesHelp()
      }
    }

    Column {
      width: parent.width
      spacing: 0

      Repeater {
        model: omackup.draftExcludes
        ExcludeRuleRow {
          required property var modelData
          required property int index
          width: parent.width
          pattern: String(modelData || "")
          rowIndex: index
          hasCursor: root.cursorActive && root.onSourcesExclusions && root.excludeIndex === index
        }
      }
    }

    TextField {
      id: excludeDraftField
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
      onVisibleChanged: {
        if (visible && root.focusExcludeDraft) {
          Qt.callLater(function() {
            excludeDraftField.forceActiveFocus()
            root.formFocused = true
            root.focusExcludeDraft = false
            root.scrollToItem(excludeDraftField)
          })
        }
      }
      Keys.onEscapePressed: {
        root.formFocused = false
        if (keyCatcher) keyCatcher.forceActiveFocus()
      }
      Connections {
        target: root
        function onFocusExcludeDraftChanged() {
          if (!root.focusExcludeDraft || !excludeDraftField.visible) return
          Qt.callLater(function() {
            if (!root.focusExcludeDraft || !excludeDraftField.visible) return
            excludeDraftField.forceActiveFocus()
            root.formFocused = true
            root.focusExcludeDraft = false
            root.scrollToItem(excludeDraftField)
          })
        }
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

  component ExcludeRuleRow: CursorSurface {
    id: excludeRow
    property string pattern: ""
    property int rowIndex: 0
    property string draft: pattern
    readonly property bool focused: root.onSourcesExclusions
      ? root.excludeIndex === rowIndex && pattern !== ""
      : (root.highlightExclude === pattern && pattern !== "")
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
          onClicked: {
            root.showTab("exclusions")
            root.excludeIndex = excludeRow.rowIndex
            root.beginEditExclude(excludeRow.pattern)
          }
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
        Keys.onPressed: function(event) {
          if (String(event.text || "").toLowerCase() === "c") {
            root.cancelEditExclude()
            event.accepted = true
          }
        }
      }

      Button {
        text: ""
        iconText: "×"
        tooltipText: "Remove exclude"
        foreground: root.foreground
        horizontalPadding: Style.space(4)
        verticalPadding: Style.space(2)
        iconSize: Style.font.body
        onClicked: root.requestRemoveExclude(excludeRow.pattern)
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
      onEntered: {
        if (root.editingExclude !== "" || root.cancelConfirmOpen) return
        root.cursorActive = true
        root.sourceIndex = treeRow.rowIndex
      }
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

    DestScheduleFields {}

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
    DestScheduleFields {}

    LabeledField {
      label: "Rate limit (0 is unlimited)"
      placeholder: "10mb/s"
      text: root.destRateLimitText
      onChanged: root.destRateLimitText = value
    }
  }

  component DestScheduleFields: Column {
    width: parent.width
    spacing: Style.space(8)

    Item {
      width: parent.width
      height: Math.max(scheduleSwitch.implicitHeight, scheduleKind.implicitHeight, scheduleManual.implicitHeight)

      ToggleSwitch {
        id: scheduleSwitch
        cursorRing: false
        checked: root.destScheduleEnabled
        foreground: root.foreground
        accent: Color.accent
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        onToggled: root.destScheduleEnabled = !root.destScheduleEnabled
      }

      Text {
        id: scheduleManual
        visible: !root.destScheduleEnabled
        anchors.left: scheduleSwitch.right
        anchors.leftMargin: Style.space(8)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: "Manual only"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        wrapMode: Text.WordWrap
      }

      Dropdown {
        id: scheduleKind
        visible: root.destScheduleEnabled
        anchors.left: scheduleSwitch.right
        anchors.leftMargin: Style.space(8)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: implicitHeight
        showLabel: false
        value: root.destScheduleKind
        options: Model.scheduleKindOptions()
        foreground: root.foreground
        onChanged: function(value) { root.destScheduleKind = value }
      }
    }

    LabeledField {
      visible: root.destScheduleEnabled && root.destScheduleKind === "interval"
      label: "Every (minutes)"
      placeholder: "30"
      text: root.destScheduleMinutes
      onChanged: root.destScheduleMinutes = value
    }

    LabeledField {
      visible: root.destScheduleEnabled && root.destScheduleKind === "daily"
      label: "Times (2:30pm = 1430, 3am = 300)"
      placeholder: "300, 1300, 1430"
      text: root.destScheduleTimes
      onChanged: root.destScheduleTimes = value
    }

    Column {
      visible: root.destScheduleEnabled && root.destScheduleKind === "weekly"
      width: parent.width
      spacing: Style.space(6)

      Row {
        spacing: Style.space(4)

        Repeater {
          model: 7
          CursorSurface {
            required property int index
            width: Style.space(22)
            implicitHeight: Style.space(22)
            foreground: root.foreground
            bordered: true
            current: !!root.destScheduleWeekdays[index]

            Text {
              anchors.centerIn: parent
              text: Model.weekdayLabels()[index]
              color: root.destScheduleWeekdays[index] ? root.foreground : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.toggleScheduleWeekday(index)
            }
          }
        }
      }

      LabeledField {
        label: "Times (2:30PM = 1430, 3AM = 300)"
        placeholder: "300, 1300, 1430"
        text: root.destScheduleTimes
        onChanged: root.destScheduleTimes = value
      }
    }

    Column {
      visible: root.destScheduleEnabled && root.destScheduleKind === "monthly"
      width: parent.width
      spacing: Style.space(4)

      LabeledField {
        label: "Day of the month"
        placeholder: "15"
        text: root.destScheduleMonthDay
        onChanged: root.destScheduleMonthDay = value
      }

      Text {
        width: parent.width
        visible: parseInt(root.destScheduleMonthDay, 10) > 28
        text: "On shorter months this runs on the last day, at 03:00."
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
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

  component SettingsGearButton: BorderSurface {
    id: gear
    readonly property int fontPx: Style.font.body
    readonly property int hitPad: Style.space(10)
    readonly property int box: Math.max(Style.space(40), gear.fontPx + gear.hitPad * 2)

    implicitWidth: box
    implicitHeight: box
    width: box
    height: box
    radius: Style.cornerRadius
    color: gearMouse.containsMouse ? Style.hoverFillFor(root.foreground, root.foreground) : "transparent"

    OpticalGlyph {
      anchors.fill: parent
      text: "󰒓"
      fontFamily: root.fontFamily
      fontSize: gear.fontPx
      color: root.foreground
    }

    MouseArea {
      id: gearMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.showScreen("settings")
    }

    PanelToolTip {
      visible: gearMouse.containsMouse
      text: "Settings"
      fontFamily: root.fontFamily
    }
  }

  Component { id: settingsGear
    SettingsGearButton {}
  }
  Component { id: settingsBack
    Button {
      text: "Back"
      foreground: root.foreground
      onClicked: root.showScreen("overview")
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
  Component { id: filesPage; FilesPage { width: column.width } }
  Component { id: exclusionsPage; ExclusionsPage { width: column.width } }
  Component { id: destKindPage; DestKindPage { width: column.width } }
  Component { id: destEditPage; DestEditPage { width: column.width } }
  Component { id: destUsbPage; DestUsbPage { width: column.width } }
  Component { id: destNasPage; DestNasPage { width: column.width } }
  Component { id: destCloudPage; DestCloudPage { width: column.width } }
  Component { id: passwordPage; PasswordPage { width: column.width } }
}
