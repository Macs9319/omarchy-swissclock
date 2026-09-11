import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Zones.js" as Zones

// A Swiss station clock in the bar, set to somewhere else. The point of the
// widget is the second half of that sentence: the built-in clock already tells
// you the time where you are, so this one is for the place you keep having to
// do arithmetic about — an office, a market open, someone you call.
//
// left click   panel with the big face and the location list
// right click  next location in the list
// middle click show/hide the digital time beside the face
// scroll       previous/next location
BarWidget {
  id: root
  moduleName: "ronnie.swissclock"

  // "local" (or an empty value, or no key at all) means follow the system
  // timezone. That is the out-of-the-box state: the clock starts on your own
  // time and only points somewhere else once you send it there.
  readonly property string timezoneSetting: String(setting("timezone", "local"))
  readonly property bool followsLocal: Zones.isLocalZone(timezoneSetting)
  readonly property string localZone: offsets.localZone
  readonly property string timezone: Zones.resolveZone(timezoneSetting, localZone)
  // What the zone list is matched against: the sentinel when following local,
  // so cycling lands back on the local row instead of on a zone with the same
  // name as the system one.
  readonly property string selectedKey: followsLocal ? "local" : timezone
  readonly property string zoneLabel: followsLocal
    ? (localZone === "" ? "Local time" : Zones.labelFor(localZone, ""))
    : Zones.labelFor(timezone, setting("label", ""))
  readonly property bool showLabel: setting("showLabel", true) === true
  readonly property string labelFormat: String(setting("labelFormat", "HH:mm"))
  readonly property bool showSeconds: setting("showSeconds", true) === true
  readonly property bool stopToGo: setting("stopToGo", true) === true
  readonly property bool classicDial: String(setting("dial", "classic")) !== "theme"
  readonly property var zoneList: Zones.parseZoneSetting(setting("zones", ""), localZone,
    followsLocal ? "" : timezone, setting("label", ""))

  readonly property var zoneMap: offsets.map
  readonly property bool zoneResolved: isFinite(Zones.offsetOf(zoneMap, timezone))
  // Until the first `date` call comes back, run on local time rather than
  // painting an empty slot — a fraction of a second later it corrects itself.
  readonly property int zoneOffset: zoneResolved ? Zones.offsetOf(zoneMap, timezone) : Zones.localOffsetMinutes()
  readonly property int localOffset: isFinite(Zones.offsetOf(zoneMap, offsets.localZone))
    ? Zones.offsetOf(zoneMap, offsets.localZone) : Zones.localOffsetMinutes()

  readonly property date zoneTime: Zones.zoneDate(zoneOffset, clock.date.getTime())
  readonly property string labelText: Qt.formatDateTime(zoneTime, labelFormat)
  // Following local, "same as your time" is a tautology — say what it is.
  readonly property string deltaText: followsLocal
    ? "local time" : Zones.deltaLabel(zoneOffset, localOffset)

  // Face size as a percentage of the bar's own height, so it keeps its
  // proportion on a taller bar or a scaled font instead of being pinned to a
  // pixel count that only suits one bar.
  readonly property int faceScale: {
    var value = Number(setting("faceScale", 72))
    return isFinite(value) ? Math.max(30, Math.min(100, Math.round(value))) : 72
  }
  readonly property real faceSize: Math.max(8, Math.min(barSize, Math.round(barSize * faceScale / 100)))

  function applySettings(changes) {
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    for (var change in changes) entry[change] = changes[change]

    // Applied locally first so the face turns on the click itself; the
    // shell.json write comes back through the bar as the same value.
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // A zone picked from the list carries its label with it, so a custom name
  // ("Mumbai" for Asia/Kolkata) survives the switch instead of reverting to
  // the zone's leaf name.
  function selectZone(tz, label) {
    var next = String(tz || "").trim()
    var local = Zones.isLocalZone(next)
    if (local) next = "local"
    if (next === root.timezoneSetting) return
    // The local row's label is generated from whatever the system zone is
    // right now; storing it would freeze the name if that ever changed.
    applySettings({ timezone: next, label: local ? "" : String(label || "") })
  }

  function cycleZone(direction) {
    var next = Zones.stepZone(root.zoneList, root.selectedKey, direction)
    var at = Zones.indexOfZone(root.zoneList, next)
    selectZone(next, at >= 0 ? root.zoneList[at].label : "")
  }

  function toggleLabel() {
    applySettings({ showLabel: !root.showLabel })
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("offsets" in target) target.offsets = offsets
  }

  // Shape contract for shell.summon/hide/toggle routing: Bar.findPanelWidget
  // requires open/close/opened on the bar-widget root.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }

  // Forwarded so this widget can stand in for the panel as the bar's popout
  // identity: Bar.requestPopout prefers closeForPopoutSwitch over close.
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  SystemClock {
    id: clock
    precision: SystemClock.Seconds
  }

  // Every zone in the list is resolved, not just the selected one: the panel
  // shows the whole list live, and one process answers for all of them.
  Offsets {
    id: offsets
    zones: {
      var list = []
      if (root.timezone !== "") list.push(root.timezone)
      for (var i = 0; i < root.zoneList.length; i++) {
        var tz = Zones.resolveZone(root.zoneList[i].tz, root.localZone)
        if (tz !== "") list.push(tz)
      }
      // The system zone earns a slot of its own: every "ahead/behind" reading
      // is measured against it, including while the clock points elsewhere.
      if (root.localZone !== "") list.push(root.localZone)
      return list
    }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "ronnie.swissclock"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function next(): void { root.cycleZone(1) }
    function previous(): void { root.cycleZone(-1) }
    function setZone(zone: string): void { root.selectZone(zone, "") }
    function useLocal(): void { root.selectZone("local", "") }
    function zone(): string { return root.timezone + " " + Qt.formatDateTime(root.zoneTime, "yyyy-MM-dd HH:mm:ss") }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    horizontalMargin: 6.5
    verticalPadding: 4
    fixedWidth: root.vertical ? -1 : Math.round(content.implicitWidth + Style.spaceReal(13))
    fixedHeight: root.vertical ? Math.round(root.faceSize + Style.spaceReal(8)) : -1
    tooltipText: root.zoneLabel + " · " + Qt.formatDateTime(root.zoneTime, "HH:mm")
      + (root.deltaText === "" ? "" : " · " + root.deltaText)

    onPressed: function(b) {
      if (b === Qt.RightButton) root.cycleZone(1)
      else if (b === Qt.MiddleButton) root.toggleLabel()
      else root.togglePanel()
    }

    onWheelMoved: function(delta) { root.cycleZone(delta > 0 ? -1 : 1) }

    Row {
      id: content
      anchors.centerIn: parent
      spacing: timeLabel.visible ? Style.space(6) : 0

      ClockFace {
        id: face
        anchors.verticalCenter: parent.verticalCenter
        diameter: root.faceSize
        hours: root.zoneTime.getHours()
        minutes: root.zoneTime.getMinutes()
        showSeconds: root.showSeconds
        stopToGo: root.stopToGo
        dialColor: root.classicDial ? "#ffffff" : "transparent"
        rimColor: root.classicDial ? "#1c1c1c" : "transparent"
        markColor: root.classicDial ? "#000000" : button.foreground
        handColor: root.classicDial ? "#000000" : button.foreground
        secondColor: root.classicDial ? "#da291c" : (root.bar ? root.bar.urgent : "#da291c")
      }

      Text {
        id: timeLabel
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        visible: !root.vertical && root.showLabel && text !== ""
        text: root.labelText
        color: button.foreground
        font.family: button.fontFamily
        font.pixelSize: Style.font.body
        renderType: Text.NativeRendering
      }
    }
  }
}
