.pragma library

// The clock is a *foreign* clock: it shows a place you are not in. Everything
// here is the small amount of timezone math that needs, kept out of the QML so
// the widget and the panel compute the same numbers the same way.
//
// Offsets themselves are not computed here — zoneinfo lives on disk and only
// `date` can read it — they arrive from Offsets.qml as minutes east of UTC.

// What `timezone` holds when the clock is simply following the system zone.
// Stored as a sentinel rather than as the resolved name so the clock keeps
// following if the machine's own timezone later changes.
var LOCAL = "local"

var DEFAULT_ZONES = [
  { tz: "Europe/Zurich", label: "Zürich" },
  { tz: "Europe/London", label: "London" },
  { tz: "Europe/Berlin", label: "Berlin" },
  { tz: "America/New_York", label: "New York" },
  { tz: "America/Los_Angeles", label: "Los Angeles" },
  { tz: "America/Sao_Paulo", label: "São Paulo" },
  { tz: "Asia/Dubai", label: "Dubai" },
  { tz: "Asia/Kolkata", label: "Mumbai" },
  { tz: "Asia/Singapore", label: "Singapore" },
  { tz: "Asia/Tokyo", label: "Tokyo" },
  { tz: "Australia/Sydney", label: "Sydney" },
  { tz: "UTC", label: "UTC" }
]

// "Europe/Zurich" -> "Zurich", "America/New_York" -> "New York". A label set
// in shell.json always wins, so "Zürich" survives round-tripping.
// A zone name is a path under /usr/share/zoneinfo, so it holds letters,
// digits, _ + - . and separators, and nothing else. Names arrive from
// shell.json and over IPC, and while they are passed to the probe as argv
// (never spliced into the script), an unchecked name still reaches `[ -e ]`
// and `TZ=` — enough to make the widget a file-existence oracle, and enough
// for "../../../etc/passwd" to quietly render as UTC instead of unresolved.
var ZONE_PATTERN = /^[A-Za-z0-9][A-Za-z0-9_+.\-]*(\/[A-Za-z0-9_+.\-]+)*$/
// Each zone in the list costs two short-lived processes a minute; a list this
// long is already unreadable, so the cap is a comfort rather than a limit.
var MAX_ZONES = 64
var MAX_LABEL = 64

function isValidZone(tz) {
  var value = String(tz || "").trim()
  if (value === "" || value.length > 120) return false
  if (value.indexOf("..") >= 0) return false
  return ZONE_PATTERN.test(value)
}

function clampLabel(text) {
  var value = String(text || "").trim()
  return value.length > MAX_LABEL ? value.slice(0, MAX_LABEL) : value
}

function isLocalZone(tz) {
  var value = String(tz || "").trim().toLowerCase()
  return value === "" || value === LOCAL || value === "system"
}

// The IANA name a row actually resolves to: the sentinel becomes the system
// zone, everything else is already a zone name.
function resolveZone(tz, localZone) {
  return isLocalZone(tz) ? String(localZone || "").trim() : String(tz || "").trim()
}

function localRowLabel(localZone) {
  var name = String(localZone || "").trim()
  return name === "" ? "Local time" : labelFor(name, "") + " (local)"
}

function labelFor(tz, override) {
  var explicit = String(override || "").trim()
  if (explicit !== "") return explicit
  // A zone the built-in list already names keeps that name, so Europe/Zurich
  // reads as "Zürich" and America/Sao_Paulo as "São Paulo" without anyone
  // having to type the diacritics into shell.json.
  for (var k = 0; k < DEFAULT_ZONES.length; k++)
    if (DEFAULT_ZONES[k].tz === tz) return DEFAULT_ZONES[k].label
  var parts = String(tz || "").split("/")
  var leaf = parts.length ? parts[parts.length - 1] : ""
  return leaf.replace(/_/g, " ")
}

// The `zones` setting is one line of text so it stays editable in the plugin
// settings UI: "Europe/Zurich=Zürich, Asia/Tokyo" — the label after `=` is
// optional and falls back to the zone's own leaf name.
function parseZoneSetting(raw, localZone, extraTz, extraLabel) {
  var text = String(raw || "").trim()
  var list = []
  if (text === "") {
    for (var d = 0; d < DEFAULT_ZONES.length; d++)
      list.push({ tz: DEFAULT_ZONES[d].tz, label: DEFAULT_ZONES[d].label })
  } else {
    var items = text.split(",")
    for (var i = 0; i < items.length; i++) {
      var item = items[i].trim()
      if (item === "") continue
      var eq = item.indexOf("=")
      var tz = (eq < 0 ? item : item.slice(0, eq)).trim()
      // A hand-written "local" entry is dropped: the row below already is it.
      if (tz === "" || isLocalZone(tz)) continue
      // A malformed name is dropped rather than shown unresolved: it can only
      // have come from hand-editing, and nothing good is downstream of it.
      if (!isValidZone(tz)) continue
      if (list.length >= MAX_ZONES) break
      list.push({ tz: tz, label: clampLabel(labelFor(tz, eq < 0 ? "" : item.slice(eq + 1))) })
    }
  }

  // Where you actually are heads the list and is always reachable, so going
  // back to your own time is one click rather than a timezone you have to
  // remember the name of.
  var local = String(localZone || "").trim()
  var rows = [{ tz: LOCAL, label: localRowLabel(local) }]
  for (var i = 0; i < list.length; i++) {
    if (local !== "" && list[i].tz === local) continue
    rows.push(list[i])
  }

  // The selected zone is always reachable too, even when a custom list forgets
  // it — otherwise cycling would strand you outside your own list.
  if (extraTz && !isLocalZone(extraTz) && !hasZone(rows, extraTz))
    rows.splice(1, 0, { tz: extraTz, label: labelFor(extraTz, extraLabel) })
  return rows
}

