import QtQuick
import "../theme2" as SpinTheme
import qs.Ui
import qs.Commons
import "../lib/Model.js" as Model

// Search: a field, filter chips, and one list of results. With an empty
// field it shows YouTube Music's home shelves, so there is always
// something to play.
Item {
  id: view

  property var svc: null
  property QtObject bar: null
  property var panel: null
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string family: "Inter"

  property string query: ""
  property string filter: ""
  property var result: null
  property var home: null
  property bool busy: false
  property string error: ""
  property int seq: 0

  readonly property bool inputFocused: field.activeFocus
  readonly property var rows: query.trim() === "" ? Model.shelfRows(home ? home.sections : [], 6) : Model.searchRows(result, filter)
  property alias cursor: list.cursor
  readonly property var current: cursor >= 0 && cursor < rows.length ? rows[cursor] : null
  readonly property var hints: inputFocused
    ? [["↵", "search"], ["↓", "results"], ["esc", "clear"]]
    : [["↵", "play or open"], ["e", "play next"], ["a", "add to queue"], ["[ ]", "filter"]]

  readonly property var filters: [
    { key: "", label: "All" }, { key: "songs", label: "Songs" }, { key: "albums", label: "Albums" },
    { key: "artists", label: "Artists" }, { key: "playlists", label: "Playlists" }, { key: "videos", label: "Videos" }
  ]

  // On screen: the panel is open on this view (see QueueView).
  property bool active: false
  function shown() { if (!home && svc && svc.ready) loadHome() }
  readonly property bool ready: svc ? svc.ready : false
  onReadyChanged: if (ready && active && !home) loadHome()
  // Spinbloom: run a search typed elsewhere (the mini player's welcome).
  function setQuery(q) { field.text = q; view.query = q; debounce.stop(); view.run() }
  function focusInput() { field.forceActiveFocus(); field.selectAll() }
  function move(dy) { list.cursor = Model.moveCursor(rows, list.cursor, dy) }

  function loadHome() {
    if (!svc) return
    svc.request("home", {}, function (r) { if (r.ok) view.home = r.data })
  }

  function run() {
    var q = view.query.trim()
    if (!q) { view.result = null; view.error = ""; return }
    var s = ++view.seq
    view.busy = true
    view.error = ""
    var args = { q: q }
    if (view.filter) args.filter = view.filter
    svc.request("search", args, function (r) {
      if (s !== view.seq) return
      view.busy = false
      if (r.ok) {
        view.result = r.data
        list.cursor = Model.firstRow(view.rows)
      } else {
        view.error = Model.errorText(r.error)
      }
    })
  }

  function cycleFilter(d) {
    var i = 0
    for (var k = 0; k < filters.length; k++) if (filters[k].key === view.filter) i = k
    setFilter(filters[(i + d + filters.length) % filters.length].key)
  }

  function setFilter(key) {
    view.filter = key
    if (view.query.trim()) run()
  }

  // Enter in the field: search now and move to the results.
  function acceptField() {
    debounce.stop()
    run()
    panel.focusKeys()
  }

  function clearField() {
    if (field.text !== "") { field.text = ""; view.query = ""; view.result = null }
    else panel.focusKeys()
  }

  function headerActivated(index) {
    var more = rows[index] && rows[index].more
    if (more && view.query.trim()) setFilter(more)
    else if (more) panel.openPage({ browseId: more, title: rows[index].header }, rows[index].moreParams)
  }

  Timer { id: debounce; interval: 350; onTriggered: view.run() }

  Column {
    id: searchHeader
    width: parent.width
    spacing: Style.space(8)

    TextField {
      accent: SpinTheme.Palette.accent
      id: field
      width: parent.width
      placeholderText: "Songs, albums, artists and playlists"
      leftPadding: Style.space(36)
      topPadding: Style.space(9)
      bottomPadding: Style.space(9)
      // Apple's search field: a soft rounded fill, no outline.
      background: Rectangle {
        radius: Style.space(10)
        color: field.activeFocus ? SpinTheme.Palette.fillPressed : SpinTheme.Palette.fill
        Behavior on color { ColorAnimation { duration: 140 } }
        Glyph {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          name: "search"
          size: Style.space(15)
          color: SpinTheme.Palette.secondary
        }
      }
      font.family: view.family
      onTextEdited: { view.query = text; debounce.restart() }
      onAccepted: view.acceptField()
      Keys.onEscapePressed: function (e) { view.clearField(); e.accepted = true }
      Keys.onDownPressed: function (e) { view.panel.focusKeys(); if (view.cursor < 0) view.move(1); e.accepted = true }
    }

    Row {
      spacing: Style.space(4)
      visible: view.query.trim() !== ""
      Repeater {
        model: view.filters
        delegate: Button {
          required property var modelData
          text: modelData.label
          fontFamily: view.family
          fontSize: Style.font.caption
          selected: view.filter === modelData.key
          foreground: view.fg
          verticalPadding: Style.space(3)
          horizontalPadding: Style.space(8)
          onClicked: view.setFilter(modelData.key)
        }
      }
    }
  }

  RowList {
    id: list
    swirlTint: view.panel ? view.panel.swirlTint : "white"
    anchors.top: searchHeader.bottom
    anchors.topMargin: Style.space(8)
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    bar: view.bar
    rows: view.rows
    playingId: view.svc ? view.svc.videoId : ""
    pendingId: view.svc ? view.svc.pendingId : ""
    actionsFor: function (row) { return view.panel ? view.panel.itemActions(row) : [] }
    emptyText: view.busy ? "Searching" : view.error !== "" ? view.error
      : view.query.trim() !== "" ? "No results" : (view.home ? "" : "Loading suggestions")
    onActivated: function (i) { view.panel.activateRow(view.rows[i]) }
    onAction: function (name, i) { view.panel.runAction(name, view.rows[i]) }
    onHeaderActivated: function (i) { view.headerActivated(i) }
    onTileActivated: function (it) { if (view.panel) view.panel.activateTile(it) }
  }
}
