import json
import os
import unittest
from unittest import mock

from usage import kimi


FIXTURE = os.path.join(os.path.dirname(__file__), "fixtures", "kimi_usage.json")


class TestKimiCredentials(unittest.TestCase):
    def test_credentials_path_honors_kimi_code_home(self):
        with mock.patch.dict(os.environ, {"KIMI_CODE_HOME": "/tmp/kimi-code"}):
            self.assertEqual(
                kimi.credentials_path(),
                "/tmp/kimi-code/credentials/kimi-code.json",
            )

    def test_credentials_path_defaults_to_home_kimi_code(self):
        with mock.patch.dict(os.environ, {}, clear=True), \
             mock.patch.object(kimi.os.path, "expanduser",
                               side_effect=lambda path: path.replace("~", "/home/me")):
            self.assertEqual(
                kimi.credentials_path(),
                "/home/me/.kimi-code/credentials/kimi-code.json",
            )

    def test_credential_paths_include_legacy_kimi_cli_location(self):
        with mock.patch.dict(os.environ, {"KIMI_SHARE_DIR": "/tmp/legacy"}, clear=True), \
             mock.patch.object(kimi.os.path, "expanduser",
                               side_effect=lambda path: path.replace("~", "/home/me")):
            self.assertEqual(
                kimi.credential_paths(),
                [
                    "/home/me/.kimi-code/credentials/kimi-code.json",
                    "/tmp/legacy/credentials/kimi-code.json",
                ],
            )

    def test_read_credentials_falls_back_to_legacy_location(self):
        valid = mock.mock_open(read_data='{"access_token":"legacy","expires_at":2000}')
        with mock.patch.object(
            kimi,
            "credential_paths",
            return_value=["/new/kimi-code.json", "/old/kimi-code.json"],
        ), mock.patch("builtins.open", valid) as opened:
            opened.side_effect = [FileNotFoundError, valid.return_value]
            result = kimi.read_credentials()

        self.assertEqual(result["access_token"], "legacy")

    def test_read_credentials_returns_mapping(self):
        with mock.patch("builtins.open", mock.mock_open(
            read_data='{"access_token":"abc","expires_at":2000}'
        )):
            self.assertEqual(kimi.read_credentials("/tmp/creds.json")["access_token"], "abc")

    def test_read_credentials_returns_none_for_invalid_file(self):
        with mock.patch("builtins.open", mock.mock_open(read_data="not-json")):
            self.assertIsNone(kimi.read_credentials("/tmp/creds.json"))

    def test_expired_token_detected(self):
        self.assertTrue(kimi.is_expired({"expires_at": 1000}, now=1000))
        self.assertFalse(kimi.is_expired({"expires_at": 1001}, now=1000))


class TestKimiParse(unittest.TestCase):
    def setUp(self):
        with open(FIXTURE) as f:
            self.fixture = json.load(f)

    def test_parse_usage_maps_five_hour_and_weekly(self):
        result = kimi.parse_kimi_usage(self.fixture)

        self.assertEqual(result["five_h"]["pct"], 34)
        self.assertEqual(result["five_h"]["resets_at"], 1781190000)
        self.assertEqual(result["weekly"]["pct"], 8)
        self.assertEqual(result["weekly"]["resets_at"], 1781600000)

    def test_parse_selects_300_minute_window(self):
        result = kimi.parse_kimi_usage(self.fixture)
        self.assertNotEqual(result["five_h"]["pct"], 10)

    def test_parse_accepts_remaining_and_clamps_percentages(self):
        payload = {
            "usage": {"limit": 100, "remaining": -20, "reset_at": 10},
            "limits": [{
                "window": {"duration": 300, "timeUnit": "MINUTE"},
                "detail": {"limit": 100, "remaining": 150, "reset_at": 20},
            }],
        }

        result = kimi.parse_kimi_usage(payload)

        self.assertEqual(result["weekly"]["pct"], 100)
        self.assertEqual(result["five_h"]["pct"], 0)

    def test_parse_accepts_iso_reset_timestamp(self):
        payload = {
            "usage": {
                "limit": 100,
                "used": 1,
                "resetAt": "2026-06-11T13:00:00Z",
            },
            "limits": [{
                "window": {"duration": 300, "timeUnit": "MINUTE"},
                "detail": {"limit": 100, "used": 1, "reset_at": 20},
            }],
        }

        result = kimi.parse_kimi_usage(payload)

        self.assertEqual(result["weekly"]["resets_at"], 1781182800)

    def test_parse_rejects_missing_five_hour_window(self):
        payload = {
            "usage": {"limit": 100, "used": 1, "reset_at": 10},
            "limits": [],
        }
        with self.assertRaises(ValueError):
            kimi.parse_kimi_usage(payload)


class TestKimiHttp(unittest.TestCase):
    def test_access_token_is_not_exposed_in_process_arguments(self):
        completed = mock.Mock(
            stdout='{"usage":{},"limits":[]}\n__HTTP__200',
        )
        with mock.patch.object(kimi, "_proxy", return_value=None), \
             mock.patch.object(kimi.subprocess, "run", return_value=completed) as run:
            kimi._http_get_usage("secret-token")

        args = run.call_args.args[0]
        self.assertNotIn("secret-token", " ".join(args))
        self.assertIn("Authorization: Bearer secret-token", run.call_args.kwargs["input"])

    def test_http_rejects_newlines_in_token(self):
        with self.assertRaises(ValueError):
            kimi._http_get_usage("bad\ntoken")


class TestKimiFetch(unittest.TestCase):
    def test_fetch_returns_no_data_without_credentials(self):
        with mock.patch.object(kimi, "read_credentials", return_value=None):
            self.assertEqual(kimi.fetch_kimi(), {"ok": False, "reason": "no_data"})

    def test_fetch_returns_expired_for_expired_credentials(self):
        creds = {"access_token": "abc", "expires_at": 1000}
        with mock.patch.object(kimi, "read_credentials", return_value=creds), \
             mock.patch.object(kimi.time, "time", return_value=1000):
            self.assertEqual(kimi.fetch_kimi(), {"ok": False, "reason": "expired"})

    def test_fetch_returns_expired_for_rejected_credentials(self):
        creds = {"access_token": "abc", "expires_at": 2000}
        with mock.patch.object(kimi, "read_credentials", return_value=creds), \
             mock.patch.object(kimi.time, "time", return_value=1000), \
             mock.patch.object(kimi, "_http_get_usage", side_effect=kimi.KimiAuthError):
            self.assertEqual(kimi.fetch_kimi(), {"ok": False, "reason": "expired"})


if __name__ == "__main__":
    unittest.main()
