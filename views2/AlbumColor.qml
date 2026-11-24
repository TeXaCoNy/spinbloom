import QtQuick

// Spinbloom design 2: the album artwork's main colour, sampled once per image.
//
// Averaging every pixel turns a multi-coloured cover into mud (red roses +
// brown stems + green leaves = tan). Instead the colourful pixels are sorted
// into twelve hue families and the family that dominates the cover wins;
// `color` is that family's own average. A cover with almost no colour (black
// and white, greys) reports no colour, and callers fall back to the theme
// accent.
//
// `vivid` lifts that hue so it reads as an accent on a dark surface
// (progress bar, liked heart, the bar's progress ring); `brightness` (0..1)
// is how light the cover is overall, so a pale cover can get a darker
// backdrop behind white text.
Item {
  id: root
  property string source: ""
  property color color: "transparent"
  property real brightness: 0
  readonly property bool valid: color.a > 0
  // Rich, not pastel: keep the hue saturated and lighten only as far as this
  // hue needs to read on a dark surface (reds stay red; dark blues and
  // purples, which carry little brightness, get lifted further).
  readonly property color vivid: valid ? liftToRead(color) : "transparent"

  function luminance(c) { return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }
  function liftToRead(c) {
    const hue = c.hslHue < 0 ? 0 : c.hslHue
    const sat = Math.max(0.62, Math.min(0.9, c.hslSaturation * 1.3))
    let light = Math.max(0.48, Math.min(0.60, c.hslLightness))
    let out = Qt.hsla(hue, sat, light, 1)
    while (luminance(out) < 0.30 && light < 0.78) {
      light += 0.02
      out = Qt.hsla(hue, sat, light, 1)
    }
    return out
  }

  // Canvas only paints while it is part of the visible scene, so the sampler
  // stays "visible" but clipped to a single, almost transparent pixel.
  width: 1; height: 1
  clip: true
  opacity: 0.01

  Canvas {
    id: sampler
    width: 24; height: 24
    property string pending: ""
    function sample(url) {
      if (!url) { root.color = "transparent"; root.brightness = 0; return }
      pending = url
      if (isImageLoaded(url)) requestPaint()
      else loadImage(url)
    }
    onImageLoaded: requestPaint()
    onAvailableChanged: if (available && pending) requestPaint()
    onPaint: {
      const url = pending
      if (!url || !isImageLoaded(url)) return
      const ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      ctx.drawImage(url, 0, 0, width, height)
      const px = ctx.getImageData(0, 0, width, height).data
      ctx.clearRect(0, 0, width, height)
      unloadImage(url)
      pending = ""

      // Two passes in one sweep: strong colours, and (for muted covers such
      // as sepia photos) gentle tints.
      const buckets = [], soft = []
      for (let k = 0; k < 12; k++) { buckets.push({ w: 0, r: 0, g: 0, b: 0 }); soft.push({ w: 0, r: 0, g: 0, b: 0 }) }
      let lumSum = 0, count = 0, colourful = 0, tinted = 0
      for (let i = 0; i < px.length; i += 4) {
        if (px[i + 3] < 128) continue
        const r = px[i] / 255, g = px[i + 1] / 255, b = px[i + 2] / 255
        const max = Math.max(r, g, b), min = Math.min(r, g, b)
        const v = max, s = max > 0 ? (max - min) / max : 0
        lumSum += 0.2126 * r + 0.7152 * g + 0.0722 * b
        count++
        // Ignore greys, near-black and blown-out pixels.
        if (s < 0.10 || v < 0.16 || v > 0.98) continue
        let h
        const d = max - min
        if (max === r) h = ((g - b) / d) % 6
        else if (max === g) h = (b - r) / d + 2
        else h = (r - g) / d + 4
        h = (h * 60 + 360) % 360
        const w = s * s * (0.4 + v)
        const tint = soft[Math.floor(h / 30) % 12]
        tint.w += w; tint.r += r * w; tint.g += g * w; tint.b += b * w
        tinted++
        if (s < 0.22) continue
        const bucket = buckets[Math.floor(h / 30) % 12]
        bucket.w += w; bucket.r += r * w; bucket.g += g * w; bucket.b += b * w
        colourful++
      }
      root.brightness = count > 0 ? lumSum / count : 0

      // Strong colours win when there are enough of them; otherwise the
      // cover's gentle tint; a truly grey cover reports no colour at all.
      const pool = colourful >= count * 0.04 ? buckets : tinted >= count * 0.08 ? soft : null
      if (!pool) { root.color = "transparent"; return }
      let best = null
      for (let k = 0; k < 12; k++) if (!best || pool[k].w > best.w) best = pool[k]
      if (!best || best.w <= 0) { root.color = "transparent"; return }
      root.color = Qt.rgba(best.r / best.w, best.g / best.w, best.b / best.w, 1)
    }
  }

  onSourceChanged: sampler.sample(source)
  Component.onCompleted: sampler.sample(source)
}
