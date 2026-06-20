"""Claude usage via the local OAuth token + /api/oauth/usage.

When the access token has expired we refresh it with the stored refresh token
and persist the result, mirroring the concurrency-safe protocol already proven
in ``usage/kimi.py`` (directory lock + post-lock re-read peer short-circuit +
form-body refresh kept out of argv + atomic write-back). This keeps a
desktop-app-only user — whose token nothing else rotates — continuously live.
"""
import json
import os
import subprocess
import threading
import time
import urllib.parse
from contextlib import contextmanager
from datetime import datetime

from . import credential_store
from . import refresh_backoff

USAGE_URL = "https://api.anthropic.com/api/oauth/usage"
OAUTH_TOKEN_URL = "https://platform.claude.com/v1/oauth/token"
CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
REFRESH_LOCK_PATH = os.path.expanduser("~/.cache/usage-widget/claude-oauth")
# A successful refresh yields an ~8h token (self-limiting); failures escalate via
# refresh_backoff so an expired token cannot hammer the OAuth endpoint into 429.
REFRESH_BACKOFF_PATH = os.path.expanduser("~/.cache/usage-widget/claude-refresh.json")
_LOCK_STALE_SECONDS = 5
_LOCK_HEARTBEAT_SECONDS = 2


class ClaudeRateLimitError(RuntimeError):
    """The Anthropic usage API returned HTTP 429."""


class ClaudeRefreshUnauthorized(RuntimeError):
    """The Claude OAuth endpoint rejected the refresh token."""


class ClaudeRefreshRateLimited(RuntimeError):
    """The Claude OAuth refresh endpoint returned HTTP 429."""


class ClaudeRefreshThrottled(RuntimeError):
    """A refresh is being skipped while the backoff window is active."""


def read_keychain_blob():
    """Return raw Claude credential JSON from the platform store, or None."""
    return credential_store.read_claude_blob()


def parse_creds(blob):
    """Extract the claudeAiOauth object from a credential blob."""
    return json.loads(blob)["claudeAiOauth"]


def is_expired(creds, now=None):
    now = time.time() if now is None else now
    exp = creds.get("expiresAt")
    if not exp:
        return True
    return (exp / 1000.0) <= now


def _norm_pct(v):
    """Normalize utilization to a 0-100 int.

    The /api/oauth/usage endpoint reports utilization on a 0-100 scale (e.g.
    86.0), and its `limits` array uses integer percents — so a value of 1.0
    means 1%, not the fraction 100%. Round and floor at 0; never rescale, or
    genuine low usage (0 < util <= 1) would be inflated (1% -> 100%).
    """
    return max(0, round(float(v)))


def _parse_resets(v):
    """Return int unix timestamp from resets_at field.
    Accepts int/float (already unix ts) or ISO 8601 string.
    """
    if isinstance(v, (int, float)):
        return int(v)
    # string: ISO 8601, possibly with Z suffix
    return int(datetime.fromisoformat(v.replace("Z", "+00:00")).timestamp())


def _proxy():
    """Return a proxy URL from HTTPS_PROXY / https_proxy, or None."""
    for key in ("HTTPS_PROXY", "https_proxy"):
        val = os.environ.get(key)
        if val:
            return val
    return None


def parse_claude_usage(data, now=None):
    """Map /api/oauth/usage JSON -> {five_h, weekly}.
    Keep ALL field-name knowledge inside this function.
    """
    now = time.time() if now is None else now
    five = data["five_hour"]
    week = data["seven_day"]
    return {
        "ok": True,
        "five_h": {"pct": _norm_pct(five["utilization"]), "resets_at": _parse_resets(five["resets_at"]), "stale": _parse_resets(five["resets_at"]) < now},
        "weekly": {"pct": _norm_pct(week["utilization"]), "resets_at": _parse_resets(week["resets_at"]), "stale": _parse_resets(week["resets_at"]) < now},
    }


