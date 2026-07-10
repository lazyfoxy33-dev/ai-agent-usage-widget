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
             mock.patch.object(fetch_usage.codex, "maybe_active_refresh"), \
             mock.patch.object(fetch_usage, "claude_with_cache",
                               return_value=no_data), \
             mock.patch.object(fetch_usage, "kimi_with_cache",
                               return_value=no_data), \
             mock.patch.object(fetch_usage, "deepseek_with_cache",
                               return_value=no_data), \
             mock.patch.object(fetch_usage, "openrouter_with_cache",
                               return_value=no_data):
            payload = json.loads(fetch_usage.build_payload())

        self.assertEqual(payload["schema_version"], 1)
        for name in ("claude", "codex", "kimi", "deepseek", "siliconflow", "openrouter"):
            provider = payload[name]
            self.assertIsInstance(provider["live"], bool)
            self.assertTrue(
                provider["fetched_at"] is None
                or isinstance(provider["fetched_at"], int)
            )

    def test_balance_provider_schema(self):
        path = os.path.join(ROOT, "contract.schema.json")
        with open(path) as f:
            schema = json.load(f)

        provider = schema["$defs"]["provider"]
        self.assertIn("kind", provider["properties"])
        self.assertIn("source", provider["properties"])
        self.assertIn("balance", provider["properties"])
        self.assertIn("burn_rate", provider["properties"])
        self.assertIn("balance_unavailable", provider["properties"]["reason"]["enum"])
        self.assertIn("login_required", provider["properties"]["reason"]["enum"])
        self.assertIn("console_session", provider["properties"]["source"]["enum"])

        balance = schema["$defs"]["balance"]
        self.assertIn("amount", balance["required"])
        self.assertIn("currency", balance["required"])

        burn_rate = schema["$defs"]["burn_rate"]
        self.assertEqual(
            set(burn_rate["properties"]["confidence"]["enum"]),
            {"none", "low", "medium", "high"}
        )
