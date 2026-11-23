import QtQuick
import Quickshell
import Quickshell.Io

// Recolors the desktop whenever the wallpaper changes. Omarchy fires no hook for that, so this polls
// the background link with a cheap readlink and only runs the generator when it moved.
Item {
  id: root

  readonly property string dir: decodeURIComponent(String(Qt.resolvedUrl(".")).replace(/^file:\/\//, ""))
  readonly property string bin: decodeURIComponent(String(Qt.resolvedUrl("bin/wallpaper-colors")).replace(/^file:\/\//, ""))
  property string lastBackground: ""
  property bool pending: false

  function sync() {
    if (syncProc.running) {
      root.pending = true
      return
    }
    syncProc.running = true
  }

  // Первый запуск: тихо ставит тему и lock-макет, потом применяет палитру и курсор.
  Component.onCompleted: installProc.running = true
  Process {
    id: installProc
    running: false
    command: ["bash", root.dir + "bin/install-config"]
    onExited: function(code) { root.sync() }
  }

  Process {
    id: syncProc
    command: [root.bin, "sync"]
    onExited: {
      if (!root.pending) return
      root.pending = false
      root.sync()
    }
  }

  Process {
    id: readlinkProc
    command: ["readlink", "-f", Quickshell.env("HOME") + "/.local/state/omarchy/current/background"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var background = String(text || "").trim()
        if (background === "" || background === root.lastBackground) return
        root.lastBackground = background
        root.sync()
      }
    }
  }

  Timer {
    interval: 1500
    running: true
    repeat: true
    onTriggered: if (!readlinkProc.running) readlinkProc.running = true
  }

  // Steam получает палитру только при её смене. Если клиент стартует позже
  // оболочки, установочный проход уже прошёл — ловим запись steam.pid и
  // несколько секунд догоняем его CDP, переживая перезагрузку страниц входа.
  FileView {
    path: Quickshell.env("HOME") + "/.steam/steam.pid"
    watchChanges: true
    onFileChanged: root.followSteam()
  }

  function followSteam() {
    if (steamProc.running) return
    steamProc.running = true
  }

  Process {
    id: steamProc
    command: ["bash", "-c", "[[ -x $1 ]] && exec \"$1\" --follow 45", "steam-accent",
              Quickshell.env("HOME") + "/.local/bin/steam-accent"]
  }
}
