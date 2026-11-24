.pragma library

// Model.js — the logic behind Spinbloom's QML, kept free of Qt objects so node
// can test it (tests/model.test.cjs).

var PLUGIN_ID = "spinbloom"

// The version this code is, kept equal to manifest.json's by a test. The
// shell's plugin reload reuses the QML it compiled before (it never clears
// its component cache), so a Service still running older code after an
// update sees a newer manifest on disk than this: it then asks for a shell
// restart instead of leaving the panel on "Starting Spinbloom".
var CODE_VERSION = "2.0.0"

function engineLineWhileDown(manifestVersion) {
  return manifestVersion !== "" && manifestVersion !== CODE_VERSION
    ? "Spinbloom was updated. Restart the shell to finish" : "Starting Spinbloom"
}

function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

// ---------------------------------------------------------------- bridge lifecycle (Service.qml)

// H1: the shell must keep trying to bring the bridge back — after it never
// answers, and after it answers, then drops — but never in a tight loop.
// Same backoff either way: double the delay (capped), and give the unit at
// least this long to show up on the socket before trying again.
function nextRetryDelay(current) { return Math.min(30000, (Number(current) || 1000) * 2) }
function retryTimerInterval(delay) { return Math.max(3000, Number(delay) || 0) }

// H2: a launch key + manifest version this session has already asked the
// bridge to restart for is never asked again — a bridge that keeps
// reporting a mismatch (a forgotten version bump, for instance) gets one
// restart, not a loop.
function restartTag(envKey, version) { return String(envKey) + "@" + String(version) }
function shouldRestartForStale(staleKey, staleVersion, lastTag, tag) {
  return (staleKey || staleVersion) && lastTag !== tag
}

// Where the song is now: the last pushed position plus the time since,
// while it plays. The page pushes on changes only; this fills the gaps.
function positionAt(player, nowMs) {
  if (!player || !player.videoId) return 0
  var pos = Number(player.position) || 0
  if (player.playing && !player.buffering && !player.ad && player.at) pos += Math.max(0, (nowMs - player.at) / 1000)
  var d = Number(player.duration) || 0
  return d > 0 ? clamp(pos, 0, d) : Math.max(0, pos)
}

function fmtTime(sec) {
  sec = Math.max(0, Math.floor(Number(sec) || 0))
  var h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), s = sec % 60
  return (h ? h + ":" + (m < 10 ? "0" : "") : "") + m + ":" + (s < 10 ? "0" : "") + s
}

function artistsText(list) {
  var out = []
  for (var i = 0; i < (list || []).length; i++) if (list[i] && list[i].name) out.push(list[i].name)
  return out.join(", ")
}

// The second line of a row.
function rowSubtitle(item) {
  if (!item) return ""
  if (item.videoId) return artistsText(item.artists) || (item.album ? item.album.name : "")
  return item.subtitle || artistsText(item.artists)
}

// A row's second line with its type in front ("Video · Artist").
function labelled(label, subtitle) {
  return label ? (subtitle ? label + " · " + subtitle : label) : subtitle
}

function nextRepeat(mode) {
  return mode === "NONE" ? "ALL" : mode === "ALL" ? "ONE" : "NONE"
}

function repeatLabel(mode) {
  return mode === "ALL" ? "Repeat all" : mode === "ONE" ? "Repeat one" : "Repeat off"
}

function nextLike(status) { return status === "LIKE" ? "INDIFFERENT" : "LIKE" }

function volumeAfter(current, steps) { return clamp(Math.round((Number(current) || 0) + steps * 5), 0, 100) }

// ------------------------------------------------------------------ lists

var GROUPS = [
  { key: "top", label: "Top result", most: 1 },
  { key: "songs", label: "Songs", most: 6 },
  { key: "albums", label: "Albums", most: 4 },
  { key: "artists", label: "Artists", most: 3 },
  { key: "playlists", label: "Playlists", most: 4 },
  { key: "videos", label: "Videos", most: 3 }
]

