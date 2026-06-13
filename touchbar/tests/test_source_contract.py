import os
import unittest


ROOT = os.path.dirname(os.path.dirname(__file__))


class TestTouchBarFreshnessSource(unittest.TestCase):
    def test_provider_decodes_shared_freshness_fields(self):
        with open(os.path.join(ROOT, "Sources", "DataSource.swift")) as f:
            source = f.read()

        self.assertIn("var live: Bool?", source)
        self.assertIn('o["live"] as? Bool', source)
        self.assertIn('o["fetched_at"]', source)

    def test_rendering_dims_provider_level_stale_data(self):
        with open(os.path.join(ROOT, "Sources", "TouchBarController.swift")) as f:
            source = f.read()

        self.assertIn("p.live == false", source)
        self.assertIn("·缓存", source)

    def test_modal_marks_detail_as_the_principal_item(self):
        with open(os.path.join(ROOT, "Sources", "TouchBarController.swift")) as f:
            source = f.read()

        self.assertIn("bar.principalItemIdentifier = detailID", source)
        self.assertIn("it.visibilityPriority = .high", source)

    def test_modal_detail_has_an_explicit_visible_width(self):
        with open(os.path.join(ROOT, "Sources", "TouchBarController.swift")) as f:
            source = f.read()

        self.assertIn("detailField.widthAnchor.constraint", source)
        self.assertIn("detailWidthConstraint", source)


if __name__ == "__main__":
    unittest.main()
