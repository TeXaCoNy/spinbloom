import QtQuick
import QtQuick.Effects
import "../theme2" as SpinTheme
import qs.Commons
import Quickshell
import Quickshell.Io
import "../lib/Model.js" as Model

// Lyrics for the song that plays. Timed lines follow the music; plain
// lyrics scroll by hand.
Item {
  id: view

  property var svc: null
  property QtObject bar: null
  property var panel: null
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string family: "Inter"

  // On screen: the panel is open on this view (see QueueView).
  property bool active: false
  property var lyrics: null
  property string forVideo: ""
  property bool busy: false
  property string error: ""
  readonly property bool timed: !!lyrics && lyrics.kind === "timed"
  readonly property int line: timed && svc ? Model.lyricIndex(lyrics.lines, svc.position * 1000 + 300) : -1
  readonly property var hints: [["j k", "scroll"], [", .", "seek"]]
  property int cursor: -1
  readonly property var current: null

  // Centred (the default) or left-aligned lines; the choice is kept on disk.
  property bool centered: true
  FileView {
    id: alignStore
    path: Quickshell.env("HOME") + "/.local/state/spinbloom/lyrics-align"
    printErrors: false
    onLoaded: view.centered = text().trim() !== "left"
  }
  function toggleAlign() {
    view.centered = !view.centered
    alignStore.setText(view.centered ? "center\n" : "left\n")
  }

  // Lines change every few seconds: ask the service for a finer clock
  // while timed lyrics are on screen.
  property bool usingFastClock: false
  readonly property bool wantsFastClock: active && timed && !!svc
  onWantsFastClockChanged: {
    if (!svc) return
    if (wantsFastClock && !usingFastClock) { svc.fastClockUsers += 1; usingFastClock = true }
    else if (!wantsFastClock && usingFastClock) { svc.fastClockUsers -= 1; usingFastClock = false }
  }
  Component.onDestruction: if (usingFastClock && svc) svc.fastClockUsers -= 1

  function shown() { load() }
  function move(dy) {
    if (timed) { handScroll = true; handTimer.restart() }
    if (timed) lines.contentY = Math.max(0, Math.min(lines.contentHeight - lines.height, lines.contentY + dy * 40))
    else plain.contentY = Math.max(0, Math.min(plain.contentHeight - plain.height, plain.contentY + dy * 40))
  }
  function activate() {}

  function load() {
    if (!svc || !svc.hasTrack) { view.lyrics = null; view.forVideo = ""; return }
    var vid = svc.videoId
    if (vid === view.forVideo && view.lyrics) return
    view.forVideo = vid
    view.busy = true
    view.error = ""
    view.lyrics = null
    svc.request("lyrics", { videoId: vid }, function (r) {
      if (vid !== view.forVideo) return
      view.busy = false
      if (r.ok) view.lyrics = r.data
      else view.error = Model.errorText(r.error)
    })
  }

  Connections {
    target: view.svc
    function onTrackChanged(v) { if (view.active) view.load() }
  }

  onLineChanged: follow()

  // Apple Music: the sung line glides to the upper third on a spring; while
  // you scroll by hand the lyrics stop following (and stop blurring) for a
  // few seconds, then pick the song back up.
  property bool handScroll: false
  Timer { id: handTimer; interval: 3000; onTriggered: { view.handScroll = false; view.follow() } }
  function follow() {
    if (!timed || line < 0 || handScroll) return
    const it = lines.itemAtIndex(line)
    if (!it) { lines.positionViewAtIndex(line, ListView.Beginning); return }
    const top = lines.originY
    const bottom = lines.originY + Math.max(0, lines.contentHeight - lines.height)
    scroller.to = Math.max(top, Math.min(it.y - lines.height * 0.26, bottom))
    scroller.restart()
  }
  SpringAnimation { id: scroller; target: lines; property: "contentY"; spring: 2.4; damping: 0.36; epsilon: 0.4 }

  // One clock for the instrumental-gap dots.
  property real pulse: 0
  NumberAnimation on pulse {
    from: 0; to: 4; duration: 2000; loops: Animation.Infinite
    running: view.active && view.timed
  }

  // No lyrics: the song's cover and a short, friendly line.
  Column {
    anchors.centerIn: parent
    width: parent.width - Style.space(40)
    spacing: Style.space(14)
    visible: !view.lyrics || view.lyrics.kind === "none"
    Item {
      anchors.horizontalCenter: parent.horizontalCenter
      width: Style.space(110); height: width
      visible: !!(view.svc && view.svc.hasTrack) && !view.busy
      Rectangle { id: emptyMask; anchors.fill: parent; radius: Style.space(10); visible: false; layer.enabled: true; color: "white" }
      Image {
        anchors.fill: parent
        source: view.svc && view.svc.hasTrack ? view.svc.thumb : ""
        sourceSize: Qt.size(256, 256)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        opacity: 0.85
        layer.enabled: true
        layer.effect: MultiEffect { maskEnabled: true; maskSource: emptyMask }
      }
    }
    Text {
      width: parent.width
      text: view.busy ? "Looking for lyrics\u2026" : view.error !== "" ? view.error
        : !view.svc || !view.svc.hasTrack ? "Play something to see its lyrics." : "Lyrics aren\u2019t available for this song."
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      horizontalAlignment: Text.AlignHCenter
      color: Util.alpha(view.fg, 0.65)
      font.family: view.family
      font.pixelSize: Style.font.body
    }
  }

  ListView {
    id: lines
    anchors.fill: parent
    anchors.bottomMargin: source.height + Style.space(6)
    visible: view.timed
    clip: true
    model: view.timed ? view.lyrics.lines : []
    boundsBehavior: Flickable.StopAtBounds
    onMovingChanged: if (moving && !scroller.running) { view.handScroll = true; handTimer.restart() }
    onContentHeightChanged: if (!scroller.running) Qt.callLater(view.follow)
    delegate: Item {
      id: lyricLine
      required property var modelData
      required property int index
      readonly property bool isCurrent: index === view.line
      readonly property bool instrumental: modelData.text === ""
      readonly property int gap: Math.abs(index - view.line)
      width: ListView.view ? ListView.view.width : 0
      height: instrumental ? Style.space(44) : lyricText.implicitHeight
      // Lines away from the sung one go soft, more the further they are.
      property real blurAmount: view.handScroll || view.line < 0 ? 0 : Math.min(0.85, gap * 0.2)
      Behavior on blurAmount { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
      layer.enabled: blurAmount > 0.02
      layer.effect: MultiEffect { blurEnabled: true; blurMax: 20; blur: lyricLine.blurAmount }

      Text {
        id: lyricText
        width: parent.width
        visible: !lyricLine.instrumental
        topPadding: Style.space(8)
        bottomPadding: Style.space(8)
        text: lyricLine.modelData.text
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        horizontalAlignment: view.centered ? Text.AlignHCenter : Text.AlignLeft
        color: Util.alpha(SpinTheme.Palette.text, lyricLine.isCurrent ? 1 : lyricLine.index < view.line ? 0.30 : 0.45)
        Behavior on color { ColorAnimation { duration: 350 } }
        font.family: view.family
        font.pixelSize: Math.round(Style.font.title * 1.3)
        font.weight: Font.Bold
        font.letterSpacing: -0.4
        transformOrigin: view.centered ? Item.Center : Item.Left
        scale: lyricLine.isCurrent ? 1 : 0.93
        Behavior on scale { SpringAnimation { spring: 3; damping: 0.4; epsilon: 0.002 } }
      }
      // Instrumental gap: three dots that breathe while the music plays on.
      Row {
        visible: lyricLine.instrumental
        anchors.verticalCenter: parent.verticalCenter
        x: view.centered ? (parent.width - width) / 2 : Style.space(4)
        spacing: Style.space(9)
        Repeater {
          model: 3
          Rectangle {
            required property int index
            readonly property real wave: lyricLine.isCurrent ? Math.max(0, 1 - Math.abs(view.pulse - index - 0.5)) : 0
            width: Style.space(11); height: width; radius: width / 2
            color: SpinTheme.Palette.text
            opacity: lyricLine.isCurrent ? 0.35 + 0.65 * wave : 0.3
            scale: 0.8 + 0.3 * wave
          }
        }
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: if (view.svc) { view.handScroll = false; view.svc.seek(lyricLine.modelData.t / 1000) }
      }
    }
  }

  Flickable {
    id: plain
    anchors.fill: parent
    anchors.bottomMargin: source.height + Style.space(6)
    visible: !!view.lyrics && view.lyrics.kind === "plain"
    clip: true
    contentHeight: plainText.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    Text {
      id: plainText
      width: plain.width
      text: view.lyrics && view.lyrics.kind === "plain" ? view.lyrics.text : ""
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      horizontalAlignment: view.centered ? Text.AlignHCenter : Text.AlignLeft
      // Untimed lyrics read like Apple Music's: large, bold, bright.
      lineHeight: 1.22
      color: Util.alpha(SpinTheme.Palette.text, 0.92)
      font.family: view.family
      font.pixelSize: Math.round(Style.font.title * 1.3)
      font.weight: Font.Bold
      font.letterSpacing: -0.4
    }
  }

  // Alignment switch, bottom right, shown whenever there are lyrics.
  HitButton {
    id: alignButton
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.bottomMargin: -Style.space(6)
    visible: !!view.lyrics && view.lyrics.kind !== "none"
    minSize: Style.space(30)
    iconText: view.centered ? "\u{F0262}" : "\u{F0260}"
    iconSize: Style.space(16)
    foreground: SpinTheme.Palette.secondary
    tooltipText: view.centered ? "Align lyrics left" : "Center lyrics"
    onClicked: view.toggleAlign()
  }

  Text {
    id: source
    anchors.bottom: parent.bottom
    width: parent.width - (alignButton.visible ? alignButton.width + Style.space(8) : 0)
    visible: text !== ""
    text: view.lyrics ? (view.lyrics.source || "") : ""
    textFormat: Text.PlainText
    elide: Text.ElideRight
    color: SpinTheme.Palette.tertiary
    font.family: view.family
    font.pixelSize: Style.font.caption
  }
}
