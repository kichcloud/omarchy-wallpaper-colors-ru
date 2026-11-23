#!/usr/bin/env python3
"""Omarchy -> Steam live accent bridge: one daemon, no third-party mods.

Источник: https://github.com/kichcloud/omarchy-steam-accent (MIT, см. LICENSE).
В плагине вызывается в режиме --once при смене палитры и в режиме --follow
при запуске Steam; постоянного демона нет.
"""
import base64, hashlib, json, math, os, re, socket, struct, subprocess, sys, time, urllib.request
from pathlib import Path
from urllib.parse import urlparse

HOME = Path.home()
STEAM = HOME / ".local/share/Steam"
CSS_DIR = STEAM / "steamui/css"
FLAG = HOME / ".steam/steam/.cef-enable-remote-debugging"
CDP = "http://127.0.0.1:8080"


def srgb(c):
    c /= 255
    return c / 12.92 if c <= .04045 else ((c + .055) / 1.055) ** 2.4


def lin(c):
    c = max(0, min(1, c))
    return round((12.92 * c if c <= .0031308 else 1.055 * c ** (1 / 2.4) - .055) * 255)


def cb(v):
    return math.copysign(abs(v) ** (1 / 3), v)


def oklab(rgb):
    r, g, b = map(srgb, rgb)
    l, m, s = (.4122214708*r+.5363325363*g+.0514459929*b,
               .2119034982*r+.6806995451*g+.1073969566*b,
               .0883024619*r+.2817188376*g+.6299787005*b)
    l, m, s = cb(l), cb(m), cb(s)
    return (.2104542553*l+.793617785*m-.0040720468*s,
            1.9779984951*l-2.428592205*m+.4505937099*s,
            .0259040371*l+.7827717662*m-.808675766*s)


def lab_rgb(l, a, b):
    l_, m_, s_ = l+.3963377774*a+.2158037573*b, l-.1055613458*a-.0638541728*b, l-.0894841775*a-1.2914855480*b
    l, m, s = l_**3, m_**3, s_**3
    return tuple(lin(x) for x in (4.0767416621*l-3.3077115913*m+.2309699292*s,
                                  -1.2684380046*l+2.6097574011*m-.3413193965*s,
                                  -.0041960863*l-.7034186147*m+1.707614701*s))


def oklch(rgb):
    l, a, b = oklab(rgb)
    return l, math.hypot(a, b), math.degrees(math.atan2(b, a)) % 360


def lch_rgb(l, c, h):
    r = math.radians(h)
    return lab_rgb(l, c * math.cos(r), c * math.sin(r))


def rgb(h):
    h = h.lstrip("#")
    h = "".join(c * 2 for c in h[:3]) if len(h) == 3 else h[:6]
    return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))


def hx(c):
    return "#%02x%02x%02x" % c


NEUTRAL = ("darker_bg", "dark_bg", "bg", "lighter_bg", "muted", "dark_fg", "fg", "bright_fg")
FAMILIES = (("red", ("red", "bright_red"), 25), ("orange", ("orange",), 55),
            ("yellow", ("yellow", "bright_yellow", "brown"), 90), ("green", ("green", "bright_green"), 135),
            ("cyan", ("cyan", "bright_cyan"), 190), ("magenta", ("magenta", "bright_magenta"), 350))


def palette():
    out = subprocess.run(["omarchy-theme-color", "--all"], capture_output=True, text=True, check=True).stdout
    return dict(line.partition("\t")[::2] for line in out.splitlines() if "\t" in line)


class Mapper:
    def __init__(self, p):
        self.accent = p.get("accent") or p.get("color4") or "#de5346"
        _, ac, ah = oklch(rgb(self.accent))
        self.ac, self.ah, self.scale = ac, ah, max(ac, .02) / .175
        valid = lambda k: re.fullmatch("#[0-9a-fA-F]{6}", p.get(k, ""))
        self.n = sorted(map(lambda k: oklab(rgb(p[k])), filter(valid, NEUTRAL))) or [oklab((22, 26, 27)), oklab((244, 242, 230))]
        self.f = []
        for _, keys, hue in FAMILIES:
            v = next((p[k] for k in keys if valid(k)), None)
            _, c, fh = oklch(rgb(v)) if v else (0, .07, hue)
            self.f.append((max(c, .04), fh))

    def neutral(self, l):
        n = self.n
        if l <= n[0][0]:
            return lab_rgb(*n[0])
        if l >= n[-1][0]:
            return lab_rgb(*n[-1])
        for a, b in zip(n, n[1:]):
            if l <= b[0]:
                t = (l - a[0]) / (b[0] - a[0] or 1)
                return lab_rgb(l, a[1]+(b[1]-a[1])*t, a[2]+(b[2]-a[2])*t)
        return lab_rgb(*n[-1])

    def map(self, c):
        l, ch, h = oklch(c)
        if ch < .04:
            return self.neutral(l)
        if 210 <= h <= 285:
            return self.neutral(l) if ch < .09 else lch_rgb(l, min(ch*self.scale, .30), self.ah)
        if ch < .045:
            return self.neutral(l)
        fc, fh = min(self.f, key=lambda f: abs((h-f[1]+180) % 360 - 180))
        return lch_rgb(l, min(max(fc, ch*.5), fc*1.8, .16), fh)


