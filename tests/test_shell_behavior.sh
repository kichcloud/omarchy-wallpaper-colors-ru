#!/usr/bin/env bash
# Изолированные тесты публичного CLI плагина. Пишут только во временный HOME.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
BIN=$ROOT/bin
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

HOME_DIR=$TMP/home
STATE=$HOME_DIR/.local/state/omarchy/wallpaper-colors
CUR=$HOME_DIR/.local/state/omarchy/current
STUBS=$TMP/stubs
LOG=$TMP/calls.log
mkdir -p "$STATE" "$CUR/theme" "$HOME_DIR/.config/foot" \
         "$HOME_DIR/.config/omarchy/themes/wallpaper-glass" \
         "$HOME_DIR/.config/omarchy/themed" "$HOME_DIR/.config/hypr" \
         "$HOME_DIR/.local/state/omarchy/toggles/hypr" \
         "$STUBS" "$TMP/runtime"

echo wallpaper-glass >"$CUR/theme.name"
printf 'dark\n' >"$STATE/mode"
printf 'accent = "#112233"\nbackground = "#000000"\n' >"$CUR/colors.toml"
printf '# fake\n' >"$CUR/bg.jpg"
ln -s "$CUR/bg.jpg" "$CUR/background"
for f in "$HOME_DIR/.config/foot/foot.ini" \
         "$HOME_DIR/.config/omarchy/themes/wallpaper-glass/foot.ini" \
         "$CUR/theme/foot.ini"; do
  printf '[colors-dark]\nalpha=0.85\nblur=yes\n' >"$f"
done

# Заглушки внешних команд — реальная система не трогается.
for name in hyprctl omarchy omarchy-bar omarchy-theme-set-glass omarchy-theme-set-foot omarchy-notification-send; do
  cat >"$STUBS/$name" <<EOF
#!/bin/sh
echo "$name \$*" >>"$LOG"
exit 0
EOF
  chmod +x "$STUBS/$name"
done
# matugen нужен для sources и проверки диапазона pick: отдаём два исходных цвета.
cat >"$STUBS/matugen" <<'EOF'
#!/bin/sh
case " $* " in
  *" --show-source-colors "*) printf '#112233\n#445566\n' ;;
  *" color hex "*) printf '{"colors":{"primary":{"dark":{"color":"#112233"}}}}' ;;
  *) printf '{"colors":{"source_color":{"dark":{"color":"#112233"}}}}' ;;
esac
exit 0
EOF
chmod +x "$STUBS/matugen"

export HOME="$HOME_DIR" PATH="$STUBS:$PATH" \
       XDG_STATE_HOME="$HOME_DIR/.local/state" XDG_RUNTIME_DIR="$TMP/runtime"

pass=0; fail=0
check() {
  local name=$1; shift
  if "$@"; then printf 'OK   %s\n' "$name"; pass=$((pass + 1))
  else printf 'FAIL %s\n' "$name"; fail=$((fail + 1)); fi
}
eq() { [[ $1 == "$2" ]]; }
file() { cat "$1" 2>/dev/null || true; }
rc_of() { "$@" >/dev/null 2>&1 && echo 0 || echo $?; }

# --- обычное использование ---
check 'status по умолчанию' eq "$($BIN/glass-style status)" glass
check 'values по умолчанию' eq "$($BIN/glass-style values)" '{"alpha":0.85,"blur":4}'
check 'sources отдаёт исходные цвета' eq "$($BIN/wallpaper-colors sources)" \
  '{"theme":"wallpaper-glass","locked":false,"active":0,"mode":"dark","colors":["#112233","#112233"]}'

$BIN/glass-style alpha 0.64 >/dev/null 2>&1
check 'alpha → state' eq "$(file "$STATE/glass-alpha")" 0.64
check 'foot с минимальной альфой (основной)' grep -q 'alpha=0.99' "$HOME_DIR/.config/foot/foot.ini"
check 'foot с минимальной альфой (тема)' grep -q 'alpha=0.99' "$CUR/theme/foot.ini"
check 'alpha → shell.toml' grep -q 'background-alpha = 0.64' "$HOME_DIR/.config/omarchy/shell.toml"
check 'alpha → OSC в запущенный foot' grep -q 'omarchy-theme-set-foot' "$LOG"
check 'alpha → hyprctl reload' grep -q 'hyprctl reload' "$LOG"

