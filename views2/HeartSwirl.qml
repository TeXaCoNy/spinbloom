import QtQuick
import QtQuick.Shapes

// The like swirl: the same motion as a disc landing in the player. Colour
// spins in from the middle and fills the heart, then blooms outward past it
// as a turning ring of sparks that fades away. Placed centred on the heart
// button; play() runs it (it never needs the song to be playing).
Item {
  id: root

  property real size: 20          // the heart glyph's size
  property color tint: "white"
  readonly property bool running: anim.running || drainAnim.running

  width: size * 6; height: width
  visible: anim.running || drainAnim.running
  // Clicks go to the heart underneath.
  enabled: false

  property real t: 0              // 0 → 1 over the whole swirl
  readonly property real fillT: Math.min(1, t / 0.35)
  readonly property real burstT: Math.max(0, Math.min(1, (t - 0.12) / 0.78))
  // Fades only in the last part, so the swirl is seen at full strength.
  readonly property real fade: t < 0.6 ? 1 : Math.max(0, 1 - (t - 0.6) / 0.4)

  function play() { drainAnim.stop(); anim.restart() }
  // Unlike: the quiet way back. The colour drains out of the heart as it
  // turns a quarter the other way and shrinks; no ring, no sparks.
  function drain() { anim.stop(); t = 0; drainAnim.restart() }
  property real u: 0              // 0 → 1 over the drain

  // The colour bloom: a soft disc of the album colour that spins out from
  // the heart (as the cover's colour pours out after a disc lands).
  Shape {
    id: bloom
    anchors.centerIn: parent
    width: root.size * (0.8 + 4.2 * root.burstT); height: width
    rotation: 140 * root.burstT
    opacity: 0.75 * root.fade * Math.min(1, root.t * 8)
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      strokeWidth: -1
      strokeColor: "transparent"
      fillGradient: RadialGradient {
        centerX: bloom.width / 2; centerY: bloom.height / 2; centerRadius: bloom.width / 2
        focalX: bloom.width / 2; focalY: bloom.height / 2; focalRadius: 0
        GradientStop { position: 0; color: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, 0.9) }
        GradientStop { position: 0.55; color: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, 0.35) }
        GradientStop { position: 1; color: "transparent" }
      }
      PathAngleArc {
        centerX: bloom.width / 2; centerY: bloom.height / 2
        radiusX: bloom.width / 2; radiusY: bloom.height / 2
        startAngle: 0; sweepAngle: 360
      }
    }
  }
  // Ring carried past the heart.
  Rectangle {
    anchors.centerIn: parent
    width: root.size * (1.0 + 3.6 * root.burstT); height: width
    radius: width / 2
    color: "transparent"
    border.width: Math.max(2, root.size * 0.16 * (1 - root.burstT))
    border.color: root.tint
    opacity: root.burstT > 0 ? root.fade : 0
  }
  // Two arms of sparks turning clockwise as they fly out (the swirl).
  Repeater {
    model: 16
    Rectangle {
      required property int index
      readonly property real lag: (index % 2) * 0.12
      readonly property real p: Math.max(0, Math.min(1, (root.burstT - lag) / (1 - lag)))
      readonly property real ang: (index * 22.5 + 170 * p) * Math.PI / 180
      readonly property real r: root.size * (0.7 + 2.5 * p)
      readonly property real s: root.size * (index % 2 ? 0.22 : 0.32) * (1 - 0.45 * p)
      width: s; height: s; radius: s / 2
      x: root.width / 2 + Math.sin(ang) * r - s / 2
      y: root.height / 2 - Math.cos(ang) * r - s / 2
      color: index % 4 === 0 ? "white" : root.tint
      opacity: p > 0 ? root.fade : 0
    }
  }
  // The filled heart spinning in from the middle, swelling, then settling.
  Glyph {
    anchors.centerIn: parent
    visible: anim.running
    name: "heart-fill"
    color: root.tint
    size: root.size
    rotation: -180 * (1 - root.fillT) * (1 - root.fillT)
    scale: root.fillT < 1 ? 0.2 + 1.5 * root.fillT : 1.7 - 0.7 * Math.min(1, (root.t - 0.35) / 0.3)
    opacity: root.fade
  }

  NumberAnimation {
    id: anim
    target: root; property: "t"; from: 0; to: 1
    duration: 1600; easing.type: Easing.Linear
  }

  // ---- unlike: the like swirl undone --------------------------------------
  // First the swirl is pulled back in (a ring and sparks spiralling inward,
  // counter-clockwise, onto the heart), then the colour drains out of the
  // heart from the top down, leaving the outline.
  readonly property real inT: Math.min(1, u / 0.4)
  readonly property real dT: Math.max(0, Math.min(1, (u - 0.32) / 0.55))
  Rectangle {
    anchors.centerIn: parent
    visible: drainAnim.running
    width: root.size * (2.6 - 1.5 * root.inT * root.inT); height: width
    radius: width / 2
    color: "transparent"
    border.width: Math.max(1.5, root.size * 0.1)
    border.color: root.tint
    opacity: root.u < 0.4 ? 0.7 * root.inT : Math.max(0, 0.7 * (1 - (root.u - 0.4) / 0.12))
  }
  Repeater {
    model: 8
    Rectangle {
      required property int index
      readonly property real ang: (index * 45 - 130 * root.inT) * Math.PI / 180
      readonly property real r: root.size * (2.3 - 1.7 * root.inT * root.inT)
      readonly property real s: root.size * 0.18
      visible: drainAnim.running
      width: s; height: s; radius: s / 2
      x: root.width / 2 + Math.sin(ang) * r - s / 2
      y: root.height / 2 - Math.cos(ang) * r - s / 2
      color: index % 2 ? "white" : root.tint
      opacity: root.u < 0.4 ? 0.85 * Math.min(1, root.inT * 3) : Math.max(0, 0.85 * (1 - (root.u - 0.4) / 0.1))
    }
  }
  // The fill, emptying from the top down.
  Item {
    visible: drainAnim.running
    anchors.centerIn: parent
    width: root.size; height: root.size
    scale: 1 + 0.12 * Math.sin(root.inT * Math.PI) - 0.1 * root.dT + 0.1 * Math.max(0, (root.u - 0.87) / 0.13)
    Item {
      anchors.bottom: parent.bottom
      width: parent.width
      height: parent.height * (1 - root.dT)
      clip: true
      Glyph {
        anchors.bottom: parent.bottom
        name: "heart-fill"
        color: root.tint
        size: root.size
      }
    }
  }
  NumberAnimation {
    id: drainAnim
    target: root; property: "u"; from: 0; to: 1
    duration: 1000; easing.type: Easing.Linear
  }
}
