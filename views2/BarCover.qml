import QtQuick

// The bar's round cover inside its progress ring. The gap between ring and
// cover is a whole pixel count, the same on every side: an odd total gap
// put the cover half a pixel off centre, and Qt rounds a centred item to a
// whole pixel, so the cover sat up and to the left in its ring.
Item {
  id: root

  property int barSize: 26
  property bool hasTrack: false
  property real progress: 0
  property color ringColor: "white"
  property color trackColor: "transparent"
  property url source: ""
  property color foreground: "white"
  property color fill: "transparent"
  property string fontFamily: ""
  property bool dim: false
  // Calm motion: a new cover just fades in (no spin).
  property bool calm: false

  readonly property int gap: Math.max(2, Math.round(barSize * 0.1))

  width: Math.round(barSize * 0.78)
  height: width

  // A new song: the ring sweeps back to its start instead of jumping.
  property real shownProgress: 0
  property real lastProgress: 0
  onProgressChanged: {
    if (root.progress < root.lastProgress - 0.15 && !root.calm) {
      sweep.from = root.shownProgress; sweep.to = root.progress; sweep.restart()
    } else if (!sweep.running) {
      root.shownProgress = root.progress
    } else {
      sweep.to = root.progress
    }
    root.lastProgress = root.progress
  }
  NumberAnimation { id: sweep; target: root; property: "shownProgress"; duration: 450; easing.type: Easing.OutCubic }

  ProgressRing {
    anchors.fill: parent
    visible: root.hasTrack
    progress: root.shownProgress
    thickness: Math.max(1.5, Math.round(root.barSize * 0.07))
    color: root.ringColor
    trackColor: root.trackColor
  }

  // The cover. A new song's picture spins in over the old one, growing
  // from the middle with a quarter turn (the player's disc swirl, in
  // miniature); the old one stays underneath until it is covered.
  property url shownSource: ""
  property url oldSource: ""
  property real spin: 1                       // 0 → 1 while a new cover comes in
  onSourceChanged: {
    var prev = root.shownSource
    root.shownSource = root.source
    if (String(prev) === "" || String(root.source) === "" || String(prev) === String(root.source)) {
      spinIn.stop(); root.spin = 1; root.oldSource = ""; return
    }
    root.oldSource = prev
    root.spin = 0
    spinIn.stop()
    // Spin once the new picture is in (it downloads), at most 1.5 s later.
    if (newCover.ready) root.startSpin(); else spinWait.restart()
  }
  function startSpin() {
    spinWait.stop()
    if (spinIn.running || root.spin >= 1) return
    spinIn.duration = root.calm ? 350 : 600
    spinIn.restart()
  }
  Timer { id: spinWait; interval: 1500; onTriggered: root.startSpin() }
  Component.onCompleted: root.shownSource = root.source
  NumberAnimation {
    id: spinIn
    target: root; property: "spin"; from: 0; to: 1
    easing.type: Easing.OutCubic
    onFinished: root.oldSource = ""
  }

  RoundCover {
    id: oldCover
    visible: String(root.oldSource) !== "" && root.spin < 1
    x: root.hasTrack ? root.gap : 0
    y: x
    width: root.width - 2 * x
    height: width
    source: root.oldSource
    foreground: root.foreground
    fill: root.fill
    fontFamily: root.fontFamily
    dim: root.dim
  }
  RoundCover {
    id: newCover
    x: root.hasTrack ? root.gap : 0
    y: x
    width: root.width - 2 * x
    height: width
    source: root.shownSource
    onReadyChanged: if (ready && spinWait.running) root.startSpin()
    foreground: root.foreground
    fill: root.fill
    fontFamily: root.fontFamily
    dim: root.dim
    opacity: root.spin
    scale: root.calm ? 1 : 0.35 + 0.65 * root.spin
    rotation: root.calm ? 0 : -90 * (1 - root.spin)
  }
}
