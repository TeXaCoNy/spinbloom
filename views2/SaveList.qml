import QtQuick
import qs.Commons
import "../lib/Model.js" as Model

// Save a song to one of your playlists (from Solfa's save picker, redrawn
// for Spinbloom). Used by the player's ••• menu drawer and by the full
// player's song rows. The host supplies the colours and opens it with
// open(item); it says what happened through done(message).
//
// A song already in the playlist is not added twice: the row says so and
// a second click adds it anyway. "New playlist" makes a playlist with the
// song in it.
Item {
  id: root

  property var svc: null
  property color ink: "white"
  property color inkSoft: Qt.rgba(1, 1, 1, 0.7)
  property string family: "Inter"
  // The list scrolls past this height.
  property real maxListHeight: Style.space(300)

  signal done(string message)

  property var item: null
  property var playlists: []
  property bool busy: false
  property string error: ""
  property string query: ""
  property string duplicateId: ""   // the row that said "already in it"
  property string savingId: ""
  property bool creating: false
  property string newName: ""
  readonly property bool signedIn: !!(svc && svc.signedIn)
  readonly property var rows: Model.saveRows(playlists, query)

  implicitHeight: col.implicitHeight

  function open(it) {
    root.item = it
    root.playlists = []
    root.query = ""
    root.error = ""
    root.duplicateId = ""
    root.savingId = ""
    root.creating = false
    root.newName = ""
    filterField.text = ""
    if (!svc || !it || !it.videoId || !signedIn) return
    root.busy = true
    svc.request("playlist.options", { videoId: it.videoId }, function (r) {
      root.busy = false
      if (!r.ok) { root.error = Model.errorText(r.error); return }
      root.playlists = (r.data && r.data.playlists) || []
    })
  }

  function save(p) {
    if (!p || !root.item || root.savingId !== "") return
    var force = root.duplicateId === p.id
    root.savingId = p.id
    var args = { playlistId: p.id, videoId: root.item.videoId }
    if (force) args.force = true
    svc.request("playlist.add", args, function (r) {
      root.savingId = ""
      if (!r.ok) { root.error = Model.errorText(r.error); return }
      if (r.data && r.data.duplicate) { root.duplicateId = p.id; return }
      root.duplicateId = ""
      root.done("Saved to " + (p.title || "playlist"))
    })
  }

  function create() {
    var title = root.newName.trim()
    if (title === "" || !root.item || root.savingId !== "") return
    root.savingId = "new"
    svc.request("playlist.create", { title: title, videoIds: [root.item.videoId] }, function (r) {
      root.savingId = ""
      if (!r.ok) { root.error = Model.errorText(r.error); return }
      root.done("Saved to new playlist " + title)
    })
  }

  Column {
    id: col
    width: parent.width
    spacing: Style.space(2)

    Text {
      width: parent.width
      leftPadding: Style.space(10)
      text: "Save to playlist"
      textFormat: Text.PlainText
      color: root.inkSoft
      font.family: root.family
      font.pixelSize: Style.font.caption
      font.weight: Font.DemiBold
    }
    Text {
      width: parent.width
      leftPadding: Style.space(10)
      bottomPadding: Style.space(6)
      text: root.item ? (root.item.title || "") : ""
      textFormat: Text.PlainText
      elide: Text.ElideRight
      color: root.ink
      font.family: root.family
      font.pixelSize: Style.font.body
      font.weight: Font.Medium
    }

    // A quiet line instead of the list: signed out, loading, an error.
    Text {
      width: parent.width
      visible: text !== ""
      leftPadding: Style.space(10)
      topPadding: Style.space(6); bottomPadding: Style.space(8)
      wrapMode: Text.WordWrap
      text: !root.signedIn ? "Sign in to YouTube Music to save songs to your playlists"
        : root.error !== "" ? root.error
        : root.busy ? "Loading your playlists…" : ""
      textFormat: Text.PlainText
      color: root.inkSoft
      font.family: root.family
      font.pixelSize: Style.font.caption
    }

    // Filter: only shown when there are enough playlists to need it.
    Rectangle {
      width: parent.width
      height: visible ? Style.space(34) : 0
      visible: root.signedIn && !root.busy && root.playlists.length > 8
      radius: height / 2
      color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.08)
      TextInput {
        id: filterField
        anchors.fill: parent
        anchors.leftMargin: Style.space(14); anchors.rightMargin: Style.space(14)
        verticalAlignment: TextInput.AlignVCenter
        color: root.ink
        font.family: root.family
        font.pixelSize: Style.font.body
        clip: true
        onTextChanged: root.query = text
        Text {
          anchors.verticalCenter: parent.verticalCenter
          visible: parent.text === ""
          text: "Find a playlist"
          color: root.inkSoft
          font: parent.font
        }
      }
    }

    ListView {
      id: list
      width: parent.width
      visible: root.signedIn && !root.busy && root.error === ""
      height: visible ? Math.min(contentHeight, root.maxListHeight) : 0
      clip: true
      interactive: contentHeight > height
      boundsBehavior: Flickable.StopAtBounds
      model: root.rows
      delegate: Item {
        id: row
        required property var modelData
        readonly property bool isHeader: !!modelData.header
        readonly property bool isCreate: !!modelData.create
        readonly property var p: modelData.playlist || null
        readonly property bool dup: !!p && root.duplicateId === p.id
        readonly property bool saving: (!!p && root.savingId === p.id) || (isCreate && root.savingId === "new")
        width: list.width
        height: isHeader ? Style.space(30) : (isCreate && root.creating) ? Style.space(46) : Style.space(44)

        Text {
          visible: row.isHeader
          anchors.left: parent.left; anchors.leftMargin: Style.space(10)
          anchors.bottom: parent.bottom; anchors.bottomMargin: Style.space(4)
          text: row.modelData.header || ""
          textFormat: Text.PlainText
          color: root.inkSoft
          font.family: root.family
          font.pixelSize: Style.font.caption
          font.weight: Font.DemiBold
        }

        Rectangle {
          visible: !row.isHeader
          anchors.fill: parent
          radius: Style.space(10)
          color: hit.containsMouse && !(row.isCreate && root.creating) ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, hit.pressed ? 0.16 : 0.09)
            : row.dup ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.06) : "transparent"
          Behavior on color { ColorAnimation { duration: 90 } }
        }
        Glyph {
          id: rowIcon
          visible: !row.isHeader
          anchors.left: parent.left; anchors.leftMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          name: row.isCreate ? "plus" : "list"
          color: root.inkSoft
          size: Style.space(17)
        }
        // "New playlist", or its name field once clicked.
        TextInput {
          id: nameField
          visible: row.isCreate && root.creating
          anchors.left: rowIcon.right; anchors.leftMargin: Style.space(12)
          anchors.right: parent.right; anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          color: root.ink
          font.family: root.family
          font.pixelSize: Style.font.body
          clip: true
          maximumLength: 150
          onVisibleChanged: if (visible) { text = ""; forceActiveFocus() }
          onTextChanged: root.newName = text
          onAccepted: root.create()
          Keys.onEscapePressed: event => { root.creating = false; event.accepted = true }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: parent.text === ""
            text: "Name, then Enter"
            color: root.inkSoft
            font: parent.font
          }
        }
        Column {
          visible: !row.isHeader && !(row.isCreate && root.creating)
          anchors.left: rowIcon.right; anchors.leftMargin: Style.space(12)
          anchors.right: rowEnd.left; anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          Text {
            width: parent.width
            text: row.isCreate ? "New playlist" : (row.p ? row.p.title : "")
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: root.ink
            font.family: root.family
            font.pixelSize: Style.font.body
          }
          Text {
            width: parent.width
            visible: text !== ""
            text: row.dup ? "Already in it · click again to add anyway" : row.p ? (row.p.count || "") : ""
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: root.inkSoft
            font.family: root.family
            font.pixelSize: Style.font.caption
          }
        }
        Text {
          id: rowEnd
          anchors.right: parent.right; anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          visible: row.saving
          text: "Saving…"
          color: root.inkSoft
          font.family: root.family
          font.pixelSize: Style.font.caption
        }
        MouseArea {
          id: hit
          anchors.fill: parent
          visible: !row.isHeader && !(row.isCreate && root.creating)
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (row.isCreate) root.creating = true
            else root.save(row.p)
          }
        }
      }
    }
  }
}
