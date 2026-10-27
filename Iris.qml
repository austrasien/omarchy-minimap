import QtQuick
import QtQuick.Effects
import qs.Commons

// Peeking closes what it holds into its centre and opening grows it back
// out, with a thin accent ring on the moving edge. veil: 1 open, 0 closed.
Item {
  id: iris

  property real veil: 1
  property real centerX: width / 2
  property real centerY: height / 2
  property real openRadius: Math.min(width, height) / 2
  readonly property real radius: openRadius * veil
  default property alias content: clipped.data

  Item {
    id: clipped
    anchors.fill: parent
    layer.enabled: iris.veil < 1
    layer.effect: MultiEffect {
      maskEnabled: true
      maskSource: mask
      maskThresholdMin: 0.5
      maskSpreadAtMin: 1.0
    }
  }

  Item {
    id: mask
    anchors.fill: parent
    layer.enabled: true
    visible: false
    Rectangle {
      x: iris.centerX - iris.radius; y: iris.centerY - iris.radius
      width: 2 * iris.radius; height: width
      radius: width / 2
      color: "black"
    }
  }

  Rectangle {
    visible: iris.veil > 0.02 && iris.veil < 0.98
    x: iris.centerX - iris.radius; y: iris.centerY - iris.radius
    width: 2 * iris.radius; height: width
    radius: width / 2
    color: "transparent"
    border.width: 2
    border.color: Color.accent
    opacity: Math.sin(Math.PI * iris.veil)
  }
}
