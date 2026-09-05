function parseJson(raw, fallback) {
  var text = String(raw || "").trim()
  if (text === "") return fallback
  try {
    var parsed = JSON.parse(text)
    if (!parsed || typeof parsed !== "object") return fallback
    return parsed
  } catch (e) {
    return fallback
  }
}

function defaultStatus() {
  return {
    ok: true,
    restic_installed: false,
    sources: ["~"],
    excludes: [],
    exclude_paths: [],
    destinations: [],
    bar: {
      alert: false,
      status: "Checking…",
      detail: ""
    }
  }
}

function parseStatus(raw) {
  var parsed = parseJson(raw, null)
  if (!parsed) {
    var failed = defaultStatus()
    failed.ok = false
    failed.error = "Failed to parse Omackup status"
    return failed
  }
  parsed.sources = Array.isArray(parsed.sources) ? parsed.sources : ["~"]
  parsed.excludes = Array.isArray(parsed.excludes) ? parsed.excludes : []
  parsed.exclude_paths = Array.isArray(parsed.exclude_paths) ? parsed.exclude_paths : []
  parsed.destinations = Array.isArray(parsed.destinations) ? parsed.destinations : []
  parsed.bar = parsed.bar && typeof parsed.bar === "object" ? parsed.bar : defaultStatus().bar
  return parsed
}

function parseList(raw, key) {
  var parsed = parseJson(raw, {})
  if (!parsed || parsed.ok === false) return []
  return Array.isArray(parsed[key]) ? parsed[key] : []
}

function formatClock(date, use24Hour) {
  var hours = date.getHours()
  var minutes = date.getMinutes()
  var pad = function(n) { return n < 10 ? "0" + n : String(n) }
  if (use24Hour !== false) return pad(hours) + ":" + pad(minutes)
  var suffix = hours >= 12 ? "PM" : "AM"
  var h12 = hours % 12
  if (h12 === 0) h12 = 12
  return h12 + ":" + pad(minutes) + " " + suffix
}

function formatWhen(ts, use24Hour) {
  var value = Number(ts || 0)
  if (!isFinite(value) || value <= 0) return "never"
  var date = new Date(value * 1000)
  var now = new Date()
  var pad = function(n) { return n < 10 ? "0" + n : String(n) }
  var clock = formatClock(date, use24Hour)
  if (date.toDateString() === now.toDateString()) return "Today, " + clock
  var yesterday = new Date(now.getTime() - 86400000)
  if (date.toDateString() === yesterday.toDateString()) return "Yesterday, " + clock
  return date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate()) + " " + clock
}

function formatBytes(bytes) {
  var value = Number(bytes || 0)
  if (!isFinite(value) || value <= 0) return "0 B"
  var units = ["B", "KB", "MB", "GB", "TB"]
  var index = 0
  while (value >= 1000 && index < units.length - 1) {
    value = value / 1000
    index++
  }
  var decimals = value >= 100 || index === 0 ? 0 : (value >= 10 ? 1 : 2)
  return value.toFixed(decimals).replace(/\.0+$/, "").replace(/(\.\d)0$/, "$1") + " " + units[index]
}

function formatDuration(seconds) {
  var value = Math.max(0, Math.round(Number(seconds) || 0))
  if (!isFinite(value)) return ""
  if (value < 60) return value + "s"
  var mins = Math.floor(value / 60)
  var secs = value % 60
  if (mins < 60) return secs > 0 ? mins + "m " + secs + "s" : mins + "m"
  var hours = Math.floor(mins / 60)
  mins = mins % 60
  return mins > 0 ? hours + "h " + mins + "m" : hours + "h"
}

function formatCompactNumber(value, decimals) {
  var places = decimals || 0
  var text = Number(value).toFixed(places)
  return text.replace(/\.0+$/, "").replace(/(\.\d)0$/, "$1")
}

function formatCompactSize(bytes) {
  var value = Number(bytes || 0)
  if (!isFinite(value) || value < 0) value = 0
  if (value < 1000) return Math.round(value) + "B"
  var units = ["K", "M", "G", "T"]
  var index = 0
  value = value / 1000
  while (value >= 1000 && index < units.length - 1) {
    value = value / 1000
    index++
  }
  var decimals = value >= 100 ? 0 : 1
  return formatCompactNumber(value, decimals) + units[index]
}

function formatRate(bytesPerSec) {
  var value = Number(bytesPerSec || 0)
  if (!isFinite(value) || value <= 0) return "0mb/s"
  var units = ["b/s", "kb/s", "mb/s", "gb/s", "tb/s"]
  var index = 0
  while (value >= 1000 && index < units.length - 1) {
    value = value / 1000
    index++
  }
  var decimals = value >= 100 || index === 0 || index === 2 ? 0 : 1
  return formatCompactNumber(value, decimals) + units[index]
}

