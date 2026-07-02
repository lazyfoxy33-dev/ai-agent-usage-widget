import json
import os
import tempfile
import unittest
from unittest import mock

from usage import openrouter


ROOT = os.path.dirname(__file__)


class TestParseOpenRouterCredits(unittest.TestCase):
    def test_balance_from_credits(self):
        payload = {"data": {"total_credits": 100.0, "total_usage": 24.58}}
        result = openrouter.parse_openrouter_credits(payload)
        self.assertEqual(result["amount"], 75.42)
        self.assertEqual(result["currency"], "USD")

    def test_numeric_strings(self):
        payload = {"data": {"total_credits": "100.00", "total_usage": "24.58"}}
        result = openrouter.parse_openrouter_credits(payload)
        self.assertAlmostEqual(result["amount"], 75.42)

    def test_missing_fields(self):
        with self.assertRaises(ValueError):
            openrouter.parse_openrouter_credits({"data": {}})


class TestParseOpenRouterKey(unittest.TestCase):
    def test_usage_fields(self):
        payload = {
            "data": {
                "limit": 100.0,
                "limit_remaining": 75.42,
                "usage": 24.58,
                "usage_daily": 3.2,
                "usage_weekly": 15.0,
                "usage_monthly": 50.0,
                "is_free_tier": False,
            }
        }
        result = openrouter.parse_openrouter_key(payload)
        self.assertEqual(result["limit"], 100.0)
        self.assertEqual(result["limit_remaining"], 75.42)
        self.assertEqual(result["usage"], 24.58)
        self.assertEqual(result["usage_daily"], 3.2)
        self.assertEqual(result["usage_weekly"], 15.0)
        self.assertEqual(result["usage_monthly"], 50.0)
        self.assertFalse(result["is_free_tier"])

    def test_invalid_payload(self):
        self.assertIsNone(openrouter.parse_openrouter_key({}))
        self.assertIsNone(openrouter.parse_openrouter_key({"data": "bad"}))


class TestEstimateFromKeyUsage(unittest.TestCase):
    def test_daily_usage(self):
        key = {"usage_daily": 3.2}
        result = openrouter.estimate_from_key_usage(key, 88.88)
        self.assertEqual(result["amount_per_day"], 3.2)
        self.assertEqual(result["window_days"], 1)
        self.assertEqual(result["confidence"], "high")
        self.assertEqual(result["estimated_days_left"], 27)

    def test_weekly_fallback(self):
        key = {"usage_weekly": 21.0}
        result = openrouter.estimate_from_key_usage(key, 30.0)
        self.assertEqual(result["amount_per_day"], 3.0)
        self.assertEqual(result["window_days"], 7)
        self.assertEqual(result["confidence"], "medium")
        self.assertEqual(result["estimated_days_left"], 10)

    def test_monthly_fallback(self):
        key = {"usage_monthly": 30.0}
        result = openrouter.estimate_from_key_usage(key, 30.0)
        self.assertEqual(result["amount_per_day"], 1.0)
        self.assertEqual(result["window_days"], 30)
        self.assertEqual(result["confidence"], "low")
        self.assertEqual(result["estimated_days_left"], 30)

    def test_zero_usage(self):
        key = {"usage_daily": 0.0}
        result = openrouter.estimate_from_key_usage(key, 100.0)
        self.assertEqual(result["confidence"], "none")
        self.assertEqual(result["reason"], "no_recent_spend")

    def test_no_usage_fields(self):
        self.assertIsNone(openrouter.estimate_from_key_usage({"limit": 100}, 100.0))


