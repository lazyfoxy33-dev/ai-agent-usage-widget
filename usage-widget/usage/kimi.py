"""Kimi Code usage via the local Kimi CLI OAuth token."""
import json
import os
import socket
import subprocess
import time
from datetime import datetime

USAGE_URL = "https://api.kimi.com/coding/v1/usages"
_PROXY_CANDIDATES = [("127.0.0.1", 7897), ("127.0.0.1", 7890)]


class KimiAuthError(RuntimeError):
    """The Kimi API rejected the local OAuth access token."""


def credentials_path():
    return credential_paths()[0]


def credential_paths():
    current_home = os.environ.get("KIMI_CODE_HOME") or os.path.expanduser("~/.kimi-code")
    legacy_home = os.environ.get("KIMI_SHARE_DIR") or os.path.expanduser("~/.kimi")
    paths = [
        os.path.join(current_home, "credentials", "kimi-code.json"),
        os.path.join(legacy_home, "credentials", "kimi-code.json"),
    ]
    return list(dict.fromkeys(paths))


def _read_credentials_file(path):
    try:
        with open(path) as f:
            data = json.load(f)
        return data if isinstance(data, dict) else None
    except (OSError, ValueError):
        return None


def read_credentials(path=None):
    if path is not None:
        return _read_credentials_file(path)
    for candidate in credential_paths():
        data = _read_credentials_file(candidate)
        if data is not None:
            return data
    return None


def is_expired(credentials, now=None):
    now = time.time() if now is None else now
    try:
        return float(credentials.get("expires_at", 0)) <= now
    except (TypeError, ValueError):
        return True


def _to_number(value):
    if isinstance(value, bool):
        raise ValueError("Boolean is not a numeric quota value")
    return float(value)


def _percentage(data):
    limit = _to_number(data["limit"])
    if limit <= 0:
        raise ValueError("Quota limit must be positive")
    if data.get("used") is not None:
        used = _to_number(data["used"])
    elif data.get("remaining") is not None:
        used = limit - _to_number(data["remaining"])
    else:
        raise ValueError("Quota usage is missing")
    return round(min(100.0, max(0.0, used / limit * 100.0)))


def _parse_reset_value(value):
    if isinstance(value, dict):
        value = value.get("seconds")
    if isinstance(value, (int, float)):
        return int(value)
    if isinstance(value, str):
        try:
            return int(float(value))
        except ValueError:
            return int(datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp())
    raise ValueError("Reset timestamp is missing")


def _reset_timestamp(data):
    for key in ("reset_at", "resetAt", "reset_time", "resetTime"):
        if data.get(key) is not None:
            return _parse_reset_value(data[key])
    raise ValueError("Reset timestamp is missing")


def _is_five_hour_limit(item):
    window = item.get("window") if isinstance(item, dict) else None
    if not isinstance(window, dict):
        return False
    try:
        duration = int(window.get("duration"))
    except (TypeError, ValueError):
        return False
    unit = str(window.get("timeUnit") or "").upper()
    return duration == 300 and "MINUTE" in unit


def _window(data):
    return {
        "pct": _percentage(data),
        "resets_at": _reset_timestamp(data),
    }


def parse_kimi_usage(payload):
    usage = payload.get("usage")
    limits = payload.get("limits")
    if not isinstance(usage, dict) or not isinstance(limits, list):
        raise ValueError("Unexpected Kimi usage response")

    five = None
    for item in limits:
        if not _is_five_hour_limit(item):
            continue
        detail = item.get("detail")
        five = detail if isinstance(detail, dict) else item
        break
    if five is None:
        raise ValueError("Five-hour Kimi limit is missing")

    return {
        "ok": True,
        "five_h": _window(five),
        "weekly": _window(usage),
    }


def _proxy():
    for key in ("HTTPS_PROXY", "https_proxy"):
        value = os.environ.get(key)
        if value:
            return value
    for host, port in _PROXY_CANDIDATES:
        try:
            with socket.create_connection((host, port), timeout=0.3):
                return f"http://{host}:{port}"
        except OSError:
            continue
    return None


def _http_get_usage(token):
    if "\n" in token or "\r" in token:
        raise ValueError("Invalid access token")
    escaped_token = token.replace("\\", "\\\\").replace('"', '\\"')
    curl_config = f'header = "Authorization: Bearer {escaped_token}"\n'
    cmd = [
        "curl", "-q", "--config", "-",
        "-sS", "--max-time", "20",
        "-H", "Accept: application/json",
        USAGE_URL,
        "-w", "\n__HTTP__%{http_code}",
    ]
    env = os.environ.copy()
    proxy = _proxy()
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
    if "\n__HTTP__" not in result.stdout:
        raise RuntimeError("Unexpected curl output")
    body, code = result.stdout.rsplit("\n__HTTP__", 1)
    code = code.strip()
    if code in ("401", "403"):
        raise KimiAuthError(f"HTTP {code}")
    if code != "200":
        raise RuntimeError(f"HTTP {code}: {body[:200]}")
    return json.loads(body)


def fetch_kimi():
    credentials = read_credentials()
    if not credentials:
        return {"ok": False, "reason": "no_data"}
    token = credentials.get("access_token")
    if not token or is_expired(credentials):
        return {"ok": False, "reason": "expired"}
    try:
        return parse_kimi_usage(_http_get_usage(token))
    except KimiAuthError:
        return {"ok": False, "reason": "expired"}
    except Exception:
        return {"ok": False, "reason": "error"}