$BIN/glass-style blur 0 >/dev/null 2>&1
check 'blur 0 → foot blur=no' grep -q 'blur=no' "$CUR/theme/foot.ini"
$BIN/glass-style blur 30 >/dev/null 2>&1
check 'blur 30 принят' eq "$(file "$STATE/glass-blur")" 30

# --- граничные значения и некорректные данные ---
check 'alpha 0.30 принят' eq "$(rc_of "$BIN/glass-style" alpha 0.30)" 0
check 'alpha 1 принят' eq "$(rc_of "$BIN/glass-style" alpha 1)" 0
check 'alpha 0.2 отклонён' eq "$(rc_of "$BIN/glass-style" alpha 0.2)" 2
check 'alpha 1.1 отклонён' eq "$(rc_of "$BIN/glass-style" alpha 1.1)" 2
check 'alpha abc отклонён' eq "$(rc_of "$BIN/glass-style" alpha abc)" 2
alpha_before=$(file "$STATE/glass-alpha")
$BIN/glass-style alpha abc >/dev/null 2>&1 || true
check 'невалидный alpha не меняет состояние' eq "$(file "$STATE/glass-alpha")" "$alpha_before"
check 'blur 31 отклонён' eq "$(rc_of "$BIN/glass-style" blur 31)" 2
check 'pick abc отклонён' eq "$(rc_of "$BIN/wallpaper-colors" pick abc)" 2
check 'pick 99 вне диапазона' eq "$(rc_of "$BIN/wallpaper-colors" pick 99)" 2

: >"$LOG"
$BIN/wallpaper-colors pick abc >/dev/null 2>&1 || true
check 'невалидный pick не трогает off' test ! -s "$STATE/off"

printf 'garbage\n' >"$STATE/glass-alpha"
printf 'garbage\n' >"$STATE/glass-blur"
check 'values при битом состоянии' eq "$($BIN/glass-style values)" '{"alpha":0.85,"blur":4}'
check 'install-config --light при битом alpha' eq "$(rc_of "$BIN/install-config" --light garbage)" 0
check 'shell.toml не сломан' grep -q 'background-alpha = 0.85' "$HOME_DIR/.config/omarchy/shell.toml"
$BIN/install-config 0.66 >/dev/null 2>&1
check 'install-config с позиционным alpha' grep -q 'background-alpha = 0.66' "$HOME_DIR/.config/omarchy/shell.toml"
$BIN/install-config garbage >/dev/null 2>&1
check 'install-config с битым alpha берёт default' grep -q 'background-alpha = 0.85' "$HOME_DIR/.config/omarchy/shell.toml"
printf '0\n' >"$STATE/glass-blur"
$BIN/install-config >/dev/null 2>&1
check 'install-config восстанавливает blur=no' grep -q 'blur=no' "$CUR/theme/foot.ini"

# --- штатный стиль ---
$BIN/glass-style opaque >/dev/null 2>&1
: >"$LOG"
$BIN/glass-style alpha 0.50 >/dev/null 2>&1
$BIN/glass-style blur 6 >/dev/null 2>&1
check 'opaque игнорирует alpha' test ! -f "$STATE/glass-alpha"
check 'opaque → values по умолчанию' eq "$($BIN/glass-style values)" '{"alpha":1.0,"blur":6}'
check 'opaque не включает blur в foot' bash -c '! grep -q blur=yes "$1"' _ "$CUR/theme/foot.ini"
check 'opaque не дёргает OSC foot' bash -c '! grep -q "omarchy-theme-set-foot" "$1"' _ "$LOG"

# --- сбой зависимости ---
mv "$STUBS/hyprctl" "$TMP/hyprctl.off"
check 'нет hyprctl — install-config --light не падает' eq "$(rc_of "$BIN/install-config" --light 0.77)" 0
check 'нет hyprctl — shell.toml обновлён' grep -q 'background-alpha = 0.77' "$HOME_DIR/.config/omarchy/shell.toml"
mv "$TMP/hyprctl.off" "$STUBS/hyprctl"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
