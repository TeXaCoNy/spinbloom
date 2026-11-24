import QtQuick
import qs.Commons

// Spinbloom: the plain "theme" background, used when "Colour from album
// artwork" is off. A soft glow of the desktop theme's accent colour (top
// left) and a fainter one of its text colour (bottom right) over the frosted
// glass, so it is never flat. It follows the Omarchy theme live.
Item {
  id: glow
  // The theme's main colour (its background), not the accent.
  property color tint: Color.popups.background
  property color second: Color.popups.text
  property real strength: 0.32
  onTintChanged: paint.requestPaint()
  onSecondChanged: paint.requestPaint()
  Canvas {
    id: paint
    anchors.fill: parent
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
      const c = getContext("2d")
      c.reset()
      const w = width, h = height, r = Math.max(w, h)
      const spot = function (x, y, rad, col, a) {
        const g = c.createRadialGradient(x, y, 0, x, y, rad)
        g.addColorStop(0, Qt.rgba(col.r, col.g, col.b, a))
        g.addColorStop(1, Qt.rgba(col.r, col.g, col.b, 0))
        c.fillStyle = g
        c.fillRect(0, 0, w, h)
      }
      // Glass reflection: a soft white sheen falling diagonally from the
      // top-left corner, and a faint highlight along the top edge.
      const sheen = c.createLinearGradient(0, 0, w * 0.55, h * 0.75)
      sheen.addColorStop(0, "rgba(255,255,255,0.13)")
      sheen.addColorStop(0.45, "rgba(255,255,255,0.04)")
      sheen.addColorStop(1, "rgba(255,255,255,0)")
      c.fillStyle = sheen
      c.fillRect(0, 0, w, h)
      const edge = c.createLinearGradient(0, 0, 0, h * 0.06)
      edge.addColorStop(0, "rgba(255,255,255,0.10)")
      edge.addColorStop(1, "rgba(255,255,255,0)")
      c.fillStyle = edge
      c.fillRect(0, 0, w, h * 0.06)
      spot(w * 0.18, h * 0.12, r * 0.75, glow.tint, glow.strength)
      spot(w * 0.92, h * 0.95, r * 0.65, glow.second, glow.strength * 0.35)
    }
  }
}
