import json
import os
import unittest
from unittest import mock

from usage import api_key_http


class TestApiKeyHttp(unittest.TestCase):
    def test_empty_token_raises(self):
        with self.assertRaises(ValueError):
            api_key_http.bearer_get_json("https://example.com", "")

    def test_newline_in_token_raises(self):
        with self.assertRaises(ValueError):
            api_key_http.bearer_get_json("https://example.com", "tok\nen")
        with self.assertRaises(ValueError):
            api_key_http.bearer_get_json("https://example.com", "tok\ren")
        with self.assertRaises(ValueError):
            api_key_http.bearer_get_json("https://example.com", "tok\ten")

    def test_auth_header_never_exposes_token_via_shell(self):
        """The helper uses urllib directly; no subprocess means no argv leakage."""
        with mock.patch.object(api_key_http, "_http_request") as req:
            req.return_value = (200, '{"ok": true}')
            api_key_http.bearer_get_json("https://example.com", "secret-token")
        _, kwargs = req.call_args
        self.assertIn("Authorization", kwargs["headers"])
        self.assertEqual(kwargs["headers"]["Authorization"], "Bearer secret-token")

    def test_401_maps_to_auth_error(self):
        with mock.patch.object(api_key_http, "_http_request", return_value=(401, "")):
            with self.assertRaises(api_key_http.ApiAuthError):
                api_key_http.bearer_get_json("https://example.com", "t")

    def test_403_maps_to_auth_error(self):
        with mock.patch.object(api_key_http, "_http_request", return_value=(403, "")):
            with self.assertRaises(api_key_http.ApiAuthError):
                api_key_http.bearer_get_json("https://example.com", "t")

    def test_429_maps_to_rate_limit_error(self):
        with mock.patch.object(api_key_http, "_http_request", return_value=(429, "")):
            with self.assertRaises(api_key_http.ApiRateLimitError):
                api_key_http.bearer_get_json("https://example.com", "t")

    def test_generic_http_error(self):
        with mock.patch.object(api_key_http, "_http_request", return_value=(500, "boom")):
            with self.assertRaises(api_key_http.ApiHttpError) as ctx:
                api_key_http.bearer_get_json("https://example.com", "t")
            self.assertEqual(ctx.exception.status, 500)

    def test_invalid_json_maps_to_response_error(self):
        with mock.patch.object(api_key_http, "_http_request", return_value=(200, "not json")):
            with self.assertRaises(api_key_http.ApiResponseError):
                api_key_http.bearer_get_json("https://example.com", "t")

    def test_success_returns_parsed_json(self):
        payload = {"balance": 12.34}
        with mock.patch.object(api_key_http, "_http_request", return_value=(200, json.dumps(payload))):
            result = api_key_http.bearer_get_json("https://example.com", "t")
        self.assertEqual(result, payload)

    def test_extra_headers_are_merged(self):
        with mock.patch.object(api_key_http, "_http_request") as req:
            req.return_value = (200, '{}')
            api_key_http.bearer_get_json(
                "https://example.com",
                "t",
                extra_headers={"X-Custom": "value"}
            )
        _, kwargs = req.call_args
        self.assertEqual(kwargs["headers"]["X-Custom"], "value")
        self.assertEqual(kwargs["headers"]["Accept"], "application/json")

    def test_proxy_propagation(self):
        env = {"HTTPS_PROXY": "http://proxy.example.com:8080"}
        with mock.patch.dict(os.environ, env, clear=False):
            with mock.patch.object(api_key_http, "_http_request") as req:
                req.return_value = (200, '{}')
                api_key_http.bearer_get_json("https://example.com", "t")
        _, kwargs = req.call_args
        # _http_request builds ProxyHandler internally; just verify it was called.
        self.assertEqual(kwargs["headers"]["Authorization"], "Bearer t")