function hasZone(list, tz) {
  for (var i = 0; i < list.length; i++) if (list[i].tz === tz) return true
  return false
}

function indexOfZone(list, tz) {
  for (var i = 0; i < list.length; i++) if (list[i].tz === tz) return i
  return -1
}

function stepZone(list, tz, direction) {
  if (!list || list.length === 0) return tz
  var at = indexOfZone(list, tz)
  var next = (at < 0 ? 0 : at + (direction >= 0 ? 1 : -1) + list.length) % list.length
  return list[next].tz
}

var MONTHS = { Jan: 0, Feb: 1, Mar: 2, Apr: 3, May: 4, Jun: 5,
               Jul: 6, Aug: 7, Sep: 8, Oct: 9, Nov: 10, Dec: 11 }
var ZDUMP_LINE = /^(\S+)\s+[A-Za-z]{3}\s+([A-Za-z]{3})\s+(\d{1,2})\s+(\d{2}):(\d{2}):(\d{2})\s+(\d{4})(?:\s+(\S+))?\s*$/
// No real zone is further out than this; a line claiming otherwise is a
// wedged clock or a binary that is not zdump, and is refused either way.
var MAX_OFFSET_MINUTES = 16 * 60

// zdump prints the wall clock in a zone, not its offset:
//   Europe/Zurich  Fri Sep 11 11:04:09 2026 CEST
// The offset is that reading taken as if it were UTC, minus now. Rounding to
// the minute absorbs the fraction of a second between the two readings.
function parseZdumpLine(line, nowMs) {
  var match = ZDUMP_LINE.exec(String(line || "").trim())
  if (!match) return null
  var month = MONTHS[match[2]]
  if (month === undefined) return null
  if (!isValidZone(match[1])) return null
  var asUtc = Date.UTC(parseInt(match[7], 10), month, parseInt(match[3], 10),
                       parseInt(match[4], 10), parseInt(match[5], 10), parseInt(match[6], 10))
  var minutes = Math.round((asUtc - (nowMs === undefined ? Date.now() : nowMs)) / 60000)
  if (!isFinite(minutes) || Math.abs(minutes) > MAX_OFFSET_MINUTES) return null
  return { tz: match[1], minutes: minutes, abbr: match[8] ? String(match[8]) : "" }
}

function offsetOf(map, tz) {
  var entry = map ? map[tz] : null
  return entry && isFinite(entry.minutes) ? entry.minutes : NaN
}

function abbrOf(map, tz) {
  var entry = map ? map[tz] : null
  return entry && entry.abbr ? entry.abbr : ""
}

function localOffsetMinutes() {
  return -(new Date()).getTimezoneOffset()
}

// A Date whose *local* fields spell out the wall clock in `offsetMinutes`, so
// Qt.formatDateTime prints the foreign time (and its weekday and month name)
// without any of it being reinterpreted back into the system zone.
function zoneDate(offsetMinutes, nowMs) {
  var ms = (nowMs === undefined || nowMs === null) ? Date.now() : nowMs
  var shifted = new Date(ms + (isFinite(offsetMinutes) ? offsetMinutes : 0) * 60000)
  return new Date(shifted.getUTCFullYear(), shifted.getUTCMonth(), shifted.getUTCDate(),
                  shifted.getUTCHours(), shifted.getUTCMinutes(), shifted.getUTCSeconds(),
                  shifted.getUTCMilliseconds())
}

// The angle of the red hand. Hilfiker's movement drives it from a free-running
// motor that completes the sweep in ~58.5s and then waits at 12 for the
// minute impulse from the master clock — the pause is the whole character of
// the thing, so it is the default rather than a smooth 60s sweep.
function secondAngle(nowMs, stopToGo) {
  var into = ((nowMs % 60000) + 60000) % 60000
  if (!stopToGo) return into / 60000 * 360
  return Math.min(into / 58500, 1) * 360
}

// How far ahead or behind the foreign clock runs: "7h ahead", "4h 30m behind".
function deltaLabel(zoneMinutes, localMinutes) {
  if (!isFinite(zoneMinutes) || !isFinite(localMinutes)) return ""
  var diff = zoneMinutes - localMinutes
  if (diff === 0) return "same as your time"
  var ahead = diff > 0
  var abs = Math.abs(diff)
  var hours = Math.floor(abs / 60)
  var minutes = abs % 60
  var span = hours > 0 ? (hours + "h" + (minutes ? " " + minutes + "m" : "")) : (minutes + "m")
  return span + (ahead ? " ahead" : " behind")
}

// Compact form for list rows, where the delta is a suffix and not a sentence.
function deltaBadge(zoneMinutes, localMinutes) {
  if (!isFinite(zoneMinutes) || !isFinite(localMinutes)) return ""
  var diff = zoneMinutes - localMinutes
  if (diff === 0) return "±0"
  var abs = Math.abs(diff)
  var hours = Math.floor(abs / 60)
  var minutes = abs % 60
  return (diff > 0 ? "+" : "−") + hours + (minutes ? ":" + (minutes < 10 ? "0" : "") + minutes : "")
}