// What a result's type is called in the unfiltered list (albums, playlists
// and artists carry theirs in the subtitle already).
var KIND_LABELS = { song: "Song", video: "Video", episode: "Episode" }

// A search result as one list: section headers and rows. With a filter,
// only that group, and all of it. Without one, YouTube Music's own order:
// the top result, then everything else as the reply ranked it, songs and
// videos side by side and nothing left out.
function searchRows(result, filter) {
  var rows = []
  if (!result) return rows
  if (!filter && Array.isArray(result.all)) {
    if (result.top) {
      rows.push({ header: "Top result" })
      rows.push({ item: result.top, label: KIND_LABELS[result.top.kind] || "" })
    }
    if (result.all.length) rows.push({ header: result.top ? "More results" : "Results" })
    for (var n = 0; n < result.all.length; n++) rows.push({ item: result.all[n], label: KIND_LABELS[result.all[n].kind] || "" })
    return rows
  }
  for (var g = 0; g < GROUPS.length; g++) {
    var group = GROUPS[g]
    if (filter && group.key !== filter) continue
    var items = group.key === "top" ? (result.top ? [result.top] : []) : (result[group.key] || [])
    if (!filter) items = items.slice(0, group.most)
    if (items.length === 0) continue
    if (!filter) rows.push({ header: group.label, more: group.key !== "top" && (result[group.key] || []).length > group.most ? group.key : "" })
    for (var i = 0; i < items.length; i++) rows.push({ item: items[i] })
  }
  return rows
}

// Shelves of a page (artist, home, library) as one list.
function sectionRows(sections, mostPerSection) {
  var rows = []
  for (var s = 0; s < (sections || []).length; s++) {
    var sec = sections[s]
    if (!sec || !sec.items || sec.items.length === 0) continue
    if (sec.title) rows.push({ header: sec.title, more: sec.more ? sec.more.browseId : "", moreParams: sec.more ? sec.more.params : "" })
    var items = mostPerSection ? sec.items.slice(0, mostPerSection) : sec.items
    for (var i = 0; i < items.length; i++) rows.push({ item: items[i] })
  }
  return rows
}

function trackRows(tracks) {
  var rows = []
  for (var i = 0; i < (tracks || []).length; i++) rows.push({ item: tracks[i], n: i + 1 })
  return rows
}

// Spinbloom: the queue the Apple way: the playing song under "Now Playing",
// then "Up Next" (songs after it), then Autoplay. Songs already played are
// left out here (the History tab has them).
function upNextRows(queue) {
  var rows = []
  if (!queue) return rows
  var items = queue.items || []
  var ci = -1
  for (var i = 0; i < items.length; i++) {
    var qi = typeof items[i].queueIndex === "number" ? items[i].queueIndex : i
    if (qi === queue.index) { ci = i; break }
  }
  if (ci >= 0) {
    rows.push({ header: "Now Playing" })
    rows.push({ item: items[ci], queueIndex: typeof items[ci].queueIndex === "number" ? items[ci].queueIndex : ci, current: true })
  }
  var next = items.slice(ci + 1)
  rows.push({ header: "Up Next", upNext: true })
  for (var j = 0; j < next.length; j++) {
    var k = ci + 1 + j
    rows.push({ item: next[j], queueIndex: typeof next[j].queueIndex === "number" ? next[j].queueIndex : k, current: false })
  }
  var auto = queue.automix || []
  if (auto.length) {
    rows.push({ header: "Autoplay" })
    for (var a = 0; a < auto.length; a++) rows.push({ item: auto[a], queueIndex: typeof auto[a].queueIndex === "number" ? auto[a].queueIndex : a, automix: true })
  }
  return rows
}

