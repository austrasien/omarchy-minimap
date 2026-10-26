import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Built-in map: Omarchy's notifications, caught from the files the
// notification daemon keeps for the toasts on screen
// (~/.local/state/omarchy/notifications/*.json). Each one asks the minimap
// for a notification: its icon in the middle, its text running once around
// the inner edge, fading in at noon, clockwise through 3, 6 and 9 (upright
// at 6), fading out back at noon. Shown one after the other.
Item {
  id: view
  required property var minimap

  readonly property string dir: minimap.home + "/.local/state/omarchy/notifications"
  readonly property bool onScreen: minimap.shownMap === "notifications"

  property var pending: []          // notifications waiting their turn
  property var current: null        // { icon, glyph, text }
  property var seen: ({})           // file names already taken
  property real offset: 0           // degrees the text's head has travelled

  // Text along the ring: one monospace cell per character.
  readonly property real radius: width / 2 - 12
  readonly property real step: cell.advanceWidth / Math.max(1, radius) * 180 / Math.PI
  readonly property var chars: current ? Array.from(current.text) : []
  readonly property real speed: 60   // degrees per second
  readonly property real lap: 360 + chars.length * step
  readonly property int runMs: Math.round(lap / speed * 1000)

  TextMetrics {
    id: cell
    font.family: Style.fontFamily
    font.pixelSize: 13
    font.bold: true
    text: "M"
  }

  // New files in the directory: a toast just went up.
  Process {
    running: true
    command: ["inotifywait", "-m", "-q", "-e", "close_write", "-e", "moved_to", "--format", "%f", view.dir]
    stdout: SplitParser {
      onRead: function(name) {
        if (!/\.json$/.test(name) || view.seen[name]) return
        var s = ({})
        for (var k in view.seen) s[k] = true
        s[name] = true
        view.seen = s
        reader.queue = reader.queue.concat([view.dir + "/" + name])
        reader.next()
      }
    }
  }

  // Reads the files one at a time.
  Process {
    id: reader
    property var queue: []
    function next() {
      if (running || !queue.length) return
      command = ["cat", queue[0]]
      queue = queue.slice(1)
      running = true
    }
    stdout: StdioCollector {
      onStreamFinished: {
        try { view.take(JSON.parse(String(text || "{}"))) } catch (e) {}
        Qt.callLater(reader.next)
      }
    }
  }

  function take(n) {
    var summary = String(n.summary || "").trim()
    var body = String(n.body || "").replace(/<[^>]*>/g, "").replace(/\s+/g, " ").trim()
    var text = summary && body ? summary + " — " + body : (summary || body || String(n.app || ""))
    if (text === "") return
    if (text.length > 140) text = text.slice(0, 139) + "…"
    var icon = ""
    if (n.image) icon = minimap.iconUrl(n.image)
    else if (n.appIcon) icon = minimap.iconUrl(n.appIcon)
    else if (n.app) icon = minimap.appIcon(String(n.app))
    pending = pending.concat([{ icon: icon, glyph: String(n.glyph || ""), text: text }])
    if (!current) showNext()
  }

  function showNext() {
    if (!pending.length) { current = null; return }
    current = pending[0]
    pending = pending.slice(1)
    offset = 0
    run.stop()
    // The coin turn takes about half a second before this face shows.
    minimap.notify(view, runMs + 700)
    if (onScreen) run.start()
  }

  onOnScreenChanged: if (onScreen && current && !run.running) run.start()

  NumberAnimation {
    id: run
    target: view
    property: "offset"
    from: 0
    to: view.lap
    duration: view.runMs
    onFinished: view.showNext()
  }

  Rectangle {
    anchors.fill: parent
    color: Qt.darker(Color.background, 1.15)
  }

  // The notification's icon, else its glyph, else a bell.
  Image {
    id: icon
    anchors.centerIn: parent
    width: parent.width * 0.42
    height: width
    visible: status === Image.Ready
    source: view.current ? view.current.icon : ""
    sourceSize.width: 128
    sourceSize.height: 128
    fillMode: Image.PreserveAspectFit
    asynchronous: true
    smooth: true
    mipmap: true
  }
  Text {
    anchors.centerIn: parent
    visible: icon.status !== Image.Ready
    text: view.current && view.current.glyph ? view.current.glyph : "\u{F009A}"
    color: Qt.alpha(Color.foreground, view.current ? 0.85 : 0.3)
    font.family: Style.fontFamily
    font.pixelSize: parent.width * 0.3
  }

  // The text, letter by letter on the ring, upright towards the outside.
  Repeater {
    model: view.chars.length
    delegate: Text {
      required property int index
      // Letters stand with their feet outwards, so the text reads upright
      // at 6 o'clock, running right to left there like a news ticker: its
      // first letter leads.
      readonly property real a: view.offset - index * view.step
      readonly property real rad: a * Math.PI / 180
      visible: a > 0 && a < 360
      opacity: Math.min(1, a / 30, (360 - a) / 30)
      x: view.width / 2 + view.radius * Math.sin(rad) - width / 2
      y: view.height / 2 - view.radius * Math.cos(rad) - height / 2
      rotation: a + 180
      text: view.chars[index] || ""
      color: Color.foreground
      font: cell.font
    }
  }
}
