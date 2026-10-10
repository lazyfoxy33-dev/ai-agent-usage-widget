import os
import unittest


ROOT = os.path.dirname(os.path.dirname(__file__))


def _read(*parts):
    with open(os.path.join(ROOT, *parts)) as f:
        return f.read()


class TestTouchBarFreshnessSource(unittest.TestCase):
    def test_provider_decodes_shared_freshness_fields(self):
        source = _read("Sources", "DataSource.swift")

        self.assertIn("var live: Bool?", source)
        self.assertIn('o["live"] as? Bool', source)
        self.assertIn('o["fetched_at"]', source)

    def test_rendering_dims_provider_level_stale_data(self):
        # Stale/cached data is now surfaced by dimming the whole gauge card
        # (`cached:`) rather than appending a "·缓存" label.
        source = _read("Sources", "TouchBarController.swift")

        self.assertIn("p.live == false", source)
        self.assertIn("cached:", source)
        self.assertIn("cached ? 0.62 : 1", _read("Sources", "ProviderGauge.swift"))

    def test_modal_lays_out_one_gauge_per_configured_provider(self):
        # Providers are no longer hardcoded: the modal builds one item per
        # configured provider, in the configured order.
        source = _read("Sources", "TouchBarController.swift")

        self.assertIn("for (index, provider) in layout.enumerated()", source)
        self.assertIn("identifiers.append(itemID(provider))", source)
        self.assertIn("TouchBarLayout.load()", source)
        self.assertNotIn("claudeID", source, "provider identifiers are derived, not fixed")
        self.assertIn("it.visibilityPriority = .high", source)

    def test_balance_providers_render_an_amount(self):
        gauge = _read("Sources", "ProviderGauge.swift")
        controller = _read("Sources", "TouchBarController.swift")

        self.assertIn("func updateBalance(", gauge)
        self.assertIn("balanceRows()", gauge)
        self.assertIn("provider.isBalance", controller)
        self.assertIn("feedBalance(", controller)

    def test_gauge_has_an_explicit_visible_width(self):
        # The single oversized text field was replaced by fixed-width gauges, so
        # the modal's total length stays bounded.
        source = _read("Sources", "ProviderGauge.swift")

        self.assertIn("widthAnchor.constraint(equalToConstant:", source)


class TestTouchBarForegroundGlance(unittest.TestCase):
    def test_collapsed_cell_follows_frontmost_ai_app(self):
        source = _read("Sources", "TouchBarController.swift")

        # Tracks the frontmost desktop app and maps it to a provider tag.
        self.assertIn("didActivateApplicationNotification", source)
        self.assertIn("providerTag(forFrontmost", source)
        # Falls back to the most recently used tool, persisted across launches.
        self.assertIn("lastUsedTag", source)
        self.assertIn('UserDefaults.standard.set(lastUsedTag', source)


if __name__ == "__main__":
    unittest.main()
