import QtQuick
import QtQuick.Shapes
import qs.Commons

// The radar sweep that clears the rim for a ticker and draws it back after
// (see `ticker` in Minimap.qml): a beam from noon, clockwise, a fading wake
// behind it. Erasing, the dial and the rim bands are gone where it has
// passed; drawing, they are back where it has passed. `mask` is what stays
// of them, for their MultiEffect.
Item {
  id: radar

  required property var minimap
  readonly property real r: Math.min(width, height) / 2
  readonly property real angle: minimap.rimSweep          // the beam, degrees from noon
  readonly property string mode: minimap.rimSweepMode     // erase | draw | ""
  readonly property real inner: minimap.tickerInner
  readonly property real outer: minimap.tickerOuter
  readonly property color beamColor: Color.accent
  property alias mask: maskItem

  function shapeAngle(dial) { return dial - 90 }

  // What stays of the dial and the bands, opaque: still ahead of the beam
  // while erasing; behind it while drawing, plus whatever an interrupted
  // erase had not reached yet.
  Item {
    id: maskItem
    width: radar.width
    height: radar.height
    visible: false
    layer.enabled: true

    Shape {
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        id: ahead
        readonly property real from: radar.mode === "erase" ? radar.angle : 0
        readonly property real to: radar.mode === "erase" ? 360 : (radar.mode === "draw" ? radar.angle : 0)
        fillColor: to > from ? "black" : "transparent"
        strokeColor: "transparent"
        startX: radar.r; startY: radar.r
        PathAngleArc {
          centerX: radar.r; centerY: radar.r
          radiusX: radar.r * 1.5; radiusY: radar.r * 1.5
          startAngle: radar.shapeAngle(ahead.from)
          sweepAngle: Math.max(0, ahead.to - ahead.from)
          moveToStart: false
        }
        PathLine { x: radar.r; y: radar.r }
      }
      ShapePath {
        id: unreached
        readonly property real from: radar.mode === "draw" ? radar.minimap.rimEraseReached : 360
        fillColor: from < 360 ? "black" : "transparent"
        strokeColor: "transparent"
        startX: radar.r; startY: radar.r
        PathAngleArc {
          centerX: radar.r; centerY: radar.r
          radiusX: radar.r * 1.5; radiusY: radar.r * 1.5
          startAngle: radar.shapeAngle(unreached.from)
          sweepAngle: 360 - unreached.from
          moveToStart: false
        }
        PathLine { x: radar.r; y: radar.r }
      }
    }
  }

  // The beam and its wake, faded in at noon and out on coming back to it.
  Item {
    anchors.fill: parent
    visible: radar.mode !== ""
    opacity: Math.min(1, radar.angle / 20, (360 - radar.angle) / 20)

    // The wake: thin slices, fainter the further behind.
    Repeater {
      model: 14
      delegate: Shape {
        id: wake
        required property int index
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        readonly property real slice: 3
        // Not back past noon: the wake grows out of it.
        visible: radar.angle >= (wake.index + 1) * wake.slice
        ShapePath {
          strokeColor: Qt.alpha(radar.beamColor, 0.4 * Math.pow(1 - wake.index / 14, 2))
          strokeWidth: radar.outer - radar.inner
          fillColor: "transparent"
          capStyle: ShapePath.FlatCap
          PathAngleArc {
            centerX: radar.r; centerY: radar.r
            radiusX: (radar.inner + radar.outer) / 2; radiusY: (radar.inner + radar.outer) / 2
            startAngle: radar.shapeAngle(radar.angle - (wake.index + 1) * wake.slice)
            sweepAngle: wake.slice
          }
        }
      }
    }

    // The beam itself, across the cleared ring.
    Rectangle {
      readonly property real a: radar.angle * Math.PI / 180
      readonly property real mid: (radar.inner + radar.outer) / 2
      width: Math.max(2, 2 * radar.minimap.uiScale)
      height: radar.outer - radar.inner + 2
      radius: width / 2
      color: radar.beamColor
      antialiasing: true
      x: radar.r + mid * Math.sin(a) - width / 2
      y: radar.r - mid * Math.cos(a) - height / 2
      rotation: radar.angle
    }
  }
}
