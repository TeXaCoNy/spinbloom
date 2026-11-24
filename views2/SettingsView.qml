import QtQuick
import QtQuick.Effects
import "../theme2" as SpinTheme
import qs.Ui
import qs.Commons
import "../lib/Model.js" as Model
import "../lib/Icons.js" as Icons

// The Settings view: replaces the panel body (Panel.qml puts it in `stage`,
// same place as Queue/Search/Library/Lyrics). Left column = sections, right
// column = that section's rows. Keyboard: ↑↓ move (sections in the left
// column, rows in the right), ←→ change a row's value, Tab switches
// column, Enter acts (same as ←→ for a stepper, toggles a switch, runs a
// button), Esc goes back (handled by Panel, which owns "?" too).
//
// Every section here is real: bound to real settings (svc.saveSetting),
// and Account/Sound reach the bridge for real (account.info/signout, the
// agent's WebAudio EQ graph). Audio quality (bitrate/codec) is out of
// scope and not built.
Item {
  id: root

  property var svc: null
  property color fg: Color.foreground
  property string family: "Inter"
  readonly property color hoverTint: Qt.tint(SpinTheme.Palette.card, Util.alpha(Color.popups.text, 0.05))

  signal backRequested()
  signal showAllKeys()

  readonly property var sections: [
    { key: "account", label: "Account" }, { key: "sound", label: "Sound" },
    { key: "playback", label: "Playback" }, { key: "look", label: "Appearance" }, { key: "bar", label: "Bar and alerts" },
    { key: "keys", label: "Keys" }, { key: "advanced", label: "Advanced" }, { key: "about", label: "About" }
  ]
  property int navIndex: 0
  readonly property string section: root.sections[root.navIndex].key
  // "nav" (left column has the cursor) or "content" (right column does).
  property string column: "content"
  property int cursor: 0
  // Handlers for the current section's rows, in the same order they are
  // drawn: { change(dir), act(), toggle() } — a row supplies whichever it
  // needs; move()/change()/act() below call through them.
  property var handlers: []

  readonly property real navWidth: Style.space(150)

  // ---- transient, per-open UI state (never persisted) -------------------

  property string accountNote: ""
  // Two-step confirms (Switch account, Sign out, Erase): one Enter arms,
  // the next one on the same row runs it. Anything else disarms: moving the
  // cursor, changing column or section, the view going away (the panel
  // closed), or armTimeoutMs with no second Enter.
  property bool switchArmed: false
  property bool signOutArmed: false
  property bool eraseArmed: false
  readonly property int armTimeoutMs: 5000
  readonly property bool armTimerRunning: armTimer.running
  function disarm() {
    root.switchArmed = false
    root.signOutArmed = false
    root.eraseArmed = false
  }
  Timer {
    id: armTimer
    interval: root.armTimeoutMs
    running: root.switchArmed || root.signOutArmed || root.eraseArmed
    onTriggered: root.disarm()
  }
  onCursorChanged: root.disarm()
  onColumnChanged: root.disarm()
  onVisibleChanged: if (!root.visible) root.disarm()
  property string cacheNote: ""
  property string eraseNote: ""
  property string engineVersionText: ""

  function rebuildHandlers() {
    root.cursor = 0
    root.handlers = root.buildHandlers(root.section)
  }
  onSectionChanged: {
    root.disarm()
    root.accountNote = ""
    root.cacheNote = ""
    root.eraseNote = ""
    root.rebuildHandlers()
    if (root.section === "about" && root.svc) {
      root.engineVersionText = "…"
      root.svc.engineVersion(function (r) { root.engineVersionText = r.ok ? r.data.product : "not running" })
    }
    if (root.section === "account" && root.svc && root.svc.signedIn) root.svc.accountInfo(function () {})
  }
  Component.onCompleted: root.rebuildHandlers()

  // Playback has one more row (Brave's ad blocker) while the engine is
  // Brave; the cursor stays where it was when that row comes or goes.
  readonly property bool braveEngine: root.svc ? Model.isBraveBrowser(root.svc.setting("browser", "")) : false
  onBraveEngineChanged: {
    if (root.section !== "playback") return
    var at = root.cursor
    root.handlers = root.buildHandlers(root.section)
    root.cursor = Math.min(at, Math.max(0, root.handlers.length - 1))
  }

  // Account shows one action signed out and two signed in, so its rows
  // (and the keyboard's) follow the sign-in state, however it changes.
  readonly property bool signedIn: root.svc ? root.svc.signedIn === true : false
  onSignedInChanged: {
    if (root.section !== "account") return
    root.disarm()
    root.rebuildHandlers()
    if (root.signedIn && root.svc) root.svc.accountInfo(function () {})
  }

  // ---- keyboard API, called by Panel.qml ---------------------------------

  function move(dir) {
    if (root.column === "nav") {
      root.navIndex = (root.navIndex + dir + root.sections.length) % root.sections.length
    } else if (root.handlers.length > 0) {
      root.cursor = (root.cursor + dir + root.handlers.length) % root.handlers.length
    }
  }
  function change(dir) {
    if (root.column !== "content") return
    var h = root.handlers[root.cursor]
    if (!h) return
    if (h.toggle) h.toggle()
    else if (h.change) h.change(dir)
  }
  function act() {
    if (root.column === "nav") { root.column = "content"; root.cursor = 0; return }
    var h = root.handlers[root.cursor]
    if (!h) return
    if (h.act) h.act()
    else if (h.toggle) h.toggle()
    else if (h.change) h.change(1)
  }
  function switchColumn() { root.column = root.column === "nav" ? "content" : "nav" }

  // ---- pointer API: a click is the keyboard's cursor move plus its key ----
  // Every row routes its click through the same handlers the keyboard uses,
  // so a click and an Enter can never disagree (the two-step confirms
  // included: a second click on an armed row runs it, like a second Enter).

  function pointAt(i) { root.column = "content"; root.cursor = i }
  function clickRow(i) { root.pointAt(i); root.act() }
  function stepRow(i, dir) { root.pointAt(i); root.change(dir) }

  // ---- handlers per section ----------------------------------------------

  function buildHandlers(sec) {
    var svc = root.svc
    if (!svc) return []
    switch (sec) {
      case "account": return (svc.signedIn ? [
        { act: function () { root.actSwitch() } },
        { act: function () { root.actSignOut() } }
      ] : [
        { act: function () { root.actSignIn() } }
      ]).concat([{ act: function () { svc.toggleEngine() } }])
      case "sound": {
        var bandHandlers = []
        for (var i = 0; i < 10; i++) (function (idx) {
          bandHandlers.push({ change: function (dir) { root.stepBand(idx, dir) } })
        })(i)
        return [
          { toggle: function () { svc.saveSetting("eqEnabled", !svc.setting("eqEnabled", false)) } },
          { change: function (dir) { root.stepEqPreset(dir) }, act: function () { root.stepEqPreset(1) } }
        ]
          .concat(bandHandlers)
          .concat([
            { change: function (dir) { svc.saveSetting("eqPreamp", Model.stepNumber(svc.setting("eqPreamp", 0), dir, -12, 0)) } },
            { toggle: function () { svc.saveSetting("eqLoudness", !svc.setting("eqLoudness", false)) } }
          ])
      }
      case "playback": return [
        { change: function (dir) { svc.nudgeSleepMode(dir) }, act: function () { svc.nudgeSleepMode(1) } },
        { toggle: function () { svc.saveSetting("startPaused", !svc.setting("startPaused", false)) } },
        { change: function (dir) { svc.saveSetting("startVolume", Model.cycleList(["last", "25", "50", "75", "100"], String(svc.setting("startVolume", "last")), dir)) } },
        { toggle: function () { svc.saveSetting("autostart", !svc.setting("autostart", true)) } },
        { change: function (dir) { svc.saveSetting("browser", Model.cycleList(Model.browserChoices(svc.browsers, svc.setting("browser", "")), svc.setting("browser", ""), dir)) } }
      ].concat(root.braveEngine ? [
        { toggle: function () { svc.saveSetting("braveAdBlock", !svc.setting("braveAdBlock", false)) } }
      ] : [])
      // Spinbloom: the mini player's artwork style and calm motion.
      case "look": return [
        { change: function (dir) { root.setArtworkStyle(root.artworkStyle === "dial" ? "flow" : "dial") },
          act: function () { root.setArtworkStyle(root.artworkStyle === "dial" ? "flow" : "dial") } },
        { toggle: function () { svc.saveSetting("motion", root.calmMotion ? "full" : "reduced") } },
        { toggle: function () { svc.saveSetting("albumColors", !root.albumColors) } },
        { toggle: function () { if (!root.userBlur) svc.saveSetting("desktopBlur", !root.desktopBlur) } },
        { change: function (dir) { root.setPlayerSize(Model.cycleList(["full", "compact", "small"], root.playerSize, dir)) },
          act: function () { root.setPlayerSize(Model.cycleList(["full", "compact", "small"], root.playerSize, 1)) } },
        { toggle: function () { svc.saveSetting("compactWheel", !root.compactWheel) } }
      ]
      case "bar": return [
        { toggle: function () { svc.saveSetting("barControls", !svc.setting("barControls", true)) } },
        { toggle: function () { svc.saveSetting("showTitle", !svc.setting("showTitle", false)) } },
        { change: function (dir) { svc.saveSetting("maxLabelWidth", Model.stepNumber(svc.setting("maxLabelWidth", 160), dir * 20, 80, 400)) } },
        { toggle: function () { svc.saveSetting("showWhenIdle", !svc.setting("showWhenIdle", true)) } },
        { toggle: function () { svc.saveSetting("notify", !svc.setting("notify", true)) } }
      ]
      case "keys": return [
        { toggle: function () { svc.saveSetting("globalKeys", !svc.setting("globalKeys", true)) } },
        { act: function () { root.showAllKeys() } }
      ]
      case "advanced": return [
        { change: function (dir) { svc.saveSetting("recycleHeapMb", Model.stepNumber(Model.recycleHeapMbFor(svc.setting("recycleHeapMb", 400)), dir * 50, Model.RECYCLE_HEAP_MB_RANGE[0], Model.RECYCLE_HEAP_MB_RANGE[1])) } },
        { change: function (dir) { svc.saveSetting("recycleHours", Model.stepNumber(Model.recycleHoursFor(svc.setting("recycleHours", 12)), dir, Model.RECYCLE_HOURS_RANGE[0], Model.RECYCLE_HOURS_RANGE[1])) } },
        { act: function () { root.cacheNote = "Clearing…"; svc.clearCache(function (r) { root.cacheNote = r.ok ? "Cleared" : "Could not clear the cache" }) } },
        { act: function () { svc.resetSettings() } },
        { act: function () { root.actErase() } }
      ]
      case "about": return []
      default: return []
    }
  }

  function stepEqPreset(dir) {
    root.setEqPreset(Model.cycleList(Model.EQ_PRESET_ORDER, root.svc.setting("eqPreset", "flat"), dir))
  }
  function setEqPreset(key) {
    var svc = root.svc
    svc.saveSetting("eqPreset", key)
    if (key !== "custom") svc.saveSetting("eqBands", JSON.stringify(Model.eqBandsFor(key, null)))
  }
  function stepBand(index, dir) {
    var bands = root.currentBands()
    root.setBand(index, Model.stepNumber(bands[index], dir, -12, 12))
  }
  function setBand(index, db) {
    var svc = root.svc
    var bands = root.currentBands().slice()
    var next = Math.max(-12, Math.min(12, Math.round(db)))
    // A drag lands on the same whole dB many times over; save only a change.
    if (bands[index] === next && svc.setting("eqPreset", "flat") === "custom") return
    bands[index] = next
    svc.saveSetting("eqBands", JSON.stringify(bands))
    svc.saveSetting("eqPreset", "custom")
  }
  function actErase() {
    if (!root.eraseArmed) { root.disarm(); root.eraseArmed = true; return }
    root.eraseArmed = false
    root.cacheNote = ""
    root.eraseNote = "Erasing…"
    root.svc.eraseProfile(function (r) { root.eraseNote = r.ok ? "Erased; starting clean" : Model.errorText(r.error) })
  }
  function actSwitch() {
    if (!root.switchArmed) { root.disarm(); root.switchArmed = true; return }
    root.switchArmed = false
    root.accountNote = "Switching…"
    root.svc.accountSwitch(function (r) { root.accountNote = r.ok ? "" : Model.errorText(r.error) })
  }
  // Two-letter fallback for the round avatar when there is no picture.
  function initialsFor(name) {
    if (!name) return "?"
    var parts = name.trim().split(/\s+/)
    var first = parts[0] ? parts[0][0] : ""
    var last = parts.length > 1 ? parts[parts.length - 1][0] : ""
    return String(first + last).toUpperCase() || "?"
  }
  function actSignIn() {
    root.accountNote = ""
    root.svc.signIn()
  }
  function actSignOut() {
    if (!root.signOutArmed) { root.disarm(); root.signOutArmed = true; return }
    root.signOutArmed = false
    root.accountNote = "Signing out…"
    root.svc.accountSignOut(function (r) { root.accountNote = r.ok ? "" : Model.errorText(r.error) })
  }

  // Bands shown for the current preset (or the custom bands themselves).
  function currentBands() {
    var svc = root.svc
    if (!svc) return Model.EQ_PRESETS.flat
    var preset = svc.setting("eqPreset", "flat")
    if (preset === "custom") return Model.parseEqBands(svc.setting("eqBands", Model.SETTINGS_DEFAULTS.eqBands))
    return Model.eqBandsFor(preset, null)
  }

  // ---- reusable pieces (same tokens as the rest of the panel) -----------

  // Inner padding of the page card (Apple's grouped settings).
  readonly property real cardPad: Style.space(10)

  readonly property string artworkStyle: root.svc && String(root.svc.setting("artwork", "dial")) === "flow" ? "flow" : "dial"
  readonly property bool albumColors: !root.svc || String(root.svc.setting("albumColors", true)) !== "false"
  readonly property bool desktopBlur: !!root.svc && String(root.svc.setting("desktopBlur", true)) === "true"
  // Spinbloom: the player's size and whether compact keeps the CD wheel.
  readonly property string playerSize: { const v = root.svc ? String(root.svc.setting("playerSize", "full")) : "full"; return v === "compact" || v === "small" ? v : "full" }
  readonly property bool compactWheel: !root.svc || String(root.svc.setting("compactWheel", false)) !== "false"
  function setPlayerSize(size) {
    if (!root.svc) return
    root.svc.saveSetting("playerSize", size)
    if (size !== "full") root.svc.saveSetting("compactKind", size)
  }
  readonly property bool userBlur: !!root.svc && !!root.svc.glass && root.svc.glass.userBlur
  readonly property bool calmMotion: !!(root.svc && String(root.svc.setting("motion", "full")) === "reduced")
  function setArtworkStyle(style) { if (root.svc) root.svc.saveSetting("artwork", style === "flow" ? "flow" : "dial") }

  component RowShell: Item {
    id: rowShell
    property color fg: root.fg
    property string family: root.family
    property string label: ""
    property string help: ""
    // The row's index in its section's handlers: the keyboard cursor lands
    // on it, and a click anywhere on the row runs it.
    property int row: -1
    readonly property bool focused: row >= 0 && root.column === "content" && root.cursor === row
    width: parent ? parent.width : 0
    // Grows with a wrapped help line. A fixed height with the text centred
    // on it pushed a two-line help's title above the row's top, where the
    // content's clip cut it off.
    height: Math.max(Style.space(46), rowText.implicitHeight + Style.space(12))
    default property alias controlChildren: controlSlot.children

    // Marks a settings row, so the row above knows to draw a divider.
    property bool settingsRow: true
    readonly property bool dividerBelow: {
      const kids = parent ? parent.children : []
      for (let i = 0; i < kids.length - 1; i++)
        if (kids[i] === rowShell) {
          for (let j = i + 1; j < kids.length; j++) {
            const k = kids[j]
            if (!k.visible || k.height === 0) continue
            return k.settingsRow === true
          }
          return false
        }
      return false
    }
    Rectangle {
      anchors.left: parent.left; anchors.leftMargin: Style.space(6)
      anchors.right: parent.right; anchors.rightMargin: Style.space(6)
      anchors.bottom: parent.bottom
      anchors.bottomMargin: -1
      height: 1
      visible: rowShell.dividerBelow
      color: Util.alpha(SpinTheme.Palette.text, 0.08)
    }
    HoverHandler { id: settingsRowHover; enabled: rowShell.row >= 0 }
    Rectangle {
      anchors.fill: parent
      radius: Style.space(8)
      color: settingsRowHover.hovered ? SpinTheme.Palette.fillHover : rowShell.focused ? SpinTheme.Palette.selected
                              : "transparent"
    }

    // Below the controls, so a control with its own pointer handling (a
    // stepper's arrows) gets the click first.
    MouseArea {
      id: rowHover
      anchors.fill: parent
      enabled: rowShell.row >= 0
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.clickRow(rowShell.row)
    }

    Column {
      id: rowText
      objectName: "rowText"
      anchors.left: parent.left
      anchors.leftMargin: Style.space(6)
      anchors.right: controlSlot.left
      anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)
      Text {
        text: rowShell.label
        textFormat: Text.PlainText
        color: rowShell.fg
        font.family: rowShell.family
        font.pixelSize: Style.font.body
      }
      Text {
        visible: rowShell.help !== ""
        width: parent.width
        text: rowShell.help
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        color: SpinTheme.Palette.secondary
        font.family: rowShell.family
        font.pixelSize: Style.font.caption
      }
    }

    Row {
      id: controlSlot
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(8)
    }
  }

  component MiniToggle: Rectangle {
    id: toggle
    property color fg: root.fg
    property bool active: false
    width: Style.space(40)
    height: Style.space(22)
    radius: height / 2
    // White when on, like every other "on" in the player (not the theme's
    // accent, so it looks right under any desktop theme).
    // On: a bright frosted track; off: faint glass. The knob is always white.
    // In a light theme the "on" track is a soft grey, not near-black.
    color: active ? Util.alpha(SpinTheme.Palette.text, SpinTheme.Palette.light ? 0.28 : 0.55) : Util.alpha(SpinTheme.Palette.text, 0.14)
    Behavior on color { ColorAnimation { duration: 160 } }
    RectangularShadow {
      anchors.fill: knob
      radius: knob.radius
      blur: 6
      offset: Qt.vector2d(0, 1)
      color: "#59000000"
    }
    Rectangle {
      id: knob
      width: parent.height - 4
      height: width
      radius: width / 2
      color: "white"
      anchors.verticalCenter: parent.verticalCenter
      x: toggle.active ? parent.width - width - 2 : 2
      Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
    }
  }

  component Chip: Rectangle {
    id: chip
    property color fg: root.fg
    property string label: ""
    property bool active: false
    signal clicked()
    width: chipText.implicitWidth + Style.space(16)
    height: Style.space(24)
    radius: Style.space(12)
    HoverHandler { id: chipHover }
    // Selected: a white pill in a light theme (as Apple's segmented
    // controls), a bright one in a dark theme.
    color: active ? (SpinTheme.Palette.light ? "white" : SpinTheme.Palette.text)
                  : chipHover.hovered ? SpinTheme.Palette.fillHover : SpinTheme.Palette.fill
    border.width: active && SpinTheme.Palette.light ? 1 : 0
    border.color: Util.alpha(SpinTheme.Palette.text, 0.12)
    Behavior on color { ColorAnimation { duration: 140 } }
    Text {
      id: chipText
      anchors.centerIn: parent
      text: chip.label
      textFormat: Text.PlainText
      color: chip.active && !SpinTheme.Palette.light ? SpinTheme.Palette.onAccent : SpinTheme.Palette.text
      font.weight: chip.active ? Font.DemiBold : Font.Normal
      font.family: root.family
      font.pixelSize: Style.font.caption
    }
    MouseArea {
      anchors.fill: parent
      anchors.topMargin: Math.min(0, (parent.height - Style.space(32)) / 2)
      anchors.bottomMargin: anchors.topMargin
      cursorShape: Qt.PointingHandCursor
      onClicked: chip.clicked()
    }
  }

  // A value with ‹ › steppers, e.g. "400 MB", "12 h", "50%".
  // A click on its left half steps down, on its right half up; `row` is the
  // RowShell's own index (the row itself would only ever step up).
  component StepValue: Item {
    id: stepValue
    property color fg: root.fg
    property string value: ""
    property int row: -1
    implicitWidth: stepRowItems.implicitWidth
    implicitHeight: Math.max(stepRowItems.implicitHeight, Style.space(32))
    width: implicitWidth
    height: implicitHeight
    Row {
      id: stepRowItems
      anchors.centerIn: parent
      spacing: Style.space(6)
      Text { text: Icons.chevronLeft; color: Util.alpha(root.fg, 0.45); font.family: root.family; font.pixelSize: Style.font.caption; textFormat: Text.PlainText }
      Text { text: stepValue.value; color: stepValue.fg; font.family: root.family; font.pixelSize: Style.font.body; textFormat: Text.PlainText }
      Text { text: Icons.chevronRight; color: Util.alpha(root.fg, 0.45); font.family: root.family; font.pixelSize: Style.font.caption; textFormat: Text.PlainText }
    }
    MouseArea {
      anchors.fill: parent
      enabled: stepValue.row >= 0
      cursorShape: Qt.PointingHandCursor
      onClicked: function (mouse) { root.stepRow(stepValue.row, mouse.x < width / 2 ? -1 : 1) }
    }
  }

  component QuietButton: Rectangle {
    id: qbtn
    activeFocusOnTab: row >= 0
    Keys.onReturnPressed: if (row >= 0) root.clickRow(row)
    Keys.onEnterPressed: if (row >= 0) root.clickRow(row)
    Keys.onSpacePressed: if (row >= 0) root.clickRow(row)
    Behavior on color { ColorAnimation { duration: Style.duration(110) } }
    property color fg: root.fg
    property string label: ""
    property bool danger: false
    // Standalone (Account) buttons carry their own row; inside a RowShell
    // they leave it at -1 and the row takes the click.
    property int row: -1
    readonly property bool focused: row >= 0 && root.column === "content" && root.cursor === row
    width: qbtnText.implicitWidth + Style.space(26)
    height: Style.space(28)
    radius: height / 2
    HoverHandler { id: quietHover }
    color: quietHover.hovered ? SpinTheme.Palette.fillPressed : focused ? SpinTheme.Palette.fillHover : SpinTheme.Palette.fill
    border.width: activeFocus ? 2 : 0
    border.color: SpinTheme.Palette.text
    Text {
      id: qbtnText
      anchors.centerIn: parent
      text: qbtn.label
      textFormat: Text.PlainText
      color: qbtn.danger ? Color.urgent : SpinTheme.Palette.text
      font.family: root.family
      font.pixelSize: Style.font.caption
      font.weight: Font.Medium
    }
    MouseArea {
      // 32 px tall at least, like every other hit box in the panel.
      anchors.fill: parent
      anchors.topMargin: Math.min(0, (parent.height - Style.space(32)) / 2)
      anchors.bottomMargin: anchors.topMargin
      enabled: qbtn.row >= 0
      cursorShape: Qt.PointingHandCursor
      onClicked: root.clickRow(qbtn.row)
    }
  }

  // ---- top row: back affordance ------------------------------------------

  Item {
    id: backRow
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: backLabel.implicitHeight

    Text {
      id: backLabel
      objectName: "settingsBack"
      text: "\u{F0141}  Settings"
      textFormat: Text.PlainText
      color: root.fg
      font.family: root.family
      font.pixelSize: Style.font.title
      font.weight: Font.Bold
      MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.backRequested() }
    }
  }

  // ---- body: left section list + right rows -----------------------------

  Row {
    id: body
    anchors.top: backRow.bottom
    anchors.topMargin: Style.space(14)
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    spacing: Style.space(16)

    Column {
      id: nav
      width: root.navWidth
      height: parent.height
      spacing: Style.space(2)
      Repeater {
        model: root.sections
        delegate: Item {
          required property var modelData
          required property int index
          width: nav.width
          height: Style.space(30)
          readonly property bool navFocused: root.column === "nav" && index === root.navIndex
          HoverHandler { id: navHover }
          Rectangle {
            anchors.fill: parent
            radius: Style.space(8)
            color: modelData.key === root.section ? SpinTheme.Palette.selected
              : navHover.hovered || navFocused ? SpinTheme.Palette.fillHover : "transparent"
          }
          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.label
            textFormat: Text.PlainText
            color: modelData.key === root.section ? SpinTheme.Palette.text : SpinTheme.Palette.secondary
            font.family: root.family
            font.pixelSize: Style.font.body
            font.weight: modelData.key === root.section ? Font.DemiBold : Font.Normal
          }
          MouseArea {
            anchors.fill: parent
            onClicked: { root.navIndex = index; root.column = "content" }
          }
        }
      }
    }

    Item {
      id: content
      width: parent.width - nav.width - parent.spacing
      height: parent.height
      clip: true

      // Apple-style grouped card behind the page: a soft rounded panel
      // that sizes itself to whichever page is showing.
      Rectangle {
        id: pageCard
        readonly property Item page: {
          for (let i = 0; i < content.children.length; i++) {
            const c = content.children[i]
            if (c.settingsPage && c.visible) return c
          }
          return null
        }
        visible: page !== null
        width: parent.width
        height: page ? Math.min(parent.height, page.height + 2 * root.cardPad) : 0
        radius: Style.space(12)
        color: Util.alpha(SpinTheme.Palette.text, 0.06)
        border.width: 1
        border.color: Util.alpha(SpinTheme.Palette.text, 0.07)
      }

      // ---- Account ----
      Column {
        visible: root.section === "account"
        property bool settingsPage: true
        x: root.cardPad; y: root.cardPad
        width: parent.width - 2 * root.cardPad
        spacing: Style.space(14)

        Row {
          visible: root.signedIn
          spacing: Style.space(14)

          // Centred on the row (never on the name column: a taller avatar
          // would then start above the row and be cut flat by the clip).
          RoundCover {
            id: avatar
            objectName: "accountAvatar"
            width: Style.space(52)
            height: width
            anchors.verticalCenter: parent.verticalCenter
            source: root.svc && root.svc.accountDetails.avatar ? root.svc.accountDetails.avatar : ""
            fill: Util.alpha(root.fg, 0.12)
            foreground: root.fg
            glyph: root.svc ? root.initialsFor(root.svc.accountDetails.name) : "?"
            fontFamily: root.family
          }

          Column {
            id: nameCol
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)
            Text {
              text: root.svc ? (root.svc.accountDetails.name || "Signed in") : ""
              textFormat: Text.PlainText
              color: root.fg
              font.family: root.family
              font.pixelSize: Style.font.subtitle
            }
            Text {
              visible: root.svc && root.svc.accountDetails.email !== ""
              text: root.svc ? root.svc.accountDetails.email : ""
              textFormat: Text.PlainText
              color: Util.alpha(root.fg, 0.6)
              font.family: root.family
              font.pixelSize: Style.font.caption
            }
            Text {
              objectName: "accountHelp"
              text: root.svc && root.svc.premium ? "Signed in to YouTube Music Premium" : "Signed in to YouTube Music"
              textFormat: Text.PlainText
              color: Util.alpha(root.fg, 0.5)
              font.family: root.family
              font.pixelSize: Style.font.caption
            }
          }
        }
        Text {
          visible: !root.signedIn
          text: "Signed out"
          textFormat: Text.PlainText
          color: root.fg
          font.family: root.family
          font.pixelSize: Style.font.subtitle
        }

        Row {
          visible: !root.signedIn
          spacing: Style.space(8)
          QuietButton {
            objectName: "accountSignIn"
            label: "Sign in"
            row: 0
          }
        }
        Row {
          visible: root.signedIn
          spacing: Style.space(8)
          QuietButton {
            objectName: "accountSwitch"
            label: root.switchArmed ? "Press again to switch" : "Switch account"
            danger: root.switchArmed
            row: 0
          }
          QuietButton {
            objectName: "accountSignOut"
            label: root.signOutArmed ? "Press again to sign out" : "Sign out"
            danger: root.signOutArmed
            row: 1
          }
        }
        Text {
          objectName: "accountHelpText"
          text: root.signedIn && root.svc && root.svc.importedSession
                ? "Copied from your browser. Signing out here leaves your browser signed in; signing out there signs Spinbloom out too."
              : root.signedIn ? "Switching signs you out, then opens Google's account chooser."
              : "Signing in opens a Google window. It closes when you are in."
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          width: parent.width
          color: Util.alpha(root.fg, 0.5)
          font.family: root.family
          font.pixelSize: Style.font.caption
        }
        // Spinbloom: the power switch lives here now (it used to sit in the
        // player's top corner).
        Column {
          spacing: Style.space(6)
          QuietButton {
            objectName: "engineToggle"
            label: root.svc && root.svc.closed ? "Turn the music engine on" : "Turn the music engine off"
            row: root.signedIn ? 2 : 1
          }
          Text {
            text: root.svc && root.svc.closed ? "Nothing plays until it is on again." : "Stops the music and frees the engine's memory until you play again."
            textFormat: Text.PlainText
            color: Util.alpha(root.fg, 0.5)
            font.family: root.family
            font.pixelSize: Style.font.caption
          }
        }

        Text {
          visible: root.accountNote !== ""
          text: root.accountNote
          textFormat: Text.PlainText
          color: Util.alpha(root.fg, 0.6)
          font.family: root.family
          font.pixelSize: Style.font.caption
        }
      }

      // ---- Sound ----
      Column {
        visible: root.section === "sound"
        property bool settingsPage: true
        x: root.cardPad; y: root.cardPad
        width: parent.width - 2 * root.cardPad
        spacing: Style.space(10)

        RowShell {
          objectName: "eqRow"
          label: "Equalizer"
          row: 0
          MiniToggle { active: root.svc ? !!root.svc.setting("eqEnabled", false) : false }
        }

        Item {
          width: parent.width
          height: presetRow.implicitHeight + Style.space(8)
          Rectangle {
            anchors.fill: parent
            radius: Style.spacing.labelGap
            color: root.column === "content" && root.cursor === 1 ? SpinTheme.Palette.selected : "transparent"
          }
          MouseArea { anchors.fill: parent; onClicked: root.pointAt(1) }
          Row {
            id: presetRow
            anchors.left: parent.left
            anchors.leftMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)
            Repeater {
              model: Model.EQ_PRESET_ORDER
              delegate: Chip {
                required property string modelData
                objectName: "eqPreset_" + modelData
                label: Model.EQ_PRESET_LABELS[modelData]
                active: root.svc && root.svc.setting("eqPreset", "flat") === modelData
                onClicked: { root.pointAt(1); root.setEqPreset(modelData) }
              }
            }
          }
        }

        Row {
          spacing: Style.space(10)
          Repeater {
            model: 10
            delegate: Item {
              id: bandCell
              required property int index
              readonly property real db: root.section === "sound" ? Model.eqBandDb(root.currentBands(), index) : 0
              readonly property bool bandFocused: root.column === "content" && root.cursor === index + 2
              width: bandCol.implicitWidth + Style.space(8)
              height: bandCol.implicitHeight + Style.space(8)

              HoverHandler { id: bandHover }
              Rectangle {
                anchors.fill: parent
                radius: Style.spacing.labelGap
                color: bandHover.hovered ? SpinTheme.Palette.fillHover : bandCell.bandFocused ? SpinTheme.Palette.selected : "transparent"
              }

              Column {
                id: bandCol
                anchors.centerIn: parent
                spacing: Style.space(4)
                Item {
                  id: track
                  objectName: "eqBandTrack" + bandCell.index
                  width: Style.space(18)
                  height: Style.space(90)
                  // Press or drag on the track: the knob goes where the
                  // pointer is (whole dB, -12..+12, like the arrow keys).
                  // Margins reach the knob's half hanging past either end.
                  MouseArea {
                    anchors.fill: parent
                    anchors.margins: -Style.space(7)
                    cursorShape: Qt.PointingHandCursor
                    preventStealing: true
                    function place(mouse) {
                      var y = mouse.y - Style.space(7)
                      root.pointAt(bandCell.index + 2)
                      root.setBand(bandCell.index, (track.height / 2 - y) / (track.height / 2) * 12)
                    }
                    onPressed: function (mouse) { place(mouse) }
                    onPositionChanged: function (mouse) { if (pressed) place(mouse) }
                  }
                  Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    width: 2
                    height: parent.height
                    color: Util.alpha(root.fg, 0.15)
                  }
                  Rectangle {
                    width: Style.space(14); height: width; radius: width / 2
                    // White knobs in both themes (Apple's sliders); in a
                    // light theme a hairline edge keeps them visible.
                    color: SpinTheme.Palette.light ? "white" : (bandCell.db !== 0 ? SpinTheme.Palette.accent : root.fg)
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: (parent.height / 2) - (bandCell.db / 12) * (parent.height / 2) - height / 2
                    border.width: bandCell.bandFocused ? 2 : SpinTheme.Palette.light ? 1 : 0
                    border.color: bandCell.bandFocused ? Util.alpha(SpinTheme.Palette.accent, 0.6) : Util.alpha(SpinTheme.Palette.text, 0.18)
                  }
                }
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: (bandCell.db > 0 ? "+" : "") + bandCell.db
                  textFormat: Text.PlainText
                  color: Util.alpha(root.fg, 0.6)
                  font.family: root.family
                  font.pixelSize: Style.font.caption
                }
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: Model.EQ_BAND_HZ[bandCell.index]
                  textFormat: Text.PlainText
                  color: Util.alpha(root.fg, 0.45)
                  font.family: root.family
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }
        }

        RowShell {
          label: "Preamp"
          row: 12
          StepValue { objectName: "preampStep"; row: 12; value: (root.svc ? root.svc.setting("eqPreamp", 0) : 0) + " dB" }
        }
        RowShell {
          label: "Even out loudness"
          help: "A compressor: quiet songs come up, loud ones do not clip"
          row: 13
          MiniToggle { active: root.svc ? !!root.svc.setting("eqLoudness", false) : false }
        }
      }

      // ---- Playback ----
      Column {
        visible: root.section === "playback"
        property bool settingsPage: true
        x: root.cardPad; y: root.cardPad
        width: parent.width - 2 * root.cardPad
        spacing: Style.space(6)

        RowShell {
          label: "Sleep timer"
          help: "Fades the volume over 10 s, then pauses"
          row: 0
          Repeater {
            model: [["off", "Off"], ["15", "15 min"], ["30", "30 min"], ["60", "1 hour"], ["end", "Song end"]]
            delegate: Chip {
              required property var modelData
              label: modelData[1]
              active: !!root.svc && root.svc.sleepMode === modelData[0]
              onClicked: { root.pointAt(0); if (root.svc) root.svc.setSleepMode(modelData[0]) }
            }
          }
        }
        RowShell {
          label: "When Spinbloom starts"
          row: 1
          Chip { label: "Play"; active: !(root.svc && root.svc.setting("startPaused", false)); onClicked: { root.pointAt(1); if (root.svc) root.svc.saveSetting("startPaused", false) } }
          Chip { label: "Stay paused"; active: !!(root.svc && root.svc.setting("startPaused", false)); onClicked: { root.pointAt(1); if (root.svc) root.svc.saveSetting("startPaused", true) } }
        }
        RowShell {
          label: "Volume at start"
          row: 2
          Repeater {
            model: [["last", "Last"], ["25", "25%"], ["50", "50%"], ["75", "75%"], ["100", "100%"]]
            delegate: Chip {
              required property var modelData
              label: modelData[1]
              active: !!root.svc && String(root.svc.setting("startVolume", "last")) === modelData[0]
              onClicked: { root.pointAt(2); if (root.svc) root.svc.saveSetting("startVolume", modelData[0]) }
            }
          }
        }
        RowShell {
          label: "Start with the shell"
          row: 3
          MiniToggle { active: root.svc ? !!root.svc.setting("autostart", true) : true }
        }
        RowShell {
          label: "Browser for the engine"
          help: "An absolute path to a Chromium-family browser (never a bare command)"
          row: 4
          Repeater {
            model: Model.browserChoices(root.svc ? root.svc.browsers : [], root.svc ? root.svc.setting("browser", "") : "")
            delegate: Chip {
              required property string modelData
              label: Model.browserLabel(modelData)
              active: !!root.svc && root.svc.setting("browser", "") === modelData
              onClicked: { root.pointAt(4); if (root.svc) root.svc.saveSetting("browser", modelData) }
            }
          }
        }
        RowShell {
          visible: root.braveEngine
          label: "Brave's ad blocker"
          help: "Lets Brave fetch its filter lists, so it can block adverts. Off keeps the engine from any background updates"
          row: 5
          MiniToggle { active: root.svc ? !!root.svc.setting("braveAdBlock", false) : false }
        }
      }

      // ---- Bar and alerts ----
      // ---- Appearance ----
      Column {
        visible: root.section === "look"
        property bool settingsPage: true
        x: root.cardPad; y: root.cardPad
        width: parent.width - 2 * root.cardPad
        spacing: Style.space(6)

        RowShell {
          label: "Artwork style"
          help: root.artworkStyle === "dial"
            ? "Dial: one large cover with a wheel of discs below it."
            : "Flow: covers side by side, tilted like a row of records."
          row: 0
          Chip { label: "Dial"; active: root.artworkStyle === "dial"; onClicked: { root.pointAt(0); root.setArtworkStyle("dial") } }
          Chip { label: "Flow"; active: root.artworkStyle === "flow"; onClicked: { root.pointAt(0); root.setArtworkStyle("flow") } }
        }
        RowShell {
          label: "Calm motion"
          help: "Songs simply cross-fade: no flying disc, drifting background or spinning discs."
          row: 1
          MiniToggle { active: root.calmMotion }
        }
        RowShell {
          label: "Colour from album artwork"
          help: root.albumColors
            ? "The background takes its colours from the song's artwork."
            : "A plain frosted background in your desktop theme's colours."
          row: 2
          MiniToggle { active: root.albumColors }
        }
        // Spinbloom: Hyprland blur for panels only (GlassBlur.qml). Off: the
        // player still has frosted glass, made from the wallpaper.
        RowShell {
          label: "Use desktop blur"
          help: root.userBlur
            ? "Your desktop already blurs panels, so the player uses it."
            : root.desktopBlur
              ? "Hyprland blurs what is behind the player and other panels. App windows are not blurred."
              : "Your desktop has blur off, so the player uses solid glass. Turn this on for real frosted glass (panels only, app windows unchanged)."
          row: 3
          opacity: root.userBlur ? 0.5 : 1
          MiniToggle { active: root.desktopBlur || root.userBlur }
        }
        RowShell {
          label: "Player size"
          help: root.playerSize === "full" ? "Full: cover, CD wheel, seek bar, volume and every button."
            : root.playerSize === "compact" ? "Compact: about half the height. Cover, title, heart, a thin progress line and Previous · Play · Next."
            : "Small: like Compact, but narrower with a smaller cover."
          row: 4
          Chip { label: "Full"; active: root.playerSize === "full"; onClicked: { root.pointAt(4); root.setPlayerSize("full") } }
          Chip { label: "Compact"; active: root.playerSize === "compact"; onClicked: { root.pointAt(4); root.setPlayerSize("compact") } }
          Chip { label: "Small"; active: root.playerSize === "small"; onClicked: { root.pointAt(4); root.setPlayerSize("small") } }
        }
        RowShell {
          label: "CD wheel in compact"
          help: root.compactWheel ? "The compact player keeps the wheel of discs under the cover." : "The compact player shows just the cover."
          row: 5
          opacity: root.playerSize === "full" ? 0.5 : 1
          MiniToggle { active: root.compactWheel }
        }
      }

      Column {
        visible: root.section === "bar"
        property bool settingsPage: true
        x: root.cardPad; y: root.cardPad
        width: parent.width - 2 * root.cardPad
        spacing: Style.space(6)

        RowShell { label: "Previous, play/pause and next in the bar"; row: 0
          MiniToggle { active: root.svc ? !!root.svc.setting("barControls", true) : true } }
        RowShell { label: "Song title in the bar"; row: 1
          MiniToggle { active: root.svc ? !!root.svc.setting("showTitle", false) : true } }
        RowShell { label: "Title width in the bar"; row: 2
          StepValue { row: 2; value: (root.svc ? root.svc.setting("maxLabelWidth", 160) : 160) + " px" } }
        RowShell { label: "Show in the bar when nothing is loaded"; row: 3
          MiniToggle { active: root.svc ? !!root.svc.setting("showWhenIdle", true) : true } }
        RowShell { label: "Notify when the song changes"; row: 4
          MiniToggle { active: root.svc ? !!root.svc.setting("notify", true) : true } }
      }

      // ---- Keys ----
      Column {
        visible: root.section === "keys"
        property bool settingsPage: true
        x: root.cardPad; y: root.cardPad
        width: parent.width - 2 * root.cardPad
        spacing: Style.space(6)

        RowShell {
          objectName: "globalKeysRow"
          label: "Global shortcuts"
          help: "Super+M panel, Super+Alt+M play/pause, Super+Alt+N next, Super+Alt+B previous, Super+Alt+L like"
          row: 0
          MiniToggle { active: root.svc ? !!root.svc.setting("globalKeys", true) : true }
        }
        RowShell {
          label: "Every key"
          row: 1
          QuietButton { label: "All keys" }
        }
      }

      // ---- Advanced ----
      Column {
        visible: root.section === "advanced"
        property bool settingsPage: true
        x: root.cardPad; y: root.cardPad
        width: parent.width - 2 * root.cardPad
        spacing: Style.space(6)

        RowShell { label: "Refresh the page when memory passes"; help: "Applies on next start"; row: 0
          StepValue { row: 0; value: Model.recycleHeapMbFor(root.svc ? root.svc.setting("recycleHeapMb", 400) : 400) + " MB" } }
        RowShell { label: "Refresh at least every"; help: "Applies on next start"; row: 1
          StepValue { row: 1; value: Model.recycleHoursFor(root.svc ? root.svc.setting("recycleHours", 12) : 12) + " h" } }
        RowShell { label: "Clear cache"; help: root.cacheNote !== "" ? root.cacheNote : "Keeps you signed in"; row: 2
          QuietButton { label: "Clear" } }
        RowShell { label: "Reset settings"; row: 3
          QuietButton { label: "Reset" } }
        RowShell {
          label: "Erase engine data"
          help: root.eraseArmed ? "Press again to erase. This signs you out." : (root.eraseNote !== "" ? root.eraseNote : "Deletes the profile; signs you out")
          row: 4
          QuietButton { label: root.eraseArmed ? "Press again" : "Erase"; danger: true }
        }
      }

      // ---- About ----
      Column {
        visible: root.section === "about"
        property bool settingsPage: true
        x: root.cardPad; y: root.cardPad
        width: parent.width - 2 * root.cardPad
        spacing: Style.space(6)

        Text { text: "Spinbloom"; textFormat: Text.PlainText; color: SpinTheme.Palette.text; font.family: root.family; font.pixelSize: Style.font.title; font.weight: Font.Bold }
        // Plain text and a quiet link in the player's own colours (no rich
        // text, so no browser-blue link colour).
        Row {
          spacing: Style.space(4)
          Text { text: "Built on"; textFormat: Text.PlainText; color: SpinTheme.Palette.secondary; font.family: root.family; font.pixelSize: Style.font.caption }
          Text {
            text: "Solfa by SirAllap"
            textFormat: Text.PlainText
            color: creditLink.containsMouse ? SpinTheme.Palette.text : SpinTheme.Palette.secondary
            font.family: root.family
            font.pixelSize: Style.font.caption
            font.weight: Font.DemiBold
            font.underline: creditLink.containsMouse
            MouseArea {
              id: creditLink
              anchors.fill: parent
              anchors.margins: -Style.space(3)
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: Qt.openUrlExternally("https://github.com/SirAllap/omarchy-solfa")
            }
          }
        }
        Text { text: "Engine: " + root.engineVersionText; textFormat: Text.PlainText; color: SpinTheme.Palette.tertiary; font.family: root.family; font.pixelSize: Style.font.caption }
      }
    }
  }
}
