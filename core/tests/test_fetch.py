import json
import unittest
from unittest import mock
import fetch_usage


class TestFetch(unittest.TestCase):
    def test_provider_success_cache_is_five_minutes(self):
        entry = {"ts": 1000, "data": {"ok": True}}
        with mock.patch.object(fetch_usage.cache, "read_entry", return_value=entry) as read:
            fetch_usage.claude_with_cache()
            read.assert_called_once_with(
                fetch_usage.CACHE_PATH,
                ttl=fetch_usage.CACHE_TTL,
            )

        self.assertEqual(fetch_usage.CACHE_TTL, 300)

    def test_combined_json_shape(self):
        codex_res = {"ok": True, "as_of": 1,
                     "five_h": {"pct": 7, "resets_at": 1},
                     "weekly": {"pct": 22, "resets_at": 2}}
        claude_res = {"ok": False, "reason": "expired"}
        kimi_res = {"ok": True, "five_h": {"pct": 34, "resets_at": 3},
                    "weekly": {"pct": 8, "resets_at": 4}}
        deepseek_res = {"ok": True, "kind": "balance",
                        "balance": {"amount": 110.0, "currency": "CNY",
                                    "available": True, "label": "Balance"},
                        "burn_rate": {"confidence": "none",
                                      "reason": "insufficient_history"}}
        siliconflow_res = {"ok": False, "kind": "balance", "reason": "no_data"}
        openrouter_res = {"ok": True, "kind": "balance",
                          "balance": {"amount": 75.42, "currency": "USD",
                                      "available": True, "label": "Balance"},
                          "burn_rate": {"amount_per_day": 3.2, "window_days": 1,
                                        "estimated_days_left": 23, "confidence": "high"}}
        with mock.patch.object(fetch_usage.time, "time", return_value=2000), \
             mock.patch.object(fetch_usage.cache, "read_entry", return_value=None), \
             mock.patch.object(fetch_usage.codex, "fetch_codex_live",
                               return_value={"ok": False, "reason": "error"}), \
             mock.patch.object(fetch_usage.codex, "parse_codex", return_value=codex_res), \
             mock.patch.object(fetch_usage, "claude_with_cache", return_value=claude_res), \
             mock.patch.object(fetch_usage, "kimi_with_cache", return_value=kimi_res), \
             mock.patch.object(fetch_usage, "deepseek_with_cache", return_value=deepseek_res), \
             mock.patch.object(fetch_usage, "siliconflow_with_cache", return_value=siliconflow_res), \
             mock.patch.object(fetch_usage, "openrouter_with_cache", return_value=openrouter_res):
            out = json.loads(fetch_usage.build_payload())
        self.assertEqual(out["schema_version"], 1)
        for name in ("claude", "codex", "kimi", "deepseek", "siliconflow", "openrouter"):
            self.assertIn(name, out)
            self.assertIn("fetched_at", out[name])
            self.assertIn("live", out[name])
        self.assertEqual(out["codex"]["five_h"]["pct"], 7)
        self.assertEqual(out["codex"]["fetched_at"], 2000)  # now, not as_of
        self.assertFalse(out["codex"]["live"])  # as_of=1, now=2000, diff=1999 > 1800
        self.assertEqual(out["claude"]["reason"], "expired")
        self.assertIsNone(out["claude"]["fetched_at"])
        self.assertFalse(out["claude"]["live"])
        self.assertEqual(out["kimi"]["weekly"]["pct"], 8)
        self.assertEqual(out["deepseek"]["kind"], "balance")
        self.assertEqual(out["deepseek"]["balance"]["currency"], "CNY")
        self.assertEqual(out["siliconflow"]["reason"], "no_data")
        self.assertEqual(out["openrouter"]["burn_rate"]["confidence"], "high")

    def test_balance_provider_success_is_written_to_separate_cache(self):
        result = {"ok": True, "kind": "balance",
                  "balance": {"amount": 10.0, "currency": "USD",
                              "available": True, "label": "Balance"},
                  "burn_rate": {"confidence": "none",
                                "reason": "insufficient_history"}}
        with mock.patch.object(fetch_usage.cache, "read_entry", return_value=None), \
             mock.patch.object(fetch_usage.openrouter, "fetch_openrouter",
                               return_value=result), \
             mock.patch.object(fetch_usage.cache, "write") as write, \
             mock.patch.object(fetch_usage.time, "time", return_value=1234):
            decorated = dict(result, fetched_at=1234, live=True)
            self.assertEqual(fetch_usage.openrouter_with_cache(), decorated)

        write.assert_called_once_with(fetch_usage.OPENROUTER_CACHE_PATH, decorated, now=1234)

    def test_balance_provider_transient_error_uses_stale_cache(self):
        stale = {"ok": True, "kind": "balance",
                 "balance": {"amount": 5.0, "currency": "USD",
                             "available": True, "label": "Balance"},
                 "burn_rate": {"confidence": "none",
                               "reason": "insufficient_history"}}
        stale_entry = {"ts": 1000, "data": stale}
        with mock.patch.object(fetch_usage.cache, "read_entry", return_value=None), \
             mock.patch.object(fetch_usage.deepseek, "fetch_deepseek",
                               return_value={"ok": False, "reason": "error"}), \
             mock.patch.object(fetch_usage.cache, "read_stale_entry",
                               return_value=stale_entry):
            result = fetch_usage.deepseek_with_cache()

        self.assertEqual(result["reason"], "stale")
        self.assertEqual(result["upstream_reason"], "error")
        self.assertEqual(result["fetched_at"], 1000)
        self.assertFalse(result["live"])
        self.assertEqual(result["balance"]["amount"], 5.0)

    def test_kimi_success_is_written_to_separate_cache(self):
        result = {"ok": True, "five_h": {"pct": 34, "resets_at": 3},
                  "weekly": {"pct": 8, "resets_at": 4}}
        with mock.patch.object(fetch_usage.cache, "read_entry", return_value=None), \
             mock.patch.object(fetch_usage.kimi, "fetch_kimi", return_value=result), \
             mock.patch.object(fetch_usage.cache, "write") as write, \
             mock.patch.object(fetch_usage.time, "time", return_value=1234):
            decorated = dict(result, fetched_at=1234, live=True)
            self.assertEqual(fetch_usage.kimi_with_cache(), decorated)

        write.assert_called_once_with(fetch_usage.KIMI_CACHE_PATH, decorated, now=1234)

    def test_kimi_transient_error_uses_stale_cache(self):
        stale = {"ok": True, "five_h": {"pct": 30, "resets_at": 3},
                 "weekly": {"pct": 7, "resets_at": 4}}
        stale_entry = {"ts": 1000, "data": stale}
        with mock.patch.object(fetch_usage.cache, "read_entry", return_value=None), \
             mock.patch.object(fetch_usage.kimi, "fetch_kimi",
                               return_value={"ok": False, "reason": "error"}), \
             mock.patch.object(fetch_usage.cache, "read_stale_entry",
                               return_value=stale_entry):
            result = fetch_usage.kimi_with_cache()

        self.assertEqual(result["reason"], "stale")
        self.assertEqual(result["upstream_reason"], "error")
        self.assertEqual(result["fetched_at"], 1000)
        self.assertFalse(result["live"])
        self.assertEqual(result["weekly"]["pct"], 7)

    def test_kimi_expired_uses_honestly_marked_stale_cache(self):
        expired = {"ok": False, "reason": "expired"}
        stale = {"ok": True, "five_h": {"pct": 30, "resets_at": 3},
                 "weekly": {"pct": 7, "resets_at": 4}}
        with mock.patch.object(fetch_usage.cache, "read_entry", return_value=None), \
             mock.patch.object(fetch_usage.kimi, "fetch_kimi", return_value=expired), \
             mock.patch.object(fetch_usage.cache, "read_stale_entry",
                               return_value={"ts": 900, "data": stale}):
            result = fetch_usage.kimi_with_cache()

        self.assertEqual(result["reason"], "stale")
        self.assertEqual(result["upstream_reason"], "expired")
        self.assertEqual(result["fetched_at"], 900)
        self.assertFalse(result["live"])

    def test_fresh_cache_is_live_and_uses_original_fetch_time(self):
        entry = {"ts": 1000, "data": {"ok": True, "five_h": {}, "weekly": {}}}
        with mock.patch.object(fetch_usage.cache, "read_entry", return_value=entry):
            result = fetch_usage.claude_with_cache()

        self.assertEqual(result["fetched_at"], 1000)
        self.assertTrue(result["live"])

    def test_codex_result_checks_opt_in_refresh_after_parsing(self):
        parsed = {
            "ok": True,
            "as_of": 1000,
            "five_h": {"pct": 1, "resets_at": 2},
            "weekly": {"pct": 3, "resets_at": 4},
        }
        with mock.patch.object(fetch_usage.cache, "read_entry", return_value=None), \
             mock.patch.object(fetch_usage.codex, "fetch_codex_live",
                               return_value={"ok": False, "reason": "error"}), \
             mock.patch.object(fetch_usage.codex, "parse_codex",
                               return_value=parsed), \
             mock.patch.object(fetch_usage.codex,
                               "maybe_active_refresh") as refresh:
            fetch_usage.codex_result(now=3000)

        refresh.assert_called_once_with(1000, now=3000)

    def test_codex_prefers_live_and_caches_it(self):
        live = {"ok": True, "as_of": 5000,
                "five_h": {"pct": 1, "resets_at": 9, "stale": False},
                "weekly": {"pct": 16, "resets_at": 9, "stale": False}}
        with mock.patch.object(fetch_usage.cache, "read_entry", return_value=None), \
             mock.patch.object(fetch_usage.codex, "fetch_codex_live",
                               return_value=live), \
             mock.patch.object(fetch_usage.codex, "parse_codex") as parse, \
             mock.patch.object(fetch_usage.cache, "write") as write:
            result = fetch_usage.codex_result(now=5000)

        self.assertTrue(result["live"])
        self.assertEqual(result["fetched_at"], 5000)
        self.assertEqual(result["five_h"]["pct"], 1)
        parse.assert_not_called()  # live succeeded → no log scrape
        write.assert_called_once_with(fetch_usage.CODEX_CACHE_PATH, live, now=5000)

    def test_codex_live_failure_falls_back_to_log_scrape(self):
        parsed = {"ok": True, "as_of": 4900,
                  "five_h": {"pct": 80, "resets_at": 9},
                  "weekly": {"pct": 40, "resets_at": 9}}
        with mock.patch.object(fetch_usage.cache, "read_entry", return_value=None), \
             mock.patch.object(fetch_usage.codex, "fetch_codex_live",
                               return_value={"ok": False, "reason": "error"}), \
             mock.patch.object(fetch_usage.codex, "parse_codex",
                               return_value=parsed), \
             mock.patch.object(fetch_usage.codex, "maybe_active_refresh"):
            result = fetch_usage.codex_result(now=5000)

        self.assertEqual(result["five_h"]["pct"], 80)  # from the log fallback
