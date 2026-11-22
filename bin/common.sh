#!/usr/bin/env bash
# Внутренние примитивы скриптов плагина. Подключается через source.
# Публичный API — это CLI bin/wallpaper-colors, bin/glass-style и bin/install-config.

STATE_DIR=${STATE_DIR:-$HOME/.local/state/omarchy/wallpaper-colors}
CURRENT_DIR=$HOME/.local/state/omarchy/current

read_theme() {
  cat "$CURRENT_DIR/theme.name" 2>/dev/null || true
}

# Все foot.ini, куда пишутся альфа и блюр. Порядок соответствует порядку include.
foot_files() {
  local theme
  theme=$(read_theme)
  printf '%s\n' \
    "$HOME/.config/foot/foot.ini" \
    "$HOME/.config/omarchy/themes/$theme/foot.ini" \
    "$CURRENT_DIR/theme/foot.ini"
}

foot_set_alpha() {
  local value=$1 file
  while IFS= read -r file; do
    [[ -f $file ]] || continue
    sed -i -E "s/^([[:space:]]*alpha[[:space:]]*=[[:space:]]*).*/\1$value/" "$file"
  done < <(foot_files)
  # Запущенный foot не перечитывает конфиг: Omarchy умеет отправить ему OSC 11
  # с альфой (urxvt-префикс [percent]). Это и даёт мгновенный эффект в терминале.
  if command -v omarchy-theme-set-foot >/dev/null 2>&1; then
    omarchy-theme-set-foot >/dev/null 2>&1 || true
  fi
}

foot_set_blur() {
  local value=$1 file=$CURRENT_DIR/theme/foot.ini
  [[ -f $file ]] || return 0
  sed -i -E "s/^([[:space:]]*blur[[:space:]]*=[[:space:]]*).*/\1$value/" "$file"
}

# Три отдельные проверки: синтаксис и диапазон сообщают об ошибке по-разному,
# а install-config принимает значения без значащих цифр (1, 0.30).
valid_alpha_syntax() { [[ $1 =~ ^0?\.[0-9]+$ || $1 =~ ^1(\.0+)?$ ]]; }
valid_alpha_value()  { [[ $1 =~ ^(0(\.[0-9]+)?|1(\.0+)?)$ ]]; }
valid_alpha_range()  { python3 -c 'import sys; v=float(sys.argv[1]); sys.exit(0 if 0.30<=v<=1.0 else 1)' "$1"; }
valid_blur()         { [[ $1 =~ ^[0-9]+$ ]] && (( $1 <= 30 )); }

# Перечитать Lua-конфиг с актуальными glass-alpha/glass-blur.
reload_hypr() {
  hyprctl reload >/dev/null 2>&1 || true
}

# Зависимости, которые перекрашиваются вместе с палитрой.
apply_tools() {
  local root=$1 steam=$HOME/.local/bin/steam-accent
  [[ -f $root/bin/cursor-recolor ]] && python3 "$root/bin/cursor-recolor" apply >/dev/null 2>&1 || true
  [[ -f $root/bin/opencode-theme ]] && python3 "$root/bin/opencode-theme" >/dev/null 2>&1 || true
  # Steam красится по событию смены палитры — отдельный демон не нужен.
  [[ -x $steam ]] && "$steam" --once >/dev/null 2>&1 || true
}
