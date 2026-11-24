import QtQuick
import QtTest
import Quickshell
import qs.Commons
import qs.Ui
import "views2" as Views

// Spinbloom running and closed, rendered once offscreen by a private
// Quickshell (test_closed.py): the bar pill playing and closed, and the
// panel's top (song, name, power button) running, with the pointer on the
// power button, and closed. Saves a picture to $SPINBLOOM_SCENE_OUT and logs
// what the widgets show as one "STATE {...}" line.
ShellRoot {
  id: scene

  component FakeSvc: QtObject {
    property bool closed: false
    property bool bridgeUp: true
    property bool signingIn: false
    property bool ready: !closed
    property bool hasTrack: !closed
    property bool isPlaying: !closed
    property bool isAd: false
    property bool adSkippable: false
    property bool signedIn: true
    property bool premium: false
    property string like: "LIKE"
    property string title: hasTrack ? "Northern Lights" : ""
    property string artist: "The Examples"
    property string album: "Placeholder Skies"
    property string engineLine: closed ? "Spinbloom is off" : ""
    property string thumb: ""
    property real duration: 214
    property real position: 83
    property real progress: 0.39
    property string repeatMode: "ALL"
    property int volume: 60
    property bool muted: false
    property string videoId: hasTrack ? "v1" : ""
    property var calls: []
    property var settings: ({})
    property int fastClockUsers: 0
    function toggleEngine() { calls.push("toggleEngine") }
    function startEngine() { calls.push("startEngine") }
    function togglePlaying() { calls.push("togglePlaying") }
    function previous() {}
    function next() {}
    function toggleLike() {}
    function skipAd() {}
    function seek(v) {}
    function shuffle() {}
    function cycleRepeat() {}
    function toggleMute() {}
    function setVolume(v) {}
  }
  FakeSvc { id: runningSvc }
  FakeSvc { id: closedSvc; closed: true }

  component FakeBar: QtObject {
    property var svc: null
    property bool vertical: false
    property int barSize: 26
    property color barForeground: Color.foreground
    property string fontFamily: Style.font.family
    property var shell: QtObject { function serviceFor(id) { return svc } }
    function showTooltip(item, text) {}
    function hideTooltip(item) {}
  }
  FakeBar { id: runningBar; svc: runningSvc }
  FakeBar { id: closedBar; svc: closedSvc }

  FloatingWindow {
    id: win
    implicitWidth: 640
    implicitHeight: 470
    visible: true
    color: Color.popups.background

    Item {
      id: stage
      anchors.fill: parent
      Rectangle { anchors.fill: parent; color: Color.popups.background }

      Column {
        x: 20; y: 16
        width: 600
        spacing: 12

        Text { text: "Bar: playing / closed"; color: Color.foreground; opacity: 0.5; font.pixelSize: 11 }
        Row {
          spacing: 16
          Rectangle {
            width: 280; height: 26; color: Color.bar ? Color.bar.background : "#101014"
            SpinbloomBar { id: barRunning; bar: runningBar; anchors.centerIn: parent }
          }
          Rectangle {
            width: 280; height: 26; color: Color.bar ? Color.bar.background : "#101014"
            SpinbloomBar { id: barClosed; bar: closedBar; anchors.centerIn: parent }
          }
        }

        // Spinbloom: when it is off, the panel shows only the way back on.
        Text { text: "Panel when off"; color: Color.foreground; opacity: 0.5; font.pixelSize: 11 }
        Rectangle {
          width: 600; height: 120; radius: 10
          color: Color.popups.background
          border.color: Qt.rgba(1, 1, 1, 0.08)
          Views.OffCard {
            id: offCard
            anchors.centerIn: parent
            width: 400
            svc: closedSvc
          }
        }
      }
    }

    TestCase {
      id: tc
      name: "closed"
      when: false
    }

    function find(item, name) {
      if (item.objectName === name) return item
      for (var i = 0; i < item.children.length; i++) {
        var f = find(item.children[i], name)
        if (f) return f
      }
      return null
    }

    Timer {
      interval: 900
      running: true
      onTriggered: {
        var turnOn = win.find(stage, "offTurnOn")
        console.log("STATE " + JSON.stringify({
          barRunning: { label: barRunning.label, controls: barRunning.showControls, opacity: barRunning.children.length },
          barClosed: { label: barClosed.label, controls: barClosed.showControls, closed: barClosed.closed },
          turnOn: { text: turnOn ? turnOn.text : null, visible: !!turnOn && turnOn.visible, w: turnOn ? turnOn.width : 0, h: turnOn ? turnOn.height : 0 }
        }))
        if (turnOn) tc.mouseClick(turnOn, turnOn.width / 2, turnOn.height / 2)
        stage.grabToImage(function (r) {
          r.saveToFile(Quickshell.env("SPINBLOOM_SCENE_OUT"))
          console.log("CLICKS " + JSON.stringify({ closed: closedSvc.calls }))
          Qt.quit()
        })
      }
    }
  }
}
