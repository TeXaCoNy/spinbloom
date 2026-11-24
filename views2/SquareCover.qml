import QtQuick
import QtQuick.Effects
import "../theme2" as SpinTheme

// Spinbloom design 2 list artwork: a rounded square (songs, albums, playlists),
// or a circle for artists, as Apple Music draws them.
Item {
  id: root
  property url source: ""
  property string glyph: ""
  property bool circle: false
  property bool dim: false
  readonly property real corner: circle ? width / 2 : Math.max(4, width * 0.18)

  implicitWidth: 40
  implicitHeight: 40

  Rectangle {
    id: mask
    width: root.width; height: root.height
    radius: root.corner
    visible: false; layer.enabled: true; color: "white"
  }

  Rectangle {
    anchors.fill: parent
    radius: root.corner
    color: SpinTheme.Palette.bubble
    Text {
      anchors.centerIn: parent
      visible: img.status !== Image.Ready
      text: root.glyph
      textFormat: Text.PlainText
      color: SpinTheme.Palette.tertiary
      font.family: "JetBrainsMono Nerd Font"
      font.pixelSize: Math.max(8, Math.round(root.width * 0.45))
    }
  }

  Image {
    id: img
    anchors.fill: parent
    source: root.source
    sourceSize: Qt.size(Math.ceil(root.width * 2), Math.ceil(root.height * 2))
    asynchronous: true
    fillMode: Image.PreserveAspectCrop
    opacity: root.dim ? 0.55 : 1
    layer.enabled: true
    layer.effect: MultiEffect { maskEnabled: true; maskSource: mask }
  }
}
