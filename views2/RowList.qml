import QtQuick
import "../theme2" as SpinTheme
import qs.Ui
import qs.Commons
import "../lib/Model.js" as Model
import "../lib/Icons.js" as Icons

// One list for every view: section headers, song rows, and (Spinbloom design)
// Apple-style artwork shelves and grids, with a keyboard cursor and per-row
// buttons that show on hover or on the cursor row.
//
//   rows: [{ header, more } | { item, current, automix, queueIndex, n }
//          | { shelf: true, items } | { grid: true, items }]
//   actionsFor(row) → [{ name, icon, tip, on }]
//
// A song row: cover (or track number), title and artist, then the hover
// buttons, then a fixed heart slot right beside the time, so a liked song's
// heart always lines up in the same column, as in Apple Music.
ListView {
  id: list

  property var rows: []
  property int cursor: -1
  property QtObject bar: null
  property string playingId: ""
  // A song just chosen and still loading (Service.pendingId).
  property string pendingId: ""
  property var actionsFor: function (row) { return [] }
  property string emptyText: ""
  property color fg: bar ? bar.foreground : Color.foreground
  property string family: "Inter"
  // Album pages: track numbers instead of covers.
  property bool numbered: false
  // The Queue: the playing row shows a tiny spinning CD (spinning = playing).
  property bool spinNow: false
  // The like swirl (HeartSwirl) on a row's heart, in this colour.
  property color swirlTint: "white"
  // History: only this row spins (the song may be listed more than once).
  property int spinIndex: -1
  property bool spinning: false
  // Album pages: the album's artist, left off rows by that same artist.
  property string pageArtist: ""
  // Buttons on the right of a section heading: (row) → [{ key, icon, label, on, tip }]
  property var headerTools: function (row) { return [] }

  signal activated(int index)
  signal action(string name, int index)
  signal headerActivated(int index)
  // A shelf or grid tile was clicked.
  signal tileActivated(var item)
  signal headerTool(string key)

  model: rows
  clip: true
  boundsBehavior: Flickable.StopAtBounds
  reuseItems: false
  cacheBuffer: 400
  spacing: 0

  onCursorChanged: if (cursor >= 0 && cursor < count) positionViewAtIndex(cursor, ListView.Contain)
  onRowsChanged: if (cursor >= rows.length) cursor = Model.firstRow(rows)

  // Which icon each row button uses (the mini player's rounded set).
  function iconFor(a) {
    switch (a.name) {
      case "like": return a.on ? "heart-fill" : "heart"
      case "next": return "play-next"
      case "queue": return "plus"
      case "radio": return "radio"
      case "up": return "up"
      case "down": return "down"
      case "remove": return "close"
      case "jump": case "play": return a.icon === Icons.shuffle ? "shuffle" : "play"
      default: return ""
    }
  }
  function scrollBy(dy) {
    const top = list.originY
    const bottom = list.originY + Math.max(0, list.contentHeight - list.height)
    list.contentY = Math.max(top, Math.min(bottom, list.contentY + dy))
  }

  Text {
    anchors.centerIn: parent
    width: parent.width - Style.space(40)
    visible: list.rows.length === 0 && list.emptyText !== ""
    text: list.emptyText
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    horizontalAlignment: Text.AlignHCenter
    color: Util.alpha(list.fg, 0.6)
    font.family: list.family
    font.pixelSize: Style.font.body
  }

  // ---- an artwork tile (shelves and grids) ---------------------------------
  component Tile: Item {
    id: tile
    property var item: null
    property real size: Style.space(124)
    readonly property bool round: !!item && item.kind === "artist"
    width: size
    height: size + tileText.height + Style.space(8)
    property real lift: tileHit.containsMouse ? 1 : 0
    Behavior on lift { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    SquareCover {
      id: tileCover
      width: tile.size; height: tile.size
      y: -tile.lift * Style.space(3)
      scale: 1 + tile.lift * 0.02
      source: tile.item ? (tile.item.thumb || "") : ""
      circle: tile.round
      glyph: !tile.item ? Icons.note : tile.round ? Icons.artist : tile.item.kind === "album" ? Icons.album : Icons.note
    }
    Column {
      id: tileText
      y: tile.size + Style.space(6)
      width: tile.size
      spacing: Style.space(1)
      Text {
        width: parent.width
        text: tile.item ? (tile.item.title || "") : ""
        textFormat: Text.PlainText
        elide: Text.ElideRight
        horizontalAlignment: tile.round ? Text.AlignHCenter : Text.AlignLeft
        color: SpinTheme.Palette.text
        font.family: list.family
        font.pixelSize: Style.font.caption
        font.weight: Font.Medium
      }
      Text {
        width: parent.width
        text: Model.rowSubtitle(tile.item)
        visible: text !== ""
        textFormat: Text.PlainText
        elide: Text.ElideRight
        horizontalAlignment: tile.round ? Text.AlignHCenter : Text.AlignLeft
        color: SpinTheme.Palette.secondary
        font.family: list.family
        font.pixelSize: Style.font.caption
      }
    }
    MouseArea {
      id: tileHit
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: list.tileActivated(tile.item)
      // Up/down wheel scrolls the page, not the shelf.
      onWheel: wheel => {
        if (Math.abs(wheel.angleDelta.y) > Math.abs(wheel.angleDelta.x)) list.scrollBy(-wheel.angleDelta.y * 0.6)
        else wheel.accepted = false
      }
    }
  }

  delegate: Item {
    id: cell
    required property var modelData
    required property int index
    readonly property bool isHeader: !!modelData.header
    readonly property bool isShelf: !!modelData.shelf
    readonly property bool isGrid: !!modelData.grid
    readonly property bool isRow: !isHeader && !isShelf && !isGrid
    readonly property var item: modelData.item || null
    readonly property bool selected: index === list.cursor
    readonly property bool loading: !!item && !!item.videoId && list.pendingId !== "" && item.videoId === list.pendingId
    readonly property bool now: list.pendingId !== "" ? loading
      : !!item && !!item.videoId && (modelData.current === true || (modelData.current === undefined && !modelData.automix && item.videoId === list.playingId))
    readonly property var allActions: isRow ? list.actionsFor(modelData) : []
    readonly property var likeAction: allActions.find(a => a.name === "like") || null
    readonly property var hoverActions: allActions.filter(a => a.name !== "like")
    // A handler, not the MouseArea: it stays hovered while the pointer is on
    // one of the row's own buttons, so they do not hide under it.
    readonly property bool showActions: selected || rowHover.hovered
    readonly property string subtitle: {
      if (!item) return ""
      const sub = Model.rowSubtitle(item)
      // The unfiltered search marks each song, video or episode with its type
      // ("Video · Artist", from Solfa 868cdc8).
      return Model.labelled(modelData && modelData.label ? modelData.label : "", list.pageArtist !== "" && sub === list.pageArtist ? "" : sub)
    }

    width: ListView.view ? ListView.view.width : 0
    z: rowSwirlRunning ? 10 : 0
    property bool rowSwirlRunning: false
    height: isHeader ? Style.space(40)
      : isShelf ? shelfView.height + Style.space(6)
      : isGrid ? gridFlow.implicitHeight + Style.space(8)
      : Style.space(46)

    // ---- section header: a bold title, "See all ›" on the right -------------
    Item {
      visible: cell.isHeader
      anchors.fill: parent
      Text {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(4)
        anchors.right: seeAll.left
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(6)
        text: cell.modelData.header || ""
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: SpinTheme.Palette.text
        font.family: list.family
        font.pixelSize: Style.font.title
        font.weight: Font.Bold
        font.letterSpacing: -0.3
      }
      // Small capsule toggles on the right (the queue's Shuffle and Repeat).
      Row {
        anchors.right: parent.right
        anchors.rightMargin: Style.space(4)
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(4)
        spacing: Style.space(6)
        visible: cell.isHeader
        Repeater {
          model: cell.isHeader ? list.headerTools(cell.modelData) : []
          delegate: Rectangle {
            id: tool
            required property var modelData
            width: toolRow.width + Style.space(18)
            height: Style.space(26)
            radius: height / 2
            color: modelData.on ? (SpinTheme.Palette.light ? "white" : SpinTheme.Palette.text) : toolHit.containsMouse ? SpinTheme.Palette.fillHover : SpinTheme.Palette.fill
            border.width: modelData.on && SpinTheme.Palette.light ? 1 : 0
            border.color: Util.alpha(SpinTheme.Palette.text, 0.12)
            Behavior on color { ColorAnimation { duration: 140 } }
            Row {
              id: toolRow
              anchors.centerIn: parent
              spacing: Style.space(5)
              Glyph { anchors.verticalCenter: parent.verticalCenter; name: tool.modelData.icon; size: Style.space(13)
                color: tool.modelData.on && !SpinTheme.Palette.light ? SpinTheme.Palette.onAccent : SpinTheme.Palette.text }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: tool.modelData.label
                textFormat: Text.PlainText
                color: tool.modelData.on && !SpinTheme.Palette.light ? SpinTheme.Palette.onAccent : SpinTheme.Palette.text
                font.family: list.family
                font.pixelSize: Style.font.caption
                font.weight: Font.Medium
              }
            }
            MouseArea { id: toolHit; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
              onClicked: list.headerTool(tool.modelData.key) }
          }
        }
      }
      Row {
        id: seeAll
        visible: !!cell.modelData.more
        anchors.right: parent.right
        anchors.rightMargin: Style.space(6)
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(8)
        spacing: Style.space(2)
        Text {
          text: "See all"
          textFormat: Text.PlainText
          color: headerMouse.containsMouse ? SpinTheme.Palette.text : SpinTheme.Palette.secondary
          font.family: list.family
          font.pixelSize: Style.font.caption
          font.weight: Font.Medium
        }
        Glyph {
          anchors.verticalCenter: parent.verticalCenter
          name: "forward"
          size: Style.space(11)
          color: headerMouse.containsMouse ? SpinTheme.Palette.text : SpinTheme.Palette.secondary
        }
      }
      MouseArea {
        id: headerMouse
        visible: seeAll.visible
        x: seeAll.x - Style.space(6); y: seeAll.y - Style.space(6)
        width: seeAll.width + Style.space(12); height: seeAll.height + Style.space(12)
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: list.headerActivated(cell.index)
      }
    }

    // ---- shelf: one row of artwork, scrolled sideways ----------------------
    ListView {
      id: shelfView
      visible: cell.isShelf
      width: parent.width
      height: cell.isShelf ? Style.space(124) + Style.space(50) : 0
      orientation: ListView.Horizontal
      spacing: Style.space(12)
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      model: cell.isShelf ? cell.modelData.items : []
      leftMargin: Style.space(4)
      rightMargin: Style.space(4)
      delegate: Tile {
        required property var modelData
        item: modelData
      }
      NumberAnimation { id: shelfAnim; target: shelfView; property: "contentX"; duration: 380; easing.type: Easing.OutCubic }
      function go(dir) {
        const lo = shelfView.originX - shelfView.leftMargin
        const hi = shelfView.originX + Math.max(0, shelfView.contentWidth + shelfView.rightMargin - shelfView.width)
        shelfAnim.to = Math.max(lo, Math.min(hi, shelfView.contentX + dir * shelfView.width * 0.8))
        shelfAnim.restart()
      }
    }
    HoverHandler { id: shelfHover; enabled: cell.isShelf }
    // ‹ › at the ends on hover, as on the Mac.
    Repeater {
      model: cell.isShelf ? [-1, 1] : []
      delegate: Rectangle {
        required property int modelData
        readonly property bool canGo: modelData < 0 ? !shelfView.atXBeginning : !shelfView.atXEnd
        visible: shelfHover.hovered && canGo
        width: Style.space(28); height: width; radius: width / 2
        x: modelData < 0 ? Style.space(2) : shelfView.width - width - Style.space(2)
        y: Style.space(124) / 2 - height / 2
        z: 5
        color: Util.alpha(SpinTheme.Palette.glass, 0.92)
        border.width: 1; border.color: SpinTheme.Palette.edge
        Glyph { anchors.centerIn: parent; name: parent.modelData < 0 ? "back" : "forward"; size: Style.space(14); color: SpinTheme.Palette.text }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: shelfView.go(parent.modelData)
        }
      }
    }

    // ---- grid: tiles wrapping to the width ----------------------------------
    Flow {
      id: gridFlow
      visible: cell.isGrid
      x: Style.space(4)
      width: parent.width - Style.space(8)
      spacing: Style.space(12)
      readonly property int cols: Math.max(2, Math.floor((width + spacing) / (Style.space(130) + spacing)))
      readonly property real tileSize: (width - spacing * (cols - 1)) / cols
      Repeater {
        model: cell.isGrid ? cell.modelData.items : []
        delegate: Tile {
          required property var modelData
          item: modelData
          size: gridFlow.tileSize
        }
      }
    }

    // ---- song row -----------------------------------------------------------
    Rectangle {
      visible: cell.isRow
      anchors.fill: parent
      radius: Style.space(8)
      color: cell.selected ? SpinTheme.Palette.selected
        : rowHover.hovered ? SpinTheme.Palette.fillHover : "transparent"
      Behavior on color { ColorAnimation { duration: 110 } }
    }

    HoverHandler { id: rowHover; enabled: cell.isRow }

    MouseArea {
      id: hover
      visible: cell.isRow
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: { list.cursor = cell.index; list.activated(cell.index) }
    }

    Row {
      id: rowContent
      visible: cell.isRow
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(10)

      // Cover, or on album pages the track number (a speaker while playing).
      Item {
        id: lead
        width: list.numbered ? Style.space(24) : Style.space(36)
        height: Style.space(36)
        anchors.verticalCenter: parent.verticalCenter
        SquareCover {
          visible: !list.numbered && !miniDisc.visible
          anchors.fill: parent
          source: cell.item ? (cell.item.thumb || "") : ""
          circle: !!cell.item && cell.item.kind === "artist"
          glyph: !cell.item ? Icons.note : cell.item.kind === "artist" ? Icons.artist : cell.item.kind === "album" ? Icons.album : Icons.note
          Rectangle {
            anchors.fill: parent; radius: Style.space(6)
            color: "#8c000000"
            visible: cell.loading
            LoadingRing { anchors.centerIn: parent; width: Style.space(20); lineWidth: Style.space(2) }
          }
        }
        // The playing song in the queue: its cover as a tiny CD that turns
        // while the music plays and rests where it is when paused.
        Item {
          id: miniDisc
          visible: !list.numbered && !cell.loading && (list.spinIndex >= 0 ? cell.index === list.spinIndex : list.spinNow && cell.now)
          anchors.fill: parent
          RoundCover {
            id: miniDiscArt
            anchors.fill: parent
            source: cell.item ? (cell.item.thumb || "") : ""
            foreground: SpinTheme.Palette.text
            fill: Util.alpha(SpinTheme.Palette.text, 0.1)
            RotationAnimator on rotation {
              from: miniDiscArt.rotation; to: miniDiscArt.rotation + 360
              duration: 4000; loops: Animation.Infinite
              running: miniDisc.visible && list.spinning
            }
          }
          // The hole and its clear ring, so it reads as a disc.
          Rectangle {
            anchors.centerIn: parent
            width: parent.width * 0.3; height: width; radius: width / 2
            color: "transparent"
            border.width: Math.max(1, width * 0.12)
            border.color: Util.alpha("white", 0.55)
            Rectangle {
              anchors.centerIn: parent
              width: parent.width * 0.42; height: width; radius: width / 2
              color: SpinTheme.Palette.glass
            }
          }
        }
        Text {
          visible: list.numbered && !cell.now && !cell.loading
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: cell.modelData.n ? String(cell.modelData.n) : ""
          textFormat: Text.PlainText
          color: SpinTheme.Palette.tertiary
          font.family: list.family
          font.pixelSize: Style.font.body
          font.features: { "tnum": 1 }
        }
        Glyph {
          visible: list.numbered && cell.now && !cell.loading
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          name: "volume-high"
          size: Style.space(15)
          color: SpinTheme.Palette.accent
        }
        LoadingRing {
          visible: list.numbered && cell.loading
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(16); lineWidth: Style.space(2)
        }
      }

      Column {
        anchors.verticalCenter: parent.verticalCenter
        width: rowContent.width - lead.width - rowContent.spacing * 2 - trailing.width
        spacing: Style.space(2)

        Row {
          width: parent.width
          spacing: Style.space(6)
          Glyph {
            id: nowMark
            visible: cell.now && !list.numbered
            anchors.verticalCenter: parent.verticalCenter
            name: "volume-high"
            size: Style.space(13)
            color: SpinTheme.Palette.accent
          }
          Text {
            width: parent.width - (nowMark.visible ? nowMark.width + parent.spacing : 0)
            text: cell.item ? cell.item.title : ""
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: cell.now ? SpinTheme.Palette.accent : list.fg
            font.family: list.family
            font.pixelSize: Style.font.body
            font.weight: cell.now ? Font.DemiBold : Font.Normal
          }
        }
        Text {
          width: parent.width
          text: (cell.item && cell.item.explicit ? "E  " : "") + cell.subtitle
          textFormat: Text.PlainText
          elide: Text.ElideRight
          visible: cell.subtitle !== ""
          color: SpinTheme.Palette.secondary
          font.family: list.family
          font.pixelSize: Style.font.caption
        }
      }

      Row {
        id: trailing
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        // Hover buttons: always laid out, shown on hover or on the cursor
        // row, so the title keeps its width and nothing jumps.
        Repeater {
          model: cell.hoverActions
          delegate: HitButton {
            id: actionButton
            required property var modelData
            anchors.verticalCenter: parent.verticalCenter
            minSize: Style.space(30)
            opacity: cell.showActions ? 1 : 0
            enabled: cell.showActions
            iconName: list.iconFor(modelData)
            iconText: iconName === "" ? modelData.icon : ""
            iconSize: Style.space(15)
            foreground: actionButton.hot ? SpinTheme.Palette.text : SpinTheme.Palette.secondary
            fontFamily: list.family
            tooltipText: modelData.tip
            onClicked: { list.cursor = cell.index; list.action(actionButton.modelData.name, cell.index) }
            Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
          }
        }

        // The heart's own slot, right beside the time: a liked song's heart
        // always shows here; an unliked one appears on hover.
        Item {
          width: Style.space(30)
          height: Style.space(30)
          anchors.verticalCenter: parent.verticalCenter
          visible: !!cell.likeAction
          HitButton {
            id: heartButton
            anchors.centerIn: parent
            minSize: Style.space(30)
            readonly property bool liked: !!(cell.likeAction && cell.likeAction.on)
            // A liked song's heart stays, but small and soft so long lists
            // stay calm; it brightens and grows on the row's hover.
            opacity: cell.showActions ? 1 : liked ? 0.45 : 0
            enabled: liked || cell.showActions
            iconName: liked ? "heart-fill" : "heart"
            iconSize: cell.showActions || heartButton.hot ? Style.space(15) : Style.space(12)
            foreground: liked || heartButton.hot ? SpinTheme.Palette.text : SpinTheme.Palette.secondary
            tooltipText: cell.likeAction ? cell.likeAction.tip : ""
            onClicked: { if (!liked) rowSwirl.play(); else rowSwirl.drain(); list.cursor = cell.index; list.action("like", cell.index) }
            Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
          }
          HeartSwirl {
            id: rowSwirl
            anchors.centerIn: heartButton
            size: Style.space(15)
            tint: list.swirlTint
            onRunningChanged: cell.rowSwirlRunning = running
          }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(40)
          horizontalAlignment: Text.AlignRight
          text: cell.item && cell.item.duration ? Model.fmtTime(cell.item.duration) : ""
          textFormat: Text.PlainText
          color: SpinTheme.Palette.tertiary
          font.family: list.family
          font.pixelSize: Style.font.caption
          font.features: { "tnum": 1 }
        }
      }
    }
  }
}
