import QtQuick

// A thin white arc that turns while a chosen song loads.
Item {
  id: ring
  property real lineWidth: 2.5
  width: 26; height: width
  Canvas {
    anchors.fill: parent
    onPaint: {
      const c = getContext("2d")
      c.reset()
      c.lineWidth = ring.lineWidth
      c.lineCap = "round"
      const r = width / 2 - ring.lineWidth
      c.strokeStyle = "rgba(255,255,255,0.25)"
      c.beginPath(); c.arc(width / 2, height / 2, r, 0, Math.PI * 2); c.stroke()
      c.strokeStyle = "white"
      c.beginPath(); c.arc(width / 2, height / 2, r, -Math.PI / 2, Math.PI * 0.35); c.stroke()
    }
  }
  RotationAnimator on rotation { from: 0; to: 360; duration: 850; loops: Animation.Infinite; running: ring.visible }
}
