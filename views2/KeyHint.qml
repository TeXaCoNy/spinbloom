import QtQuick
import qs.Commons
import "../theme2" as SpinTheme

// A key and what it does, for the hint line.
Row {
  id: hint

  property string keys: ""
  property string label: ""
  property QtObject bar: null
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string family: "Inter"

  spacing: Style.space(10)

  Rectangle {
    anchors.verticalCenter: parent.verticalCenter
    width: Math.max(height, keyText.implicitWidth + Style.space(14))
    height: keyText.implicitHeight + Style.space(8)
    radius: Style.space(6)
    color: SpinTheme.Palette.bubble
    Text {
      id: keyText
      anchors.centerIn: parent
      text: hint.keys
      textFormat: Text.PlainText
      color: SpinTheme.Palette.text
      font.family: hint.family
      font.pixelSize: Style.font.caption
      font.weight: Font.DemiBold
    }
  }

  Text {
    anchors.verticalCenter: parent.verticalCenter
    text: hint.label
    textFormat: Text.PlainText
    color: SpinTheme.Palette.secondary
    font.family: hint.family
    font.pixelSize: Style.font.body
  }
}
