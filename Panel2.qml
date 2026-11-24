import QtQuick
import QtQuick.Window as QtWindow
import "theme2" as SpinTheme
import qs.Ui
import QtQuick.Effects
import Quickshell
import qs.Commons
import "lib/Model.js" as Model
import "lib/Icons.js" as Icons
import "views2" as Views

// Spinbloom design 2 copy of Panel.qml: album-coloured backdrop, a compact
// now-playing header, segmented tabs; every highlight follows the album.
// The panel: now playing at the top, then Queue, Search, Library, Lyrics
// and History, and pages (album, artist, playlist) opened from any list.
// Everything works from the keyboard; the hint line says how.
Panel {
  id: root
  moduleName: "spinbloom"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var svc: null

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string family: "Inter"

  readonly property var tabs: [
    // Apple Music's order: Home first, then your Library, then what is
    // playing (Queue, Lyrics) and History.
    { key: "search", label: "Home" }, { key: "library", label: "Library" },
    { key: "queue", label: "Queue" }, { key: "lyrics", label: "Lyrics" },
    { key: "history", label: "History" }
  ]
  property string tab: "queue"
  property var pages: []
  readonly property var view: pages.length > 0 ? detailView
    : tab === "queue" ? queueView : tab === "search" ? searchView : tab === "library" ? libraryView : tab === "history" ? historyView : lyricsView
  property bool allKeys: false
  property string flash: ""
  // Settings replaces the panel body; the gear in BrandCorner and Esc are
  // the only ways in and out — no new key letter is spent on it.
  property bool settingsOpen: false
  readonly property var settingsPage: settingsView
  function toggleSettings() { root.settingsOpen = !root.settingsOpen }
  // Settings opened from the player's ••• menu: Back (the arrow or Esc)
  // returns to the player, in whatever size it was, not to the library.
  property bool returnToPlayer: false
  signal playerRequested()
  function closeSettings() {
    root.settingsOpen = false
    if (root.returnToPlayer) { root.returnToPlayer = false; root.playerRequested() }
  }

  onOpenedChanged: {
    if (svc) svc.panelOpen = opened
    if (!opened) { allKeys = false; settingsOpen = false; saveOpen = false; returnToPlayer = false; return }
    if (svc) svc.lastError = ""  // old news from while it was closed
    if (svc && !svc.hasTrack && tab === "queue") tab = "search"
    // With autostart off, opening the panel is what starts YouTube Music.
    if (svc && svc.bridgeUp && svc.engine.status === "stopped") svc.startEngine()
    Qt.callLater(function () {
      root.focusKeys()
      if (root.view && root.view.shown) root.view.shown()
    })
  }

  function focusKeys() { keys.forceActiveFocus() }

  function showTab(key) {
    returnToPlayer = false   // a tab chosen in the panel: stay in the panel
    pages = []
    tab = key
    Qt.callLater(function () {
      if (root.view.shown) root.view.shown()
      if (key === "search") searchView.focusInput()
      else root.focusKeys()
    })
  }

  function cycleTab(d) {
    var i = 0
    for (var k = 0; k < tabs.length; k++) if (tabs[k].key === tab) i = k
    showTab(tabs[(i + d + tabs.length) % tabs.length].key)
  }

  // Spinbloom: open Home with a search already run (from the mini player).
  function searchFor(q) {
    showTab("search")
    Qt.callLater(function () { searchView.setQuery(q) })
  }

  // Spinbloom: show a song highlighted in the queue (songs with no album page).
  function showInQueue(videoId) {
    queueView.focusId = videoId || ""
    showTab("queue")
  }

  function openPage(item, params) {
    if (!item || !item.browseId) return
    var p = { id: item.browseId, title: item.title || "", params: params || "", focus: item.focus || "" }
    pages = pages.concat([p])
    detailView.open(p)
    focusKeys()
  }

  function back() {
    if (pages.length === 0) { root.close(); return }
    var rest = pages.slice(0, -1)
    // A page the player opened (artist, album): backing out of the last
    // one returns to the player.
    if (rest.length === 0 && root.returnToPlayer) { root.returnToPlayer = false; root.playerRequested(); return }
    pages = rest
    if (rest.length) detailView.open(rest[rest.length - 1])
    focusKeys()
  }

  function say(text) { root.flash = text; flashTimer.restart() }
  Timer { id: flashTimer; interval: 2600; onTriggered: root.flash = "" }

  // Only the open panel shows an error (there is one panel per bar, and a
  // closed one would swallow it).
  Connections {
    target: root.svc
    function onLastErrorChanged() { if (root.opened && root.svc.lastError) { root.say(root.svc.lastError); root.svc.lastError = "" } }
  }

  // The bar matches panels by the widget that hosts them, not by this item.
  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function") return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  // ---- rows: what Enter and the row buttons do, the same everywhere

  function itemActions(row) {
    var it = row && row.item
    if (!it) return []
    if (it.videoId) return [
      root.likeAction(it),
      { name: "next", icon: Icons.playNext, tip: "Play next (e)" },
      { name: "queue", icon: Icons.plus, tip: "Add to queue (a)" },
      { name: "save", icon: Icons.savePlaylist, tip: "Save to playlist" },
      { name: "radio", icon: Icons.radio, tip: "Start radio (R)" }
    ]
    if (it.kind === "artist") return [{ name: "play", icon: Icons.shuffle, tip: "Shuffle this artist" }]
    if (it.playlistId) return [{ name: "play", icon: Icons.play, tip: "Play" }]
    return []
  }

  // The song just chosen shows at once, before YouTube Music has loaded it.
  readonly property bool loadingSong: !!(svc && svc.pendingId)
  readonly property string liveThumb: loadingSong ? String(svc.pendingItem.thumb || "")
    : svc && svc.hasTrack ? svc.thumb : ""

  // "Colour from album artwork" (Settings → Appearance).
  readonly property bool albumBackdrop: !svc || String(svc.setting("albumColors", true)) !== "false"
  // The like swirl's colour on song rows: the album's, as in the player.
  readonly property color swirlTint: albumBackdrop && albumColor.valid ? albumColor.vivid : SpinTheme.Palette.accent

  // A shelf or grid tile: play a song, open anything else.
  function activateTile(it) { if (it) root.activateRow({ item: it }, "") }

  function activateRow(row, contextList) {
    var it = row && row.item
    if (!it || !svc) return
    if (it.videoId) {
      var args = { videoId: it.videoId }
      if (contextList) args.playlistId = contextList
      else if (it.playlistId) args.playlistId = it.playlistId
      svc.markPending(it)
      svc.request("play", args, function (r) { if (r.ok) root.say("Playing " + it.title); else { svc.clearPending(); svc.report(r.error) } })
    } else if (it.browseId) {
      openPage(it)
    }
  }

  // The heart on a song row: like it (or remove the like) without playing it.
  function likeAction(it) {
    var liked = !!(svc && svc.likeOfId(it.videoId) === "LIKE")
    return { name: "like", icon: liked ? Icons.heart : Icons.heartOutline, on: liked,
             tip: liked ? "Remove from Liked music" : "Add to Liked music" }
  }
  function toggleRowLike(it) {
    if (!it || !it.videoId || !svc) return
    var liked = svc.likeOfId(it.videoId) === "LIKE"
    svc.setLikeFor(it.videoId, liked ? "INDIFFERENT" : "LIKE", function (r) {
      if (r.ok) root.say(liked ? "Removed from Liked music" : "Added to Liked music: " + (it.title || ""))
    })
  }

  function runAction(name, row) {
    var it = row && row.item
    if (!it || !svc) return
    if (name === "like") { root.toggleRowLike(it); return }
    if (name === "save") { root.openSave(it); return }
    if (name === "next" || name === "queue") {
      svc.enqueue(it, name === "next", function (r) {
        if (r.ok) root.say(name === "next" ? "Plays next: " + it.title : "Added to the queue: " + it.title)
        else svc.report(r.error)
      })
    } else if (name === "radio") {
      svc.radioFor(it)
      root.say("Radio from " + it.title)
    } else if (name === "play") {
      svc.markPending(it)
      svc.playItem(it, function (r) { if (r.ok) root.say("Playing " + it.title); else { svc.clearPending(); svc.report(r.error) } })
    }
  }

  // ---- keys

  // Save to playlist: the picker over the panel (same one as the player's).
  property bool saveOpen: false
  function openSave(it) {
    if (!it || !it.videoId) return
    savePicker.open(it)
    root.saveOpen = true
  }

  function onKey(event) {
    if (root.saveOpen && event.key === Qt.Key_Escape) { root.saveOpen = false; event.accepted = true; return }
    var t = event.text
    var k = event.key
    var inField = root.pages.length === 0 && root.tab === "search" && searchView.inputFocused
    if (k === Qt.Key_Escape) {
      if (root.allKeys) root.allKeys = false
      else if (root.settingsOpen) root.closeSettings()
      else root.back()
      event.accepted = true
      return
    }
    // Signing in: the keyboard may fall back here while Google's window is
    // open or hidden (saving). A stray key must not cancel it or start
    // another; the card's Cancel button is the way out.
    if (root.svc && root.svc.signingIn) {
      event.accepted = true
      return
    }
    if (root.settingsOpen) {
      if (k === Qt.Key_Tab || k === Qt.Key_Backtab) { settingsView.switchColumn(); event.accepted = true; return }
      if (k === Qt.Key_Down) { settingsView.move(1); event.accepted = true; return }
      if (k === Qt.Key_Up) { settingsView.move(-1); event.accepted = true; return }
      if (k === Qt.Key_Left) { settingsView.change(-1); event.accepted = true; return }
      if (k === Qt.Key_Right) { settingsView.change(1); event.accepted = true; return }
      if (k === Qt.Key_Return || k === Qt.Key_Enter) { settingsView.act(); event.accepted = true; return }
      event.accepted = true
      return
    }
    if (k === Qt.Key_Tab || k === Qt.Key_Backtab) {
      const current = keys.QtWindow.Window.window.activeFocusItem || keys
      const next = current.nextItemInFocusChain(!((event.modifiers & Qt.ShiftModifier) || k === Qt.Key_Backtab))
      if (next) next.forceActiveFocus(Qt.TabFocusReason)
      event.accepted = true
      return
    }
    if (inField) {
      if (k === Qt.Key_Up) { event.accepted = true }
      return
    }
    var v = root.view
    var cur = v && v.current ? v.current : null
    if (k === Qt.Key_Down || t === "j") { v.move(1); event.accepted = true; return }
    if (k === Qt.Key_Up || t === "k") { v.move(-1); event.accepted = true; return }
    if (k === Qt.Key_Left || t === "h") { if (root.pages.length) root.back(); else root.cycleTab(-1); event.accepted = true; return }
    if (k === Qt.Key_Right || t === "l") { if (!root.pages.length) root.cycleTab(1); event.accepted = true; return }
    if (k === Qt.Key_Return || k === Qt.Key_Enter) {
      if (svc.closed) svc.startEngine()
      else if (v === queueView) queueView.activate()
      else if (v === libraryView && !libraryView.signedIn) svc.signIn()
      else if (cur) root.activateRow(cur, v === detailView ? detailView.contextList() : "")
      event.accepted = true
      return
    }
    if (k === Qt.Key_Space) { svc.togglePlaying(); event.accepted = true; return }
    if (k === Qt.Key_Backspace) { root.back(); event.accepted = true; return }
    if (k === Qt.Key_Delete) { if (v === queueView) queueView.key("x"); event.accepted = true; return }
    if (!t) return
    if (v && v.key && v.key(t)) { event.accepted = true; return }
    var handled = true
    switch (t) {
      case "/": root.showTab("search"); break
      case "1": root.showTab("search"); break
      case "2": root.showTab("library"); break
      case "3": root.showTab("queue"); break
      case "4": root.showTab("lyrics"); break
      case "5": root.showTab("history"); break
      case "n": svc.next(); break
      case "p": svc.previous(); break
      case ",": svc.seekBy(-10); break
      case ".": svc.seekBy(10); break
      case "-": svc.nudgeVolume(-1); break
      case "=": case "+": svc.nudgeVolume(1); break
      case "m": svc.toggleMute(); break
      case "f": svc.toggleLike(); break
      case "d": svc.dislike(); break
      case "r": svc.cycleRepeat(); break
      case "s": svc.shuffle(); root.say("Queue shuffled"); break
      case "a": if (cur) root.runAction("queue", cur); break
      case "e": if (cur) root.runAction("next", cur); break
      case "R": if (cur && cur.item && cur.item.videoId) root.runAction("radio", cur); else if (svc.hasTrack) { svc.radioFor(svc.player); root.say("Radio from " + svc.title) } break
      case "g": root.openArtist(cur); break
      case "o": root.openAlbum(cur); break
      case "[": if (v === searchView) searchView.cycleFilter(-1); else if (v === libraryView) libraryView.cycleSection(-1); break
      case "]": if (v === searchView) searchView.cycleFilter(1); else if (v === libraryView) libraryView.cycleSection(1); break
      case "w": if (svc.gated) svc.signIn(); else svc.showWindow(); break
      case "W": svc.hideWindow(); break
      case "i": if (brand.showSignIn) svc.signIn(); else handled = false; break
      case "?": root.allKeys = !root.allKeys; break
      default: handled = false
    }
    event.accepted = handled
  }

  // g / o: the artist or album of the row under the cursor, else of the song.
  function openArtist(row) {
    var it = row && row.item && row.item.videoId ? row.item : (svc.hasTrack ? svc.player : null)
    var a = it && it.artists && it.artists.length && it.artists[0].id ? it.artists[0] : null
    if (a) openPage({ browseId: a.id, title: a.name })
  }
  function openAlbum(row) {
    var it = row && row.item && row.item.videoId ? row.item : (svc.hasTrack ? svc.player : null)
    if (it && it.album && it.album.id) openPage({ browseId: it.album.id, title: it.album.name })
  }


  // ---- album colour: drives theme2's accent for every design-2 view
  Binding {
    target: SpinTheme.Palette
    property: "accent"
    // Highlights are white, as Apple Music draws them; the album colour is
    // carried by the backdrop instead of the text.
    value: SpinTheme.Palette.text
  }

  // ---- surface

  Item { id: anchorDummy; visible: false }

  LibraryPopup2 {
    id: panel
    anchorItem: root.anchorItem || anchorDummy
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    // The album backdrop runs to the card's edge; the content keeps its own margin.
    padding: 1
    contentWidth: panel.fittedContentWidth(Style.space(560))
    // Gated or off, the card is all there is: no empty stage under it.
    contentHeight: root.svc && root.svc.gated && !root.settingsOpen
      ? panel.fittedContentHeight(hero.implicitHeight + gate.implicitHeight + Style.space(44))
      : root.svc && root.svc.closed && !root.settingsOpen
      ? panel.fittedContentHeight(hero.implicitHeight + offCard.implicitHeight + Style.space(52))
      : panel.cappedContentHeight(Style.space(660))

    // Blurred artwork behind everything, washed darker for legibility.
    Rectangle {
      id: backdropMask
      width: backdrop.width; height: backdrop.height
      radius: Math.max(Style.cornerRadius, Style.space(18)) - 1
      visible: false; layer.enabled: true; color: "white"
    }
    // Sampled inside the window: its canvas only paints while on screen.
    Views.AlbumColor { id: albumColor; source: root.liveThumb }

    Item {
      id: backdrop
      anchors.fill: parent
      clip: true
      layer.enabled: true
      layer.effect: MultiEffect { maskEnabled: true; maskSource: backdropMask }
      readonly property string artwork: root.liveThumb
      property int front: -1
      function update() {
        if (!artwork) { front = -1; return }
        const active = layers.itemAt(front)
        if (active && String(active.source) === artwork) return
        const incoming = layers.itemAt(front === 0 ? 1 : 0)
        if (!incoming) return
        incoming.source = artwork
        if (incoming.status === Image.Ready) front = incoming.index
      }
      onArtworkChanged: update()
      Component.onCompleted: Qt.callLater(update)
      // Spinbloom: without Hyprland blur the glass turns almost solid (GlassBlur).
      readonly property bool clear: !root.svc || !root.svc.glass || root.svc.glass.compositor
      Repeater {
        id: layers
        model: 2
        Image {
          required property int index
          anchors.fill: parent
          anchors.margins: -Style.space(60)
          sourceSize: Qt.size(64, 64)
          asynchronous: true
          fillMode: Image.PreserveAspectCrop
          // Settings sits on a plain, neutral glass (like System Settings);
          // the album colours fade back in when you leave it.
          opacity: index === backdrop.front && root.albumBackdrop && !root.settingsOpen ? 0.7 : 0
          visible: opacity > 0
          layer.enabled: visible
          layer.effect: MultiEffect { blurEnabled: true; blur: 1; blurMax: 64; saturation: 0.55; brightness: -0.08 }
          Behavior on opacity { NumberAnimation { duration: 450; easing.type: Easing.InOutQuad } }
          onStatusChanged: if (status === Image.Ready && String(source) === backdrop.artwork) backdrop.front = index
        }
      }
      Rectangle {
        anchors.fill: parent
        readonly property real pale: root.albumBackdrop ? Math.max(0, Math.min(1, (albumColor.brightness - 0.35) / 0.45)) : 0
        color: Util.alpha(SpinTheme.Palette.glass, backdrop.clear ? 0.62 + 0.25 * pale : 0.94)
      }
      Views.ThemeGlow {
        anchors.fill: parent
        opacity: root.albumBackdrop ? 0 : 1
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.InOutQuad } }
      }
    }
    // A plain Item, not a FocusScope: a scope hands focus back to the child
    // that had it, so the search field would keep the keys after Enter.
    // Keys the field does not take still bubble up to here.
    Item {
      id: keys
      anchors.fill: parent
      anchors.margins: Style.space(16)
      focus: true
      Keys.onPressed: function (event) { root.onKey(event) }

      // Compact now-playing header: the full controls live in the player
      // card, one click away (click the cover or the title).
      Item {
        id: hero
        objectName: "panelHero"
        visible: !root.settingsOpen
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.rightMargin: brand.width + Style.space(8)
        implicitHeight: Style.space(68)
        height: implicitHeight

        Rectangle {
          id: heroCoverMask
          width: heroCover.width; height: heroCover.height
          radius: Style.space(9); visible: false; layer.enabled: true; color: "white"
        }
        Rectangle {
          id: heroCoverBack
          width: Style.space(52); height: width
          anchors.left: parent.left
          anchors.top: parent.top
          radius: Style.space(9)
          color: SpinTheme.Palette.bubble
          layer.enabled: true
          layer.effect: MultiEffect { shadowEnabled: true; shadowOpacity: 0.35; shadowBlur: 0.5; shadowVerticalOffset: Style.space(3) }
          Image {
            id: heroCover
            anchors.fill: parent
            source: root.liveThumb
            sourceSize: Qt.size(128, 128)
            asynchronous: true; fillMode: Image.PreserveAspectCrop
            layer.enabled: true
            layer.effect: MultiEffect { maskEnabled: true; maskSource: heroCoverMask }
          }
          // The chosen song is loading: a dark veil and a turning ring.
          Rectangle {
            anchors.fill: parent; radius: parent.radius
            color: "#80000000"
            visible: root.loadingSong
            Views.LoadingRing { anchors.centerIn: parent; width: Style.space(22); lineWidth: Style.space(2.2) }
          }
          Text {
            anchors.centerIn: parent
            visible: heroCover.status !== Image.Ready
            text: Icons.note
            color: SpinTheme.Palette.tertiary
            font.family: "JetBrainsMono Nerd Font"; font.pixelSize: Style.space(22)
          }
        }
        Column {
          anchors.left: heroCoverBack.right
          anchors.leftMargin: Style.space(12)
          anchors.right: heroControls.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: heroCoverBack.verticalCenter
          spacing: Style.space(2)
          Text {
            width: parent.width
            text: root.loadingSong ? (root.svc.pendingItem.title || "") : root.svc && root.svc.hasTrack ? root.svc.title : "Nothing playing"
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: SpinTheme.Palette.text
            font.family: root.family; font.pixelSize: Style.font.title; font.weight: Font.Bold
          }
          Text {
            width: parent.width
            text: root.loadingSong ? (root.svc.pendingItem.artists || []).map(e => e.name || "").filter(Boolean).join(", ")
              : root.svc && root.svc.hasTrack ? root.svc.artist : "Search for something to play"
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: SpinTheme.Palette.secondary
            font.family: root.family; font.pixelSize: Style.font.body
          }
        }
        MouseArea {
          anchors.left: parent.left
          anchors.right: heroControls.left
          anchors.top: parent.top; anchors.bottom: heroCoverBack.bottom
          cursorShape: Qt.PointingHandCursor
          onClicked: if (root.hostWidget) { root.close(); Qt.callLater(function() { root.hostWidget.open() }) }
        }
        // Previous · play/pause · next, as in Apple Music's top bar.
        Row {
          id: heroControls
          anchors.right: parent.right
          anchors.verticalCenter: heroCoverBack.verticalCenter
          spacing: Style.space(2)
          Views.HitButton {
            anchors.verticalCenter: parent.verticalCenter
            minSize: Style.space(36)
            iconName: "previous"
            iconSize: Style.space(18)
            foreground: SpinTheme.Palette.text
            tooltipText: "Previous"
            enabled: !!(root.svc && root.svc.hasTrack)
            onClicked: if (root.svc) root.svc.previous()
          }
          Views.HitButton {
            id: heroPlay
            anchors.verticalCenter: parent.verticalCenter
            minSize: Style.space(42)
            iconName: root.loadingSong || (root.svc && root.svc.isPlaying) ? "pause" : "play"
            iconSize: Style.space(24)
            foreground: SpinTheme.Palette.text
            tooltipText: root.svc && root.svc.isPlaying ? "Pause" : "Play"
            enabled: !!(root.svc && root.svc.hasTrack)
            onClicked: if (root.svc) root.svc.togglePlaying()
          }
          Views.HitButton {
            anchors.verticalCenter: parent.verticalCenter
            minSize: Style.space(36)
            iconName: "next"
            iconSize: Style.space(18)
            foreground: SpinTheme.Palette.text
            tooltipText: "Next"
            enabled: !!(root.svc && root.svc.hasTrack)
            onClicked: if (root.svc) root.svc.next()
          }
        }

        // A thin progress line under the header; click or drag to seek.
        Item {
          id: heroProgress
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: Style.space(10)
          visible: !!(root.svc && root.svc.hasTrack)
          readonly property real duration: root.svc ? Math.max(1, root.svc.duration) : 1
          property bool dragging: false
          property real dragValue: 0
          readonly property real fraction: Math.max(0, Math.min(1, (dragging ? dragValue : (root.svc ? root.svc.position : 0)) / duration))
          readonly property bool hot: progressHit.containsMouse || dragging
          Rectangle {
            anchors.left: parent.left; anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: heroProgress.hot ? Style.space(6) : Style.space(3)
            radius: height / 2
            color: Util.alpha(SpinTheme.Palette.text, 0.18)
            Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Rectangle {
              height: parent.height; radius: height / 2
              width: Math.max(height, parent.width * heroProgress.fraction)
              color: SpinTheme.Palette.text
            }
          }
          MouseArea {
            id: progressHit
            anchors.fill: parent
            anchors.topMargin: -Style.space(4); anchors.bottomMargin: -Style.space(4)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            enabled: !!(root.svc && root.svc.duration > 0 && !root.svc.isAd)
            function valueAt(x) { return Math.max(0, Math.min(1, x / Math.max(1, width))) * heroProgress.duration }
            onPressed: mouse => { heroProgress.dragging = true; heroProgress.dragValue = valueAt(mouse.x) }
            onPositionChanged: mouse => { if (heroProgress.dragging) heroProgress.dragValue = valueAt(mouse.x) }
            onReleased: { heroProgress.dragging = false; if (root.svc) root.svc.seek(heroProgress.dragValue) }
          }
        }
      }

      // Spinbloom's name and the power button, top right: far from play.
      Views.BrandCorner {
        id: brand
        objectName: "panelBrand"
        // Level with the play controls (Settings: level with its title row).
        y: root.settingsOpen ? 0 : hero.y + heroControls.y + heroControls.height / 2 - height / 2
        anchors.right: parent.right
        // The power button's box reaches into the card's padding, like "?".
        anchors.rightMargin: -Math.min(Style.space(8), Math.max(0, Style.spacing.popupPadding - Style.space(2)))
        svc: root.svc
        foreground: root.fg
        fontFamily: root.family
        settingsOpen: root.settingsOpen
        onGearClicked: root.toggleSettings()
      }

      Views.SignInCard {
        id: gate
        anchors.top: hero.bottom
        anchors.topMargin: Style.space(12)
        width: parent.width
        visible: root.svc ? root.svc.gated && !root.settingsOpen : false
        svc: root.svc
        bar: root.bar
      }

      Views.OffCard {
        id: offCard
        objectName: "offCard"
        anchors.top: hero.bottom
        anchors.topMargin: Style.space(18)
        width: parent.width
        visible: keys.off && !root.settingsOpen
        svc: root.svc
        bar: root.bar
      }

      // While YouTube Music waits on Google (cookies, sign-in) there is one
      // thing to do: the card above. Nothing below it would work yet.
      readonly property bool gated: root.svc ? root.svc.gated : false
      // Off, the same: only the way back on.
      readonly property bool off: root.svc ? root.svc.closed === true : false
      readonly property bool blocked: gated || off

      // Segmented control: one capsule, the open tab lifted out in the
      // album colour.
      Rectangle {
        id: tabRow
        objectName: "panelTabs"
        visible: !keys.blocked && !root.settingsOpen
        anchors.top: gate.visible ? gate.bottom : hero.bottom
        anchors.topMargin: Style.space(14)
        anchors.left: parent.left
        anchors.right: parent.right
        height: Style.space(34)
        radius: height / 2
        color: SpinTheme.Palette.fill
        readonly property real segment: (width - Style.space(6)) / root.tabs.length
        readonly property int current: {
          if (root.pages.length > 0) return -1
          for (var i = 0; i < root.tabs.length; i++) if (root.tabs[i].key === root.tab) return i
          return -1
        }
        Rectangle {
          visible: tabRow.current >= 0
          x: Style.space(3) + tabRow.segment * Math.max(0, tabRow.current)
          y: Style.space(3)
          width: tabRow.segment
          height: tabRow.height - Style.space(6)
          radius: height / 2
          // The selected tab's pill: white in a light theme (Apple's
          // segmented control), bright in a dark one.
          color: SpinTheme.Palette.light ? "white" : SpinTheme.Palette.accent
          Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
          Behavior on color { ColorAnimation { duration: 300 } }
        }
        Repeater {
          model: root.tabs
          delegate: Item {
            required property var modelData
            required property int index
            readonly property bool current: index === tabRow.current
            x: Style.space(3) + tabRow.segment * index
            y: Style.space(3)
            width: tabRow.segment
            height: tabRow.height - Style.space(6)
            Accessible.role: Accessible.PageTab
            Accessible.name: modelData.label
            Rectangle {
              anchors.fill: parent
              radius: height / 2
              color: !parent.current && tabHit.containsMouse ? SpinTheme.Palette.fillHover : "transparent"
            }
            Text {
              anchors.centerIn: parent
              text: modelData.label
              textFormat: Text.PlainText
              color: parent.current && !SpinTheme.Palette.light ? SpinTheme.Palette.onAccent : SpinTheme.Palette.text
              font.family: root.family
              font.pixelSize: Style.font.caption
              font.weight: parent.current ? Font.DemiBold : Font.Normal
            }
            MouseArea {
              id: tabHit
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.showTab(modelData.key)
            }
          }
        }
      }

      // Settings takes it all, from the top row down: its "‹ Settings" back
      // row sits level with the brand corner, which stays (gear, power).
      Item {
        id: stage
        visible: root.settingsOpen || !keys.blocked
        anchors.top: root.settingsOpen ? parent.top : tabRow.bottom
        anchors.topMargin: root.settingsOpen ? 0 : Style.space(10)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: footer.top
        anchors.bottomMargin: Style.space(8)

        Views.QueueView { id: queueView; anchors.fill: parent; visible: !root.settingsOpen && !root.allKeys && root.view === queueView; active: root.opened && visible; svc: root.svc; bar: root.bar; panel: root }
        Views.SearchView { id: searchView; anchors.fill: parent; visible: !root.settingsOpen && !root.allKeys && root.view === searchView; active: root.opened && visible; svc: root.svc; bar: root.bar; panel: root }
        Views.LibraryView { id: libraryView; anchors.fill: parent; visible: !root.settingsOpen && !root.allKeys && root.view === libraryView; active: root.opened && visible; svc: root.svc; bar: root.bar; panel: root }
        Views.LyricsView { id: lyricsView; anchors.fill: parent; visible: !root.settingsOpen && !root.allKeys && root.view === lyricsView; active: root.opened && visible; svc: root.svc; bar: root.bar; panel: root }
        Views.HistoryView { id: historyView; anchors.fill: parent; visible: !root.settingsOpen && !root.allKeys && root.view === historyView; active: root.opened && visible; svc: root.svc; bar: root.bar; panel: root }
        Views.DetailView { id: detailView; anchors.fill: parent; visible: !root.settingsOpen && !root.allKeys && root.view === detailView; svc: root.svc; bar: root.bar; panel: root }

        Views.SettingsView {
          id: settingsView
          objectName: "settingsView"
          anchors.fill: parent
          visible: root.settingsOpen
          svc: root.svc
          fg: root.fg
          family: root.family
          onBackRequested: root.closeSettings()
          onShowAllKeys: { root.settingsOpen = false; root.allKeys = true }
        }

        // Every key, on "?".
        Rectangle {
          anchors.fill: parent
          visible: root.allKeys
          clip: true
          color: SpinTheme.Palette.fill
          radius: Style.space(12)
          Text {
            id: keysTitle
            x: Style.space(16); y: Style.space(14)
            text: "Keyboard Shortcuts"
            textFormat: Text.PlainText
            color: SpinTheme.Palette.text
            font.family: root.family
            font.pixelSize: Style.font.title
            font.weight: Font.Bold
          }
          Flow {
            anchors.top: keysTitle.bottom
            anchors.topMargin: Style.space(14)
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: Style.space(16)
            anchors.rightMargin: Style.space(16)
            spacing: Style.space(12)
            Repeater {
              model: Model.ALL_KEY_HINTS
              delegate: Views.KeyHint { required property var modelData; keys: modelData[0]; label: modelData[1]; bar: root.bar; width: (parent.width - Style.space(12)) / 2 }
            }
          }
        }
      }

      Item {
        id: footer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Style.space(32)
        HoverHandler { id: footHover }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - allKeysButton.width - Style.space(4)
          visible: root.flash !== ""
          text: root.flash
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: SpinTheme.Palette.accent
          font.family: root.family
          font.pixelSize: Style.font.caption
        }

        Row {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - (root.settingsOpen ? 0 : allKeysButton.width + Style.space(4))
          clip: true
          visible: false
          spacing: Style.space(12)
          Repeater {
            model: Model.footerHints(root.view ? root.view.hints : null,
                                     !!(root.svc && root.svc.hasTrack && !root.svc.isAd && root.svc.signedIn),
                                     root.pages.length === 0 && root.view === searchView && searchView.inputFocused)
            delegate: Views.KeyHint { required property var modelData; keys: modelData[0]; label: modelData[1]; bar: root.bar }
          }
        }

        // Settings has its own, fixed hints: movement, not song controls.
        Row {
          anchors.verticalCenter: parent.verticalCenter
          visible: false
          spacing: Style.space(12)
          Repeater {
            model: [["↑↓", "move"], ["←→", "change"], ["Tab", "sections"], ["Esc", "back"]]
            delegate: Views.KeyHint { required property var modelData; keys: modelData[0]; label: modelData[1]; bar: root.bar }
          }
        }

        // Every key is one "?" away: typed, or clicked here.
        Views.HitButton {
          id: allKeysButton
          anchors.right: parent.right
          // "all keys" lines up with the edge: the box reaches into the card's
          // padding, never past it.
          anchors.rightMargin: -Math.min(Style.space(8), Math.max(0, Style.spacing.popupPadding - Style.space(2)))
          anchors.verticalCenter: parent.verticalCenter
          // Sized for the longer label: "close" does not shrink the box.
          width: Style.space(28)
          minSize: Style.space(28)
          text: root.allKeys ? "×" : "?"
          tooltipText: root.allKeys ? "Close keyboard shortcuts" : "Keyboard shortcuts"
          visible: !keys.blocked && !root.settingsOpen
          foreground: root.fg
          onClicked: root.allKeys = !root.allKeys
          // Out of sight until the pointer comes near the panel's foot (or
          // the shortcuts are open); typing "?" still works any time.
          opacity: footHover.hovered || root.allKeys || hot ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        }
        Views.KeyHint { id: allKeysSizer; visible: false; keys: "?"; label: "all keys"; bar: root.bar }
      }
    }

    // ---- save to playlist ---------------------------------------------------
    Rectangle {
      anchors.fill: parent
      z: 50
      radius: Math.max(Style.cornerRadius, Style.space(18)) - 1
      color: Util.alpha("black", root.saveOpen ? 0.45 : 0)
      Behavior on color { ColorAnimation { duration: 200 } }
      visible: root.saveOpen || saveCard.opacity > 0.01
      MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onClicked: root.saveOpen = false; onWheel: event => { event.accepted = true } }
      Rectangle {
        id: saveCard
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: root.saveOpen ? 0 : Style.space(16)
        Behavior on anchors.verticalCenterOffset { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
        width: Math.min(parent.width - Style.space(48), Style.space(400))
        height: savePicker.implicitHeight + Style.space(32)
        radius: Style.space(18)
        color: Util.alpha(SpinTheme.Palette.glass, 0.98)
        border.width: 1
        border.color: Util.alpha(SpinTheme.Palette.text, 0.12)
        opacity: root.saveOpen ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: event => { event.accepted = true } }
        Views.SaveList {
          id: savePicker
          x: Style.space(14); y: Style.space(16)
          width: parent.width - Style.space(28)
          svc: root.svc
          ink: SpinTheme.Palette.text
          inkSoft: Util.alpha(SpinTheme.Palette.text, 0.72)
          family: root.family
          maxListHeight: Style.space(360)
          onDone: function (message) { root.saveOpen = false; root.say(message) }
        }
      }
    }
  }
}
