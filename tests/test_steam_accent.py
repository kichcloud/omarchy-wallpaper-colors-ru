#!/usr/bin/env python3
"""Юнит-тесты чистых частей steam-accent (без Steam и CDP)."""
import importlib.machinery
import importlib.util
import io
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

MODULE = Path(__file__).resolve().parents[1] / "assets/steam/steam-accent.py"
loader = importlib.machinery.SourceFileLoader("steam_accent", str(MODULE))
spec = importlib.util.spec_from_loader("steam_accent", loader)
sa = importlib.util.module_from_spec(spec)
sys.modules["steam_accent"] = sa
loader.exec_module(sa)


class IdentityMapper:
    accent = "#b2c5ff"
    ac = 0.1
    ah = 250.0
    scale = 1.0

    def map(self, c):
        return tuple(c)


class ColorMath(unittest.TestCase):
    def test_oklch_roundtrip(self):
        for original in ((255, 0, 0), (0, 255, 0), (18, 52, 86), (200, 200, 200)):
            l, c, h = sa.oklch(original)
            got = sa.lch_rgb(l, c, h)
            for a, b in zip(original, got):
                self.assertLessEqual(abs(a - b), 3, (original, got))

    def test_rgb_helper(self):
        # 3-значный hex раскрывается по стандарту: #abc == #aabbcc.
        self.assertEqual(sa.rgb("#abc"), (170, 187, 204))
        self.assertEqual(sa.rgb("#11223344"), (17, 34, 51))


class Retint(unittest.TestCase):
    def test_mapped_alpha(self):
        m = IdentityMapper()
        self.assertEqual(sa.mapped(m, (1, 2, 3), 0, "#orig"), "#orig")
        self.assertEqual(sa.mapped(m, (1, 2, 3), 1, "#orig"), "#010203")
        self.assertEqual(sa.mapped(m, (1, 2, 3), 0.5, "#orig"), "rgba(1, 2, 3, 0.5)")

    def test_retint_keeps_urls_and_strings(self):
        css = 'a{background:url("#ff0000");content:"#ff0000";color:#ff0000}'
        out = sa.retint(css, IdentityMapper())
        self.assertIn('url("#ff0000")', out)
        self.assertIn('content:"#ff0000"', out)
        self.assertIn('color:#ff0000', out)

    def test_retint_keeps_zero_alpha(self):
        out = sa.retint("a{color:#ff000000}", IdentityMapper())
        self.assertIn("#ff000000", out)

    def test_single_pass_restore(self):
        # 700 плейсхолдеров должны восстановиться без потерь и без O(n*len).
        css = ";".join(f"a{{color:#{i:06x}}}" for i in range(700))
        out = sa.retint(css, IdentityMapper())
        self.assertEqual(out.count("color:#"), 700)
        self.assertNotIn("\x00", out)


class Build(unittest.TestCase):
    def test_build_stylesheet_uses_given_dir(self):
        with tempfile.TemporaryDirectory() as td:
            d = Path(td)
            (d / "sp.css").write_text("--color-blue-1: #123456; --color-blue-7: #654321;")
            (d / "theme.css").write_text(".x{color:#112233}" + " " * 120)
            css = sa.build_stylesheet(IdentityMapper(), d)
        self.assertIn("--omarchy-accent:#b2c5ff", css)
        self.assertIn("--omarchy-accent-rgb:178,197,255", css)
        self.assertIn("--color-accent-1:", css)
        self.assertIn("--color-accent-7:", css)
        self.assertIn(".x{color:#112233}", css)


class Failures(unittest.TestCase):
    def test_palette_force_override(self):
        """STEAM_ACCENT_FORCE должен подменять акцент, если это корректный hex."""
        out = mock.Mock(stdout="accent\t#112233\nbackground\t#000000\n")
        with mock.patch.object(sa.subprocess, "run", return_value=out), \
             mock.patch.dict(os.environ, {"STEAM_ACCENT_FORCE": "#ff0000"}):
            self.assertEqual(sa.palette()["accent"], "#ff0000")

    def test_palette_force_garbage_ignored(self):
        """Невалидный STEAM_ACCENT_FORCE не должен ломать палитру."""
        out = mock.Mock(stdout="accent\t#112233\n")
        with mock.patch.object(sa.subprocess, "run", return_value=out), \
             mock.patch.dict(os.environ, {"STEAM_ACCENT_FORCE": "not-a-color"}):
            self.assertEqual(sa.palette()["accent"], "#112233")

    def test_pages_unavailable(self):
        """Нет CDP — возвращаем пустой список, а не исключение."""
        with mock.patch.object(sa.urllib.request, "urlopen", side_effect=OSError("no cdp")):
            self.assertEqual(sa.pages(), [])

    def test_inject_without_targets(self):
        """Нет вкладок — inject возвращает 0 и не падает."""
        with mock.patch.object(sa, "pages", return_value=[]):
            self.assertEqual(sa.inject("css", "rev"), 0)

    def test_flag_failure_does_not_crash(self):
        """Недоступный ~/.steam не должен ронять --once."""
        flag = mock.MagicMock()
        flag.parent.mkdir.side_effect = OSError("denied")
        fake_sys = mock.MagicMock()
        fake_sys.argv = ["steam-accent", "--once"]
        fake_sys.stderr = io.StringIO()
        with mock.patch.object(sa, "FLAG", flag), \
             mock.patch.object(sa, "refresh", return_value=("css", None)), \
             mock.patch.object(sa, "sys", fake_sys):
            self.assertEqual(sa.main(), 0)
        self.assertIn("cannot create CDP flag", fake_sys.stderr.getvalue())

    def test_refresh_keeps_old_css_on_generation_error(self):
        """Сбой генерации не должен стирать уже применённый CSS."""
        with mock.patch.object(sa, "signature", return_value=(1, 0, 0, 0)), \
             mock.patch.object(sa, "stylesheet", side_effect=RuntimeError("boom")), \
             mock.patch.object(sa, "inject", return_value=0) as inj, \
             mock.patch.object(sys, "stderr", new_callable=io.StringIO) as err:
            css, sig = sa.refresh("old-css", None)
        self.assertEqual(css, "old-css")
        self.assertIsNone(sig)
        self.assertIn("generate failed", err.getvalue())
        inj.assert_called_once_with("old-css", mock.ANY)


class UnusualInputs(unittest.TestCase):
    def test_retint_percent_alpha(self):
        out = sa.retint("a{color:rgba(1, 2, 3, 50%)}", IdentityMapper())
        self.assertIn("rgba(1, 2, 3, 0.5)", out)

    def test_retint_empty_css(self):
        self.assertEqual(sa.retint("", IdentityMapper()), "")

    def test_retint_no_placeholder_collision(self):
        """Литеральные NUL-последовательности в CSS не должны ломать retint."""
        src = 'a{content:"\\x000\\x00";color:#ffffff}'
        out = sa.retint(src, IdentityMapper())
        self.assertIn('content:"\\x000\\x00"', out)
        self.assertIn('color:#ffffff', out)

    def test_build_empty_dir(self):
        with tempfile.TemporaryDirectory() as td:
            css = sa.build_stylesheet(IdentityMapper(), Path(td))
        self.assertIn("--omarchy-accent:#b2c5ff", css)
        self.assertEqual(css.count("{"), 1)  # только :root


if __name__ == "__main__":
    unittest.main()
