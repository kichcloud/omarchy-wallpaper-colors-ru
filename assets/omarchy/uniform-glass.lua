-- Единая прозрачность и блюр для ВСЕГО: окон, бара, доков, меню,
-- уведомлений, tooltip'ов, OSD и всплывающих окон.
-- Стиль переключается кнопками в панели «Цвета обоев»:
--   ~/.local/state/omarchy/uniform-glass/style → glass | opaque

local styleFile = (os.getenv("HOME") or "") .. "/.local/state/omarchy/uniform-glass/style"
local style = "glass"
local sf = io.open(styleFile, "r")
if sf then
  local v = sf:read("*l")
  if v == "glass" or v == "opaque" then style = v end
  sf:close()
end
local A = (style == "opaque") and 1.0 or 0.85

hl.config({
  decoration = {
    active_opacity = A,
    inactive_opacity = A,
    blur = {
      enabled = true,
      size = 4,
      passes = 2,
      brightness = 0.75,
      popups = true,
      special = true,
      -- Штатный toggle window-glassy включает new_optimizations, из-за чего
      -- блюр статических окон кэшируется и перестаёт быть виден. Гасим его.
      new_optimizations = false,
    },
  },
})

-- Absolute opacity for every window. Overrides exceptions from Omarchy,
-- Hyprforge and per-app rules (e.g. Vesktop, +transparent-window => 1 1).
hl.window_rule({
  name = "uniform-glass-opacity",
  match = { class = ".*" },
  opacity = string.format("%.2f override %.2f override", A, A),
})

-- Терминалы задают прозрачность фона сами (foot alpha=0.85): Hyprland
-- размывает только под поверхностями со своей alpha < 1. Поэтому здесь
-- композиторская opacity = 1, чтобы итог остался 0.85 и текст был резким.
hl.window_rule({
  name = "terminal-native-alpha",
  match = { tag = "terminal" },
  opacity = "1 override 1 override",
})

-- Все окна, включая браузер, остаются одинаково прозрачными (A).
-- Раньше здесь было исключение для полноэкранного видео, но оно срабатывало
-- и при "на всю ширину" (maximized) — браузер становился непрозрачным.
-- Теперь все состояния браузера остаются одинаково стеклянными.

-- В штатном стиле подавляем собственную alpha окон (в том числе foot 0.85),
-- иначе OpenCode остаётся прозрачным даже при актив_opacity = 1.
if style == "opaque" then
  hl.window_rule({
    name = "uniform-opaque-force-rgbx",
    match = { class = ".*" },
    force_rgbx = true,
  })
end

-- Blur on every Wayland layer surface, not just the shell whitelist.
hl.layer_rule({
  name = "uniform-glass-layers",
  match = { namespace = ".*" },
  blur = true,
  blur_popups = true,
  ignore_alpha = 0.02,
})
