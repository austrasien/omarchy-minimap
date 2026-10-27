import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.Commons
import "../../Model.js" as Model

// The current workspace stretched onto the disc (one window fills it, two
// side by side make two half discs), with the other occupied workspaces as
// equal arcs around it, in order clockwise from the top. Every window shows
// its app icon in the middle of its visible part. Agents show the same way
// on their window and on their workspace's arc: a fast red blink when
// blocked on a permission prompt, a slow theme-accent blink when a turn is
// done, theme-accent rings for as long as they work. The current workspace is only the disc; while you switch, the
// arc you are heading to closes in the theme accent.
Item {
  id: map

  property var arcs: []              // from Model.workspaceArcs
  property int bandWidth: 14
  property int bandGap: 3
  property real uiScale: 1           // the fixed sizes below are for a 210 px disc
  property var markers: ({})         // address → working | waiting | done
  property var lastFocus: ({})       // address → epoch seconds
  property var deskVisits: ({})      // workspace id → epoch seconds it was last left
  property real fogSince: 0          // windows not focused since start count from here
  property real nowSec: Date.now() / 1000

  readonly property real inset: bandWidth + bandGap

  signal focusWindow(string address)
  signal focusWorkspace(int id)
  signal moveWindow(string address, int workspace)

  // Dragging a window: its icon follows the pointer, the arc under it
  // lights up, and dropping it there sends the window to that workspace.
  property string dragAddress: ""
  property string dragIcon: ""
  property point dragPoint: Qt.point(0, 0)
  property var dragTiles: []
  readonly property var dropArc: {
    if (map.dragAddress === "") return null
    var dx = map.dragPoint.x - width / 2, dy = map.dragPoint.y - height / 2
    if (Math.sqrt(dx * dx + dy * dy) < width / 2 - map.inset) return null
    return Model.arcAt(map.arcs, Model.pointAngle(map.dragPoint.x, map.dragPoint.y, width))
  }

  // Shared blink clocks so every marker of a kind pulses in step.
  property real slowPulse: 1
  property real fastPulse: 1
  // A turn finished on the current desk: three quick accent blinks.
  property real donePulse: 1
  SequentialAnimation on donePulse {
    loops: Animation.Infinite
    NumberAnimation { from: 1; to: 0.2; duration: 350; easing.type: Easing.InOutSine }
    NumberAnimation { from: 0.2; to: 1; duration: 350; easing.type: Easing.InOutSine }
  }
  SequentialAnimation on slowPulse {
    loops: Animation.Infinite
    NumberAnimation { from: 1; to: 0.2; duration: 1200; easing.type: Easing.InOutSine }
    NumberAnimation { from: 0.2; to: 1; duration: 1200; easing.type: Easing.InOutSine }
  }
  SequentialAnimation on fastPulse {
    loops: Animation.Infinite
    NumberAnimation { from: 1; to: 0.15; duration: 250 }
    NumberAnimation { from: 0.15; to: 1; duration: 250 }
  }

  // Shared clock for the working rings: tiles are rebuilt on every terrain
  // refresh, so a per-tile animation would restart and jump back.
  property real ripplePhase: 0
  NumberAnimation on ripplePhase {
    loops: Animation.Infinite
    from: 0; to: 1
    duration: 4500
  }

  function markerColor(state) {
    return state === "waiting" ? Color.urgent : Color.accent
  }

  function pulseFor(state) {
    return state === "waiting" ? map.fastPulse : (state === "done" ? map.slowPulse : 1)
  }

  function mixColor(a, b, k) {
    return Qt.rgba(a.r + (b.r - a.r) * k, a.g + (b.g - a.g) * k, a.b + (b.b - a.b) * k, a.a + (b.a - a.a) * k)
  }

  // The arc opening for the workspace you leave keeps the accent of the disc
  // landing in it, then fades to its own colour over the end of the switch.
  readonly property real settle: Math.max(0, Math.min(1, (map.t - 0.55) / 0.45))

  function restingColor(arc) {
    if (arc.state === "waiting" || arc.state === "done") return map.markerColor(arc.state)
    // Plain grey, darkening towards black the longer the desk goes unvisited.
    var grey = map.mixColor(Qt.darker(Color.background, 1.15), Color.foreground, 0.3)
    var idle = map.nowSec - (map.deskVisits[arc.id] || map.fogSince)
    return map.mixColor(grey, Qt.rgba(0, 0, 0, 1), Model.deskDarkness(idle))
  }

  function arcColor(arc) {
    if (arc.leaving) return map.mixColor(Color.accent, map.restingColor(arc), map.settle)
    if (arc.arriving) return Color.accent
    return map.restingColor(arc)
  }

  Rectangle {
    anchors.fill: parent
    color: Qt.darker(Color.background, 1.15)
  }

  // Band: click goes to the workspace under the pointer.
  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    readonly property var arc: {
      if (!containsMouse) return null
      var dx = mouseX - width / 2, dy = mouseY - height / 2
      if (Math.sqrt(dx * dx + dy * dy) < width / 2 - map.inset) return null
      return Model.arcAt(map.arcs, Model.pointAngle(mouseX, mouseY, width))
    }
    cursorShape: arc ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: if (arc) map.focusWorkspace(arc.id)
  }

  // The repeaters are keyed by workspace id so the switch animation only
  // moves arcs; it never rebuilds them frame by frame.
  Repeater {
    model: map.arcIds
    delegate: Shape {
      id: arcShape
      required property var modelData
      readonly property var arc: map.arcFor(modelData)
      anchors.fill: parent
      visible: arc !== null
      opacity: !arc ? 0 : (arc.leaving ? 1 + (map.pulseFor(arc.state) - 1) * map.settle : map.pulseFor(arc.state))
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        strokeColor: !arcShape.arc ? "transparent"
          : (map.dropArc && map.dropArc.id === arcShape.arc.id ? Color.accent : map.arcColor(arcShape.arc))
        strokeWidth: map.bandWidth
        fillColor: "transparent"
        capStyle: ShapePath.FlatCap
        PathAngleArc {
          centerX: map.width / 2; centerY: map.height / 2
          radiusX: map.width / 2 - map.bandWidth / 2; radiusY: radiusX
          startAngle: arcShape.arc ? arcShape.arc.start - 90 : 0
          sweepAngle: arcShape.arc ? arcShape.arc.sweep : 0
        }
      }
    }
  }

  // Working agents: accent rings centred on the disc, crossing their arc
  // from the inside out, like the rings spreading over a window.
  Repeater {
    model: map.arcIds
    delegate: Item {
      id: arcRipple
      required property var modelData
      readonly property var arc: map.arcFor(modelData)
      readonly property bool on: arc !== null && arc.state === "working" && !map.switching
      visible: on
      anchors.fill: parent
      layer.enabled: on
      layer.effect: MultiEffect {
        maskEnabled: true
        maskSource: arcMask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
      }

      readonly property real bandR: map.width / 2 - map.bandWidth / 2
      // Rings centred on the disc, crossing the band from its inner edge
      // outwards: waves from the centre, seen through the arc.
      readonly property real ox: map.width / 2
      readonly property real oy: map.height / 2
      readonly property real innerR: map.width / 2 - map.bandWidth
      readonly property real phase: map.ripplePhase

      Repeater {
        model: 2
        delegate: Rectangle {
          required property int index
          readonly property real t: (arcRipple.phase + index / 2) % 1
          readonly property real p: 1 - (1 - t) * (1 - t)
          readonly property real r: arcRipple.innerR + map.bandWidth * p
          x: arcRipple.ox - r; y: arcRipple.oy - r
          width: 2 * r; height: 2 * r
          radius: r
          color: "transparent"
          border.width: 2.5 * map.uiScale
          border.color: Color.accent
          opacity: Math.sin(Math.PI * t) * 0.8
        }
      }

      Shape {
        id: arcMask
        anchors.fill: parent
        visible: false
        layer.enabled: arcRipple.on
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
          strokeColor: "black"
          strokeWidth: map.bandWidth
          fillColor: "transparent"
          capStyle: ShapePath.FlatCap
          PathAngleArc {
            centerX: map.width / 2; centerY: map.height / 2
            radiusX: arcRipple.bandR; radiusY: radiusX
            startAngle: arcRipple.arc ? arcRipple.arc.start - 90 : 0
            sweepAngle: arcRipple.arc ? arcRipple.arc.sweep : 0
          }
        }
      }
    }
  }

  // On each arc, its apps' icons side by side along the band, centred on
  // the arc; "+n" when they do not all fit. Holding Super swaps them for
  // the desk number, as does a desk whose icons could not be found.
  Repeater {
    model: map.arcIds
    delegate: Item {
      id: arcLabels
      required property var modelData
      readonly property var arc: map.arcFor(modelData)
      readonly property real dist: map.width / 2 - map.bandWidth / 2
      readonly property var slots: Model.arcIconSlots(arc, dist, map.bandWidth - 3 * map.uiScale, 2 * map.uiScale)
      readonly property bool numbered: map.numbersShown || slots.length === 0
      readonly property color ink: arc && (arc.arriving || (arc.leaving && map.settle < 0.5) || arc.state === "waiting" || arc.state === "done")
        ? Color.background : Color.foreground
      anchors.fill: parent

      Text {
        readonly property real a: arcLabels.arc ? arcLabels.arc.mid * Math.PI / 180 : 0
        x: map.width / 2 + arcLabels.dist * Math.sin(a) - width / 2
        y: map.height / 2 - arcLabels.dist * Math.cos(a) - height / 2
        visible: opacity > 0
        opacity: arcLabels.arc !== null && arcLabels.arc.sweep > 14 && arcLabels.numbered ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
        // The scratchpad (negative id) reads "0", as in Spaces.
        text: arcLabels.modelData < 0 ? "0" : String(arcLabels.modelData)
        color: arcLabels.ink
        font.family: Style.fontFamily
        font.pixelSize: Math.round(11 * map.uiScale)
        font.bold: true
      }

      Item {
        anchors.fill: parent
        visible: opacity > 0
        opacity: arcLabels.numbered ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 150 } }

        Repeater {
          model: arcLabels.slots
          delegate: Item {
            required property var modelData
            readonly property real a: modelData.angle * Math.PI / 180
            width: map.bandWidth - 6 * map.uiScale; height: width
            x: map.width / 2 + arcLabels.dist * Math.sin(a) - width / 2
            y: map.height / 2 - arcLabels.dist * Math.cos(a) - height / 2

            Image {
              anchors.fill: parent
              visible: modelData.icon !== undefined
              source: modelData.icon || ""
              sourceSize.width: 64; sourceSize.height: 64
              asynchronous: true
              smooth: true
              mipmap: true
            }
            Text {
              anchors.centerIn: parent
              visible: modelData.more !== undefined
              text: "+" + modelData.more
              color: arcLabels.ink
              font.family: Style.fontFamily
              font.pixelSize: Math.round(9 * map.uiScale)
              font.bold: true
            }
          }
        }
      }
    }
  }

  // A workspace on the inner disc. Each window is drawn as its rectangle
  // cut to the circle, so the outer edges follow the round.
  component TerrainLayer: Item {
    id: terrain
    property var tiles: []
    property bool interactive: true
    width: map.width - 2 * map.inset
    height: width

    Repeater {
      model: terrain.tiles
      delegate: Item {
        id: tile
        required property var modelData
        readonly property string marker: map.markers[modelData.address] || ""
        readonly property var outline: Model.tileOutline(modelData.x, modelData.y,
          modelData.w, modelData.h, terrain.width, 1.5)
        // Middle of the visible part, in tile coordinates.
        readonly property var centre: {
          var c = Model.polygonCentroid(outline)
          return { x: c.x - modelData.x, y: c.y - modelData.y, area: c.area }
        }
        x: modelData.x; y: modelData.y
        width: modelData.w; height: modelData.h
        // A working window sits above the others so its rings cross them.
        z: marker === "working" ? 3 : (modelData.floating ? 2 : 1)
        opacity: map.dragAddress === modelData.address ? 0.35
          : modelData.focused || marker !== "" ? 1
          : Model.fogOpacity(map.lastFocus[modelData.address] || map.fogSince, map.nowSec, 0.3)

        Behavior on opacity { NumberAnimation { duration: 600 } }

        Shape {
          x: -tile.x; y: -tile.y
          width: terrain.width; height: terrain.height
          preferredRendererType: Shape.CurveRenderer
          ShapePath {
            fillColor: tile.modelData.focused ? Qt.alpha(Color.accent, 0.35) : Qt.alpha(Color.foreground, 0.2)
            strokeColor: tile.modelData.focused ? Color.accent : Qt.alpha(Color.foreground, 0.4)
            strokeWidth: (tile.modelData.focused ? 1.5 : 1) * map.uiScale
            joinStyle: ShapePath.RoundJoin
            PathPolyline {
              path: tile.outline.map(function(p) { return Qt.point(p.x, p.y) })
            }
          }
        }

        // Agent state, the same as on the arcs: blocked = fast red blink,
        // done = slow accent blink, working = accent rings spreading from the
        // app icon over the whole disc for as long as it works, so the rings
        // of two working windows cross.
        Shape {
          visible: tile.marker === "waiting" || tile.marker === "done"
          x: -tile.x; y: -tile.y
          width: terrain.width; height: terrain.height
          opacity: tile.marker === "done" ? map.donePulse : map.pulseFor(tile.marker)
          preferredRendererType: Shape.CurveRenderer
          ShapePath {
            fillColor: Qt.alpha(map.markerColor(tile.marker), 0.45)
            strokeColor: map.markerColor(tile.marker)
            strokeWidth: 2 * map.uiScale
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: tile.outline.map(function(p) { return Qt.point(p.x, p.y) }) }
          }
        }

        Item {
          id: ripple
          readonly property bool on: tile.marker === "working"
          visible: on
          x: -tile.x; y: -tile.y
          width: terrain.width; height: terrain.height
          layer.enabled: on
          layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: rippleMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
          }

          readonly property real ox: tile.x + tile.centre.x
          readonly property real oy: tile.y + tile.centre.y
          // Far enough to reach the farthest point of the disc.
          readonly property real reach: {
            var c = terrain.width / 2
            return Math.hypot(ox - c, oy - c) + c
          }
          readonly property real phase: map.ripplePhase

          Repeater {
            model: 2
            delegate: Rectangle {
              required property int index
              // Calm: rings ease out as they widen and fade softly.
              readonly property real t: (ripple.phase + index / 2) % 1
              readonly property real p: 1 - (1 - t) * (1 - t)
              readonly property real r: Math.max(1, ripple.reach * p)
              x: ripple.ox - r; y: ripple.oy - r
              width: 2 * r; height: 2 * r
              radius: r
              color: "transparent"
              border.width: 2.5 * map.uiScale
              border.color: Color.accent
              opacity: Math.sin(Math.PI * t) * 0.8
            }
          }
        }

        Rectangle {
          id: rippleMask
          x: -tile.x; y: -tile.y
          width: terrain.width; height: terrain.height
          radius: width / 2
          color: "black"
          visible: false
          layer.enabled: ripple.on
        }

        MouseArea {
          anchors.fill: parent
          enabled: terrain.interactive
          // No hover here: the band's area below tracks the pointer alone.
          cursorShape: map.dragAddress === tile.modelData.address ? Qt.ClosedHandCursor : Qt.PointingHandCursor
          preventStealing: true
          property point pressAt: Qt.point(0, 0)
          onPressed: function(mouse) { pressAt = Qt.point(mouse.x, mouse.y) }
          onPositionChanged: function(mouse) {
            if (map.dragAddress === "" && Math.hypot(mouse.x - pressAt.x, mouse.y - pressAt.y) > 6) {
              map.dragIcon = tile.modelData.icon || ""
              map.dragTiles = map.terrain ? map.terrain.windows : []
              map.dragAddress = tile.modelData.address
            }
            if (map.dragAddress !== "") map.dragPoint = mapToItem(map, mouse.x, mouse.y)
          }
          onReleased: {
            if (map.dragAddress === "") { map.focusWindow(tile.modelData.address); return }
            var target = map.dropArc
            if (target) map.moveWindow(map.dragAddress, target.id)
            map.dragAddress = ""
          }
          onCanceled: map.dragAddress = ""
        }

        // Every window shows its app icon in the middle of its visible part.
        Image {
          id: appIcon
          visible: status === Image.Ready
          readonly property real side: Math.min(30 * map.uiScale, Math.max(12 * map.uiScale, Math.sqrt(tile.centre.area) * 0.4))
          width: side; height: side
          x: tile.centre.x - width / 2
          y: tile.centre.y - height / 2
          source: tile.modelData.icon || ""
          sourceSize.width: 64; sourceSize.height: 64
          asynchronous: true
          smooth: true
          mipmap: true
        }
      }
    }
  }


  // Switching workspace: the workspace you leave shrinks into the arc that
  // opens for it on the band, while the one you go to grows out of its arc,
  // which closes; the other arcs slide to their new places.
  property var terrain: ({ id: -1, windows: [] })   // { id, windows } from Minimap
  property int shownId: -1
  property var shownWindows: []
  property var leavingWindows: []
  property int leavingId: -1
  property int arrivingId: -1
  property var fromArcs: []
  property var latestArcs: []
  property var olderArcs: []
  property real t: 1                // 0 → 1 over the switch
  readonly property bool switching: t < 1
  readonly property real bandR: map.width / 2 - map.bandWidth / 2
  readonly property real dotScale: map.bandWidth / (map.width - 2 * map.inset)
  readonly property var shownArcs: map.switching ? Model.blendArcs(map.fromArcs, map.arcs, map.t) : map.arcs
  // Each disc rides the middle of its own arc as that arc opens or closes.
  readonly property real leavingAngle: map.arcAngle(map.shownArcs, map.leavingId, map.arcAngle(map.arcs, map.leavingId, 0))
  readonly property real arrivingAngle: map.arcAngle(map.shownArcs, map.arrivingId, map.arcAngle(map.fromArcs, map.arrivingId, map.leavingAngle + 180))
  property var arcIds: []
  onShownArcsChanged: {
    var ids = map.shownArcs.map(function(a) { return a.id }).sort(function(a, b) { return a - b })
    if (ids.join(",") !== map.arcIds.join(",")) map.arcIds = ids
  }
  function arcFor(id) {
    var arcs = map.shownArcs
    for (var i = 0; i < arcs.length; i++) if (arcs[i].id === id) return arcs[i]
    return null
  }

  function arcAngle(arcs, id, fallback) {
    for (var i = 0; i < arcs.length; i++) if (arcs[i].id === id) return arcs[i].mid
    return fallback
  }

  // Keep the layout from before the switch: arcs and terrain both follow
  // the current workspace, in either order.
  onArcsChanged: { map.olderArcs = map.latestArcs; map.latestArcs = map.arcs }

  onTerrainChanged: {
    var next = map.terrain || { id: -1, windows: [] }
    if (next.id !== map.shownId && map.shownId > 0 && next.id > 0 && map.visible) {
      map.leavingWindows = map.shownWindows
      map.leavingId = map.shownId
      map.arrivingId = next.id
      map.fromArcs = map.arcAngle(map.latestArcs, next.id, null) !== null ? map.latestArcs : map.olderArcs
      switchAnim.restart()
    }
    map.shownId = next.id
    map.shownWindows = next.windows
  }

  NumberAnimation {
    id: switchAnim
    target: map
    property: "t"
    from: 0; to: 1
    duration: 420
    easing.type: Easing.InOutCubic
  }

  TerrainLayer {
    id: leaving
    visible: map.switching
    interactive: false
    tiles: map.leavingWindows
    readonly property real a: map.leavingAngle * Math.PI / 180
    scale: 1 - (1 - map.dotScale) * map.t
    x: map.inset + map.bandR * Math.sin(a) * map.t
    y: map.inset - map.bandR * Math.cos(a) * map.t
    // Stays solid most of the way, then melts into the arc it lands in.
    opacity: 1 - map.t * map.t * map.t
  }

  TerrainLayer {
    id: arriving
    // Frozen during a drag: a refresh would rebuild the tile being dragged.
    tiles: map.dragAddress !== "" ? map.dragTiles : (map.terrain ? map.terrain.windows : [])
    readonly property real a: map.arrivingAngle * Math.PI / 180
    readonly property real k: 1 - map.t
    scale: 1 - (1 - map.dotScale) * k
    x: map.inset + map.bandR * Math.sin(a) * k
    y: map.inset - map.bandR * Math.cos(a) * k
    opacity: map.switching ? 0.25 + 0.75 * map.t : 1
  }

  // Held Super: the current workspace's number over the disc.
  property bool numbersShown: false
  Rectangle {
    visible: map.numbersShown && map.shownId !== -1
    anchors.centerIn: parent
    width: Math.max(bigNumber.implicitWidth, bigNumber.implicitHeight) + 18 * map.uiScale
    height: width
    radius: width / 2
    color: Qt.alpha(Color.background, 0.8)
    border.width: 2 * map.uiScale
    border.color: Color.accent
    z: 7

    Text {
      id: bigNumber
      anchors.centerIn: parent
      text: map.shownId < 0 ? "0" : String(map.shownId)
      color: Color.foreground
      font.family: Style.fontFamily
      font.pixelSize: Math.round(30 * map.uiScale)
      font.bold: true
    }
  }

  // The dragged window's icon, under the pointer.
  Image {
    visible: map.dragAddress !== "" && status === Image.Ready
    width: 26 * map.uiScale; height: width
    x: map.dragPoint.x - width / 2
    y: map.dragPoint.y - height / 2
    z: 10
    source: map.dragIcon
    sourceSize.width: 64; sourceSize.height: 64
    smooth: true
    mipmap: true
    opacity: 0.9
  }
}
