-- Единая прозрачность и блюр для ВСЕГО: окон, бара, доков, меню,
-- уведомлений, tooltip'ов, OSD и всплывающих окон.
-- Стиль переключается кнопками в панели «Цвета обоев»:
--   ~/.local/state/omarchy/wallpaper-colors/glass-style → glass | opaque

local styleFile = (os.getenv("HOME") or "") .. "/.local/state/omarchy/wallpaper-colors/glass-style"
local style = "glass"
local sf = io.open(styleFile, "r")
if sf then
  local v = sf:read("*l")
  if v == "glass" or v == "opaque" then style = v end
  sf:close()
end
local stateDir = (os.getenv("HOME") or "") .. "/.local/state/omarchy/wallpaper-colors"

-- Ползунки плагина пишут сюда переопределения; без них — стиль по умолчанию.
local function numberFrom(name, fallback, min, max)
  local f = io.open(stateDir .. "/" .. name, "r")
  if not f then return fallback end
  local n = tonumber((f:read("*l") or ""):match("^[%d%.]+$"))
  f:close()
  if not n then return fallback end
  return math.max(min, math.min(max, n))
end

local alphaOverride = numberFrom("glass-alpha", nil, 0.30, 1.0)
local A = alphaOverride or ((style == "opaque") and 1.0 or 0.85)
local blurSize = numberFrom("glass-blur", 4, 0, 30)

hl.config({
  decoration = {
    active_opacity = A,
    inactive_opacity = A,
    blur = {
      -- При полностью непрозрачных поверхностях размывать нечего.
      enabled = blurSize > 0 and A < 1.0,
      size = blurSize,
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

-- Folio тоже рисует фон сам (wrapper подставляет альфу в colors.toml).
hl.window_rule({
  name = "folio-native-alpha",
  match = { class = "folio" },
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
