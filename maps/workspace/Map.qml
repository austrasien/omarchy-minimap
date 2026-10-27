import QtQuick

// Built-in map: the focused workspace stretched onto the disc, the other
// occupied ones as arcs around it, with the coding agents' state.
Item {
  id: view
  required property var minimap

  WorkspaceMap {
    anchors.fill: parent
    terrain: view.minimap.terrain
    numbersShown: view.minimap.numbersShown
    arcs: view.minimap.workspaceArcs
    bandWidth: view.minimap.bandWidth
    bandGap: view.minimap.bandGap
    uiScale: view.minimap.uiScale
    markers: view.minimap.markers
    lastFocus: view.minimap.lastFocus
    deskVisits: view.minimap.deskVisits
    fogSince: view.minimap.startedAt
    nowSec: view.minimap.nowSec
    onFocusWindow: function(address) { view.minimap.focusWindow(address) }
    onFocusWorkspace: function(id) { view.minimap.focusWorkspace(id) }
    onHoverWorkspace: function(id) { view.minimap.hoverDesk(id) }
    onMoveWindow: function(address, workspace) { view.minimap.moveWindow(address, workspace) }
  }
}