function rateLimitBpsFromKibs(kibs) {
  var value = Number(kibs || 0)
  if (!isFinite(value) || value <= 0) return 0
  return Math.round(value * 1024)
}

function rateLimitKibsFromBps(bps) {
  var value = Number(bps || 0)
  if (!isFinite(value) || value <= 0) return 0
  return Math.max(1, Math.round(value / 1024))
}

function formatRateLimit(kibs) {
  return formatRate(rateLimitBpsFromKibs(kibs))
}

function formatRateLimitField(kibs) {
  var value = Number(kibs || 0)
  if (!isFinite(value) || value <= 0) return "0"
  return formatRateLimit(value)
}

function parseRateLimit(text) {
  var raw = String(text || "").trim().toLowerCase()
  if (raw === "" || raw === "0" || raw === "unlimited" || raw === "none") {
    return { ok: true, kibs: 0 }
  }
  raw = raw.replace(/\s+/g, "").replace(/\/s$/, "")
  var match = raw.match(/^([0-9]*\.?[0-9]+)(tb|gb|mb|kb|t|g|m|k|b)?$/)
  if (!match) {
    return { ok: false, kibs: 0, error: "Rate limit should look like 10mb/s, or 0 for unlimited" }
  }
  var amount = Number(match[1])
  if (!isFinite(amount) || amount < 0) {
    return { ok: false, kibs: 0, error: "Rate limit should look like 10mb/s, or 0 for unlimited" }
  }
  if (amount === 0) return { ok: true, kibs: 0 }
  var unit = match[2] || "mb"
  var multiplier = 1000000
  if (unit === "b") multiplier = 1
  else if (unit === "k" || unit === "kb") multiplier = 1000
  else if (unit === "m" || unit === "mb") multiplier = 1000000
  else if (unit === "g" || unit === "gb") multiplier = 1000000000
  else if (unit === "t" || unit === "tb") multiplier = 1000000000000
  var kibs = rateLimitKibsFromBps(amount * multiplier)
  if (kibs <= 0) {
    return { ok: false, kibs: 0, error: "Rate limit is too small" }
  }
  return { ok: true, kibs: kibs }
}

function formatEtaClock(seconds) {
  var value = Number(seconds)
  if (!isFinite(value) || value < 0) return ""
  value = Math.round(value)
  if (value < 60) return value + "s"
  var hours = Math.floor(value / 3600)
  var mins = Math.floor((value % 3600) / 60)
  var secs = value % 60
  if (hours > 0) return mins > 0 ? hours + "h" + mins + "m" : hours + "h"
  if (value >= 600) return mins + "m"
  return secs > 0 ? mins + "m" + secs + "s" : mins + "m"
}

function formatBackupStats(percent, filesDone, filesTotal, bytesDone, bytesTotal, bytesPerSec, etaSeconds) {
  var pct = Math.round(Math.max(0, Math.min(1, Number(percent) || 0)) * 100)
  var eta = formatEtaClock(etaSeconds)
  return pct + "% - "
    + Math.max(0, Math.round(Number(filesDone) || 0)) + "/"
    + Math.max(0, Math.round(Number(filesTotal) || 0)) + " - "
    + formatCompactSize(bytesDone) + "/" + formatCompactSize(bytesTotal) + " - "
    + formatRate(bytesPerSec)
    + (eta ? " - " + eta : "")
}

function destMeta(dest, use24Hour) {
  if (!dest) return ""
  if (dest.failed) return dest.last_error || "Last backup failed"
  if (dest.overdue) return "Overdue · last " + formatWhen(dest.last_success, use24Hour)
  if (dest.last_success) return formatWhen(dest.last_success, use24Hour)
  return dest.has_password ? "Never backed up" : "Needs a password"
}

function pendingLabel(dest) {
  if (!dest) return ""
  var pending = Number(dest.pending_files || 0)
  if (pending <= 0) return ""
  var neu = Number(dest.pending_new || 0)
  var changed = Number(dest.pending_changed || 0)
  if (neu > 0 && changed > 0) return pending + " files to back up (" + neu + " new · " + changed + " changed)"
  if (neu > 0) return neu + (neu === 1 ? " new file to back up" : " new files to back up")
  if (changed > 0) return changed + (changed === 1 ? " changed file to back up" : " changed files to back up")
  return pending + (pending === 1 ? " file to back up" : " files to back up")
}