// The queue: what is queued, then what autoplay would pick.
function queueRows(queue) {
  var rows = []
  if (!queue) return rows
  var items = queue.items || []
  for (var i = 0; i < items.length; i++) rows.push({ item: items[i], queueIndex: typeof items[i].queueIndex === "number" ? items[i].queueIndex : i, current: (typeof items[i].queueIndex === "number" ? items[i].queueIndex : i) === queue.index })
  var auto = queue.automix || []
  if (auto.length) {
    rows.push({ header: "Autoplay" })
    for (var j = 0; j < auto.length; j++) rows.push({ item: auto[j], queueIndex: typeof auto[j].queueIndex === "number" ? auto[j].queueIndex : j, automix: true })
  }
  return rows
}

// Next row the cursor can stop on (headers are skipped).
function moveCursor(rows, index, delta) {
  if (!rows || rows.length === 0) return -1
  var i = index
  if (i < 0) i = delta > 0 ? -1 : rows.length
  for (var n = 0; n < rows.length; n++) {
    i += delta > 0 ? 1 : -1
    if (i < 0 || i >= rows.length) return index >= 0 && index < rows.length && isStop(rows[index]) ? index : firstRow(rows)
    if (isStop(rows[i])) return i
  }
  return index
}

// Rows the keyboard cursor can stop on: songs and items, not headers or the
// Spinbloom artwork shelves and grids (those are for the pointer).
function isStop(row) { return !!row && !row.header && !row.shelf && !row.grid }

function firstRow(rows) {
  for (var i = 0; i < (rows || []).length; i++) if (isStop(rows[i])) return i
  return -1
}

// Spinbloom: sections as Apple-style shelves. A section that is (nearly) all
// songs stays a list of rows (at most `mostSongs`); anything else (albums,
// playlists, artists, mixes) becomes one row of artwork tiles.
function mostlySongs(items) {
  var n = 0
  for (var i = 0; i < (items || []).length; i++) if (items[i] && items[i].videoId) n++
  return items && items.length > 0 && n >= items.length * 0.8
}
function shelfRows(sections, mostSongs) {
  var rows = []
  for (var s = 0; s < (sections || []).length; s++) {
    var sec = sections[s]
    if (!sec || !sec.items || sec.items.length === 0) continue
    if (sec.title) rows.push({ header: sec.title, more: sec.more ? sec.more.browseId : "", moreParams: sec.more ? sec.more.params : "" })
    if (mostlySongs(sec.items)) {
      var items = mostSongs ? sec.items.slice(0, mostSongs) : sec.items
      for (var i = 0; i < items.length; i++) rows.push({ item: items[i] })
    } else {
      rows.push({ shelf: true, items: sec.items.slice(0, 24) })
    }
  }
  return rows
}
// Spinbloom: every section as a wrapping grid of tiles (Library's grid view).
function gridRows(sections) {
  var rows = []
  var many = (sections || []).filter(function (s) { return s && s.items && s.items.length }).length > 1
  for (var s = 0; s < (sections || []).length; s++) {
    var sec = sections[s]
    if (!sec || !sec.items || sec.items.length === 0) continue
    if (many && sec.title) rows.push({ header: sec.title })
    rows.push({ grid: true, items: sec.items })
  }
  return rows
}

// The line being sung (lines sorted by start, ms). -1 before the first.
function lyricIndex(lines, ms) {
  var lo = 0, hi = (lines || []).length - 1, ans = -1
  while (lo <= hi) {
    var mid = (lo + hi) >> 1
    if (lines[mid].t <= ms) { ans = mid; lo = mid + 1 } else hi = mid - 1
  }
  return ans
}

// ------------------------------------------------------------------ bridge

// Pending requests whose time is up.
function expired(pending, nowMs) {
  var out = []
  for (var id in pending) if (pending[id] && pending[id].deadline <= nowMs) out.push(Number(id))
  return out
}

// Words for the engine's state, for the one line that explains it.
function engineLine(engine, account) {
  var st = engine ? engine.status : ""
  if (st === "ready") {
    if (account && account.host && account.host !== "music.youtube.com") return "Waiting for sign-in"
    return ""
  }
  if (st === "starting") return "Starting YouTube Music"
  if (st === "attaching") return "Connecting"
  if (st === "stuck") return "YouTube Music stopped answering. Restarting it"
  if (st === "crashed") return "YouTube Music closed. Starting it again"
  if (st === "signing-in") return "Signing in, in the Google window"
  if (st === "stopped") return engine && engine.error ? engine.error : "Spinbloom is off"
  return "Starting"
}