def _http_get_usage(token):
    """Fetch usage JSON from Anthropic API via curl.

    Uses curl so an HTTPS_PROXY / https_proxy proxy is honoured. The proxy URL
    is passed via the subprocess environment (HTTPS_PROXY) rather than -x so it
    works transparently with curl's built-in proxy support. The authorization
    header is passed through stdin so the token is not exposed in process
    arguments.
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
    if code == "429":
        raise ClaudeRateLimitError("HTTP 429")
    if code != "200":
        raise RuntimeError(f"HTTP {code}: {body[:200]}")
    return json.loads(body)


def _http_refresh(refresh_token):
    """Exchange a refresh token for a fresh OAuth token set.

    The body is form-encoded (JSON is rejected by the gateway) and passed via
    stdin so the secret never lands in argv. Returns the parsed token JSON.
    """
    if "\n" in refresh_token or "\r" in refresh_token:
        raise ValueError("Invalid refresh token")
    body = urllib.parse.urlencode({
        "grant_type": "refresh_token",
        "refresh_token": refresh_token,
        "client_id": CLIENT_ID,
    })
    cmd = [
        "curl", "-q",
        "-sS", "--max-time", "20",
        "-H", "Accept: application/json",
        "-H", "Content-Type: application/x-www-form-urlencoded",
        "-H", "User-Agent: claude-cli/1.0 (external, cli)",
        "--data-binary", "@-",
        OAUTH_TOKEN_URL,
        "-w", "\n__HTTP__%{http_code}",
    ]
    env = os.environ.copy()
    proxy = _proxy()
    if proxy:
        env["HTTPS_PROXY"] = proxy
    result = subprocess.run(
        cmd, input=body, capture_output=True, text=True, timeout=25, env=env
    )
    if "\n__HTTP__" not in result.stdout:
        raise RuntimeError("Unexpected curl output")
    response_body, code = result.stdout.rsplit("\n__HTTP__", 1)
    code = code.strip()
    try:
        data = json.loads(response_body)
    except ValueError:
        data = {}
    if code in ("400", "401", "403") or data.get("error") == "invalid_grant":
        raise ClaudeRefreshUnauthorized(f"HTTP {code}")
    if code == "429":
        raise ClaudeRefreshRateLimited("HTTP 429")
    if code != "200":
        raise RuntimeError(f"HTTP {code}: {response_body[:200]}")
    if not all(data.get(key) for key in ("access_token", "refresh_token")):
        raise RuntimeError("Claude refresh response is missing tokens")
    return data


def _touch_lock(lock_dir, stop):
    while not stop.wait(_LOCK_HEARTBEAT_SECONDS):
        try:
            os.utime(lock_dir, None)
        except OSError:
            return


@contextmanager
def _refresh_lock(timeout=60):
    """Official directory lock (mkdir + heartbeat + stale recovery).

    Verbatim copy of the Kimi protocol so the working provider is untouched.
    """
    target = REFRESH_LOCK_PATH
    lock_dir = target + ".lock"
    parent = os.path.dirname(target)
    os.makedirs(parent, mode=0o700, exist_ok=True)
    try:
        os.chmod(parent, 0o700)
    except OSError:
        pass
    with open(target, "a"):
        pass

    deadline = time.monotonic() + timeout
    while True:
        try:
            os.mkdir(lock_dir, 0o700)
            break
        except FileExistsError:
            try:
                stale = time.time() - os.path.getmtime(lock_dir)
                if stale > _LOCK_STALE_SECONDS:
                    os.rmdir(lock_dir)
                    continue
            except (FileNotFoundError, OSError):
                pass
            if time.monotonic() >= deadline:
                raise RuntimeError("Timed out waiting for Claude OAuth lock")
            time.sleep(0.5)

    stop = threading.Event()
    heartbeat = threading.Thread(target=_touch_lock, args=(lock_dir, stop), daemon=True)
    heartbeat.start()
    try:
        yield
    finally:
        stop.set()
        heartbeat.join(timeout=1)
        try:
            os.rmdir(lock_dir)
        except OSError:
            pass


def _refresh_creds(creds, now=None):
    """Refresh + persist the Claude OAuth token under the lock.

    Re-reads the stored blob after acquiring the lock: if a peer already
    refreshed it, use that and skip the network. Otherwise — gated by the
    escalating refresh_backoff so repeated failures can't hammer the endpoint —
    exchange the refresh token, merge only the three token fields back into the
    blob (preserving all others), and write it atomically. Returns the fresh
    ``claudeAiOauth`` dict.
    """
    now = time.time() if now is None else now
    with _refresh_lock():
        blob = read_keychain_blob()
        active = creds
        if blob:
            try:
                stored = parse_creds(blob)
            except (ValueError, KeyError):
                stored = None
            if stored is not None:
                if not is_expired(stored, now=now):
                    return stored          # peer already refreshed
                active = stored

        refresh_token = active.get("refreshToken")
        if not refresh_token:
            raise ClaudeRefreshUnauthorized("Missing refresh token")
        if not refresh_backoff.due(REFRESH_BACKOFF_PATH, now):
            raise ClaudeRefreshThrottled("backing off after a recent failure")

        try:
            refreshed = _http_refresh(refresh_token)
        except ClaudeRefreshRateLimited:
            refresh_backoff.note_failure(REFRESH_BACKOFF_PATH, now, rate_limited=True)
            raise
        except Exception:
            refresh_backoff.note_failure(REFRESH_BACKOFF_PATH, now)
            raise
        refresh_backoff.clear(REFRESH_BACKOFF_PATH)

        expires_in = int(refreshed.get("expires_in", 0))
        updated = dict(active)
        updated["accessToken"] = refreshed["access_token"]
        updated["refreshToken"] = refreshed["refresh_token"]
        updated["expiresAt"] = int((now + expires_in) * 1000)

        try:
            full = json.loads(blob) if blob else {}
            if not isinstance(full, dict):
                full = {}
        except ValueError:
            full = {}
        full["claudeAiOauth"] = updated
        credential_store.write_claude_blob(json.dumps(full))
        return updated


def fetch_claude():
    """Full pipeline: keychain -> expiry (refresh if needed) -> API -> parse."""
    blob = read_keychain_blob()
    if not blob:
        return {"ok": False, "reason": "expired"}
    try:
        creds = parse_creds(blob)
    except (ValueError, KeyError):
        return {"ok": False, "reason": "expired"}
    if is_expired(creds):
        try:
            creds = _refresh_creds(creds)
        except (ClaudeRefreshUnauthorized, ClaudeRefreshThrottled):
            return {"ok": False, "reason": "expired"}
        except ClaudeRefreshRateLimited:
            return {"ok": False, "reason": "rate_limited"}
        except Exception:
            return {"ok": False, "reason": "error"}
        if is_expired(creds):
            return {"ok": False, "reason": "expired"}
    try:
        data = _http_get_usage(creds["accessToken"])
        return parse_claude_usage(data, now=time.time())
    except ClaudeRateLimitError:
        return {"ok": False, "reason": "rate_limited"}
    except Exception:
        return {"ok": False, "reason": "error"}