function destNameFromLabel(label) {
  var cleaned = String(label || "").trim().toLowerCase()
  var out = ""
  var i
  for (i = 0; i < cleaned.length; i++) {
    var ch = cleaned.charAt(i)
    if ((ch >= "a" && ch <= "z") || (ch >= "0" && ch <= "9") || ch === "-" || ch === "_") out += ch
    else out += "-"
  }
  out = out.replace(/-+/g, "-").replace(/^-+/, "").replace(/-+$/, "")
  return out
}

function destGlyph(kind) {
  if (kind === "nas") return "󰒍"
  if (kind === "cloud") return "󰅟"
  return "󰕓"
}

function entryGlyph(entry) {
  if (!entry) return "󰈔"
  if (entry.type === "dir") return "󰉋"
  var name = String(entry.name || "").toLowerCase()
  var index = name.lastIndexOf(".")
  var ext = index >= 0 ? name.substring(index + 1) : ""
  if (["jpg", "jpeg", "png", "gif", "webp", "svg"].indexOf(ext) >= 0) return "󰋩"
  if (["mp4", "mov", "mkv", "webm"].indexOf(ext) >= 0) return "󰈫"
  if (["pdf", "txt", "md", "doc", "docx"].indexOf(ext) >= 0) return "󰈙"
  return "󰈔"
}

function snapshotLabel(snap) {
  if (!snap) return "Snapshot"
  var raw = String(snap.time || "")
  if (!raw) return String(snap.id || "latest")
  var date = new Date(raw)
  if (isNaN(date.getTime())) return raw
  var pad = function(n) { return n < 10 ? "0" + n : String(n) }
  return date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate()) + " " + pad(date.getHours()) + ":" + pad(date.getMinutes())
}

function scheduleOptions() {
  return [
    { value: "", label: "Manual only" },
    { value: "*-*-* 03:00:00", label: "Every night at 03:00" },
    { value: "*-*-* 12:00:00", label: "Every day at 12:00" },
    { value: "*-*-* 18:00:00", label: "Every day at 18:00" },
    { value: "Mon..Fri *-*-* 03:00:00", label: "Weekdays at 03:00" }
  ]
}

function scheduleLabel(schedule) {
  var value = String(schedule || "")
  var options = scheduleOptions()
  var i
  for (i = 0; i < options.length; i++) {
    if (String(options[i].value) === value) return String(options[i].label)
  }
  return value || "Manual only"
}

function cloudBackends() {
  return [
    { value: "s3", label: "Amazon S3 / compatible" },
    { value: "b2", label: "Backblaze B2" }
  ]
}

function timeFormatOptions() {
  return [
    { value: "12", label: "12-hour (3:04 PM)" },
    { value: "24", label: "24-hour (15:04)" }
  ]
}

function notifyAgeOptions() {
  return [
    { value: "1", label: "1 hour" },
    { value: "6", label: "6 hours" },
    { value: "12", label: "12 hours" },
    { value: "24", label: "1 day" },
    { value: "48", label: "2 days" },
    { value: "168", label: "1 week" }
  ]
}

function notifyAgeLabel(hours) {
  var value = String(hours || "")
  var options = notifyAgeOptions()
  var i
  for (i = 0; i < options.length; i++) {
    if (String(options[i].value) === value) return String(options[i].label)
  }
  var n = Number(hours || 0)
  if (!isFinite(n) || n <= 0) return "1 day"
  if (n === 1) return "1 hour"
  if (n < 24) return n + " hours"
  if (n === 24) return "1 day"
  if (n % 24 === 0) {
    var days = n / 24
    return days === 1 ? "1 day" : (days + " days")
  }
  return n + " hours"
}

function basename(path) {
  var value = String(path || "").replace(/\/+$/, "")
  var parts = value.split("/")
  return parts[parts.length - 1] || value || "/"
}

function parentPath(path) {
  var value = String(path || "").replace(/\/+$/, "")
  var index = value.lastIndexOf("/")
  if (index <= 0) return "/"
  return value.substring(0, index) || "/"
}

function expandUser(path, home) {
  var value = String(path || "").replace(/\/+$/, "")
  var root = String(home || "").replace(/\/+$/, "")
  if (value === "" || value === "~") return root || value
  if (value.indexOf("~/") === 0) return (root || "") + value.substring(1)
  return value
}

function storeSource(path, home) {
  var abs = expandUser(path, home)
  var root = String(home || "").replace(/\/+$/, "")
  if (abs === root) return "~"
  return abs
}