function errorText(code) {
  switch (code) {
    case "signin-required": return "Sign in to do that"
    case "bad-args": return "That request was not valid"
    case "timeout": return "YouTube Music took too long to answer"
    case "bridge-down": return "Spinbloom's helper is restarting"
    case "not-on-app": return "Finish signing in first"
    case "engine-signing-in": return "Finish signing in first"
    case "playing": return "That song is playing; skip it first"
    case "not-found": return "Nothing found"
    case "sleep-pause-failed": return "The sleep timer could not pause; the volume was left down"
    case "engine-busy": return "YouTube Music did not close; try again"
    case "signin-failed": return "Signing in did not finish; YouTube Music is still signed out"
    case "erase-refused": return "That folder is not Spinbloom's engine profile; nothing was deleted"
    case "erase-failed": return "Some engine data could not be deleted"
    default:
      if (/^engine-/.test(code || "")) return "YouTube Music is not ready yet"
      if (/^http-/.test(code || "")) return "YouTube Music refused the request (" + code.slice(5) + ")"
      return "Something went wrong (" + (code || "unknown") + ")"
  }
}

// ------------------------------------------------------------------ keys

// Each key calls the service over the shell's IPC (no process of ours to
// start per press), so a failure is reported like any other user action.
// Each command has a first-choice key and fallbacks. The first one nobody
// else holds is used; a key another app holds is never taken (Super+M stays
// Omarchy's minimize). Mods: Super 64, Shift 1, Ctrl 4, Alt 8.
var KEY_CHOICES = [
  { command: "toggle", description: "Spinbloom: open or close",
    choices: ["SUPER + ALT + M", "SUPER + SHIFT + M", "SUPER + CTRL + M"] },
  { command: "playPause", description: "Spinbloom: play or pause",
    choices: ["SUPER + ALT + P", "SUPER + SHIFT + P", "SUPER + CTRL + P"] },
  { command: "next", description: "Spinbloom: next song",
    choices: ["SUPER + ALT + N", "SUPER + ALT + PERIOD"] },
  { command: "previous", description: "Spinbloom: previous song",
    choices: ["SUPER + ALT + B", "SUPER + ALT + V"] },
  { command: "like", description: "Spinbloom: like",
    choices: ["SUPER + ALT + L", "SUPER + ALT + H"] }
]
var MOD_BITS = { SUPER: 64, SHIFT: 1, CTRL: 4, ALT: 8 }
var MOD_ORDER = [["SUPER", 64], ["SHIFT", 1], ["CTRL", 4], ["ALT", 8]]

function parseKeys(keys) {
  var parts = String(keys).split(" + "), mods = 0
  for (var i = 0; i < parts.length - 1; i++) mods |= MOD_BITS[parts[i]] || 0
  return { keys: keys, mods: mods, key: parts[parts.length - 1].toUpperCase() }
}

// Binds that are ours (by their description).
var OWN_KEY_RE = /^Spinbloom:/

function bindList(bindsJson) {
  try { var b = JSON.parse(bindsJson || "[]"); return Array.isArray(b) ? b : null } catch (e) { return null }
}

// For each command, the first of its keys that nobody else holds.
function freeKeys(bindsJson) {
  var binds = bindList(bindsJson)
  if (!binds) return []
  var taken = {}
  for (var i = 0; i < binds.length; i++) {
    var b = binds[i]
    if (!b || OWN_KEY_RE.test(b.description || "")) continue
    taken[(b.modmask | 0) + ":" + String(b.key || "").toUpperCase()] = true
  }
  var out = []
  for (var c = 0; c < KEY_CHOICES.length; c++) {
    var k = KEY_CHOICES[c]
    for (var j = 0; j < k.choices.length; j++) {
      var pk = parseKeys(k.choices[j])
      if (taken[pk.mods + ":" + pk.key]) continue
      taken[pk.mods + ":" + pk.key] = true
      out.push({ keys: pk.keys, mods: pk.mods, key: pk.key, command: k.command, description: k.description })
      break
    }
  }
  return out
}

