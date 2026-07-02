import json
import os
import tempfile
import time
import unittest

from usage import balance_history


class TestBalanceHistory(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.path = os.path.join(self.tmpdir, "history.jsonl")

    def tearDown(self):
        try:
            os.remove(self.path)
        except OSError:
            pass
        os.rmdir(self.tmpdir)

    def _write(self, records):
        with open(self.path, "w") as f:
            for r in records:
                f.write(json.dumps(r, separators=(",", ":")) + "\n")

    def _read(self):
        with open(self.path) as f:
            return [json.loads(line) for line in f]

    def test_insufficient_history(self):
        result = balance_history.estimate([], 10.0, "USD", 1000)
        self.assertEqual(result, {"confidence": "none", "reason": "insufficient_history"})

    def test_no_recent_spend(self):
        history = [{"ts": 0, "amount": 10.0, "currency": "USD"}]
        result = balance_history.estimate(history, 10.0, "USD", 86400 * 8)
        self.assertEqual(result["confidence"], "none")
        self.assertEqual(result["reason"], "no_recent_spend")

    def test_balance_increased(self):
        history = [{"ts": 0, "amount": 5.0, "currency": "USD"}]
        result = balance_history.estimate(history, 10.0, "USD", 86400 * 8)
        self.assertEqual(result["confidence"], "none")
        self.assertEqual(result["reason"], "balance_increased")

    def test_ignores_different_currency(self):
        history = [
            {"ts": 0, "amount": 100.0, "currency": "CNY"},
            {"ts": 0, "amount": 10.0, "currency": "USD"},
        ]
        result = balance_history.estimate(history, 5.0, "USD", 86400 * 8)
        self.assertEqual(result["confidence"], "high")
        self.assertEqual(result["window_days"], 8)
        self.assertEqual(result["estimated_days_left"], 8)

    def test_seven_day_high_confidence(self):
        history = [{"ts": 0, "amount": 100.0, "currency": "USD"}]
        result = balance_history.estimate(history, 50.0, "USD", 86400 * 7)
        self.assertEqual(result["confidence"], "high")
        self.assertAlmostEqual(result["amount_per_day"], 50.0 / 7)
        self.assertEqual(result["window_days"], 7)
        self.assertEqual(result["estimated_days_left"], 7)

    def test_twenty_four_hour_medium_confidence(self):
        history = [
            {"ts": 0, "amount": 100.0, "currency": "USD"},
            {"ts": 3600, "amount": 95.0, "currency": "USD"},
            {"ts": 7200, "amount": 90.0, "currency": "USD"},
        ]
        result = balance_history.estimate(history, 80.0, "USD", 86400 * 2)
        # Newest point at least 24h old is ts=7200 (~1.9 days old).
        self.assertEqual(result["confidence"], "medium")
        self.assertEqual(result["window_days"], 1)
        self.assertEqual(result["estimated_days_left"], 15)

    def test_twenty_four_hour_low_confidence_with_few_points(self):
        history = [{"ts": 0, "amount": 100.0, "currency": "USD"}]
        result = balance_history.estimate(history, 80.0, "USD", 86400 * 2)
        self.assertEqual(result["confidence"], "low")
        self.assertEqual(result["window_days"], 2)
        self.assertEqual(result["estimated_days_left"], 8)

    def test_prefers_seven_day_point(self):
        now = 86400 * 10
        history = [
            {"ts": now - 86400 * 9, "amount": 200.0, "currency": "USD"},
            {"ts": now - 86400 * 2, "amount": 120.0, "currency": "USD"},
            {"ts": now - 86400 * 1, "amount": 110.0, "currency": "USD"},
        ]
        result = balance_history.estimate(history, 100.0, "USD", now)
        # The 9-day-old point is the newest one >= 7 days old.
        self.assertEqual(result["window_days"], 9)
        self.assertEqual(result["estimated_days_left"], 9)

    def test_falls_back_to_one_day_point(self):
        now = 86400 * 3
        history = [
            {"ts": now - 86400 * 2, "amount": 120.0, "currency": "USD"},
            {"ts": now - 86400 * 1, "amount": 110.0, "currency": "USD"},
            {"ts": now - 3600, "amount": 105.0, "currency": "USD"},
        ]
        result = balance_history.estimate(history, 100.0, "USD", now)
        # No point >= 7 days old; newest >= 1 day old is the 1-day-old point.
        self.assertEqual(result["window_days"], 1)
        self.assertEqual(result["estimated_days_left"], 10)

    def test_record_appends_and_estimates(self):
        result = balance_history.record_and_estimate(self.path, 100.0, "USD", now=0)
        self.assertEqual(result["confidence"], "none")
        self.assertEqual(result["reason"], "insufficient_history")

        result = balance_history.record_and_estimate(self.path, 50.0, "USD", now=86400 * 8)
        self.assertEqual(result["confidence"], "high")
        self.assertEqual(result["estimated_days_left"], 8)

        records = self._read()
        self.assertEqual(len(records), 2)
        self.assertEqual(records[-1], {"ts": 86400 * 8, "amount": 50.0, "currency": "USD"})

    def test_prunes_old_records(self):
        old = [{"ts": i, "amount": float(i), "currency": "USD"} for i in range(10)]
        # One record older than 45 days
        old[0]["ts"] = -86400 * 50
        self._write(old)
        balance_history.record_and_estimate(self.path, 100.0, "USD", now=86400 * 10)
        records = self._read()
        self.assertEqual(len(records), 10)
        self.assertTrue(all(r["ts"] >= 0 for r in records))

    def test_caps_at_500_records(self):
        many = [{"ts": i * 60, "amount": float(i), "currency": "USD"} for i in range(510)]
        self._write(many)
        balance_history.record_and_estimate(self.path, 100.0, "USD", now=510 * 60)
        records = self._read()
        self.assertEqual(len(records), 500)

    def test_ignores_malformed_lines(self):
        with open(self.path, "w") as f:
            f.write('{"ts":0,"amount":10,"currency":"USD"}\n')
            f.write("not json\n")
            f.write('{"incomplete": true}\n')
        result = balance_history.record_and_estimate(self.path, 5.0, "USD", now=86400 * 8)
        self.assertEqual(result["confidence"], "high")