function isAncestorPath(parent, child, home) {
  var p = expandUser(parent, home)
  var c = expandUser(child, home)
  if (!p || !c) return false
  return c === p || c.indexOf(p + "/") === 0
}

function sourceCheckState(path, sources, home) {
  var abs = expandUser(path, home)
  var list = sources || []
  var i
  for (i = 0; i < list.length; i++) {
    if (expandUser(list[i], home) === abs) return "on"
  }
  for (i = 0; i < list.length; i++) {
    if (isAncestorPath(list[i], abs, home)) return "inherited"
  }
  for (i = 0; i < list.length; i++) {
    if (isAncestorPath(abs, list[i], home)) return "partial"
  }
  return "off"
}

function isExactPath(path, list, home) {
  var abs = expandUser(path, home)
  var i
  for (i = 0; i < (list || []).length; i++) {
    if (expandUser(list[i], home) === abs) return true
  }
  return false
}

function isExcluded(path, excludePaths, home) {
  var abs = expandUser(path, home)
  var i
  for (i = 0; i < (excludePaths || []).length; i++) {
    if (isAncestorPath(excludePaths[i], abs, home)) return true
  }
  return false
}

function pathRelativeToHome(path, home) {
  var abs = expandUser(path, home)
  var root = expandUser("~", home)
  if (!abs) return ""
  if (!root) return abs.charAt(0) === "/" ? abs.substring(1) : abs
  if (abs === root) return ""
  if (abs.indexOf(root + "/") === 0) return abs.substring(root.length + 1)
  if (abs.charAt(0) === "/") return abs.substring(1)
  return abs
}

function globSpecialToRegExp(pattern) {
  var out = ""
  var i = 0
  var n = String(pattern || "").length
  while (i < n) {
    var c = pattern.charAt(i)
    if (c === "*" && pattern.charAt(i + 1) === "*") {
      if (i + 2 >= n) {
        if (out.length && out.charAt(out.length - 1) === "/") {
          out = out.substring(0, out.length - 1) + "(?:/.*)?"
        } else {
          out += ".*"
        }
        i += 2
        continue
      }
      if (pattern.charAt(i + 2) === "/") {
        out += "(?:.*/)?"
        i += 3
        continue
      }
      out += ".*"
      i += 2
      continue
    }
    if (c === "*") {
      out += "[^/]*"
      i += 1
      continue
    }
    if (c === "?") {
      out += "[^/]"
      i += 1
      continue
    }
    if (c === "[") {
      var close = pattern.indexOf("]", i + 1)
      if (close < 0) {
        out += "\\["
        i += 1
        continue
      }
      out += pattern.substring(i, close + 1)
      i = close + 1
      continue
    }
    if ("+()|^$.{}\\".indexOf(c) >= 0) out += "\\"
    out += c
    i += 1
  }
  return out
}

function excludePatternMatches(pattern, relPath, isDir) {
  var raw = String(pattern || "").trim()
  if (raw === "" || raw.charAt(0) === "#" || raw.charAt(0) === "!") return false

  var dirOnly = raw.charAt(raw.length - 1) === "/"
  var body = dirOnly ? raw.replace(/\/+$/, "") : raw
  if (dirOnly && !isDir) return false

  var anchored = body.charAt(0) === "/"
  if (anchored) body = body.substring(1)

  var anywhere = !anchored && body.indexOf("/") < 0
  var rx
  try {
    var inner = globSpecialToRegExp(body)
    rx = new RegExp(anywhere ? "(^|/)" + inner + "$" : "^" + inner + "$")
  } catch (e) {
    return false
  }
  return rx.test(String(relPath || ""))
}

function firstMatchingExcludePattern(relPath, isDir, excludes) {
  var i
  var pattern
  for (i = 0; i < (excludes || []).length; i++) {
    pattern = excludes[i]
    if (excludePatternMatches(pattern, relPath, isDir)) return String(pattern)
  }
  return ""
}

function matchingExcludePattern(path, type, excludes, home) {
  var rel = pathRelativeToHome(path, home)
  var isDir = type === "dir"
  var direct = firstMatchingExcludePattern(rel, isDir, excludes)
  if (direct) return direct
  if (!rel) return ""
  var parts = rel.split("/")
  var prefix = ""
  var i
  for (i = 0; i < parts.length - 1; i++) {
    prefix = prefix ? prefix + "/" + parts[i] : parts[i]
    var match = firstMatchingExcludePattern(prefix, true, excludes)
    if (match) return match
  }
  return ""
}

