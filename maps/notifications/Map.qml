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
  // The text runs once the minimap's radar has cleared the rim.
  readonly property bool canRun: onScreen && minimap.tickerReady

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
          // The one blowing away (right-click) goes when its burst is over.
          view.settle(function(it) { return it.file === name && it.persistent && it !== view.dismissing })
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
    // Then the radar clears the rim, and draws it back after.
    if (!current.persistent) minimap.notify(view, runMs + 700 + 2 * minimap.rimSweepMs)
    if (canRun) run.start()
  }

  function settle(test) {
    temps = temps.filter(function(it) { return !test(it) })
    stack = stack.filter(function(it) { return !test(it) })
    if (!stack.length) minimap.release(view)
    // refresh() sees the current one gone and moves on (or closes): clearing
    // it here first would make "nothing left" look unchanged to it.
    refresh()
  }

  onCanRunChanged: if (canRun && current && !run.running && !dismissing) run.start()

  NumberAnimation {
    id: run
    target: view
    property: "tickerOffset"
    from: 0
    to: view.lap
    duration: view.runMs
    onFinished: {
      if (!view.current || view.dismissing) return
      // An urgent one goes round again until settled.
      if (view.current.persistent) { if (view.canRun) run.start(); return }
      var done = view.current
      view.settle(function(it) { return it === done })
    }
  }

  // ------------------------------------------------- dismissed (right-click)
  //
  // The icon winds up (a small pull back), then collapses into a bright
  // point spinning as it goes; the point bursts: a shockwave runs to the
  // rim with a spray of sparks, and the text round the rim is blown
  // outwards letter by letter, from its head. Then the next one in turn.
  property var dismissing: null     // the notification going away
  property real implode: 0          // 0 → 1: the face collapsing (InBack: winds up first)
  property real boom: 0             // 0 → 1: the burst
  property real tickerBurst: 0      // 0 → 1: the rim text blown away (Ticker.qml)

  function dismissCurrent() {
    var done = current
    invoker.command = ["omarchy-shell", "notifications", "dismissId", done.id]
    invoker.running = true
    if (Style.reduceMotion) { settle(function(it) { return it === done }); return }
    dismissing = done
    run.pause()
    dismissAnim.restart()
  }

  // `omarchy-shell austraz.minimap demo notifications dismiss`: the
  // right-click, from a keybind or a script.
  function demo(arg) {
    if (arg === "dismiss" && current && onScreen && !dismissing) dismissCurrent()
  }

  ParallelAnimation {
    id: dismissAnim
    SequentialAnimation {
      NumberAnimation { target: view; property: "implode"; from: 0; to: 1; duration: 340; easing.type: Easing.InBack; easing.overshoot: 2.2 }
      NumberAnimation { target: view; property: "boom"; from: 0; to: 1; duration: 560; easing.type: Easing.OutCubic }
    }
    SequentialAnimation {
      PauseAnimation { duration: 260 }
      NumberAnimation { target: view; property: "tickerBurst"; from: 0; to: 1; duration: 640; easing.type: Easing.OutQuad }
    }
    onFinished: {
      var done = view.dismissing
      // Its letters are gone: they must not come back as the burst resets.
      if (view.current === done) view.tickerChars = []
      view.dismissing = null
      view.implode = 0
      view.boom = 0
      view.tickerBurst = 0
      run.stop()
      view.settle(function(it) { return it === done })
    }
  }

  Rectangle {
    anchors.fill: parent
    color: Qt.darker(Color.background, 1.15)
  }

  // A glow of the accent as it bursts.
  Rectangle {
    anchors.fill: parent
    radius: width / 2
    color: Color.accent
    opacity: view.boom > 0 ? 0.18 * Math.pow(1 - view.boom, 2) : 0
  }

  // Clicking acts like clicking its toast (hidden by hideToasts): the
  // notification's default action, e.g. opening what it announces. It
  // closes the notification, temporary or urgent; the next one in turn
  // shows, else the minimap goes back to the chosen map. A right-click
  // only dismisses it, without its action (and without opening the
  // minimap's settings, which a right-click does elsewhere on the disc).
  Process { id: invoker }
  MouseArea {
    anchors.fill: parent
    enabled: view.current !== null && view.onScreen
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: enabled && !view.dismissing ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: function(mouse) {
      if (view.dismissing) return
      if (mouse.button === Qt.RightButton) { view.dismissCurrent(); return }
      var done = view.current
      invoker.command = ["omarchy-shell", "notifications", "invoke", done.id]
      invoker.running = true
      view.settle(function(it) { return it === done })
    }
  }

  // The face: the notification's icon, else its glyph, else a bell. It
  // collapses on a dismissal.
  Item {
    id: face
    anchors.fill: parent
    scale: Math.max(0, 1 - view.implode)
    rotation: view.implode * 200
    opacity: Math.min(1, 1.6 * (1 - view.implode))

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

  // The point it collapses into: it lights up as the face shrinks, and
  // gives way to the burst.
  Rectangle {
    readonly property real s: view.boom > 0 ? 1 - view.boom : Math.max(0, (view.implode - 0.6) / 0.4)
    anchors.centerIn: parent
    width: view.width * 0.09 * (view.boom > 0 ? 1 + 0.6 * view.boom : s)
    height: width
    radius: width / 2
    color: Qt.lighter(Color.accent, 1.5)
    opacity: view.boom > 0 ? Math.pow(1 - view.boom, 1.5) : s
    visible: opacity > 0
  }

  // The shockwaves: an accent one, and a thinner one just behind.
  Repeater {
    model: 2
    delegate: Rectangle {
      required property int index
      readonly property real t: Math.max(0, Math.min(1, (view.boom - index * 0.14) / (1 - index * 0.14)))
      anchors.centerIn: parent
      width: view.width * (0.08 + 1.0 * t)
      height: width
      radius: width / 2
      color: "transparent"
      border.color: index === 0 ? Color.accent : Color.foreground
      border.width: Math.max(1, view.width * (index === 0 ? 0.035 : 0.015) * (1 - t))
      opacity: t > 0 ? (index === 0 ? 0.9 : 0.5) * (1 - t) : 0
      visible: opacity > 0
    }
  }

  // The sparks, thrown out at slightly uneven angles, speeds and sizes.
  Repeater {
    model: 22
    delegate: Rectangle {
      required property int index
      readonly property real angle: (index * 360 / 22 + ((index * 53) % 17) - 8) * Math.PI / 180
      readonly property real reach: view.width * (0.24 + 0.24 * ((index * 37) % 11) / 10)
      readonly property real d: reach * view.boom
      x: view.width / 2 + d * Math.cos(angle) - width / 2
      y: view.height / 2 + d * Math.sin(angle) - height / 2
      width: view.width * (index % 3 === 0 ? 0.055 : 0.035) * (1 - 0.5 * view.boom)
      height: width
      radius: width / 2
      color: index % 2 ? Color.accent : Qt.lighter(Color.accent, 1.6)
      opacity: view.boom > 0 ? 1 - Math.pow(view.boom, 2.2) : 0
      visible: opacity > 0
    }
  }
}
