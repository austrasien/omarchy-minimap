import QtQuick
import QtQuick.Shapes
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Commons

// Built-in map: what is playing (MPRIS). The album cover fills the disc,
// a red ring grows clockwise from noon along its edge as the track plays,
// and paused the cover dims under a white pause sign. Click plays/pauses.
// It asks the minimap for a notification on pause, on a skip (with a << or
// >> sign) and 2.5 s before a track ends, so the old cover shows 2.5 s and
// the new one 2.5 s.
Item {
  id: view
  required property var minimap

  // The player that is playing, else a paused one; stopped players do
  // not count.
  readonly property var player: {
    var list = Mpris.players.values
    var paused = null
    for (var i = 0; i < list.length; i++) {
      if (list[i].isPlaying) return list[i]
      if (!paused && list[i].playbackState === MprisPlaybackState.Paused) paused = list[i]
    }
    return paused
  }
  readonly property bool playing: player !== null && player.isPlaying
  // Nothing to show without a player: the minimap skips the map then.
  readonly property bool empty: player === null
  readonly property real progress: player && player.lengthSupported && player.length > 0
    ? Math.max(0, Math.min(1, player.position / player.length)) : 0

  // MPRIS does not push the position; ask for it while playing.
  Timer {
    interval: 500
    running: view.playing && view.player.positionSupported
    repeat: true
    onTriggered: {
      view.player.positionChanged()
      view.checkTrack()
    }
  }

  // ---------------------------------------------------- notifications

  readonly property string trackKey: player
    ? player.dbusName + "|" + player.trackArtist + "|" + player.trackTitle : ""
  property var history: []          // recent track keys, oldest first
  property string endNotified: ""   // track whose ending was announced
  property real endNotifiedAt: 0
  property real lastPosition: 0
  property string skip: ""          // "next" | "prev" while its sign shows

  function showSkip(direction) {
    skip = direction
    skipTimer.restart()
    minimap.notify(view)
  }
  Timer { id: skipTimer; interval: 1500; onTriggered: view.skip = "" }

  onPlayingChanged: if (!playing && player && player.playbackState === MprisPlaybackState.Paused) minimap.notify(view)

  onTrackKeyChanged: {
    var key = trackKey
    if (key === "") return
    var h = history
    var natural = Date.now() - endNotifiedAt < 4000
    if (h.length && h[h.length - 1] !== key && !natural)
      showSkip(h.length >= 2 && h[h.length - 2] === key ? "prev" : "next")
    if (!h.length || h[h.length - 1] !== key) history = h.concat([key]).slice(-10)
    lastPosition = 0
  }

  // A track about to end, or jumping back to its start (previous on a
  // track already playing restarts it).
  function checkTrack() {
    if (!player || !player.lengthSupported || player.length <= 0) return
    var pos = player.position
    if (pos > player.length - 2.5 && endNotified !== trackKey) {
      endNotified = trackKey
      endNotifiedAt = Date.now()
      minimap.notify(view)
    }
    if (lastPosition > 5 && pos < 2) showSkip("prev")
    lastPosition = pos
  }

  // The shell has no Qt network access: remote covers (Spotify, web
  // players) go through curl into the cache first.
  readonly property string artUrl: player ? String(player.trackArtUrl || "") : ""
  readonly property bool remoteArt: /^https?:/.test(artUrl)
  readonly property string artFile: remoteArt ? view.minimap.cacheDir + "/covers/" + Qt.md5(artUrl) + ".img" : ""
  property string cover: ""
  onArtUrlChanged: {
    if (!remoteArt) { cover = artUrl; return }
    cover = ""
    coverFetch.running = false
    coverFetch.running = true
  }
  Component.onCompleted: artUrlChanged()
  Process {
    id: coverFetch
    command: ["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && { [ -s \"$1\" ] || curl -fsSL --max-time 10 -o \"$1\" \"$2\"; }",
      "sh", view.artFile, view.artUrl]
    onExited: function(code) { if (code === 0) view.cover = "file://" + view.artFile }
  }

  Rectangle {
    anchors.fill: parent
    color: Qt.darker(Color.background, 1.15)
  }

  // Nothing playing, or no cover: a note.
  Text {
    anchors.centerIn: parent
    visible: art.status !== Image.Ready
    text: "\u{F075A}"
    color: Qt.alpha(Color.foreground, view.player ? 0.6 : 0.3)
    font.family: Style.fontFamily
    font.pixelSize: parent.width * 0.3
  }

  // Zoomed in a little so the round crop keeps the middle of the cover.
  Image {
    id: art
    anchors.centerIn: parent
    width: parent.width * 1.12
    height: width
    source: view.cover
    fillMode: Image.PreserveAspectCrop
    sourceSize.width: 512
    asynchronous: true
    smooth: true
    mipmap: true
  }

  // Paused: the cover dims under a white pause sign.
  Rectangle {
    anchors.fill: parent
    color: "black"
    opacity: view.player && !view.playing ? 0.55 : 0
    Behavior on opacity { NumberAnimation { duration: 200 } }
  }
  Row {
    anchors.centerIn: parent
    spacing: parent.width * 0.07
    opacity: view.player && !view.playing ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 200 } }
    Repeater {
      model: 2
      Rectangle {
        width: view.width * 0.08
        height: view.width * 0.3
        radius: width / 3
        color: "white"
      }
    }
  }

  // A skip: the cover dims a moment under a white << or >>.
  Rectangle {
    anchors.fill: parent
    color: "black"
    opacity: view.skip !== "" && view.playing ? 0.45 : 0
    Behavior on opacity { NumberAnimation { duration: 200 } }
  }
  Shape {
    id: skipSign
    readonly property real s: view.width * 0.15     // one triangle's width
    readonly property real h: view.width * 0.3
    readonly property bool back: view.skip === "prev"
    width: 2 * s; height: h
    anchors.centerIn: parent
    opacity: view.skip !== "" && view.playing ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 200 } }
    preferredRendererType: Shape.CurveRenderer
    transform: Scale { origin.x: skipSign.s; xScale: skipSign.back ? -1 : 1 }
    ShapePath {
      fillColor: "white"
      strokeColor: "transparent"
      PathPolyline { path: [Qt.point(0, 0), Qt.point(skipSign.s, skipSign.h / 2), Qt.point(0, skipSign.h), Qt.point(0, 0)] }
    }
    ShapePath {
      fillColor: "white"
      strokeColor: "transparent"
      PathPolyline { path: [Qt.point(skipSign.s, 0), Qt.point(2 * skipSign.s, skipSign.h / 2), Qt.point(skipSign.s, skipSign.h), Qt.point(skipSign.s, 0)] }
    }
  }

  // Progress: red, clockwise from noon, on the inner edge of the disc.
  Shape {
    anchors.fill: parent
    visible: view.player !== null && view.progress > 0
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      strokeColor: "#e53935"
      strokeWidth: 8 * (view.minimap.uiScale || 1)
      fillColor: "transparent"
      capStyle: ShapePath.FlatCap
      PathAngleArc {
        centerX: view.width / 2; centerY: view.height / 2
        radiusX: view.width / 2 - 4 * (view.minimap.uiScale || 1); radiusY: radiusX
        startAngle: -90
        sweepAngle: 360 * view.progress
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    enabled: view.player !== null && view.player.canTogglePlaying
    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: view.player.togglePlaying()
  }
}
