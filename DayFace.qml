import QtQuick
import QtQuick.Shapes
import qs.Commons
import "Model.js" as Model

// The day/night dial's details on the middle circle, while it is hovered:
// the sun's path as an arch over the horizon, sunrise on the left and
// sunset on the right, its golden hours (sunrise until the sun is 6° up,
// 6° until sunset) in orange at both ends and the sun where it is now. A
// few things, large: the day's length in the arch, the two times under
// the horizon, and the golden hour under way or next.
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
  readonly property real hy: w * 0.6          // the horizon
  readonly property real archR: w * 0.28

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
      strokeWidth: 3 * face.minimap.uiScale
      fillColor: "transparent"
      capStyle: ShapePath.FlatCap
      PathAngleArc { centerX: face.w / 2; centerY: face.hy; radiusX: face.archR; radiusY: face.archR; startAngle: 180; sweepAngle: 180 }
    }
    ShapePath {
      strokeColor: face.goldenEnd ? Qt.alpha(face.goldenColor, face.day ? 1 : 0.5) : "transparent"
      strokeWidth: 5 * face.minimap.uiScale
      fillColor: "transparent"
      capStyle: ShapePath.FlatCap
      PathAngleArc {
        centerX: face.w / 2; centerY: face.hy; radiusX: face.archR; radiusY: face.archR
        startAngle: 180; sweepAngle: 180 * face.along(face.goldenEnd)
      }
    }
    ShapePath {
      strokeColor: face.goldenStart ? Qt.alpha(face.goldenColor, face.day ? 1 : 0.5) : "transparent"
      strokeWidth: 5 * face.minimap.uiScale
      fillColor: "transparent"
      capStyle: ShapePath.FlatCap
      PathAngleArc {
        centerX: face.w / 2; centerY: face.hy; radiusX: face.archR; radiusY: face.archR
        startAngle: 180 + 180 * face.along(face.goldenStart); sweepAngle: 180 * (1 - face.along(face.goldenStart))
      }
    }
    // The horizon.
    ShapePath {
      strokeColor: Qt.alpha(Color.foreground, 0.35)
      strokeWidth: 1.5 * face.minimap.uiScale
      fillColor: "transparent"
      startX: face.w / 2 - face.archR - face.w * 0.06; startY: face.hy
      PathLine { x: face.w / 2 + face.archR + face.w * 0.06; y: face.hy }
    }
  }

  // The sun where it is now, by day.
  Rectangle {
    readonly property real a: Math.PI * (1 + face.along(face.now))
    visible: face.day
    width: face.w * 0.075; height: width; radius: width / 2
    x: face.w / 2 + face.archR * Math.cos(a) - width / 2
    y: face.hy + face.archR * Math.sin(a) - height / 2
    color: face.sunColor
  }

  // The day's length, in the arch.
  Text {
    visible: face.known
    anchors.horizontalCenter: parent.horizontalCenter
    y: face.hy - face.archR * 0.55 - height / 2
    text: Model.durationText(face.set - face.rise)
    color: Color.foreground
    font.family: Style.fontFamily
    font.pixelSize: Math.round(face.w * 0.1)
    font.bold: true
  }

  // Sunrise and sunset, under each end.
  Repeater {
    model: face.known ? [{ t: face.rise, side: -1 }, { t: face.set, side: 1 }] : []
    delegate: Text {
      required property var modelData
      x: face.w / 2 + modelData.side * face.archR - width / 2
      y: face.hy + face.w * 0.03
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
    y: face.hy + face.w * 0.17
    text: window ? "golden " + face.minimap.hm(window[0]) + "–" + face.minimap.hm(window[1]) : ""
    color: face.goldenColor
    font.family: Style.fontFamily
    font.pixelSize: Math.round(face.w * 0.068)
    font.bold: true
  }
}
