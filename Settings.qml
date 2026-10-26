import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The minimap's settings, opened from the clock. Every change is written to
// minimap.json straight away; sliders write when they are released.
Column {
  id: settings

  required property var cfg
  signal save(var patch)

  readonly property int labelWidth: 108
  readonly property int controlWidth: 210
  spacing: 10

  component Label: Text {
    width: settings.labelWidth
    color: Qt.alpha(Color.popups.text, 0.7)
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    verticalAlignment: Text.AlignVCenter
  }

  component Value: Text {
    color: Color.popups.text
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    verticalAlignment: Text.AlignVCenter
  }

  // A slider with its value next to it, shown live while dragging.
  component Setting: Row {
    id: setting
    property string label: ""
    property real value: 0
    property real minimum: 0
    property real maximum: 1
    property var format: function(v) { return String(v) }
    signal released(real value)
    spacing: 8
    height: 24

    Label { text: setting.label; height: parent.height }
    PanelSlider {
      id: slider
      width: settings.controlWidth - 52
      anchors.verticalCenter: parent.verticalCenter
      value: setting.value
      minimum: setting.minimum
      maximum: setting.maximum
      integer: true
      trackColor: Qt.alpha(Color.popups.text, 0.15)
      fillColor: Color.accent
      knobColor: Color.popups.text
      onReleased: function(v) { setting.released(v) }
    }
    Value { text: setting.format(slider.liveValue); height: parent.height; width: 44; horizontalAlignment: Text.AlignRight }
  }

  component Choice: Row {
    id: choice
    property string label: ""
    property var options: []
    property string value: ""
    signal changed(string value)
    spacing: 8

    Label { text: choice.label; height: group.height }
    ButtonGroup {
      id: group
      options: choice.options
      value: choice.value
      foreground: Color.popups.text
      background: Color.popups.background
      fontSize: Style.font.body
      onChanged: function(v) { choice.changed(v) }
    }
  }

  Text {
    text: "Minimap"
    color: Color.popups.text
    font.family: Style.font.family
    font.pixelSize: Style.font.subtitle
    font.bold: true
  }

  Choice {
    label: "Coin"
    options: [
      { value: "top-left", label: "↖", tooltip: "En haut à gauche" },
      { value: "top-right", label: "↗", tooltip: "En haut à droite" },
      { value: "bottom-left", label: "↙", tooltip: "En bas à gauche" },
      { value: "bottom-right", label: "↘", tooltip: "En bas à droite" }
    ]
    value: settings.cfg.corner
    onChanged: function(v) { settings.save({ corner: v }) }
  }

  Choice {
    visible: Quickshell.screens.length > 1
    label: "Écran"
    options: {
      var out = [{ value: "", label: "Actif" }]
      for (var i = 0; i < Quickshell.screens.length; i++) out.push(Quickshell.screens[i].name)
      return out
    }
    value: settings.cfg.monitor
    onChanged: function(v) { settings.save({ monitor: v }) }
  }

  Setting {
    label: "Taille"
    value: settings.cfg.size
    minimum: 120
    maximum: 480
    format: function(v) { return Math.round(v / 10) * 10 }
    onReleased: function(v) { settings.save({ size: Math.round(v / 10) * 10 }) }
  }

  Setting {
    label: "Opacité"
    value: Math.round(settings.cfg.opacity * 100)
    minimum: 20
    maximum: 100
    format: function(v) { return Math.round(v / 5) * 5 + " %" }
    onReleased: function(v) { settings.save({ opacity: Math.round(v / 5) * 5 / 100 }) }
  }

  Row {
    spacing: 8
    Label { text: "Heure"; height: clockToggle.height }
    ToggleSwitch {
      id: clockToggle
      checked: settings.cfg.clock
      onToggled: settings.save({ clock: !settings.cfg.clock })
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "sinon au survol"
      color: Qt.alpha(Color.popups.text, 0.5)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }

  Row {
    spacing: 8
    Label { text: "Sur la barre"; height: overBar.height }
    ToggleSwitch {
      id: overBar
      checked: settings.cfg.overBar
      onToggled: settings.save({ overBar: !settings.cfg.overBar })
    }
  }

  Row {
    spacing: 8
    Label { text: "Compacter"; height: compact.height }
    ToggleSwitch {
      id: compact
      checked: settings.cfg.autoCompact
      onToggled: settings.save({ autoCompact: !settings.cfg.autoCompact })
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "bureaux 1..n, sans trou"
      color: Qt.alpha(Color.popups.text, 0.5)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }

  Row {
    spacing: 8
    Label { text: "Découpe"; height: cutout.height }
    ToggleSwitch {
      id: cutout
      checked: settings.cfg.cutout
      onToggled: settings.save({ cutout: !settings.cfg.cutout })
    }
  }

  Text {
    topPadding: 4
    text: "Météo"
    color: Qt.alpha(Color.popups.text, 0.5)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.bold: true
  }

  Setting {
    label: "Zoom"
    value: settings.cfg.zoom
    minimum: Model.MIN_ZOOM
    maximum: Model.MAX_ZOOM
    onReleased: function(v) { settings.save({ zoom: Math.round(v) }) }
  }

  Setting {
    label: "Alerte pluie"
    value: settings.cfg.rainAlert
    minimum: 0
    maximum: 30
    format: function(v) { return Math.round(v) === 0 ? "non" : Math.round(v) + " min" }
    onReleased: function(v) { settings.save({ rainAlert: Math.round(v) }) }
  }

  Choice {
    label: "Fond"
    options: [
      { value: "auto", label: "Auto" },
      { value: "dark", label: "Sombre" },
      { value: "light", label: "Clair" }
    ]
    value: settings.cfg.basemap
    onChanged: function(v) { settings.save({ basemap: v }) }
  }
}
