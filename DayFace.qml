import QtQuick
import QtQuick.Shapes
import qs.Commons
import "Model.js" as Model

// The day/night dial's details on the middle circle, while it is hovered:
// the sun's path as a wide arch around the face, from eight o'clock
// (sunrise) over the top to four o'clock (sunset), its golden hours
// (sunrise until the sun is 6° up, 6° until sunset) in orange at both ends
// and the sun where it is now. Inside, large: the day's length, sunrise
// and sunset by each end, and the golden hour under way or next.
Item {
  id: face

  required property var minimap
  property bool shown: false

  readonly property real w: width
  readonly property real now: minimap.nowSec
  readonly property real rise: minimap.sunrise
  readonly property real set: minimap.sunset
  readonly property var sun: minimap.sun
  readonly property bool known: rise > 0 && set > rise
  readonly property bool day: known && now >= rise && now < set
  readonly property real goldenEnd: sun && sun.goldenEnd ? sun.goldenEnd : 0
  readonly property real goldenStart: sun && sun.goldenStart ? sun.goldenStart : 0

  // Along the arch: 0 at sunrise, 1 at sunset.
  function along(t) { return Math.max(0, Math.min(1, (t - rise) / (set - rise))) }

  readonly property color sunColor: "#f6c344"
  readonly property color goldenColor: "#ff9f43"
  // The arch: Qt angles (0 at three o'clock, clockwise), eight o'clock is
  // 150, four o'clock 30 + 360.
  readonly property real archR: w * 0.38
  readonly property real archStart: 150
  readonly property real archSweep: 240
  function archAngle(f) { return (archStart + archSweep * f) * Math.PI / 180 }

  visible: opacity > 0
  opacity: shown ? 1 : 0
  Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }

  Rectangle {
    anchors.fill: parent
    radius: width / 2
    color: Color.background
  }

  Shape {
    anchors.fill: parent
    visible: face.known
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      strokeColor: Qt.alpha(face.sunColor, face.day ? 0.45 : 0.2)
      strokeWidth: 4 * face.minimap.uiScale
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      PathAngleArc { centerX: face.w / 2; centerY: face.w / 2; radiusX: face.archR; radiusY: face.archR; startAngle: face.archStart; sweepAngle: face.archSweep }
    }
    ShapePath {
      strokeColor: face.goldenEnd ? Qt.alpha(face.goldenColor, face.day ? 1 : 0.5) : "transparent"
      strokeWidth: 6 * face.minimap.uiScale
      fillColor: "transparent"
      capStyle: ShapePath.FlatCap
      PathAngleArc {
        centerX: face.w / 2; centerY: face.w / 2; radiusX: face.archR; radiusY: face.archR
        startAngle: face.archStart; sweepAngle: face.archSweep * face.along(face.goldenEnd)
      }
    }
    ShapePath {
      strokeColor: face.goldenStart ? Qt.alpha(face.goldenColor, face.day ? 1 : 0.5) : "transparent"
      strokeWidth: 6 * face.minimap.uiScale
      fillColor: "transparent"
      capStyle: ShapePath.FlatCap
      PathAngleArc {
        centerX: face.w / 2; centerY: face.w / 2; radiusX: face.archR; radiusY: face.archR
        startAngle: face.archStart + face.archSweep * face.along(face.goldenStart)
        sweepAngle: face.archSweep * (1 - face.along(face.goldenStart))
      }
    }
  }

  // The sun where it is now, by day.
  Rectangle {
    readonly property real a: face.archAngle(face.along(face.now))
    visible: face.day
    width: face.w * 0.085; height: width; radius: width / 2
    x: face.w / 2 + face.archR * Math.cos(a) - width / 2
    y: face.w / 2 + face.archR * Math.sin(a) - height / 2
    color: face.sunColor
  }

  // The day's length, in the middle.
  Text {
    visible: face.known
    anchors.horizontalCenter: parent.horizontalCenter
    y: face.w * 0.4 - height / 2
    text: Model.durationText(face.set - face.rise)
    color: Color.foreground
    font.family: Style.fontFamily
    font.pixelSize: Math.round(face.w * 0.13)
    font.bold: true
  }

  // Sunrise and sunset in the opening at the bottom, each on its end's side.
  Repeater {
    model: face.known ? [{ t: face.rise, side: -1 }, { t: face.set, side: 1 }] : []
    delegate: Text {
      required property var modelData
      x: face.w / 2 + modelData.side * face.w * 0.17 - width / 2
      y: face.w * 0.78 - height / 2
      text: face.minimap.hm(modelData.t)
      color: Color.foreground
      font.family: Style.fontFamily
      font.pixelSize: Math.round(face.w * 0.09)
      font.bold: true
    }
  }

  // The golden hour under way, or the next one (tomorrow morning's is close
  // enough to today's after sunset).
  Text {
    readonly property var window: {
      if (!face.goldenEnd || !face.goldenStart) return null
      if (face.now < face.goldenEnd || face.now >= face.set) return [face.rise, face.goldenEnd]
      return [face.goldenStart, face.set]
    }
    visible: window !== null
    anchors.horizontalCenter: parent.horizontalCenter
    y: face.w * 0.56 - height / 2
    text: window ? "golden " + face.minimap.hm(window[0]) + "–" + face.minimap.hm(window[1]) : ""
    color: face.goldenColor
    font.family: Style.fontFamily
    font.pixelSize: Math.round(face.w * 0.068)
    font.bold: true
  }
}
