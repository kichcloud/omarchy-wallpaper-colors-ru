# Wallpaper Colors RU

Форк [adityamiskin/omarchy-wallpaper-colors](https://github.com/adityamiskin/omarchy-wallpaper-colors)
с встроенным перекрашивателем курсора из
[cursor-accent](https://github.com/smoothpixels/omarchy-cursor-accent).

Один плагин красит **тему Omarchy и курсор** по цветам обоев.

## Что внутри

- **Акцент** — палитра matugen для текущих обоев, выбор акцента, «Тема по умолчанию».
- **Режим** — `Авто` (порог яркости 0.6), `Тёмная`, `Светлая`.
- **Курсор** — Bibata, перекрашенный в цвета темы; собирается при смене темы и при старте оболочки. Формы `modern` / `original`, режимы `follow` / `fixed` / `default`.

## Установка

```bash
omarchy plugin add https://github.com/kichcloud/omarchy-wallpaper-colors-ru.git --enable
```

Нужны `matugen`, `magick`, `jq`, `python3` с `gi`/`cairo` (есть в Omarchy).

## Управление курсором

```bash
BIN=~/.config/omarchy/plugins/kich.wallpaper-colors-ru/bin/cursor-recolor
$BIN status              # текущие настройки
$BIN follow              # следовать теме
$BIN fixed '#ff8800'     # фиксированный цвет
$BIN default             # системный курсор
$BIN shape modern|original
```

## Состояние

- `~/.local/state/omarchy/wallpaper-colors/` — акценты, режим, бэкапы;
- `~/.local/state/omarchy/wallpaper-colors/cursor/` — конфиг курсора и блокировка;
- `~/.local/share/icons/Omarchy-Accent/` — установленная тема курсора (hyprcursor + Xcursor).

Отдельный плагин `cursor-accent` и его хуки **не нужны** — удалены.

## Тема рабочего стола и lock

При первом запуске (после установки плагина) `bin/install-themes` молча:

- копирует тему **`wallpaper-glass`** в `~/.config/omarchy/themes/` — она видна в штатной карусели тем как «Wallpaper Glass» — и переключается на неё, не меняя текущие обои;
- кладёт `WallpaperGlass.qml` в `~/.config/omarchy/lock-designs/` и выбирает его (`my-wallpaper-glass`) в настройках lock-дизайнов.

Lock-макет — стандартный центр с полем пароля; фон берётся из реально установленных обоев (`current/background`), цвета — из палитры, которую плагин пишет в `colors.toml` (`qs.Commons.Color`). Повторные запуски ничего не меняют: установка идемпотентна по маркеру в каталоге темы.

## Обои

Плагин следит за `~/.local/state/omarchy/current/background`. Если обои ставятся сторонним плагином мимо симлинка, обнови его:

```bash
omarchy theme bg set /путь/к/картинке
```
