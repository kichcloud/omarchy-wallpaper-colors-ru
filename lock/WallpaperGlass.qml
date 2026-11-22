// name: Wallpaper Glass
// description: Стандартный макет: обои и акцент от omarchy-wallpaper-color
//
// Тот же центр с полем пароля, что и у стокового макета, но цвета берутся
// из палитры, которую плагин пишет в colors.toml (Commons.Color), а фон —
// из реально установленных обоев (current/background).
import QtQuick
import QtQuick.Effects
import qs.Commons

DesignBase {
  id: lock
  inputItem: field.input

  Rectangle {
    anchors.fill: parent
    color: Color.background
  }

  Image {
    id: wallpaper
    anchors.fill: parent
    source: lock.loadBackground ? lock.fileUrl(lock.backgroundPath) : ""
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    cache: false
    sourceSize.width: width
    sourceSize.height: height
  }

  MultiEffect {
    anchors.fill: wallpaper
    source: wallpaper
    autoPaddingEnabled: false
    blurEnabled: lock.loadBackground && wallpaper.status === Image.Ready
    blur: 1.0
    blurMax: 128
    blurMultiplier: 1.25
    contrast: -0.08
  }

  // Тонкая рамка в цвете акцента поверх размытых обоев.
  Rectangle {
    anchors.centerIn: field
    width: field.width + 8
    height: field.height + 8
    radius: field.radius + 4
    color: "transparent"
    border.width: 1
    border.color: Color.accent
    opacity: 0.85
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    onClicked: { lock.wakeRequested(); lock.forcePasswordFocus() }
    onPositionChanged: lock.wakeRequested()
  }

  PasswordField {
    id: field
    lock: lock
    anchors.centerIn: parent
    width: 381
    height: 67
    outlineThickness: 3
    radius: Style.cornerRadius
    showLockGlyph: false
    placeholder: "Enter Password"
    fontScale: 1.125
  }
}