HEX = re.compile(r"#[0-9a-fA-F]{8}\b|#[0-9a-fA-F]{6}\b|#[0-9a-fA-F]{3}\b")
RGB = re.compile(r"rgba?\(\s*(\d+)\s*[,\s]\s*(\d+)\s*[,\s]\s*(\d+)\s*(?:[,/]\s*([0-9.]+%?)\s*)?\)", re.I)
PROT = re.compile(r"url\([^)]*\)|\"(?:[^\"\\]|\\.)*\"|'(?:[^'\\]|\\.)*'", re.I | re.S)


def mapped(m, c, a, original):
    """Перекрасить цвет, сохранив прозрачность. a=0 оставляет исходник нетронутым."""
    if not a:
        return original
    n = m.map(c)
    return "rgba(%d, %d, %d, %g)" % (*n, a) if a < .999 else hx(n)


# Один проход: защищённые фрагменты и цвета разбираются одним regex. Раньше
# для защиты цветов подставлялись NUL-плейсхолдеры, которые теоретически могли
# совпасть с литералом в CSS. Теперь плейсхолдеров нет вовсе.
TOKEN = re.compile(PROT.pattern + "|" + HEX.pattern + "|" + RGB.pattern, re.I | re.S)


def retint(css, m):
    def sub(x):
        s = x.group(0)
        if s[0] in "\"'" or s[:3].lower() == "url":
            return s
        if s[0] == "#":
            h = s[1:]
            a = int(h[6:8], 16)/255 if len(h) == 8 else 1
            return mapped(m, rgb(h), a, s)
        a = float(x[4].rstrip("%"))/(100 if "%" in x[4] else 1) if x[4] else 1
        return mapped(m, (int(x[1]), int(x[2]), int(x[3])), a, s)

    return TOKEN.sub(sub, css)


def build_stylesheet(m, css_dir):
    """Собрать CSS из маппера и каталога стилей — без обращения к палитре темы."""
    sp = css_dir / "sp.css"
    scale = {}
    if sp.is_file():
        for step, value in re.findall(r"--color-blue-(\d+)\s*:\s*(#[0-9a-fA-F]{6})", sp.read_text(errors="replace")):
            scale.setdefault(int(step), value)
    lines = [":root{"]
    for step in sorted(scale or {i: "#1a9fff" for i in range(1, 13)}):
        l, c, _ = oklch(rgb(scale.get(step, "#1a9fff")))
        ch = c*m.scale
        if step >= 7:
            ch = max(ch, m.ac*.95)
        lines.append("--color-accent-%d:%s;" % (step, hx(lch_rgb(l, min(ch, .30), m.ah))))
    a = rgb(m.accent)
    lines += ["--color-accent-contrast:%s" % ("#000000" if .299*a[0]+.587*a[1]+.114*a[2] > 186 else "#ffffff"),
              "--omarchy-accent:%s" % m.accent,
              "--omarchy-accent-rgb:%d,%d,%d" % a, "}"]
    out = ["\n".join(lines)]
    for f in sorted(css_dir.glob("*.css")):
        css = retint(f.read_text(errors="replace"), m)
        if len(css) > 100:
            out.append(css)
    return "\n".join(out)


def stylesheet():
    return build_stylesheet(Mapper(palette()), CSS_DIR)


