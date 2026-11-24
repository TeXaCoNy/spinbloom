import QtQuick
import QtQuick.Effects
import "../theme2" as SpinTheme
import qs.Ui
import qs.Commons
import "../lib/Model.js" as Model
import "../lib/Icons.js" as Icons

// An album, a playlist, an artist, or a "show all" shelf, opened from any
// list. Esc goes back.
Item {
  id: view

  property var svc: null
  property QtObject bar: null
  property var panel: null
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string family: "Inter"

  property var page: null        // { id, params, title }
  property var info: null
  property bool busy: false
  property bool loadingMore: false
  property string error: ""
  readonly property var rows: !info ? [] : info.tracks ? Model.trackRows(info.tracks) : Model.shelfRows(info.sections, info.kind === "artist" ? 6 : 0)
  property alias cursor: list.cursor
  readonly property var current: cursor >= 0 && cursor < rows.length ? rows[cursor] : null
  readonly property var hints: [["↵", "play or open"], ["e", "play next"], ["esc", "back"]]

  function shown() {}
  function move(dy) {
    list.cursor = Model.moveCursor(rows, list.cursor, dy)
    if (dy > 0 && list.cursor >= rows.length - 3) loadMore()
  }

  // Spinbloom: a page opened for a song (title clicked in the mini player)
  // lands with that song highlighted and in view; otherwise the first row.
  function startRow() {
    var want = view.page && view.page.focus ? view.page.focus : ""
    if (want) for (var i = 0; i < view.rows.length; i++)
      if (view.rows[i].item && view.rows[i].item.videoId === want) return i
    return Model.firstRow(view.rows)
  }
  function open(p) {
    view.page = p
    view.info = p.info || null
    view.error = ""
    if (view.info) { list.cursor = view.startRow(); return }
    view.busy = true
    var want = p.id
    var args = { id: p.id }
    if (p.params) args.params = p.params
    svc.request("browse", args, function (r) {
      if (!view.page || view.page.id !== want) return
      view.busy = false
      if (!r.ok) { view.error = Model.errorText(r.error); return }
      view.info = r.data
      view.page.info = r.data
      if (want === "VLLM" || want === "LM") svc.noteLiked(r.data.tracks)
      list.cursor = view.startRow()
      Qt.callLater(function () { if (list.cursor >= 0) list.positionViewAtIndex(list.cursor, ListView.Center) })
    })
  }

  function loadMore() {
    if (!view.info || !view.info.continuation || view.loadingMore) return
    view.loadingMore = true
    var want = view.page.id
    svc.request("browse", { id: view.page.id, continuation: view.info.continuation }, function (r) {
      view.loadingMore = false
      if (!view.page || view.page.id !== want || !r.ok) return
      var d = Object.assign({}, view.info)
      d.tracks = (d.tracks || []).concat(r.data.tracks || [])
      d.continuation = r.data.continuation || ""
      view.info = d
      view.page.info = d
    })
  }

  // Tracks play in their list's context: an album keeps playing the album.
  function contextList() { return view.info && view.info.kind !== "artist" ? (view.info.playlistId || "") : "" }

  function playAll(shuffle) {
    if (!view.info) return
    if (view.info.kind === "artist") {
      var s = shuffle ? view.info.shuffle : view.info.radio
      if (!s) return
      var a = { playlistId: s.playlistId }
      if (s.videoId) a.videoId = s.videoId
      if (s.params) a.params = s.params
      svc.request("play", a)
      return
    }
    if (!view.info.playlistId) return
    var args = { playlistId: view.info.playlistId }
    if (shuffle) args.params = "wAEB8gECKAE%3D"
    svc.request("play", args)
  }

  // Apple-style page header: "‹ Back", then large artwork with the title,
  // artist and details beside it, and capsule Play and Shuffle buttons.
  readonly property bool isArtist: !!view.info && view.info.kind === "artist"
  readonly property bool isAlbum: !!view.info && view.info.kind === "album"
  readonly property string albumArtist: isAlbum ? Model.artistsText(view.info.artists) : ""

  Column {
    id: head
    width: parent.width
    spacing: Style.space(10)

    Item {
      width: backLink.width
      height: backLink.height
      Row {
        id: backLink
        spacing: Style.space(2)
        opacity: backHit.containsMouse ? 1 : 0.75
        Glyph { anchors.verticalCenter: parent.verticalCenter; name: "back"; size: Style.space(14); color: view.fg }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "Back"
          textFormat: Text.PlainText
          color: view.fg
          font.family: view.family
          font.pixelSize: Style.font.caption
          font.weight: Font.Medium
        }
      }
      MouseArea {
        id: backHit
        x: -Style.space(6); y: -Style.space(4)
        width: backLink.width + Style.space(12); height: backLink.height + Style.space(8)
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: if (view.panel) view.panel.back()
      }
    }

    Row {
      width: parent.width
      spacing: Style.space(16)

      Item {
        id: cover
        width: Style.space(128); height: width
        Rectangle {
          id: coverMask
          anchors.fill: parent
          radius: view.isArtist ? width / 2 : Style.space(10)
          visible: false; layer.enabled: true; color: "white"
        }
        Rectangle {
          anchors.fill: parent
          radius: coverMask.radius
          color: SpinTheme.Palette.bubble
          layer.enabled: true
          layer.effect: MultiEffect { shadowEnabled: true; shadowOpacity: 0.45; shadowBlur: 0.8; shadowVerticalOffset: Style.space(6) }
        }
        Image {
          anchors.fill: parent
          source: view.info ? (view.info.thumb || "") : ""
          sourceSize: Qt.size(512, 512)
          asynchronous: true; fillMode: Image.PreserveAspectCrop; smooth: true; mipmap: true
          layer.enabled: true
          layer.effect: MultiEffect { maskEnabled: true; maskSource: coverMask }
        }
      }

      Column {
        id: headInfo
        width: parent.width - cover.width - parent.spacing
        // Bottom-aligned with the artwork, as Apple does.
        y: Math.max(0, cover.height - implicitHeight)
        spacing: Style.space(3)
        Text {
          width: parent.width
          text: view.info && view.info.title ? view.info.title : (view.page ? view.page.title : "")
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          maximumLineCount: 2
          elide: Text.ElideRight
          color: view.fg
          font.family: view.family
          font.pixelSize: Math.round(Style.font.title * 1.35)
          font.weight: Font.Bold
          font.letterSpacing: -0.5
        }
        Text {
          width: parent.width
          visible: text !== ""
          text: !view.info ? "" : view.isAlbum ? view.albumArtist
            : view.info.kind === "playlist" ? (view.info.author || "") : ""
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: Util.alpha(view.fg, 0.85)
          font.family: view.family
          font.pixelSize: Style.font.body
        }
        Text {
          width: parent.width
          text: !view.info ? (view.busy ? "Loading" : view.error)
            : [view.info.subtitle || "", view.info.tracks && view.info.tracks.length && !view.isArtist
                ? view.info.tracks.length + (view.info.tracks.length === 1 ? " song" : " songs") : ""].filter(Boolean).join(" \u00b7 ")
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: Util.alpha(view.fg, 0.55)
          font.family: view.family
          font.pixelSize: Style.font.caption
        }
        Item { width: 1; height: Style.space(6) }
        Row {
          spacing: Style.space(8)
          Capsule {
            visible: !!view.info && (view.isArtist ? !!view.info.radio : !!view.info.playlistId)
            primary: true
            icon: view.isArtist ? "radio" : "play"
            label: view.isArtist ? "Radio" : "Play"
            onClicked: view.playAll(false)
          }
          Capsule {
            visible: !!view.info && (view.isArtist ? !!view.info.shuffle : !!view.info.playlistId)
            icon: "shuffle"
            label: "Shuffle"
            onClicked: view.playAll(true)
          }
        }
      }
    }
  }

  // A capsule button: white with dark text (primary), or a soft glass fill.
  component Capsule: Rectangle {
    id: cap
    property bool primary: false
    property string icon: ""
    property string label: ""
    signal clicked()
    width: capRow.width + Style.space(28)
    height: Style.space(32)
    radius: height / 2
    color: cap.primary ? (capHit.containsMouse ? Qt.darker(SpinTheme.Palette.text, 1.08) : SpinTheme.Palette.text)
      : capHit.containsMouse ? SpinTheme.Palette.fillHover : SpinTheme.Palette.fill
    scale: capHit.pressed ? 0.96 : 1
    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
    Behavior on color { ColorAnimation { duration: 110 } }
    Row {
      id: capRow
      anchors.centerIn: parent
      spacing: Style.space(6)
      Glyph {
        anchors.verticalCenter: parent.verticalCenter
        name: cap.icon
        size: Style.space(14)
        color: cap.primary ? SpinTheme.Palette.onAccent : SpinTheme.Palette.text
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: cap.label
        textFormat: Text.PlainText
        color: cap.primary ? SpinTheme.Palette.onAccent : SpinTheme.Palette.text
        font.family: view.family
        font.pixelSize: Style.font.caption
        font.weight: Font.DemiBold
      }
    }
    MouseArea { id: capHit; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: cap.clicked() }
  }

  RowList {
    id: list
    swirlTint: view.panel ? view.panel.swirlTint : "white"
    anchors.top: head.bottom
    anchors.topMargin: Style.space(14)
    numbered: view.isAlbum
    pageArtist: view.albumArtist
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    bar: view.bar
    rows: view.rows
    playingId: view.svc ? view.svc.videoId : ""
    pendingId: view.svc ? view.svc.pendingId : ""
    actionsFor: function (row) { return view.panel ? view.panel.itemActions(row) : [] }
    emptyText: view.busy ? "Loading" : view.error
    onActivated: function (i) { view.panel.activateRow(view.rows[i], view.contextList()) }
    onAction: function (name, i) { view.panel.runAction(name, view.rows[i]) }
    onHeaderActivated: function (i) { var r = view.rows[i]; if (r.more) view.panel.openPage({ browseId: r.more, title: r.header }, r.moreParams) }
    onAtYEndChanged: if (atYEnd) view.loadMore()
    onTileActivated: function (it) { if (view.panel) view.panel.activateRow({ item: it }, "") }
  }
}
