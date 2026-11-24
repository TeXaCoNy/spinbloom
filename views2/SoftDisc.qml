import QtQuick
import QtQuick.Shapes

// A mask for the "pour" reveals: solid white at (centerX, centerY), fading to
// clear by `reach`. Used as a MultiEffect maskSource; lowering the effect's
// threshold then spreads a soft-edged circle outward from the centre.
// (Drawn as a Shape, which still renders into its layer while hidden.)
Shape {
  id: root
  property real centerX: width / 2
  property real centerY: height / 2
  property real reach: Math.max(Math.hypot(centerX, centerY), Math.hypot(width - centerX, centerY),
                                Math.hypot(centerX, height - centerY), Math.hypot(width - centerX, height - centerY)) * 1.2
  preferredRendererType: Shape.CurveRenderer
  ShapePath {
    strokeWidth: -1
    strokeColor: "transparent"
    fillGradient: RadialGradient {
      centerX: root.centerX; centerY: root.centerY; centerRadius: root.reach
      focalX: root.centerX; focalY: root.centerY; focalRadius: 0
      GradientStop { position: 0; color: "white" }
      GradientStop { position: 1; color: "transparent" }
    }
    startX: 0; startY: 0
    PathLine { x: root.width; y: 0 }
    PathLine { x: root.width; y: root.height }
    PathLine { x: 0; y: root.height }
    PathLine { x: 0; y: 0 }
  }
}
