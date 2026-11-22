import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Кнопка в баре и панель выбора акцента/режима.
Panel {
  id: root
  moduleName: "kich.wallpaper-colors-ru"
  ipcTarget: "kich.wallpaper-colors-ru"

  readonly property string bin: decodeURIComponent(String(Qt.resolvedUrl("bin/wallpaper-colors")).replace(/^file:\/\//, ""))
  readonly property string styleBin: decodeURIComponent(String(Qt.resolvedUrl("bin/glass-style")).replace(/^file:\/\//, ""))
  readonly property color fg: root.bar ? root.bar.foreground : Commons.Color.foreground
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family

  property var colors: []
  property string theme: ""
  property string mode: "auto"
  property int active: 0
  property bool locked: false
  property bool loading: false
  property bool applying: false
  property string glassStyle: "glass"
  property string pendingStyle: ""
  property real pendingAlpha: 0.85
  property real shellAlpha: 0.85
  property real blurSize: 4
  readonly property real alphaPercent: Math.max(0, Math.min(100, (1 - root.shellAlpha) / 0.7 * 100))
  property string error: ""
  property int cursor: 0
  property bool cursorActive: false

  readonly property var rows: [{ index: -1, name: "Тема по умолчанию", color: "" }].concat(
    root.colors.map(function(c, i) { return { index: i, name: i ? "Цвет " + (i + 1) : "Обои", color: c } }))
  readonly property int activeRow: root.active + 1
  readonly property var modes: [
    { id: "auto", name: "Авто" }, { id: "dark", name: "Тёмная" }, { id: "light", name: "Светлая" }
  ]

  component T: Text {
    textFormat: Text.PlainText
    color: root.fg
    font.family: root.fontFamily
  }

  function refresh() {
    if (sourcesProc.running) return
    root.loading = !root.colors.length; root.error = ""
    sourcesProc.running = true
  }
  function run(proc, args) {
    root.applying = true; root.error = ""
    proc.command = [root.bin].concat(args); proc.running = true
  }
  function finish(code, msg) {
    root.applying = false
    if (code !== 0) root.error = msg
    root.refresh()
  }
  function pick(i) { if (!pickProc.running) run(pickProc, i < 0 ? ["reset"] : ["pick", String(i)]) }
  function setMode(m) { if (!setModeProc.running && root.mode !== m) run(setModeProc, ["mode", m]) }
  function setGlassStyle(s) {
    if (styleProc.running || root.glassStyle === s) return
    root.pendingStyle = s; root.applying = true
    styleProc.command = [root.styleBin, s]; styleProc.running = true
  }
  function setAlpha(v) {
    if (alphaProc.running) return
    var pct = v === undefined ? alphaSlider.liveValue : v
    root.pendingAlpha = Number((1 - pct / 100 * 0.7).toFixed(2))
    alphaProc.command = [root.styleBin, "alpha", String(root.pendingAlpha)]; alphaProc.running = true
  }
  function setBlur(v) {
    if (blurProc.running) return
    var px = v === undefined ? blurSlider.liveValue : v
    blurProc.command = [root.styleBin, "blur", String(Math.round(px))]
    blurProc.running = true
  }

  onOpenedChanged: if (opened) {
    root.cursorActive = false
    styleStatusProc.running = true
    tuneProc.running = true
    refresh()
  }

  Process {
    id: sourcesProc
    command: [root.bin, "sources"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.loading = false
        try {
          var r = JSON.parse(String(text || "").trim())
          root.colors = r.colors; root.theme = r.theme; root.mode = r.mode || "auto"
          root.locked = r.locked; root.active = r.active; root.cursor = root.activeRow
        } catch (e) { root.error = "Не удалось прочитать цвета обоев. Установлен ли matugen?" }
      }
    }
  }
  Process {
    id: styleStatusProc
    command: [root.styleBin, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.glassStyle = String(text || "").trim() === "opaque" ? "opaque" : "glass"
    }
  }
  Process {
    id: styleProc
    onExited: function(c) {
      if (c === 0) root.glassStyle = root.pendingStyle
      root.applying = false
      root.refresh()
    }
  }
  Process {
    id: tuneProc
    command: [root.styleBin, "values"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var v = JSON.parse(String(text || "").trim())
          root.shellAlpha = v.alpha; root.blurSize = v.blur
        } catch (e) {}
      }
    }
  }
  Process {
    id: alphaProc
    onExited: function(c) { if (c === 0) root.shellAlpha = root.pendingAlpha }
  }
  Process { id: blurProc; onExited: function(c) { if (c === 0) root.blurSize = Math.round(blurSlider.liveValue) } }
  Process { id: pickProc; onExited: function(c) { root.finish(c, "Не удалось применить цвет") } }
  Process { id: setModeProc; onExited: function(c) { root.finish(c, "Не удалось изменить режим") } }

  implicitWidth: button.implicitWidth; implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰏘"
    tooltipText: "Цвета обоев"
    onPressed: function(b) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button; owner: root; bar: root.bar; open: root.opened; focusTarget: keys
    contentWidth: panel.fittedContentWidth(Style.space(220))
    contentHeight: panel.fittedContentHeight(col.implicitHeight)

    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) root.cursorActive = true
        else root.cursor = (root.cursor + (dx || dy) + root.rows.length) % root.rows.length
      }
      onActivateRequested: if (root.cursorActive && root.colors.length) root.pick(root.rows[root.cursor].index)
      onCloseRequested: root.close()
      onTabRequested: function(d) { root.switchPanel(d) }
    }

    Column {
      id: col
      anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
      spacing: Style.space(8)

      PanelSectionHeader { text: "Акцент"; foreground: root.fg; fontFamily: root.fontFamily }

      T {
        visible: root.locked; width: parent.width; wrapMode: Text.Wrap; opacity: .6
        font.pixelSize: Style.font.bodySmall
        text: root.theme + " установлена из git — цвета не изменены."
      }
      T {
        visible: root.loading || root.applying || root.error !== ""
        width: parent.width; wrapMode: Text.Wrap
        color: root.error !== "" ? Commons.Color.urgent : root.fg
        opacity: root.error !== "" ? 1 : .6; font.pixelSize: Style.font.bodySmall
        text: root.error !== "" ? root.error : root.applying ? "Применяем…" : "Читаем обои…"
      }

      Row {
        width: col.width
        spacing: Style.space(10)
        Repeater {
          model: root.colors.length ? root.rows : []
          Rectangle {
            required property var modelData; required property int index
            readonly property bool current: index === root.activeRow
            readonly property bool hot: (root.cursorActive && root.cursor === index) || mouse.containsMouse
            width: Style.space(28); height: width; radius: width / 2
            color: modelData.color || "transparent"
            border.width: current ? Math.max(1, Style.space(2)) : (modelData.color ? 0 : 1)
            border.color: root.fg
            opacity: hot || current ? 1 : .85
            antialiasing: true
            MouseArea {
              id: mouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
              onEntered: { root.cursorActive = true; root.cursor = index }
              onClicked: root.pick(modelData.index)
            }
          }
        }
      }

      PanelSectionHeader { text: "Режим"; foreground: root.fg; fontFamily: root.fontFamily }
      Row {
        width: col.width; spacing: Style.space(6)
        Repeater {
          model: root.modes
          Rectangle {
            required property var modelData
            readonly property bool current: root.mode === modelData.id
            width: (col.width - Style.space(12)) / 3; height: Style.space(28); radius: Style.cornerRadius
            color: current ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, .14) : "transparent"
            border.width: current ? 1 : 0; border.color: root.fg
            T {
              anchors.centerIn: parent; text: modelData.name
              font.pixelSize: Style.font.bodySmall; font.bold: current
            }
            MouseArea {
              anchors.fill: parent; cursorShape: Qt.PointingHandCursor
              onClicked: root.setMode(modelData.id)
            }
          }
        }
      }

      PanelSectionHeader { text: "Стиль"; foreground: root.fg; fontFamily: root.fontFamily }
      Row {
        width: col.width; spacing: Style.space(6)
        Repeater {
          model: [
            { id: "glass", name: "Прозрачный" },
            { id: "opaque", name: "Штатный" }
          ]
          Rectangle {
            required property var modelData
            readonly property bool current: root.glassStyle === modelData.id
            width: (col.width - Style.space(6)) / 2; height: Style.space(28); radius: Style.cornerRadius
            color: current ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, .14) : "transparent"
            border.width: current ? 1 : 0; border.color: root.fg
            T {
              anchors.centerIn: parent; text: modelData.name
              font.pixelSize: Style.font.bodySmall; font.bold: current
            }
            MouseArea {
              anchors.fill: parent; cursorShape: Qt.PointingHandCursor
              onClicked: root.setGlassStyle(modelData.id)
            }
          }
        }
      }

      PanelSectionHeader {
        visible: root.glassStyle !== "opaque"
        text: "Прозрачность"; foreground: root.fg; fontFamily: root.fontFamily
      }
      Row {
        visible: root.glassStyle !== "opaque"
        width: col.width; spacing: Style.space(8)
        PanelSlider {
          id: alphaSlider
          bar: root.bar
          width: col.width - Style.space(46)
          minimum: 0; maximum: 100; step: 1; integer: true
          value: root.alphaPercent
          trackColor: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, .14)
          fillColor: root.fg; knobColor: root.fg
          onReleased: function(v) { root.setAlpha(v) }
        }
        T {
          width: Style.space(38); horizontalAlignment: Text.AlignRight
          text: Math.round(alphaSlider.liveValue) + "%"
          font.pixelSize: Style.font.bodySmall
        }
      }

      PanelSectionHeader {
        visible: root.glassStyle !== "opaque"
        text: "Блюр"; foreground: root.fg; fontFamily: root.fontFamily
      }
      Row {
        visible: root.glassStyle !== "opaque"
        width: col.width; spacing: Style.space(8)
        PanelSlider {
          id: blurSlider
          bar: root.bar
          width: col.width - Style.space(46)
          minimum: 0; maximum: 30; step: 1; integer: true
          value: root.blurSize
          trackColor: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, .14)
          fillColor: root.fg; knobColor: root.fg
          onReleased: function(v) { root.setBlur(v) }
        }
        T {
          width: Style.space(38); horizontalAlignment: Text.AlignRight
          text: Math.round(blurSlider.liveValue) + "px"
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
  }
}
