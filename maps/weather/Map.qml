import QtQuick
import qs.Commons
import "../../Model.js" as Model

// Built-in map: rain radar over the basemap around the weather location,
// with the nowcast line. The minimap fetches the radar, the forecast and
// the tiles; Ctrl+wheel zooms (handled by the minimap). As a notification (rain alert, or
// `omarchy-shell austraz.minimap radar`) it plays the end of the radar loop
// within the notification's 5 s, ending on now.
Item {
  id: view
  required property var minimap
  // Maps stay loaded in the background: only fetch tiles when on screen.
  readonly property bool shown: minimap.shownMap === "weather"
  onShownChanged: {
    if (!shown) return
    if (replayPending) { replayPending = false; weather.replay(replayFrames) }
    minimap.requestTiles(weather.wanted)
  }

  // The 5 s notification: the coin turn (~0.5 s), 8 frames 0.45 s apart,
  // then a moment on the latest.
  readonly property int replayFrames: 8
  property bool replayPending: false
  function playRadar() {
    if (shown) weather.replay(replayFrames)
    else replayPending = true
    minimap.notify(view)
  }

  // Rain alert: X minutes (cfg.rainAlert) before the forecast rain starts,
  // ask the minimap to show this map; once per dry spell. The forecast
  // comes in 15 min steps, so the start time is that precise at best.
  readonly property real rainAt: Model.rainStart(minimap.forecast ? minimap.forecast.rain : [], minimap.nowSec)
  property bool announced: false
  onRainAtChanged: if (rainAt === 0) announced = false
  Timer {
    interval: 15000
    running: view.minimap.cfg.rainAlert > 0 && view.rainAt > 0 && !view.announced
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      if (Date.now() / 1000 < view.rainAt - view.minimap.cfg.rainAlert * 60) return
      view.announced = true
      view.playRadar()
    }
  }

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
    onWantedChanged: if (view.shown) view.minimap.requestTiles(wanted)
    Component.onCompleted: if (view.shown) view.minimap.requestTiles(wanted)
  }
}
