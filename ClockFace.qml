import QtQuick
import "Zones.js" as Zones

// Hans Hilfiker's 1944 Bahnhofsuhr, drawn to its own proportions rather than
// to a generic analog-clock template: bar markers that reach a quarter of the
// way in, blunt hands with a short tail past the centre, and the red paddle
// second hand that gave the design its face.
//
// The dial is a Canvas (painted once per size/colour change) and the hands are
// plain rotated rectangles, so the sweeping hand costs a transform per frame
// and never a repaint — this thing lives in the bar and ticks all day.
Item {
  id: face

  property real diameter: 120
  property int hours: 10
  property int minutes: 10
  property bool showSeconds: true
  property bool stopToGo: true
  // Driven internally, but exposed so several faces could be ganged together.
  property real secondAngle: 0

  property color dialColor: "#ffffff"
  property color rimColor: "#1c1c1c"
  property color markColor: "#000000"
  property color handColor: "#000000"
  // Pantone 485, the red SBB has used on the paddle since the beginning.
  property color secondColor: "#da291c"
  // A centre cap over the hands. The real Bahnhofsuhr has none — the paddle
  // hand's tail covers the pivot — but a wall of them reads better with one,
  // so it is opt-in rather than drawn by default.
  property color hubColor: "transparent"

  readonly property real radius: diameter / 2
  // Sixty ticks at bar size would be a grey smudge, so below ~44px the dial
  // keeps only the twelve hour bars — the same simplification the real clock's
  // small siblings make.
  readonly property bool detailed: diameter >= 44
  // Smaller than this, twelve bars crowd into a grey ring and the hands lose
  // against them, so the dial keeps only the quarters.
  readonly property bool minimal: diameter < 15
  // Supersample the dial and scale it down: bar-sized ticks are fractions of a
  // pixel wide, and this is cheaper than fighting the rasteriser.
  readonly property int sampling: diameter < 64 ? 3 : 2

  // At bar size the hands have to win against the markers, so they thicken
  // and the hour bars give up some length — the same trade the small
  // platform clocks make against the big concourse ones.
  readonly property real markInner: detailed ? 0.64 : 0.70
  readonly property real hourThickness: radius * (detailed ? 0.125 : 0.15)
  readonly property real minuteThickness: radius * (detailed ? 0.085 : 0.105)

  readonly property real hourAngle: ((hours % 12) + minutes / 60) * 30
  readonly property real minuteAngle: minutes * 6

  implicitWidth: diameter
  implicitHeight: diameter

  onDialColorChanged: dial.requestPaint()
  onRimColorChanged: dial.requestPaint()
  onMarkColorChanged: dial.requestPaint()
  onDetailedChanged: dial.requestPaint()
  onMinimalChanged: dial.requestPaint()

  component Hand: Item {
    id: hand
    property real angle: 0
    property real reach: 0      // centre to tip
    property real tail: 0       // centre to the stub on the far side
    property real thickness: 2
    property color paint: "black"

    anchors.fill: parent
    transformOrigin: Item.Center
    rotation: angle

    Rectangle {
      width: Math.max(1, hand.thickness)
      height: hand.reach + hand.tail
      x: (hand.width - width) / 2
      y: hand.height / 2 - hand.reach
      color: hand.paint
      antialiasing: true
    }
  }

  Canvas {
    id: dial
    width: Math.max(1, Math.round(face.diameter * face.sampling))
    height: width
    anchors.centerIn: parent
    scale: 1 / face.sampling
    antialiasing: true

    onPaint: {
      var ctx = getContext("2d")
      var R = width / 2
      ctx.reset()
      ctx.clearRect(0, 0, width, height)
      ctx.save()
      ctx.translate(R, R)

      var rim = R * (face.detailed ? 0.035 : 0.055)
      var dialR = R - rim

      if (face.dialColor.a > 0) {
        ctx.beginPath()
        ctx.arc(0, 0, dialR + rim / 2, 0, Math.PI * 2)
        ctx.fillStyle = face.dialColor
        ctx.fill()
      }

      if (face.rimColor.a > 0 && rim > 0) {
        ctx.beginPath()
        ctx.arc(0, 0, R - rim / 2, 0, Math.PI * 2)
        ctx.lineWidth = rim
        ctx.strokeStyle = face.rimColor
        ctx.stroke()
      }

      var outer = dialR * 0.94
      var hourWidth = R * 0.105
      var hourInner = dialR * face.markInner
      var minuteWidth = R * 0.038
      var minuteInner = dialR * 0.855

      ctx.fillStyle = face.markColor
      for (var i = 0; i < 60; i++) {
        var isHour = i % 5 === 0
        if (!isHour && !face.detailed) continue
        if (face.minimal && i % 15 !== 0) continue
        ctx.save()
        ctx.rotate(i * Math.PI / 30)
        var w = isHour ? hourWidth : minuteWidth
        var inner = isHour ? hourInner : minuteInner
        ctx.fillRect(-w / 2, -outer, w, outer - inner)
        ctx.restore()
      }

      ctx.restore()
    }
  }

  Hand {
    reach: face.radius * 0.60
    tail: face.radius * 0.10
    thickness: face.hourThickness
    paint: face.handColor
    // Shortest would unwind the hour hand backwards across noon.
    Behavior on angle { RotationAnimation { direction: RotationAnimation.Clockwise; duration: 300; easing.type: Easing.OutCubic } }
    angle: face.hourAngle
  }

  // The minute hand of a station clock does not creep: it is held until the
  // master clock's impulse and then snaps, which is what the overshoot is.
  Hand {
    reach: face.radius * 0.92
    tail: face.radius * 0.10
    thickness: face.minuteThickness
    paint: face.handColor
    Behavior on angle { RotationAnimation { direction: RotationAnimation.Clockwise; duration: 220; easing.type: Easing.OutBack } }
    angle: face.minuteAngle
  }

  // Paddle hand: thin stem, then the disc that reads as a signal flag at a
  // distance. No Behavior — it is driven every frame and must not animate
  // backwards through the reset at 12.
  Item {
    id: secondHand
    anchors.fill: parent
    visible: face.showSeconds
    transformOrigin: Item.Center
    rotation: face.secondAngle

    Rectangle {
      width: Math.max(1, face.radius * 0.032)
      height: face.radius * 0.76
      x: (parent.width - width) / 2
      y: parent.height / 2 - face.radius * 0.60
      color: face.secondColor
      antialiasing: true
    }

    Rectangle {
      readonly property real discRadius: Math.max(1.2, face.radius * 0.105)
      width: discRadius * 2
      height: width
      radius: discRadius
      x: (parent.width - width) / 2
      y: parent.height / 2 - face.radius * 0.685 - discRadius
      color: face.secondColor
      antialiasing: true
    }
  }

  Rectangle {
    readonly property real hubRadius: Math.max(1.5, face.radius * 0.055)
    visible: face.hubColor.a > 0
    width: hubRadius * 2
    height: width
    radius: hubRadius
    anchors.centerIn: parent
    color: face.hubColor
    antialiasing: true
  }

  // 25fps is enough for a sweep this slow to read as continuous, and it keeps
  // the widget off the 60fps treadmill for the whole session.
  Timer {
    interval: 40
    repeat: true
    running: face.showSeconds && face.visible
    triggeredOnStart: true
    onTriggered: face.secondAngle = Zones.secondAngle(Date.now(), face.stopToGo)
  }
}
