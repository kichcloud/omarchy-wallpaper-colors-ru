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
- `~/.local/share/icons/Omarchy-Accent/` — установленная тема курсора (hyprcursor + Xcursor);
- `~/.local/state/omarchy/wallpaper-colors/current.json` — публикуемый результат для других плагинов.

Отдельный плагин `cursor-accent` и его хуки **не нужны** — удалены.

## Интерфейс для других плагинов

После каждой перекраски плагин атомарно пишет `current.json`:

```json
{
  "schema": 1,
  "theme": "ash-wc",
  "mode": "dark",
  "wallpaper": "/путь/к/обоям.jpg",
  "palette": { "background": "#…", "accent": "#…", "foreground": "#…", … },
  "updated": 1763800000
}
```

Другие плагины могут читать `palette.<key>` и `wallpaper` напрямую вместо файлов темы.
Файл удаляется при «Тема по умолчанию» — тогда потребитель должен вернуться к
`colors.toml` активной темы. Пример адаптера: `plymouth/common.sh` в
lock screen explorer использует `theme_color()` / `wallpaper_path()` отсюда.

## Обои

Плагин следит за `~/.local/state/omarchy/current/background`. Если обои ставятся сторонним плагином мимо симлинка, обнови его:

```bash
omarchy theme bg set /путь/к/картинке
```
