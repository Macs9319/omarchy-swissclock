import QtQuick
import Quickshell.Io
import "Zones.js" as Zones

// Resolves IANA zone names to UTC offsets by asking `date`, because zoneinfo
// (and therefore DST) can only be read off disk. One process per refresh
// covers every zone the widget and its panel care about.
//
// `map` is reassigned wholesale rather than mutated so QML bindings that read
// it actually re-evaluate.
Item {
  id: root

  // Zone names to resolve. Duplicates and blanks are tolerated.
  property var zones: []
  property var map: ({})
  property string localZone: ""
  property int refreshIntervalMs: 60000
  // A wall that is not on screen has nothing to keep fresh.
  property bool active: true

  // Re-asking every minute is what keeps a DST changeover from lingering: a
  // zone that springs forward is wrong for at most one minute, and one short
  // process a minute costs less than parsing zoneinfo ourselves would.
  readonly property string script: ""
    + "printf '=local\\t%s\\n' \"$(timedatectl show -p Timezone --value 2>/dev/null || readlink -f /etc/localtime | sed 's#.*/zoneinfo/##')\"; "
    + "for z in \"$@\"; do "
    + "  if [ -e \"/usr/share/zoneinfo/$z\" ]; then printf '%s\\t%s\\t%s\\n' \"$z\" \"$(TZ=\"$z\" date +%z)\" \"$(TZ=\"$z\" date +%Z)\"; "
    + "  else printf '%s\\t\\t\\n' \"$z\"; fi; "
    + "done"

  property bool refreshQueued: false

  function wantedZones() {
    var seen = ({})
    var list = []
    for (var i = 0; i < (zones || []).length; i++) {
      var tz = String(zones[i] || "").trim()
      // Zone names go to the shell as argv entries and are never spliced into
      // the script text, so the quoting is not what is at stake here: the
      // check is so that a name which is not a zone never reaches `[ -e ]` or
      // `TZ=` at all. Last line of defence — callers validate too.
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
    probe.command = ["bash", "-c", root.script, "swissclock"].concat(list)
    probe.running = true
  }

  function apply(text) {
    var next = ({})
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i]
      if (line === "") continue
      var parts = line.split("\t")
      if (parts[0] === "=local") {
        var name = String(parts[1] || "").trim()
        if (name !== "") root.localZone = name
        continue
      }
      var minutes = Zones.parseOffsetMinutes(parts[1])
      next[parts[0]] = {
        minutes: minutes,
        abbr: String(parts[2] || "").trim(),
        valid: isFinite(minutes)
      }
    }
    root.map = next
  }

  onZonesChanged: debounce.restart()
  Component.onCompleted: refresh()

  // Zone lists change in bursts — a settings write touches several bindings at
  // once — so coalesce instead of spawning a process per change.
  Timer {
    id: debounce
    interval: 60
    onTriggered: root.refresh()
  }

  Timer {
    interval: root.refreshIntervalMs
    repeat: true
    running: root.active
    onTriggered: root.refresh()
  }

  onActiveChanged: if (active) refresh()

  Process {
    id: probe
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.apply(text)
    }
    onExited: if (root.refreshQueued) Qt.callLater(root.refresh)
  }
}
