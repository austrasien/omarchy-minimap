import QtQuick
import QtMultimedia
import Quickshell.Io

// A video background, cut like the still one and kept on OWE's clock. OWE
// cannot share its frames while it plays on the desktop (its lock feed
// replaces the desktop output), so the file is decoded here a second time,
// muted, and nudged towards OWE's playback position (`owe render-status`).
// Only the piece under the item is decoded: bin/wallpaper-video-corner cuts
// it once into ~/.cache; until that is done, the whole video plays clipped.
Item {
  id: view
  // file:// URL of the video.
  property string source: ""
  // Model.wallpaperCrop(): the scaled size and the clip, in device px.
  property var crop: null
  property real dpr: 1
  // False stops the decode (hidden, or the cut is off).
  property bool active: true

  clip: true

  // The cut piece: its file and where it sits, in device px from the clip.
  property string piece: ""
  property rect pieceRect: Qt.rect(0, 0, 0, 0)
  readonly property string cropKey: active && crop ? [source, crop.sourceSize.width, crop.sourceSize.height,
    crop.clip.x, crop.clip.y, crop.clip.width, crop.clip.height].join(" ") : ""
  onCropKeyChanged: {
    piece = ""
    cut.start()
  }

  Process {
    id: cut
    property bool again: false
    function start() {
      var c = view.crop
      if (!view.active || !c || view.source === "") return
      if (running) { again = true; return }
      command = [Qt.resolvedUrl("bin/wallpaper-video-corner").toString().replace(/^[a-z]+:\/\//, ""),
        String(view.source).replace(/^file:\/\//, ""),
        c.sourceSize.width, c.sourceSize.height, c.clip.x, c.clip.y, c.clip.width, c.clip.height].map(String)
      running = true
    }
    stdout: StdioCollector {
      onStreamFinished: {
        // A newer cut is queued: this one is stale.
        if (cut.again) return
        var m = /^(-?\d+) (-?\d+) (\d+) (\d+) (.+)$/.exec(String(text).trim())
        if (!m) return
        view.pieceRect = Qt.rect(Number(m[1]), Number(m[2]), Number(m[3]), Number(m[4]))
        view.piece = "file://" + m[5]
      }
    }
    onExited: if (again) { again = false; start() }
  }

  MediaPlayer {
    id: player
    source: !view.active ? "" : view.piece !== "" ? view.piece : view.source
    loops: MediaPlayer.Infinite
    videoOutput: output
    onSourceChanged: {
      playbackRate = 1
      view.synced = false
    }
  }

  VideoOutput {
    id: output
    readonly property bool cut: view.piece !== ""
    x: cut ? view.pieceRect.x / view.dpr : view.crop ? -view.crop.clip.x / view.dpr : 0
    y: cut ? view.pieceRect.y / view.dpr : view.crop ? -view.crop.clip.y / view.dpr : 0
    width: cut ? view.pieceRect.width / view.dpr : view.crop ? view.crop.sourceSize.width / view.dpr : 0
    height: cut ? view.pieceRect.height / view.dpr : view.crop ? view.crop.sourceSize.height / view.dpr : 0
    fillMode: VideoOutput.Stretch
  }

  // Polls OWE quickly until the two decodes line up, then every few seconds.
  property bool synced: false
  Timer {
    interval: view.synced ? 3000 : 400
    running: view.active && view.source !== ""
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!status.running) { status.sentAt = Date.now(); status.running = true }
    onRunningChanged: if (!running) view.synced = false
  }

  Process {
    id: status
    property real sentAt: 0
    command: ["owe", "render-status"]
    stdout: StdioCollector {
      onStreamFinished: {
        try { view.follow(JSON.parse(text), (Date.now() - status.sentAt) / 2000) } catch (e) {}
      }
    }
  }

  // Seeks when far off (start, background switch, OWE resumed), otherwise
  // speeds up or slows down a little so the gap closes without a jump.
  function follow(s, latency) {
    if (!view.active || !s || s.status !== "ok") return
    if (s.kind !== "video" || s.paused || !s.ready) {
      player.pause()
      view.synced = false
      return
    }
    var duration = player.duration / 1000
    if (!(duration > 0)) {
      player.play()
      return
    }
    var target = (s.time_pos + latency) % duration
    if (player.playbackState !== MediaPlayer.PlayingState) {
      player.position = Math.round(target * 1000)
      player.play()
      return
    }
    // Ahead of OWE is negative, behind is positive, across the loop seam.
    var gap = target - player.position / 1000
    gap = ((gap % duration) + 1.5 * duration) % duration - duration / 2
    if (Math.abs(gap) > 0.25) {
      player.position = Math.round(target * 1000)
      player.playbackRate = 1
      view.synced = false
    } else if (Math.abs(gap) <= 0.05) {
      // Within a frame (positions only move frame by frame): leave it.
      player.playbackRate = 1
      view.synced = true
    } else {
      // Closes the gap over about two seconds.
      player.playbackRate = 1 + Math.max(-0.1, Math.min(0.1, gap / 2))
      view.synced = false
    }
  }
}
