import json
import unittest
from unittest import mock
import fetch_usage


class TestFetch(unittest.TestCase):
    def test_provider_success_cache_is_five_minutes(self):
        with mock.patch.object(fetch_usage.cache, "read", return_value={"ok": True}) as read:
            fetch_usage.claude_with_cache()
            read.assert_called_once_with(
                fetch_usage.CACHE_PATH,
                ttl=fetch_usage.CACHE_TTL,
            )

        self.assertEqual(fetch_usage.CACHE_TTL, 300)

    def test_combined_json_shape(self):
        codex_res = {"ok": True, "five_h": {"pct": 7, "resets_at": 1},
                     "weekly": {"pct": 22, "resets_at": 2}}
        claude_res = {"ok": False, "reason": "expired"}
        kimi_res = {"ok": True, "five_h": {"pct": 34, "resets_at": 3},
                    "weekly": {"pct": 8, "resets_at": 4}}
        with mock.patch.object(fetch_usage.codex, "parse_codex", return_value=codex_res), \
             mock.patch.object(fetch_usage, "claude_with_cache", return_value=claude_res), \
             mock.patch.object(fetch_usage, "kimi_with_cache", return_value=kimi_res):
            out = json.loads(fetch_usage.build_payload())
        self.assertEqual(out["codex"]["five_h"]["pct"], 7)
        self.assertEqual(out["claude"]["reason"], "expired")
        self.assertEqual(out["kimi"]["weekly"]["pct"], 8)

    def test_kimi_success_is_written_to_separate_cache(self):
        result = {"ok": True, "five_h": {"pct": 34, "resets_at": 3},
                  "weekly": {"pct": 8, "resets_at": 4}}
        with mock.patch.object(fetch_usage.cache, "read", return_value=None), \
             mock.patch.object(fetch_usage.kimi, "fetch_kimi", return_value=result), \
             mock.patch.object(fetch_usage.cache, "write") as write:
            self.assertEqual(fetch_usage.kimi_with_cache(), result)

        write.assert_called_once_with(fetch_usage.KIMI_CACHE_PATH, result)

    def test_kimi_transient_error_uses_stale_cache(self):
        stale = {"ok": True, "five_h": {"pct": 30, "resets_at": 3},
                 "weekly": {"pct": 7, "resets_at": 4}}
        with mock.patch.object(fetch_usage.cache, "read", return_value=None), \
             mock.patch.object(fetch_usage.kimi, "fetch_kimi",
                               return_value={"ok": False, "reason": "error"}), \
             mock.patch.object(fetch_usage.cache, "read_stale", return_value=stale):
            result = fetch_usage.kimi_with_cache()

        self.assertEqual(result["reason"], "stale")
        self.assertEqual(result["weekly"]["pct"], 7)

    def test_kimi_expired_does_not_use_stale_cache(self):
        expired = {"ok": False, "reason": "expired"}
        with mock.patch.object(fetch_usage.cache, "read", return_value=None), \
             mock.patch.object(fetch_usage.kimi, "fetch_kimi", return_value=expired), \
             mock.patch.object(fetch_usage.cache, "read_stale") as read_stale:
            result = fetch_usage.kimi_with_cache()

        self.assertEqual(result, expired)
        read_stale.assert_not_called()
