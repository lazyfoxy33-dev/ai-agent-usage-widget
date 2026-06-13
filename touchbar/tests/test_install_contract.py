import os
import unittest


ROOT = os.path.dirname(os.path.dirname(__file__))


def read_script(name):
    with open(os.path.join(ROOT, name)) as handle:
        return handle.read()


class TestTouchBarInstallContract(unittest.TestCase):
    def test_shared_signer_cleans_metadata_and_verifies_signature(self):
        self.assertTrue(os.path.exists(os.path.join(ROOT, "sign_bundle.sh")))
        source = read_script("sign_bundle.sh")

        self.assertIn('xattr -cr "$app"', source)
        self.assertIn('codesign --force --deep --sign - "$app"', source)
        self.assertIn(
            'codesign --verify --deep --strict --verbose=2 "$app"',
            source,
        )
        self.assertIn("for attempt in", source)
        self.assertIn("return 1", source)

    def test_build_uses_shared_strict_signer(self):
        source = read_script("build.sh")

        self.assertIn('./sign_bundle.sh "$APP"', source)
        self.assertNotIn("codesign ", source)

    def test_installer_uses_stable_applications_copy(self):
        source = read_script("install.sh")

        self.assertIn('INSTALL_APP="$HOME/Applications/QuotaBar.app"', source)
        self.assertIn('${INSTALL_APP}…', source)
        self.assertIn("ditto --norsrc --noextattr", source)
        self.assertIn('./sign_bundle.sh "$INSTALL_APP"', source)
        self.assertIn(
            'sed "s#__APP_PATH__#$INSTALL_APP#g"',
            source,
        )

        template = read_script("com.quotabar.app.plist")
        self.assertIn(
            "__APP_PATH__/Contents/MacOS/QuotaBar",
            template,
        )

    def test_installer_reloads_launch_agent_in_gui_domain(self):
        source = read_script("install.sh")

        self.assertIn('launchctl print "$GUI_DOMAIN/$LABEL"', source)
        self.assertIn("launchctl bootout", source)
        self.assertNotIn(
            'launchctl bootout "$GUI_DOMAIN/$LABEL" 2>/dev/null || true',
            source,
        )
        self.assertIn("launchctl bootstrap", source)
        self.assertIn("launchctl kickstart -k", source)
        self.assertIn("pkill -x QuotaBar", source)


if __name__ == "__main__":
    unittest.main()
