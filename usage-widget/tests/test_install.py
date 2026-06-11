import os
import unittest


ROOT = os.path.join(os.path.dirname(__file__), "..")
INSTALL = os.path.join(ROOT, "install.sh")
ASSETS = os.path.join(ROOT, "assets")


class TestInstall(unittest.TestCase):
    def test_provider_assets_exist(self):
        self.assertTrue(os.path.isfile(os.path.join(ASSETS, "kimi-code.png")))
        self.assertTrue(os.path.isfile(os.path.join(ASSETS, "codex-app.png")))

    def test_installer_copies_assets_directory(self):
        with open(INSTALL) as f:
            source = f.read()

        self.assertIn('rm -rf "$DEST/assets"', source)
        self.assertIn('cp -R "$SRC/assets" "$DEST/"', source)

    def test_installer_removes_obsolete_refresh_script(self):
        with open(INSTALL) as f:
            source = f.read()

        self.assertIn('rm -f "$DEST/codex-refresh.sh"', source)


if __name__ == "__main__":
    unittest.main()
