import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons

// A card that opens next to an item of the minimap, towards the screen's
// interior (away from the corner the minimap sits in). Clicking anywhere
// outside the card and the minimap closes it.
PopupWindow {
  id: pop

  required property Item target    // the card opens beside this item
  property bool cornerRight: true
  property bool cornerBottom: true
  property bool open: false
  property int gap: 8
  property int padding: 12
  default property alias content: body.data

  // Above or below the target, on the interior side ("below"), or beside it.
  property bool beside: false

  function toggle() { open = !open }
  function reanchor() { if (visible) anchor.updateAnchor() }

  visible: open
  color: "transparent"
  implicitWidth: body.implicitWidth + 2 * padding + 2
  implicitHeight: body.implicitHeight + 2 * padding + 2

  onImplicitWidthChanged: reanchor()
  onImplicitHeightChanged: reanchor()
  onCornerRightChanged: reanchor()
  onCornerBottomChanged: reanchor()

  HyprlandFocusGrab {
    active: pop.open
    windows: pop.target && pop.target.QsWindow.window ? [pop, pop.target.QsWindow.window] : [pop]
    onCleared: pop.open = false
  }

  anchor {
    window: pop.target ? pop.target.QsWindow.window : null
    adjustment: PopupAdjustment.Slide
    edges: Edges.Top | Edges.Left
    gravity: Edges.Bottom | Edges.Right
    rect.width: 1
    rect.height: 1

    onAnchoring: {
      var t = pop.target
      var w = t ? t.QsWindow.window : null
      if (!w) return
      var pw = pop.implicitWidth, ph = pop.implicitHeight
      var x, y
      if (pop.beside) {
        // Level with the target's far edge, on its interior side.
        x = pop.cornerRight ? -pw - pop.gap : t.width + pop.gap
        y = pop.cornerBottom ? t.height - ph : 0
      } else {
        // Aligned on the target's interior edge, above or below it.
        x = pop.cornerRight ? t.width - pw : 0
        y = pop.cornerBottom ? -ph - pop.gap : t.height + pop.gap
      }
      var p = w.contentItem.mapFromItem(t, x, y)
      pop.anchor.rect.x = Math.round(p.x)
      pop.anchor.rect.y = Math.round(p.y)
    }
  }

  Rectangle {
    anchors.fill: parent
    color: Color.popups.background
    border.width: 1
    border.color: Color.popups.border
    radius: Style.cornerRadius

    Item {
      id: body
      x: pop.padding + 1
      y: pop.padding + 1
      implicitWidth: childrenRect.width
      implicitHeight: childrenRect.height
      width: implicitWidth
      height: implicitHeight
    }
  }
}
