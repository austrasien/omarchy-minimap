import QtQuick
import qs.Commons

// A map's line of text round the rim (see `ticker` in Minimap.qml), in the
// room the day/night dial and the rim bands leave while it runs. Letter by
// letter, feet outwards, so it reads upright at 6 o'clock, running right to
// left there like a news ticker: its first letter leads. Each letter fades
// in at noon and out back at noon; closed early (clicked), the letters fade
// where they stand while the radar draws the dial and the bands back.
Item {
  id: ticker

  required property var minimap
  // The last map to run text: kept while its letters fade out.
  property Item source: null
  readonly property var chars: source && source.tickerChars ? source.tickerChars : []
  readonly property real offset: source ? source.tickerOffset : 0
  // 0 → 1 while the map blows its text away (a dismissed notification):
  // each letter flies outwards, spinning, from the head of the text on.
  readonly property real burst: source && source.tickerBurst ? source.tickerBurst : 0
  readonly property real r: Math.min(width, height) / 2

  // In once the radar has cleared the rim, out as it starts drawing it back.
  opacity: minimap.tickerReady ? 1 : 0
  visible: opacity > 0
  Behavior on opacity { NumberAnimation { duration: Style.reduceMotion ? 0 : 250 } }

  Connections {
    target: ticker.minimap
    function onTickerChanged() { if (ticker.minimap.ticker) ticker.source = ticker.minimap.ticker }
  }

  Repeater {
    model: ticker.chars.length
    delegate: Text {
      required property int index
      readonly property real a: ticker.offset - index * ticker.minimap.tickerStep
      readonly property real rad: a * Math.PI / 180
      readonly property real t: ticker.burst <= 0 ? 0
        : Math.max(0, Math.min(1, ticker.burst * 1.8 - 0.8 * index / Math.max(1, ticker.chars.length)))
      readonly property real fly: ticker.minimap.tickerRadius + t * t * 34 * ticker.minimap.uiScale
      visible: a > 0 && a < 360 && t < 1
      opacity: Math.min(1, a / 30, (360 - a) / 30) * (1 - t)
      scale: 1 + 0.8 * t
      x: ticker.r + fly * Math.sin(rad) - width / 2
      y: ticker.r - fly * Math.cos(rad) - height / 2
      rotation: a + 180 + t * (index % 2 ? 140 : -140)
      text: ticker.chars[index] || ""
      color: Color.foreground
      font: ticker.minimap.tickerFont
    }
  }
}
