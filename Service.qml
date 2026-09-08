import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

// Headless singleton. The shell mounts one of these for the plugin; every
// bar widget (one per monitor) reads the same instance via serviceFor().
Item {
  id: root

  property var shell: null
  property var settings: ({})
  property bool dormant: false
  property int _openPanels: 0

  property bool resticInstalled: false
  property var destinations: []
  property var sources: ["~"]
  property var excludes: []
  property var excludePaths: []
  property var draftSources: ["~"]
  property var draftExcludes: []
  property var draftExcludePaths: []
  property bool sourcesEditing: false
  property bool sourcesSaving: false
  readonly property bool sourcesDirty: {
    if (!sourcesEditing) return false
    return !sameStringList(draftSources, sources)
      || !sameStringList(draftExcludePaths, excludePaths)
      || !sameStringList(draftExcludes, excludes)
  }
  property var mounts: []
  property bool mountsLoading: false
  property var snapshots: []
  property var listing: []
  property var dirs: []
  property string dirsPath: ""
  property string dirsParent: ""
  property string listingPath: "/"
  property bool restoreOpen: false
  property string restoreDest: ""
  property string restoreDestDisplay: ""
  property string restoreSnapshot: "latest"
  property int restoreSnapIndex: 0
  property int restoreEntryIndex: 0
  property string restoreFocus: "timeline"
  property var restoreSelected: null
  property var preview: ({
    kind: "",
    name: "",
    path: "",
    size: 0,
    mtime: "",
    text: "",
    image_path: ""
  })
  property bool previewLoading: false
  property int previewSeq: 0
  property int previewJobSeq: 0
  property string homePath: ""
  property var expandedPaths: ({})
  property var childrenByPath: ({})
  property alias treeRows: treeModel
  property bool treeLoading: false
  property int treeRefreshSeq: 0
  property real selectionBytes: 0
  property int selectionFiles: 0
  property bool selectionSizeLoading: false
  property int selectionSizeSeq: 0
  property string selectionSizeStdoutBuf: ""
  property string selectionSizeStderrBuf: ""
  property int selectionSizeSpinnerIndex: 0
  readonly property string selectionSizeSpinnerChars: "⠁⠂⠄⡀⡈⡐⡠⣀⣁⣂⣄⣌⣔⣤⣥⣦⣮⣶⣷⣿⡿⠿⢟⠟⡛⠛⠫⢋⠋⠍⡉⠉⠑⠡⢁"
  readonly property string selectionSizeSpinner: selectionSizeSpinnerChars.charAt(selectionSizeSpinnerIndex % selectionSizeSpinnerChars.length)
  readonly property string selectionSizeText: {
    if (selectionSizeLoading) return "Selected files: "
    var activeSources = sourcesEditing ? draftSources : sources
    if (!activeSources || activeSources.length === 0) return "Selected files: 0 B · 0 files"
    var label = Model.formatBytes(selectionBytes)
    if (selectionFiles > 0) return "Selected files: " + label + " · " + selectionFiles + " files"
    return "Selected files: " + label
  }
  readonly property string selectionSizeSummary: {
    if (selectionSizeLoading) return "Calculating…"
    var activeSources = sourcesEditing ? draftSources : sources
    if (!activeSources || activeSources.length === 0) return "0 B · 0 files"
    var label = Model.formatBytes(selectionBytes)
    if (selectionFiles > 0) return label + " · " + selectionFiles + " files"
    return label
  }

  ListModel { id: treeModel }
  property string statusText: "Checking…"
  property string statusDetail: ""
  property bool alert: false
  readonly property bool hasFailedBackup: {
    if (alert) return true
    var list = destinations || []
    var i
    for (i = 0; i < list.length; i++) {
      if (list[i] && (list[i].failed === true || list[i].overdue === true)) return true
    }
    return false
  }
  readonly property bool hasUnbackedUp: Number(pendingFiles || 0) > 0
  property string actionStatus: ""
  property string lastError: ""
  property string lastPassword: ""
  property string lastWarning: ""
  property string lastOpened: ""
  property bool refreshing: false
  property bool panelOpen: false
  property int pendingFiles: 0
  property bool pendingScanning: false
  property int pendingScanSeq: 0
  property int pendingJobSeq: 0
  property int lastNotifiedPending: -1
  property int lastNotifiedStaleSince: 0
  property string lastNotifiedOverdueKey: ""
  property string lastNotifiedPendingDestKey: ""
  property var _notifyQueue: []

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 60, 15, 3600)
  readonly property int pendingScanIntervalSec: intSetting("pendingScanIntervalSec", 900, 120, 86400)
  readonly property bool notifyOnUnbackedUp: boolSetting("notifyOnUnbackedUp", true)
  readonly property bool notifyOnStaleUnbackedUp: boolSetting("notifyOnStaleUnbackedUp", false)
  readonly property int staleUnbackedUpHours: intSetting("staleUnbackedUpHours", 24, 1, 720)
  readonly property bool notifyOnMissedBackup: boolSetting("notifyOnMissedBackup", true)
  readonly property bool colorfulBackupBar: boolSetting("colorfulBackupBar", true)
  readonly property bool use24HourTime: boolSetting("use24HourTime", true)
  // Silent background jobs (reachability polls) must not flash the UI as "busy".
  property bool workerSilent: false
  readonly property bool busy: backupActive || backupStarting || (worker.running && !workerSilent)
  function setPanelOpen(open) {
    if (open) _openPanels += 1
    else if (_openPanels > 0) _openPanels -= 1
    panelOpen = _openPanels > 0
  }

  function destByName(name) {
    var list = destinations || []
    var i
    for (i = 0; i < list.length; i++) {
      if (list[i] && String(list[i].name) === String(name)) return list[i]
    }
    return null
  }

  function destDisplayName(name) {
    var dest = destByName(name)
    if (!dest) return String(name || "")
    return String(dest.display_name || dest.name || name)
  }

  function destIsReachable(name) {
    var list = destinations || []
    var i
    for (i = 0; i < list.length; i++) {
      if (list[i] && String(list[i].name) === String(name))
        return list[i].reachable === true
    }
    return false
  }
  property bool backupActive: false
  property bool backupStarting: false
  property bool backupCancelling: false
  property string backupDest: ""
  property real backupPercent: 0
  property int backupEtaSeconds: -1
  property real backupBytesDone: 0
  property real backupTotalBytes: 0
  property real backupBytesPerSec: 0
  property int backupFilesDone: 0
  property int backupTotalFiles: 0
  property string backupPhase: ""
  property bool backupDisconnected: false
  property string backupSuccessDest: ""
  readonly property bool backupCalculating: !backupDisconnected && (backupPhase === "calculating" || backupPhase === "starting")
  readonly property string backupEtaText: {
    if (!backupActive) return ""
    if (backupEtaSeconds < 0) return "Estimating time left…"
    if (backupEtaSeconds === 0 && backupPercent >= 0.999) return "Finishing…"
    return "~" + Model.formatDuration(backupEtaSeconds) + " left"
  }
  readonly property string backupStatsLine: {
    if (backupDisconnected) {
      var pct = Math.round(Math.max(0, Math.min(1, backupPercent)) * 100)
      return pct + "% - disconnected"
    }
    if (backupCalculating) return "Calculating files and size…"
    return Model.formatBackupStats(
      backupPercent,
      backupFilesDone,
      backupTotalFiles,
      backupBytesDone,
      backupTotalBytes,
      backupBytesPerSec,
      backupEtaSeconds
    )
  }
  readonly property string backupProgressLabel: {
    if (!backupActive) return ""
    return "Backing up " + (backupDest || "…") + " · " + backupStatsLine
  }
  readonly property string helperPath: {
    var home = Quickshell.env("HOME") || ""
    return home + "/.config/omarchy/plugins/gravey.omackup/bin/omackup"
  }

  property var _queue: []
  property var _current: null
  property string _stdout: ""
  property string _stderr: ""
  property int selectionSizeJobSeq: 0

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function boolSetting(name, fallback) {
    var value = settings ? settings[name] : undefined
    if (value === undefined || value === null) return fallback
    if (value === true || value === 1 || value === "1" || value === "true") return true
    if (value === false || value === 0 || value === "0" || value === "false") return false
    return fallback
  }

  function elideStatus(text) {
    var value = String(text || "").replace(/\s+/g, " ").trim()
    return value.length > 180 ? value.substring(0, 177) + "…" : value
  }

  function copyStringList(list) {
    var out = []
    var i
    for (i = 0; i < (list || []).length; i++) out.push(String(list[i]))
    return out
  }

  function jsonStringList(list) {
    var parts = []
    var i
    for (i = 0; i < (list || []).length; i++) parts.push(JSON.stringify(String(list[i] || "")))
    return "[" + parts.join(",") + "]"
  }

  function selectionOverrideJson() {
    var src = copyStringList(sourcesEditing ? draftSources : sources)
    var exPaths = copyStringList(sourcesEditing ? draftExcludePaths : excludePaths)
    var ex = copyStringList(sourcesEditing ? draftExcludes : excludes)
    return '{"sources":' + jsonStringList(src)
      + ',"exclude_paths":' + jsonStringList(exPaths)
      + ',"excludes":' + jsonStringList(ex) + '}'
  }

  function sameStringList(a, b) {
    var left = a || []
    var right = b || []
    if (left.length !== right.length) return false
    var i
    for (i = 0; i < left.length; i++) {
      if (String(left[i]) !== String(right[i])) return false
    }
    return true
  }

  function beginSourcesEdit() {
    draftSources = copyStringList(sources)
    draftExcludePaths = copyStringList(excludePaths)
    draftExcludes = copyStringList(excludes)
    sourcesEditing = true
    refreshSelectionSize()
  }

  function cancelSourcesEdit() {
    draftSources = copyStringList(sources)
    draftExcludePaths = copyStringList(excludePaths)
    draftExcludes = copyStringList(excludes)
    sourcesEditing = false
    sourcesSaving = false
    lastError = ""
    refreshSelectionSize()
  }

  function saveSourcesEdit(onDone) {
    if (sourcesSaving) return
    sourcesSaving = true
    lastError = ""
    run(["selection-set", "--json", JSON.stringify({
      sources: draftSources || [],
      exclude_paths: draftExcludePaths || [],
      excludes: draftExcludes || []
    })], function(payload) {
      sources = payload.sources || draftSources
      excludePaths = payload.exclude_paths || draftExcludePaths
      excludes = payload.excludes || draftExcludes
      draftSources = copyStringList(sources)
      draftExcludePaths = copyStringList(excludePaths)
      draftExcludes = copyStringList(excludes)
      sourcesEditing = false
      sourcesSaving = false
      refreshSelectionSize()
      refresh()
      if (onDone) onDone(true)
    }, function(err) {
      sourcesSaving = false
      lastError = elideStatus(err)
      if (onDone) onDone(false)
    })
  }

  function run(args, onOk, onErr, silent) {
    if (root.dormant) {
      if (onErr) onErr("Omackup service is not ready")
      return
    }
    _queue.push({
      args: args,
      onOk: onOk,
      onErr: onErr,
      silent: silent === true
    })
    kick()
  }

  function kick() {
    if (worker.running || _queue.length === 0) return
    _current = _queue.shift()
    workerSilent = _current.silent === true
    _stdout = ""
    _stderr = ""
    if (!_current.silent) {
      lastError = ""
    }
    worker.command = [helperPath].concat(_current.args)
    worker.running = true
  }

  function applyStatus(raw) {
    var parsed = Model.parseStatus(raw)
    if (parsed.ok === false && parsed.error) {
      lastError = parsed.error
      return
    }
    resticInstalled = parsed.restic_installed === true
    sources = parsed.sources
    excludes = parsed.excludes
    excludePaths = parsed.exclude_paths || []
    if (!sourcesEditing) {
      draftSources = copyStringList(sources)
      draftExcludes = copyStringList(excludes)
      draftExcludePaths = copyStringList(excludePaths)
    }
    destinations = parsed.destinations
    pendingFiles = Number(parsed.pending_files || 0)
    statusText = String(parsed.bar.status || "Omackup")
    statusDetail = String(parsed.bar.detail || "")
    alert = parsed.bar.alert === true
    if (parsed.error) lastError = parsed.error
    else if (!resticInstalled) lastError = "restic is not installed. Run: omarchy pkg add restic"
    else if (lastError.indexOf("restic is not installed") === 0) lastError = ""
    if (parsed.active_backup) handleBackupPayload(parsed.active_backup)
    evaluateNotifications()
    Qt.callLater(root.startPendingScheduledBackups)
  }

  function mergePendingIntoDestinations(results) {
    var byName = {}
    var i
    for (i = 0; i < (results || []).length; i++) {
      var item = results[i]
      if (!item || !item.name) continue
      byName[String(item.name)] = item
    }
    var next = []
    var total = 0
    for (i = 0; i < (destinations || []).length; i++) {
      var dest = destinations[i]
      var copy = {}
      var key
      for (key in dest) copy[key] = dest[key]
      var pending = byName[String(dest.name)]
      if (pending && pending.ok) {
        copy.pending_files = Number(pending.files_pending || 0)
        copy.pending_new = Number(pending.files_new || 0)
        copy.pending_changed = Number(pending.files_changed || 0)
        copy.pending_checked_at = Number(pending.checked_at || 0)
        copy.pending_since = Number(pending.pending_since || 0)
      }
      total += Number(copy.pending_files || 0)
      next.push(copy)
    }
    destinations = next
    pendingFiles = total
  }

  function sendNotify(title, body) {
    _notifyQueue = (_notifyQueue || []).concat([{ title: String(title || "Omackup"), body: String(body || "") }])
    kickNotify()
  }

  function kickNotify() {
    if (notifyProc.running || !_notifyQueue || _notifyQueue.length === 0) return
    var next = _notifyQueue[0]
    var rest = []
    var i
    for (i = 1; i < _notifyQueue.length; i++) rest.push(_notifyQueue[i])
    _notifyQueue = rest
    notifyProc.command = ["notify-send", "-a", "Omackup", "-u", "normal", next.title, next.body]
    notifyProc.running = true
  }

  function oldestPendingSince() {
    var oldest = 0
    var list = destinations || []
    var i
    for (i = 0; i < list.length; i++) {
      var dest = list[i]
      if (!dest || Number(dest.pending_files || 0) <= 0) continue
      var since = Number(dest.pending_since || dest.pending_checked_at || 0)
      if (since <= 0) continue
      if (oldest === 0 || since < oldest) oldest = since
    }
    return oldest
  }

  function destHasSchedule(dest) {
    if (!dest) return false
    if (dest.schedule && dest.schedule.enabled === true) return true
    return Model.scheduleEnabled(dest.schedule)
  }

  function overdueDestNames() {
    var names = []
    var list = destinations || []
    var i
    for (i = 0; i < list.length; i++) {
      var dest = list[i]
      if (!dest || dest.overdue !== true) continue
      if (dest.schedule_pending) continue
      if (!destHasSchedule(dest)) continue
      names.push(String(dest.display_name || dest.name || "destination"))
    }
    names.sort()
    return names
  }

  function pendingDestNames() {
    var names = []
    var list = destinations || []
    var i
    for (i = 0; i < list.length; i++) {
      var dest = list[i]
      if (!dest || dest.schedule_pending !== true) continue
      if (dest.schedule_pending_notified === true) continue
      names.push(String(dest.display_name || dest.name || "destination"))
    }
    names.sort()
    return names
  }

  readonly property bool hasSchedulePending: {
    var list = destinations || []
    var i
    for (i = 0; i < list.length; i++) {
      if (list[i] && list[i].schedule_pending === true) return true
    }
    return false
  }

  function notifyPending(total) {
    if (total <= 0) {
      lastNotifiedPending = 0
      lastNotifiedStaleSince = 0
      return
    }
    if (lastNotifiedPending === total) return
    if (lastNotifiedPending > 0 && total <= lastNotifiedPending) {
      lastNotifiedPending = total
      return
    }
    lastNotifiedPending = total
    if (!notifyOnUnbackedUp) return
    var msg = total === 1 ? "1 file needs backing up" : (total + " files need backing up")
    sendNotify("Unbacked-up changes", msg)
  }

  function evaluateNotifications() {
    var pendingNames = pendingDestNames()
    var pendingKey = pendingNames.join("\n")
    if (pendingNames.length === 0) {
      lastNotifiedPendingDestKey = ""
    } else if (notifyOnMissedBackup && pendingKey !== lastNotifiedPendingDestKey) {
      lastNotifiedPendingDestKey = pendingKey
      if (pendingNames.length === 1)
        sendNotify("Backup pending", pendingNames[0] + " is not connected. Backup will start when it is.")
      else
        sendNotify("Backup pending", pendingNames.length + " destinations are waiting to be connected")
    }

    var overdueNames = overdueDestNames()
    var overdueKey = overdueNames.join("\n")
    if (overdueNames.length === 0) {
      lastNotifiedOverdueKey = ""
    } else if (notifyOnMissedBackup && overdueKey !== lastNotifiedOverdueKey) {
      lastNotifiedOverdueKey = overdueKey
      if (overdueNames.length === 1)
        sendNotify("Backup missed", "Scheduled backup for " + overdueNames[0] + " did not run")
      else
        sendNotify("Backup missed", overdueNames.length + " scheduled backups did not run")
    }

    if (pendingFiles <= 0) {
      lastNotifiedStaleSince = 0
      return
    }
    if (!notifyOnStaleUnbackedUp) return
    var since = oldestPendingSince()
    if (since <= 0) return
    var ageSec = (Date.now() / 1000) - since
    if (ageSec < staleUnbackedUpHours * 3600) return
    if (lastNotifiedStaleSince === since) return
    lastNotifiedStaleSince = since
    var ageLabel = Model.notifyAgeLabel(staleUnbackedUpHours)
    var msg = pendingFiles === 1
      ? "1 file has been waiting more than " + ageLabel
      : (pendingFiles + " files have been waiting more than " + ageLabel)
    sendNotify("Unbacked-up changes", msg)
  }

  function refreshPendingChanges(force) {
    if (pendingScanning && !force) return
    if (backupActive || backupStarting) return
    pendingScanDebounce.restart()
  }

  function runPendingChangesScan() {
    if (root.dormant) return
    if (backupActive || backupStarting) return
    pendingScanSeq += 1
    var seq = pendingScanSeq
    pendingScanning = true
    pendingJobSeq = seq
    if (pendingProc.running) pendingProc.running = false
    pendingProc.command = [helperPath, "pending-changes"]
    pendingProc.running = true
  }

  function refresh() {
    if (refreshing) return
    refreshing = true
    run(["status"], function(payload) {
      applyStatus(JSON.stringify(payload))
      refreshing = false
    }, function(err) {
      lastError = elideStatus(err)
      refreshing = false
    }, true)
  }

  function refreshMounts(onDone) {
    if (mountsLoading) return
    mountsLoading = true
    run(["mounts"], function(payload) {
      mounts = payload.mounts || []
      mountsLoading = false
      if (onDone) onDone(mounts)
    }, function(err) {
      mountsLoading = false
      lastError = elideStatus(err)
      if (onDone) onDone([])
    })
  }

  function listDirs(path, dirsOnly) {
    var args = ["dirs", "--path", path]
    if (dirsOnly) args.push("--dirs-only")
    run(args, function(payload) {
      dirsPath = String(payload.path || path)
      dirsParent = String(payload.parent || "")
      dirs = payload.entries || []
    })
  }

  function copyMap(source) {
    var out = {}
    var key
    for (key in source) {
      if (source[key] !== undefined) out[key] = source[key]
    }
    return out
  }

  function sortTreeEntries(entries) {
    var list = (entries || []).slice()
    list.sort(function(a, b) {
      var aHidden = String(a && a.name ? a.name : "").charAt(0) === "."
      var bHidden = String(b && b.name ? b.name : "").charAt(0) === "."
      if (aHidden !== bHidden) return aHidden ? 1 : -1
      var aDir = a && a.type === "dir"
      var bDir = b && b.type === "dir"
      if (aDir !== bDir) return aDir ? -1 : 1
      return String(a && a.name ? a.name : "").toLowerCase().localeCompare(String(b && b.name ? b.name : "").toLowerCase())
    })
    return list
  }

  function rebuildTree() {
    treeModel.clear()
    if (!homePath) return
    treeModel.append({
      path: homePath,
      name: Model.basename(homePath) || homePath,
      type: "dir",
      depth: 0,
      expanded: expandedPaths[homePath] === true,
      hasChildren: true
    })
    if (expandedPaths[homePath] === true) appendTreeChildren(homePath, 1)
  }

  function appendTreeChildren(parent, depth) {
    var kids = sortTreeEntries(childrenByPath[parent] || [])
    for (var i = 0; i < kids.length; i++) {
      var kid = kids[i]
      var isDir = kid.type === "dir"
      var loaded = childrenByPath[kid.path] !== undefined
      treeModel.append({
        path: String(kid.path || ""),
        name: String(kid.name || ""),
        type: String(kid.type || "file"),
        depth: depth,
        expanded: expandedPaths[kid.path] === true,
        hasChildren: isDir && (!loaded || (childrenByPath[kid.path] || []).length > 0)
      })
      if (isDir && expandedPaths[kid.path] === true && loaded) {
        appendTreeChildren(kid.path, depth + 1)
      }
    }
  }

  function loadTreePath(path, seq, onOk, onErr) {
    run(["dirs", "--path", path, "--all"], function(payload) {
      if (seq !== treeRefreshSeq) return
      if (onOk) onOk(payload)
    }, function(err) {
      if (seq !== treeRefreshSeq) return
      if (onErr) onErr(err)
    })
  }

  function refreshHomeTree() {
    var home = String(Quickshell.env("HOME") || "")
    if (!homePath && home) homePath = home
    if (!homePath) {
      lastError = "Could not find your home folder"
      return
    }
    if (treeLoading) return

    var toReload = []
    if (childrenByPath[homePath] !== undefined || expandedPaths[homePath] === true)
      toReload.push(homePath)
    var key
    for (key in expandedPaths) {
      if (expandedPaths[key] === true && key !== homePath) toReload.push(key)
    }
    if (toReload.length === 0) toReload.push(homePath)

    treeRefreshSeq += 1
    var seq = treeRefreshSeq
    treeLoading = true
    reloadTreePaths(toReload, 0, seq, {})
  }

  function reloadTreePaths(paths, index, seq, nextCache) {
    if (seq !== treeRefreshSeq) return
    if (index >= paths.length) {
      childrenByPath = nextCache
      treeLoading = false
      rebuildTree()
      return
    }
    var path = paths[index]
    loadTreePath(path, seq, function(payload) {
      if (path === homePath) homePath = String(payload.path || homePath)
      nextCache[path] = sortTreeEntries(payload.entries || [])
      reloadTreePaths(paths, index + 1, seq, nextCache)
    }, function(err) {
      lastError = elideStatus(err)
      if (path !== homePath) {
        var nextExp = copyMap(expandedPaths)
        delete nextExp[path]
        expandedPaths = nextExp
      }
      reloadTreePaths(paths, index + 1, seq, nextCache)
    })
  }

  function ensureHomeTree() {
    var home = String(Quickshell.env("HOME") || "")
    if (!homePath && home) homePath = home
    if (!homePath) {
      lastError = "Could not find your home folder"
      return
    }
    rebuildTree()
    if (childrenByPath[homePath] !== undefined) return
    treeRefreshSeq += 1
    var seq = treeRefreshSeq
    treeLoading = true
    loadTreePath(homePath, seq, function(payload) {
      homePath = String(payload.path || homePath)
      var cache = copyMap(childrenByPath)
      cache[homePath] = sortTreeEntries(payload.entries || [])
      childrenByPath = cache
      treeLoading = false
      rebuildTree()
    }, function(err) {
      treeLoading = false
      lastError = elideStatus(err)
    })
  }

  function toggleExpand(path) {
    var exp = copyMap(expandedPaths)
    if (exp[path]) {
      delete exp[path]
      expandedPaths = exp
      rebuildTree()
      return
    }
    exp[path] = true
    expandedPaths = exp
    if (childrenByPath[path] !== undefined) {
      rebuildTree()
      return
    }
    rebuildTree()
    var seq = treeRefreshSeq
    treeLoading = true
    loadTreePath(path, seq, function(payload) {
      var cache = copyMap(childrenByPath)
      cache[path] = sortTreeEntries(payload.entries || [])
      childrenByPath = cache
      treeLoading = false
      rebuildTree()
    }, function(err) {
      treeLoading = false
      lastError = elideStatus(err)
    })
  }

  function applySelection(next) {
    if (!next) return
    if (next.blocked) {
      lastError = "This item stays excluded until you left-click the excluded folder itself"
      return
    }
    lastError = ""
    draftSources = copyStringList(next.sources || [])
    draftExcludePaths = copyStringList(next.excludePaths || [])
    if (!sourcesEditing) sourcesEditing = true
    refreshSelectionSize()
  }

  function includeItem(path) {
    applySelection(Model.leftClickItem(path, draftSources, draftExcludePaths, homePath))
  }

  function excludeItem(path) {
    applySelection(Model.rightClickItem(path, draftSources, draftExcludePaths, homePath))
  }

  function cycleItem(path) {
    applySelection(Model.cycleItem(path, draftSources, draftExcludePaths, homePath))
  }

  function setSources(paths) {
    applySelection({ sources: paths || [], excludePaths: draftExcludePaths })
  }

  function toggleSource(path) {
    includeItem(path)
  }

  function addSource(path) {
    run(["sources", "add", path], function() { refresh() })
  }

  function removeSource(path) {
    run(["sources", "remove", path], function() { refresh() })
  }

  function addExclude(pattern) {
    var value = String(pattern || "").trim()
    if (!value) return
    var next = copyStringList(draftExcludes)
    var i
    for (i = 0; i < next.length; i++) {
      if (next[i] === value) {
        refreshSelectionSize()
        return
      }
    }
    next.push(value)
    draftExcludes = next
    if (!sourcesEditing) sourcesEditing = true
    refreshSelectionSize()
  }

  function removeExclude(pattern) {
    var value = String(pattern || "")
    var next = []
    var i
    for (i = 0; i < (draftExcludes || []).length; i++) {
      if (String(draftExcludes[i]) !== value) next.push(String(draftExcludes[i]))
    }
    draftExcludes = next
    if (!sourcesEditing) sourcesEditing = true
    refreshSelectionSize()
  }

  function replaceExclude(oldPattern, newPattern) {
    var previous = String(oldPattern || "")
    var nextValue = String(newPattern || "").trim()
    if (!previous) return
    if (!nextValue) {
      removeExclude(previous)
      return
    }
    if (nextValue === previous) return
    var next = []
    var i
    var replaced = false
    for (i = 0; i < (draftExcludes || []).length; i++) {
      if (String(draftExcludes[i]) === previous) {
        if (!replaced && next.indexOf(nextValue) < 0) {
          next.push(nextValue)
          replaced = true
        }
        continue
      }
      next.push(String(draftExcludes[i]))
    }
    if (!replaced && next.indexOf(nextValue) < 0) next.push(nextValue)
    draftExcludes = next
    if (!sourcesEditing) sourcesEditing = true
    refreshSelectionSize()
  }

  function resetExcludes() {
    run(["exclude", "defaults"], function(payload) {
      draftExcludes = copyStringList(payload.excludes || [])
      if (!sourcesEditing) sourcesEditing = true
      refreshSelectionSize()
    }, function(err) {
      lastError = elideStatus(err)
    }, true)
  }

  function refreshSelectionSize() {
    selectionSizeLoading = true
    selectionSizeDebounce.restart()
  }

  function runSelectionSize() {
    if (root.dormant) return
    if (lastError === "Could not calculate selection size") lastError = ""
    selectionSizeSeq += 1
    var seq = selectionSizeSeq
    selectionSizeLoading = true
    var args = [helperPath, "selection-size", "--json", selectionOverrideJson()]
    if (selectionSizeProc.running) selectionSizeProc.running = false
    Qt.callLater(function() {
      if (seq !== root.selectionSizeSeq) return
      root.selectionSizeStdoutBuf = ""
      root.selectionSizeStderrBuf = ""
      root.selectionSizeJobSeq = seq
      selectionSizeProc.command = args
      selectionSizeProc.running = true
    })
  }

  function pickFolder(onPicked) {
    actionStatus = "Opening folder picker…"
    run(["pick-folder"], function(payload) {
      actionStatus = ""
      if (onPicked) onPicked(String(payload.path || ""))
    }, function(err, payload) {
      actionStatus = ""
      if (payload && payload.cancelled) return
      lastError = elideStatus(err)
    })
  }

  function addDestination(args, onDone) {
    actionStatus = "Saving destination…"
    run(args, function(payload) {
      actionStatus = ""
      refresh()
      if (onDone) onDone(payload.destination || payload)
    }, function(err) {
      actionStatus = ""
      lastError = elideStatus(err)
    })
  }

  function removeDestination(name, onDone) {
    run(["dest-remove", name], function() {
      refresh()
      if (onDone) onDone()
    })
  }

  function setKey(name, password, onDone) {
    var args = ["key-set", "--dest", name]
    if (password) args.push("--password", password)
    run(args, function(payload) {
      lastPassword = String(payload.password || "")
      lastWarning = String(payload.warning || "")
      refresh()
      if (onDone) onDone(payload)
    })
  }

  function showKey(name, onDone) {
    run(["key-show", "--dest", name], function(payload) {
      lastPassword = String(payload.password || "")
      lastWarning = String(payload.warning || "")
      if (onDone) onDone(payload)
    })
  }

  function copySensitive(text) {
    var value = String(text || "")
    if (!value) return false
    // --sensitive sets the password-manager hint so Omarchy's clipboard
    // history (and other managers that honor it) skip this paste.
    Quickshell.execDetached([
      "bash", "-c",
      "printf %s " + shellQuote(value) + " | wl-copy --type text/plain --sensitive"
    ])
    return true
  }

  function shellQuote(value) {
    return "'" + String(value || "").replace(/'/g, "'\\''") + "'"
  }

  function initDest(name, onDone) {
    actionStatus = "Initializing repository…"
    run(["init", "--dest", name], function(payload) {
      actionStatus = payload.already_initialized ? "Repository already initialized" : "Repository ready"
      actionStatusTimer.restart()
      refresh()
      if (onDone) onDone(payload)
    }, function(err) {
      actionStatus = ""
      lastError = elideStatus(err)
      refresh()
      if (onDone) onDone(null)
    })
  }

  property var pendingReachableSince: ({})

  function startPendingScheduledBackups() {
    if (root.dormant) return
    if (backupActive || backupStarting) return
    var list = destinations || []
    var now = Date.now()
    var next = {}
    var i
    for (i = 0; i < list.length; i++) {
      var dest = list[i]
      var name = dest && dest.name ? String(dest.name) : ""
      if (!dest || dest.schedule_pending !== true || !name) continue
      if (dest.reachable !== true) continue
      next[name] = pendingReachableSince[name] || now
      if (now - next[name] < 2500) continue
      pendingReachableSince = next
      backupNow(name, true)
      return
    }
    pendingReachableSince = next
  }

  function backupNow(name, scheduled) {
    if (root.dormant) return
    if (backupActive || backupStarting) {
      lastError = "A backup is already running"
      return
    }
    if (worker.running && !workerSilent) {
      lastError = "Omackup is busy — try again in a moment"
      return
    }
    lastError = ""
    backupSuccessDest = ""
    backupDest = String(name || "")
    backupPercent = 0
    backupEtaSeconds = -1
    backupBytesDone = 0
    backupTotalBytes = 0
    backupBytesPerSec = 0
    backupFilesDone = 0
    backupTotalFiles = 0
    backupDisconnected = false
    backupPhase = "calculating"
    backupCancelling = false
    actionStatus = ""
    if (pendingProc.running) {
      pendingScanSeq += 1
      pendingScanning = false
      pendingProc.running = false
    }
    var args = ["backup-start", "--dest", backupDest]
    if (scheduled) args.push("--scheduled")
    backupActive = true
    backupStarting = true
    startBackupFollow()
    run(args, function(payload) {
      if (payload && payload.skipped) {
        clearBackupUi()
        Qt.callLater(root.refresh)
        return
      }
      backupActive = true
      startBackupFollow()
    }, function(err) {
      backupStarting = false
      backupActive = false
      backupPhase = ""
      lastError = elideStatus(err)
    })
  }

  function clearBackupSuccess() {
    backupSuccessDest = ""
    backupSuccessTimer.stop()
  }

  function showBackupSuccess(name) {
    backupSuccessDest = String(name || "")
    if (backupSuccessDest) backupSuccessTimer.restart()
    else backupSuccessTimer.stop()
  }

  function cancelBackup() {
    if (!backupActive && !backupStarting) return
    backupCancelling = true
    startBackupFollow()
    run(["backup-cancel"], function() {}, function(err) {
      lastError = elideStatus(err)
    })
  }

  function startBackupFollow() {
    if (root.dormant) return
    if (backupFollowProc.running) return
    backupFollowProc.command = [helperPath, "backup-follow"]
    backupFollowProc.running = true
  }

  function handleBackupLine(line) {
    handleBackupPayload(Model.parseJson(line, null))
  }

  function handleBackupPayload(payload) {
    if (!payload) return
    if (payload.dest) backupDest = String(payload.dest)
    if (payload.event === "idle") {
      if (backupStarting || backupCancelling) return
      if (backupActive) clearBackupUi()
      return
    }
    if (backupCancelling && payload.event === "progress") return
    if (payload.event === "progress") {
      var totalBytes = Number(payload.total_bytes || 0)
      var totalFiles = Number(payload.total_files || 0)
      var percent = Number(payload.percent || 0)
      var phase = String(payload.phase || "")
      backupActive = true
      backupStarting = false
      if (phase === "disconnected") {
        backupDisconnected = true
        backupPhase = "disconnected"
        backupBytesPerSec = 0
        backupEtaSeconds = -1
        if (backupTotalBytes <= 0) backupTotalBytes = totalBytes
        if (backupTotalFiles <= 0) backupTotalFiles = totalFiles
        if (totalBytes > 0 && Number(payload.bytes_done || 0) > 0) {
          var frozen = Math.min(1, Number(payload.bytes_done) / (backupTotalBytes || totalBytes))
          if (frozen > backupPercent) backupPercent = frozen
        } else if (percent > backupPercent) {
          backupPercent = percent
        }
        return
      }
      backupDisconnected = false
      if (phase === "running" || totalBytes > 0 || percent > 0)
        backupPhase = "running"
      else if ((phase === "calculating" || phase === "starting") && (backupTotalBytes > 0 || backupBytesDone > 0))
        backupPhase = "running"
      else if (phase === "calculating" || phase === "starting")
        backupPhase = "calculating"
      else
        backupPhase = backupPhase === "running" ? "running" : "calculating"
      backupEtaSeconds = payload.eta_seconds === undefined || payload.eta_seconds === null
        ? -1
        : Number(payload.eta_seconds)
      backupBytesDone = Number(payload.bytes_done || 0)
      backupBytesPerSec = Number(payload.bytes_per_second || 0)
      backupFilesDone = Number(payload.files_done || 0)
      if (backupPhase === "calculating") {
        backupPercent = 0
        backupTotalBytes = 0
        backupTotalFiles = 0
      } else {
        if (backupTotalBytes <= 0) backupTotalBytes = totalBytes
        if (backupTotalFiles <= 0) backupTotalFiles = totalFiles
        if (backupTotalBytes > 0) backupPercent = Math.min(1, backupBytesDone / backupTotalBytes)
        else if (backupTotalFiles > 0) backupPercent = Math.min(1, backupFilesDone / backupTotalFiles)
        else backupPercent = percent
      }
      return
    }
    if (payload.event === "warning" && payload.error) {
      lastError = elideStatus(payload.error)
      return
    }
    if (payload.event === "done") {
      backupStarting = false
      backupCancelling = false
      if (payload.cancelled) {
        actionStatus = "Backup cancelled"
        actionStatusTimer.restart()
        clearBackupUi()
        return
      }
      if (payload.ok) {
        backupPercent = 1
        backupEtaSeconds = 0
        backupPhase = "done"
        showBackupSuccess(backupDest)
        clearBackupUi()
        refresh()
        refreshPendingChanges(true)
      } else {
        backupPhase = "failed"
        lastError = elideStatus(payload.error || "Backup failed")
        actionStatus = ""
        clearBackupUi()
        refresh()
      }
    }
  }

  function clearBackupUi() {
    backupActive = false
    backupStarting = false
    backupCancelling = false
    backupPhase = ""
    backupDisconnected = false
    backupFilesDone = 0
    backupTotalFiles = 0
    Qt.callLater(root.kick)
  }

  function loadSnapshots(name, onDone) {
    actionStatus = "Reading snapshots…"
    run(["snapshots", "--dest", name], function(payload) {
      actionStatus = ""
      snapshots = payload.snapshots || []
      if (onDone) onDone(payload.snapshots || [])
    })
  }

  function loadListing(name, snapshot, path, onDone, onErr) {
    actionStatus = "Reading files…"
    run(["ls", "--dest", name, "--snapshot", snapshot, "--path", path], function(payload) {
      actionStatus = ""
      listingPath = String(payload.path || path)
      listing = payload.entries || []
      if (payload.missing && path && path !== "/") {
        loadListing(name, snapshot, Model.parentPath(path), onDone, onErr)
        return
      }
      if (onDone) onDone(payload)
    }, function(err) {
      actionStatus = ""
      if (onErr) onErr(err)
    })
  }

  function openRestore(name) {
    var dest = String(name || "")
    if (!dest) return
    if (!destIsReachable(dest)) {
      lastError = "Destination is not reachable"
      return
    }
    restoreDest = dest
    restoreDestDisplay = destDisplayName(dest)
    restoreSnapshot = "latest"
    restoreSnapIndex = 0
    restoreEntryIndex = 0
    restoreFocus = "timeline"
    restoreSelected = null
    preview = Model.emptyPreview()
    previewLoading = false
    listing = []
    listingPath = "/"
    restoreOpen = true
    loadSnapshots(dest, function(items) {
      restoreSnapIndex = 0
      if (!items || !items.length) return
      selectRestoreSnapshot(items[0], "/")
    })
  }

  function closeRestore() {
    restoreOpen = false
    previewLoading = false
    previewSeq += 1
    if (previewProc.running) previewProc.running = false
    preview = Model.emptyPreview()
  }

  function selectRestoreSnapshot(snap, path) {
    if (!restoreDest || !snap) return
    restoreSnapshot = String(snap.id || snap.full_id || "latest")
    var list = snapshots || []
    var i
    restoreSnapIndex = 0
    for (i = 0; i < list.length; i++) {
      if (String(list[i].id || list[i].full_id) === restoreSnapshot) {
        restoreSnapIndex = i
        break
      }
    }
    restoreFocus = "timeline"
    var selected = restoreSelected
    openRestoreFolder(path || listingPath || "/", true)
    if (selected && selected.type !== "dir" && selected.path)
      loadPreview(restoreDest, restoreSnapshot, selected.path)
  }

  function openRestoreFolder(path, keepSelection) {
    if (!restoreDest) return
    loadListing(restoreDest, restoreSnapshot, path || "/", function(payload) {
      restoreEntryIndex = 0
      if (!keepSelection) {
        restoreSelected = {
          type: "dir",
          name: Model.basename(listingPath),
          path: listingPath === "/" ? "" : listingPath,
          size: 0
        }
        preview = {
          kind: "dir",
          name: listingPath === "/" ? "Backups" : Model.basename(listingPath),
          path: listingPath,
          size: 0,
          mtime: "",
          text: "",
          image_path: ""
        }
        previewLoading = false
      }
    })
  }

  function goRestoreUp() {
    if (!listingPath || listingPath === "/") return
    openRestoreFolder(Model.parentPath(listingPath))
  }

  function selectRestoreEntry(entry, index) {
    if (!entry) return
    if (index !== undefined && index >= 0) restoreEntryIndex = index
    restoreSelected = entry
    restoreFocus = "browser"
    if (entry.type === "dir") {
      previewLoading = false
      preview = {
        kind: "dir",
        name: entry.name,
        path: entry.path,
        size: 0,
        mtime: String(entry.mtime || ""),
        text: "",
        image_path: ""
      }
      return
    }
    loadPreview(restoreDest, restoreSnapshot, entry.path)
  }

  function activateRestoreEntry(entry, index) {
    if (!entry) return
    if (entry.type === "dir") {
      if (index !== undefined && index >= 0) restoreEntryIndex = index
      openRestoreFolder(entry.path)
      return
    }
    selectRestoreEntry(entry, index)
  }

  function restoreCurrent() {
    if (!restoreDest) return
    var path = ""
    if (restoreSelected && restoreSelected.path)
      path = restoreSelected.path
    else if (listingPath && listingPath !== "/")
      path = listingPath
    restorePath(restoreDest, restoreSnapshot, path)
  }

  function loadPreview(name, snapshot, path) {
    previewSeq += 1
    var seq = previewSeq
    previewJobSeq = seq
    previewLoading = true
    preview = {
      kind: "",
      name: Model.basename(path),
      path: path,
      size: 0,
      mtime: "",
      text: "",
      image_path: ""
    }
    if (previewProc.running) previewProc.running = false
    previewProc.command = [helperPath, "preview", "--dest", name, "--snapshot", snapshot, "--path", path]
    previewProc.running = true
  }

  function restorePath(name, snapshot, path) {
    actionStatus = "Restoring…"
    var args = ["restore", "--dest", name, "--snapshot", snapshot]
    if (path) args.push("--path", path)
    run(args, function(payload) {
      lastOpened = String(payload.opened || payload.target || "")
      actionStatus = "Restored to ~/Restored"
      actionStatusTimer.restart()
      if (lastOpened) run(["open", lastOpened], function() {}, function() {}, true)
    })
  }

  function setSchedule(name, spec) {
    var args = ["schedule-set", "--dest", name]
    if (spec) args.push("--schedule", typeof spec === "string" ? spec : JSON.stringify(spec))
    else args.push("--manual")
    run(args, function() { refresh() })
  }

  function setEnv(name, pairs, onDone) {
    if (!pairs || pairs.length === 0) {
      if (onDone) onDone({})
      return
    }
    run(["env-set", "--dest", name].concat(pairs), function(payload) {
      if (onDone) onDone(payload)
    }, function(err) {
      lastError = elideStatus(err)
    })
  }

  Component.onCompleted: root.startBackupFollow()

  onDormantChanged: {
    if (root.dormant) {
      if (backupFollowProc.running) backupFollowProc.running = false
    } else {
      root.startBackupFollow()
    }
  }

  Timer {
    id: selectionSizeDebounce
    interval: 350
    repeat: false
    onTriggered: root.runSelectionSize()
  }

  Timer {
    id: selectionSizeSpinnerTimer
    interval: 90
    repeat: true
    running: !root.dormant && root.selectionSizeLoading
    onTriggered: root.selectionSizeSpinnerIndex = (root.selectionSizeSpinnerIndex + 1) % root.selectionSizeSpinnerChars.length
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: !root.dormant
    triggeredOnStart: true
    onTriggered: {
      root.startBackupFollow()
      root.refresh()
    }
  }

  Timer {
    id: reconnectPollTimer
    interval: 3000
    repeat: true
    running: !root.dormant && (root.panelOpen || root.hasSchedulePending)
    onTriggered: {
      if (!root.refreshing) root.refresh()
    }
  }

  Timer {
    id: pendingScanDebounce
    interval: 1500
    repeat: false
    onTriggered: root.runPendingChangesScan()
  }

  Timer {
    id: pendingScanTimer
    interval: root.pendingScanIntervalSec * 1000
    repeat: true
    running: !root.dormant
    triggeredOnStart: true
    onTriggered: root.refreshPendingChanges(false)
  }

  Timer {
    id: backupFollowRestart
    interval: 400
    repeat: false
    onTriggered: root.startBackupFollow()
  }

  Timer {
    id: backupSuccessTimer
    interval: 10000
    repeat: false
    onTriggered: root.clearBackupSuccess()
  }

  Timer {
    id: actionStatusTimer
    interval: 2400
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Process {
    id: notifyProc
    running: false
    command: []
    onExited: root.kickNotify()
  }

  Process {
    id: pendingProc
    running: false
    command: []
    stdout: StdioCollector {
      id: pendingStdout
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: pendingStderr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      var seq = root.pendingJobSeq
      if (seq !== root.pendingScanSeq) return
      root.pendingScanning = false
      var stdout = String(pendingStdout.text || "")
      var payload = Model.parseJson(stdout, null)
      if (exitCode !== 0 || !payload || payload.ok === false) return
      if (payload.skipped === true) return
      var previous = root.pendingFiles
      root.mergePendingIntoDestinations(payload.destinations || [])
      if (payload.pending_files !== undefined) root.pendingFiles = Number(payload.pending_files || 0)
      if (root.pendingFiles > 0 && previous <= 0) root.notifyPending(root.pendingFiles)
      else if (root.pendingFiles > previous && previous >= 0) root.notifyPending(root.pendingFiles)
      else if (root.pendingFiles <= 0) root.lastNotifiedPending = 0
      root.evaluateNotifications()
      root.refresh()
    }
  }

  Process {
    id: backupFollowProc
    running: false
    command: []
    stdout: SplitParser {
      onRead: function(line) { root.handleBackupLine(line) }
    }
    stderr: StdioCollector {
      waitForEnd: true
    }
    onExited: function() {
      if (!root.dormant) backupFollowRestart.restart()
    }
  }

  Process {
    id: selectionSizeProc
    running: false
    command: []
    stdout: StdioCollector {
      id: selectionSizeStdout
      waitForEnd: true
      onStreamFinished: root.selectionSizeStdoutBuf = text
    }
    stderr: StdioCollector {
      id: selectionSizeStderr
      waitForEnd: true
      onStreamFinished: root.selectionSizeStderrBuf = text
    }
    onExited: function(exitCode) {
      var seq = root.selectionSizeJobSeq
      if (seq !== root.selectionSizeSeq) return
      var stdout = String(selectionSizeStdout.text || root.selectionSizeStdoutBuf || "")
      var stderr = String(selectionSizeStderr.text || root.selectionSizeStderrBuf || "")
      var payload = Model.parseJson(stdout, null)
      if (exitCode === 0 && payload && payload.ok !== false && payload.skipped !== true) {
        root.selectionBytes = Number(payload.bytes || 0)
        root.selectionFiles = Number(payload.files || 0)
      }
      root.selectionSizeLoading = false
    }
  }

  Process {
    id: previewProc
    running: false
    command: []
    stdout: StdioCollector {
      id: previewStdout
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: previewStderr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      var seq = root.previewJobSeq
      if (seq !== root.previewSeq) return
      root.previewLoading = false
      var stdout = String(previewStdout.text || "")
      var payload = Model.parseJson(stdout, null)
      if (exitCode !== 0 || !payload || payload.ok === false) {
        root.preview = {
          kind: "unsupported",
          name: root.preview && root.preview.name ? root.preview.name : "",
          path: root.preview && root.preview.path ? root.preview.path : "",
          size: 0,
          mtime: "",
          text: "",
          image_path: ""
        }
        return
      }
      root.preview = {
        kind: String(payload.kind || "binary"),
        name: String(payload.name || ""),
        path: String(payload.path || ""),
        size: Number(payload.size || 0),
        mtime: String(payload.mtime || ""),
        text: String(payload.text || ""),
        image_path: String(payload.image_path || "")
      }
    }
  }

  RestoreWindow {
    omackup: root
  }

  Process {
    id: worker
    running: false
    command: []
    stdout: StdioCollector {
      id: workerStdout
      waitForEnd: true
      onStreamFinished: root._stdout = text
    }
    stderr: StdioCollector {
      id: workerStderr
      waitForEnd: true
      onStreamFinished: root._stderr = text
    }
    onExited: function(exitCode) {
      var stdout = String(workerStdout.text || root._stdout || "")
      var stderr = String(workerStderr.text || root._stderr || "")
      var payload = Model.parseJson(stdout, null)
      var current = root._current
      root._current = null
      root.workerSilent = false
      if (exitCode === 0 && payload) {
        if (current && current.onOk) current.onOk(payload)
      } else {
        var message = ""
        if (payload && payload.error) message = payload.error
        else message = stderr || stdout || "Omackup command failed"
        if (!current || !current.silent) root.lastError = root.elideStatus(message)
        if (current && current.onErr) current.onErr(message, payload)
      }
      Qt.callLater(root.kick)
    }
  }
}
