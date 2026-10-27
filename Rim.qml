import QtQuick
import QtQuick.Shapes
import qs.Commons
import "Model.js" as Model

// The ring around the map: a 24 h dial (noon at the top, midnight at the
// bottom). By day the arc from the real sunrise to sunset is yellow with the
// sun on the current time; by night the arc from sunset to sunrise is blue
// with the moon in its real phase. From the map outwards, none overlapping:
// the map's edge, the battery band, the day/night dial. Battery: on
// battery a stripe from now to the estimated empty time; charging an orange
// stripe to full, then a green one for how long that charge would last;
// plugged in and full, the green runtime from now.
Item {
  id: rim

  property real ringWidth: 22         // dial + battery band, see below
  property bool cardinals: true      // pilot's bezel, else plain ticks at the quarters too
  signal batteryClicked()
  readonly property real unit: ringWidth / 22   // the sizes below are for a 22 px ring
  readonly property real dialWidth: 8 * unit
  readonly property real batteryWidth: 8 * unit   // as wide as the dial
  readonly property real bandGap: 3 * unit        // clear space between the bands
  property var now: new Date()
  property var daylight: null        // {start, end} dial angles, or null
  property bool daytime: true
  property int battery: -1           // percent, -1 = no battery
  property string batteryMode: ""    // discharging | charging | estimate
  property real batterySeconds: 0    // solid stripe from now: to empty, or to full
  property real batteryAfterSeconds: 0 // dashed stripe after it: runtime on a charge

  readonly property real r: Math.min(width, height) / 2
  // From the outside: dial 8 px, 3 px gap, battery band 8 px, 3 px gap,
  // then the map's edge.
  readonly property real dialR: r - dialWidth / 2
  readonly property real cardinalOut: 3 * unit   // how far the noon triangle and E, S, W stick out
  readonly property real batteryR: r - dialWidth - bandGap - batteryWidth / 2
  readonly property real timeAngle: Model.dialAngle(Model.secondsOfDay(now))
  readonly property color sunColor: "#f6c344"
  readonly property color dayColor: Qt.alpha(sunColor, 0.55)
  readonly property color nightColor: Qt.alpha("#5b8cff", 0.55)
  readonly property color restColor: Qt.alpha(Color.foreground, 0.08)
  readonly property var moon: Model.moonOutline(Model.moonPhase(now.getTime() / 1000), (dialWidth + 6 * unit) / 2)
  // On battery the stripe runs from green (100 %) to red (0 %) and blinks
  // under 10 %; charging it is orange; the runtime a charge would give is green.
  readonly property bool batteryLow: rim.batteryMode === "discharging" && rim.battery >= 0 && rim.battery < 10
  property real blink: 1
  readonly property color batteryColor: rim.batteryMode === "charging" ? "#ff9f43"
    : rim.batteryMode === "discharging" && rim.battery >= 0
      ? Qt.hsla(Math.min(rim.battery, 100) / 100 / 3, 0.75, 0.5, rim.batteryLow ? rim.blink : 1)
      : Qt.alpha(Color.foreground, 0.85)

  SequentialAnimation on blink {
    running: rim.batteryLow && rim.visible
    loops: Animation.Infinite
    onRunningChanged: if (!running) rim.blink = 1
    NumberAnimation { to: 0.15; duration: 500; easing.type: Easing.InOutSine }
    NumberAnimation { to: 1; duration: 500; easing.type: Easing.InOutSine }
  }
  readonly property color runtimeColor: "#7fd88f"
  readonly property real batteryEnd: timeAngle + Model.batterySweep(batterySeconds)

  // Shape angles start at 3 o'clock; the dial starts at 12.
  function shapeAngle(dial) { return dial - 90 }
  function sweep(start, end) { return ((end - start) % 360 + 360) % 360 }

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      strokeColor: rim.restColor
      strokeWidth: rim.dialWidth
      fillColor: "transparent"
      capStyle: ShapePath.FlatCap
      PathAngleArc {
        centerX: rim.r; centerY: rim.r
        radiusX: rim.dialR; radiusY: rim.dialR
        startAngle: 0; sweepAngle: 360
      }
    }

    // Day: sunrise → sunset. Night: sunset → sunrise.
    ShapePath {
      strokeColor: rim.daylight ? (rim.daytime ? rim.dayColor : rim.nightColor) : "transparent"
      strokeWidth: rim.dialWidth
      fillColor: "transparent"
      capStyle: ShapePath.FlatCap
      PathAngleArc {
        centerX: rim.r; centerY: rim.r
        radiusX: rim.dialR; radiusY: rim.dialR
        startAngle: !rim.daylight ? 0 : rim.shapeAngle(rim.daytime ? rim.daylight.start : rim.daylight.end)
        sweepAngle: !rim.daylight ? 0 : (rim.daytime ? rim.sweep(rim.daylight.start, rim.daylight.end)
          : rim.sweep(rim.daylight.end, rim.daylight.start))
      }
    }

    ShapePath {
      strokeColor: rim.batterySeconds > 0 ? rim.batteryColor : "transparent"
      strokeWidth: rim.batteryWidth
      fillColor: "transparent"
      capStyle: ShapePath.FlatCap
      PathAngleArc {
        centerX: rim.r; centerY: rim.r
        radiusX: rim.batteryR; radiusY: rim.batteryR
        startAngle: rim.shapeAngle(rim.timeAngle)
        sweepAngle: Model.batterySweep(rim.batterySeconds)
      }
    }

    ShapePath {
      strokeColor: rim.batteryAfterSeconds > 0 ? rim.runtimeColor : "transparent"
      strokeWidth: rim.batteryWidth
      fillColor: "transparent"
      capStyle: ShapePath.FlatCap
      PathAngleArc {
        centerX: rim.r; centerY: rim.r
        radiusX: rim.batteryR; radiusY: rim.batteryR
        startAngle: rim.shapeAngle(rim.batteryEnd)
        sweepAngle: Math.min(Model.batterySweep(rim.batteryAfterSeconds), 355 - Model.batterySweep(rim.batterySeconds))
      }
    }
  }

  // A pilot's bezel: a downward triangle at the top, E, S and W at the
  // other quarters, and a small tick at each watch hour in between.
  Repeater {
    model: rim.cardinals ? [30, 60, 120, 150, 210, 240, 300, 330] : [0, 30, 60, 90, 120, 150, 180, 210, 240, 270, 300, 330]
    delegate: Rectangle {
      required property var modelData
      width: 1.5 * rim.unit
      height: rim.dialWidth * 0.6
      radius: 1
      color: Qt.alpha(Color.foreground, 0.5)
      x: rim.r + (rim.dialR) * Math.sin(modelData * Math.PI / 180) - width / 2
      y: rim.r - (rim.dialR) * Math.cos(modelData * Math.PI / 180) - height / 2
      rotation: modelData
    }
  }

  Shape {
    id: noon
    visible: rim.cardinals
    // From just past the outer edge down to the middle of the battery band.
    readonly property real tipOut: rim.cardinalOut
    readonly property real h: rim.dialWidth + rim.bandGap + rim.batteryWidth / 2 + tipOut
    readonly property real w: h * 1.25   // wider than tall
    width: w; height: h
    x: rim.r - w / 2
    y: -tipOut
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      fillColor: Color.foreground
      strokeColor: Color.background
      strokeWidth: 1.5 * rim.unit
      joinStyle: ShapePath.MiterJoin
      PathPolyline { path: [Qt.point(0, 0), Qt.point(noon.w, 0), Qt.point(noon.w / 2, noon.h), Qt.point(0, 0)] }
    }
  }

  Repeater {
    model: rim.cardinals ? [{ a: 90, t: "E" }, { a: 180, t: "S" }, { a: 270, t: "W" }] : []
    delegate: Text {
      id: cardinal
      required property var modelData
      // The letter's ink, not its line box, sticks out past the ring's
      // outer edge by `cardinalOut`.
      readonly property rect ink: cardinalInk.tightBoundingRect
      readonly property real half: (modelData.a % 180 === 0 ? ink.height : ink.width) / 2
      readonly property real at: rim.r + rim.cardinalOut - half
      readonly property real a: modelData.a * Math.PI / 180
      x: rim.r + at * Math.sin(a) - ink.x - ink.width / 2
      y: rim.r - at * Math.cos(a) - baselineOffset - ink.y - ink.height / 2
      TextMetrics { id: cardinalInk; font: cardinal.font; text: cardinal.text }
      text: modelData.t
      color: Color.foreground
      style: Text.Outline
      styleColor: Color.background
      font.family: "Noto Sans"
      font.pixelSize: Math.round(rim.dialWidth * 1.7)
      font.weight: Font.Black
    }
  }

  // The sun, or at night the moon in its current phase, on the current time.
  Item {
    id: body
    readonly property real a: rim.timeAngle * Math.PI / 180
    readonly property real br: width / 2
    width: rim.dialWidth + 6 * rim.unit
    height: width
    x: rim.r + rim.dialR * Math.sin(a) - width / 2
    y: rim.r - rim.dialR * Math.cos(a) - height / 2

    Rectangle {
      visible: rim.daytime
      anchors.fill: parent
      radius: width / 2
      color: rim.sunColor
    }

    // The dark side, so a new moon still shows as an outline.
    Rectangle {
      visible: !rim.daytime
      anchors.fill: parent
      radius: width / 2
      color: Color.background
      border.width: 1
      border.color: Qt.alpha(Color.foreground, 0.45)
    }

    // The lit side, between the limb and the terminator.
    Shape {
      visible: !rim.daytime
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        fillColor: "#ece6cf"
        strokeColor: "transparent"
        PathPolyline { path: rim.moon.map(function(p) { return Qt.point(p.x, p.y) }) }
      }
    }
  }

  // A click on the battery band (gaps around it included) opens the
  // battery panel.
  MouseArea {
    anchors.fill: parent
    enabled: rim.battery >= 0
    cursorShape: Qt.PointingHandCursor
    containmentMask: QtObject {
      function contains(p: point): bool {
        var d = Math.hypot(p.x - rim.r, p.y - rim.r)
        return Math.abs(d - rim.batteryR) <= rim.batteryWidth / 2 + rim.bandGap / 2
      }
    }
    onClicked: rim.batteryClicked()
  }
}
