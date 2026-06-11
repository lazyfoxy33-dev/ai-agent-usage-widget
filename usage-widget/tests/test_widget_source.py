import os
import unittest


INDEX = os.path.join(os.path.dirname(__file__), "..", "index.jsx")


class TestWidgetSource(unittest.TestCase):
    def setUp(self):
        with open(INDEX) as f:
            self.source = f.read()

    def test_three_digit_percentage_uses_smaller_font(self):
        self.assertIn("function pctFontSize", self.source)
        self.assertIn("pct >= 100 ? 14 : 18", self.source)
        self.assertIn("fontSize: pctFontSize(fivePct)", self.source)
        self.assertIn('transform: "translateY(-1px)"', self.source)
        self.assertIn("fontSize: 8", self.source)

    def test_codex_uses_blue_purple_app_identity(self):
        self.assertIn('accent: "#6676FF"', self.source)
        self.assertIn('soft: "#A78BFA"', self.source)
        self.assertIn("codexAccentGradient", self.source)
        self.assertIn("codex-cloud", self.source)
        self.assertNotIn("#19C37D", self.source)


if __name__ == "__main__":
    unittest.main()