class WS:
    def __init__(self, url):
        u = urlparse(url)
        self.s = socket.create_connection((u.hostname, u.port), 3)
        self.s.settimeout(3)
        key = base64.b64encode(os.urandom(16)).decode()
        self.s.sendall(("GET %s HTTP/1.1\r\nHost: %s:%d\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                        "Sec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\n\r\n" % (u.path, u.hostname, u.port, key)).encode())
        buf = b""
        while b"\r\n\r\n" not in buf:
            buf += self.s.recv(4096)

    def send(self, obj):
        d = json.dumps(obj).encode()
        k = os.urandom(4)
        n = len(d)
        h = (bytes([0x81, 0x80|n]) if n < 126 else
             bytes([0x81, 0xFE])+struct.pack("!H", n) if n < 65536 else
             bytes([0x81, 0xFF])+struct.pack("!Q", n))
        self.s.sendall(h+k+bytes(c^k[i % 4] for i, c in enumerate(d)))

    def recv(self):
        b = self.s.recv(2)
        n = b[1] & 127
        if n == 126:
            n = struct.unpack("!H", self.s.recv(2))[0]
        elif n == 127:
            n = struct.unpack("!Q", self.s.recv(8))[0]
        if b[1] & 128:
            k = self.s.recv(4)
            d = bytes(c^k[i % 4] for i, c in enumerate(self.s.recv(n)))
        else:
            d = self.s.recv(n)
        return json.loads(d)

    def evaluate(self, expr):
        self.send({"id": 1, "method": "Runtime.evaluate", "params": {"expression": expr, "returnByValue": True}})
        while True:
            r = self.recv()
            if r.get("id") == 1:
                return r.get("result", {}).get("result", {}).get("value")


CHECK = "document.getElementById('omarchy-accent')?.dataset.rev||''"


def pages():
    """CDP-цели типа page. Пустой список, если отладка в Steam не включена."""
    try:
        return [t for t in json.load(urllib.request.urlopen(CDP+"/json/list", timeout=2))
                if t.get("type") == "page"]
    except Exception:
        return []


def inject(css, rev):
    apply = ("(()=>{let s=document.getElementById('omarchy-accent');if(!s){s=document.createElement('style');"
             "s.id='omarchy-accent';document.head.appendChild(s)}s.dataset.rev=%s;s.textContent=%s;return 1})()"
             % (json.dumps(rev), json.dumps(css)))
    n = 0
    for t in pages():
        try:
            w = WS(t["webSocketDebuggerUrl"])
            if w.evaluate(CHECK) != rev:
                w.evaluate(apply)
                n += 1
            w.s.close()
        except Exception:
            pass
    return n


def signature():
    # Палитра тоже входит в подпись: иначе процесс --follow, запущенный при
    # старте Steam, мог бы затереть только что применённый новый акцент старым CSS.
    stamps = []
    for p in ("theme.name", "theme.generation", "theme/colors.toml"):
        try:
            st = (HOME/".local/state/omarchy/current"/p).stat()
            stamps.append((st.st_mtime_ns, st.st_size))
        except OSError:
            stamps.append((0, 0))
    files = [(f.stat().st_mtime_ns, f.stat().st_size) for f in CSS_DIR.glob("*.css")]
    return tuple(stamps), len(files), sum(s for _, s in files), max((m for m, _ in files), default=0)


def refresh(css, sig):
    """Один шаг: при необходимости собрать CSS и накатить его на вкладки Steam."""
    s = signature()
    if s != sig:
        try:
            css, sig = stylesheet(), s
        except Exception as e:
            print("generate failed:", e, file=sys.stderr)
            sig = None
    if css:
        n = inject(css, hashlib.sha1(css.encode()).hexdigest()[:12])
        if n:
            print("updated", n, "target(s)", flush=True)
    return css, sig


def timeout_arg(name):
    """Необязательный таймаут в секундах, например --follow 45."""
    try:
        return max(0.0, float(sys.argv[sys.argv.index(name) + 1]))
    except (ValueError, IndexError):
        return 0.0


def follow(seconds):
    """Догонять запускающийся Steam, пока его CDP отвечает.

    Нужен, когда клиент стартует позже оболочки: установочный проход уже
    прошёл, а Steam ещё не открыл CDP. Повторная инъекция переживает
    перезагрузку документа при входе в аккаунт. Это не демон: процесс
    завершается через несколько секунд после старта Steam.
    """
    end = time.monotonic() + seconds
    seen = idle = 0
    css, sig = "", None
    while time.monotonic() < end:
        css, sig = refresh(css, sig)
        if pages():
            seen, idle = 1, 0
        elif seen:
            idle += 1
            if idle >= 3:
                return
        time.sleep(3)


def main():
    try:
        FLAG.parent.mkdir(parents=True, exist_ok=True)
        FLAG.touch()
    except OSError as e:
        # Нет каталога Steam — CDP недоступен, но генерация/инъекция ещё могут
        # сработать, если Steam уже запущен с включённой отладкой.
        print("cannot create CDP flag:", e, file=sys.stderr)
    follow_for = timeout_arg("--follow")
    if follow_for:
        follow(follow_for)
    else:
        refresh("", None)
    return 0


if __name__ == "__main__":
    sys.exit(main())
