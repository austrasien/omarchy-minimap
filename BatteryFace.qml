import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

// The battery band's details on the middle circle, while it is hovered,
// drawn like austraz.power's panel: the five busiest apps as a ring around
// the edge (its TOP CPU bar bent round, same colours, a share each), and in
// the middle the power drawn or taken over the last 15 minutes (its CHARGE
// RATE chart), with the level and the time left under it. The watts come
// from the history austraz.power keeps (watt-history.json, a sample every
// 10 s); the apps from ps, read every 2.5 s while shown. Like austraz.power,
// a share is ps's average since the process started, so a burst shows less.
Item {
  id: face

  required property var minimap
  property bool shown: false

  readonly property real k: minimap.uiScale || 1
  readonly property real w: width
  readonly property var palette: ["#5aa8ff", "#ff7a59", "#3dd68c", "#e0c35a", "#c084fc"]
  readonly property color lineColor: "#5aa8ff"

  visible: opacity > 0
  opacity: shown ? 1 : 0
  Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }

  // ---- the watts, from austraz.power

  readonly property string historyPath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
    + "/omarchy/power/watt-history.json"
  property var points: []
  FileView {
    id: history
    path: face.historyPath
    watchChanges: face.shown
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var list = JSON.parse(text() || "[]")
        face.points = Array.isArray(list) ? list.filter(function(p) { return p && p.t > 0 && p.watts >= 0 }) : []
      } catch (e) {}
    }
  }
  onShownChanged: if (shown) { history.reload(); top.running = true }

  readonly property real t1: points.length ? Math.max(Date.now(), points[points.length - 1].t) : Date.now()
  readonly property real t0: t1 - 15 * 60000
  readonly property real peak: {
    var m = 0
    for (var i = 0; i < points.length; i++) if (points[i].t >= t0) m = Math.max(m, points[i].watts)
    return m
  }
  readonly property real axis: peak <= 0 ? 1 : peak <= 5 ? 5 : peak <= 10 ? 10 : Math.ceil(peak / 10) * 10
  readonly property real watts: points.length ? points[points.length - 1].watts : 0

  // ---- the busiest apps, as austraz.power groups them

  property var apps: []           // [{ name, cpu, count }], the top five
  Process {
    id: top
    command: ["ps", "-eo", "pcpu=,comm=", "--sort=-pcpu"]
    stdout: StdioCollector {
      onStreamFinished: {
        var byName = ({}), order = []
        var lines = String(text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
          var m = /^\s*(\d+(?:\.\d+)?)\s+(.+)$/.exec(lines[i])
          if (!m) continue
          var name = m[2].trim(), cpu = Number(m[1])
          if (name === "ps") continue            // this very read
          if (!byName[name]) { byName[name] = { name: name, cpu: 0, count: 0 }; order.push(name) }
          byName[name].cpu += cpu
          byName[name].count++
        }
        var list = order.map(function(n) { return byName[n] }).sort(function(a, b) { return b.cpu - a.cpu })
        face.apps = list.slice(0, 5).filter(function(a) { return a.cpu > 0 })
      }
    }
  }
  Timer { interval: 2500; running: face.shown; repeat: true; onTriggered: if (!top.running) top.running = true }

  // ---- drawing

  Rectangle {
    anchors.fill: parent
    radius: width / 2
    color: Color.background
  }

  // The apps' ring: a share of the five each, from noon, clockwise.
  readonly property real ringWidth: 0.09 * w
  readonly property font labelFont: Qt.font({ family: Style.fontFamily, pixelSize: Math.round(ringWidth * 0.72), bold: true })
  readonly property real ringR: w / 2 - 3 * k - ringWidth / 2
  readonly property var segments: {
    var total = 0
    for (var i = 0; i < apps.length; i++) total += apps[i].cpu
    var out = [], at = 0, gap = apps.length > 1 ? 3 : 0
    for (var j = 0; j < apps.length; j++) {
      var sweep = total > 0 ? apps[j].cpu / total * 360 : 0
      out.push({ app: apps[j], start: at + gap / 2, sweep: Math.max(0, sweep - gap), color: palette[j % palette.length] })
      at += sweep
    }
    return out
  }

  Repeater {
    model: face.segments
    delegate: Item {
      id: segment
      required property var modelData
      anchors.fill: parent

      Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
          strokeColor: Qt.alpha(segment.modelData.color, 0.85)
          strokeWidth: face.ringWidth
          fillColor: "transparent"
          capStyle: ShapePath.FlatCap
          PathAngleArc {
            centerX: face.w / 2; centerY: face.w / 2
            radiusX: face.ringR; radiusY: face.ringR
            startAngle: segment.modelData.start - 90
            sweepAngle: segment.modelData.sweep
          }
        }
      }

      // The app's name curved along its segment, with its share when that
      // fits too; upright below the middle; nothing when even the name
      // does not fit.
      Item {
        id: label
        anchors.fill: parent
        readonly property real mid: (segment.modelData.start + segment.modelData.sweep / 2) * Math.PI / 180
        readonly property real room: segment.modelData.sweep * Math.PI / 180 * face.ringR - 6 * face.k
        readonly property string name: segment.modelData.app.name
        readonly property string full: name + " " + Math.round(segment.modelData.app.cpu) + "%"
        readonly property string text: ink.advanceWidth(full) <= room ? full : ink.advanceWidth(name) <= room ? name : ""
        readonly property bool below: Math.cos(mid) < 0
        readonly property real total: ink.advanceWidth(text)
        FontMetrics { id: ink; font: face.labelFont }

        Repeater {
          model: label.text.length
          delegate: Text {
            required property int index
            readonly property string ch: label.text.charAt(index)
            readonly property real before: ink.advanceWidth(label.text.slice(0, index))
            readonly property real off: before + ink.advanceWidth(ch) / 2 - label.total / 2
            readonly property real a: label.mid + (label.below ? -off : off) / face.ringR
            x: face.w / 2 + face.ringR * Math.sin(a) - width / 2
            y: face.w / 2 - face.ringR * Math.cos(a) - height / 2
            rotation: a * 180 / Math.PI + (label.below ? 180 : 0)
            text: ch
            color: "#14151f"
            font: face.labelFont
          }
        }
      }
    }
  }

  // The middle: watts now, the last 15 minutes, the level and time left.
  Column {
    anchors.centerIn: parent
    width: face.w * 0.6
    spacing: face.w * 0.02

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: (face.minimap.batteryMode === "charging" ? "↑ " : face.minimap.batteryMode === "discharging" ? "↓ " : "")
        + (face.watts >= 10 ? Math.round(face.watts) : (Math.round(face.watts * 10) / 10)) + " W"
      color: Color.foreground
      font.family: Style.fontFamily
      font.pixelSize: Math.round(face.w * 0.11)
      font.bold: true
    }

    Item {
      id: chart
      width: parent.width
      height: face.w * 0.22
      visible: face.points.length > 1

      readonly property var line: {
        var out = []
        for (var i = 0; i < face.points.length; i++) {
          var p = face.points[i]
          if (p.t < face.t0) continue
          out.push(Qt.point((p.t - face.t0) / (face.t1 - face.t0) * width,
            2 + (1 - Math.min(1, p.watts / face.axis)) * (height - 4)))
        }
        return out
      }

      Rectangle { width: parent.width; height: 1; y: 2; color: Qt.alpha(Color.foreground, 0.12) }
      Rectangle { width: parent.width; height: 1; y: Math.round(parent.height / 2); color: Qt.alpha(Color.foreground, 0.12) }
      Rectangle { width: parent.width; height: 1; y: parent.height - 2; color: Qt.alpha(Color.foreground, 0.12) }

      Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
          strokeColor: "transparent"
          fillColor: Qt.alpha(face.lineColor, 0.16)
          PathPolyline {
            path: {
              var l = chart.line
              if (l.length < 2) return []
              return [Qt.point(l[0].x, chart.height)].concat(l, [Qt.point(l[l.length - 1].x, chart.height)])
            }
          }
        }
        ShapePath {
          strokeColor: face.lineColor
          strokeWidth: 1.8 * face.k
          fillColor: "transparent"
          joinStyle: ShapePath.RoundJoin
          PathPolyline { path: chart.line }
        }
      }

      Text {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 3
        text: face.axis + " W"
        color: Qt.alpha(Color.foreground, 0.45)
        font.family: Style.fontFamily
        font.pixelSize: Math.round(face.w * 0.05)
      }
    }

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: {
        var m = face.minimap
        if (m.batteryPercent < 0) return ""
        var out = m.batteryPercent + " %"
        if (m.batterySeconds > 0) out += (m.batteryMode === "charging" ? " · plein dans " : " · ") + Model.durationText(m.batterySeconds)
        return out
      }
      color: Qt.alpha(Color.foreground, 0.75)
      font.family: Style.fontFamily
      font.pixelSize: Math.round(face.w * 0.065)
      elide: Text.ElideRight
    }
  }
}
