import QtQuick
import qs.Commons
import "../../Model.js" as Model

// Weather radar: Esri basemap, RainViewer reflectivity, Esri labels on
// top, you in the middle. At rest it shows the latest scan; while hovered
// it loops the last two hours.
Item {
  id: map

  property var location: null        // {name, lat, lon}
  property int zoom: 7
  property string basemapStyle: "dark"
  property string radarHost: ""
  property var frames: []            // [{time, path}], oldest first
  property bool animate: false
  property string nowcast: ""
  property real nowSec: Date.now() / 1000

  readonly property var center: map.location ? Model.worldPixel(map.location.lat, map.location.lon, map.zoom) : null
  readonly property var baseTiles: map.center ? Model.tilesFor(map.center.x, map.center.y, map.zoom, map.zoom, map.width) : []
  readonly property var radarTiles: map.center
    ? Model.tilesFor(map.center.x, map.center.y, map.zoom, Math.min(map.zoom, Model.RADAR_MAX_ZOOM), map.width) : []
  readonly property int lastFrame: map.frames.length - 1
  property int shownFrame: lastFrame

  // Tiles come from the disk cache; `ready` holds the files fetch-tiles
  // has confirmed, and `wanted` is what this view needs right now.
  property string cacheDir: ""
  property var ready: ({})

  function src(file) { return map.ready[file] ? "file://" + file : "" }

  readonly property var wanted: {
    var out = []
    if (!map.center || map.cacheDir === "") return out
    for (var i = 0; i < map.baseTiles.length; i++) {
      var t = map.baseTiles[i]
      out.push({ url: Model.basemapUrl(map.basemapStyle, "base", t), file: Model.basemapFile(map.cacheDir, map.basemapStyle, "base", t) })
      out.push({ url: Model.basemapUrl(map.basemapStyle, "labels", t), file: Model.basemapFile(map.cacheDir, map.basemapStyle, "labels", t) })
    }
    var first = map.animate ? 0 : map.lastFrame
    for (var f = Math.max(0, first); f <= map.lastFrame; f++) {
      for (var j = 0; j < map.radarTiles.length; j++) {
        var r = map.radarTiles[j]
        out.push({ url: Model.radarUrl(map.radarHost, map.frames[f].path, r), file: Model.radarFile(map.cacheDir, map.frames[f].path, r) })
      }
    }
    return out
  }

  onLastFrameChanged: shownFrame = lastFrame
  onAnimateChanged: if (!animate) shownFrame = lastFrame

  Timer {
    interval: 450
    repeat: true
    running: map.animate && map.frames.length > 1
    onTriggered: map.shownFrame = map.shownFrame >= map.lastFrame ? 0 : map.shownFrame + 1
  }

  Rectangle {
    anchors.fill: parent
    color: map.basemapStyle === "light" ? "#e8e8e3" : "#1b1c1f"
  }

  Repeater {
    model: map.baseTiles
    delegate: Image {
      required property var modelData
      x: modelData.left; y: modelData.top
      width: modelData.size; height: modelData.size
      source: map.src(Model.basemapFile(map.cacheDir, map.basemapStyle, "base", modelData))
      asynchronous: true
      cache: true
      smooth: true
    }
  }

  // One layer per radar frame. The latest is always loaded; the others only
  // while animating, so an idle minimap costs a handful of tiles.
  Repeater {
    model: map.frames
    delegate: Item {
      id: frameLayer
      required property var modelData
      required property int index
      anchors.fill: parent
      opacity: 0.8
      visible: index === map.shownFrame

      Loader {
        anchors.fill: parent
        active: frameLayer.index === map.lastFrame || map.animate
        sourceComponent: Item {
          Repeater {
            model: map.radarTiles
            delegate: Image {
              required property var modelData
              x: modelData.left; y: modelData.top
              width: modelData.size; height: modelData.size
              source: map.src(Model.radarFile(map.cacheDir, frameLayer.modelData.path, modelData))
              asynchronous: true
              cache: true
              smooth: true
            }
          }
        }
      }
    }
  }

  Repeater {
    model: map.baseTiles
    delegate: Image {
      required property var modelData
      x: modelData.left; y: modelData.top
      width: modelData.size; height: modelData.size
      source: map.src(Model.basemapFile(map.cacheDir, map.basemapStyle, "labels", modelData))
      asynchronous: true
      cache: true
      smooth: true
      opacity: 0.85
    }
  }

  // You are here.
  Item {
    visible: map.location !== null
    anchors.centerIn: parent
    width: 10; height: 10

    Rectangle {
      id: pulse
      anchors.centerIn: parent
      width: 10; height: 10; radius: width / 2
      color: "transparent"
      border.width: 2
      border.color: Color.accent
      SequentialAnimation on scale {
        loops: Animation.Infinite
        NumberAnimation { from: 1; to: 2.6; duration: 1600; easing.type: Easing.OutCubic }
        PauseAnimation { duration: 600 }
      }
      SequentialAnimation on opacity {
        loops: Animation.Infinite
        NumberAnimation { from: 0.9; to: 0; duration: 1600; easing.type: Easing.OutCubic }
        PauseAnimation { duration: 600 }
      }
    }

    Rectangle {
      anchors.centerIn: parent
      width: 8; height: 8; radius: 4
      color: Color.accent
      border.width: 1.5
      border.color: Color.background
    }
  }

  Text {
    visible: map.location === null
    anchors.centerIn: parent
    width: parent.width * 0.7
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.WordWrap
    text: "Lieu inconnu\nomarchy-weather-location"
    color: Color.foreground
    font.family: Style.fontFamily
    font.pixelSize: 11
  }

  // Nowcast and scan age, low in the disc.
  Rectangle {
    readonly property string label: {
      var frame = map.frames[map.shownFrame]
      var age = frame ? Model.frameAge(frame.time, map.nowSec) : ""
      if (map.animate) return age
      return map.nowcast !== "" ? map.nowcast : age
    }
    visible: label !== ""
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: parent.height * 0.12
    width: info.implicitWidth + 12
    height: info.implicitHeight + 4
    radius: height / 2
    color: Qt.alpha(Color.background, 0.8)

    Text {
      id: info
      anchors.centerIn: parent
      text: parent.label
      color: Color.foreground
      font.family: Style.fontFamily
      font.pixelSize: 10
    }
  }
}
