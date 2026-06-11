"""Claude usage via Keychain OAuth token + /api/oauth/usage (read-only token)."""
import json
import os
import socket
import subprocess
import time
from datetime import datetime

KEYCHAIN_SERVICE = "Claude Code-credentials"
USAGE_URL = "https://api.anthropic.com/api/oauth/usage"
_PROXY_CANDIDATES = [("127.0.0.1", 7897), ("127.0.0.1", 7890)]


def read_keychain_blob():
    """Return raw JSON string from Keychain, or None."""
    try:
        out = subprocess.run(
            ["security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-w"],
            capture_output=True, text=True, timeout=10,
        )
        return out.stdout.strip() or None
    except (OSError, subprocess.SubprocessError):
        return None


def parse_creds(blob):
    """Extract claudeAiOauth object from Keychain blob."""
    return json.loads(blob)["claudeAiOauth"]


def is_expired(creds, now=None):
    now = time.time() if now is None else now
    exp = creds.get("expiresAt")
    if not exp:
        return True
    return (exp / 1000.0) <= now


def _norm_pct(v):
    """Normalize utilization to 0-100 int. Accept 0-1 or 0-100."""
    v = float(v)
    if v <= 1.0:
        v *= 100.0
    return round(v)


def _parse_resets(v):
    """Return int unix timestamp from resets_at field.
    Accepts int/float (already unix ts) or ISO 8601 string.
    """
    if isinstance(v, (int, float)):
        return int(v)
    # string: ISO 8601, possibly with Z suffix
    return int(datetime.fromisoformat(v.replace("Z", "+00:00")).timestamp())


def _proxy():
    """Return a proxy URL string or None.

    Priority:
    1. HTTPS_PROXY / https_proxy env var (already set by user/shell)
    2. Probe well-known local Clash proxy ports (7897, 7890)
    3. None
    """
    for key in ("HTTPS_PROXY", "https_proxy"):
        val = os.environ.get(key)
        if val:
            return val
    # Probe local ports (0.3 s timeout each)
    for host, port in _PROXY_CANDIDATES:
        try:
            with socket.create_connection((host, port), timeout=0.3):
                return f"http://{host}:{port}"
        except OSError:
            continue
    return None


def parse_claude_usage(data):
    """Map /api/oauth/usage JSON -> {five_h, weekly}.
    Keep ALL field-name knowledge inside this function.
    """
    five = data["five_hour"]
    week = data["seven_day"]
    return {
        "ok": True,
        "five_h": {"pct": _norm_pct(five["utilization"]), "resets_at": _parse_resets(five["resets_at"])},
        "weekly": {"pct": _norm_pct(week["utilization"]), "resets_at": _parse_resets(week["resets_at"])},
    }


def _http_get_usage(token):
    """Fetch usage JSON from Anthropic API via curl.

    Uses curl so that the local Clash proxy is honoured even when Übersicht
    launches the widget without shell env vars set.  The proxy URL is passed
    via the subprocess environment (HTTPS_PROXY) rather than -x so it works
    transparently with curl's built-in proxy support. The authorization header
    is passed through stdin so the token is not exposed in process arguments.
    """
    if "\n" in token or "\r" in token:
        raise ValueError("Invalid access token")
    escaped_token = token.replace("\\", "\\\\").replace('"', '\\"')
    curl_config = f'header = "Authorization: Bearer {escaped_token}"\n'
    proxy = _proxy()
    cmd = [
        "curl", "-q", "--config", "-",
        "-sS", "--max-time", "20",
        "-H", "anthropic-beta: oauth-2025-04-20",
        "-H", "User-Agent: claude-cli/1.0 (external, cli)",
        "-H", "Accept: application/json",
        USAGE_URL,
        "-w", "\n__HTTP__%{http_code}",
    ]
    env = os.environ.copy()
    if proxy:
        env["HTTPS_PROXY"] = proxy
    result = subprocess.run(
        cmd,
        input=curl_config,
        capture_output=True,
        text=True,
        timeout=25,
        env=env,
    )
    raw = result.stdout
    # Split off the status sentinel appended by -w
    if "\n__HTTP__" in raw:
        body, code = raw.rsplit("\n__HTTP__", 1)
    else:
        raise RuntimeError(f"Unexpected curl output: {raw!r}")
    code = code.strip()
    if code != "200":
        raise RuntimeError(f"HTTP {code}: {body[:200]}")
    return json.loads(body)


def fetch_claude():
    """Full pipeline: keychain -> expiry -> API -> parse. Returns result dict."""
    blob = read_keychain_blob()
    if not blob:
        return {"ok": False, "reason": "expired"}
    try:
        creds = parse_creds(blob)
    except (ValueError, KeyError):
        return {"ok": False, "reason": "expired"}
    if is_expired(creds):
        return {"ok": False, "reason": "expired"}
    try:
        data = _http_get_usage(creds["accessToken"])
        return parse_claude_usage(data)
    except Exception:
        return {"ok": False, "reason": "error"}
