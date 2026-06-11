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
        self.assertIn('src="/usage-widget/assets/codex-app.png"', self.source)
        self.assertIn('objectFit: "contain"', self.source)
        self.assertNotIn('aria-label="codex-cloud"', self.source)
        self.assertNotIn("#19C37D", self.source)

    def test_codex_icon_uses_apple_style_continuous_corners(self):
        self.assertIn('borderRadius: 8', self.source)
        self.assertIn('overflow: "hidden"', self.source)
        self.assertIn(
            'WebkitMaskImage: "-webkit-radial-gradient(white, black)"',
            self.source,
        )

    def test_kimi_uses_official_console_palette_and_logo(self):
        self.assertIn('const KM = { accent: "#1478FF"', self.source)
        self.assertIn('soft: "#252A33"', self.source)
        self.assertIn('src="/usage-widget/assets/kimi-code.png"', self.source)
        self.assertIn('panel("Kimi Code"', self.source)
        self.assertIn("data.kimi", self.source)

    def test_cached_provider_data_is_visibly_marked(self):
        self.assertIn('data.reason === "stale"', self.source)
        self.assertIn("缓存数据", self.source)

    def test_widget_is_anchored_to_bottom_right(self):
        self.assertIn("right: 40px; bottom: 40px;", self.source)
        self.assertNotIn("left: 40px; top: 40px;", self.source)


if __name__ == "__main__":
    unittest.main()