// A bind from `hyprctl -j binds` written back as "SUPER + ALT + M".
function bindKeys(b) {
  // Only a plain key name goes into the Lua string (never "]]" or a newline).
  if (!/^[A-Za-z0-9_]{1,32}$/.test(String(b.key || ""))) return ""
  var m = b.modmask | 0, names = []
  for (var i = 0; i < MOD_ORDER.length; i++) if (m & MOD_ORDER[i][1]) names.push(MOD_ORDER[i][0])
  names.push(String(b.key || "").toUpperCase())
  return names.join(" + ")
}

// Lua for `hyprctl eval`: our old binds removed first (any key, either name),
// so a reload, a changed choice or the rename never leaves one behind.
function bindLua(entries, shellBin, bindsJson) {
  var bin = shellBin || "/usr/share/omarchy/bin/omarchy-shell"
  var lua = bindsJson ? unbindLua(bindsJson) : ""
  for (var i = 0; i < entries.length; i++) {
    var e = entries[i]
    var cmd = e.command === "toggle"
      ? bin + " shell toggle " + PLUGIN_ID + " '{}'"
      : bin + " " + PLUGIN_ID + " " + e.command
    lua += "pcall(hl.unbind, [[" + e.keys + "]]); "
    lua += "hl.bind([[" + e.keys + "]], hl.dsp.exec_cmd([[" + cmd + "]]), { description = [[" + e.description + "]] }); "
  }
  return lua
}

function unbindLua(bindsJson) {
  var binds = bindList(bindsJson)
  if (!binds) return ""
  var lua = "", seen = {}
  for (var j = 0; j < binds.length; j++) {
    var b = binds[j]
    if (!b || !OWN_KEY_RE.test(b.description || "")) continue
    var k = bindKeys(b)
    if (!k || seen[k]) continue
    seen[k] = true
    lua += "pcall(hl.unbind, [[" + k + "]]); "
  }
  return lua
}

// ------------------------------------------------------------------ notifications

function notifyText(player) {
  if (!player || !player.title) return null
  var body = artistsText(player.artists)
  if (player.album && player.album.name) body += (body ? " — " : "") + player.album.name
  return { summary: player.title, body: body }
}

// A value stepped by ←→ inside a fixed range (SettingsView's number rows).
function stepNumber(value, delta, lo, hi) { return clamp((Number(value) || 0) + delta, lo, hi) }

// The next (or previous) item of a fixed list, wrapping (SettingsView's
// preset/option rows: eqPreset, startVolume, browser...).
function cycleList(list, current, dir) {
  if (!list || list.length === 0) return current
  var i = list.indexOf(current)
  if (i < 0) i = 0
  i = (i + (dir > 0 ? 1 : -1) + list.length) % list.length
  return list[i]
}

// Settings > "Browser for the engine": Auto, then the browsers the bridge
// found installed (hello's `browsers`), then the current path when it is
// none of those (set by hand, or uninstalled since) so it stays shown and
// the cycle can leave it.
// Settings shows the Brave ad-blocker row only for a Brave engine: the same
// test the bridge uses (bin/spinbloom-engine blocks_ads) on the browser's file name.
function isBraveBrowser(path) {
  return String(path || "").split("/").pop().toLowerCase().indexOf("brave") >= 0
}

