import QtQuick
import "../theme2" as SpinTheme
import qs.Ui
import qs.Commons

// Spinbloom is off (the engine closed on purpose, or after it kept crashing):
// nothing below would work, so under the header ("Spinbloom is off") the panel
// shows only the way back on.
Column {
  id: card

  property var svc: null
  property QtObject bar: null
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string family: "Inter"

  spacing: Style.space(10)

  Button {
    objectName: "offTurnOn"
    anchors.horizontalCenter: parent.horizontalCenter
    // At least 32 px tall, like every other control (an easy target).
    height: Math.max(implicitHeight, Style.space(34))
    text: "Turn on"
    fontFamily: card.family
    foreground: SpinTheme.Palette.accent
    bordered: true
    onClicked: if (card.svc) card.svc.startEngine()
  }

  Text {
    width: parent.width
    text: "or press Enter"
    textFormat: Text.PlainText
    horizontalAlignment: Text.AlignHCenter
    color: Util.alpha(card.fg, 0.5)
    font.family: card.family
    font.pixelSize: Style.font.caption
  }
}
