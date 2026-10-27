import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

// The wallpaper ring around the disc, as if the disc were cut out of the
// window under it, and that window's border carried around the cut.
Item {
  id: view
  required property var minimap

  // The wallpaper ring, under the disc.
  Item {
    id: cutout
    visible: minimap.ring > 0 && minimap.wallpaper !== ""
    anchors.fill: parent
    layer.enabled: visible
    layer.effect: MultiEffect {
      maskEnabled: true
      maskSource: cutoutMask
      maskThresholdMin: 0.5
      maskSpreadAtMin: 1.0
    }

    // Only the piece under the window, cut once by bin/wallpaper-corner and
    // cached on disk: the shell never decodes the full wallpaper.
    readonly property var crop: Model.wallpaperCrop(minimap.wallpaperSize.width, minimap.wallpaperSize.height,
      minimap.windowOrigin.w, minimap.windowOrigin.h, minimap.targetScreen ? minimap.targetScreen.devicePixelRatio : 1,
      Qt.rect(minimap.windowOrigin.x, minimap.windowOrigin.y, view.width, view.height))
    readonly property string cropKey: crop ? [minimap.wallpaper, crop.sourceSize.width, crop.sourceSize.height,
      crop.clip.x, crop.clip.y, crop.clip.width, crop.clip.height].join(" ") : ""
    property string piece: ""
    onCropKeyChanged: cut.start()

    Process {
      id: cut
      property bool again: false
      function start() {
        var c = cutout.crop
        if (!c) return
        if (running) { again = true; return }
        command = [Qt.resolvedUrl("bin/wallpaper-corner").toString().replace(/^[a-z]+:\/\//, ""),
          String(minimap.wallpaper).replace(/^file:\/\//, ""),
          c.sourceSize.width, c.sourceSize.height, c.clip.x, c.clip.y, c.clip.width, c.clip.height].map(String)
        running = true
      }
      stdout: StdioCollector { onStreamFinished: { var p = text.trim(); if (p) cutout.piece = "file://" + p } }
      onExited: if (again) { again = false; start() }
    }

    Image {
      anchors.fill: parent
      source: cutout.piece
      asynchronous: true
      cache: false
      smooth: true
    }
  }

  // The cut: the disc plus the ring, and the window's corner on the side
  // the minimap sits, from the disc centre out to that corner.
  Item {
    id: cutoutMask
    anchors.fill: parent
    layer.enabled: true
    visible: false
    Rectangle {
      x: minimap.cx - minimap.cutR; y: minimap.cy - minimap.cutR
      width: 2 * minimap.cutR; height: width
      radius: width / 2
      color: "black"
    }
    Rectangle {
      x: minimap.cornerRight ? minimap.cx : 0
      y: minimap.cornerBottom ? minimap.cy : 0
      width: minimap.cornerRight ? parent.width - minimap.cx : minimap.cx
      height: minimap.cornerBottom ? parent.height - minimap.cy : minimap.cy
      color: "black"
    }
  }

  // The cut window's border, carried around the cut: active colour when
  // it has focus, inactive otherwise, only where that window really is
  // (its border box) and not across the masked corner.
  Item {
    id: cutBorder
    readonly property var w: minimap.underWindow
    visible: minimap.ring > 0 && w !== null
    x: w ? w.at[0] - minimap.borderSize - minimap.windowOrigin.mx - minimap.windowOrigin.x : 0
    y: w ? w.at[1] - minimap.borderSize - minimap.windowOrigin.my - minimap.windowOrigin.y : 0
    width: w ? w.size[0] + 2 * minimap.borderSize : 0
    height: w ? w.size[1] + 2 * minimap.borderSize : 0
    clip: true

    Shape {
      x: -cutBorder.x; y: -cutBorder.y
      width: view.width; height: view.height
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        strokeColor: cutBorder.w && cutBorder.w.focused ? minimap.activeBorder : minimap.inactiveBorder
        strokeWidth: minimap.borderSize
        fillColor: "transparent"
        capStyle: ShapePath.FlatCap
        PathAngleArc {
          centerX: minimap.cx; centerY: minimap.cy
          radiusX: minimap.cutR + minimap.borderSize / 2; radiusY: radiusX
          // Skip the quarter facing the screen corner (masked).
          startAngle: minimap.cornerRight ? (minimap.cornerBottom ? 90 : 0) : (minimap.cornerBottom ? 180 : 270)
          sweepAngle: 270
        }
      }
    }
  }
}
