"""Shared Bearer-token HTTP helper for API-key balance providers.

Secrets travel only in request headers held in process memory; they never enter
argv, shell commands, logs, or cache files.
"""
import json
import os
import urllib.error
import urllib.request


class ApiAuthError(RuntimeError):
    """Credentials missing, expired, or rejected (HTTP 401/403)."""


class ApiRateLimitError(RuntimeError):
    """The upstream API returned HTTP 429."""


class ApiHttpError(RuntimeError):
    """A non-2xx HTTP response that is not auth or rate-limit."""

    def __init__(self, status, body=None):
        super().__init__(f"HTTP {status}")
        self.status = status
        self.body = body


class ApiResponseError(RuntimeError):
    """The HTTP response body could not be parsed as JSON."""


def _proxy():
    """Return a proxy URL from HTTPS_PROXY / https_proxy, or None."""
    for key in ("HTTPS_PROXY", "https_proxy"):
        val = os.environ.get(key)
        if val:
            return val
    return None


def _http_request(url, headers=None, timeout=25):
    """Return (status, body) for a GET request, honoring HTTPS_PROXY."""
    proxy = _proxy()
    proxies = {"https": proxy, "http": proxy} if proxy else {}
    opener = urllib.request.build_opener(urllib.request.ProxyHandler(proxies))
    request = urllib.request.Request(url, headers=headers or {})
    try:
        with opener.open(request, timeout=timeout) as response:
            return response.status, response.read().decode("utf-8")
    except urllib.error.HTTPError as error:
        return error.code, error.read().decode("utf-8", errors="replace")


def bearer_get_json(url, token, timeout=25, extra_headers=None):
    """GET ``url`` with a Bearer token and return parsed JSON.

    Args:
        url: The endpoint URL.
        token: The API key / bearer token. Must not contain newlines.
        timeout: Request timeout in seconds.
        extra_headers: Optional dict of additional request headers.

    Returns:
        Parsed JSON response as a Python object.

    Raises:
        ValueError: If the token is empty or contains whitespace.
        ApiAuthError: On HTTP 401/403.
        ApiRateLimitError: On HTTP 429.
        ApiHttpError: On other non-2xx responses.
        ApiResponseError: If the body is not valid JSON.
    """
    if not token or not isinstance(token, str):
        raise ValueError("Missing or invalid API token")
    if "\n" in token or "\r" in token or "\t" in token:
        raise ValueError("Token contains invalid whitespace")

    headers = {"Authorization": f"Bearer {token}", "Accept": "application/json"}
    if extra_headers:
        headers.update(extra_headers)

    status, body = _http_request(url, headers=headers, timeout=timeout)

    if status in (401, 403):
        raise ApiAuthError(f"HTTP {status}")
    if status == 429:
        raise ApiRateLimitError(f"HTTP {status}")
    if status != 200:
        raise ApiHttpError(status, body=body)

    try:
        return json.loads(body)
    except ValueError as exc:
        raise ApiResponseError(f"Invalid JSON response: {exc}") from exc
