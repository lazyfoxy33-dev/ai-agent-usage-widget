import os
import json as _json
import unittest
from contextlib import contextmanager
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
        result = claude.parse_claude_usage(self._fixture(), now=1800000000)
        self.assertEqual(result["five_h"]["pct"], 49)
        self.assertEqual(result["weekly"]["pct"], 5)
        expected_five_h_ts = int(datetime.fromisoformat("2026-06-11T12:09:59.599553+00:00").timestamp())
        self.assertEqual(result["five_h"]["resets_at"], expected_five_h_ts)
        # resets_at is in the past vs now=1800000000, so stale should be True
        self.assertTrue(result["five_h"]["stale"])
        self.assertTrue(result["weekly"]["stale"])

    def test_parse_accepts_0_to_100_scale(self):
        data = {"five_hour": {"utilization": 43, "resets_at": 1},
                "seven_day": {"utilization": 61, "resets_at": 2}}
        result = claude.parse_claude_usage(data, now=3)
        self.assertEqual(result["five_h"]["pct"], 43)
        self.assertTrue(result["five_h"]["stale"])  # resets_at=1 < now=3
        self.assertTrue(result["weekly"]["stale"])  # resets_at=2 < now=3

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
    def test_credential_read_is_delegated_to_platform_store(self):
        blob = '{"claudeAiOauth":{"accessToken":"token"}}'
        with mock.patch(
            "usage.credential_store.read_claude_blob", return_value=blob
        ) as read:
            self.assertEqual(claude.read_keychain_blob(), blob)
        read.assert_called_once_with()

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

    def test_valid_token_is_used_without_refreshing(self):
        creds = {"accessToken": "token", "expiresAt": 5_000_000}
        with mock.patch.object(claude, "read_keychain_blob",
                               return_value='{"claudeAiOauth":{}}'), \
             mock.patch.object(claude, "parse_creds", return_value=creds), \
             mock.patch.object(claude.time, "time", return_value=1000), \
             mock.patch.object(claude, "_refresh_creds") as refresh, \
             mock.patch.object(claude, "_http_get_usage", return_value={"ok": True}), \
             mock.patch.object(claude, "parse_claude_usage", return_value={"ok": True}):
            self.assertEqual(claude.fetch_claude(), {"ok": True})
        refresh.assert_not_called()

    def test_expired_token_is_refreshed_persisted_then_used(self):
        old = {"accessToken": "old", "refreshToken": "r", "expiresAt": 1_000_000}
        fresh = {"accessToken": "new", "refreshToken": "r2", "expiresAt": 9_000_000}
        with mock.patch.object(claude, "read_keychain_blob",
                               return_value='{"claudeAiOauth":{}}'), \
             mock.patch.object(claude, "parse_creds", return_value=old), \
             mock.patch.object(claude.time, "time", return_value=2000), \
             mock.patch.object(claude, "_refresh_creds", return_value=fresh) as refresh, \
             mock.patch.object(claude, "_http_get_usage", return_value={}) as get, \
             mock.patch.object(claude, "parse_claude_usage", return_value={"ok": True}):
            self.assertEqual(claude.fetch_claude(), {"ok": True})
        refresh.assert_called_once()
        self.assertEqual(get.call_args.args[0], "new")

    def test_refresh_unauthorized_maps_to_expired(self):
        old = {"accessToken": "old", "refreshToken": "r", "expiresAt": 1_000_000}
        with mock.patch.object(claude, "read_keychain_blob",
                               return_value='{"claudeAiOauth":{}}'), \
             mock.patch.object(claude, "parse_creds", return_value=old), \
             mock.patch.object(claude.time, "time", return_value=2000), \
             mock.patch.object(claude, "_refresh_creds",
                               side_effect=claude.ClaudeRefreshUnauthorized):
            self.assertEqual(
                claude.fetch_claude(), {"ok": False, "reason": "expired"}
            )