// How Settings names an engine browser: "Auto" for none, the well-known
// ones by their product name, anything else by its file name, capitalized.
var BROWSER_NAMES = {
  "chromium": "Chromium", "google-chrome-stable": "Google Chrome", "brave": "Brave",
  "brave-browser": "Brave", "vivaldi-stable": "Vivaldi", "microsoft-edge-stable": "Microsoft Edge"
}
function browserLabel(path) {
  var name = String(path || "").split("/").pop()
  if (name === "") return "Auto"
  return BROWSER_NAMES[name] || name.charAt(0).toUpperCase() + name.slice(1)
}

function browserChoices(installed, current) {
  var list = [""].concat(installed || [])
  if (current && list.indexOf(current) < 0) list.push(current)
  return list
}

// ------------------------------------------------------------------ settings

// Mirrors manifest.json's barWidget.defaults exactly (model.test.cjs checks
// the two stay in step). Settings > Advanced > "Reset settings" writes them
// over the current entry (settingsAfterReset), in one write.
var SETTINGS_DEFAULTS = {
  barControls: true, showTitle: false, maxLabelWidth: 160, showWhenIdle: true, notify: true,
  globalKeys: true, autostart: true, browser: "", braveAdBlock: false,
  eqEnabled: false, eqPreset: "flat", eqBands: "[0,0,0,0,0,0,0,0,0,0]", eqPreamp: 0, eqLoudness: false,
  startPaused: false, startVolume: "last", recycleHeapMb: 400, recycleHours: 12,
  artwork: "dial", albumColors: true, playerSize: "full", compactKind: "small", compactWheel: false, motion: "full", desktopBlur: true
}

function settingsAfterReset(current) {
  return Object.assign({}, current || {}, SETTINGS_DEFAULTS)
}

// What the bridge is started under (SPINBLOOM_LAUNCH_KEY): `autostart|browser|
// braveAdBlock`, from one settings snapshot. Truthiness is the one the
// SPINBLOOM_NO_LAUNCH / SPINBLOOM_BRAVE_ADBLOCK vars use (a hand-edited "false"
// string counts as on in both), so the key and the vars never disagree. The
// bridge parses it back from both ends, so a browser path may hold a "|".
function launchKey(settings) {
  var s = settings || {}
  var autostart = s.autostart === undefined || s.autostart === null ? true : s.autostart
  var browser = s.browser === undefined || s.browser === null ? "" : s.browser
  return (autostart ? "true" : "false") + "|" + String(browser) + "|" + (s.braveAdBlock ? "true" : "false")
}

// A bar widget starts with `{}` and gets its shell.json entry a moment
// later (the shell assigns the widget's `bar` before its `settings`). `{}`
// is not a settings entry: adopting it would start the engine under the
// defaults. A real entry always carries at least its id.
function hasSettings(incoming) {
  return !!incoming && typeof incoming === "object" && Object.keys(incoming).length > 0
}

// Settings writes go to shell.json through the shell, and come back to the
// service as the widget's whole entry, later. Writes not yet seen coming
// back (`pending`, key -> value) win over what an echo says, so a stale echo
// of an earlier write cannot undo a later one; an echo that carries a
// pending value confirms it.
function mergePendingSettings(incoming, pending) {
  var settings = Object.assign({}, incoming || {})
  var left = {}
  for (var k in pending) {
    if (JSON.stringify(settings[k]) === JSON.stringify(pending[k])) continue
    settings[k] = pending[k]
    left[k] = pending[k]
  }
  return { settings: settings, pending: left }
}

// Advanced > memory: SPINBLOOM_RECYCLE_HEAP_MB / SPINBLOOM_RECYCLE_HOURS. Too low
// and the page is swapped every hour; too high and V8's ceiling (768 MB)
// comes first.
var RECYCLE_HEAP_MB_RANGE = [200, 700]
var RECYCLE_HOURS_RANGE = [1, 72]
function recycleHeapMbFor(v) {
  var n = Number(v)
  return v === null || v === undefined || v === "" || !isFinite(n) ? 400 : clamp(Math.round(n), RECYCLE_HEAP_MB_RANGE[0], RECYCLE_HEAP_MB_RANGE[1])
}
function recycleHoursFor(v) {
  var n = Number(v)
  return v === null || v === undefined || v === "" || !isFinite(n) ? 12 : clamp(Math.round(n), RECYCLE_HOURS_RANGE[0], RECYCLE_HOURS_RANGE[1])
}

