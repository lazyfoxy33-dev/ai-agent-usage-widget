import os
import unittest


INDEX = os.path.join(os.path.dirname(__file__), "..", "index.jsx")


class TestWidgetSource(unittest.TestCase):
    def setUp(self):
        with open(INDEX) as f:
            self.source = f.read()

    def test_codex_accent_is_new_purple_and_has_no_gradient(self):
        self.assertIn('accent: "#7B83F5"', self.source)
        self.assertNotIn("#6676FF", self.source)
        self.assertNotIn("codexAccentGradient", self.source)
        self.assertNotIn("codexSoftGradient", self.source)
        self.assertNotIn("linearGradient", self.source)

    def test_themes_follow_system_and_use_brand_tint_backgrounds(self):
        self.assertIn("prefers-color-scheme: dark", self.source)
        self.assertIn("matchMedia", self.source)
        # Brand tint backgrounds from the redesign spec
        self.assertIn("#FAF7F3", self.source)
        self.assertIn("#211F1C", self.source)
        self.assertIn("#F6F6FB", self.source)
        self.assertIn("#1B1B23", self.source)
        self.assertIn("#F4F7FC", self.source)
        self.assertIn("#181C24", self.source)

    def test_tone_tokens_are_chosen_from_theme(self):
        self.assertIn('ink: "#26231F"', self.source)
        self.assertIn('sub: "#9a9286"', self.source)
        self.assertIn('track: "rgba(0,0,0,.09)"', self.source)
        self.assertIn('div: "rgba(0,0,0,.06)"', self.source)
        self.assertIn('ink: "#ECEAE6"', self.source)
        self.assertIn('sub: "#8c887f"', self.source)
        self.assertIn('track: "rgba(255,255,255,.13)"', self.source)
        self.assertIn('div: "rgba(255,255,255,.07)"', self.source)

    def test_two_letter_quota_codes_and_header_reset_countdown(self):
        self.assertIn('label === "Weekly" ? "Wk"', self.source)
        self.assertIn('"Wk"', self.source)
        self.assertIn("↻", self.source)
        self.assertIn("function soonestWindow", self.source)
        self.assertIn("soonestWindow(wins)", self.source)

    def test_no_resets_in_prefix(self):
        self.assertNotIn("Resets in", self.source)

    def test_bar_rows_use_track_fill_and_semantic_value_color(self):
        self.assertIn("function usageBarRow", self.source)
        self.assertIn("dangerTrack", self.source)
        self.assertIn("width: `${clamped}%`", self.source)
        self.assertIn("width: 46", self.source)
        self.assertIn("width: 38", self.source)

    def test_bar_primary_design_replaces_ring_primary(self):
        self.assertIn("function usageBarRow", self.source)
        self.assertIn("function usagePanel", self.source)
        self.assertIn("usageBarRow(wins[0]", self.source)
        self.assertIn("usageBarRow(wins[1]", self.source)
        self.assertNotIn("function ring(", self.source)
        self.assertNotIn("<circle", self.source)

    def test_widget_is_anchored_to_top_left(self):
        self.assertIn("left: 40px; top: 40px;", self.source)
        self.assertNotIn("right: 40px; bottom: 40px;", self.source)

    def test_two_state_captions_and_i18n_dictionary(self):
        self.assertIn("缓存数据 · 等待刷新", self.source)
        self.assertIn("Cached · awaiting refresh", self.source)
        self.assertIn("未登录 · 请先在", self.source)
        self.assertIn("Not signed in · Log in via", self.source)
        self.assertIn("请求受限 · 稍后自动重试", self.source)
        self.assertIn("Rate limited · retrying soon", self.source)
        self.assertIn("Claude Code", self.source)
        self.assertIn("Codex CLI", self.source)
        self.assertIn("Kimi CLI", self.source)
        self.assertIn("navigator.language", self.source)

    def test_app_icons_are_kept(self):
        self.assertIn('src="/usage-widget/assets/claude-app.png"', self.source)
        self.assertIn('src="/usage-widget/assets/codex-app.png"', self.source)
        self.assertIn('src="/usage-widget/assets/kimi-code.png"', self.source)
        self.assertIn('src="/usage-widget/assets/deepseek.png"', self.source)
        self.assertIn('src="/usage-widget/assets/siliconflow.png"', self.source)
        self.assertIn('src="/usage-widget/assets/openrouter.png"', self.source)
        self.assertNotIn("glyphLogo(\"D\"", self.source)
        self.assertNotIn("glyphLogo(\"S\"", self.source)
        self.assertNotIn("glyphLogo(\"O\"", self.source)

    def test_command_reads_only_control_app_shared_state_at_runtime(self):
        self.assertNotIn("Übersicht/widgets/usage-widget", self.source)
        self.assertNotIn("Übersicht/widgets/usage-widget", self.source)
        self.assertNotIn("FETCHER_DIRS", self.source)
        self.assertNotIn("for d in", self.source)
        self.assertIn("QUOTAWIDGET_SHARED_USAGE", self.source)
        self.assertIn("group.dev.lazyfoxy.QuotaWidget", self.source)
        self.assertIn("usage.json", self.source)

    def test_old_design_tokens_are_removed(self):
        self.assertNotIn('soft: "#A78BFA"', self.source)
        self.assertNotIn('soft: "#252A33"', self.source)

    def test_widget_prefers_control_app_shared_state(self):
        self.assertIn("QUOTAWIDGET_SHARED_USAGE", self.source)
        self.assertIn("group.dev.lazyfoxy.QuotaWidget", self.source)
        self.assertIn("usage.json", self.source)


if __name__ == "__main__":
    unittest.main()
