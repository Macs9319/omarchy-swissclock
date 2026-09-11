import QtQuick
import Quickshell.Io
import "Zones.js" as Zones

// Resolves IANA zone names to UTC offsets. QML has no timezone database, so
// something that has one has to be asked — but this asks as narrowly as it
// can, because the asking repeats every minute inside a shell process that
// lives for the whole session:
//
//   * no shell in the pipeline — one binary, one argv, nothing to word-split
//     or quote, and a single child to reap rather than a process tree
//   * absolute paths and a cleared environment, so what runs cannot be
//     redecided by PATH, LD_PRELOAD, or anything else inherited
//   * a hard deadline and an output cap, so a wedged or substituted binary
//     costs one dropped refresh instead of the session
//
// `map` is reassigned wholesale rather than mutated so QML bindings that read
// it actually re-evaluate.
Item {
  id: root

  // Zone names to resolve. Duplicates, blanks and malformed names are dropped.
  property var zones: []
  property var map: ({})
  property string localZone: ""
  property int refreshIntervalMs: 60000
  // A wall that is not on screen has nothing to keep fresh.
  property bool active: true

  // tzdata ships both the database this reads and the binary that reads it,
  // so zdump is present wherever the zone files themselves are.
  readonly property string zdumpBin: "/usr/bin/zdump"
  readonly property string timedatectlBin: "/usr/bin/timedatectl"
  // C locale so the month names parse; nothing else is inherited.
  readonly property var probeEnvironment: ({ "LC_ALL": "C" })
  readonly property int probeTimeoutMs: 5000
  readonly property int maxOutputBytes: 32768

  property bool refreshQueued: false
  property var collected: []
  property int collectedBytes: 0
  property int lastLocalOffset: Zones.localOffsetMinutes()

  function wantedZones() {
    var seen = ({})
    var list = []
    for (var i = 0; i < (zones || []).length; i++) {
      var tz = String(zones[i] || "").trim()
      // Last line of defence — callers validate too. A name that is not a
      // zone never becomes an argument to anything.
      if (seen[tz] || !Zones.isValidZone(tz)) continue
      if (list.length >= Zones.MAX_ZONES) break
      seen[tz] = true
      list.push(tz)
    }
    return list
  }

  function refresh() {
    var list = wantedZones()
    if (list.length === 0) return
    if (probe.running) {
      refreshQueued = true
      return
    }
    refreshQueued = false
    collected = []
    collectedBytes = 0
    probe.command = [root.zdumpBin].concat(list)
    probe.running = true
  }

  // The system zone's *offset* comes from the JS engine and is always live;
  // only its name needs asking for, so this runs at startup and then only
  // when the local offset moves — a timezone change or a DST step.
  function refreshLocalZone() {
    if (localProbe.running) return
    localProbe.command = [root.timedatectlBin, "show", "-p", "Timezone", "--value"]
    localProbe.running = true
  }

  function collect(line) {
    collectedBytes += String(line).length + 1
    if (collectedBytes > root.maxOutputBytes) {
      abort()
      return
    }
    collected.push(line)
  }

  // SIGKILL rather than a polite request: whatever is being stopped is either
  // wedged or not the program this expected to run.
  function abort() {
    if (probe.running) probe.signal(9)
  }

  function apply() {
    var now = Date.now()
    var next = ({})
    for (var i = 0; i < collected.length; i++) {
      var parsed = Zones.parseZdumpLine(collected[i], now)
      // A zone zdump does not know prints nothing here (it complains on
      // stderr), so it stays absent from the map and reads as unresolved
      // rather than quietly becoming UTC.
      if (parsed) next[parsed.tz] = { minutes: parsed.minutes, abbr: parsed.abbr, valid: true }
    }
    root.map = next
    collected = []
  }

  onZonesChanged: debounce.restart()
  onActiveChanged: if (active) refresh()

  Component.onCompleted: {
    refreshLocalZone()
    refresh()
  }

  // Zone lists change in bursts — a settings write touches several bindings at
  // once — so coalesce instead of spawning a process per change.
  Timer {
    id: debounce
    interval: 60
    onTriggered: root.refresh()
  }

  // Re-asking every minute is what keeps a DST changeover from lingering: a
  // zone that springs forward is wrong for at most a minute.
  Timer {
    interval: root.refreshIntervalMs
    repeat: true
    running: root.active
    onTriggered: {
      root.refresh()
      var offset = Zones.localOffsetMinutes()
      if (offset !== root.lastLocalOffset) {
        root.lastLocalOffset = offset
        root.refreshLocalZone()
      }
    }
  }

  Timer {
    id: deadline
    interval: root.probeTimeoutMs
    onTriggered: root.abort()
  }

  Timer {
    id: localDeadline
    interval: root.probeTimeoutMs
    onTriggered: if (localProbe.running) localProbe.signal(9)
  }

  Process {
    id: probe
    clearEnvironment: true
    environment: root.probeEnvironment

    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(line) { root.collect(line) }
    }

    // Unknown zone names are reported here. Read and discarded rather than
    // left to inherit the shell's stderr, but still counted: a binary that
    // floods either stream is a binary to stop.
    stderr: SplitParser {
      splitMarker: "\n"
      onRead: function(line) {
        root.collectedBytes += String(line).length + 1
        if (root.collectedBytes > root.maxOutputBytes) root.abort()
      }
    }

    onStarted: deadline.restart()
    onExited: {
      deadline.stop()
      root.apply()
      if (root.refreshQueued) Qt.callLater(root.refresh)
    }
  }

  Process {
    id: localProbe
    clearEnvironment: true
    environment: root.probeEnvironment

    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(line) {
        var name = String(line || "").trim()
        // Validated like any other zone name: this one is only ever a label
        // and a map key, but it arrives from a subprocess all the same.
        if (Zones.isValidZone(name)) root.localZone = name
      }
    }

    onStarted: localDeadline.restart()
    onExited: localDeadline.stop()
  }
}
