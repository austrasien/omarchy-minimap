import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Built-in map: Omarchy's notifications, caught from the files the
// notification daemon keeps for the toasts on screen
// (~/.local/state/omarchy/notifications/*.json). Each one asks the minimap
// for a notification: its icon large in the middle, its text running once
// round the rim as the minimap's ticker (the day/night dial and the rim
// bands step aside meanwhile), fading in at noon, clockwise through 3, 6
// and 9 (upright at 6), fading out back at noon. Shown one after the other. An urgent one
// (critical urgency) waits for the user: a persistent notification of the
// minimap, until clicked or until the daemon closes it.
Item {
  id: view
  required property var minimap

  readonly property string dir: minimap.home + "/.local/state/omarchy/notifications"
  readonly property bool onScreen: minimap.shownMap === "notifications"

  property var temps: []            // notifications in turn
  property var stack: []            // urgent ones, the latest last
  property var current: null        // { id, file, icon, glyph, text, persistent }
  // Nothing to show between notifications: the minimap skips the map then.
  readonly property bool empty: current === null && temps.length === 0 && stack.length === 0
  property var seen: ({})           // file names already taken

  // The text round the rim (the minimap's ticker, see Ticker.qml). Its
  // letters stay once it is done, so they fade where they stand.
  readonly property bool tickerActive: current !== null
  property var tickerChars: []
  property real tickerOffset: 0     // degrees the text's head has travelled
  readonly property real lap: 360 + tickerChars.length * minimap.tickerStep
  readonly property int runMs: Math.round(lap / Math.max(1, minimap.tickerSpeed) * 1000)

  // New files in the directory: a toast just went up.
  Process {
    running: true
    command: ["inotifywait", "-m", "-q", "-e", "close_write", "-e", "moved_to", "-e", "moved_from", "-e", "delete",
      "--format", "%e %f", view.dir]
    stdout: SplitParser {
      onRead: function(line) {
        var sp = line.indexOf(" ")
        var ev = line.slice(0, sp), name = line.slice(sp + 1)
        if (!/\.json$/.test(name)) return
        // An urgent one gone (closed, moved to the history): nothing to
        // wait for. The others expire there long before their text has
        // gone round: they run their course.
        if (/MOVED_FROM|DELETE/.test(ev)) {
          view.settle(function(it) { return it.file === name && it.persistent })
          return
        }
        if (view.seen[name]) return
        var s = ({})
        for (var k in view.seen) s[k] = true
        s[name] = true
        view.seen = s
        reader.queue = reader.queue.concat([name])
        reader.next()
      }
    }
  }

  // Reads the files one at a time.
  Process {
    id: reader
    property var queue: []
    property string file: ""
    function next() {
      if (running || !queue.length) return
      file = queue[0]
      command = ["cat", view.dir + "/" + file]
      queue = queue.slice(1)
      running = true
    }
    stdout: StdioCollector {
      onStreamFinished: {
        try { view.take(JSON.parse(String(text || "{}")), reader.file) } catch (e) {}
        Qt.callLater(reader.next)
      }
    }
  }

  function take(n, file) {
    var summary = String(n.summary || "").trim()
    var body = String(n.body || "").replace(/<[^>]*>/g, "").replace(/\s+/g, " ").trim()
    var text = summary && body ? summary + " — " + body : (summary || body || String(n.app || ""))
    if (text === "") return
    if (text.length > 140) text = text.slice(0, 139) + "…"
    var icon = ""
    if (n.image) icon = minimap.iconUrl(n.image)
    else if (n.appIcon) icon = minimap.iconUrl(n.appIcon)
    else if (n.app) icon = minimap.appIcon(String(n.app))
    var item = { id: String(n.id), file: file, icon: icon, glyph: String(n.glyph || ""), text: text,
                 persistent: Number(n.urgency) >= 2 }
    if (item.persistent) {
      stack = stack.concat([item])
      minimap.notify(view, 0, true)
    } else {
      temps = temps.concat([item])
    }
    refresh()
  }

  // What shows: the first in turn, else the latest urgent one.
  function refresh() {
    var next = temps.length ? temps[0] : (stack.length ? stack[stack.length - 1] : null)
    if (next === current) return
    current = next
    run.stop()
    if (!current) { minimap.dismiss(view); return }
    tickerChars = Array.from(current.text)
    tickerOffset = 0
    // The coin turn takes about half a second before this face shows.
    if (!current.persistent) minimap.notify(view, runMs + 700)
    if (onScreen) run.start()
  }

  function settle(test) {
    temps = temps.filter(function(it) { return !test(it) })
    stack = stack.filter(function(it) { return !test(it) })
    if (!stack.length) minimap.release(view)
    // refresh() sees the current one gone and moves on (or closes): clearing
    // it here first would make "nothing left" look unchanged to it.
    refresh()
  }

  onOnScreenChanged: if (onScreen && current && !run.running) run.start()

  NumberAnimation {
    id: run
    target: view
    property: "tickerOffset"
    from: 0
    to: view.lap
    duration: view.runMs
    onFinished: {
      if (!view.current) return
      // An urgent one goes round again until settled.
      if (view.current.persistent) { if (view.onScreen) run.start(); return }
      var done = view.current
      view.settle(function(it) { return it === done })
    }
  }

  Rectangle {
    anchors.fill: parent
    color: Qt.darker(Color.background, 1.15)
  }

  // Clicking acts like clicking its toast (hidden by hideToasts): the
  // notification's default action, e.g. opening what it announces. It
  // closes the notification, temporary or urgent; the next one in turn
  // shows, else the minimap goes back to the chosen map.
  Process { id: invoker }
  MouseArea {
    anchors.fill: parent
    enabled: view.current !== null && view.onScreen
    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: {
      var done = view.current
      invoker.command = ["omarchy-shell", "notifications", "invoke", done.id]
      invoker.running = true
      view.settle(function(it) { return it === done })
    }
  }

  // The notification's icon, else its glyph, else a bell.
  Image {
    id: icon
    anchors.centerIn: parent
    width: parent.width * 0.62
    height: width
    visible: status === Image.Ready
    source: view.current ? view.current.icon : ""
    sourceSize.width: 256
    sourceSize.height: 256
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
    font.pixelSize: parent.width * 0.45
  }
}
