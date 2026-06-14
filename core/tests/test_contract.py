import json
import os
import unittest
from unittest import mock

import fetch_usage


ROOT = os.path.dirname(os.path.dirname(__file__))


class TestContract(unittest.TestCase):
    def test_schema_requires_freshness_fields_for_every_provider(self):
        path = os.path.join(ROOT, "contract.schema.json")
        with open(path) as f:
            schema = json.load(f)

        self.assertEqual(schema["properties"]["schema_version"]["const"], 1)
        provider = schema["$defs"]["provider"]
        self.assertIn("fetched_at", provider["required"])
        self.assertIn("live", provider["required"])

    def test_actual_payload_has_required_provider_shape(self):
        no_data = {"ok": False, "reason": "no_data"}
        with mock.patch.object(fetch_usage.cache, "read_entry", return_value=None), \
             mock.patch.object(fetch_usage.codex, "fetch_codex_live",
                               return_value=no_data), \
             mock.patch.object(fetch_usage.codex, "parse_codex",
                               return_value=no_data), \
             mock.patch.object(fetch_usage, "claude_with_cache",
                               return_value=no_data), \
             mock.patch.object(fetch_usage, "kimi_with_cache",
                               return_value=no_data):
            payload = json.loads(fetch_usage.build_payload())

        self.assertEqual(payload["schema_version"], 1)
        for name in ("claude", "codex", "kimi"):
            provider = payload[name]
            self.assertIsInstance(provider["live"], bool)
            self.assertTrue(
                provider["fetched_at"] is None
                or isinstance(provider["fetched_at"], int)
            )
