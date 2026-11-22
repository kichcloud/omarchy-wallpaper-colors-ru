#!/usr/bin/env bash
# Smoke-проверка публичного API плагина. Сохраняет и восстанавливает состояние.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
BIN=$ROOT/bin
ST=${STATE_DIR:-$HOME/.local/state/omarchy/wallpaper-colors}
CUR=$HOME/.local/state/omarchy/current

pass=0; fail=0
check() {
  local name=$1; shift
  if "$@"; then printf 'OK   %s\n' "$name"; pass=$((pass + 1))
  else printf 'FAIL %s\n' "$name"; fail=$((fail + 1)); fi
}
eq() { [[ $1 == "$2" ]]; }
file() { cat "$1" 2>/dev/null || true; }

# --- фиксируем состояние и восстанавливаем даже при падении ---
backup=$(mktemp -d)
for k in glass-style glass-alpha glass-blur mode off picks.json; do
  [[ -f $ST/$k ]] && cp "$ST/$k" "$backup/$k"
done
[[ -f $CUR/theme.name ]] && cp "$CUR/theme.name" "$backup/theme.name"
restore() {
  for k in glass-style glass-alpha glass-blur mode off picks.json; do
    if [[ -f $backup/$k ]]; then cp "$backup/$k" "$ST/$k"; else rm -f "$ST/$k"; fi
  done
  [[ -f $backup/theme.name ]] && cp "$backup/theme.name" "$CUR/theme.name"
  # Производные конфиги тоже вернуть к исходной альфе.
  if [[ -f $backup/glass-alpha ]]; then
    "$BIN/install-config" --light "$(cat "$backup/glass-alpha")" >/dev/null 2>&1 || true
  fi
  rm -rf "$backup"
}
trap restore EXIT

mkdir -p "$ST"

# --- CLI: статус и формат значений ---
style=$($BIN/glass-style status)
check 'glass-style status — glass|opaque' bash -c '[[ $1 == glass || $1 == opaque ]]' _ "$style"
values=$($BIN/glass-style values)
check 'values — валидный JSON' python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert set(d)=={"alpha","blur"}' "$values"
check 'values — альфа 0.30..1.0' python3 -c 'import json,sys; assert 0.30<=json.loads(sys.argv[1])["alpha"]<=1.0' "$values"
check 'values — блюр 0..30' python3 -c 'import json,sys; assert 0<=json.loads(sys.argv[1])["blur"]<=30' "$values"

# --- обработка ошибок (EXIT CODE И СООБЩЕНИЯ НЕ МЕНЯТЬ) ---
err=$($BIN/glass-style alpha abc 2>&1 >/dev/null) && rc=0 || rc=$?
check 'alpha: нечисло → rc=2 + usage' bash -c '[[ $1 == 2 && $2 == "usage: glass-style alpha 0.30..1.0" ]]' _ "$rc" "$err"
err=$($BIN/glass-style alpha 0.2 2>&1 >/dev/null) && rc=0 || rc=$?
check 'alpha: вне диапазона → rc=2 без usage' bash -c '[[ $1 == 2 && -z $2 ]]' _ "$rc" "$err"
err=$($BIN/glass-style blur 31 2>&1 >/dev/null) && rc=0 || rc=$?
check 'blur: >30 → rc=2 + usage' bash -c '[[ $1 == 2 && $2 == "usage: glass-style blur 0..30" ]]' _ "$rc" "$err"
$BIN/wallpaper-colors pick abc >/dev/null 2>&1 && rc=0 || rc=$?
check 'pick: нечисло → rc=2' eq "$rc" 2

# --- слайдеры: состояние и производные файлы ---
$BIN/glass-style glass >/dev/null 2>&1 || true
$BIN/glass-style alpha 0.64 >/dev/null 2>&1
check 'alpha → glass-alpha' eq "$(file "$ST/glass-alpha")" 0.64
check 'alpha → foot.ini' grep -q 'alpha=0.64' "$HOME/.config/foot/foot.ini" 2>/dev/null
check 'alpha → shell.toml' grep -q 'background-alpha = 0.64' "$HOME/.config/omarchy/shell.toml" 2>/dev/null
check 'Vesktop transparent=true' python3 -c 'import json,sys; assert json.load(open(sys.argv[1])).get("transparent") is True' "$HOME/.config/vesktop/settings/settings.json"
check 'alpha.css следует за ползунком' bash -c 'grep -q "rgba(var(--oc-bg-rgb), $(cat "$1"))" "$2"' _ "$ST/glass-alpha" "$HOME/.local/share/omarchy-glass/alpha.css"
check 'тема Vencord содержит alpha' grep -q 'rgba(var(--oc-bg-rgb),' "$HOME/.config/vesktop/themes/omarchy-glass.theme.css"
check 'Vesktop исключён из opacity' grep -q 'vesktop-native-alpha' "$HOME/.config/hypr/uniform-glass.lua"

$BIN/glass-style blur 8 >/dev/null 2>&1
check 'blur → glass-blur' eq "$(file "$ST/glass-blur")" 8
check 'blur → foot.ini' grep -q 'blur=yes' "$CUR/theme/foot.ini" 2>/dev/null
$BIN/glass-style blur 0 >/dev/null 2>&1
check 'blur=0 → foot blur=no' grep -q 'blur=no' "$CUR/theme/foot.ini" 2>/dev/null

# --- штатный стиль игнорирует ползунки ---
$BIN/glass-style opaque >/dev/null 2>&1
$BIN/glass-style alpha 0.50 >/dev/null 2>&1
check 'opaque не становится прозрачным' test ! -f "$ST/glass-alpha"
$BIN/glass-style blur 4 >/dev/null 2>&1
check 'opaque → foot без blur=yes' bash -c '! grep -q blur=yes "$1" 2>/dev/null' _ "$CUR/theme/foot.ini"
$BIN/glass-style glass >/dev/null 2>&1
$BIN/glass-style blur 4 >/dev/null 2>&1

# --- reset не оставляет тему без палитры ---
$BIN/wallpaper-colors reset >/dev/null 2>&1
check 'reset сохраняет colors.toml' test -f "$HOME/.config/omarchy/themes/wallpaper-glass/colors.toml"
$BIN/wallpaper-colors pick 0 >/dev/null 2>&1
check 'pick 0 снимает off' test ! -s "$ST/off"

# --- OSD: оболочка должна суммонить наш плагин вместо отключённого omarchy.osd ---
check 'manifest: clonedFrom omarchy.osd' python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d.get("omarchy",{}).get("clonedFrom")=="omarchy.osd"' "$ROOT/manifest.json"

# --- идемпотентность установки ---
$BIN/install-config >/dev/null 2>&1
check 'require в hyprland.lua не дублируется' bash -c '[[ $(grep -c "require(\"hypr.uniform-glass\")" "$1" 2>/dev/null) == 1 ]]' _ "$HOME/.config/hypr/hyprland.lua"
check 'секции shell.toml не дублируются' bash -c '[[ -z $(grep "^\[" "$1" 2>/dev/null | sort | uniq -d) ]]' _ "$HOME/.config/omarchy/shell.toml"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
