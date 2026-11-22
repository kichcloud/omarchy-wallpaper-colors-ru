#!/usr/bin/env python3
"""Юнит-тесты чистых частей steam-accent (без Steam и CDP)."""
import importlib.machinery
import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

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
        # Важно зафиксировать текущее поведение: 3-значный hex раскрывается как
        # "abcabc", а не "aabbcc". Это отдельный баг, не трогаем в рефакторинге.
        self.assertEqual(sa.rgb("#abc"), (171, 202, 188))
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


if __name__ == "__main__":
    unittest.main()
