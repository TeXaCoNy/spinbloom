import QtQuick
import "../theme2" as SpinTheme
import qs.Ui
import qs.Commons
import QtQuick.Controls as Controls

// The kit's button with a hit box that does not depend on its glyph: at
// least `minSize` on each side (a square for an icon), and a small press
// that follows the pointer. Hover, pressed and keyboard-cursor fills come
// from the kit, so every theme still decides the colours.
Button {
  id: root
  focusable: true
  HoverHandler { id: musicHover }
  accent: SpinTheme.Palette.accent
  // Icon-only buttons get a round macOS-style hover disc (drawn below);
  // labelled buttons keep the kit's capsule fill.
  background: !iconOnly && musicHover.hovered ? SpinTheme.Palette.fillHover : "transparent"

  // New-design icon (views2/icons) in place of a font glyph: set iconName.
  property string iconName: ""
  iconText: ""
  Rectangle {
    z: -1
    visible: root.iconOnly
    anchors.centerIn: parent
    width: Math.min(root.width, root.height); height: width; radius: width / 2
    color: press.active ? SpinTheme.Palette.fillPressed : musicHover.hovered || root.hasCursor ? SpinTheme.Palette.fillHover : "transparent"
    Behavior on color { ColorAnimation { duration: Style.duration(110) } }
  }
  Glyph {
    anchors.centerIn: parent
    name: root.iconName
    color: root.foreground
    size: Math.round(root.iconSize * 1.1)
  }
  // The kit's square tooltip is switched off (fully transparent); the
  // rounded design-2 tooltip below shows the same text instead.
  tooltipBackground: "transparent"
  tooltipBorder: "transparent"
  tooltipForeground: "transparent"

  Controls.ToolTip {
    id: roundTip
    visible: root.tooltipText !== "" && musicHover.hovered
    delay: 500
    y: root.height + Style.space(6)
    x: (root.width - width) / 2
    padding: 0
    enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 140 } }
    exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 100 } }
    background: Rectangle {
      radius: Style.space(8)
      color: Util.alpha(SpinTheme.Palette.glass, 0.96)
      border.width: 1
      border.color: SpinTheme.Palette.edge
    }
    contentItem: Text {
      text: root.tooltipText
      textFormat: Text.PlainText
      color: SpinTheme.Palette.text
      font.family: "Inter"
      font.pixelSize: Style.font.caption
      leftPadding: Style.space(10); rightPadding: Style.space(10)
      topPadding: Style.space(5); bottomPadding: Style.space(5)
    }
  }

  Behavior on background { ColorAnimation { duration: Style.duration(110) } }

  // Smallest side of the box; the glyph sits in its middle.
  property real minSize: Style.space(32)
  // A square box for an icon-only button, grown to fit a label otherwise.
  readonly property bool iconOnly: text === ""

  width: iconOnly ? minSize : Math.max(minSize, implicitWidth)
  height: Math.max(minSize, implicitHeight)
  horizontalPadding: iconOnly ? 0 : Math.max(Style.spacing.controlPaddingX, Style.space(12))
  verticalPadding: 0

  // Pressed: shrink a little, straight away, and let go just as fast.
  // Only a pointer press moves it; a key never does.
  scale: press.active ? 0.94 : 1
  Behavior on scale { NumberAnimation { duration: Style.duration(110); easing.type: Easing.OutCubic } }

  // Above the kit's MouseArea: watches the press without taking it.
  Item {
    anchors.fill: parent
    PointHandler { id: press; acceptedButtons: Qt.LeftButton; enabled: root.enabled }
  }
}
