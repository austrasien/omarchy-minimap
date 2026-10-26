import QtQuick
import qs.Commons
import "../../Model.js" as Model

// Built-in map: rain radar over the basemap around the weather location,
// with the nowcast line. The minimap fetches the radar, the forecast and
// the tiles; the wheel zooms.
Item {
  id: view
  required property var minimap

  WeatherMap {
    id: weather
    anchors.fill: parent
    location: view.minimap.location
    zoom: view.minimap.cfg.zoom
    basemapStyle: view.minimap.cfg.basemap === "auto"
      ? (Model.isLightColor(Color.background) ? "light" : "dark") : view.minimap.cfg.basemap
    radarHost: view.minimap.radarHost
    frames: view.minimap.radarFrames
    animate: view.minimap.hovered
    nowcast: view.minimap.forecast ? Model.nowcastLine(view.minimap.forecast.rain, view.minimap.nowSec) : ""
    nowSec: view.minimap.nowSec
    cacheDir: view.minimap.cacheDir
    ready: view.minimap.tilesReady
    onWantedChanged: view.minimap.requestTiles(wanted)
    Component.onCompleted: view.minimap.requestTiles(wanted)
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.NoButton
    onWheel: function(wheel) { view.minimap.setZoom(view.minimap.cfg.zoom + (wheel.angleDelta.y > 0 ? 1 : -1)) }
  }
}