class TestFetchOpenRouter(unittest.TestCase):
    def setUp(self):
        self.env = os.environ.get("OPENROUTER_API_KEY")
        self.tmpdir = tempfile.mkdtemp()
        self.history_path = os.path.join(self.tmpdir, "openrouter-history.jsonl")

    def tearDown(self):
        if self.env is not None:
            os.environ["OPENROUTER_API_KEY"] = self.env
        elif "OPENROUTER_API_KEY" in os.environ:
            del os.environ["OPENROUTER_API_KEY"]
        try:
            os.remove(self.history_path)
        except OSError:
            pass
        os.rmdir(self.tmpdir)

    def test_missing_api_key_returns_no_data(self):
        if "OPENROUTER_API_KEY" in os.environ:
            del os.environ["OPENROUTER_API_KEY"]
        result = openrouter.fetch_openrouter()
        self.assertEqual(result, {"ok": False, "kind": "balance", "reason": "no_data"})

    def test_auth_failure_maps_to_expired(self):
        os.environ["OPENROUTER_API_KEY"] = "test-token"
        with mock.patch.object(openrouter.api_key_http, "bearer_get_json",
                               side_effect=openrouter.api_key_http.ApiAuthError("403")):
            result = openrouter.fetch_openrouter()
        self.assertEqual(result, {"ok": False, "kind": "balance", "reason": "expired"})

    def test_rate_limit_maps_to_rate_limited(self):
        os.environ["OPENROUTER_API_KEY"] = "test-token"
        with mock.patch.object(openrouter.api_key_http, "bearer_get_json",
                               side_effect=openrouter.api_key_http.ApiRateLimitError("429")):
            result = openrouter.fetch_openrouter()
        self.assertEqual(result, {"ok": False, "kind": "balance", "reason": "rate_limited"})

    def test_generic_error_maps_to_error(self):
        os.environ["OPENROUTER_API_KEY"] = "test-token"
        with mock.patch.object(openrouter.api_key_http, "bearer_get_json",
                               side_effect=RuntimeError("boom")):
            result = openrouter.fetch_openrouter()
        self.assertEqual(result, {"ok": False, "kind": "balance", "reason": "error"})

    def test_credits_success_with_key_fallback(self):
        os.environ["OPENROUTER_API_KEY"] = "test-token"
        credits = {"data": {"total_credits": 100.0, "total_usage": 20.0}}
        key = {"data": {"usage_daily": 4.0}}

        def fake_get(url, token):
            if url == openrouter.CREDITS_URL:
                return credits
            if url == openrouter.KEY_URL:
                return key
            raise ValueError("unexpected url")

        with mock.patch.object(openrouter.api_key_http, "bearer_get_json", side_effect=fake_get):
            result = openrouter.fetch_openrouter()

        self.assertTrue(result["ok"])
        self.assertEqual(result["balance"]["amount"], 80.0)
        self.assertEqual(result["balance"]["currency"], "USD")
        self.assertEqual(result["burn_rate"]["amount_per_day"], 4.0)
        self.assertEqual(result["burn_rate"]["estimated_days_left"], 20)

    def test_key_failure_falls_back_to_history(self):
        os.environ["OPENROUTER_API_KEY"] = "test-token"
        credits = {"data": {"total_credits": 80.0, "total_usage": 0.0}}

        def fake_get(url, token):
            if url == openrouter.CREDITS_URL:
                return credits
            if url == openrouter.KEY_URL:
                raise RuntimeError("key endpoint failed")
            raise ValueError("unexpected url")

        with mock.patch.object(openrouter.api_key_http, "bearer_get_json", side_effect=fake_get), \
             mock.patch.object(openrouter, "HISTORY_PATH", self.history_path):
            result = openrouter.fetch_openrouter(now=86400 * 8)

        self.assertTrue(result["ok"])
        self.assertEqual(result["burn_rate"]["confidence"], "none")

        credits["data"]["total_usage"] = 40.0
        with mock.patch.object(openrouter.api_key_http, "bearer_get_json", side_effect=fake_get), \
             mock.patch.object(openrouter, "HISTORY_PATH", self.history_path):
            result = openrouter.fetch_openrouter(now=86400 * 16)

        self.assertEqual(result["burn_rate"]["confidence"], "high")

    def test_fixtures_load(self):
        with open(os.path.join(ROOT, "fixtures", "openrouter_credits.json")) as f:
            credits = json.load(f)
        with open(os.path.join(ROOT, "fixtures", "openrouter_key.json")) as f:
            key = json.load(f)
        balance = openrouter.parse_openrouter_credits(credits)
        self.assertAlmostEqual(balance["amount"], 75.42)
        key_data = openrouter.parse_openrouter_key(key)
        self.assertEqual(key_data["usage_daily"], 3.2)