function itemMark(path, sources, excludePaths, home) {
  if (isExcluded(path, excludePaths, home)) return "excluded"
  var state = sourceCheckState(path, sources, home)
  if (state === "on" || state === "inherited") return "included"
  if (state === "partial") return "partial"
  return "off"
}

function removeMatching(list, path, home, descendantsToo) {
  var abs = expandUser(path, home)
  var next = []
  var i
  var item
  for (i = 0; i < (list || []).length; i++) {
    item = list[i]
    if (expandUser(item, home) === abs) continue
    if (descendantsToo && isAncestorPath(abs, item, home)) continue
    next.push(item)
  }
  return next
}

function addUniquePath(list, path, home) {
  var stored = storeSource(path, home)
  var next = removeMatching(list, path, home, false)
  next.push(stored)
  return next
}

function addSourcePath(sources, path, home) {
  var abs = expandUser(path, home)
  var next = []
  var i
  var source
  for (i = 0; i < (sources || []).length; i++) {
    source = sources[i]
    if (isAncestorPath(source, abs, home) || isAncestorPath(abs, source, home)) continue
    next.push(source)
  }
  next.push(storeSource(abs, home))
  return next
}

function leftClickItem(path, sources, excludePaths, home) {
  var currentSources = sources || []
  var currentExcludes = excludePaths || []
  if (isExactPath(path, currentExcludes, home)) {
    var nextExcludes = removeMatching(currentExcludes, path, home, false)
    var covered = sourceCheckState(path, currentSources, home)
    return {
      sources: (covered === "on" || covered === "inherited") ? currentSources.slice() : addSourcePath(currentSources, path, home),
      excludePaths: nextExcludes
    }
  }
  if (isExcluded(path, currentExcludes, home)) {
    return { sources: currentSources.slice(), excludePaths: currentExcludes.slice(), blocked: true }
  }
  var state = sourceCheckState(path, currentSources, home)
  if (state === "on") {
    return {
      sources: removeMatching(currentSources, path, home, false),
      excludePaths: currentExcludes.slice()
    }
  }
  if (state === "inherited") {
    return {
      sources: currentSources.slice(),
      excludePaths: addUniquePath(currentExcludes, path, home)
    }
  }
  return {
    sources: addSourcePath(currentSources, path, home),
    // Keep sticky right-click excludes under this path. Including a parent
    // must not wipe child exclusions.
    excludePaths: removeMatching(currentExcludes, path, home, false)
  }
}

function rightClickItem(path, sources, excludePaths, home) {
  var currentSources = sources || []
  var currentExcludes = excludePaths || []
  if (isExactPath(path, currentExcludes, home)) {
    return {
      sources: currentSources.slice(),
      excludePaths: removeMatching(currentExcludes, path, home, false)
    }
  }
  return {
    sources: removeMatching(currentSources, path, home, true),
    excludePaths: addUniquePath(currentExcludes, path, home)
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    parseJson: parseJson,
    defaultStatus: defaultStatus,
    parseStatus: parseStatus,
    parseList: parseList,
    formatClock: formatClock,
    formatWhen: formatWhen,
    formatBytes: formatBytes,
    formatDuration: formatDuration,
    formatCompactSize: formatCompactSize,
    formatRate: formatRate,
    rateLimitBpsFromKibs: rateLimitBpsFromKibs,
    rateLimitKibsFromBps: rateLimitKibsFromBps,
    formatRateLimit: formatRateLimit,
    formatRateLimitField: formatRateLimitField,
    parseRateLimit: parseRateLimit,
    formatEtaClock: formatEtaClock,
    formatBackupStats: formatBackupStats,
    destMeta: destMeta,
    pendingLabel: pendingLabel,
    destNameFromLabel: destNameFromLabel,
    destGlyph: destGlyph,
    entryGlyph: entryGlyph,
    snapshotLabel: snapshotLabel,
    scheduleOptions: scheduleOptions,
    scheduleLabel: scheduleLabel,
    timeFormatOptions: timeFormatOptions,
    cloudBackends: cloudBackends,
    notifyAgeOptions: notifyAgeOptions,
    notifyAgeLabel: notifyAgeLabel,
    basename: basename,
    parentPath: parentPath,
    expandUser: expandUser,
    storeSource: storeSource,
    isAncestorPath: isAncestorPath,
    sourceCheckState: sourceCheckState,
    isExactPath: isExactPath,
    isExcluded: isExcluded,
    pathRelativeToHome: pathRelativeToHome,
    excludePatternMatches: excludePatternMatches,
    matchingExcludePattern: matchingExcludePattern,
    itemMark: itemMark,
    leftClickItem: leftClickItem,
    rightClickItem: rightClickItem
  }
}
