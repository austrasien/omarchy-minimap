import QtQuick
import QtMultimedia
import Quickshell.Io

// A video background, cut like the still one and kept on OWE's clock. OWE
// cannot share its frames while it plays on the desktop (its lock feed
// replaces the desktop output), so the file is decoded here a second time,
// muted, and nudged towards OWE's playback position (`owe render-status`).
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

  MediaPlayer {
    id: player
    source: view.active ? view.source : ""
    loops: MediaPlayer.Infinite
    videoOutput: output
    onSourceChanged: if (source == "") playbackRate = 1
  }

  VideoOutput {
    id: output
    x: view.crop ? -view.crop.clip.x / view.dpr : 0
    y: view.crop ? -view.crop.clip.y / view.dpr : 0
    width: view.crop ? view.crop.sourceSize.width / view.dpr : 0
    height: view.crop ? view.crop.sourceSize.height / view.dpr : 0
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
