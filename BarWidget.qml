import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "lib/Model.js" as Model
import "lib/Icons.js" as Icons
import "lib/StoredSettings.js" as StoredSettings
import "views2" as Views

// The bar pill: a round cover in a progress ring, the song, and previous /
// play-pause / next. Left click opens the panel, middle click plays or
// pauses, right click skips, the wheel sets the volume (Shift+wheel seeks).
BarWidget {
  id: root
  moduleName: "spinbloom"

  readonly property var svc: bar && bar.shell ? bar.shell.serviceFor("spinbloom") : null

  // Recover settings at cold startup even before the host hands the entry over.
  property var savedSettings: null
  readonly property var effectiveSettings: savedSettings === null ? root.settings : savedSettings
  function displaySetting(name, fallback) {
    const value = effectiveSettings ? effectiveSettings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }
  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.savedSettings = StoredSettings.parse(text(), root.moduleName) }
      catch (error) { console.warn("Spinbloom: could not read saved widget settings") }
    }
  }
  onEffectiveSettingsChanged: { pushSettings(); injectPanel() }

  // The service reads its settings from this widget's shell.json entry,
  // and saves new ones back through the shell's plugin API (Settings).
  // The shell assigns this widget's `bar` before its `settings`, so for a
  // moment `settings` is still the empty default: that is not an entry, and
  // the service must never see it (it would start the engine on defaults).
  function pushSettings() {
    if (!root.svc || !root.bar || !Model.hasSettings(root.effectiveSettings)) return
    if (typeof root.svc.adoptSettings === "function") root.svc.adoptSettings(root.effectiveSettings)
    else root.svc.settings = root.effectiveSettings
    root.svc.shell = root.bar ? root.bar.shell : null
  }
  onSvcChanged: { pushSettings(); injectPanel() }
  onSettingsChanged: { pushSettings(); injectPanel() }
  onBarChanged: { pushSettings(); injectPanel() }
  Component.onCompleted: pushSettings()

  // Spinbloom: the player's typeface (Inter, SIL Open Font License, see
  // fonts/LICENSE.txt) ships inside the plugin, so it looks the same on a
  // plain Omarchy install with no fonts added.
  Repeater {
    model: ["Inter-Regular.ttf", "Inter-Medium.ttf", "Inter-SemiBold.ttf", "Inter-Bold.ttf"]
    delegate: Item {
      id: fontSlot
      required property string modelData
      FontLoader {
        source: Qt.resolvedUrl("fonts/" + fontSlot.modelData)
        onStatusChanged: if (status === FontLoader.Error) console.warn("Spinbloom: font failed to load:", fontSlot.modelData)
      }
    }
  }
  // >>> Spinbloom design switch >>>
  // "Design" setting: "classic" (MiniPlayer.qml, unchanged) or "new"
  // (MiniPlayer2.qml). Only this block and the ring colour below know about it.
  // The Spinbloom design is the only player now (Classic retired 2026-11-19;
  // its files are in ~/.config/omarchy/plugin-backups/spinbloom-classic-design-*).
  readonly property bool newDesign: true
  readonly property var miniPlayer: miniLoader.item
  function setDesign(value) {
    if (!root.bar || !root.bar.shell) return
    var next = Object.assign({}, root.effectiveSettings || {}, { design: value })
    root.bar.shell.updateEntryInline(root.moduleName, next)
  }
  // "Artwork" setting: "dial" (default) or "flow".
  //   omarchy bar set spinbloom artwork dial|flow
  // Dial is the default; Flow only when chosen (right-click the cover).
  readonly property string artworkStyle: String(root.displaySetting("artwork", "dial")) === "flow" ? "flow" : "dial"
  // "Motion" setting: "full" (default) or "reduced" (calm: no flying disc,
  // drifting backdrop or spinning disc).
  //   omarchy-shell spinbloom.player setReduceMotion true|false
  readonly property bool reduceMotion: String(root.displaySetting("motion", "full")) === "reduced"
  // "Player size" setting: "full" (default), "compact" or "small"; and
  // whether compact keeps the CD wheel ("compactWheel", default on).
  //   omarchy-shell spinbloom.player setPlayerSize full|compact|small
  readonly property string playerSize: { const v = String(root.displaySetting("playerSize", "full")); return v === "compact" || v === "small" ? v : "full" }
  readonly property bool compactWheel: String(root.displaySetting("compactWheel", false)) !== "false"
  readonly property string compactKind: String(root.displaySetting("compactKind", "small")) === "small" ? "small" : "compact"
  function setPlayerSize(size) {
    if (!root.bar || !root.bar.shell) return
    var extra = { playerSize: size }
    if (size === "compact" || size === "small") extra.compactKind = size
    root.bar.shell.updateEntryInline(root.moduleName, Object.assign({}, root.effectiveSettings || {}, extra))
  }
  function setCompactWheel(on) {
    if (!root.bar || !root.bar.shell) return
    root.bar.shell.updateEntryInline(root.moduleName, Object.assign({}, root.effectiveSettings || {}, { compactWheel: !!on }))
  }
  function setMotion(reduced) {
    if (!root.bar || !root.bar.shell) return
    var next = Object.assign({}, root.effectiveSettings || {}, { motion: reduced ? "reduced" : "full" })
    root.bar.shell.updateEntryInline(root.moduleName, next)
  }
  function setArtwork(value) {
    if (!root.bar || !root.bar.shell) return
    var next = Object.assign({}, root.effectiveSettings || {}, { artwork: value === "dial" ? "dial" : "flow" })
    root.bar.shell.updateEntryInline(root.moduleName, next)
  }
  function openLibrary(tab) {
    if (root.miniPlayer) root.miniPlayer.close()
    Qt.callLater(function() {
      if (panelLoader.item) {
        // "settings": the full player opens on its Settings page.
        panelLoader.item.showTab(tab === "settings" ? "search" : (tab || "search"))
        if (tab === "settings") { panelLoader.item.settingsOpen = true; panelLoader.item.returnToPlayer = true }
        panelLoader.item.open()
      }
    })
  }
  Loader {
    id: miniLoader
    source: Qt.resolvedUrl("MiniPlayer2.qml")
    onLoaded: {
      item.bar = Qt.binding(function() { return root.bar })
      item.svc = Qt.binding(function() { return root.svc })
      item.anchorItem = root
      item.libraryRequested.connect(function(tab) { root.openLibrary(typeof tab === "string" ? tab : "search") })
      if (item.pageRequested) item.pageRequested.connect(function(page) {
        item.close()
        Qt.callLater(function() {
          if (!panelLoader.item) return
          panelLoader.item.open()
          if (page.queueFocus) panelLoader.item.showInQueue(page.queueFocus)
          else { panelLoader.item.openPage(page); panelLoader.item.returnToPlayer = true }
        })
      })
      if (item.searchRequested) item.searchRequested.connect(function(q) {
        item.close()
        Qt.callLater(function() {
          if (!panelLoader.item) return
          panelLoader.item.open()
          panelLoader.item.searchFor(q)
        })
      })
      if (item.reduceMotion !== undefined) item.reduceMotion = Qt.binding(function() { return root.reduceMotion })
      if (item.playerSizeRequested) {
        item.playerSize = Qt.binding(function() { return root.playerSize })
        item.compactWheel = Qt.binding(function() { return root.compactWheel })
        item.compactKind = Qt.binding(function() { return root.compactKind })
        item.playerSizeRequested.connect(function(size) { root.setPlayerSize(size) })
      }
      if (item.artworkStyleRequested) {
        item.artworkStyle = Qt.binding(function() { return root.artworkStyle })
        item.artworkStyleRequested.connect(function(style) { root.setArtwork(style) })
      }
    }
  }
  // Open a tab of the full player from outside:
  //   omarchy-shell spinbloom.player openTab lyrics|queue|search|library|history
  IpcHandler {
    target: "spinbloom.player"
    function openTab(tab: string): void {
      var allowed = ["queue", "search", "library", "lyrics", "history"]
      root.openLibrary(allowed.indexOf(tab) >= 0 ? tab : "search")
    }
    function closeAll(): void { root.close() }
    function setArtwork(style: string): void { root.setArtwork(style) }
    function setReduceMotion(reduced: bool): void { root.setMotion(reduced) }
    function linkTitle(): void { if (root.miniPlayer && root.miniPlayer.testTitle) root.miniPlayer.testTitle() }
    function linkArtist(): void { if (root.miniPlayer && root.miniPlayer.testArtist) root.miniPlayer.testArtist() }
    function showOutput(): void { if (root.miniPlayer && root.miniPlayer.testOutput) root.miniPlayer.testOutput() }
    // Preview the first-launch screens without signing out: signin | pick | off
    function previewWelcome(mode: string): void {
      if (!root.miniPlayer || !root.miniPlayer.testWelcome) return
      root.miniPlayer.open()
      root.miniPlayer.testWelcome(mode)
    }
    // Test hook: show or hide the bar's hover card.
    function showHoverCard(on: bool): void { root.cardShown = on && root.hasTrack }
    function setPlayerSize(size: string): void { root.setPlayerSize(size) }
    function setCompactWheel(on: bool): void { root.setCompactWheel(on) }
    function testSwirl(): void { if (root.miniPlayer) root.miniPlayer.testSwirl() }
    function testDrain(): void { if (root.miniPlayer) root.miniPlayer.testDrain() }
    function testSleep(): void { if (root.miniPlayer) root.miniPlayer.testSleep() }
    function showMore(): void { if (root.miniPlayer && root.miniPlayer.testMore) root.miniPlayer.testMore() }
    function glassPreview(mode: string): void { if (root.svc && root.svc.glass) root.svc.glass.previewSolid = mode === "solid" }
    function openPlayer(): void { if (root.miniPlayer) root.miniPlayer.open() }
    // Test hook: on the Dial, play the disc `delta` places along the wheel.
    // Opens the player first (if closed) so the animation can be seen.
    function dialPick(delta: int): void {
      if (!root.miniPlayer || !root.miniPlayer.testPick) return
      if (root.miniPlayer.opened) { root.miniPlayer.testPick(delta); return }
      root.miniPlayer.open()
      dialPickTimer.delta = delta
      dialPickTimer.restart()
    }
    function showShortcuts(): void {
      root.openLibrary("search")
      Qt.callLater(function() { if (panelLoader.item) panelLoader.item.allKeys = true })
    }
    function openSettings(): void {
      root.openLibrary("queue")
      Qt.callLater(function() { if (panelLoader.item) panelLoader.item.settingsOpen = true })
    }
    function openSettingsSection(section: string): void {
      openSettings()
      Qt.callLater(function() {
        var p = panelLoader.item
        var v = p ? p.settingsPage : null
        if (!v) return
        for (var i = 0; i < v.sections.length; i++) if (v.sections[i].key === section) v.navIndex = i
      })
    }
  }
  Timer {
    id: dialPickTimer
    property int delta: 0
    interval: 1200
    onTriggered: if (root.miniPlayer && root.miniPlayer.opened) root.miniPlayer.testPick(delta)
  }
  // <<< Spinbloom design switch <<<

  // Bar click opens the compact player; full Spinbloom remains one button away.
  readonly property bool opened: (miniPlayer ? miniPlayer.opened : false) || (panelLoader.item && panelLoader.item.opened === true)
  readonly property bool popoutSwitchClosing: miniPlayer ? miniPlayer.popoutSwitchClosing : false
  function open() { if (panelLoader.item) panelLoader.item.close(); if (miniPlayer) miniPlayer.open() }
  function close() { if (miniPlayer) miniPlayer.close(); if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (opened) close(); else open() }
  function closeForPopoutSwitch() {
    if (miniPlayer && miniPlayer.opened) miniPlayer.closeForPopoutSwitch()
    if (panelLoader.item && panelLoader.item.opened) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var p = panelLoader.item
    if (!p) return
    p.bar = root.bar
    p.settings = root.effectiveSettings
    p.anchorItem = root
    p.hostWidget = root
    p.svc = root.svc
  }

  Loader {
    id: panelLoader
    active: true
    // Spinbloom design switch: the new design has its own copy of the full player.
    source: Qt.resolvedUrl("Panel2.qml")
    visible: false
    onLoaded: {
      root.injectPanel(); Qt.callLater(root.injectPanel)
      // Back from Settings that the player opened: return to the player.
      if (item.playerRequested) item.playerRequested.connect(function() { root.open() })
    }
  }

  // ---- state
  readonly property bool hasTrack: svc ? svc.hasTrack : false
  // Closed: Spinbloom's mark and name, dimmed, and nothing else. Any click
  // starts it again (a left click also opens the panel).
  readonly property bool closed: svc ? svc.closed : false
  readonly property bool playing: svc ? svc.isPlaying : false
  readonly property bool showControls: root.displaySetting("barControls", true) && hasTrack && !vertical
  readonly property bool signingIn: svc ? svc.signingIn : false
  readonly property bool showTitle: root.displaySetting("showTitle", false) && (hasTrack || closed || signingIn) && !vertical
  readonly property real maxLabelWidth: Number(root.setting("maxLabelWidth", 160)) || 160
  readonly property color fg: bar ? bar.barForeground : Color.foreground
  readonly property string family: bar ? bar.fontFamily : Style.font.family
  // The bar is shared: the title only. Artist, album and time are in the tooltip.
  readonly property string label: signingIn ? "Signing in…" : svc && hasTrack ? svc.title : closed ? "Spinbloom" : ""

  visible: hasTrack || root.setting("showWhenIdle", true)
  implicitWidth: visible ? body.implicitWidth + Style.space(10) : 0
  implicitHeight: barSize

  Row {
    id: body
    anchors.centerIn: parent
    spacing: Style.space(6)
    opacity: root.closed ? 0.45 : 1
    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

    Views.BarCover {
      id: coverSlot
      anchors.verticalCenter: parent.verticalCenter
      barSize: root.barSize
      hasTrack: root.hasTrack
      progress: root.svc ? root.svc.progress : 0
      // Spinbloom design switch: the new design draws the ring in the bar's own
      // text colour, like every other bar icon (macOS keeps the menu bar
      // monochrome); classic keeps the theme accent.
      ringColor: root.playing ? (root.newDesign ? root.fg : Color.accent) : Util.alpha(root.fg, 0.45)
      trackColor: Util.alpha(root.fg, 0.15)
      source: root.svc ? root.svc.thumb : ""
      foreground: root.fg
      fill: root.hasTrack ? Util.alpha(root.fg, 0.08) : "transparent"
      fontFamily: root.family
      dim: root.hasTrack && !root.playing
      calm: root.reduceMotion
      opacity: root.closed || (root.svc && (root.svc.ready || root.svc.hasTrack)) ? 1 : 0.55

      // While a sign-in runs (the panel closes when the Google window is
      // used), the bar's icon breathes: something is happening.
      transformOrigin: Item.Center
      SequentialAnimation on scale {
        loops: Animation.Infinite
        running: root.signingIn
        onRunningChanged: if (!running) coverSlot.scale = 1
        NumberAnimation { from: 0.85; to: 1.1; duration: 1400; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1.1; to: 0.85; duration: 1400; easing.type: Easing.InOutSine }
      }
    }

    // The title: fades up on a new song, glides sideways while pointed at
    // when it is too long, and dims a little while paused (as the cover does).
    Item {
      id: labelText
      visible: root.showTitle
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(root.maxLabelWidth, titleFull.implicitWidth)
      height: titleFull.implicitHeight
      clip: true
      readonly property real overflow: Math.max(0, titleFull.implicitWidth - width)
      readonly property bool scrolling: barHit.containsMouse && overflow > 0
      opacity: root.hasTrack && !root.playing ? 0.6 : 1
      Behavior on opacity { NumberAnimation { duration: 250 } }
      Text {
        id: titleFull
        text: root.label
        textFormat: Text.PlainText
        // Cut with "…" at rest; full width while it scrolls.
        width: labelText.scrolling ? implicitWidth : labelText.width
        elide: labelText.scrolling ? Text.ElideNone : Text.ElideRight
        color: root.fg
        font.family: root.family
        font.pixelSize: Style.font.body
        transform: Translate { id: titleShift }
        onTextChanged: { x = 0; titleIn.restart() }
        ParallelAnimation {
          id: titleIn
          NumberAnimation { target: titleFull; property: "opacity"; from: 0; to: 1; duration: 380; easing.type: Easing.OutCubic }
          NumberAnimation { target: titleShift; property: "y"; from: Style.space(5); to: 0; duration: 460; easing.type: Easing.OutCubic }
        }
        SequentialAnimation on x {
          running: labelText.scrolling
          loops: Animation.Infinite
          onRunningChanged: if (!running) titleFull.x = 0
          PauseAnimation { duration: 500 }
          NumberAnimation { to: -labelText.overflow; duration: Math.max(1200, labelText.overflow * 26); easing.type: Easing.InOutSine }
          PauseAnimation { duration: 1400 }
          NumberAnimation { to: 0; duration: 450; easing.type: Easing.OutCubic }
        }
      }
    }

    Row {
      visible: root.showControls
      anchors.verticalCenter: parent.verticalCenter
      spacing: 0

      BarIconButton {
        bar: root.bar
        // The player's own rounded icons, in the bar's colour.
        iconComponent: Component { Views.Glyph { name: "previous"; size: Math.round(Style.bar.iconSize * 0.92); color: root.fg } }
        tooltipText: "Previous"
        slotSize: Math.round(Style.bar.iconSlot * 0.85)
        onPressed: function (b) { if (b === Qt.LeftButton && root.svc) root.svc.previous() }
      }
      BarIconButton {
        bar: root.bar
        // The player's own rounded icons, in the bar's colour.
        iconComponent: Component { Views.Glyph { name: root.playing ? "pause" : "play"; size: Math.round(Style.bar.iconSize * 0.92); color: root.fg } }
        tooltipText: root.playing ? "Pause" : "Play"
        slotSize: Math.round(Style.bar.iconSlot * 0.85)
        onPressed: function (b) { if (b === Qt.LeftButton && root.svc) root.svc.togglePlaying() }
      }
      BarIconButton {
        bar: root.bar
        // The player's own rounded icons, in the bar's colour.
        iconComponent: Component { Views.Glyph { name: "next"; size: Math.round(Style.bar.iconSize * 0.92); color: root.fg } }
        tooltipText: "Next"
        slotSize: Math.round(Style.bar.iconSlot * 0.85)
        onPressed: function (b) { if (b === Qt.LeftButton && root.svc) root.svc.next() }
      }
    }
  }

  // Clicks and wheel on the cover and the title (the buttons take their own).
  MouseArea {
    id: barHit
    x: body.x
    y: 0
    width: coverSlot.width + (labelText.visible ? labelText.width + body.spacing : 0) + Style.space(5)
    height: parent.height
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    property real wheelAcc: 0

    onClicked: function (mouse) {
      if (root.closed) {
        root.svc.startEngine()
        if (mouse.button === Qt.LeftButton) root.toggle()
        return
      }
      if (mouse.button === Qt.MiddleButton) { if (root.svc) root.svc.togglePlaying() }
      else if (mouse.button === Qt.RightButton) { if (root.svc) root.svc.next() }
      else root.toggle()
    }
    onWheel: function (wheel) {
      if (!root.svc || !root.hasTrack) return
      var w = Util.wheelSteps(wheelAcc, wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x)
      wheelAcc = w.remainder
      if (w.steps === 0) return
      if (wheel.modifiers & Qt.ShiftModifier) root.svc.seekBy(w.steps * 5)
      else root.svc.nudgeVolume(w.steps)
    }
    onEntered: {
      if (!root.bar) return
      var s = root.svc
      if (s && s.hasTrack) { hoverDelay.restart(); return }   // the glass card below
      var tip = s && s.hasTrack
        ? s.title + (s.artist ? "\n" + s.artist : "") + (s.album ? "\n" + s.album : "")
          + "\n" + Model.fmtTime(s.position) + " of " + Model.fmtTime(s.duration) + ", volume " + (s.muted ? "muted" : s.volume + "%")
        : s && s.closed ? "Spinbloom is off. Click to turn it on."
        : (s ? (s.engineLine || "Nothing playing. Click to search.") : "Spinbloom")
      root.bar.showTooltip(root, tip)
    }
    onExited: { hoverDelay.stop(); root.cardShown = false; if (root.bar) root.bar.hideTooltip(root) }
  }
  // ---- hover card: artwork, title, artist, album and a progress line ------
  // Its own small window that never takes focus or closes other panels.
  property bool cardShown: false
  Timer { id: hoverDelay; interval: 450; onTriggered: root.cardShown = barHit.containsMouse && root.hasTrack && !root.opened }
  onOpenedChanged: if (opened) root.cardShown = false

  PopupWindow {
    id: hoverCard
    readonly property bool atBottom: !!root.bar && root.bar.position === "bottom"
    visible: root.cardShown || cardBody.opacity > 0.01
    color: "transparent"
    // Same surface as the mini player: album colours on = the dark album
    // backdrop; off = the theme's main colour, deepened like the player's
    // smoke behind its controls. Text is always white, as in the player.
    readonly property bool album: String(root.displaySetting("albumColors", true)) !== "false"
    readonly property color themeBg: Util.alpha(Color.popups.background, 1)
    readonly property bool lightTheme: (Color.popups.text.r + Color.popups.text.g + Color.popups.text.b) / 3 < 0.5
    readonly property color base: album ? (lightTheme ? "#2b2c34" : themeBg)
                                        : Qt.tint(themeBg, Qt.rgba(0, 0, 0, lightTheme ? 0.62 : 0.15))
    readonly property color ink: "white"
    implicitWidth: Style.space(320)
    implicitHeight: Style.space(120)
    mask: Region {}
    anchor.item: coverSlot
    anchor.edges: atBottom ? Edges.Top : Edges.Bottom
    anchor.gravity: atBottom ? Edges.Top : Edges.Bottom
    anchor.adjustment: PopupAdjustment.Slide

    Item {
      id: cardBody
      x: Style.space(10); y: Style.space(8)
      width: parent.width - Style.space(20)
      height: parent.height - Style.space(20)
      opacity: root.cardShown ? 1 : 0
      scale: root.cardShown ? 1 : 0.96
      transformOrigin: hoverCard.atBottom ? Item.Bottom : Item.Top
      Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
      RectangularShadow {
        anchors.fill: parent; radius: Style.space(14)
        blur: Style.space(14); offset: Qt.vector2d(0, Style.space(4))
        color: "#66000000"
      }
      Rectangle { id: cardMask; anchors.fill: parent; radius: Style.space(14); visible: false; layer.enabled: true; color: "white" }
      Item {
        anchors.fill: parent
        layer.enabled: true
        layer.effect: MultiEffect { maskEnabled: true; maskSource: cardMask }
        Rectangle { anchors.fill: parent; color: hoverCard.base }
        Image {
          anchors.fill: parent
          anchors.margins: -Style.space(30)
          source: root.svc && root.cardShown ? root.svc.thumb : ""
          sourceSize: Qt.size(48, 48)
          fillMode: Image.PreserveAspectCrop
          opacity: hoverCard.album ? 0.7 : 0
          layer.enabled: true
          layer.effect: MultiEffect { blurEnabled: true; blur: 1; blurMax: 48; saturation: 0.85; brightness: -0.04 }
        }
        Rectangle { anchors.fill: parent; color: Util.alpha(hoverCard.base, hoverCard.album ? 0.45 : 0) }
        // Album colours off: the player's theme glow and glass sheen.
        Views.ThemeGlow { anchors.fill: parent; visible: !hoverCard.album; second: "white" }
      }
      Rectangle { anchors.fill: parent; radius: Style.space(14); color: "transparent"; border.width: 1; border.color: Util.alpha("white", 0.12) }

      Rectangle { id: artMask; width: Style.space(64); height: width; radius: Style.space(8); visible: false; layer.enabled: true; color: "white" }
      Image {
        id: cardArt
        x: Style.space(12); anchors.verticalCenter: parent.verticalCenter
        width: Style.space(64); height: width
        source: root.svc && root.cardShown ? root.svc.thumb : ""
        sourceSize: Qt.size(160, 160)
        fillMode: Image.PreserveAspectCrop
        layer.enabled: true
        layer.effect: MultiEffect { maskEnabled: true; maskSource: artMask }
      }
      Column {
        anchors.left: cardArt.right; anchors.leftMargin: Style.space(12)
        anchors.right: parent.right; anchors.rightMargin: Style.space(14)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)
        Text {
          width: parent.width
          text: root.svc ? root.svc.title : ""
          textFormat: Text.PlainText; elide: Text.ElideRight
          color: hoverCard.ink
          font.family: "Inter"; font.pixelSize: Style.font.body; font.weight: Font.DemiBold
        }
        Text {
          width: parent.width
          text: root.svc ? root.svc.artist : ""
          visible: text !== ""
          textFormat: Text.PlainText; elide: Text.ElideRight
          color: Util.alpha(hoverCard.ink, 0.72)
          font.family: "Inter"; font.pixelSize: Style.font.caption
        }
        Text {
          width: parent.width
          text: root.svc ? root.svc.album : ""
          visible: text !== ""
          textFormat: Text.PlainText; elide: Text.ElideRight
          color: Util.alpha(hoverCard.ink, 0.5)
          font.family: "Inter"; font.pixelSize: Style.font.caption
        }
        Item { width: 1; height: Style.space(5) }
        Rectangle {
          width: parent.width; height: Style.space(3); radius: height / 2
          color: Util.alpha(hoverCard.ink, 0.18)
          Rectangle {
            height: parent.height; radius: height / 2
            width: Math.max(height, parent.width * (root.svc && root.svc.duration > 0 ? Math.min(1, root.svc.position / root.svc.duration) : 0))
            color: hoverCard.ink
          }
        }
        Item {
          width: parent.width; height: cardTime.implicitHeight
          Text {
            id: cardTime
            text: root.svc ? Model.fmtTime(root.svc.position) : ""
            color: Util.alpha(hoverCard.ink, 0.55)
            font.family: "Inter"; font.pixelSize: Math.max(9, Style.font.caption - 1); font.features: { "tnum": 1 }
          }
          Text {
            anchors.right: parent.right
            text: root.svc ? "-" + Model.fmtTime(Math.max(0, root.svc.duration - root.svc.position)) : ""
            color: Util.alpha(hoverCard.ink, 0.55)
            font.family: "Inter"; font.pixelSize: Math.max(9, Style.font.caption - 1); font.features: { "tnum": 1 }
          }
        }
      }
    }
  }
}
