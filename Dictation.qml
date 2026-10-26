import QtQuick
import qs.Commons

// Dictation on the minimap's middle circle. While recording, a ring of bars
// carries the microphone as a wave: each new level enters at noon and runs
// down both sides, so speech reads as ripples flowing round the dial, behind
// a microphone that swells with the voice and a live rim that breathes red.
// Transcribing pulls the bars short and sends a comet circling through them.
// It opens with the bars bursting out of the centre, noon first, and closes
// by drawing them back in before the face folds away.
Item {
  id: face

  property bool shown: false
  property string phase: "idle"
  property real peak: 0
  property bool speech: false

  readonly property bool recording: phase === "recording"
  readonly property int count: 48
  readonly property int half: count / 2
  readonly property real outer: width / 2 - 6
  readonly property real inner: width * 0.3

  property var history: []     // newest first, one per slot from noon down
  property real voice: 0       // smoothed level for the microphone and halo
  property real grow: 0        // bars: 0 tucked in the centre, 1 out
  property real head: 0        // the transcribing comet, in bar slots
  property real pulse: 0.2     // the live rim's breath
  property real wiggle: 0      // the pencil at work

  SequentialAnimation on pulse {
    running: face.visible && face.recording
    loops: Animation.Infinite
    NumberAnimation { to: 0.85; duration: 700; easing.type: Easing.InOutSine }
    NumberAnimation { to: 0.2; duration: 700; easing.type: Easing.InOutSine }
  }

  SequentialAnimation on wiggle {
    running: face.visible && !face.recording
    loops: Animation.Infinite
    NumberAnimation { to: -14; duration: 260; easing.type: Easing.InOutSine }
    NumberAnimation { to: 10; duration: 260; easing.type: Easing.InOutSine }
  }

  visible: shown || closing.running
  scale: 0

  onShownChanged: {
    if (shown) {
      closing.stop()
      history = []
      voice = 0
      opening.restart()
    } else {
      opening.stop()
      closing.restart()
    }
  }

  ParallelAnimation {
    id: opening
    NumberAnimation { target: face; property: "scale"; to: 1; duration: 360; easing.type: Easing.OutBack; easing.overshoot: 1.7 }
    NumberAnimation { target: face; property: "grow"; from: 0; to: 1; duration: 700; easing.type: Easing.OutCubic }
  }

  SequentialAnimation {
    id: closing
    NumberAnimation { target: face; property: "grow"; to: 0; duration: 320; easing.type: Easing.InCubic }
    NumberAnimation { target: face; property: "scale"; to: 0; duration: 200; easing.type: Easing.InBack; easing.overshoot: 2 }
  }

  // The wave moves on at a steady pace whatever rate the levels come in.
  Timer {
    interval: 45
    repeat: true
    running: face.visible && face.recording
    onTriggered: {
      var v = Math.min(1, Math.sqrt(Math.max(0, face.peak)) * 1.1)
      face.voice += (v - face.voice) * 0.35
      face.history = [v].concat(face.history.slice(0, face.half))
    }
  }

  NumberAnimation on head {
    running: face.visible && !face.recording
    from: 0; to: face.count
    duration: 1100
    loops: Animation.Infinite
  }

  Rectangle {
    anchors.fill: parent
    radius: width / 2
    color: Color.background
  }

  // The live rim: red, breathing, while the microphone is open.
  Rectangle {
    id: rim
    anchors.fill: parent
    anchors.margins: 1
    radius: width / 2
    color: "transparent"
    border.width: 2
    border.color: Color.urgent
    opacity: face.recording ? face.pulse : 0
    Behavior on opacity { enabled: !face.recording; NumberAnimation { duration: 250 } }
  }

  // Halo behind the microphone, swelling with the voice.
  Rectangle {
    anchors.centerIn: parent
    width: face.inner * 2 * (0.62 + 0.5 * face.voice) * face.grow
    height: width
    radius: width / 2
    color: Color.accent
    opacity: face.recording ? 0.1 + 0.3 * face.voice : 0.08
    Behavior on width { NumberAnimation { duration: 90 } }
  }

  Repeater {
    model: face.count
    delegate: Item {
      id: bar
      required property int index
      // Slot 0 is noon; both sides count down from it to six o'clock.
      readonly property int slot: index <= face.half ? index : face.count - index
      readonly property real level: face.history[slot] || 0
      // Opening sends the bars out from noon round to six o'clock.
      readonly property real out: Math.max(0, Math.min(1, face.grow * 1.8 - slot / face.half * 0.8))
      // Transcribing: how close the comet is, 1 at its head, fading behind.
      readonly property real comet: {
        var d = (face.head - index + face.count) % face.count
        return Math.max(0, 1 - d / (face.count * 0.4))
      }
      readonly property real length: (face.outer - face.inner)
        * (face.recording ? 0.08 + 0.92 * level : 0.12 + 0.35 * comet * comet)

      x: face.width / 2
      y: face.height / 2
      rotation: index * 360 / face.count

      Rectangle {
        x: -width / 2
        width: 4
        radius: 2
        height: Math.max(3, bar.length) * bar.out
        y: -face.inner * (0.4 + 0.6 * bar.out) - height
        color: face.recording ? Color.accent : Qt.lighter(Color.accent, 1 + 0.5 * bar.comet)
        opacity: face.recording
          ? (face.speech ? 0.45 : 0.25) + 0.55 * bar.level
          : 0.15 + 0.85 * bar.comet
        Behavior on height { NumberAnimation { duration: 70; easing.type: Easing.OutQuad } }
      }
    }
  }

  Text {
    id: glyph
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: face.recording ? "󰍬" : "󰏫"
    color: face.recording && face.speech ? Color.accent : Color.foreground
    Behavior on color { ColorAnimation { duration: 150 } }
    font.family: Style.fontFamily
    font.pixelSize: face.width * 0.2
    scale: (face.recording ? 1 + 0.35 * face.voice : 1) * face.grow
    Behavior on scale { NumberAnimation { duration: 90 } }

    rotation: face.recording ? 0 : face.wiggle
  }
}
