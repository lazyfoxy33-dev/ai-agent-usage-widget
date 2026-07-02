import json
import os
import tempfile
import unittest
from unittest import mock

from usage import deepseek


ROOT = os.path.dirname(__file__)


class TestParseDeepSeekBalance(unittest.TestCase):
    def test_cny_balance(self):
        payload = {
            "is_available": True,
            "balance_infos": [{
                "currency": "CNY",
                "total_balance": "110.00",
                "granted_balance": "10.00",
                "topped_up_balance": "100.00",
            }]
        }
        result = deepseek.parse_deepseek_balance(payload)
        self.assertTrue(result["ok"])
        self.assertEqual(result["kind"], "balance")
        self.assertEqual(result["balance"]["amount"], 110.0)
        self.assertEqual(result["balance"]["currency"], "CNY")
        self.assertTrue(result["balance"]["available"])
        self.assertEqual(result["balance"]["label"], "Balance")

    def test_usd_balance(self):
        payload = {
            "is_available": True,
            "balance_infos": [{
                "currency": "USD",
                "total_balance": 24.58,
            }]
        }
        result = deepseek.parse_deepseek_balance(payload)
        self.assertEqual(result["balance"]["amount"], 24.58)
        self.assertEqual(result["balance"]["currency"], "USD")

    def test_unavailable_balance(self):
        payload = {
            "is_available": False,
            "balance_infos": [{"currency": "CNY", "total_balance": "0.00"}]
        }
        result = deepseek.parse_deepseek_balance(payload)
        self.assertFalse(result["balance"]["available"])

    def test_numeric_string(self):
        payload = {
            "balance_infos": [{"currency": "CNY", "total_balance": " 88.8 "}]
        }
        result = deepseek.parse_deepseek_balance(payload)
        self.assertEqual(result["balance"]["amount"], 88.8)

    def test_missing_balance_infos(self):
        with self.assertRaises(ValueError):
            deepseek.parse_deepseek_balance({})

    def test_empty_balance_infos(self):
        with self.assertRaises(ValueError):
            deepseek.parse_deepseek_balance({"balance_infos": []})

    def test_malformed_payload(self):
        with self.assertRaises(ValueError):
            deepseek.parse_deepseek_balance({"balance_infos": [{}]})


class TestFetchDeepSeek(unittest.TestCase):
    def setUp(self):
        self.env = os.environ.get("DEEPSEEK_API_KEY")
        self.tmpdir = tempfile.mkdtemp()
        self.history_path = os.path.join(self.tmpdir, "deepseek-history.jsonl")

    def tearDown(self):
        if self.env is not None:
            os.environ["DEEPSEEK_API_KEY"] = self.env
        elif "DEEPSEEK_API_KEY" in os.environ:
            del os.environ["DEEPSEEK_API_KEY"]
        try:
            os.remove(self.history_path)
        except OSError:
            pass
        os.rmdir(self.tmpdir)

    def test_missing_api_key_returns_no_data(self):
        if "DEEPSEEK_API_KEY" in os.environ:
            del os.environ["DEEPSEEK_API_KEY"]
        result = deepseek.fetch_deepseek()
        self.assertEqual(result, {"ok": False, "kind": "balance", "reason": "no_data"})

    def test_auth_failure_maps_to_expired(self):
        os.environ["DEEPSEEK_API_KEY"] = "test-token"
        with mock.patch.object(deepseek.api_key_http, "bearer_get_json",
                               side_effect=deepseek.api_key_http.ApiAuthError("401")):
            result = deepseek.fetch_deepseek()
        self.assertEqual(result, {"ok": False, "kind": "balance", "reason": "expired"})

    def test_rate_limit_maps_to_rate_limited(self):
        os.environ["DEEPSEEK_API_KEY"] = "test-token"
        with mock.patch.object(deepseek.api_key_http, "bearer_get_json",
                               side_effect=deepseek.api_key_http.ApiRateLimitError("429")):
            result = deepseek.fetch_deepseek()
        self.assertEqual(result, {"ok": False, "kind": "balance", "reason": "rate_limited"})

    def test_generic_error_maps_to_error(self):
        os.environ["DEEPSEEK_API_KEY"] = "test-token"
        with mock.patch.object(deepseek.api_key_http, "bearer_get_json",
                               side_effect=RuntimeError("boom")):
            result = deepseek.fetch_deepseek()
        self.assertEqual(result, {"ok": False, "kind": "balance", "reason": "error"})

    def test_successful_fetch_records_history(self):
        os.environ["DEEPSEEK_API_KEY"] = "test-token"
        payload = {
            "is_available": True,
            "balance_infos": [{"currency": "USD", "total_balance": "80.00"}]
        }
        with mock.patch.object(deepseek.api_key_http, "bearer_get_json", return_value=payload), \
             mock.patch.object(deepseek, "HISTORY_PATH", self.history_path):
            result = deepseek.fetch_deepseek(now=86400 * 8)

        self.assertTrue(result["ok"])
        self.assertEqual(result["balance"]["amount"], 80.0)
        self.assertEqual(result["burn_rate"]["confidence"], "none")

        # Second fetch with spend yields an estimate.
        payload["balance_infos"][0]["total_balance"] = "40.00"
        with mock.patch.object(deepseek.api_key_http, "bearer_get_json", return_value=payload), \
             mock.patch.object(deepseek, "HISTORY_PATH", self.history_path):
            result = deepseek.fetch_deepseek(now=86400 * 16)

        self.assertEqual(result["burn_rate"]["confidence"], "high")
        self.assertEqual(result["burn_rate"]["estimated_days_left"], 8)

    def test_fixture_loads(self):
        path = os.path.join(ROOT, "fixtures", "deepseek_balance.json")
        with open(path) as f:
            payload = json.load(f)
        result = deepseek.parse_deepseek_balance(payload)
        self.assertEqual(result["balance"]["amount"], 110.0)
        self.assertEqual(result["balance"]["currency"], "CNY")
