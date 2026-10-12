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

    def test_short_span_has_no_estimate(self):
        # Two samples five minutes apart cannot establish a daily burn rate.
        now = 86400 * 2
        history = [{"ts": now - 300, "amount": 100.0, "currency": "USD"}]
        result = balance_history.estimate(history, 99.0, "USD", now)
        self.assertEqual(result["confidence"], "none")
        self.assertEqual(result["reason"], "insufficient_history")

    def test_history_outside_the_window_has_no_estimate(self):
        # Everything is older than the trailing window: nothing describes today.
        now = 86400 * 8
        history = [{"ts": 0, "amount": 100.0, "currency": "USD"}]
        result = balance_history.estimate(history, 50.0, "USD", now)
        self.assertEqual(result["confidence"], "none")
        self.assertEqual(result["reason"], "insufficient_history")

    def test_no_recent_spend(self):
        now = 86400 * 2
        history = [{"ts": now - 86400, "amount": 10.0, "currency": "USD"}]
        result = balance_history.estimate(history, 10.0, "USD", now)
        self.assertEqual(result["confidence"], "none")
        self.assertEqual(result["reason"], "no_recent_spend")

    def test_balance_increased(self):
        now = 86400 * 2
        history = [{"ts": now - 86400, "amount": 5.0, "currency": "USD"}]
        result = balance_history.estimate(history, 10.0, "USD", now)
        self.assertEqual(result["confidence"], "none")
        self.assertEqual(result["reason"], "balance_increased")

    def test_ignores_different_currency(self):
        now = 86400 * 2
        history = [
            {"ts": now - 86400, "amount": 100.0, "currency": "CNY"},
            {"ts": now - 86400, "amount": 10.0, "currency": "USD"},
        ]
        result = balance_history.estimate(history, 5.0, "USD", now)
        self.assertEqual(result["confidence"], "medium")
        self.assertEqual(result["window_days"], 1)
        self.assertEqual(result["estimated_days_left"], 1)

    def test_full_day_of_samples_is_medium_confidence(self):
        now = 86400 * 3
        history = [
            {"ts": now - 86400, "amount": 100.0, "currency": "USD"},
            {"ts": now - 3600, "amount": 95.0, "currency": "USD"},
        ]
        result = balance_history.estimate(history, 90.0, "USD", now)
        # The point is the oldest sample inside the window (a day ago).
        self.assertEqual(result["confidence"], "medium")
        self.assertEqual(result["window_days"], 1)
        self.assertAlmostEqual(result["amount_per_day"], 10.0)
        self.assertEqual(result["estimated_days_left"], 9)

    def test_short_window_is_low_confidence(self):
        now = 86400 * 10
        history = [{"ts": now - 7 * 3600, "amount": 110.0, "currency": "USD"}]
        result = balance_history.estimate(history, 103.0, "USD", now)
        self.assertEqual(result["confidence"], "low")
        self.assertEqual(result["window_days"], 0)
        self.assertAlmostEqual(result["amount_per_day"], 24.0)
        self.assertEqual(result["estimated_days_left"], 4)

    def test_week_old_samples_are_ignored(self):
        # A nine-day-old balance must not dilute today's pace.
        now = 86400 * 10
        history = [
            {"ts": now - 86400 * 9, "amount": 200.0, "currency": "USD"},
            {"ts": now - 7 * 3600, "amount": 110.0, "currency": "USD"},
        ]
        result = balance_history.estimate(history, 103.0, "USD", now)
        # 7 spent in 7 hours = 24/day; the nine-day-old point would have said 11/day.
        self.assertAlmostEqual(result["amount_per_day"], 24.0)
        self.assertEqual(result["window_days"], 0)

    def test_window_caps_at_a_day(self):
        # Two days of samples: only the last day is used.
        now = 86400 * 10
        history = [
            {"ts": now - 86400 * 2, "amount": 500.0, "currency": "USD"},
            {"ts": now - 86400, "amount": 100.0, "currency": "USD"},
        ]
        result = balance_history.estimate(history, 90.0, "USD", now)
        self.assertAlmostEqual(result["amount_per_day"], 10.0)
        self.assertEqual(result["window_days"], 1)
        self.assertEqual(result["confidence"], "medium")

    def test_record_appends_and_estimates(self):
        result = balance_history.record_and_estimate(self.path, 100.0, "USD", now=0)
        self.assertEqual(result["confidence"], "none")
        self.assertEqual(result["reason"], "insufficient_history")

        result = balance_history.record_and_estimate(self.path, 90.0, "USD", now=7 * 3600)
        self.assertEqual(result["confidence"], "low")
        self.assertEqual(result["estimated_days_left"], 2)

        records = self._read()
        self.assertEqual(len(records), 2)
        self.assertEqual(records[-1], {"ts": 7 * 3600, "amount": 90.0, "currency": "USD"})

    def test_prunes_old_records(self):
        now = 86400 * 10
        records = [{"ts": now - i * 3600, "amount": float(i), "currency": "USD"} for i in range(1, 10)]
        records.append({"ts": now - 86400 * 8, "amount": 1.0, "currency": "USD"})
        self._write(records)
        balance_history.record_and_estimate(self.path, 100.0, "USD", now=now)
        kept = self._read()
        # The nine recent samples plus the new one; the eight-day-old record is gone.
        self.assertEqual(len(kept), 10)
        self.assertTrue(all(r["ts"] >= now - 86400 * 7 for r in kept))

    def test_caps_at_500_records(self):
        many = [{"ts": i * 60, "amount": float(i), "currency": "USD"} for i in range(510)]
        self._write(many)
        balance_history.record_and_estimate(self.path, 100.0, "USD", now=510 * 60)
        records = self._read()
        self.assertEqual(len(records), 500)

    def test_ignores_malformed_lines(self):
        now = 86400 * 8
        with open(self.path, "w") as f:
            f.write(json.dumps({"ts": now - 86400, "amount": 10.0, "currency": "USD"}) + "\n")
            f.write("not json\n")
            f.write('{"incomplete": true}\n')
        result = balance_history.record_and_estimate(self.path, 5.0, "USD", now=now)
        self.assertEqual(result["confidence"], "medium")
