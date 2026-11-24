import QtQuick
import qs.Commons
import "../lib/Model.js" as Model
import "../lib/Icons.js" as Icons

// The queue: what plays next, and what autoplay would add after it.
Item {
  id: view

  property var svc: null
  property QtObject bar: null
  property var panel: null

  // On screen: the panel is open on this view. (`visible` stays true in a
  // closed panel's hidden window.)
  property bool active: false
  property var queue: null
  property string error: ""
  // The song J/K just moved: the cursor follows it once the queue reloads.
  property string follow: ""
  // Spinbloom: a song to highlight once the queue loads (from the mini
  // player's title, for songs with no album page). Kept for a moment so
  // the panel's own first load cannot move the cursor off it.
  property string focusId: ""
  onFocusIdChanged: if (focusId !== "") focusClear.restart()
  Timer { id: focusClear; interval: 2500; onTriggered: view.focusId = "" }
  readonly property var rows: Model.upNextRows(queue)
  property alias cursor: list.cursor
  readonly property var current: cursor >= 0 && cursor < rows.length ? rows[cursor] : null
  readonly property var hints: [["↵", "play"], ["x", "remove"], ["J K", "move"]]

  function shown() { load(true) }
  function move(dy) {
    list.cursor = Model.moveCursor(rows, list.cursor, dy)
    if (dy > 0 && list.cursor >= rows.length - 3) loadMore()
  }

  // A long list (a playlist, a radio) comes a page at a time; YouTube Music
  // adds the next one by itself only when playback nears the end. Reaching
  // the end of the list here asks for it too, one page per queue read
  // (from Solfa 775a445).
  property var askedMoreFor: null
  function loadMore() {
    if (!svc || !view.queue || !view.queue.more || view.askedMoreFor === view.queue) return
    view.askedMoreFor = view.queue
    svc.request("queue.more", {}, function (r) { if (!r.ok) view.askedMoreFor = null })
  }

  function load(jumpToCurrent) {
    if (!svc) return
    svc.request("queue", {}, function (r) {
      if (!r.ok) { view.error = Model.errorText(r.error); return }
      view.error = ""
      var keep = view.follow || (view.current && view.current.item ? view.current.item.videoId : "")
      view.follow = ""
      // Spinbloom: a reload (song change, queue edit) keeps the list where you
      // left it instead of snapping back to the top. Remember the row at the
      // top edge and how far into it the view sat, then put it back.
      var topRow = jumpToCurrent ? -1 : list.indexAt(list.width / 2, list.contentY + 1)
      var topItem = topRow >= 0 ? list.itemAtIndex(topRow) : null
      var into = topItem ? list.contentY - topItem.y : 0
      view.queue = r.data
      if (view.focusId) {
        for (var f = 0; f < view.rows.length; f++) if (view.rows[f].item && view.rows[f].item.videoId === view.focusId) {
          list.cursor = f
          Qt.callLater(function () { list.positionViewAtIndex(list.cursor, ListView.Center) })
          return
        }
      }
      if (topRow >= 0) Qt.callLater(function () {
        var row = Math.min(topRow, list.count - 1)
        if (row < 0) return
        list.positionViewAtIndex(row, ListView.Beginning)
        list.contentY += into
      })
      if (jumpToCurrent || !keep) {
        list.cursor = r.data.index >= 0 ? r.data.index : Model.firstRow(view.rows)
      } else {
        for (var i = 0; i < view.rows.length; i++) if (view.rows[i].item && view.rows[i].item.videoId === keep && !view.rows[i].automix) { list.cursor = i; return }
      }
    })
  }

  function actionsFor(row) {
    if (!row || !row.item) return []
    var heart = view.panel && view.panel.likeAction ? [view.panel.likeAction(row.item)] : []
    if (row.automix) return heart.concat([{ name: "jump", icon: Icons.play, tip: "Play now" }, { name: "remove", icon: Icons.close, tip: "Remove (x)" }])
    var out = heart.slice()
    if (row.queueIndex > 0) out.push({ name: "up", icon: Icons.up, tip: "Move up (K)" })
    if (view.queue && row.queueIndex < view.queue.items.length - 1) out.push({ name: "down", icon: Icons.down, tip: "Move down (J)" })
    if (!row.current) out.push({ name: "remove", icon: Icons.close, tip: "Remove (x)" })
    return out
  }

  function done(r) { if (!r.ok) view.error = Model.errorText(r.error) }

  function jump(row) {
    if (!row || !row.item) return
    svc.markPending(row.item)
    svc.request("queue.jump", { index: row.queueIndex, automix: !!row.automix }, function (r) { if (!r.ok) svc.clearPending(); done(r) })
  }
  function remove(row) {
    if (!row || !row.item) return
    if (row.current) { view.error = Model.errorText("playing"); return }
    svc.request("queue.remove", { index: row.queueIndex, automix: !!row.automix }, done)
  }
  function shift(row, d) {
    if (!row || !row.item || row.automix || !view.queue) return
    var to = row.queueIndex + d
    if (to < 0 || to >= view.queue.items.length) return
    // The reload after the move puts the cursor back on this song.
    view.follow = row.item.videoId
    svc.request("queue.move", { from: row.queueIndex, to: to }, function (r) { done(r) })
  }

  function runAction(name, row) {
    if (name === "like") { if (view.panel && row && row.item) view.panel.toggleRowLike(row.item); return }
    if (name === "jump") jump(row)
    else if (name === "remove") remove(row)
    else if (name === "up") shift(row, -1)
    else if (name === "down") shift(row, 1)
  }

  // Keys only the queue has.
  function key(t) {
    if (t === "x") { remove(view.current); return true }
    if (t === "K") { shift(view.current, -1); return true }
    if (t === "J") { shift(view.current, 1); return true }
    return false
  }
  function activate() { jump(view.current) }

  Timer { id: reload; interval: 120; onTriggered: view.load(false) }

  Connections {
    target: view.svc
    function onQueueChanged() { if (view.active) reload.restart() }
  }

  RowList {
    id: list
    swirlTint: view.panel ? view.panel.swirlTint : "white"
    anchors.fill: parent
    bar: view.bar
    rows: view.rows
    playingId: view.svc ? view.svc.videoId : ""
    spinNow: true
    spinning: !!(view.svc && view.svc.isPlaying)
    pendingId: view.svc ? view.svc.pendingId : ""
    actionsFor: view.actionsFor
    emptyText: view.error !== "" ? view.error : "Nothing queued yet. Press / to find something."
    onActivated: function (i) { view.jump(view.rows[i]) }
    onAction: function (name, i) { view.runAction(name, view.rows[i]) }
    onAtYEndChanged: if (atYEnd) view.loadMore()
    // "Up Next" carries Shuffle and Repeat on the right of its heading.
    headerTools: function (row) {
      if (!row.upNext || !view.svc) return []
      var mode = view.svc.repeatMode
      return [
        { key: "shuffle", icon: "shuffle", label: "Shuffle", on: false, tip: "Shuffle what plays next (s)" },
        { key: "repeat", icon: mode === "ONE" ? "repeat-one" : "repeat", label: mode === "ONE" ? "Repeat one" : "Repeat",
          on: mode !== "NONE", tip: Model.repeatLabel(mode) + " (r)" }
      ]
    }
    onHeaderTool: function (key) {
      if (!view.svc) return
      if (key === "shuffle") view.svc.shuffle()
      else if (key === "repeat") view.svc.cycleRepeat()
    }
  }
}
