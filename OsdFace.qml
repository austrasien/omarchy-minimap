import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.Commons

// A system OSD on the middle circle. It pops out of the centre with
// the ring spinning in; the level springs to each new value behind
// a glowing head, every step sends a ripple the way it went (out
// when louder, in when softer) and rolls the readout like a
// counter, and crossing 100 % flashes red. Closing unwinds the
// ring and folds the face back into the centre.
// Optional fields: `color` tints the ring and head; `ghost` (0..1) draws a
// pale arc from the level to it (a forecast); `detail` adds small lines
// under the readout; `quiet` fades the face in and out instead (hover
// details, see Minimap.holdOsd).
Item {
  id: osdFace
  required property var minimap
  // Volume always reads on the overdrive scale: 100 % at six
  // o'clock, 200 % back at noon.
  readonly property bool volume: String(minimap.osd.iconKey || "").indexOf("volume") === 0
  readonly property real max: volume ? 200 : Math.max(1, Number(minimap.osd.maxValue || minimap.osd.max) || 100)
  readonly property real value: Number(minimap.osd.value) || 0
  readonly property bool progress: !!minimap.osd.hasProgress
  readonly property bool overdriven: progress && max > 100 && value > 100
  readonly property real target: progress ? Math.max(0, Math.min(1, value / max)) : 0
  readonly property bool quiet: !!minimap.osd.quiet
  // Detail lines need room: smaller icon and readout then.
  readonly property bool detailed: !!minimap.osd.detail
  readonly property color tint: overdriven ? Color.urgent
    : /^#[0-9a-fA-F]{6,8}$/.test(String(minimap.osd.color || "")) ? minimap.osd.color : Color.accent
  readonly property real ghost: progress ? Math.max(0, Math.min(1, Number(minimap.osd.ghost) || 0)) : 0
  readonly property real radius: width / 2 - 4 * minimap.uiScale

  // The ring as drawn: springs after the target, unwinds on close.
  property real level: 0
  property bool springy: false
  Behavior on level {
    enabled: osdFace.springy
    SpringAnimation { spring: 3.2; damping: 0.26; epsilon: 0.0005 }
  }
  readonly property real shownLevel: Math.max(0, Math.min(1.02, level))
  readonly property real headAngle: (-90 + 360 * shownLevel) * Math.PI / 180

  property real lastValue: -1
  property int dir: 1
  property string readout: ""
  property string previousReadout: ""
  property real roll: 1

  function stepped() {
    var v = value
    if (!minimap.osdOpen) {          // opening: no step to show yet
      lastValue = v
      readout = minimap.osd.message || ""
      previousReadout = ""
      roll = 1
      return
    }
    level = target
    if (v === lastValue && readout === (minimap.osd.message || "")) return
    dir = v >= lastValue ? 1 : -1
    lastValue = v
    previousReadout = readout
    readout = minimap.osd.message || ""
    rollAnim.restart()
    ripple.restart()
    kick.restart()
  }

  onOverdrivenChanged: if (overdriven && minimap.osdOpen) flash.restart()

  Connections {
    target: osdFace.minimap
    function onOsdChanged() { osdFace.stepped() }
    function onOsdOpenChanged() {
      if (minimap.osdOpen) {
        closing.stop()
        fadeOut.stop()
        osdFace.springy = false
        osdFace.level = 0
        osdFace.springy = true
        osdFace.level = osdFace.target
        if (osdFace.quiet) fadeIn.restart()
        else opening.restart()
      } else {
        opening.stop()
        fadeIn.stop()
        if (osdFace.quiet) fadeOut.restart()
        else closing.restart()
      }
    }
  }

  visible: minimap.osdOpen || closing.running || fadeOut.running
  scale: 0
  opacity: 0

  ParallelAnimation {
    id: opening
    NumberAnimation { target: osdFace; property: "scale"; to: 1; duration: 380; easing.type: Easing.OutBack; easing.overshoot: 1.8 }
    NumberAnimation { target: osdFace; property: "opacity"; to: 1; duration: 90 }
    NumberAnimation { target: dial; property: "rotation"; from: -120; to: 0; duration: 520; easing.type: Easing.OutCubic }
    NumberAnimation { target: readoutBox; property: "scale"; from: 0.4; to: 1; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
  }

  // The quiet way: no pop, no spin, a short fade.
  SequentialAnimation {
    id: fadeIn
    ScriptAction { script: { osdFace.scale = 1; dial.rotation = 0; readoutBox.scale = 1 } }
    NumberAnimation { target: osdFace; property: "opacity"; to: 1; duration: 140; easing.type: Easing.OutQuad }
  }
  SequentialAnimation {
    id: fadeOut
    NumberAnimation { target: osdFace; property: "opacity"; to: 0; duration: 140; easing.type: Easing.InQuad }
    ScriptAction { script: { osdFace.scale = 0; osdFace.springy = false } }
  }

  SequentialAnimation {
    id: closing
    ParallelAnimation {
      NumberAnimation { target: osdFace; property: "level"; to: 0; duration: 240; easing.type: Easing.InCubic }
      NumberAnimation { target: dial; property: "rotation"; to: 90; duration: 240; easing.type: Easing.InCubic }
      NumberAnimation { target: readoutBox; property: "scale"; to: 0.5; duration: 240; easing.type: Easing.InBack }
    }
    ParallelAnimation {
      NumberAnimation { target: osdFace; property: "scale"; to: 0; duration: 200; easing.type: Easing.InBack; easing.overshoot: 2 }
      NumberAnimation { target: osdFace; property: "opacity"; to: 0; duration: 200; easing.type: Easing.InQuad }
    }
    ScriptAction { script: { osdFace.springy = false; dial.rotation = 0 } }
  }

  Rectangle {
    anchors.fill: parent
    radius: width / 2
    color: Color.background
  }

  // Red flash when the level crosses 100 %.
  Rectangle {
    id: flashDisc
    anchors.fill: parent
    radius: width / 2
    color: Color.urgent
    opacity: 0
    SequentialAnimation {
      id: flash
      NumberAnimation { target: flashDisc; property: "opacity"; to: 0.55; duration: 70 }
      NumberAnimation { target: flashDisc; property: "opacity"; to: 0; duration: 520; easing.type: Easing.OutCubic }
    }
  }

  // A ring that leaves the dial outwards on a step up and falls
  // inwards on a step down.
  Rectangle {
    id: wave
    anchors.centerIn: parent
    width: osdFace.width - 8 * minimap.uiScale
    height: width
    radius: width / 2
    color: "transparent"
    border.width: 3 * minimap.uiScale
    border.color: osdFace.tint
    opacity: 0
    visible: osdFace.progress
    ParallelAnimation {
      id: ripple
      NumberAnimation { target: wave; property: "scale"; from: osdFace.dir > 0 ? 0.96 : 1; to: osdFace.dir > 0 ? 1.16 : 0.62; duration: 460; easing.type: Easing.OutCubic }
      NumberAnimation { target: wave; property: "opacity"; from: 0.85; to: 0; duration: 460; easing.type: Easing.OutQuad }
    }
  }

  Item {
    id: dial
    anchors.fill: parent
    visible: osdFace.progress

    Shape {
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        strokeColor: Qt.alpha(Color.foreground, 0.12)
        strokeWidth: 8 * minimap.uiScale
        fillColor: "transparent"
        PathAngleArc {
          centerX: osdFace.width / 2; centerY: osdFace.height / 2
          radiusX: osdFace.radius; radiusY: radiusX
          startAngle: -90; sweepAngle: 360
        }
      }
      ShapePath {
        strokeColor: osdFace.tint
        Behavior on strokeColor { ColorAnimation { duration: 220 } }
        strokeWidth: 8 * minimap.uiScale
        fillColor: "transparent"
        capStyle: ShapePath.FlatCap
        PathAngleArc {
          centerX: osdFace.width / 2; centerY: osdFace.height / 2
          radiusX: osdFace.radius; radiusY: radiusX
          startAngle: -90; sweepAngle: 360 * osdFace.shownLevel
        }
      }
      // Where the level is heading (a forecast), pale, past the level.
      ShapePath {
        strokeColor: Qt.alpha(osdFace.tint, 0.3)
        strokeWidth: 8 * minimap.uiScale
        fillColor: "transparent"
        capStyle: ShapePath.FlatCap
        PathAngleArc {
          centerX: osdFace.width / 2; centerY: osdFace.height / 2
          radiusX: osdFace.radius; radiusY: radiusX
          startAngle: -90 + 360 * osdFace.shownLevel
          sweepAngle: 360 * Math.max(0, osdFace.ghost - osdFace.shownLevel)
        }
      }
      // The real 100 % when the scale goes past it (volume overdrive).
      ShapePath {
        strokeColor: osdFace.max > 100 ? Color.foreground : "transparent"
        strokeWidth: 12 * minimap.uiScale
        fillColor: "transparent"
        capStyle: ShapePath.FlatCap
        PathAngleArc {
          centerX: osdFace.width / 2; centerY: osdFace.height / 2
          radiusX: osdFace.radius; radiusY: radiusX
          startAngle: -90 + 360 * 100 / osdFace.max - 1; sweepAngle: 2
        }
      }
    }

    // The glowing head at the end of the arc.
    Item {
      id: head
      visible: osdFace.shownLevel > 0.005
      x: osdFace.width / 2 + osdFace.radius * Math.cos(osdFace.headAngle) - width / 2
      y: osdFace.height / 2 + osdFace.radius * Math.sin(osdFace.headAngle) - height / 2
      width: 30 * minimap.uiScale; height: width
      Rectangle {
        anchors.centerIn: parent
        width: head.width; height: width; radius: width / 2
        color: osdFace.tint
        opacity: 0.22
      }
      Rectangle {
        anchors.centerIn: parent
        width: 18 * minimap.uiScale; height: width; radius: width / 2
        color: osdFace.tint
        opacity: 0.45
      }
      Rectangle {
        anchors.centerIn: parent
        width: 10 * minimap.uiScale; height: width; radius: width / 2
        color: Qt.lighter(osdFace.tint, 1.6)
      }
    }
  }

  Column {
    anchors.centerIn: parent
    width: parent.width * (osdFace.detailed ? 0.76 : 0.7)
    spacing: osdFace.width * 0.02
    Text {
      id: osdIcon
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: minimap.osd.icon || ""
      color: osdFace.overdriven ? Color.urgent : Color.foreground
      Behavior on color { ColorAnimation { duration: 220 } }
      font.family: Style.fontFamily
      font.pixelSize: osdFace.width * (osdFace.detailed ? 0.13 : osdFace.progress ? 0.2 : 0.26)
      SequentialAnimation {
        id: kick
        NumberAnimation { target: osdIcon; property: "scale"; to: 1.22; duration: 70; easing.type: Easing.OutQuad }
        NumberAnimation { target: osdIcon; property: "scale"; to: 1; duration: 260; easing.type: Easing.OutBack; easing.overshoot: 3 }
      }
    }
    // The readout rolls like a counter: the old value leaves the
    // way the level went and the new one follows it in.
    Item {
      id: readoutBox
      width: parent.width
      height: current.implicitHeight
      clip: true
      visible: osdFace.readout !== ""
      NumberAnimation { id: rollAnim; target: osdFace; property: "roll"; from: 0; to: 1; duration: 190; easing.type: Easing.OutCubic }
      Text {
        id: current
        width: parent.width
        y: (1 - osdFace.roll) * parent.height * osdFace.dir
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: osdFace.readout
        color: osdFace.overdriven ? Color.urgent : Color.foreground
        Behavior on color { ColorAnimation { duration: 220 } }
        font.family: Style.fontFamily
        font.bold: true
        font.pixelSize: osdFace.width * (osdFace.detailed ? 0.14 : osdFace.progress ? 0.17 : 0.09)
        wrapMode: Text.Wrap
        maximumLineCount: 2
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        y: -osdFace.roll * parent.height * osdFace.dir
        visible: osdFace.roll < 1
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: osdFace.previousReadout
        color: current.color
        opacity: 1 - osdFace.roll
        font: current.font
        wrapMode: Text.Wrap
        maximumLineCount: 2
        elide: Text.ElideRight
      }
    }
    Text {
      width: parent.width
      visible: text !== ""
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: minimap.osd.detail || ""
      color: Qt.alpha(Color.foreground, 0.7)
      font.family: Style.fontFamily
      // Smaller when there are four lines.
      font.pixelSize: Math.round(osdFace.width * (String(minimap.osd.detail || "").split("\n").length > 3 ? 0.058 : 0.065))
      wrapMode: Text.Wrap
      maximumLineCount: 4
      elide: Text.ElideRight
      lineHeight: 0.95
    }
  }
}
