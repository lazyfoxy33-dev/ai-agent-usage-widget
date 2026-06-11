import json
import unittest
from unittest import mock
import fetch_usage


class TestFetch(unittest.TestCase):
    def test_combined_json_shape(self):
        codex_res = {"ok": True, "five_h": {"pct": 7, "resets_at": 1},
                     "weekly": {"pct": 22, "resets_at": 2}}
        claude_res = {"ok": False, "reason": "expired"}
        with mock.patch.object(fetch_usage.codex, "parse_codex", return_value=codex_res), \
             mock.patch.object(fetch_usage, "claude_with_cache", return_value=claude_res):
            out = json.loads(fetch_usage.build_payload())
        self.assertEqual(out["codex"]["five_h"]["pct"], 7)
        self.assertEqual(out["claude"]["reason"], "expired")