// ------------------------------------------------------------------ equalizer (Sound section; the graph itself is engine/agent.js)

var EQ_BAND_HZ = ["32", "64", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
var EQ_PRESETS = {
  flat: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  bass: [6, 5, 3, 1, 0, 0, 0, 0, 0, 0],
  treble: [0, 0, 0, 0, 0, 1, 2, 3, 4, 5],
  vocal: [-2, -2, -1, 1, 3, 3, 2, 0, -1, -1],
  loudness: [4, 3, 1, 0, -1, -1, 0, 1, 3, 4]
}
var EQ_PRESET_ORDER = ["flat", "bass", "treble", "vocal", "loudness", "custom"]
var EQ_PRESET_LABELS = { flat: "Flat", bass: "Bass", treble: "Treble", vocal: "Vocal", loudness: "Loudness", custom: "Custom" }

// The bands to show for a preset: the preset's own numbers, or (for
// "custom") whatever the user last set.
function eqBandsFor(preset, customBands) {
  var p = EQ_PRESETS[preset]
  if (p) return p.slice()
  return Array.isArray(customBands) && customBands.length === 10 ? customBands.slice() : EQ_PRESETS.flat.slice()
}

// eqBands is stored as a JSON string (the manifest schema has no array
// type); this is always a 10-number array, whatever is in the setting.
function parseEqBands(json) {
  try {
    var v = JSON.parse(json)
    if (Array.isArray(v) && v.length === 10) return v.map(function (n) { return clamp(Number(n) || 0, -12, 12) })
  } catch (e) { /* fall through */ }
  return EQ_PRESETS.flat.slice()
}

function eqBandDb(bands, index) { return clamp(Number((bands || [])[index]) || 0, -12, 12) }

// The eq.set payload actually sent to the page. Off (eqEnabled false) always
// means flat gains, no preamp and no loudness, whatever preset or custom
// bands are stored — they stay untouched in settings, so turning it back on
// returns exactly what was there before.
function eqPayload(enabled, preset, customBands, preamp, loudness) {
  if (!enabled) return { preset: "flat", bands: EQ_PRESETS.flat.slice(), preamp: 0, loudness: false }
  return { preset: preset, bands: eqBandsFor(preset, customBands), preamp: clamp(Number(preamp) || 0, -12, 0), loudness: !!loudness }
}

// ------------------------------------------------------------------ sleep timer (Playback; not persisted)

var SLEEP_OPTIONS = ["off", "15", "30", "60", "end"]
function sleepLabel(mode) {
  switch (mode) {
    case "15": return "15 min"
    case "30": return "30 min"
    case "60": return "60 min"
    case "end": return "End of song"
    default: return "Off"
  }
}
function nextSleepOption(mode, dir) {
  var i = SLEEP_OPTIONS.indexOf(mode)
  if (i < 0) i = 0
  i = (i + (dir > 0 ? 1 : -1) + SLEEP_OPTIONS.length) % SLEEP_OPTIONS.length
  return SLEEP_OPTIONS[i]
}
// Milliseconds until the 10 s fade should start for a plain countdown
// timer, or -1 for "off" and "end" (which have no fixed delay).
function sleepFadeDelayMs(mode) {
  var minutes = { "15": 15, "30": 30, "60": 60 }[mode]
  return minutes ? Math.max(0, minutes * 60000 - 10000) : -1
}
// "End of song": true the instant the fade should start — the armed song is
// still the one playing and is within its last 10 s of its own duration.
// False once a fade is already running (one-shot) or a different song is
// playing (skipped away from, or it already changed): whatever comes after
// the armed song never fires a fade of its own.
function shouldStartSleepFade(mode, armedVideoId, videoId, duration, position, alreadyFading) {
  if (mode !== "end" || !armedVideoId || alreadyFading) return false
  if (videoId !== armedVideoId) return false
  return duration > 0 && (duration - position) <= 10
}

// The fade: `steps` volume levels from the current volume down to 0, evenly
// spaced (Service.qml calls setVolume with each, one per tick).
function fadeVolumeSteps(fromVolume, steps) {
  steps = Math.max(1, Math.floor(steps) || 1)
  var out = []
  for (var i = 1; i <= steps; i++) out.push(Math.max(0, Math.round(fromVolume * (1 - i / steps))))
  return out
}

// The volume a fade had started from, to give back when the fade is cut
// short (the timer turned off or changed mid-fade); null when none runs.
function sleepVolumeToRestore(fadeVolume) {
  return fadeVolume >= 0 ? fadeVolume : null
}
// After the fade's pause, looked at a moment later: "restore" the volume
// once the song really is paused; "retry" the pause once if it is still
// playing; then "give-up" and stay faded down (a sleeper is not woken by
// the song coming back at full volume).
function sleepAfterPause(playing, tries) {
  if (!playing) return "restore"
  return tries < 1 ? "retry" : "give-up"
}

// startVolume: "last" (do nothing) or a 0-100 percent to apply once, after
// the engine's own restore has run. null means "leave it".
function startVolumeFor(setting) {
  if (setting === undefined || setting === null || setting === "last" || setting === "") return null
  var n = Number(setting)
  return isFinite(n) ? clamp(Math.round(n), 0, 100) : null
}

// ------------------------------------------------------------------ key hints

// Every panel key, for the "?" list.
var ALL_KEY_HINTS = [
  ["space", "play or pause"], ["n / p", "next / previous"], [", / .", "back / forward 10 s"], ["- / =", "volume"],
  ["m", "mute"], ["f / d", "like / dislike"], ["r", "repeat"], ["s", "shuffle"], ["1-5 or ← →", "tabs"], ["/", "search"],
  ["↵", "play or open"], ["e / a", "play next / add to queue"], ["R", "radio"], ["g / o", "artist / album"],
  ["x, J / K", "remove, move (queue)"], ["[ ]", "filter / section"], ["w", "show the YouTube window"], ["i", "sign in (signed out)"], ["esc", "back / close"],
  ["?", "show or hide this list"]
]

// The footer line: the view's main key, then play, next and like (when
// there is a song to like). Four at most; "?" sits apart, at the right.
// While a text field has the keys, letters and space type into it: only
// the field's own keys are shown.
function footerHints(viewHints, canLike, inField) {
  if (inField) return Array.isArray(viewHints) ? viewHints.slice(0, 4) : []
  var out = []
  var first = Array.isArray(viewHints) && viewHints.length ? viewHints[0] : null
  var common = [["space", "play/pause"], ["n p", "next/previous"]]
  if (canLike) common.push(["f", "like"])
  if (first && !common.some(function (h) { return h[0] === first[0] })) out.push(first)
  return out.concat(common).slice(0, 4)
}

// ------------------------------------------------------------------ save to a playlist (from Solfa 910e777)

// The picker's rows: "New playlist" first, then the playlists whose title
// holds what was typed (case does not matter), under "Recent" and "All
// playlists" as YouTube Music lists them (a header only over a group that
// has rows).
function saveRows(playlists, query) {
  var rows = [{ create: true }]
  var q = String(query || "").trim().toLowerCase()
  var list = (playlists || []).filter(function (p) { return q === "" || String(p.title || "").toLowerCase().indexOf(q) !== -1 })
  var groups = [{ label: "Recent", recent: true }, { label: "All playlists", recent: false }]
  for (var g = 0; g < groups.length; g++) {
    var items = list.filter(function (p) { return !!p.recent === groups[g].recent })
    if (items.length === 0) continue
    rows.push({ header: groups[g].label })
    for (var i = 0; i < items.length; i++) rows.push({ playlist: items[i] })
  }
  return rows
}
