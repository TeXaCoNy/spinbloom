import QtQuick
import QtQuick.Effects

// One icon from views2/icons (white SVG line icons, filled transport), tinted
// to `color`. Replaces the Nerd Font glyphs in the new design so every icon
// shares one rounded, even-weight look.
Item {
  id: g
  property string name: ""
  property color color: "white"
  property real size: 20
  width: size
  height: size
  visible: name !== ""

  Image {
    id: img
    anchors.fill: parent
    source: g.name !== "" ? Qt.resolvedUrl("icons/" + g.name + ".svg") : ""
    sourceSize: Qt.size(Math.ceil(g.size * 2), Math.ceil(g.size * 2))
    smooth: true
    mipmap: true
    visible: false
  }
  MultiEffect {
    anchors.fill: img
    source: img
    colorization: 1
    colorizationColor: Qt.rgba(g.color.r, g.color.g, g.color.b, 1)
    opacity: g.color.a
  }
}
