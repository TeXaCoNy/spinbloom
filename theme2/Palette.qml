pragma Singleton

import QtQuick
import qs.Commons

// Spinbloom design 2 palette for the full player (Panel2 and views2).
// Same names as the old shared theme's Palette so the copied views keep working,
// except `accent` is writable: Panel2 binds it to the album colour, so every
// highlight in the design-2 screens follows the artwork. The classic screens
// import the old shared theme and keep the theme accent.
QtObject {
    property color accent: Color.accent
    readonly property color text: Color.popups.text
    // A light desktop theme (dark text): controls switch to Apple's light
    // look (white knobs and selected chips, soft grey tracks).
    readonly property bool light: (text.r + text.g + text.b) / 3 < 0.5
    readonly property color card: Util.alpha(Color.popups.background, 1)
    readonly property color glass: Qt.tint(card, Qt.rgba(0, 0, 0, 0.05))
    readonly property color onAccent: Util.alpha(Color.popups.background, 1)
    readonly property color fill: Util.alpha(text, 0.07)
    readonly property color fillHover: Util.alpha(text, 0.11)
    readonly property color fillPressed: Util.alpha(text, 0.15)
    readonly property color hover: fillHover
    readonly property color selected: Util.alpha(text, 0.12)
    readonly property color bubble: Util.alpha(text, 0.12)
    readonly property color secondary: Util.alpha(text, 0.60)
    readonly property color tertiary: Util.alpha(text, 0.42)
    readonly property color outline: Util.alpha(text, 0.14)
    readonly property color hairline: Util.alpha(text, 0.10)
    readonly property color edge: Util.alpha(text, 0.14)
}
