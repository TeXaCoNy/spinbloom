import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Spinbloom: frosted glass for the player on every desktop, with nothing to set
// up and no config file edited.
//
// 1. The player asks Hyprland itself (at runtime, `hyprctl eval`) to blur
//    what is behind its window: the same rule a user would otherwise write in
//    their own Hyprland config.
// 2. Hyprland only blurs anything when its blur main switch is on, and
//    Omarchy ships with it off. Then `compositor` is false and the player's
//    glass turns almost solid (apps cannot see other windows on Wayland, so
//    there is nothing honest to show through it), with a one-time tip.
// 3. Optional (Settings → Appearance → "Use desktop blur", off by default):
//    the player turns Hyprland blur on for panels only (every app window opts
//    out, so windows look as before). Runtime only: it is undone by turning
//    the switch off, and a Hyprland restart forgets it.
Item {
  id: g
  property var svc: null

  // The player's window (ArtworkPopup2 / LibraryPopup2 layer namespace).
  readonly property string ns: "spinbloom-player"

  readonly property bool wantDesktopBlur: !!svc && String(svc.setting("desktopBlur", true)) === "true"
  // Hyprland's blur main switch is on (whoever turned it on).
  property bool hyprBlur: false
  // It is on because this player turned it on (option 3).
  property bool ours: false
  property bool known: false
  // Real blur behind the player is available.
  // Test hook (IPC glassPreview solid|auto): show the player as it looks
  // without Hyprland blur, without touching Hyprland.
  property bool previewSolid: false
  readonly property bool compositor: hyprBlur && !previewSolid
  // The user's own Hyprland config already blurs (option 3 not needed).
  readonly property bool userBlur: hyprBlur && !ours

  readonly property string sig: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || ""
  readonly property string markDir: Quickshell.env("HOME") + "/.local/state/spinbloom"
  readonly property string markPath: markDir + "/desktop-blur"

  function lua(code) { Quickshell.execDetached(["/usr/bin/hyprctl", "eval", code]) }

  // One handle per rule set in a Lua global, so registering again (every
  // shell start, every reload) never stacks rules.
  function registerRule() {
    lua("local R = _G.__spinbloom_player_glass; if R then for _, r in pairs(R) do pcall(function() r:set_enabled(false) end) end end; " +
        "_G.__spinbloom_player_glass = { hl.layer_rule({ match = { namespace = [[^" + ns + "$]] }, " +
        "blur = true, blur_popups = true, ignore_alpha = 0.2, no_anim = true }) }")
  }

  function enableDesktop() {
    lua("local R = _G.__spinbloom_desktop_blur; if R then pcall(function() R:set_enabled(false) end) end; " +
        "hl.config({ decoration = { blur = { enabled = true, size = 10, passes = 3, new_optimizations = true, xray = false, " +
        "contrast = 1.0, brightness = 0.85, noise = 0.015, vibrancy = 0.25, vibrancy_darkness = 0.2, popups = false, special = false } } }); " +
        "_G.__spinbloom_desktop_blur = hl.window_rule({ match = { class = [[.*]] }, no_blur = true })")
    Quickshell.execDetached(["/bin/sh", "-c", "mkdir -p \"$1\" && printf %s \"$2\" > \"$3\"", "sh", markDir, sig, markPath])
    g.ours = true
    g.hyprBlur = true
  }
  function disableDesktop() {
    lua("local R = _G.__spinbloom_desktop_blur; if R then pcall(function() R:set_enabled(false) end) end; _G.__spinbloom_desktop_blur = nil; " +
        "hl.config({ decoration = { blur = { enabled = false } } })")
    Quickshell.execDetached(["/bin/rm", "-f", markPath])
    g.ours = false
    g.hyprBlur = false
  }
  function apply() {
    if (!known) return
    if (wantDesktopBlur && !hyprBlur) enableDesktop()
    else if (!wantDesktopBlur && ours) disableDesktop()
  }
  onWantDesktopBlurChanged: apply()

  // Ask Hyprland whether blur is on, and whether that is our doing.
  function refresh() {
    registerRule()
    if (!query.running) query.running = true
  }
  Process {
    id: query
    command: ["/bin/sh", "-c", "/usr/bin/hyprctl -j getoption decoration:blur:enabled; echo; echo '@@'; cat \"$1\" 2>/dev/null", "sh", g.markPath]
    stdout: StdioCollector {
      onStreamFinished: {
        var parts = String(text).split("@@")
        var on = false
        try {
          var o = JSON.parse(parts[0])
          on = o.bool === true || o.int === 1
        } catch (e) { on = false }
        var mark = parts.length > 1 ? parts[1].trim() : ""
        g.hyprBlur = on
        g.ours = on && mark !== "" && mark === g.sig
        g.known = true
        g.apply()
      }
    }
  }

  Component.onCompleted: refresh()
  // A Hyprland config reload wipes runtime rules and options: set them again.
  Connections {
    target: Hyprland
    function onRawEvent(event) { if (event.name === "configreloaded") refreshLater.restart() }
  }
  Timer { id: refreshLater; interval: 400; onTriggered: g.refresh() }
}
