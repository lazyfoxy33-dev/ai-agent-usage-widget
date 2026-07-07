import json
import os
import tempfile
import unittest
from unittest import mock

from usage import siliconflow


ROOT = os.path.dirname(__file__)


class TestParseSiliconFlowInfo(unittest.TestCase):
    def test_total_balance(self):
        payload = {"data": {"totalBalance": "15.00", "status": "active"}}
        result = siliconflow.parse_siliconflow_info(payload)
        self.assertEqual(result["balance"]["amount"], 15.0)
        self.assertEqual(result["balance"]["currency"], "CNY")
        self.assertTrue(result["balance"]["available"])

    def test_balance_fallback(self):
        payload = {"data": {"balance": "12.50", "status": "active"}}
        result = siliconflow.parse_siliconflow_info(payload)
        self.assertEqual(result["balance"]["amount"], 12.5)

    def test_charge_balance_ignored_when_total_present(self):
        payload = {"data": {
            "balance": "10.00",
            "chargeBalance": "5.00",
            "totalBalance": "15.00",
            "status": "active"
        }}
        result = siliconflow.parse_siliconflow_info(payload)
        self.assertEqual(result["balance"]["amount"], 15.0)

    def test_status_inactive(self):
        payload = {"data": {"totalBalance": "5.00", "status": "inactive"}}
        result = siliconflow.parse_siliconflow_info(payload)
        self.assertFalse(result["balance"]["available"])

    def test_currency_override(self):
        payload = {"data": {"totalBalance": "1.00", "currency": "USD"}}
        result = siliconflow.parse_siliconflow_info(payload)
        self.assertEqual(result["balance"]["currency"], "USD")

    def test_numeric_value(self):
        payload = {"data": {"totalBalance": 99.99}}
        result = siliconflow.parse_siliconflow_info(payload)
        self.assertEqual(result["balance"]["amount"], 99.99)

    def test_missing_data(self):
        with self.assertRaises(ValueError):
            siliconflow.parse_siliconflow_info({})

    def test_missing_balance(self):
        with self.assertRaises(ValueError):
            siliconflow.parse_siliconflow_info({"data": {"status": "active"}})

    def test_negative_total_balance_is_not_displayable(self):
        payload = {"data": {"balance": "0", "chargeBalance": "-70.639", "totalBalance": "-70.639", "status": "normal"}}
        with self.assertRaises(siliconflow.BalanceUnavailableError):
            siliconflow.parse_siliconflow_info(payload)


class TestFetchSiliconFlow(unittest.TestCase):
    def setUp(self):
        self.env = os.environ.get("SILICONFLOW_API_KEY")
        self.tmpdir = tempfile.mkdtemp()
        self.history_path = os.path.join(self.tmpdir, "siliconflow-history.jsonl")

    def tearDown(self):
        if self.env is not None:
            os.environ["SILICONFLOW_API_KEY"] = self.env
        elif "SILICONFLOW_API_KEY" in os.environ:
            del os.environ["SILICONFLOW_API_KEY"]
        try:
            os.remove(self.history_path)
        except OSError:
            pass
        os.rmdir(self.tmpdir)

    def test_missing_api_key_returns_no_data(self):
        if "SILICONFLOW_API_KEY" in os.environ:
            del os.environ["SILICONFLOW_API_KEY"]
        result = siliconflow.fetch_siliconflow()
        self.assertEqual(result, {"ok": False, "kind": "balance", "reason": "no_data"})

    def test_auth_failure_maps_to_expired(self):
        os.environ["SILICONFLOW_API_KEY"] = "test-token"
        with mock.patch.object(siliconflow.api_key_http, "bearer_get_json",
                               side_effect=siliconflow.api_key_http.ApiAuthError("403")):
            result = siliconflow.fetch_siliconflow()
        self.assertEqual(result, {"ok": False, "kind": "balance", "reason": "expired"})

    def test_cn_endpoint_is_used_when_com_rejects_key(self):
        os.environ["SILICONFLOW_API_KEY"] = "test-token"
        payload = {"data": {"totalBalance": "66.00", "status": "normal"}}
        with mock.patch.object(
            siliconflow.api_key_http,
            "bearer_get_json",
            side_effect=[siliconflow.api_key_http.ApiAuthError("403"), payload],
        ) as request, mock.patch.object(siliconflow, "HISTORY_PATH", self.history_path):
            result = siliconflow.fetch_siliconflow(now=86400 * 8)

        self.assertTrue(result["ok"])
        self.assertEqual(result["balance"]["amount"], 66.0)
        self.assertEqual(request.call_args_list[0].args[0], "https://api.siliconflow.com/v1/user/info")
        self.assertEqual(request.call_args_list[1].args[0], "https://api.siliconflow.cn/v1/user/info")

    def test_rate_limit_maps_to_rate_limited(self):
        os.environ["SILICONFLOW_API_KEY"] = "test-token"
        with mock.patch.object(siliconflow.api_key_http, "bearer_get_json",
                               side_effect=siliconflow.api_key_http.ApiRateLimitError("429")):
            result = siliconflow.fetch_siliconflow()
        self.assertEqual(result, {"ok": False, "kind": "balance", "reason": "rate_limited"})

    def test_generic_error_maps_to_error(self):
        os.environ["SILICONFLOW_API_KEY"] = "test-token"
        with mock.patch.object(siliconflow.api_key_http, "bearer_get_json",
                               side_effect=RuntimeError("boom")):
            result = siliconflow.fetch_siliconflow()
        self.assertEqual(result, {"ok": False, "kind": "balance", "reason": "error"})

    def test_negative_api_balance_maps_to_unavailable(self):
        os.environ["SILICONFLOW_API_KEY"] = "test-token"
        payload = {"data": {"balance": "0", "chargeBalance": "-70.639", "totalBalance": "-70.639", "status": "normal"}}
        with mock.patch.object(siliconflow.api_key_http, "bearer_get_json", return_value=payload), \
             mock.patch.object(siliconflow, "HISTORY_PATH", self.history_path):
            result = siliconflow.fetch_siliconflow()
        self.assertEqual(result, {"ok": False, "kind": "balance", "reason": "balance_unavailable"})

    def test_successful_fetch_records_history(self):
        os.environ["SILICONFLOW_API_KEY"] = "test-token"
        payload = {"data": {"totalBalance": "80.00", "status": "active"}}
        with mock.patch.object(siliconflow.api_key_http, "bearer_get_json", return_value=payload), \
             mock.patch.object(siliconflow, "HISTORY_PATH", self.history_path):
            result = siliconflow.fetch_siliconflow(now=86400 * 8)

        self.assertTrue(result["ok"])
        self.assertEqual(result["balance"]["amount"], 80.0)
        self.assertEqual(result["burn_rate"]["confidence"], "none")

        payload["data"]["totalBalance"] = "40.00"
        with mock.patch.object(siliconflow.api_key_http, "bearer_get_json", return_value=payload), \
             mock.patch.object(siliconflow, "HISTORY_PATH", self.history_path):
            result = siliconflow.fetch_siliconflow(now=86400 * 16)

        self.assertEqual(result["burn_rate"]["confidence"], "high")
        self.assertEqual(result["burn_rate"]["estimated_days_left"], 8)

    def test_fixture_loads(self):
        path = os.path.join(ROOT, "fixtures", "siliconflow_user_info.json")
        with open(path) as f:
            payload = json.load(f)
        result = siliconflow.parse_siliconflow_info(payload)
        self.assertEqual(result["balance"]["amount"], 15.0)
        self.assertEqual(result["balance"]["currency"], "CNY")
