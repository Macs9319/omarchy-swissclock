import QtQuick
import qs.Commons
import qs.Ui
import "Zones.js" as Zones

// The popup behind the bar face: the same clock drawn big enough to read as a
// station clock, and the list of places you can point it at. Picking a row
// writes the choice through the host widget, so it persists in shell.json
// rather than being a session-only whim.
Panel {
  id: root
  moduleName: "ronnie.swissclock"
  manageIpc: false

  property var anchorItem: null
  // The bar tracks the widget in its slot, not this nested panel, so popout
  // coordination and panel switching have to identify as the widget.
  property var hostWidget: null
  property var offsets: null

  readonly property var barIdentity: hostWidget || root
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string timezone: hostWidget ? hostWidget.timezone : ""
  readonly property string zoneLabel: hostWidget ? hostWidget.zoneLabel : "Local time"
  readonly property bool followsLocal: hostWidget ? hostWidget.followsLocal : true
  readonly property string selectedKey: hostWidget ? hostWidget.selectedKey : "local"
  readonly property bool showSeconds: hostWidget ? hostWidget.showSeconds : true
  readonly property bool stopToGo: hostWidget ? hostWidget.stopToGo : true
  readonly property bool classicDial: hostWidget ? hostWidget.classicDial : true
  readonly property var zoneList: hostWidget ? hostWidget.zoneList : []
  readonly property var offsetMap: offsets ? offsets.map : ({})
  readonly property string localZone: offsets ? offsets.localZone : ""
  // The subtitle names the zone and says outright when the clock is simply
  // your own time, so "09:32" is never ambiguous about which place it means.
  readonly property string zoneSubtitle: {
    var name = timezone === "" ? localZone : timezone
    var parts = []
    if (name !== "") parts.push(name)
    // Following local, the "local" marker is worth more than the abbreviation
    // and the line only has room for one of them.
    if (followsLocal) parts.push("local")
    else if (zoneAbbr !== "") parts.push(zoneAbbr)
    return parts.join(" · ")
  }

  readonly property int zoneOffset: isFinite(Zones.offsetOf(offsetMap, timezone))
    ? Zones.offsetOf(offsetMap, timezone) : Zones.localOffsetMinutes()
  readonly property int localOffset: isFinite(Zones.offsetOf(offsetMap, localZone))
    ? Zones.offsetOf(offsetMap, localZone) : Zones.localOffsetMinutes()
  readonly property string zoneAbbr: Zones.abbrOf(offsetMap, timezone)

  // Driven only while open. A quarter-second beat lands the minute hand on the
  // minute without the panel holding a clock subscription all session.
  property double nowMs: Date.now()
  readonly property date zoneTime: Zones.zoneDate(zoneOffset, nowMs)

  property int cursorIndex: 0
  property bool cursorActive: false

  function setCursor(index) {
    cursorActive = true
    cursorIndex = index
  }

  function moveCursor(delta) {
    if (zoneList.length === 0) return
    cursorActive = true
    cursorIndex = Math.max(0, Math.min(zoneList.length - 1, cursorIndex + delta))
  }

  function chooseZone(zone) {
    if (!zone || !hostWidget) return
    hostWidget.selectZone(zone.tz, zone.label)
  }

  function activateCursor() {
    if (cursorIndex < 0 || cursorIndex >= zoneList.length) return
    chooseZone(zoneList[cursorIndex])
  }

  onOpenedChanged: {
    if (!opened) return
    nowMs = Date.now()
    cursorActive = false
    var at = Zones.indexOfZone(zoneList, selectedKey)
    cursorIndex = at < 0 ? 0 : at
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Timer {
    interval: 250
    repeat: true
    running: root.opened
    triggeredOnStart: true
    onTriggered: root.nowMs = Date.now()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(356))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { root.moveCursor(dy) }
      onActivateRequested: root.activateCursor()
      onReturnRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: column
          width: flick.width
          spacing: Style.space(12)

          Row {
            width: parent.width
            spacing: Style.space(16)

            ClockFace {
              id: hero
              anchors.verticalCenter: parent.verticalCenter
              diameter: Style.space(120)
              hours: root.zoneTime.getHours()
              minutes: root.zoneTime.getMinutes()
              showSeconds: root.showSeconds
              stopToGo: root.stopToGo
              visible: root.opened
              dialColor: root.classicDial ? "#ffffff" : "transparent"
              rimColor: root.classicDial ? "#1c1c1c" : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
              markColor: root.classicDial ? "#000000" : root.foreground
              handColor: root.classicDial ? "#000000" : root.foreground
              secondColor: root.classicDial ? "#da291c" : (root.bar ? root.bar.urgent : "#da291c")
            }

            Column {
              width: parent.width - hero.width - Style.space(16)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(3)

              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: root.zoneLabel
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
                font.bold: true
                elide: Text.ElideRight
              }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: root.zoneSubtitle
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }

              Item { width: 1; height: Style.space(4) }

              Text {
                textFormat: Text.PlainText
                text: Qt.formatDateTime(root.zoneTime, root.showSeconds ? "HH:mm:ss" : "HH:mm")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: Qt.formatDateTime(root.zoneTime, "dddd d MMMM")
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: root.deltaSentence
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          PanelSectionHeader {
            text: "LOCATIONS"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Column {
            id: zoneColumn
            width: parent.width
            spacing: Style.space(2)

            Repeater {
              model: root.zoneList

              ZoneRow {
                required property var modelData
                required property int index
                width: zoneColumn.width
                zone: modelData
                rowIndex: index
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: "Right-click or scroll the bar clock to cycle locations · middle-click hides the time"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }

  readonly property string deltaSentence: {
    if (followsLocal) return "Your local time"
    var delta = Zones.deltaLabel(zoneOffset, localOffset)
    if (delta === "") return ""
    if (delta === "same as your time") return "Same as your time"
    var here = localZone === "" ? "" : " " + Zones.labelFor(localZone, "")
    return delta.charAt(0).toUpperCase() + delta.slice(1) + here
  }

  component ZoneRow: CursorSurface {
    id: row
    property var zone: null
    property int rowIndex: 0

    readonly property string tz: zone ? String(zone.tz || "") : ""
    readonly property string label: zone ? String(zone.label || "") : ""
    readonly property string effectiveTz: Zones.resolveZone(tz, root.localZone)
    readonly property int offsetMinutes: Zones.offsetOf(root.offsetMap, effectiveTz)
    readonly property bool resolved: isFinite(offsetMinutes)
    readonly property bool isCurrent: tz === root.selectedKey

    hasCursor: root.cursorActive && root.cursorIndex === rowIndex
    current: isCurrent
    foreground: root.foreground
    implicitHeight: rowInner.implicitHeight + Style.spacing.lg

    Item {
      id: rowInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      implicitHeight: rowLabel.implicitHeight

      Text {
        id: rowLabel
        textFormat: Text.PlainText
        anchors.left: parent.left
        anchors.right: rowTime.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: row.label
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: row.isCurrent
        elide: Text.ElideRight
      }

      Text {
        id: rowBadge
        textFormat: Text.PlainText
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignRight
        width: Style.space(34)
        text: row.resolved ? Zones.deltaBadge(row.offsetMinutes, root.localOffset) : ""
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        id: rowTime
        textFormat: Text.PlainText
        anchors.right: rowBadge.left
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignRight
        // A zone name that zoneinfo does not know stays visibly unresolved
        // instead of silently rendering as UTC.
        text: row.resolved ? Qt.formatDateTime(Zones.zoneDate(row.offsetMinutes, root.nowMs), "HH:mm") : "—"
        color: row.isCurrent ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setCursor(row.rowIndex)
      onClicked: root.chooseZone(row.zone)
    }
  }
}
