import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import "Zones.js" as Zones

// The clock wall: every location at once, the way a newsroom hangs them —
// a grid of dials with the city on a plate underneath.
//
// It is a fullscreen overlay rather than a second panel because it is meant
// to be looked at, not worked in: summon it, read it, dismiss it. The zone
// list, dial style and second-hand behaviour arrive in the summon payload
// from the bar widget, so the wall shows the same places the bar cycles.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  property var zones: []
  property bool showSeconds: true
  property bool stopToGo: true
  property bool classicDial: true
  property string rimStyle: "red"

  readonly property string pluginId: (manifest && manifest.id) || "ronnie.swissclock"
  readonly property string localZone: offsets.localZone
  readonly property int localOffset: isFinite(Zones.offsetOf(offsets.map, localZone))
    ? Zones.offsetOf(offsets.map, localZone) : Zones.localOffsetMinutes()

  // Swiss red for the bezel, matching the clocks that hang in station halls
  // and control rooms; "black" is the plain Mondaine, "theme" borrows the bar.
  readonly property color rimColor: rimStyle === "black" ? "#1c1c1c"
    : (rimStyle === "theme" ? Color.accent : "#d8232a")
  readonly property color dialColor: classicDial ? "#ffffff" : "transparent"
  readonly property color markColor: classicDial ? "#000000" : Color.foreground
  readonly property color secondColor: classicDial ? "#da291c" : Color.urgent

  // One beat for the whole wall: every face reads the same instant, and
  // nothing ticks while the overlay is closed.
  property double nowMs: Date.now()

  function open(payloadJson) {
    applyPayload(payloadJson)
    root.opened = true
    root.nowMs = Date.now()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function applyPayload(payloadJson) {
    var payload = ({})
    try {
      var raw = String(payloadJson || "").trim()
      if (raw !== "") payload = JSON.parse(raw)
    } catch (e) {
      // A malformed payload is not worth refusing to open over; the defaults
      // below still produce a usable wall.
    }
    if (typeof payload.showSeconds === "boolean") root.showSeconds = payload.showSeconds
    if (typeof payload.stopToGo === "boolean") root.stopToGo = payload.stopToGo
    if (typeof payload.classicDial === "boolean") root.classicDial = payload.classicDial
    if (typeof payload.rim === "string" && payload.rim !== "") root.rimStyle = payload.rim
    root.zones = sanitizeZones(payload.zones)
  }

  // The payload arrives over the shell's IPC, so it is only as trustworthy as
  // anything else running as this user — but a wall of ten thousand dials is
  // a frozen session, and a name that is not a zone has no business reaching
  // the probe. Both are cheap to refuse.
  function sanitizeZones(raw) {
    if (!Array.isArray(raw) || raw.length === 0)
      return Zones.parseZoneSetting("", root.localZone, "", "")
    var out = []
    for (var i = 0; i < raw.length && out.length < Zones.MAX_ZONES; i++) {
      var entry = raw[i]
      if (!entry) continue
      var tz = String(entry.tz || "")
      if (!Zones.isLocalZone(tz) && !Zones.isValidZone(tz)) continue
      out.push({ tz: tz, label: Zones.clampLabel(entry.label) })
    }
    return out.length > 0 ? out : Zones.parseZoneSetting("", root.localZone, "", "")
  }

  // Columns are chosen by trying every split and keeping the one that makes
  // the faces biggest — a wall of 5 reads differently from a wall of 13, and
  // neither should be laid out to a guess.
  function bestColumns(count, w, h, ratio) {
    if (count <= 0 || w <= 0 || h <= 0) return 1
    var best = 1
    var bestSize = 0
    for (var cols = 1; cols <= count; cols++) {
      var rows = Math.ceil(count / cols)
      var size = Math.min(w / cols, (h / rows) / ratio)
      if (size > bestSize) {
        bestSize = size
        best = cols
      }
    }
    return best
  }

  Offsets {
    id: offsets
    active: root.opened
    zones: {
      var list = []
      for (var i = 0; i < root.zones.length; i++) {
        var tz = Zones.resolveZone(root.zones[i].tz, root.localZone)
        if (tz !== "") list.push(tz)
      }
      if (root.localZone !== "") list.push(root.localZone)
      return list
    }
  }

  Timer {
    interval: 250
    repeat: true
    running: root.opened
    triggeredOnStart: true
    onTriggered: root.nowMs = Date.now()
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "ronnie-swissclock-wall"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    readonly property real margin: Style.space(48)
    readonly property real headerHeight: Style.space(52)
    readonly property real footerHeight: Style.space(34)
    // Face, plate and the time line beneath it, as a multiple of the face.
    readonly property real cellRatio: 1.42
    readonly property real gridWidth: width - margin * 2
    readonly property real gridHeight: height - margin * 2 - headerHeight - footerHeight
    readonly property int columns: root.bestColumns(root.zones.length, gridWidth, gridHeight, cellRatio)
    readonly property int rows: Math.max(1, Math.ceil(root.zones.length / Math.max(1, columns)))
    readonly property real cellWidth: gridWidth / Math.max(1, columns)
    readonly property real cellHeight: gridHeight / rows
    readonly property real faceSize: Math.max(Style.space(64),
      Math.min(Style.space(340), Math.min(cellWidth, cellHeight / cellRatio) - Style.space(18)))

    Rectangle {
      anchors.fill: parent
      // Near-opaque: whatever is behind the wall is not part of it, and text
      // bleeding through a clock face reads as a rendering fault.
      color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.985)
    }

    // Twenty-four faint bands, one per hour of longitude: the map behind a
    // wall of clocks, reduced to the only thing it was ever saying.
    Row {
      anchors.fill: parent

      Repeater {
        model: 24

        Rectangle {
          required property int index
          width: panel.width / 24
          height: panel.height
          color: index % 2 === 0
            ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.022)
            : "transparent"
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape || event.key === Qt.Key_Space
            || event.key === Qt.Key_Return || event.text === "q" || event.text === "w") {
          root.dismiss()
          event.accepted = true
        }
      }

      Text {
        id: header
        textFormat: Text.PlainText
        anchors.top: parent.top
        anchors.topMargin: panel.margin
        anchors.horizontalCenter: parent.horizontalCenter
        text: Qt.formatDateTime(Zones.zoneDate(root.localOffset, root.nowMs), "dddd d MMMM yyyy")
        color: Qt.darker(Color.foreground, 1.35)
        font.family: Style.font.family
        font.pixelSize: Style.font.title
      }

      Grid {
        id: grid
        anchors.centerIn: parent
        anchors.verticalCenterOffset: Style.space(6)
        columns: panel.columns
        columnSpacing: 0
        rowSpacing: 0

        Repeater {
          model: root.zones

          Item {
            id: cell
            required property var modelData
            required property int index

            readonly property string tz: modelData ? String(modelData.tz || "") : ""
            readonly property string effectiveTz: Zones.resolveZone(tz, root.localZone)
            readonly property bool isLocal: Zones.isLocalZone(tz)
            readonly property int offsetMinutes: Zones.offsetOf(offsets.map, effectiveTz)
            readonly property bool resolved: isFinite(offsetMinutes)
            readonly property date cellTime: Zones.zoneDate(resolved ? offsetMinutes : root.localOffset, root.nowMs)
            readonly property string cellLabel: modelData && modelData.label
              ? String(modelData.label).replace(/\s*\(local\)\s*$/, "")
              : Zones.labelFor(effectiveTz, "")

            width: panel.cellWidth
            height: panel.cellHeight

            Column {
              anchors.centerIn: parent
              spacing: Style.space(12)

              ClockFace {
                anchors.horizontalCenter: parent.horizontalCenter
                diameter: panel.faceSize
                hours: cell.cellTime.getHours()
                minutes: cell.cellTime.getMinutes()
                showSeconds: root.showSeconds && cell.resolved
                stopToGo: root.stopToGo
                visible: root.opened
                opacity: cell.resolved ? 1 : 0.4
                dialColor: root.dialColor
                rimColor: root.rimColor
                markColor: root.markColor
                handColor: root.markColor
                secondColor: root.secondColor
                hubColor: root.classicDial ? root.rimColor : root.secondColor
              }

              // The plate: a newsroom wall names its clocks, and the name is
              // what you actually read first.
              Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.max(plate.implicitWidth + Style.space(22), panel.faceSize * 0.7)
                height: plate.implicitHeight + Style.space(10)
                radius: Style.space(3)
                color: Qt.rgba(0, 0, 0, 0.55)
                border.width: cell.isLocal ? Math.max(1, Style.space(1)) : 0
                border.color: Qt.rgba(1, 1, 1, 0.35)

                Text {
                  id: plate
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  text: cell.cellLabel.toUpperCase()
                  color: "#ffffff"
                  font.family: Style.font.family
                  font.pixelSize: Math.max(Style.font.bodySmall, Math.round(panel.faceSize * 0.11))
                  font.bold: true
                }
              }

              Text {
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                text: {
                  if (!cell.resolved) return "—"
                  var time = Qt.formatDateTime(cell.cellTime, "HH:mm")
                  if (cell.isLocal) return time + " · local"
                  // A zone can share your offset without being where you are —
                  // Singapore beside Kuala Lumpur — so that reads "same time",
                  // not "local".
                  if (cell.offsetMinutes === root.localOffset) return time + " · same time"
                  return time + " · " + Zones.deltaLabel(cell.offsetMinutes, root.localOffset)
                }
                color: Qt.darker(Color.foreground, 1.3)
                font.family: Style.font.family
                font.pixelSize: Math.max(Style.font.caption, Math.round(panel.faceSize * 0.085))
              }
            }
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        anchors.bottom: parent.bottom
        anchors.bottomMargin: panel.margin
        anchors.horizontalCenter: parent.horizontalCenter
        text: "Esc to close"
        color: Qt.darker(Color.foreground, 1.7)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }
  }
}
