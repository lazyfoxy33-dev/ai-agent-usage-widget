import os
import json as _json
import unittest
from datetime import datetime
from unittest import mock
from usage import claude


class TestClaudeAuth(unittest.TestCase):
    def test_expired_token_detected(self):
        creds = {"accessToken": "tok", "expiresAt": 1000 * 1000}  # ms
        self.assertTrue(claude.is_expired(creds, now=2000))  # now=2000s > 1000s

    def test_valid_token_not_expired(self):
        creds = {"accessToken": "tok", "expiresAt": 5000 * 1000}
        self.assertFalse(claude.is_expired(creds, now=2000))

    def test_token_from_creds_blob(self):
        blob = '{"claudeAiOauth":{"accessToken":"abc","expiresAt":5000000}}'
        creds = claude.parse_creds(blob)
        self.assertEqual(creds["accessToken"], "abc")
        self.assertEqual(creds["expiresAt"], 5000000)


class TestClaudeParse(unittest.TestCase):
    def _fixture(self):
        p = os.path.join(os.path.dirname(__file__), "fixtures", "claude_usage.json")
        with open(p) as f:
            return _json.load(f)

    def test_parse_five_h_and_weekly(self):
        result = claude.parse_claude_usage(self._fixture())
        self.assertEqual(result["five_h"]["pct"], 49)
        self.assertEqual(result["weekly"]["pct"], 5)
        expected_five_h_ts = int(datetime.fromisoformat("2026-06-11T12:09:59.599553+00:00").timestamp())
        self.assertEqual(result["five_h"]["resets_at"], expected_five_h_ts)

    def test_parse_accepts_0_to_100_scale(self):
        data = {"five_hour": {"utilization": 43, "resets_at": 1},
                "seven_day": {"utilization": 61, "resets_at": 2}}
        result = claude.parse_claude_usage(data)
        self.assertEqual(result["five_h"]["pct"], 43)

    def test_parse_resets_iso_string(self):
        iso = "2026-06-11T12:09:59.599553+00:00"
        expected = int(datetime.fromisoformat(iso).timestamp())
        self.assertEqual(claude._parse_resets(iso), expected)

    def test_parse_resets_numeric(self):
        self.assertEqual(claude._parse_resets(1780670000), 1780670000)
        self.assertEqual(claude._parse_resets(1780670000.7), 1780670000)

    def test_parse_resets_z_suffix(self):
        iso_z = "2026-06-11T12:09:59.599553Z"
        iso_plus = "2026-06-11T12:09:59.599553+00:00"
        self.assertEqual(claude._parse_resets(iso_z), claude._parse_resets(iso_plus))


class TestClaudeProxy(unittest.TestCase):
    def test_proxy_returns_env_https_proxy(self):
        with mock.patch.dict(os.environ, {"HTTPS_PROXY": "http://myproxy:8080"}, clear=False):
            result = claude._proxy()
        self.assertEqual(result, "http://myproxy:8080")

    def test_proxy_returns_env_https_proxy_lowercase(self):
        # Remove uppercase variant so only lowercase is seen
        env = {k: v for k, v in os.environ.items() if k != "HTTPS_PROXY"}
        env["https_proxy"] = "http://lowerproxy:9090"
        with mock.patch.dict(os.environ, env, clear=True):
            result = claude._proxy()
        self.assertEqual(result, "http://lowerproxy:9090")

    def test_proxy_returns_none_when_no_env_and_no_open_port(self):
        # Patch socket.create_connection to always refuse (simulate no proxy)
        import socket
        env = {k: v for k, v in os.environ.items()
               if k not in ("HTTPS_PROXY", "https_proxy")}
        with mock.patch.dict(os.environ, env, clear=True), \
             mock.patch("socket.create_connection", side_effect=OSError("refused")):
            result = claude._proxy()
        self.assertIsNone(result)


class TestClaudeHttp(unittest.TestCase):
    def test_access_token_is_not_exposed_in_process_arguments(self):
        token = "secret-access-token"
        completed = mock.Mock(stdout='{"ok":true}\n__HTTP__200')
        with mock.patch.object(claude, "_proxy", return_value=None), \
             mock.patch.object(claude.subprocess, "run", return_value=completed) as run:
            result = claude._http_get_usage(token)

        cmd = run.call_args.args[0]
        self.assertNotIn(token, " ".join(cmd))
        self.assertEqual(cmd[:4], ["curl", "-q", "--config", "-"])
        self.assertIn("Authorization: Bearer " + token, run.call_args.kwargs["input"])
        self.assertEqual(result, {"ok": True})

    def test_http_429_raises_rate_limit_error(self):
        completed = mock.Mock(stdout='{"error":"limited"}\n__HTTP__429')
        with mock.patch.object(claude, "_proxy", return_value=None), \
             mock.patch.object(claude.subprocess, "run", return_value=completed):
            with self.assertRaises(claude.ClaudeRateLimitError):
                claude._http_get_usage("token")


class TestClaudeFetch(unittest.TestCase):
    def test_fetch_maps_rate_limit_separately(self):
        creds = {"accessToken": "token", "expiresAt": 2_000_000}
        with mock.patch.object(claude, "read_keychain_blob",
                               return_value='{"claudeAiOauth":{}}'), \
             mock.patch.object(claude, "parse_creds", return_value=creds), \
             mock.patch.object(claude.time, "time", return_value=1000), \
             mock.patch.object(claude, "_http_get_usage",
                               side_effect=claude.ClaudeRateLimitError):
            self.assertEqual(
                claude.fetch_claude(),
                {"ok": False, "reason": "rate_limited"},
            )