class TestClaudeRefresh(unittest.TestCase):
    @contextmanager
    def _unlocked(self, timeout=60):
        yield

    def test_refresh_short_circuits_when_peer_already_rotated(self):
        initial = {"accessToken": "old", "refreshToken": "old-r", "expiresAt": 1_000_000}
        peer = {"accessToken": "peer", "refreshToken": "peer-r", "expiresAt": 9_000_000}
        with mock.patch.object(claude, "_refresh_lock", self._unlocked), \
             mock.patch.object(claude, "read_keychain_blob",
                               return_value='{"claudeAiOauth":{}}'), \
             mock.patch.object(claude, "parse_creds", return_value=peer), \
             mock.patch.object(claude, "_http_refresh") as refresh, \
             mock.patch.object(claude.credential_store, "write_claude_blob") as write:
            result = claude._refresh_creds(initial, now=2000)

        self.assertEqual(result, peer)
        refresh.assert_not_called()
        write.assert_not_called()

    def test_refresh_persists_only_token_fields_and_keeps_others(self):
        initial = {
            "accessToken": "old", "refreshToken": "old-r",
            "expiresAt": 1_000_000, "subscriptionType": "max",
        }
        token_response = {
            "access_token": "new", "refresh_token": "new-r", "expires_in": 28800,
        }
        with mock.patch.object(claude, "_refresh_lock", self._unlocked), \
             mock.patch.object(claude, "read_keychain_blob", return_value=None), \
             mock.patch.object(claude, "_refresh_throttled", return_value=False), \
             mock.patch.object(claude, "_mark_refresh_attempt"), \
             mock.patch.object(claude, "_http_refresh",
                               return_value=token_response), \
             mock.patch.object(claude.credential_store, "write_claude_blob") as write:
            result = claude._refresh_creds(initial, now=2000)

        self.assertEqual(result["accessToken"], "new")
        self.assertEqual(result["refreshToken"], "new-r")
        self.assertEqual(result["expiresAt"], int((2000 + 28800) * 1000))
        self.assertEqual(result["subscriptionType"], "max")  # preserved
        written = _json.loads(write.call_args.args[0])
        self.assertEqual(written["claudeAiOauth"]["accessToken"], "new")
        self.assertEqual(written["claudeAiOauth"]["subscriptionType"], "max")

    def test_refresh_token_is_sent_in_stdin_not_process_arguments(self):
        completed = mock.Mock(
            stdout=(
                '{"access_token":"new","refresh_token":"new-r",'
                '"expires_in":28800}\n__HTTP__200'
            ),
        )
        with mock.patch.object(claude, "_proxy", return_value=None), \
             mock.patch.object(claude.subprocess, "run", return_value=completed) as run:
            result = claude._http_refresh("secret-refresh")

        argv = run.call_args.args[0]
        self.assertNotIn("secret-refresh", " ".join(argv))
        self.assertIn("refresh_token=secret-refresh", run.call_args.kwargs["input"])
        self.assertEqual(result["access_token"], "new")

    def test_http_refresh_invalid_grant_raises_unauthorized(self):
        completed = mock.Mock(stdout='{"error":"invalid_grant"}\n__HTTP__400')
        with mock.patch.object(claude, "_proxy", return_value=None), \
             mock.patch.object(claude.subprocess, "run", return_value=completed):
            with self.assertRaises(claude.ClaudeRefreshUnauthorized):
                claude._http_refresh("dead-token")

    def test_recent_attempt_backs_off_without_calling_network(self):
        initial = {"accessToken": "old", "refreshToken": "r", "expiresAt": 1_000_000}
        with mock.patch.object(claude, "_refresh_lock", self._unlocked), \
             mock.patch.object(claude, "read_keychain_blob", return_value=None), \
             mock.patch.object(claude, "_refresh_throttled", return_value=True), \
             mock.patch.object(claude, "_http_refresh") as refresh:
            with self.assertRaises(claude.ClaudeRefreshThrottled):
                claude._refresh_creds(initial, now=2000)
        refresh.assert_not_called()

    def test_throttled_refresh_surfaces_as_expired(self):
        old = {"accessToken": "old", "refreshToken": "r", "expiresAt": 1_000_000}
        with mock.patch.object(claude, "read_keychain_blob",
                               return_value='{"claudeAiOauth":{}}'), \
             mock.patch.object(claude, "parse_creds", return_value=old), \
             mock.patch.object(claude.time, "time", return_value=2000), \
             mock.patch.object(claude, "_refresh_creds",
                               side_effect=claude.ClaudeRefreshThrottled):
            self.assertEqual(
                claude.fetch_claude(), {"ok": False, "reason": "expired"}
            )
