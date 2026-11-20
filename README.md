# Wallpaper Colors RU

Форк [adityamiskin/omarchy-wallpaper-colors](https://github.com/adityamiskin/omarchy-wallpaper-colors):
перекрашивает активную тему Omarchy по цветам текущих обоев.

## Отличия от оригинала

- **Русский интерфейс** — все строки в панели переведены.
- **Переключатель режима** в панели: `Авто` / `Тёмная` / `Светлая`.
  Выбор хранится в `~/.local/state/omarchy/wallpaper-colors/mode`.
- **Меньше вызовов matugen**: список акцентов строится одним сканированием
  изображения + быстрыми `matugen color hex` вместо повторного разбора картинки
  для каждого кандидата.
- **Короче код**: общие функции/QML-компоненты вынесены, пользовательские
  ошибки/`setmode` объединены.

## Установка

```bash
omarchy plugin add https://github.com/kichcloud/omarchy-wallpaper-colors-ru.git --enable
```

Нужны `matugen`, `magick` (ImageMagick) и `jq`.

## Как пользоваться

Иконка палитры в баре открывает панель:

- **Акцент** — «Тема по умолчанию» и цвета, которые дают обои;
- **Режим** — `Авто` (порог яркости 0.6), `Тёмная`, `Светлая`.

Смена обоев отслеживается по `/home/$USER/.local/state/omarchy/current/background`.
Если обои ставятся сторонним плагином мимо этой symlink, обновите её:

```bash
omarchy theme bg set /путь/к/картинке
```

## Возврат к оригинальной теме

Выберите «Тема по умолчанию» в панели, затем:

```bash
omarchy plugin remove kich.wallpaper-colors-ru
rm -rf ~/.local/state/omarchy/wallpaper-colors
```
