import QtQuick
import "theme2" as SpinTheme
import QtQuick.Effects
import Quickshell
import qs.Ui
import qs.Commons
import qs.Commons as Commons
import "lib/Icons.js" as Icons
import "lib/Model.js" as Model
import "lib/CoverSelection.js" as CoverSelection
import "views2" as Views2

// Spinbloom design 2 of the compact player ("New" in the Design setting).
// The classic design lives on, unchanged, in MiniPlayer.qml.
//
// One album-coloured surface: the blurred artwork fills the whole card and
// the controls sit directly on it. Cover Flow carousel with tilted, darkened
// neighbours; bold title, quiet artist; bare transport symbols; a progress
// line that thickens under the pointer with elapsed / -remaining; a volume
// slider; and Lyrics · Output · Queue · Search along the bottom.
Item {
  id: root
  property var bar: null
  property var svc: null
  property var anchorItem: null
  property bool opened: false
  readonly property bool popoutSwitchClosing: popup.popoutSwitchClosing
  readonly property bool hasTrack: !!(svc && svc.hasTrack)
  readonly property string family: "Inter"
  // The "stage": with album colours on, the mini player is always the rich,
  // darkened album backdrop with white controls (Apple Music's Now Playing),
  // even under a light desktop theme. With album colours off it follows the
  // theme completely (light theme: light glass, dark icons).
  readonly property bool stage: albumBackdrop && SpinTheme.Palette.light
  // Light theme with album colours off: white controls on glass instead of
  // dark grey ones. lightLook "white" = milky white glass with a soft smoke
  // toward the controls; "smoke" = a smoky tinted glass.
  // (Now every theme, dark or light: the blend look whenever album colours are off.)
  readonly property bool paleGlass: !albumBackdrop
  // "blend": the theme's main colour as milky glass over the artwork, turning
  // to smoke only behind the title and controls, so they stay readable.
  property string lightLook: "blend"
  readonly property bool blend: paleGlass && lightLook === "blend"
  readonly property bool milky: paleGlass && (lightLook === "white" || blend)
  readonly property color glassC: stage ? "#2b2c34" : paleGlass ? (milky ? Util.alpha(Commons.Color.popups.background, 1) : "#3a3b44") : SpinTheme.Palette.glass
  // The darkening toward the controls: never white (milky glass uses smoke).
  // The smoke is the theme's own main colour, darkened (keeps its hue):
  // a dark theme's colour is used almost as it is, a light one is deepened.
  readonly property color washC: milky ? Qt.tint(Util.alpha(Commons.Color.popups.background, 1), Qt.rgba(0, 0, 0, SpinTheme.Palette.light ? 0.70 : 0.20)) : glassC
  readonly property color ink: stage || paleGlass ? "white" : Commons.Color.popups.text
  // Secondary text (artist, times, badge) is see-through white; over a light
  // theme's pale glass that reads as grey, so it is kept more solid there.
  readonly property bool paleWhite: milky && SpinTheme.Palette.light
  readonly property color inkSoft: Util.alpha(ink, paleWhite ? 0.90 : 0.62)
  readonly property color inkFaint: Util.alpha(ink, paleWhite ? 0.78 : 0.40)
  // Apple Music's rule: the album colour lives in the blurred backdrop; text,
  // progress and controls stay white so they never sink into a same-hue
  // background. (albumColor still feeds the backdrop's brightness wash.)

  property var covers: []
  property int browseIndex: -1
  property bool queueLoading: false
  property bool selectingCover: false
  property string browseError: ""
  readonly property var preview: browseIndex >= 0 && browseIndex < covers.length ? covers[browseIndex] : null
  readonly property bool previewing: !!(preview && svc && preview.item.videoId !== svc.videoId)

  signal libraryRequested(string tab)
  signal classicRequested()
  // Open an album or artist page in the full player (BarWidget handles it).
  signal pageRequested(var item)

  // ---- first launch -------------------------------------------------------
  // Before sign-in: a welcome with a Sign in button. Signed in with nothing
  // played yet: "Pick something to play" with a search box and six of the
  // account's mixes and playlists. Both sit on the player's own drifting
  // violet / teal gradient, so it never looks empty on any desktop theme.
  // `welcomePreview` ("signin" | "pick") shows them for a look (IPC
  // previewWelcome), without signing out.
  property string welcomePreview: ""
  readonly property string welcomeMode: welcomePreview !== "" ? welcomePreview
    : !svc ? ""
    : (svc.gated || (svc.ready && !svc.signedIn)) ? "signin"
    : (svc.ready && svc.signedIn && !hasTrack && !loadingSong) ? "pick" : ""
  signal searchRequested(string query)
  property var starters: []
  function loadStarters() {
    if (!svc || starters.length) return
    svc.request("home", {}, function (r) {
      if (!r.ok || !r.data) return
      const lists = [], songs = []
      for (const sec of (r.data.sections || []))
        for (const it of (sec.items || [])) {
          if (!it) continue
          if (it.videoId) songs.push(it)
          else if (it.playlistId || it.browseId) lists.push(it)
        }
      root.starters = lists.concat(songs).slice(0, 6)
    })
  }
  onWelcomeModeChanged: if (welcomeMode === "pick" && opened) loadStarters()
  function startTile(it) {
    if (!svc || !it) return
    if (it.videoId) { svc.markPending(it); svc.playItem(it) }
    else if (it.playlistId || it.kind === "artist") svc.playItem(it)
    else if (it.browseId) pageRequested({ browseId: it.browseId, title: it.title || "" })
    if (welcomePreview !== "") welcomePreview = ""
  }

  // ---- ••• menu ----------------------------------------------------------
  property bool moreOpen: false
  property Item moreAnchor: null
  property string notice: ""
  Timer { id: noticeTimer; interval: 2600; onTriggered: root.notice = "" }
  function say(text) { notice = text; noticeTimer.restart() }
  readonly property var albumRef: hasTrack && svc.player && svc.player.album && svc.player.album.id ? svc.player.album : null
  readonly property var artistRef: {
    if (!hasTrack || !svc.player || !svc.player.artists) return null
    const a = svc.player.artists.find(e => e && e.id)
    return a || null
  }
  readonly property var moreItems: [
    { key: "radio", icon: "radio", label: "Start radio from this song", on: true },
    { key: "save", icon: "playlist-add", label: "Save to playlist…", on: !!(svc && svc.signedIn) },
    { key: "sleep", icon: "sleep", label: svc && svc.sleepMode !== "off" ? "Sleep timer: " + sleepShort : "Sleep timer…", on: true },
    { key: "album", icon: "album", label: "Go to album", on: !!albumRef },
    { key: "artist", icon: "artist", label: "Go to artist", on: !!artistRef },
    { key: "dislike", icon: "thumb-down", label: svc && svc.like === "DISLIKE" ? "Undo \u201cNot for me\u201d" : "Not for me", on: !!(svc && svc.signedIn) },
    { key: "link", icon: "link", label: "Copy song link", on: true },
    { key: "settings", icon: "gear", label: "Settings", on: true }
  ]
  function openMore(anchor) {
    if (!hasTrack) return
    moreAnchor = anchor
    moreOpen = !moreOpen
  }
  // Test hook (IPC showMore): open the ••• menu as a click would.
  function testOutput() { openOutputPicker() }
  function testWelcome(mode) { welcomePreview = mode === "signin" || mode === "pick" ? mode : ""; if (welcomePreview === "pick") loadStarters() }
  function testMore() { openMore(dialMore) }
  // ---- title and artist links ------------------------------------------
  // The song the title block describes, with its album and artist links:
  // the browsed or chosen song, else the one playing. None mid-landing.
  readonly property var linkSong: landingHold ? null
    : shownItem ? shownItem
    : hasTrack && svc.player ? svc.player : null
  readonly property var linkArtists: linkSong && linkSong.artists ? linkSong.artists.filter(a => a && a.name) : []
  // Title → the song's album, highlighted on it; with no album, the song
  // highlighted in the full player's queue. Never a pop-up.
  function openTitle() {
    if (!linkSong || !linkSong.videoId) return
    const album = linkSong.album
    if (album && album.id) pageRequested({ browseId: album.id, title: album.name || "", focus: linkSong.videoId })
    else pageRequested({ queueFocus: linkSong.videoId })
  }
  // Test hooks (IPC linkTitle / linkArtist): act as a click on them.
  function testTitle() { openTitle() }
  function testArtist() { openArtist(linkArtists[0]) }
  function openArtist(a) {
    if (a && a.id) pageRequested({ browseId: a.id, title: a.name || "" })
  }

  // The like swirl (HeartSwirl): started at the click, so it shows even
  // while the song is paused; a like from a key starts it when it arrives.
  signal swirlRequested()
  property real swirlAt: 0
  readonly property color swirlTint: albumBackdrop && albumColor.valid ? albumColor.vivid : ink
  function likeSwirl() { swirlAt = Date.now(); swirlRequested() }
  signal drainRequested()
  function unlikeSwirl() { swirlAt = Date.now(); drainRequested() }
  // Test hook (IPC testSwirl): open the player, then swirl a moment later.
  Timer { id: swirlTest; interval: 1500; onTriggered: root.likeSwirl() }
  function testSwirl() { open(); swirlTest.restart() }
  Timer { id: drainTest; interval: 1500; onTriggered: root.unlikeSwirl() }
  function testDrain() { open(); drainTest.restart() }
  Timer { id: sleepTest; interval: 1500; onTriggered: { root.sleepNow = Date.now(); root.sleepOpen = true } }
  function testSleep() { open(); sleepTest.restart() }
  Connections {
    target: root.svc
    ignoreUnknownSignals: true
    function onLikeChanged() {
      if (!root.opened || Date.now() - root.swirlAt <= 4000) return
      if (root.svc.like === "LIKE") root.likeSwirl(); else root.unlikeSwirl()
    }
  }

  function moreAction(key) {
    moreOpen = false
    if (key === "settings") { libraryRequested("settings"); return }
    if (!svc || !hasTrack) return
    if (key === "save") { openSavePicker(); return }
    if (key === "sleep") { outputOpen = false; saveOpen = false; sleepNow = Date.now(); sleepOpen = true; return }
    if (key === "radio") { svc.radioFor(svc.player); say("Starting radio from this song") }
    else if (key === "album" && albumRef) pageRequested({ browseId: albumRef.id, title: albumRef.name || "" })
    else if (key === "artist" && artistRef) pageRequested({ browseId: artistRef.id, title: artistRef.name || "" })
    else if (key === "dislike") {
      const undo = svc.like === "DISLIKE"
      svc.dislike()   // the song's id is taken now, before the skip below
      // Like the YouTube Music app: a song marked "Not for me" is skipped.
      if (!undo) Qt.callLater(function() { if (root.svc) root.svc.next() })
      say(undo ? "Removed \u201cNot for me\u201d" : "Got it. Skipping to the next song.")
    }
    else if (key === "link") {
      Quickshell.execDetached(["wl-copy", "https://music.youtube.com/watch?v=" + svc.videoId])
      say("Link copied")
    }
  }

  // Artwork style: "flow" (tilted neighbours, the original) or "dial" (one
  // cover, a faint wheel of the queue peeking below). BarWidget feeds and
  // stores it; right-click the artwork to swap.
  property string artworkStyle: "dial"
  signal artworkStyleRequested(string style)
  readonly property bool dial: artworkStyle === "dial" || compact
  // Player size (Settings → Appearance, or the shrink/expand button):
  // "full", "compact" (same width, about half the height) or "small"
  // (narrower too). Compact keeps the cover, the CD wheel (unless
  // compactWheel is off), title and artist, the heart and •••, a thin
  // progress line and Previous · Play · Next.
  property string playerSize: "full"
  property bool compactWheel: true
  // Which compact the shrink button goes to.
  property string compactKind: "compact"
  signal playerSizeRequested(string size)
  readonly property bool compact: playerSize === "compact" || playerSize === "small"
  readonly property bool small: playerSize === "small"
  readonly property bool showWheel: !compact || compactWheel
  // Scale of the cover and wheel against the full player.
  readonly property real k: small ? 0.62 : compact ? 0.78 : 1
  readonly property bool playing: !!(svc && svc.isPlaying)
  // Apple Music: the cover settles back a little while paused.
  readonly property real pauseScale: hasTrack && !playing && !loadingSong ? 0.86 : 1

  // ---- logic shared with the classic player ------------------------------
  function sharpCover(value) {
    var url = String(value || "")
    if (url.indexOf("//") === 0) url = "https:" + url
    if (/^https:\/\/[^/]*(googleusercontent\.com|ggpht\.com)\//.test(url)) {
      const pixels = Math.max(1024, Math.ceil(Style.space(440) * Screen.devicePixelRatio))
      if (/=w\d+-h\d+/.test(url)) return url.replace(/=w\d+-h\d+/, "=w" + pixels + "-h" + pixels)
      if (/=s\d+/.test(url)) return url.replace(/=s\d+/, "=s" + pixels)
    }
    return url
  }
  function loadQueue() {
    if (!svc || queueLoading || !opened) return
    queueLoading = true
    svc.request("queue", {}, function(r) {
      queueLoading = false
      if (!r.ok || !r.data) { browseError = "Queue unavailable"; return }
      lastQueue = r.data
      applyQueue(r.data)
    })
  }
  // A new playlist or radio that starts at its first song: the songs played
  // before it (up to 50, newest next to the playing one) sit on the left of
  // the wheel, so scrolling left walks back through history ("earlier" discs,
  // not part of the queue; picking one plays it the normal way). They stay
  // for as long as this queue does, so the wheel never jumps.
  property var lastQueue: null
  property var earlierRows: []
  property string earlierKey: ""
  property bool earlierLate: false
  Timer {
    id: earlierApply; interval: 400
    onTriggered: {
      if (root.flyWhenLoaded !== "" || dialArt.holding || root.selectingCover) { restart(); return }
      if (root.lastQueue) root.applyQueue(root.lastQueue)
    }
  }
  function applyQueue(data) {
      // Only a disc the listener is browsing (not the one playing) is kept
      // where it was across a reload.
      const keep = previewing ? preview.item.videoId : ""
      const now = loadingSong ? pendingId : (svc.videoId || "")
      const queued = Model.queueRows(data).filter(row => !!row.item)
      const first = queued.find(row => !row.automix)
      const key = first ? first.item.videoId : ""
      // Decided once the playing song is in the new queue (a new radio's list
      // can arrive while the old song is still on: asked again next load).
      if (key !== earlierKey && queued.some(row => row.item.videoId === now)) {
        earlierKey = key
        earlierRows = []
        if (key !== "" && now === key) {
          earlierLate = false
          svc.recentBefore(queued.map(row => row.item.videoId).concat([now]), 50, function (list) {
            if (root.earlierKey !== key || !list.length) return
            root.earlierRows = list.map(it => ({ item: it, queueIndex: -1, earlier: true }))
            if (root.earlierLate) earlierApply.restart()
          })
          earlierLate = true   // an answer from here on comes back later
        }
      }
      const rows = earlierRows.concat(queued)
      // Same queue as before: keep the list, so the wheel and covers are not
      // rebuilt (that would restart their pictures mid-animation).
      const sig = list => list.map(row => [row.item.videoId, row.item.thumb, row.automix ? 1 : 0, row.queueIndex].join("\u0001")).join("\u0002")
      if (sig(rows) !== sig(covers)) covers = rows
      // The disc that is really playing: matched by the song, not only by
      // the queue's index. A new queue (radio, a playlist) can arrive before
      // YouTube Music has moved its index to the song it is playing; going
      // by the index alone parked the wheel on the old song and showed it
      // as if it were being browsed.
      const atIndex = covers.findIndex(row => !row.automix && !row.earlier && row.queueIndex === data.index)
      let playing = atIndex >= 0 && covers[atIndex].item.videoId === now ? atIndex : covers.findIndex(row => row.item.videoId === now)
      if (playing < 0 && now === "") playing = atIndex
      const remembered = keep ? covers.findIndex(row => row.item.videoId === keep) : -1
      browseIndex = remembered >= 0 ? remembered : playing
      browseError = ""
      flyIfLoaded()
  }
  function browse(delta) {
    if (!covers.length) { loadQueue(); return }
    browseIndex = Math.max(0, Math.min(covers.length - 1, browseIndex + delta))
  }
  function playPreview() {
    if (!svc) return
    // A second pick while the first is still being sent: play it next.
    if (selectingCover) { if (previewing) queuedPick = true; return }
    if (!previewing) {
      if (svc.hasTrack) {
        browseError = ""
        if (svc.closed) { svc.play(); return }
        selectingCover = true
        svc.request("transport", {action: svc.isPlaying ? "pause" : "play"}, function(r) {
          selectingCover = false
          browseError = r.ok ? "" : Model.errorText(r.error)
        })
      }
      return
    }
    if (!preview) return
    const row = preview
    selectingCover = true
    browseError = ""
    // Respond at once: the clicked song takes over the title, colours and
    // cover straight away while YouTube Music loads it in the background.
    pendingFrom = svc.videoId
    switchSent = false
    pending = row.item
    pendingTimeout.restart()
    // YouTube Music stops the playing song the moment it is asked to switch,
    // so a short fade (about 0.4 s) runs first; then the switch is sent.
    fadeOutThen(function() {
      switchSent = true
      CoverSelection.play(svc, row.item, !!row.automix, function(r) {
        selectingCover = false
        // The volume comes back when the new song is on (onVideoIdChanged /
        // loadingSong), never while the old one may still be playing.
        if (!r.ok) restoreVolume()
        browseError = r.ok ? "" : Model.errorText(r.error)
        if (r.ok) queueRefresh.restart()
        else pending = null
        if (queuedPick) { queuedPick = false; Qt.callLater(root.playPreview) }
      })
    }, 480)
  }

  // Dial: play a disc from the wheel, with the CD animation.
  function pickDisc(index) {
    if (!svc || index < 0 || index >= covers.length) return
    // A pick while a new list's flight is still waiting: that one is dropped.
    if (flyWhenLoaded !== "") { flyWhenLoaded = ""; flyWait.stop(); dialArt.holding = false; dialArt.oldOutside = false }
    if (covers[index].item.videoId === (loadingSong ? pendingId : svc.videoId)) { browseIndex = index; return }
    // Until the disc lands, the title and colours stay as they were.
    if (!dialArt.holding) { heldTitle = shownTitle; heldArtist = shownArtist; heldThumb = liveThumb }
    browseIndex = index
    dialArt.fly(index)
    playPreview()
  }
  property bool queuedPick: false
  property string heldTitle: ""
  property string heldArtist: ""
  property string heldThumb: ""
  readonly property bool landingHold: dial && dialArt.holding
  // Calm mode (setting "motion: reduced"): no flying disc, drifting
  // backdrop or spinning disc; songs simply cross-fade.
  property bool reduceMotion: false
  // One flow after a disc goes in: a single circle of new colour (radius
  // flowR, px from the cover's middle) that fills the cover and carries
  // straight on into the background, and one spin (flowSpin, degrees,
  // clockwise to 0) shared by the cover art and the background colours.
  property bool flowActive: false
  // A picked song: the playing one fades down (to 1, not 0, so Chromium
  // keeps its sound stream open) while the new one loads, then the volume
  // fades back up as the new song starts. fadeKeep is the listener's own
  // volume while a change is under way (-1 when none).
  property int fadeKeep: -1
  property real fadeLevel: 0
  // The switch is sent once the fade is down to 12% (about 0.9 s into a
  // 1.2 s fade): quiet enough that the stop is not heard, and YouTube
  // Music can start loading the new song a little sooner.
  onFadeLevelChanged: {
    if (fadeKeep < 0 || !svc) return
    svc.setVolume(fadeLevel)
    if (afterFade && fadeLevel <= Math.max(1, fadeKeep * 0.12)) switchNow()
  }
  property var afterFade: null
  function switchNow() {
    const next = afterFade
    afterFade = null
    fadeDown.stop()
    if (next) next()
  }
  // The fade follows the ear: the volume falls by the same share in every
  // moment (an even drop in loudness), instead of an even drop in level,
  // which sounds like nothing happens and then a cliff at the end.
  // fadeP 0 → 1 runs the level from fadeKeep down to 8% of it.
  readonly property real fadeFloor: 0.08
  property real fadeP: 0
  onFadePChanged: if (fadeKeep >= 0 && fadeDown.running) fadeLevel = Math.max(1, fadeKeep * Math.pow(fadeFloor, fadeP))
  NumberAnimation {
    id: fadeDown; target: root; property: "fadeP"; to: 1; duration: 1200; easing.type: Easing.Linear
    onFinished: root.switchNow()
  }
  // The new song starts at the listener's full volume: put it back as soon
  // as YouTube Music has switched (the old song has stopped by then).
  function restoreVolume() {
    if (fadeKeep < 0) return
    const keep = fadeKeep
    fadeKeep = -1
    fadeDown.stop()
    if (svc) svc.setVolume(keep)
  }
  // Fade the playing song out, then run `next` (the switch). Nothing to
  // fade (paused, or already quiet): switch straight away.
  function fadeOutThen(next, ms) {
    fadeDown.duration = ms || 1200
    if (!svc || !svc.isPlaying) { next(); return }
    if (fadeKeep < 0) { fadeKeep = Math.round(svc.volume); fadeLevel = fadeKeep }
    if (fadeLevel <= 1.5) { next(); return }
    afterFade = next
    // Carry on from where a fade already under way had got to.
    fadeDown.from = Math.max(0, Math.min(1, Math.log(fadeLevel / fadeKeep) / Math.log(fadeFloor)))
    fadeDown.restart()
  }
  onLoadingSongChanged: if (!loadingSong) { restoreVolume(); dialArt.hurry() }
  property real flowR: 0
  property real flowSpin: 0
  onFlowRChanged: if (flowActive) dialArt.reveal = Math.min(1, flowR / dialArt.coverReach)
  // "Colour from album artwork" (Settings → Appearance). Off: a plain frosted
  // background in the desktop theme's colours (views2/ThemeGlow).
  readonly property bool albumBackdrop: !svc || String(svc.setting("albumColors", true)) !== "false"
  // Test hook (IPC dialPick): browse by `delta` discs and play that one.
  function testPick(delta) {
    if (!covers.length) return
    pickDisc(Math.max(0, Math.min(covers.length - 1, (browseIndex < 0 ? 0 : browseIndex) + delta)))
  }

  // The song the user just chose, until its sound actually starts.
  property var pending: null
  readonly property string pendingId: pending ? String(pending.videoId || "") : ""
  readonly property bool loadingSong: pendingId !== ""
  function isCurrent(videoId) {
    return loadingSong ? videoId === pendingId : hasTrack && videoId === svc.videoId
  }
  // The song that was playing when a new one was picked, and whether the
  // switch has been sent: YouTube Music sometimes plays the picked song
  // under another video id (the music video instead of the album track),
  // so "a different song is now playing after the switch" counts as
  // started too, not only an exact id match.
  property string pendingFrom: ""
  property bool switchSent: false
  onPendingChanged: if (!pending) switchSent = false
  function checkPending() {
    if (!loadingSong || !svc || !svc.isPlaying || svc.isAd) return
    if (svc.videoId === pendingId || (switchSent && svc.videoId !== "" && svc.videoId !== pendingFrom)) pending = null
  }
  Connections {
    target: root.svc
    ignoreUnknownSignals: true
    function onIsPlayingChanged() { root.checkPending() }
    function onVideoIdChanged() { if (root.fadeKeep >= 0 && !root.afterFade) root.restoreVolume(); root.checkPending(); root.autoFlight() }
  }

  // The song that was on before the current one: what the title, colours
  // and wheel showed, so a change can fly from it.
  property string lastId: ""
  property string lastTitle: ""
  property string lastArtist: ""
  property string lastThumb: ""
  // The song changed without a disc being picked here (Next or Previous,
  // a key, a song that ended, a pick in the full player): the wheel's disc
  // for it flies into the cover just as a pick does. The music is already
  // playing, so the flight is the quick catch-up version (hurry).
  function noteSong() {
    if (!svc || !svc.hasTrack || svc.isAd || !svc.videoId) return
    lastId = svc.videoId; lastTitle = svc.title; lastArtist = svc.artist; lastThumb = svc.thumb
  }
  // The title and picture can arrive a moment after the song itself.
  Connections {
    target: root.svc
    ignoreUnknownSignals: true
    function onTitleChanged() { if (root.svc.videoId === root.lastId) root.noteSong() }
    function onArtistChanged() { if (root.svc.videoId === root.lastId) root.noteSong() }
    function onThumbChanged() { if (root.svc.videoId === root.lastId) root.noteSong() }
  }
  function autoFlight() {
    const was = lastId, wasTitle = lastTitle, wasArtist = lastArtist, wasThumb = lastThumb
    const now = svc && svc.hasTrack && !svc.isAd ? (svc.videoId || "") : ""
    if (now !== "") noteSong()
    if (now === "" || was === "" || now === was) return
    if (!opened || !dial || !showWheel || reduceMotion || loadingSong || dialArt.holding) return
    const to = covers.findIndex(row => !row.header && row.item && row.item.videoId === now)
    const from = covers.findIndex(row => !row.header && row.item && row.item.videoId === was)
    heldTitle = wasTitle; heldArtist = wasArtist; heldThumb = wasThumb
    if (to < 0) {
      // A new list (a radio, a playlist): its discs arrive a moment after
      // the song. Hold the old cover and title until they are on the wheel,
      // then fly (loadQueue); give up after a few seconds.
      flyWhenLoaded = now
      dialArt.oldOutside = true
      dialArt.heldRow = -1
      dialArt.holding = true
      flyWait.restart()
      queueRefresh.restart()
      return
    }
    if (to === from) return
    dialArt.oldOutside = from < 0
    browseIndex = to
    dialArt.fly(to, from)
    dialArt.hurry()
  }
  property string flyWhenLoaded: ""
  Timer {
    id: flyWait; interval: 4000
    onTriggered: {
      if (root.flyWhenLoaded === "") return
      root.flyWhenLoaded = ""
      dialArt.holding = false; dialArt.oldOutside = false
    }
  }
  // Called once a queue has loaded: the waiting flight goes if its disc is there.
  function flyIfLoaded() {
    if (flyWhenLoaded === "") return
    if (!svc || svc.videoId !== flyWhenLoaded) { flyWhenLoaded = ""; flyWait.stop(); dialArt.holding = false; dialArt.oldOutside = false; return }
    const to = covers.findIndex(row => !row.header && row.item && row.item.videoId === flyWhenLoaded)
    if (to < 0) { queueRefresh.restart(); return }   // not there yet: ask again
    flyWhenLoaded = ""
    flyWait.stop()
    browseIndex = to
    dialArt.fly(to, -1)
    dialArt.hurry()
  }
  Timer { id: pendingTimeout; interval: 12000; onTriggered: root.pending = null }
  Connections {
    target: root.svc
    function onQueueChanged() { queueRefresh.restart() }
    function onTrackChanged() { if (!root.loadingSong && !dialArt.holding) root.browseIndex = -1; queueRefresh.restart() }
  }
  Timer { id: queueRefresh; interval: 150; onTriggered: root.loadQueue() }
  function open() {
    if (svc && svc.closed) svc.startEngine()
    opened = true
  }
  function close() { opened = false }
  function toggle() { if (opened) close(); else open() }
  function closeForPopoutSwitch() { popup.closeForPopoutSwitch() }
  onOpenedChanged: {
    // Blur on or off may have changed since last time (GlassBlur).
    if (opened && svc && svc.glass) svc.glass.refresh()
    if (opened && lastId === "") noteSong()
    if (svc) svc.panelOpen = opened
    if (opened) { browseIndex = -1; loadQueue(); if (welcomeMode === "pick") loadStarters() }
    else { moreOpen = false; outputOpen = false; saveOpen = false; sleepOpen = false }
  }

  // Output: the Control Center's Sound section lists every output device.
  // Output: a drawer inside the player that sends only the music to a
  // device ("Same as computer" by default). No other plugin needed.
  property bool outputOpen: false
  // Sleep timer: a drawer like "Play music on", from the ••• menu (the same
  // timer as Settings → Playback).
  property bool sleepOpen: false
  property real sleepNow: Date.now()
  Timer { interval: 10000; repeat: true; running: root.sleepOpen || root.moreOpen; onTriggered: root.sleepNow = Date.now() }
  readonly property int sleepMinutesLeft: svc && svc.sleepEndsAt > 0 ? Math.max(1, Math.ceil((svc.sleepEndsAt - sleepNow) / 60000)) : 0
  readonly property string sleepShort: !svc ? "" : svc.sleepMode === "end" ? "end of song"
    : sleepMinutesLeft > 0 ? sleepMinutesLeft + " min left" : Model.sleepLabel(svc.sleepMode)
  function pickSleep(mode) {
    if (svc) svc.setSleepMode(mode)
    sleepNow = Date.now()
    sleepClose.restart()
    say(mode === "off" ? "Sleep timer off" : mode === "end" ? "Pauses at the end of this song" : "Pauses in " + Model.sleepLabel(mode))
  }
  Timer { id: sleepClose; interval: 260; onTriggered: root.sleepOpen = false }

  // Save to playlist: a drawer like "Play music on", from the ••• menu.
  property bool saveOpen: false
  function openSavePicker() {
    if (!svc || !hasTrack) return
    outputOpen = false
    savePicker.open({ videoId: svc.videoId, title: svc.title })
    saveOpen = true
  }
  function openOutputPicker() {
    if (!svc) return
    moreOpen = false
    svc.refreshOutputs()
    outputOpen = !outputOpen
  }
  function pickOutput(name) {
    if (!svc) return
    svc.setMusicOutput(name)
    outputCloseTimer.restart()
  }
  Timer { id: outputCloseTimer; interval: 260; onTriggered: root.outputOpen = false }
  readonly property string defaultOutputLabel: {
    if (!svc) return ""
    const d = svc.outputs["default"]
    const hit = (svc.outputs.sinks || []).find(x => x.name === d)
    return hit ? hit.label : ""
  }

  // What the title block shows: the browsed cover while browsing.
  readonly property var shownItem: loadingSong ? pending : previewing ? preview.item : null
  readonly property string shownTitle: landingHold ? heldTitle : shownItem ? (shownItem.title || "") : hasTrack ? svc.title : "Nothing playing"
  readonly property string shownArtist: landingHold ? heldArtist : shownItem
    ? (shownItem.artists || []).map(e => e.name || "").filter(Boolean).join(", ")
    : hasTrack ? svc.artist : "Search to choose your music"

  // Artwork that drives the backdrop: the chosen song's as soon as it is clicked.
  readonly property string liveThumb: landingHold ? heldThumb : loadingSong ? sharpCover(pending.thumb || "") : hasTrack ? svc.thumb : ""
  Views2.AlbumColor { id: albumColor; source: root.liveThumb }

  // ---- building blocks ---------------------------------------------------
  // A bare symbol button: no chrome until hovered, then a soft disc.
  // A thin white arc that turns while the chosen song loads.
  component LoadingRing: Item {
    id: ring
    width: Style.space(26); height: width
    Canvas {
      anchors.fill: parent
      onPaint: {
        const c = getContext("2d")
        c.reset()
        c.lineWidth = Style.space(2.5)
        c.lineCap = "round"
        c.strokeStyle = "rgba(255,255,255,0.25)"
        c.beginPath(); c.arc(width / 2, height / 2, width / 2 - c.lineWidth, 0, Math.PI * 2); c.stroke()
        c.strokeStyle = "white"
        c.beginPath(); c.arc(width / 2, height / 2, width / 2 - c.lineWidth, -Math.PI / 2, Math.PI * 0.35); c.stroke()
      }
    }
    RotationAnimator on rotation { from: 0; to: 360; duration: 850; loops: Animation.Infinite; running: ring.visible }
  }

  component SymbolButton: Item {
    id: btn
    property string icon: ""
    property string tip: ""
    property real size: Style.space(36)
    property real glyphSize: Style.space(18)
    property color glyphColor: root.ink
    signal clicked()
    width: size; height: size
    opacity: enabled ? 1 : 0.35
    activeFocusOnTab: enabled
    Accessible.role: Accessible.Button
    Accessible.name: tip
    Accessible.onPressAction: clicked()
    Keys.onReturnPressed: clicked()
    Keys.onSpacePressed: clicked()
    Rectangle {
      anchors.fill: parent
      radius: width / 2
      color: Util.alpha(root.ink, btnHit.pressed ? 0.16 : btnHit.containsMouse || btn.activeFocus ? 0.09 : 0)
      Behavior on color { ColorAnimation { duration: Style.duration(110) } }
    }
    Views2.Glyph {
      anchors.centerIn: parent
      name: btn.icon
      color: btn.glyphColor
      size: btn.glyphSize
    }
    // pop: the icon gives a small bounce when it changes (the liked heart).
    property bool pop: false
    property real popScale: 1
    onIconChanged: if (pop) popAnim.restart()
    SequentialAnimation {
      id: popAnim
      NumberAnimation { target: btn; property: "popScale"; to: 1.3; duration: 120; easing.type: Easing.OutCubic }
      NumberAnimation { target: btn; property: "popScale"; to: 1; duration: 300; easing.type: Easing.OutBack; easing.overshoot: 3 }
    }
    transform: Scale { origin.x: btn.width / 2; origin.y: btn.height / 2; xScale: btn.popScale; yScale: btn.popScale }
    PanelToolTip {
      visible: btnHit.containsMouse && btn.tip !== ""
      text: btn.tip
      panelBackground: Util.alpha(root.glassC, 0.97)
      panelForeground: root.ink
      panelBorder: Util.alpha(root.ink, 0.10)
      delay: 600
    }
    MouseArea {
      id: btnHit
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: btn.clicked()
    }
    scale: btnHit.pressed ? 0.9 : 1
    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: 2 } }
  }

  // Apple Music style line slider: thin at rest, thicker under the pointer.
  component LineSlider: Item {
    id: line
    property real value: 0
    property real minimum: 0
    property real maximum: 1
    property color fillColor: root.ink
    property bool dragging: false
    // Scroll over the line to nudge it by this much (0 = off).
    property real wheelStep: 0
    property real liveValue: value
    readonly property real fraction: Math.max(0, Math.min(1, (liveValue - minimum) / Math.max(0.0001, maximum - minimum)))
    readonly property bool hot: lineHit.containsMouse || dragging
    signal moved(real value)
    signal released(real value)
    onValueChanged: if (!dragging) liveValue = value
    implicitHeight: Style.space(16)
    Rectangle {
      id: lineTrack
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      // Rest 4 px, hover 7 px, held 11 px: it swells under the finger like
      // Apple Music's scrubber, then springs back on release.
      height: line.dragging ? Style.space(11) : line.hot ? Style.space(7) : Style.space(4)
      radius: height / 2
      color: Util.alpha(root.ink, line.dragging ? 0.28 : 0.20)
      Behavior on height { SpringAnimation { spring: 5; damping: 0.38; epsilon: 0.2 } }
      Behavior on color { ColorAnimation { duration: 140 } }
      Rectangle {
        height: parent.height
        radius: height / 2
        width: Math.max(height, parent.width * line.fraction)
        color: line.fillColor
        Behavior on color { ColorAnimation { duration: 300 } }
      }
    }
    MouseArea {
      id: lineHit
      anchors.fill: parent
      anchors.topMargin: -Style.space(9)
      anchors.bottomMargin: -Style.space(9)
      hoverEnabled: true
      preventStealing: true
      cursorShape: line.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onWheel: wheel => { if (line.wheelStep > 0) {
        const step = (wheel.angleDelta.y || wheel.angleDelta.x) > 0 ? line.wheelStep : -line.wheelStep
        const v = Math.max(line.minimum, Math.min(line.maximum, line.value + step))
        line.moved(v); line.released(v)
      } }
      function valueAt(x) {
        const f = Math.max(0, Math.min(1, x / Math.max(1, width)))
        return line.minimum + f * (line.maximum - line.minimum)
      }
      onPressed: mouse => { line.dragging = true; line.liveValue = valueAt(mouse.x); line.moved(line.liveValue) }
      onPositionChanged: mouse => { if (line.dragging) { line.liveValue = valueAt(mouse.x); line.moved(line.liveValue) } }
      onReleased: { line.dragging = false; line.released(line.liveValue); line.liveValue = line.value }
    }
  }

  // ---- the window --------------------------------------------------------
  ArtworkPopup2 {
    id: popup
    anchorItem: root.anchorItem
    bar: root.bar
    owner: root
    open: root.opened
    padding: 0
    borderSpec: Border.flat("transparent", 0)
    contentWidth: root.small ? Style.space(300) : Style.space(400)
    contentHeight: root.compact
      ? Math.ceil(Style.space(18) + carousel.height + controls.anchors.topMargin + controls.implicitHeight + Style.space(16))
      : Style.space(566)
    focusTarget: card

    Rectangle {
      id: roundMask
      width: card.width; height: card.height
      radius: card.radius
      layer.enabled: true
      visible: false
      color: "white"
    }
    RectangularShadow {
      anchors.fill: card
      radius: card.radius
      blur: Style.space(34)
      spread: -Style.space(2)
      offset: Qt.vector2d(0, Style.space(10))
      color: "#66000000"
      z: -1
    }

    Rectangle {
      id: card
      anchors.fill: parent
      radius: Math.max(Style.cornerRadius, Style.space(18))
      // Album colours off: clearer glass, so the blurred desktop shows
      // through instead of a flat grey.
      color: "transparent"
      focus: true
      layer.enabled: true
      layer.effect: MultiEffect { maskEnabled: true; maskSource: roundMask }

      // Real frosted glass needs Hyprland's blur (GlassBlur). Without it
      // nothing behind the player can be shown honestly (apps cannot see
      // other windows on Wayland), so the glass turns almost solid.
      readonly property bool clear: !root.svc || !root.svc.glass || root.svc.glass.compositor
      HoverHandler { id: cardHover }
      Rectangle {
        anchors.fill: parent
        color: Util.alpha(root.glassC, !card.clear ? 0.94 : root.albumBackdrop ? 0.80 : root.blend ? (SpinTheme.Palette.light ? 0.30 : 0.55) : root.milky ? 0.22 : 0.50)
      }

      // Blurred artwork across the whole card. A new song's colours pour in:
      // they land on the cover and spread outward in a soft circle until the
      // card is full, turning a little as they go (a gentle whirl that slows
      // to the backdrop's usual drift). Calm motion: a plain cross-fade.
      Item {
        id: backdrop
        anchors.fill: parent
        readonly property string artwork: root.liveThumb
        // The picked disc's art, fetched while it flies so the pour is ready.
        readonly property string upcoming: root.landingHold && root.pending ? root.sharpCover(root.pending.thumb || "") : ""
        property int front: -1
        property int prev: -1          // the old colours, kept under the pour
        property real pour: 1          // 0 → 1: the circle spreading out
        property real swirl: 0         // extra turn of the new colours (degrees)
        property bool stirring: false  // a stir is running: layers switch at once
        // Where the colour lands: the middle of the big cover.
        readonly property real pourX: width / 2
        readonly property real pourY: carousel.y + (root.dial ? dialArt.bigY + dialArt.bigSize / 2 : carousel.height / 2)
        // Distance from there to the furthest corner of the card.
        readonly property real far: Math.max(Math.hypot(pourX, pourY), Math.hypot(width - pourX, pourY),
                                             Math.hypot(pourX, height - pourY), Math.hypot(width - pourX, height - pourY))
        // The same picture in another size is not a new song.
        function key(u) {
          return String(u || "").replace(/^\/\//, "https://")
            .replace(/=[ws]\d+[^/]*$/, "")
            .replace(/\/(default|mqdefault|hqdefault|sddefault|maxresdefault|hq720)\.(jpg|webp)(\?.*)?$/, "")
        }
        function update() {
          if (!artwork) { pourAnim.stop(); front = -1; prev = -1; return }
          const active = layers.itemAt(front)
          if (active && key(active.source) === key(artwork)) return
          const incoming = layers.itemAt(front === 0 ? 1 : 0)
          if (!incoming) return
          if (key(incoming.source) !== key(artwork)) incoming.source = artwork
          if (incoming.status === Image.Ready) startPour(incoming.index)
        }
        function preload() {
          if (!upcoming) return
          const active = layers.itemAt(front)
          if (active && key(active.source) === key(upcoming)) return
          const incoming = layers.itemAt(front === 0 ? 1 : 0)
          if (incoming && key(incoming.source) !== key(upcoming)) incoming.source = upcoming
        }
        function startPour(i) {
          if (i === front) return
          pourAnim.stop()
          // Inside a disc's flow: the shared circle and spin drive it.
          if (root.flowActive && front >= 0 && !root.reduceMotion && root.opened) {
            stirring = true
            pour = 0; swirl = 0
            prev = front; front = i
            return
          }
          if (front < 0 || root.reduceMotion || !root.opened) {
            stirring = false
            prev = -1; front = i; pour = 1; swirl = 0
            return
          }
          // Flow: once the new cover has slid to the front it bounces once,
          // then its colour spreads out as a rounded square (no spin).
          if (!root.dial) {
            stirring = true
            pour = 0; swirl = 0
            prev = front; front = i
            flowSettle.waited = 0
            flowSettle.restart()
            return
          }
          stirring = true
          pour = 0; swirl = -48
          prev = front; front = i
          pourAnim.restart()
        }
        onArtworkChanged: update()
        // The disc's flow has finished: the new colours are everywhere.
        function finishFlow() {
          if (prev < 0 && !stirring) return
          prev = -1; stirring = false; pour = 1; swirl = 0
        }
        // How far the background circle must reach to cover every corner.
        readonly property real bgReach: far * 1.6
        readonly property real spinNow: root.flowActive ? root.flowSpin : swirl
        // The background circle starts at the cover's corners (not the
        // middle), so the colour carries straight on out of the cover.
        readonly property real startThreshold: Math.max(0, 1 - (dialArt.bigSize / 2 * Math.SQRT2) / (far * 1.6))
        onUpcomingChanged: preload()
        // Flow: wait for the covers to stop sliding (at most 0.9 s) and for
        // the new song to actually start (at most 5 s).
        Timer {
          id: flowSettle
          interval: 30; repeat: true
          property int waited: 0
          onTriggered: {
            waited += interval
            const settled = Math.abs(carousel.position - Math.max(0, root.browseIndex)) < 0.06 || waited > 900
            const ready = !root.loadingSong || waited > 5000
            if (settled && ready) {
              stop()
              carousel.bounce()
              pourAnim.restart()
            }
          }
        }
        // Flow's fill shape: a rounded square (views2/square-fill.png, solid
        // in the middle and fading outward), centred on the cover and big
        // enough that the card's corners are fully covered at the end.
        readonly property real squareHalf: Math.max(Math.max(pourX, width - pourX), Math.max(pourY, height - pourY)) / 0.9
        // It starts right at the cover's edges.
        readonly property real squareStart: Math.max(0, 1 - 0.75 * (Style.space(270) / 2) / Math.max(1, squareHalf))
        Item {
          id: squareMask
          anchors.fill: parent
          visible: false
          layer.enabled: true
          Image {
            width: backdrop.squareHalf * 2; height: width
            x: backdrop.pourX - width / 2
            y: backdrop.pourY - height / 2
            source: Qt.resolvedUrl("views2/square-fill.png")
            sourceSize: Qt.size(512, 512)
            smooth: true
          }
        }
        Component.onCompleted: Qt.callLater(update)

        // The colour change works like colour on a spinning plate (or an
        // old cartoon iris): the new colours start as a small circle on the
        // cover and grow outward as a round circle while they spin, turning
        // clockwise the same way as the backdrop's drift and the CD. The
        // spin is quick at first and slows down until it is just the usual
        // slow drift.
        ParallelAnimation {
          id: pourAnim
          SequentialAnimation {
            // Starts at the speed the cover's circle was moving, then picks
            // up evenly (no pause or lurch where cover and background meet).
            NumberAnimation { target: backdrop; property: "pour"; from: 0; to: 1; duration: 2400; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.333, 0.19, 0.667, 0.523, 1, 1] }
            ScriptAction { script: { backdrop.prev = -1; backdrop.stirring = false } }
          }
          // The colours start turning at the playing CD's speed (40°/s, the
          // same as the cover's art spin) and slow evenly to a stop just as
          // the fill completes, leaving only the backdrop's very slow drift.
          // (48° over the 2.4 s fill: OutQuad starts at 2 × 48 / 2.4 = 40°/s.)
          NumberAnimation { target: backdrop; property: "swirl"; to: 0; duration: 2400; easing.type: Easing.OutQuad }
        }

        // The circle's shape: solid at the cover, fading outward. Its reach
        // is long enough that the far corners are fully covered at the end.
        Views2.SoftDisc {
          id: pourMask
          anchors.fill: parent
          centerX: backdrop.pourX
          centerY: backdrop.pourY
          reach: backdrop.far * 1.6
          visible: false
          layer.enabled: true
        }

        // The blurred artwork slowly turns and breathes while music plays,
        // so the colours drift like Apple Music's living backdrop. It is a
        // square wider than the card's diagonal, so no corner ever shows.
        // (Timed on the main thread so both layers can follow it.)
        Item {
          id: drift
          anchors.centerIn: parent
          width: Math.hypot(parent.width, parent.height) + Style.space(90)
          height: width
          // Spinning round the cover (not the card's middle) also shifts the
          // square; the spinning colours grow just enough to keep every
          // corner covered, and are back to normal size when the spin ends.
          readonly property real coverOffset: Math.hypot(backdrop.pourX - parent.width / 2, backdrop.pourY - parent.height / 2)
          function spinZoom(angle) {
            const a = Math.abs(angle)
            if (a < 0.01) return 1
            const shift = 2 * coverOffset * (a >= 180 ? 1 : Math.sin(a * Math.PI / 360))
            return Math.max(1, (Math.hypot(parent.width, parent.height) / 2 + shift) / (width / 2))
          }
          readonly property bool live: root.opened && root.playing
          // The steady turn is off (2026-11-23: only the breathing keeps the
          // colours alive; the pour still swirls in). true brings it back.
          readonly property bool spins: false
          NumberAnimation on rotation {
            from: 0; to: 360; duration: 95000
            loops: Animation.Infinite
            running: drift.spins && root.opened && !root.reduceMotion
            paused: running && !drift.live
          }
          SequentialAnimation on scale {
            loops: Animation.Infinite
            running: root.opened && !root.reduceMotion
            paused: running && !drift.live
            NumberAnimation { from: 1.0; to: 1.22; duration: 8000; easing.type: Easing.InOutSine }
            NumberAnimation { from: 1.22; to: 1.0; duration: 8000; easing.type: Easing.InOutSine }
          }
        }

        Repeater {
          id: layers
          model: 2
          Item {
            id: colourLayer
            required property int index
            property alias source: art.source
            readonly property int status: art.status
            readonly property bool pouring: index === backdrop.front && backdrop.prev >= 0 && backdrop.pour < 1
            anchors.fill: parent
            z: index === backdrop.front ? 2 : 1
            opacity: (index === backdrop.front || index === backdrop.prev) && root.albumBackdrop ? 0.85 : 0
            visible: opacity > 0
            // Fades are for Calm motion and the colour switch; while the
            // circle grows, the layers switch at once.
            Behavior on opacity {
              enabled: !backdrop.stirring
              NumberAnimation { duration: 1100; easing.type: Easing.InOutQuad }
            }
            layer.enabled: pouring
            layer.effect: MultiEffect {
              maskEnabled: true
              maskSource: root.dial ? pourMask : squareMask
              // Starts at the edge of the cover and carries on outward.
              // In a disc's flow it is the very same circle as the cover's
              // (same middle, same radius, same soft edge in pixels).
              maskThresholdMin: root.flowActive ? Math.max(0, 1 - root.flowR / backdrop.bgReach)
                                                : Math.max(0, (root.dial ? backdrop.startThreshold : backdrop.squareStart) * (1 - backdrop.pour))
              maskSpreadAtMin: root.flowActive ? 0.3 * dialArt.coverReach / backdrop.bgReach : root.dial ? 0.18 : 0.12
            }
            // The spin, round the cover (only the new colours spin).
            Item {
              anchors.fill: parent
              transform: Rotation {
                origin.x: backdrop.pourX
                origin.y: backdrop.pourY
                angle: colourLayer.index === backdrop.front ? backdrop.spinNow : 0
              }
              Item {
                x: (parent.width - width) / 2
                y: (parent.height - height) / 2
                width: drift.width; height: width
                rotation: drift.rotation
                scale: drift.scale * (colourLayer.index === backdrop.front ? drift.spinZoom(backdrop.spinNow) : 1)
                Image {
                  id: art
                  anchors.fill: parent
                  sourceSize: Qt.size(64, 64)
                  asynchronous: true
                  fillMode: Image.PreserveAspectCrop
                  layer.enabled: colourLayer.visible
                  layer.effect: MultiEffect { blurEnabled: true; blur: 1; blurMax: 64; saturation: root.stage ? 0.85 : 0.6; brightness: root.stage ? 0.02 : -0.06 }
                  onStatusChanged: if (status === Image.Ready && backdrop.key(source) === backdrop.key(backdrop.artwork)) backdrop.startPour(colourLayer.index)
                }
              }
            }
          }
        }
        // Darken towards the controls so text always reads.
        // Pale covers get a deeper wash so white text keeps its contrast.
        Rectangle {
          id: wash
          z: 5
          // The stage lets more of the album's own colour through (a lighter
          // darkening; the white text still reads on it).
          readonly property real strength: root.stage ? 0.72 : root.albumBackdrop ? 1 : root.milky ? 0.42 : 0.55
          anchors.fill: parent
          property real pale: root.albumBackdrop ? Math.max(0, Math.min(1, (albumColor.brightness - 0.35) / 0.45)) : 0
          // Change gently along with the colour fill (about 3 s) instead of
          // all at once when the disc lands, which looked like a flash.
          Behavior on pale { NumberAnimation { duration: 3000; easing.type: Easing.InOutSine } }
          gradient: Gradient {
            GradientStop { position: 0.0; color: Util.alpha(root.washC, root.blend ? 0 : (0.10 + 0.40 * wash.pale) * wash.strength) }
            GradientStop { position: 0.38; color: Util.alpha(root.washC, root.blend ? 0.04 : (0.33 + 0.36 * wash.pale) * wash.strength) }
            GradientStop { position: 0.55; color: Util.alpha(root.washC, root.blend ? 0.58 : (0.45 + 0.35 * wash.pale) * wash.strength) }
            GradientStop { position: 1.0; color: Util.alpha(root.washC, root.blend ? 0.70 : (0.70 + 0.22 * wash.pale) * wash.strength) }
          }
        }
        Views2.ThemeGlow {
          z: 6
          second: root.paleGlass ? "white" : Commons.Color.popups.text
          anchors.fill: parent
          opacity: root.albumBackdrop ? 0 : 1
          visible: opacity > 0.01
          Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.InOutQuad } }
        }
      }

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) { if (root.saveOpen) root.saveOpen = false; else if (root.sleepOpen) root.sleepOpen = false; else if (root.outputOpen) root.outputOpen = false; else if (root.moreOpen) root.moreOpen = false; else root.close() }
        else if (event.key === Qt.Key_Space && root.svc) root.svc.togglePlaying()
        else if (event.key === Qt.Key_Right && root.svc) root.svc.next()
        else if (event.key === Qt.Key_Left && root.svc) root.svc.previous()
        else if (event.key === Qt.Key_F && root.svc) root.svc.toggleLike()
        else return
        event.accepted = true
      }

      // ---- Cover Flow ------------------------------------------------------
      Item {
        id: carousel
        x: 0; y: Style.space(18)
        width: parent.width
        // Compact: just room for the cover and the top of the wheel (the
        // facing disc whole), so the title never sits on the discs.
        height: !root.showWheel ? dialArt.bigSize + Style.space(6)
          : root.compact ? dialArt.thumbTop + dialArt.thumb * (1 + dialArt.focusGrow) + Style.space(4)
          : Style.space(290)
        // The Dial's wheel peeks in from below and is cut at the card's edge
        // (the flying disc lives in flightLayer, so it is never cut); discs
        // fade out as they near the cut, so no hard edge shows.
        clip: root.dial
        // While a picked disc is turned to the top, the flight drives the
        // wheel itself (a timed turn, so the lift can follow straight on).
        property real position: dialArt.turning ? dialArt.turnPos : Math.max(0, root.browseIndex)
        // Flow: the front cover's single bounce when a new song arrives.
        property real bounceScale: 1
        function bounce() { if (!root.reduceMotion) bounceAnim.restart() }
        SequentialAnimation {
          id: bounceAnim
          NumberAnimation { target: carousel; property: "bounceScale"; to: 1.06; duration: 150; easing.type: Easing.OutQuad }
          NumberAnimation { target: carousel; property: "bounceScale"; to: 0.985; duration: 170; easing.type: Easing.InOutQuad }
          NumberAnimation { target: carousel; property: "bounceScale"; to: 1; duration: 200; easing.type: Easing.OutQuad }
        }
        Behavior on position {
          enabled: !dialArt.turning
          SpringAnimation { spring: 3.2; damping: 0.34; epsilon: 0.002 }
        }
        readonly property var rows: root.covers.length ? root.covers
          : [{item: {videoId: root.svc ? root.svc.videoId : "", thumb: root.svc ? root.svc.thumb : ""}}]
        Repeater {
          model: carousel.rows
          delegate: Item {
            id: cover
            required property var modelData
            required property int index
            readonly property real offset: index - carousel.position
            readonly property real distance: Math.abs(offset)
            readonly property real tilt: Math.max(-1, Math.min(1, offset))
            readonly property bool currentTrack: root.isCurrent(modelData.item.videoId)
              readonly property bool loadingHere: root.loadingSong && modelData.item.videoId === root.pendingId
            width: Style.space(270); height: width
            x: (carousel.width - width) / 2 + offset * Style.space(150) + tilt * Style.space(28)
            y: (carousel.height - height) / 2
            property real pauseFactor: currentTrack && distance < 0.5 ? root.pauseScale : 1
            Behavior on pauseFactor { SpringAnimation { spring: 2.6; damping: 0.26; epsilon: 0.002 } }
            // Hover lifts the front cover a touch toward you (it can be clicked).
            property real hoverLift: coverHit.containsMouse && distance < 0.5 ? 1 : 0
            Behavior on hoverLift { SpringAnimation { spring: 4; damping: 0.45; epsilon: 0.005 } }
            scale: (1 - Math.min(1, distance) * 0.2) * pauseFactor * (1 + 0.025 * hoverLift) * (distance < 0.5 ? carousel.bounceScale : 1)
            z: 10 - distance
            // Click feedback: the new state's symbol shows briefly, then fades.
            property real flash: 0
            property string flashIcon: "play"
            SequentialAnimation {
              id: coverFlash
              NumberAnimation { target: cover; property: "flash"; to: 1; duration: 90; easing.type: Easing.OutCubic }
              PauseAnimation { duration: 320 }
              NumberAnimation { target: cover; property: "flash"; to: 0; duration: 380; easing.type: Easing.InCubic }
            }

            visible: !root.dial && distance < 2.4
            opacity: distance < 1.6 ? 1 : Math.max(0, 1 - (distance - 1.6) * 1.25)
            transform: Rotation {
              origin.x: cover.tilt < 0 ? cover.width : 0
              origin.y: cover.height / 2
              axis { x: 0; y: 1; z: 0 }
              angle: -cover.tilt * 38
            }
            Rectangle {
              anchors.fill: parent; radius: Style.space(12)
              color: Commons.Color.background
              layer.enabled: true
              layer.effect: MultiEffect { shadowEnabled: true; shadowOpacity: 0.45 - Math.min(1, cover.distance) * 0.2; shadowBlur: 0.8; shadowVerticalOffset: Style.space(8) }
            }
            Rectangle {
              id: coverMask
              width: cover.width; height: cover.height; radius: Style.space(12)
              visible: false; layer.enabled: true; color: "white"
            }
            Image {
              anchors.fill: parent
              source: cover.visible ? root.sharpCover(root.svc && cover.modelData.item.videoId === root.svc.videoId ? root.svc.thumb : cover.modelData.item.thumb) : ""
              sourceSize: Qt.size(Math.ceil(width * Screen.devicePixelRatio), Math.ceil(height * Screen.devicePixelRatio))
              asynchronous: true; fillMode: Image.PreserveAspectCrop; smooth: true; mipmap: true
              layer.enabled: true
              layer.effect: MultiEffect { maskEnabled: true; maskSource: coverMask }
              Text { anchors.centerIn: parent; visible: parent.status !== Image.Ready; text: Icons.note; color: root.inkSoft; font.pixelSize: Style.space(60) }
            }
            // Neighbours sink back into shadow rather than turning see-through.
            Rectangle {
              anchors.fill: parent; radius: Style.space(12)
              color: "black"
              opacity: Math.min(1, cover.distance) * 0.5
            }
            Rectangle {
              anchors.centerIn: parent
              width: Style.space(54); height: width; radius: width / 2
              opacity: cover.loadingHere ? 1 : cover.flash
              scale: cover.loadingHere ? 1 : 0.85 + 0.15 * cover.flash
              color: "#80000000"
              LoadingRing { anchors.centerIn: parent; visible: cover.loadingHere }
              Views2.Glyph {
                anchors.centerIn: parent
                visible: !cover.loadingHere
                name: cover.flashIcon
                color: "white"
                size: Style.space(24)
              }
            }
            MouseArea {
              id: coverHit
              anchors.fill: parent; cursorShape: Qt.PointingHandCursor
              hoverEnabled: true
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              onClicked: mouse => {
                if (mouse.button === Qt.RightButton) { root.artworkStyleRequested("dial"); return }
                const toggling = cover.currentTrack && !root.loadingSong && (!root.covers.length || cover.index === root.browseIndex || root.browseIndex < 0)
                if (toggling) { cover.flashIcon = root.playing ? "pause" : "play"; coverFlash.restart() }
                if (root.covers.length) root.browseIndex = cover.index; root.playPreview()
              }
              onWheel: event => wheelInput.handleWheel(event)
            }
          }
        }

        // ---- Dial ------------------------------------------------------------
        // One large cover (the song that plays); below it, the queue as small
        // discs on a wheel whose top just peeks into the card. The disc facing
        // straight up is the biggest, the rest shrink away from it. Scrolling
        // turns the wheel. Clicking a disc plays it like a CD: it lifts out of
        // the wheel and grows (no spin until it is in the player), slides up
        // behind the cover as if into a slot, and the new art sweeps up into
        // the cover. The flying disc itself lives in flightLayer, outside this
        // clipped area, so it is never cut off.
        Item {
          id: dialArt
          anchors.fill: parent
          visible: root.dial
          readonly property real bigSize: Style.space(222) * root.k
          readonly property real bigY: Style.space(2)
          readonly property real thumb: Style.space(34) * (root.small ? 0.7 : root.k)
          readonly property real radius: Style.space(330) * root.k
          readonly property real step: 11.5
          readonly property real focusGrow: 0.32
          readonly property real thumbTop: bigSize + Style.space(26) * root.k

          readonly property int currentRow: {
            const rows = carousel.rows
            for (let i = 0; i < rows.length; i++) if (root.isCurrent(rows[i].item.videoId)) return i
            return rows.length === 1 ? 0 : -1
          }
          // From the click until the disc is inside the cover.
          property bool holding: false
          property int heldRow: -1
          // The old song is not on the wheel (a new list replaced it): its
          // cover is drawn by heldCover from heldThumb instead of a row.
          property bool oldOutside: false
          readonly property int shownRow: holding ? heldRow : currentRow
          // The old cover, kept under the new art while it sweeps in.
          property int prevRow: -1
          property real reveal: 1
          // The new cover's grow into place (0 → 1, with a soft overshoot).
          property real grow: 1
          // The new art's turn while it spills in (degrees, clockwise to 0).
          // How far the cover's circle reaches (past its corners).
          readonly property real coverReach: bigSize / 2 * Math.SQRT2 * 1.6
          property real bump: 1
          // First the wheel turns the picked disc to the top (turning), then
          // it lifts off from there (airborne) and goes into the player.
          property bool turning: false
          property real turnPos: 0
          property bool airborne: false
          // The disc is at the slot, spinning, waiting for the music.
          property bool reading: false
          // Catch-up: the music never waits for the animation. If the song
          // starts while the disc is still turning or flying, the rest of
          // the flight is done quickly (about a quarter of a second) so the
          // disc lands and the colours flow in together with the sound.
          function hurry() {
            if (!flight.running) return
            flight.stop()
            rushTurn.to = turnAnim.to
            rushTurn.duration = turning ? 160 : 0
            rush.restart()
          }
          function arrive() {
            if (!root.loadingSong) { landing.restart(); return }
            reading = true
            readWait.waited = 0
            readWait.restart()
          }
          // Neighbours close the flying disc's gap while it is away.
          property real gap: airborne ? 1 : 0
          Behavior on gap { SpringAnimation { spring: 3; damping: 0.45; epsilon: 0.005 } }

          // Mask for the cover spill-in: solid in the middle, fading to the
          // corners. The cover shows where it is denser than the moving
          // threshold, so lowering the threshold spreads a soft circle out.
          Views2.SoftDisc {
            id: spillMask
            width: dialArt.bigSize; height: width
            reach: dialArt.coverReach
            visible: false
            layer.enabled: true
          }

          function shiftFor(index) {
            if (gap <= 0 || disc.flyIndex < 0 || index === disc.flyIndex) return 0
            return (index < disc.flyIndex ? 0.5 : -0.5) * gap
          }
          // A wheel disc's place and size for a row.
          function geom(index) {
            const off = index - carousel.position + shiftFor(index)
            const ang = off * step * Math.PI / 180
            const focus = Math.max(0, 1 - Math.abs(off))
            const size = thumb * (1 + focusGrow * focus)
            const cx = width / 2 + Math.sin(ang) * radius
            const cy = thumbTop + thumb / 2 + (1 - Math.cos(ang)) * radius
            return { x: cx - size / 2, y: cy - size / 2, s: size, off: off, focus: focus }
          }
          function fly(index, fromRow) {
            const row = carousel.rows[index]
            if (!row || root.reduceMotion) return
            if (holding && airborne) ghost.start()   // changed mind: drop that one back
            else if (!holding) heldRow = fromRow !== undefined ? fromRow : currentRow
            // Picked again during the final sweep: finish it at once.
            reveal = 1; grow = 1; prevRow = -1; bump = 1
            landing.stop(); rush.stop(); readWait.stop(); reading = false
            if (root.flowActive) { root.flowActive = false; backdrop.finishFlow() }
            const from = carousel.position
            disc.source = root.sharpCover(row.item.thumb || "")
            disc.flyIndex = index
            holding = true
            airborne = false
            turnPos = from
            turning = true
            const dist = Math.abs(index - from)
            turnAnim.to = index
            turnAnim.duration = dist < 0.02 ? 0 : Math.min(900, 320 + 150 * dist)
            flight.restart()
          }
          // The picked disc has reached the top: it lifts off from there.
          function liftOff() {
            const g = geom(disc.flyIndex)
            disc.sx = g.x; disc.sy = g.y; disc.ss = g.s
            airborne = true
            turning = false
          }

          Repeater {
            id: bigCovers
            model: root.dial ? carousel.rows : []
            delegate: Item {
              id: big
              required property var modelData
              required property int index
              readonly property bool shown: index === dialArt.shownRow
              readonly property bool underWipe: index === dialArt.prevRow
              readonly property bool currentTrack: root.isCurrent(modelData.item.videoId)
              readonly property bool loadingHere: root.loadingSong && modelData.item.videoId === root.pendingId && !dialArt.holding
              // Spill-in: the new cover spreads out over the old one in a
              // soft circle from the middle, sharpening as it goes; the old
              // one softens a little underneath until it is covered.
              readonly property bool wiping: shown && dialArt.reveal < 1
              readonly property bool leaving: underWipe && dialArt.reveal < 1
              readonly property real blurAmount: wiping ? (1 - dialArt.reveal) * 0.35 : leaving ? dialArt.reveal * 0.25 : 0
              property real pauseFactor: currentTrack ? root.pauseScale : 1
              Behavior on pauseFactor { SpringAnimation { spring: 2.6; damping: 0.26; epsilon: 0.002 } }
              opacity: wiping || leaving || shown || underWipe ? 1 : 0
              Behavior on opacity {
                enabled: !big.wiping && !big.leaving
                NumberAnimation { duration: big.shown || big.underWipe ? 160 : 420; easing.type: Easing.InOutQuad }
              }
              visible: opacity > 0.001
              width: dialArt.bigSize; height: width
              x: (dialArt.width - width) / 2
              y: dialArt.bigY
              z: shown ? 3 : underWipe ? 2.5 : 2
              // Hover lifts the cover a touch toward you (it can be clicked).
              property real hoverLift: bigHit.containsMouse && shown && !dialArt.holding ? 1 : 0
              Behavior on hoverLift { SpringAnimation { spring: 4; damping: 0.45; epsilon: 0.005 } }
              scale: pauseFactor * (1 + 0.025 * hoverLift) * (shown ? dialArt.bump * (0.975 + 0.025 * dialArt.grow) : leaving ? dialArt.bump * (1 - 0.025 * dialArt.reveal) : 1)
              // Click feedback: the new state's symbol shows briefly, then fades.
              property real flash: 0
              property string flashIcon: "play"
              SequentialAnimation {
                id: bigFlash
                NumberAnimation { target: big; property: "flash"; to: 1; duration: 90; easing.type: Easing.OutCubic }
                PauseAnimation { duration: 320 }
                NumberAnimation { target: big; property: "flash"; to: 0; duration: 380; easing.type: Easing.InCubic }
              }

              RectangularShadow {
                anchors.fill: parent; radius: Style.space(14)
                blur: Style.space(26) + big.hoverLift * Style.space(12)
                offset: Qt.vector2d(0, Style.space(10) + big.hoverLift * Style.space(5))
                color: Util.alpha("black", 0.5 + big.hoverLift * 0.12)
                // Only one cover shadow at a time: a RectangularShadow is a
                // filled blur, so a second one (the new cover's while it
                // spills in over the old one, or under the lid while the
                // disc flies) darkens the art and the colours around it.
                visible: big.shown ? !big.wiping && !dialArt.holding : big.leaving
              }
              Item {
                id: sweep
                anchors.fill: parent
                layer.enabled: big.wiping
                layer.effect: MultiEffect {
                  maskEnabled: true
                  maskSource: spillMask
                  // Starts as a small dot in the middle of the cover.
                  maskThresholdMin: Math.max(0, 1 - dialArt.reveal)
                  maskSpreadAtMin: 0.3
                }
                Item {
                  width: big.width; height: big.height
                  Rectangle {
                    id: bigMask
                    anchors.fill: parent; radius: Style.space(14)
                    visible: false; layer.enabled: true; color: "white"
                  }
                  Rectangle { anchors.fill: parent; radius: Style.space(14); color: Commons.Color.background }
                  // The art spins in round the middle (clockwise, at the CD's
                  // speed); it is enlarged just enough while turned that its
                  // corners never show inside the rounded cover.
                  Item {
                    anchors.fill: parent
                    layer.enabled: true
                    layer.effect: MultiEffect {
                      maskEnabled: true; maskSource: bigMask
                      // No padding: the blur must stay inside the cover, or
                      // the rounded mask stretches outward and the corners
                      // turn square while the art spills in.
                      autoPaddingEnabled: false
                      blurEnabled: big.blurAmount > 0.001
                      blur: big.blurAmount; blurMax: 48
                    }
                  Image {
                    id: bigImg
                    readonly property real spin: big.shown && root.flowActive ? root.flowSpin : 0
                    anchors.fill: parent
                    rotation: spin
                    scale: Math.abs(Math.cos(spin * Math.PI / 180)) + Math.abs(Math.sin(spin * Math.PI / 180))
                    // Loaded as soon as its disc is picked, so the art is
                    // ready by the time the disc is in (no late pop).
                    source: big.visible || big.shown || big.underWipe || (dialArt.holding && big.index === disc.flyIndex) ? root.sharpCover(big.currentTrack && !root.loadingSong ? root.svc.thumb : big.modelData.item.thumb) : ""
                    sourceSize: Qt.size(Math.ceil(width * Screen.devicePixelRatio), Math.ceil(height * Screen.devicePixelRatio))
                    asynchronous: true; fillMode: Image.PreserveAspectCrop; smooth: true; mipmap: true
                    retainWhileLoading: true
                    Views2.Glyph { anchors.centerIn: parent; visible: parent.status !== Image.Ready; name: "note"; color: root.inkSoft; size: Style.space(56) }
                  }
                  }
                }
              }
              Rectangle {
                anchors.centerIn: parent
                width: Style.space(54); height: width; radius: width / 2
                opacity: big.loadingHere && !big.wiping ? 1 : big.flash
                scale: big.loadingHere ? 1 : 0.85 + 0.15 * big.flash
                color: "#80000000"
                LoadingRing { anchors.centerIn: parent; visible: big.loadingHere }
                Views2.Glyph {
                  anchors.centerIn: parent
                  visible: !big.loadingHere
                  name: big.flashIcon
                  color: "white"; size: Style.space(24)
                }
              }
              MouseArea {
                id: bigHit
                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: mouse => {
                  if (mouse.button === Qt.RightButton) { root.artworkStyleRequested("flow"); return }
                  if (root.previewing) { root.pickDisc(root.browseIndex); return }
                  if (!root.loadingSong) { big.flashIcon = root.playing ? "pause" : "play"; bigFlash.restart() }
                  root.playPreview()
                }
                onWheel: event => wheelInput.handleWheel(event)
              }
            }
          }

          // The wheel. Its discs stay completely plain; below the cut at the
          // bottom a faint, blurred mirror of them (wheelReflection) softens
          // the straight edge, like discs standing on glass.
          Item {
            id: wheelContent
            anchors.fill: parent
          // The old song's cover when it is not on the wheel (a new list
          // replaced the queue): stays in place while the disc flies, and
          // under the new art while that spills in.
          Item {
            id: heldCover
            readonly property bool on: dialArt.oldOutside && (dialArt.holding || dialArt.reveal < 1)
            visible: on && root.heldThumb !== ""
            width: dialArt.bigSize; height: width
            x: (dialArt.width - width) / 2
            y: dialArt.bigY
            z: 2.5
            RectangularShadow {
              anchors.fill: parent; radius: Style.space(14)
              blur: Style.space(26); offset: Qt.vector2d(0, Style.space(10))
              color: Util.alpha("black", 0.5)
              visible: dialArt.holding
            }
            Rectangle { id: heldMask; anchors.fill: parent; radius: Style.space(14); visible: false; layer.enabled: true; color: "white" }
            Item {
              anchors.fill: parent
              layer.enabled: true
              layer.effect: MultiEffect { maskEnabled: true; maskSource: heldMask; autoPaddingEnabled: false; blurEnabled: dialArt.reveal < 1; blur: dialArt.reveal * 0.25; blurMax: 48 }
              Image {
                anchors.fill: parent
                source: heldCover.visible ? root.sharpCover(root.heldThumb) : ""
                sourceSize: Qt.size(Math.ceil(width * Screen.devicePixelRatio), Math.ceil(height * Screen.devicePixelRatio))
                asynchronous: true; fillMode: Image.PreserveAspectCrop; smooth: true; mipmap: true
              }
            }
          }

          Repeater {
            model: root.dial ? carousel.rows : []
            delegate: Item {
              id: tick
              required property var modelData
              required property int index
              readonly property var g: dialArt.geom(index)
              readonly property real distance: Math.abs(g.off)
              readonly property bool currentTrack: root.isCurrent(modelData.item.videoId)
              readonly property bool flying: dialArt.airborne && disc.flyIndex === index
              // Hover lifts the disc a touch; a press lifts it further.
              property real lift: tickHit.pressed ? 1 : tickHit.containsMouse ? 0.45 : 0
              Behavior on lift { SpringAnimation { spring: 4; damping: 0.4; epsilon: 0.005 } }
              visible: distance < 4.6 && root.showWheel
              width: g.s; height: g.s
              x: g.x
              y: g.y - lift * Style.space(4)
              rotation: g.off * dialArt.step
              scale: 1 + lift * 0.1
              // Every disc stays clear and bright; only the far ends of the
              // arc fade a little as they curve away.
              // Near the card's sides or the bottom of the wheel's area the
              // disc fades away, so it melts out instead of being cut off.
              readonly property real edgeFade: {
                const cx = g.x + g.s / 2, cy = g.y + g.s / 2
                const room = Math.min(cx, dialArt.width - cx, dialArt.height - cy) - g.s / 2
                // Fully visible until it touches the edge, then fades out as
                // it slides across it (gone when about 60% is past it).
                return Math.max(0, Math.min(1, (room + g.s * 0.6) / (g.s * 0.6 + Style.space(10))))
              }
              opacity: flying ? 0 : Math.max(0.4, 1 - Math.max(0, distance - 1.5) * 0.25)
              Behavior on opacity { NumberAnimation { duration: 160 } }
              RectangularShadow {
                anchors.fill: parent; radius: width / 2
                // Only a lifted (hovered or pressed) disc casts a shadow.
                visible: tick.lift > 0.01
                blur: Style.space(4) + tick.lift * Style.space(10)
                offset: Qt.vector2d(0, Style.space(1) + tick.lift * Style.space(4))
                color: Util.alpha("black", tick.lift * 0.5)
              }
              // The disc face: spins slowly while its song plays, like a CD
              // in the player, and stops where it is when paused.
              Item {
                id: face
                anchors.fill: parent
                RotationAnimator on rotation {
                  from: 0; to: 360; duration: 9000; loops: Animation.Infinite
                  running: tick.currentTrack && root.opened && !root.reduceMotion
                  paused: running && (!root.playing || root.loadingSong)
                }
                Rectangle {
                  id: tickMask
                  anchors.fill: parent; radius: width / 2
                  visible: false; layer.enabled: true; color: "white"
                }
                Image {
                  anchors.fill: parent
                  // Loaded a few discs ahead of the visible ones, so scrolling
                  // the wheel never shows a disc waiting for its picture.
                  source: tick.distance < 10 ? (tick.currentTrack && !root.loadingSong ? root.svc.thumb : tick.modelData.item.thumb) : ""
                  retainWhileLoading: true
                  sourceSize: Qt.size(128, 128)
                  asynchronous: true; fillMode: Image.PreserveAspectCrop; smooth: true
                  layer.enabled: true
                  layer.effect: MultiEffect { maskEnabled: true; maskSource: tickMask }
                }
                Rectangle {
                  anchors.centerIn: parent
                  width: parent.width * 0.16; height: width; radius: width / 2
                  color: "#1a1a1f"
                  border.width: 1; border.color: Util.alpha("white", 0.3)
                }
              }
              Rectangle {
                anchors.fill: parent; anchors.margins: -Style.space(3)
                radius: width / 2; color: "transparent"
                border.width: Style.space(1.5)
                border.color: Util.alpha(root.ink, 0.85)
                visible: tick.currentTrack
              }
              MouseArea {
                id: tickHit
                anchors.fill: parent; anchors.margins: -Style.space(4)
                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: root.pickDisc(tick.index)
                onWheel: event => wheelInput.handleWheel(event)
              }
            }
          }
          }
        }
        MouseArea {
          id: wheelInput
          anchors.fill: parent; acceptedButtons: Qt.NoButton; z: -1
          property real travel: 0
          function handleWheel(event) {
            travel += event.angleDelta.y || event.angleDelta.x || event.pixelDelta.y || event.pixelDelta.x
            if (Math.abs(travel) >= 100) { root.browse(travel < 0 ? 1 : -1); travel = 0 }
            event.accepted = true
          }
          onWheel: event => handleWheel(event)
        }
      }

      // ---- the wheel's mirror (Dial) -----------------------------------------
      // The strip of the wheel just above the cut, flipped upside down below
      // it, blurred and fading away: the discs look as if they stand on
      // glass, so the bottom edge is no longer a hard straight line.
      Item {
        id: wheelReflection
        visible: root.dial && root.albumBackdrop !== undefined
        x: carousel.x
        y: carousel.y + carousel.height
        width: carousel.width
        height: Style.space(26)
        opacity: 0.45
        layer.enabled: visible
        layer.effect: MultiEffect {
          autoPaddingEnabled: false
          blurEnabled: true; blur: 0.45; blurMax: 24
          maskEnabled: true; maskSource: wheelReflectionFade
        }
        ShaderEffectSource {
          anchors.fill: parent
          sourceItem: root.dial ? wheelContent : null
          sourceRect: Qt.rect(0, wheelContent.height - wheelReflection.height, wheelContent.width, wheelReflection.height)
          live: true
          hideSource: false
          transform: Scale { origin.y: wheelReflection.height / 2; yScale: -1 }
        }
      }
      Rectangle {
        id: wheelReflectionFade
        width: wheelReflection.width; height: wheelReflection.height
        visible: false
        layer.enabled: true
        gradient: Gradient {
          GradientStop { position: 0; color: "white" }
          GradientStop { position: 1; color: "transparent" }
        }
      }

      // ---- the flying disc (Dial) -------------------------------------------
      // Above the clipped wheel so the disc is never cut off. A copy of the
      // cover (the lid) sits on top of the disc so it slides in behind it.
      Item {
        id: flightLayer
        x: carousel.x; y: carousel.y
        width: carousel.width; height: carousel.height
        visible: root.dial

        // A disc dropped back to the wheel when another one is picked.
        Item {
          id: ghost
          visible: drop.running
          property int idx: -1
          property string source: ""
          property real fx: 0
          property real fy: 0
          property real fs: 0
          property real p: 0
          readonly property var home: idx >= 0 ? dialArt.geom(idx) : ({ x: fx, y: fy, s: fs })
          x: fx + (home.x - fx) * p
          y: fy + (home.y - fy) * p
          width: fs + (home.s - fs) * p
          height: width
          opacity: 1 - p * 0.4
          function start() {
            idx = disc.flyIndex; source = disc.source
            fx = disc.x; fy = disc.y; fs = disc.width
            p = 0; drop.restart()
          }
          NumberAnimation { id: drop; target: ghost; property: "p"; from: 0; to: 1; duration: 380; easing.type: Easing.InOutCubic }
          Rectangle { id: ghostMask; anchors.fill: parent; radius: width / 2; visible: false; layer.enabled: true; color: "white" }
          Image {
            anchors.fill: parent; source: ghost.source
            sourceSize: Qt.size(512, 512); fillMode: Image.PreserveAspectCrop; smooth: true; mipmap: true
            layer.enabled: true; layer.effect: MultiEffect { maskEnabled: true; maskSource: ghostMask }
          }
        }

        Item {
          id: disc
          visible: dialArt.airborne
          property int flyIndex: -1
          property string source: ""
          property real sx: 0
          property real sy: 0
          property real ss: 0
          // Scales with the cover (compact and small players).
          readonly property real midSize: Style.space(200) * root.k
          readonly property real midX: (dialArt.width - midSize) / 2
          readonly property real midY: dialArt.bigY + dialArt.bigSize - midSize * 0.58
          readonly property real endY: dialArt.bigY + (dialArt.bigSize - midSize) / 2
          property real rise: 0
          property real slide: 0
          width: ss + (midSize - ss) * rise
          height: width
          x: sx + (midX - sx) * rise
          y: sy + (midY - sy) * rise + (endY - midY) * slide
          // Higher off the wheel = softer, further shadow.
          RectangularShadow {
            anchors.fill: parent; radius: width / 2
            blur: Style.space(4) + Style.space(22) * Math.min(1, disc.rise)
            offset: Qt.vector2d(0, Style.space(2) + Style.space(12) * Math.min(1, disc.rise))
            color: Util.alpha("black", 0.30 + 0.25 * Math.min(1, disc.rise))
          }
          Rectangle { id: discMask; anchors.fill: parent; radius: width / 2; visible: false; layer.enabled: true; color: "white" }
          Image {
            anchors.fill: parent
            source: disc.source
            sourceSize: Qt.size(512, 512)
            asynchronous: true; fillMode: Image.PreserveAspectCrop; smooth: true; mipmap: true
            layer.enabled: true
            layer.effect: MultiEffect { maskEnabled: true; maskSource: discMask }
          }
          // A faint rainbow sheen, like light on a real CD, drifting as it moves.
          Canvas {
            id: sheen
            anchors.fill: parent
            opacity: 0.16
            rotation: 40 + disc.rise * 70 + disc.slide * 50
            onWidthChanged: requestPaint()
            onPaint: {
              const c = getContext("2d")
              c.reset()
              const r = width / 2
              const gr = c.createConicalGradient(r, r, 0)
              const hues = ["#ff4d6d", "#ffd166", "#06d6a0", "#4cc9f0", "#9b5de5", "#ff4d6d", "#ffd166", "#06d6a0", "#4cc9f0", "#9b5de5", "#ff4d6d"]
              for (let i = 0; i < hues.length; i++) gr.addColorStop(i / (hues.length - 1), hues[i])
              c.fillStyle = gr
              c.beginPath()
              c.arc(r, r, r, 0, Math.PI * 2)
              c.arc(r, r, r * 0.2, 0, Math.PI * 2, true)
              c.fill()
            }
          }
          Rectangle {
            anchors.centerIn: parent
            width: parent.width * 0.34; height: width; radius: width / 2
            color: Util.alpha("white", 0.16)
            border.width: Math.max(1, parent.width * 0.012); border.color: Util.alpha("white", 0.42)
          }
          Rectangle {
            anchors.centerIn: parent
            width: parent.width * 0.12; height: width; radius: width / 2
            color: "#1a1a1f"
            border.width: Math.max(1, parent.width * 0.01); border.color: Util.alpha("white", 0.35)
          }
        }

        // The lid: the old cover drawn over the disc while it goes in,
        // casting its shadow onto it.
        Item {
          id: lid
          visible: dialArt.holding
          readonly property var heldBig: bigCovers.count > dialArt.heldRow && dialArt.heldRow >= 0 ? bigCovers.itemAt(dialArt.heldRow) : null
          width: dialArt.bigSize; height: width
          x: (dialArt.width - width) / 2
          y: dialArt.bigY
          scale: (heldBig ? heldBig.pauseFactor : 1) * dialArt.bump
          RectangularShadow {
            anchors.fill: parent; radius: Style.space(14)
            blur: Style.space(26); offset: Qt.vector2d(0, Style.space(10))
            color: "#8c000000"
          }
          Rectangle { id: lidMask; anchors.fill: parent; radius: Style.space(14); visible: false; layer.enabled: true; color: "white" }
          Rectangle { anchors.fill: parent; radius: Style.space(14); color: Commons.Color.background }
          Image {
            anchors.fill: parent
            source: lid.visible ? root.sharpCover(root.heldThumb) : ""
            sourceSize: Qt.size(Math.ceil(width * Screen.devicePixelRatio), Math.ceil(height * Screen.devicePixelRatio))
            asynchronous: true; fillMode: Image.PreserveAspectCrop; smooth: true; mipmap: true
            layer.enabled: true
            layer.effect: MultiEffect { maskEnabled: true; maskSource: lidMask }
          }
        }

        SequentialAnimation {
          id: flight
          PropertyAction { target: disc; properties: "rise,slide,rotation"; value: 0 }
          // The whole wheel turns until the picked disc faces the top...
          NumberAnimation { id: turnAnim; target: dialArt; property: "turnPos"; easing.type: Easing.InOutCubic }
          ScriptAction { script: dialArt.liftOff() }
          // ...then it lifts and grows with a spring-like settle at the top. (Timed
          // curves: a sequence cannot wait on a true spring animation.)
          NumberAnimation { target: disc; property: "rise"; to: 1; duration: 640; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
          // Slide up behind the cover, stopping at the slot's rim...
          NumberAnimation { target: disc; property: "slide"; to: 0.72; duration: 440; easing.type: Easing.InOutCubic }
          ScriptAction { script: dialArt.arrive() }
        }
        // The quick finish of a flight (dialArt.hurry): the wheel finishes
        // turning, the disc lifts and slides to the slot in one move.
        SequentialAnimation {
          id: rush
          NumberAnimation { id: rushTurn; target: dialArt; property: "turnPos"; easing.type: Easing.OutCubic }
          ScriptAction { script: if (!dialArt.airborne) dialArt.liftOff() }
          ParallelAnimation {
            NumberAnimation { target: disc; property: "rise"; to: 1; duration: 240; easing.type: Easing.OutCubic }
            NumberAnimation { target: disc; property: "slide"; to: 0.72; duration: 240; easing.type: Easing.InOutCubic }
          }
          ScriptAction { script: dialArt.arrive() }
        }
        // ...where it spins up like a CD being read until the new song is
        // actually playing (at most 5 s), then drops in, so the art and the
        // colours arrive together with the music.
        Timer {
          id: readWait
          interval: 30; repeat: true
          property int waited: 0
          onTriggered: {
            waited += interval
            if (!root.loadingSong || waited > 5000) { stop(); dialArt.reading = false; landing.restart() }
          }
        }
        NumberAnimation {
          target: disc; property: "rotation"; from: 0; to: 360; duration: 700
          loops: Animation.Infinite; running: dialArt.reading
        }
        SequentialAnimation {
          id: landing
          NumberAnimation { target: disc; property: "slide"; to: 1; duration: 200; easing.type: Easing.InCubic }
          // The cover dips as it takes the disc...
          NumberAnimation { target: dialArt; property: "bump"; to: 0.965; duration: 130; easing.type: Easing.OutCubic }
          ScriptAction { script: { dialArt.prevRow = dialArt.heldRow; root.flowR = 0; root.flowSpin = -60; root.flowActive = true; dialArt.reveal = 0; dialArt.grow = 0; dialArt.holding = false; dialArt.airborne = false } }
          // ...then one flow: a small dot in the middle of the cover grows
          // into a circle that fills the cover and carries straight on out
          // into the background, all one circle, eased in and out. The art
          // and the colours turn together, clockwise, starting at the
          // playing CD's speed (40°/s: OutQuad over 3 s from 60°) and
          // slowing evenly to the backdrop's slow drift as the fill ends.
          ParallelAnimation {

            NumberAnimation { target: root; property: "flowR"; from: 0; to: backdrop.bgReach; duration: 3000; easing.type: Easing.InOutSine }
            NumberAnimation { target: root; property: "flowSpin"; to: 0; duration: 3000; easing.type: Easing.OutQuad }
            NumberAnimation { target: dialArt; property: "grow"; to: 1; duration: 1000; easing.type: Easing.OutCubic }
            NumberAnimation { target: dialArt; property: "bump"; to: 1; duration: 380; easing.type: Easing.OutCubic }
          }
          ScriptAction { script: { root.flowActive = false; dialArt.reveal = 1; backdrop.finishFlow(); dialArt.prevRow = -1; disc.flyIndex = -1; dialArt.oldOutside = false } }
        }
      }

      // ---- title · artist · like ------------------------------------------
      Column {
        id: controls
        // White controls on milky glass: a soft shadow keeps them readable
        // over pale wallpapers.
        layer.enabled: root.milky
        layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "#000000"; shadowOpacity: 0.35; shadowBlur: 0.35; shadowVerticalOffset: 1 }
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: carousel.bottom
        anchors.topMargin: root.compact ? Style.space(12) : Style.space(18)
        anchors.leftMargin: root.small ? Style.space(16) : Style.space(24)
        anchors.rightMargin: root.small ? Style.space(16) : Style.space(24)
        spacing: Style.space(4)

        Item {
          width: parent.width
          // Both artwork styles: the title and artist sit centred, with the
          // ••• on the left and the heart on the right, so Dial and Flow
          // only differ in the artwork itself.
          height: Math.max(titleBlock.height, dialLike.height)

          Column {
            id: titleBlock
            anchors.left: dialMore.right
            anchors.leftMargin: Style.space(6)
            anchors.right: dialLike.left
            anchors.rightMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            // A new song's title and artist fade up into place.
            property string key: root.shownTitle + "\u0001" + root.shownArtist
            onKeyChanged: textIn.restart()
            transform: Translate { id: textShift }
            ParallelAnimation {
              id: textIn
              NumberAnimation { target: titleBlock; property: "opacity"; from: 0; to: 1; duration: 420; easing.type: Easing.OutCubic }
              NumberAnimation { target: textShift; property: "y"; from: Style.space(8); to: 0; duration: 520; easing.type: Easing.OutCubic }
            }

            // Long titles drift sideways instead of being cut off.
            Item {
              id: titleClip
              width: parent.width
              height: titleText.implicitHeight
              clip: true
              readonly property real overflow: Math.max(0, titleText.implicitWidth - width)
              Text {
                id: titleText
                width: Math.max(implicitWidth, titleClip.width)
                horizontalAlignment: Text.AlignHCenter
                text: root.shownTitle
                textFormat: Text.PlainText
                color: root.ink
                font.family: root.family
                font.pixelSize: Style.font.title
                font.weight: Font.DemiBold
                font.letterSpacing: -0.35
                font.underline: titleLink.containsMouse
                onTextChanged: { x = 0; marquee.restart() }
                SequentialAnimation on x {
                  id: marquee
                  running: root.opened && titleClip.overflow > 0
                  loops: Animation.Infinite
                  PauseAnimation { duration: 2200 }
                  NumberAnimation { to: -titleClip.overflow; duration: Math.max(1500, titleClip.overflow * 28); easing.type: Easing.InOutSine }
                  PauseAnimation { duration: 1600 }
                  NumberAnimation { to: 0; duration: 500; easing.type: Easing.OutCubic }
                }
              }
              // Click the title: its album (or the song in the queue).
              MouseArea {
                id: titleLink
                readonly property real textLeft: titleText.x + (titleText.width - titleText.contentWidth) * 0.5
                x: Math.max(0, textLeft)
                width: Math.min(parent.width, titleText.contentWidth)
                height: parent.height
                enabled: !!root.linkSong
                hoverEnabled: true
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.openTitle()
              }
            }
            Text {
              width: parent.width
              visible: !artistLinks.visible
              text: root.shownArtist
              textFormat: Text.PlainText
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideRight
              color: root.inkSoft
              font.family: root.family
              font.pixelSize: Style.font.body
            }
            // Each artist name is its own link to that artist's page.
            Item {
              id: artistLinks
              width: parent.width
              height: artistRow.implicitHeight
              visible: root.linkArtists.length > 0
              clip: true
              Row {
                id: artistRow
                x: Math.max(0, (parent.width - width) / 2)
                Repeater {
                  model: root.linkArtists
                  delegate: Row {
                    id: artistPart
                    required property var modelData
                    required property int index
                    Text {
                      id: artistName
                      text: artistPart.modelData.name
                      textFormat: Text.PlainText
                      color: artistHit.containsMouse && artistPart.modelData.id ? root.ink : root.inkSoft
                      Behavior on color { ColorAnimation { duration: 120 } }
                      font.family: root.family
                      font.pixelSize: Style.font.body
                      font.underline: artistHit.containsMouse && !!artistPart.modelData.id
                      MouseArea {
                        id: artistHit
                        anchors.fill: parent
                        enabled: !!artistPart.modelData.id
                        hoverEnabled: true
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: root.openArtist(artistPart.modelData)
                      }
                    }
                    Text {
                      visible: artistPart.index < root.linkArtists.length - 1
                      text: ", "
                      color: root.inkSoft
                      font.family: root.family
                      font.pixelSize: Style.font.body
                    }
                  }
                }
              }
            }
            Text {
              width: parent.width
              // Only short messages ("Link copied") and errors: no how-to hints.
              visible: root.notice !== "" || root.browseError !== ""
              text: root.notice !== "" ? root.notice : root.browseError
              textFormat: Text.PlainText
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideRight
              color: root.inkFaint
              font.family: root.family
              font.pixelSize: Style.font.caption
            }
          }

          // Dial: ••• at the left edge and the heart at the right, the centred
          // title between them (the bars below run the full width, as in Flow).
          SymbolButton {
            id: dialMore
            visible: true
            anchors.left: parent.left
            anchors.leftMargin: -Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            icon: "more"
            glyphSize: Style.space(18)
            glyphColor: root.moreOpen ? root.ink : root.inkSoft
            tip: "More"
            enabled: root.hasTrack
            onClicked: root.openMore(dialMore)
          }
          SymbolButton {
            id: dialLike
            visible: true
            anchors.right: parent.right
            anchors.rightMargin: -Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            readonly property bool liked: !!(root.svc && root.svc.like === "LIKE")
            icon: liked ? "heart-fill" : "heart"
            glyphSize: Style.space(20)
            glyphColor: liked ? root.ink : root.inkSoft
            tip: liked ? "Unlike song" : "Like song"
            enabled: root.hasTrack && !root.svc.isAd
            onClicked: { if (!root.svc) return; if (!liked) root.likeSwirl(); else root.unlikeSwirl(); root.svc.toggleLike() }
          }
          Views2.HeartSwirl {
            id: dialLikeSwirl
            anchors.centerIn: dialLike
            z: 20
            size: dialLike.glyphSize
            tint: root.swirlTint
            Connections {
              target: root
              function onSwirlRequested() { if (dialLike.visible) dialLikeSwirl.play() }
              function onDrainRequested() { if (dialLike.visible) dialLikeSwirl.drain() }
            }
          }
          SymbolButton {
            id: flowMore
            visible: false
            anchors.right: likeButton.left
            anchors.verticalCenter: parent.verticalCenter
            icon: "more"
            glyphSize: Style.space(18)
            glyphColor: root.moreOpen ? root.ink : root.inkSoft
            tip: "More"
            enabled: root.hasTrack
            onClicked: root.openMore(flowMore)
          }
          SymbolButton {
            id: likeButton
            visible: false
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            readonly property bool liked: !!(root.svc && root.svc.like === "LIKE")
            icon: liked ? "heart-fill" : "heart"
            glyphSize: Style.space(20)
            glyphColor: liked ? root.ink : root.inkSoft
            tip: liked ? "Unlike song" : "Like song"
            enabled: root.hasTrack && !root.svc.isAd
            onClicked: { if (!root.svc) return; if (!liked) root.likeSwirl(); else root.unlikeSwirl(); root.svc.toggleLike() }
          }
          Views2.HeartSwirl {
            id: likeButtonSwirl
            anchors.centerIn: likeButton
            z: 20
            size: likeButton.glyphSize
            tint: root.swirlTint
            Connections {
              target: root
              function onSwirlRequested() { if (likeButton.visible) likeButtonSwirl.play() }
              function onDrainRequested() { if (likeButton.visible) likeButtonSwirl.drain() }
            }
          }
        }

        Item { width: 1; height: Style.space(6) }

        // ---- progress ------------------------------------------------------
        Item {
          width: parent.width
          height: progress.implicitHeight
          // Room at both ends on the Dial, so the line stays centred with the
          // heart at its right.
          readonly property real inset: 0
        LineSlider {
          id: progress
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.leftMargin: parent.inset
          anchors.rightMargin: parent.inset
          anchors.verticalCenter: parent.verticalCenter
          minimum: 0
          maximum: root.svc ? Math.max(1, root.svc.duration) : 1
          value: root.svc ? root.svc.position : 0
          fillColor: root.ink
          // Compact: a thin line that only shows how far in the song is.
          enabled: !root.compact && root.hasTrack && !root.svc.isAd && root.svc.duration > 0
          opacity: root.compact ? 0.8 : 1
          onReleased: v => { if (root.svc) root.svc.seek(v) }
        }
        }
        Item {
          visible: !root.compact
          width: parent.width
          height: elapsed.implicitHeight
          readonly property real inset: 0
          readonly property real shownPosition: progress.dragging ? progress.liveValue : root.svc ? root.svc.position : 0
          Text {
            id: elapsed
            anchors.left: parent.left
            anchors.leftMargin: parent.inset
            text: Model.fmtTime(parent.shownPosition)
            color: root.inkSoft
            font.family: root.family; font.pixelSize: Style.font.caption
            font.features: { "tnum": 1 }
          }
          Text {
            anchors.right: parent.right
            anchors.rightMargin: parent.inset
            text: "-" + Model.fmtTime(Math.max(0, (root.svc ? root.svc.duration : 0) - parent.shownPosition))
            color: root.inkSoft
            font.family: root.family; font.pixelSize: Style.font.caption
            font.features: { "tnum": 1 }
          }
          // Quality badge, like Apple Music's Lossless pill: the stream's
          // format, shown once the engine reports it.
          Rectangle {
            id: qualityBadge
            readonly property string itag: root.hasTrack && root.svc.player ? String(root.svc.player.audioItag || "") : ""
            readonly property var names: ({
              "774": "HIGH QUALITY \u00b7 OPUS 256", "141": "HIGH QUALITY \u00b7 AAC 256",
              "251": "OPUS \u00b7 160 KBPS", "140": "AAC \u00b7 128 KBPS",
              "250": "OPUS \u00b7 70 KBPS", "249": "OPUS \u00b7 50 KBPS", "139": "AAC \u00b7 48 KBPS" })
            readonly property string label: names[itag] || ""
            anchors.centerIn: parent
            visible: label !== ""
            width: badgeText.implicitWidth + Style.space(12)
            height: badgeText.implicitHeight + Style.space(4)
            radius: Style.space(4)
            color: "transparent"
            border.width: 1
            border.color: Util.alpha(root.ink, 0.35)
            Text {
              id: badgeText
              anchors.centerIn: parent
              text: qualityBadge.label
              textFormat: Text.PlainText
              color: root.inkSoft
              font.family: root.family
              font.pixelSize: Math.max(8, Style.font.caption - 2)
              font.weight: Font.DemiBold
              font.letterSpacing: 0.6
            }
          }
        }

        // ---- transport -----------------------------------------------------
        Item {
          width: parent.width
          height: root.compact ? Style.space(56) : Style.space(64)
          Row {
            anchors.centerIn: parent
            spacing: root.small ? Style.space(18) : Style.space(30)
            scale: root.small ? 0.82 : root.compact ? 0.9 : 1
            SymbolButton {
              anchors.verticalCenter: parent.verticalCenter
              size: Style.space(50); glyphSize: Style.space(30)
              icon: "previous"; tip: "Previous"
              enabled: root.hasTrack
              onClicked: if (root.svc) root.svc.previous()
            }
            SymbolButton {
              anchors.verticalCenter: parent.verticalCenter
              size: Style.space(64); glyphSize: Style.space(38)
              icon: root.playing || root.loadingSong ? "pause" : "play"
              tip: root.svc && root.svc.isPlaying ? "Pause" : "Play"
              enabled: root.hasTrack
              onClicked: if (root.svc) root.svc.togglePlaying()
            }
            SymbolButton {
              anchors.verticalCenter: parent.verticalCenter
              size: Style.space(50); glyphSize: Style.space(30)
              icon: "next"; tip: "Next"
              enabled: root.hasTrack
              onClicked: if (root.svc) root.svc.next()
            }
          }
        }

        // ---- volume --------------------------------------------------------
        Item {
          visible: !root.compact
          width: parent.width
          height: Style.space(28)
          Views2.Glyph {
            id: volLow
            anchors.right: volSlider.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            name: root.svc && (root.svc.muted || root.svc.volume === 0) ? "volume-mute" : "volume-low"
            color: root.inkSoft
            size: Style.space(16)
            MouseArea {
              anchors.fill: parent; anchors.margins: -Style.space(4)
              cursorShape: Qt.PointingHandCursor
              onClicked: if (root.svc) root.svc.toggleMute()
            }
          }
          // Same ends as the progress line (inset on the Dial); the speaker
          // icons sit just outside it.
          LineSlider {
            id: volSlider
            readonly property real inset: Style.space(26)
            anchors.left: parent.left
            anchors.leftMargin: inset
            anchors.right: parent.right
            anchors.rightMargin: inset
            anchors.verticalCenter: parent.verticalCenter
            minimum: 0; maximum: 100
            value: root.svc ? (root.svc.muted ? 0 : root.svc.volume) : 0
            fillColor: root.ink
            enabled: !!root.svc
            wheelStep: 5
            onMoved: v => { if (root.svc) root.svc.setVolume(Math.round(v)) }
          }
          Views2.Glyph {
            id: volHigh
            anchors.left: volSlider.right
            anchors.leftMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            name: "volume-high"
            color: root.inkSoft
            size: Style.space(16)
          }
        }

        Item { width: 1; height: Style.space(6) }

        // ---- lyrics · output · queue · search · design ---------------------
        Item {
          visible: !root.compact
          width: parent.width
          height: Style.space(40)
          Row {
            anchors.centerIn: parent
            spacing: Style.space(26)
            SymbolButton { icon: "queue"; tip: "Queue"; glyphColor: root.inkSoft; onClicked: root.libraryRequested("queue") }
            SymbolButton { icon: "search"; tip: "Library and search"; glyphColor: root.inkSoft; onClicked: root.libraryRequested("search") }
            SymbolButton { icon: "lyrics"; tip: "Lyrics"; glyphColor: root.inkSoft; onClicked: root.libraryRequested("lyrics") }
            SymbolButton { icon: "output"; tip: "Play music on…"; glyphColor: root.outputOpen || (root.svc && root.svc.musicOutput !== "") ? root.ink : root.inkSoft; onClicked: root.openOutputPicker() }
          }
        }
      }

      // ---- first launch overlay ----------------------------------------------
      Item {
        id: welcome
        anchors.fill: parent
        z: 50
        opacity: root.welcomeMode !== "" ? 1 : 0
        visible: opacity > 0.01
        // The first song's artwork fades in from under the gradient.
        Behavior on opacity { NumberAnimation { duration: 700; easing.type: Easing.InOutQuad } }
        // Swallow pointer input meant for the player underneath.
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: event => { event.accepted = true } }

        // Drifting violet / magenta / teal light on a deep base.
        Rectangle { anchors.fill: parent; color: "#1c1830" }
        Canvas {
          id: glow
          anchors.centerIn: parent
          width: Math.hypot(parent.width, parent.height) * 1.25
          height: width
          onWidthChanged: requestPaint()
          onPaint: {
            const c = getContext("2d")
            c.reset()
            const w = width
            const blob = function (x, y, r, col) {
              const g = c.createRadialGradient(x * w, y * w, 0, x * w, y * w, r * w)
              g.addColorStop(0, col)
              g.addColorStop(1, "rgba(28,24,48,0)")
              c.fillStyle = g
              c.fillRect(0, 0, w, w)
            }
            blob(0.36, 0.34, 0.36, "rgba(91,75,214,0.95)")
            blob(0.68, 0.42, 0.32, "rgba(192,69,143,0.80)")
            blob(0.46, 0.72, 0.36, "rgba(31,143,154,0.85)")
          }
          RotationAnimator on rotation {
            from: 0; to: 360; duration: 70000; loops: Animation.Infinite
            running: welcome.visible && root.opened && !root.reduceMotion
          }
          SequentialAnimation on scale {
            loops: Animation.Infinite
            running: welcome.visible && root.opened && !root.reduceMotion
            NumberAnimation { from: 1.0; to: 1.18; duration: 14000; easing.type: Easing.InOutSine }
            NumberAnimation { from: 1.18; to: 1.0; duration: 14000; easing.type: Easing.InOutSine }
          }
        }
        Rectangle {
          anchors.fill: parent
          gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0.08, 0.07, 0.12, 0.10) }
            GradientStop { position: 0.6; color: Qt.rgba(0.08, 0.07, 0.12, 0.50) }
            GradientStop { position: 1.0; color: Qt.rgba(0.08, 0.07, 0.12, 0.72) }
          }
        }

        // ---- before sign-in ----
        Column {
          visible: root.welcomeMode === "signin"
          anchors.horizontalCenter: parent.horizontalCenter
          y: Style.space(46)
          width: parent.width - Style.space(56)
          spacing: Style.space(10)
          Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Style.space(176); height: width
            radius: Style.space(16)
            color: Qt.rgba(1, 1, 1, 0.10)
            border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.18)
            Views2.Glyph { anchors.centerIn: parent; name: "note"; size: Style.space(64); color: Qt.rgba(1, 1, 1, 0.75) }
          }
          Item { width: 1; height: Style.space(12) }
          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "Welcome to Spinbloom"
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: "white"
            font.family: root.family
            font.pixelSize: Math.round(Style.font.title * 1.15)
            font.weight: Font.DemiBold
            font.letterSpacing: -0.4
          }
          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.svc && root.svc.signingIn ? "Finish signing in in the window that opened."
              : "All of YouTube Music, right in your bar. Sign in to bring your library, likes and playlists."
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            lineHeight: 1.2
            color: Qt.rgba(1, 1, 1, 0.72)
            font.family: root.family
            font.pixelSize: Style.font.body
          }
          Item { width: 1; height: Style.space(10) }
          Rectangle {
            id: signInButton
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !(root.svc && root.svc.signingIn)
            width: signInRow.width + Style.space(36)
            height: Style.space(40)
            radius: height / 2
            color: signInHit.containsMouse ? Qt.rgba(1, 1, 1, 0.88) : "white"
            scale: signInHit.pressed ? 0.96 : 1
            Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
            Row {
              id: signInRow
              anchors.centerIn: parent
              spacing: Style.space(8)
              Views2.Glyph { anchors.verticalCenter: parent.verticalCenter; name: "artist"; size: Style.space(16); color: "#1c1830" }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Sign in to YouTube Music"
                textFormat: Text.PlainText
                color: "#1c1830"
                font.family: root.family
                font.pixelSize: Style.font.body
                font.weight: Font.DemiBold
              }
            }
            MouseArea {
              id: signInHit
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: { if (root.welcomePreview !== "") return; if (root.svc) root.svc.signIn() }
            }
          }
          LoadingRing { anchors.horizontalCenter: parent.horizontalCenter; visible: !!(root.svc && root.svc.signingIn) }
        }

        // ---- signed in, nothing played yet ----
        Column {
          visible: root.welcomeMode === "pick"
          anchors.horizontalCenter: parent.horizontalCenter
          y: Style.space(34)
          width: parent.width - Style.space(44)
          spacing: Style.space(10)
          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "Pick something to play"
            textFormat: Text.PlainText
            color: "white"
            font.family: root.family
            font.pixelSize: Math.round(Style.font.title * 1.15)
            font.weight: Font.DemiBold
            font.letterSpacing: -0.4
          }
          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "Search for any song, or start with one of your mixes."
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: Qt.rgba(1, 1, 1, 0.72)
            font.family: root.family
            font.pixelSize: Style.font.body
          }
          Item { width: 1; height: Style.space(4) }
          // Search: Enter opens the full player with the results.
          Rectangle {
            width: parent.width
            height: Style.space(38)
            radius: Style.space(10)
            color: welcomeSearch.activeFocus ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(1, 1, 1, 0.13)
            border.width: 1; border.color: Qt.rgba(1, 1, 1, welcomeSearch.activeFocus ? 0.30 : 0.14)
            Behavior on color { ColorAnimation { duration: 140 } }
            Views2.Glyph {
              id: welcomeSearchIcon
              anchors.left: parent.left; anchors.leftMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              name: "search"; size: Style.space(15); color: Qt.rgba(1, 1, 1, 0.7)
            }
            TextInput {
              id: welcomeSearch
              anchors.left: welcomeSearchIcon.right; anchors.leftMargin: Style.space(9)
              anchors.right: parent.right; anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              color: "white"
              selectionColor: Qt.rgba(1, 1, 1, 0.35)
              font.family: root.family
              font.pixelSize: Style.font.body
              clip: true
              Text {
                visible: welcomeSearch.text === ""
                anchors.verticalCenter: parent.verticalCenter
                text: "Songs, albums, artists"
                textFormat: Text.PlainText
                color: Qt.rgba(1, 1, 1, 0.5)
                font: welcomeSearch.font
              }
              Keys.onReturnPressed: { const q = text.trim(); if (q) { root.searchRequested(q); text = "" } }
              Keys.onEnterPressed: { const q = text.trim(); if (q) { root.searchRequested(q); text = "" } }
              Keys.onEscapePressed: { if (text !== "") text = ""; else root.close() }
            }
          }
          Item { width: 1; height: Style.space(4) }
          Grid {
            id: starterGrid
            width: parent.width
            columns: 3
            columnSpacing: Style.space(10)
            rowSpacing: Style.space(10)
            readonly property real tile: (width - columnSpacing * 2) / 3
            Repeater {
              model: root.starters
              delegate: Item {
                id: starter
                required property var modelData
                width: starterGrid.tile
                height: starterGrid.tile + Style.space(20)
                property real lift: starterHit.containsMouse ? 1 : 0
                Behavior on lift { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                Rectangle { id: starterMask; width: starterGrid.tile; height: width; radius: Style.space(9); visible: false; layer.enabled: true; color: "white" }
                Item {
                  width: starterGrid.tile; height: width
                  y: -starter.lift * Style.space(3)
                  scale: 1 + starter.lift * 0.03
                  RectangularShadow { anchors.fill: parent; radius: Style.space(9); blur: Style.space(12); offset: Qt.vector2d(0, Style.space(4)); color: "#55000000" }
                  Rectangle { anchors.fill: parent; radius: Style.space(9); color: Qt.rgba(1, 1, 1, 0.1) }
                  Image {
                    anchors.fill: parent
                    source: root.sharpCover(starter.modelData.thumb || "")
                    sourceSize: Qt.size(256, 256)
                    asynchronous: true; fillMode: Image.PreserveAspectCrop; smooth: true
                    layer.enabled: true
                    layer.effect: MultiEffect { maskEnabled: true; maskSource: starterMask }
                  }
                }
                Text {
                  y: starterGrid.tile + Style.space(5)
                  width: parent.width
                  text: starter.modelData.title || ""
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  color: Qt.rgba(1, 1, 1, 0.88)
                  font.family: root.family
                  font.pixelSize: Style.font.caption
                }
                MouseArea {
                  id: starterHit
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.startTile(starter.modelData)
                }
              }
            }
          }
          LoadingRing { anchors.horizontalCenter: parent.horizontalCenter; visible: root.starters.length === 0 }
        }

        // The controls, greyed out until there is something to play.
        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(26)
          spacing: Style.space(40)
          opacity: 0.28
          Views2.Glyph { anchors.verticalCenter: parent.verticalCenter; name: "previous"; size: Style.space(24); color: "white" }
          Views2.Glyph { anchors.verticalCenter: parent.verticalCenter; name: "play"; size: Style.space(32); color: "white" }
          Views2.Glyph { anchors.verticalCenter: parent.verticalCenter; name: "next"; size: Style.space(24); color: "white" }
        }
      }

      // ---- blur tip (once) -----------------------------------------------------
      // Hyprland blur is off (Omarchy's default): the glass is solid. A small
      // one-time tip offers real frosted glass ("Use desktop blur"); either
      // button puts it away for good.
      Rectangle {
        id: blurTip
        readonly property bool wanted: !!root.svc && !!root.svc.glass && root.svc.glass.known
          && !root.svc.glass.compositor && !root.svc.glass.wantDesktopBlur
          && String(root.svc.setting("blurTipSeen", false)) !== "true" && !welcome.visible
        z: 40
        visible: opacity > 0.01
        opacity: wanted && root.opened ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
        anchors.horizontalCenter: parent.horizontalCenter
        y: Style.space(10)
        width: tipRow.implicitWidth + Style.space(20)
        height: Style.space(32)
        radius: height / 2
        color: Util.alpha("#1c1d24", 0.92)
        border.width: 1
        border.color: Util.alpha("white", 0.12)
        Row {
          id: tipRow
          anchors.centerIn: parent
          spacing: Style.space(10)
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Want frosted glass?"
            color: Util.alpha("white", 0.85)
            font.family: root.family; font.pixelSize: Style.font.caption
          }
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: onText.implicitWidth + Style.space(16); height: Style.space(22); radius: height / 2
            color: onHit.containsMouse ? "#ffffff" : Util.alpha("white", 0.9)
            Text { id: onText; anchors.centerIn: parent; text: "Turn on blur"; color: "#1c1d24"; font.family: root.family; font.pixelSize: Style.font.caption; font.weight: Font.DemiBold }
            MouseArea {
              id: onHit; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
              onClicked: { root.svc.saveSetting("blurTipSeen", true); root.svc.saveSetting("desktopBlur", true) }
            }
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "✕"
            color: Util.alpha("white", closeHit.containsMouse ? 0.9 : 0.55)
            font.pixelSize: Style.font.caption
            MouseArea {
              id: closeHit; anchors.fill: parent; anchors.margins: -Style.space(6); hoverEnabled: true; cursorShape: Qt.PointingHandCursor
              onClicked: root.svc.saveSetting("blurTipSeen", true)
            }
          }
        }
      }

      // ---- ••• menu overlay ---------------------------------------------------
      // A click anywhere outside the menu closes it.
      MouseArea {
        anchors.fill: parent
        z: 60
        visible: root.moreOpen
        acceptedButtons: Qt.AllButtons
        onClicked: root.moreOpen = false
        onWheel: event => { event.accepted = true }
      }
      Item {
        id: moreMenu
        z: 61
        width: Style.space(250)
        height: moreColumn.height + Style.space(12)
        readonly property bool fromLeft: root.dial
        readonly property point at: root.moreAnchor ? root.moreAnchor.mapToItem(card, 0, 0) : Qt.point(0, 0)
        x: Math.max(Style.space(12), Math.min(card.width - width - Style.space(12),
             fromLeft ? at.x : at.x + (root.moreAnchor ? root.moreAnchor.width : 0) - width))
        y: Math.max(Style.space(12), at.y - height - Style.space(6))
        visible: opacity > 0.01
        opacity: root.moreOpen ? 1 : 0
        scale: root.moreOpen ? 1 : 0.92
        transformOrigin: fromLeft ? Item.BottomLeft : Item.BottomRight
        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
        RectangularShadow {
          anchors.fill: parent; radius: Style.space(14)
          blur: Style.space(24); offset: Qt.vector2d(0, Style.space(8))
          color: "#70000000"
        }
        Rectangle {
          anchors.fill: parent
          radius: Style.space(14)
          color: Util.alpha(root.glassC, 0.97)
          border.width: 1
          border.color: Util.alpha(root.ink, 0.12)
        }
        Column {
          id: moreColumn
          x: Style.space(6); y: Style.space(6)
          width: parent.width - Style.space(12)
          Repeater {
            model: root.moreItems
            delegate: Item {
              id: moreRow
              required property var modelData
              width: moreColumn.width
              height: Style.space(38)
              opacity: modelData.on ? 1 : 0.4
              Rectangle {
                anchors.fill: parent
                radius: Style.space(9)
                color: rowHit.containsMouse && moreRow.modelData.on ? Util.alpha(root.ink, rowHit.pressed ? 0.16 : 0.09) : "transparent"
                Behavior on color { ColorAnimation { duration: 90 } }
              }
              Views2.Glyph {
                id: rowIcon
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                name: moreRow.modelData.icon
                color: root.inkSoft
                size: Style.space(17)
              }
              Text {
                anchors.left: rowIcon.right
                anchors.leftMargin: Style.space(12)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                text: moreRow.modelData.label
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: root.ink
                font.family: root.family
                font.pixelSize: Style.font.body
              }
              MouseArea {
                id: rowHit
                anchors.fill: parent
                hoverEnabled: true
                enabled: moreRow.modelData.on
                cursorShape: Qt.PointingHandCursor
                onClicked: root.moreAction(moreRow.modelData.key)
              }
            }
          }
        }
      }

      // ---- output drawer --------------------------------------------------------
      // Slides up from the bottom of the player, over the controls. Only the
      // music moves; the computer's other sounds keep their device.
      MouseArea {
        anchors.fill: parent
        z: 70
        visible: root.outputOpen
        acceptedButtons: Qt.AllButtons
        onClicked: root.outputOpen = false
        onWheel: event => { event.accepted = true }
      }
      Item {
        id: outputDrawer
        z: 71
        width: parent.width
        height: drawerColumn.height + Style.space(28)
        y: root.outputOpen ? parent.height - height : parent.height + Style.space(12)
        Behavior on y { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
        visible: y < parent.height
        // Swallow clicks on the drawer itself (the catcher above closes it).
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: event => { event.accepted = true } }
        RectangularShadow {
          anchors.fill: drawerBg; radius: Style.space(18)
          blur: Style.space(30); offset: Qt.vector2d(0, -Style.space(4))
          color: "#66000000"
        }
        Rectangle {
          id: drawerBg
          anchors.fill: parent
          anchors.bottomMargin: -Style.space(20)
          radius: Style.space(18)
          color: Util.alpha(root.glassC, 0.97)
          border.width: 1
          border.color: Util.alpha(root.ink, 0.12)
        }
        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          y: Style.space(8)
          width: Style.space(36); height: Style.space(4); radius: height / 2
          color: Util.alpha(root.ink, 0.25)
        }
        Column {
          id: drawerColumn
          x: Style.space(14); y: Style.space(22)
          width: parent.width - Style.space(28)
          spacing: Style.space(2)
          Text {
            leftPadding: Style.space(10)
            bottomPadding: Style.space(6)
            text: "Play music on"
            textFormat: Text.PlainText
            color: root.inkSoft
            font.family: root.family
            font.pixelSize: Style.font.caption
            font.weight: Font.DemiBold
          }
          Repeater {
            model: [{ name: "", label: "Same as computer", sub: root.defaultOutputLabel }]
              .concat(root.svc ? (root.svc.outputs.sinks || []).map(x => ({ name: x.name, label: x.label, sub: "" })) : [])
            delegate: Item {
              id: outRow
              required property var modelData
              readonly property bool chosen: !!root.svc && root.svc.musicOutput === modelData.name
              width: drawerColumn.width
              height: modelData.sub !== "" ? Style.space(48) : Style.space(40)
              Rectangle {
                anchors.fill: parent
                radius: Style.space(10)
                color: outHit.containsMouse ? Util.alpha(root.ink, outHit.pressed ? 0.16 : 0.09) : outRow.chosen ? Util.alpha(root.ink, 0.06) : "transparent"
                Behavior on color { ColorAnimation { duration: 90 } }
              }
              Views2.Glyph {
                id: outIcon
                anchors.left: parent.left; anchors.leftMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                name: outRow.modelData.name === "" ? "output" : "volume-high"
                color: outRow.chosen ? root.ink : root.inkSoft
                size: Style.space(17)
              }
              Column {
                anchors.left: outIcon.right; anchors.leftMargin: Style.space(12)
                anchors.right: outCheck.left; anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                Text {
                  width: parent.width
                  text: outRow.modelData.label
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  color: root.ink
                  font.family: root.family
                  font.pixelSize: Style.font.body
                  font.weight: outRow.chosen ? Font.DemiBold : Font.Normal
                }
                Text {
                  width: parent.width
                  visible: outRow.modelData.sub !== ""
                  text: "Now: " + outRow.modelData.sub
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  color: root.inkSoft
                  font.family: root.family
                  font.pixelSize: Style.font.caption
                }
              }
              Views2.Glyph {
                id: outCheck
                anchors.right: parent.right; anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                name: "check"
                opacity: outRow.chosen ? 1 : 0
                color: root.ink
                size: Style.space(15)
              }
              MouseArea {
                id: outHit
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.pickOutput(outRow.modelData.name)
              }
            }
          }
        }
      }

      // ---- shrink / expand ---------------------------------------------------
      // Switches between the full and the compact player. Shows only while the
      // pointer is over the player, so it never clutters the art.
      SymbolButton {
        id: sizeButton
        z: 60
        x: Style.space(10); y: Style.space(10)
        size: Style.space(30); glyphSize: Style.space(15)
        // Steps through the three sizes: Full → Compact → Small → Full.
        readonly property string nextSize: root.playerSize === "full" ? "compact" : root.playerSize === "compact" ? "small" : "full"
        icon: nextSize === "full" ? "expand" : "shrink"
        tip: nextSize === "full" ? "Full player" : nextSize === "compact" ? "Compact player" : "Small player"
        glyphColor: root.ink
        opacity: cardHover.hovered || sizeButton.activeFocus ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Rectangle {
          anchors.fill: parent; radius: width / 2; z: -1
          color: Util.alpha("black", 0.28)
        }
        onClicked: root.playerSizeRequested(nextSize)
      }

      // ---- sleep timer drawer ----------------------------------------------------
      MouseArea {
        anchors.fill: parent
        z: 74
        visible: root.sleepOpen
        acceptedButtons: Qt.AllButtons
        onClicked: root.sleepOpen = false
        onWheel: event => { event.accepted = true }
      }
      Item {
        id: sleepDrawer
        z: 75
        width: parent.width
        height: sleepColumn.height + Style.space(28)
        y: root.sleepOpen ? parent.height - height : parent.height + Style.space(12)
        Behavior on y { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
        visible: y < parent.height
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: event => { event.accepted = true } }
        RectangularShadow {
          anchors.fill: sleepBg; radius: Style.space(18)
          blur: Style.space(30); offset: Qt.vector2d(0, -Style.space(4))
          color: "#66000000"
        }
        Rectangle {
          id: sleepBg
          anchors.fill: parent
          anchors.bottomMargin: -Style.space(20)
          radius: Style.space(18)
          color: Util.alpha(root.glassC, 0.97)
          border.width: 1
          border.color: Util.alpha(root.ink, 0.12)
        }
        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          y: Style.space(8)
          width: Style.space(36); height: Style.space(4); radius: height / 2
          color: Util.alpha(root.ink, 0.25)
        }
        Column {
          id: sleepColumn
          x: Style.space(14); y: Style.space(22)
          width: parent.width - Style.space(28)
          spacing: Style.space(2)
          Text {
            width: parent.width
            leftPadding: Style.space(10)
            bottomPadding: Style.space(6)
            text: !root.svc || root.svc.sleepMode === "off" ? "Sleep timer"
              : "Sleep timer · " + (root.svc.sleepMode === "end" ? "pauses at the end of this song" : "pauses in " + root.sleepMinutesLeft + " min")
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: root.inkSoft
            font.family: root.family
            font.pixelSize: Style.font.caption
            font.weight: Font.DemiBold
          }
          Repeater {
            model: [["off", "Off"], ["15", "15 minutes"], ["30", "30 minutes"], ["60", "1 hour"], ["end", "End of this song"]]
            delegate: Item {
              id: sleepRow
              required property var modelData
              readonly property bool chosen: !!root.svc && root.svc.sleepMode === modelData[0]
              width: sleepColumn.width
              height: Style.space(40)
              Rectangle {
                anchors.fill: parent
                radius: Style.space(10)
                color: sleepHit.containsMouse ? Util.alpha(root.ink, sleepHit.pressed ? 0.16 : 0.09) : sleepRow.chosen ? Util.alpha(root.ink, 0.06) : "transparent"
                Behavior on color { ColorAnimation { duration: 90 } }
              }
              Views2.Glyph {
                id: sleepIcon
                anchors.left: parent.left; anchors.leftMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                name: sleepRow.modelData[0] === "off" ? "close" : "sleep"
                color: sleepRow.chosen ? root.ink : root.inkSoft
                size: Style.space(16)
              }
              Text {
                anchors.left: sleepIcon.right; anchors.leftMargin: Style.space(12)
                anchors.right: sleepCheck.left; anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: sleepRow.modelData[1]
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: root.ink
                font.family: root.family
                font.pixelSize: Style.font.body
                font.weight: sleepRow.chosen ? Font.DemiBold : Font.Normal
              }
              Views2.Glyph {
                id: sleepCheck
                anchors.right: parent.right; anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                name: "check"
                opacity: sleepRow.chosen ? 1 : 0
                color: root.ink
                size: Style.space(15)
              }
              MouseArea {
                id: sleepHit
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.pickSleep(sleepRow.modelData[0])
              }
            }
          }
        }
      }

      // ---- save-to-playlist drawer --------------------------------------------
      MouseArea {
        anchors.fill: parent
        z: 72
        visible: root.saveOpen
        acceptedButtons: Qt.AllButtons
        onClicked: root.saveOpen = false
        onWheel: event => { event.accepted = true }
      }
      Item {
        id: saveDrawer
        z: 73
        width: parent.width
        height: savePicker.implicitHeight + Style.space(42)
        y: root.saveOpen ? parent.height - height : parent.height + Style.space(12)
        Behavior on y { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
        visible: y < parent.height
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: event => { event.accepted = true } }
        RectangularShadow {
          anchors.fill: saveBg; radius: Style.space(18)
          blur: Style.space(30); offset: Qt.vector2d(0, -Style.space(4))
          color: "#66000000"
        }
        Rectangle {
          id: saveBg
          anchors.fill: parent
          anchors.bottomMargin: -Style.space(20)
          radius: Style.space(18)
          color: Util.alpha(root.glassC, 0.97)
          border.width: 1
          border.color: Util.alpha(root.ink, 0.12)
        }
        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          y: Style.space(8)
          width: Style.space(36); height: Style.space(4); radius: height / 2
          color: Util.alpha(root.ink, 0.25)
        }
        Views2.SaveList {
          id: savePicker
          x: Style.space(14); y: Style.space(22)
          width: parent.width - Style.space(28)
          svc: root.svc
          ink: root.ink
          inkSoft: root.inkSoft
          family: root.family
          maxListHeight: Style.space(320)
          onDone: function (message) { root.saveOpen = false; root.say(message) }
        }
      }

      // Hairline edge, as the Control Center has.
      Rectangle {
        anchors.fill: parent; radius: parent.radius; color: "transparent"
        border.width: 1; border.color: Util.alpha(root.ink, 0.14)
      }
    }
  }
}
