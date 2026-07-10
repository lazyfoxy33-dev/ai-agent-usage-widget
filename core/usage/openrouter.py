"""OpenRouter balance provider.

Fetches credits from ``https://openrouter.ai/api/v1/credits`` and optionally
queries ``/api/v1/key`` for official usage-based burn-rate data.
"""
import os

from . import api_key_http
from . import balance_history

CREDITS_URL = "https://openrouter.ai/api/v1/credits"
KEY_URL = "https://openrouter.ai/api/v1/key"
HISTORY_PATH = "~/.cache/usage-widget/openrouter-history.jsonl"
DEFAULT_CURRENCY = "USD"


def _as_float(value):
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        return float(value.strip())
    raise ValueError(f"Cannot convert {type(value).__name__} to float")


def parse_openrouter_credits(payload):
    """Map OpenRouter /api/v1/credits JSON -> balance amount and currency."""
    if not isinstance(payload, dict):
        raise ValueError("OpenRouter response is not an object")

    data = payload.get("data")
    if not isinstance(data, dict):
        raise ValueError("OpenRouter credits response missing data")

    total_credits = data.get("total_credits")
    total_usage = data.get("total_usage")
    if total_credits is None or total_usage is None:
        raise ValueError("OpenRouter credits missing total_credits or total_usage")

    return {
        "amount": _as_float(total_credits) - _as_float(total_usage),
        "currency": DEFAULT_CURRENCY,
    }


def parse_openrouter_key(payload):
    """Map OpenRouter /api/v1/key JSON -> usage fields, or None if unusable."""
    if not isinstance(payload, dict):
        return None
    data = payload.get("data")
    if not isinstance(data, dict):
        return None

    def maybe_float(key):
        value = data.get(key)
        if value is None:
            return None
        try:
            return _as_float(value)
        except (TypeError, ValueError):
            return None

    return {
        "limit": maybe_float("limit"),
        "limit_remaining": maybe_float("limit_remaining"),
        "usage": maybe_float("usage"),
        "usage_daily": maybe_float("usage_daily"),
        "usage_weekly": maybe_float("usage_weekly"),
        "usage_monthly": maybe_float("usage_monthly"),
        "is_free_tier": bool(data.get("is_free_tier", False)),
    }


def estimate_from_key_usage(key_data, balance_amount):
    """Return a burn-rate estimate using official key usage fields.

    Prefers ``usage_daily``, then ``usage_weekly``, then ``usage_monthly``.
    Falls back to a no-estimate result when no usage field is present or all
    are zero.
    """
    if not key_data:
        return None

    candidates = [
        (key_data.get("usage_daily"), 1, "high"),
        (key_data.get("usage_weekly"), 7, "medium"),
        (key_data.get("usage_monthly"), 30, "low"),
    ]
    for usage, window_days, confidence in candidates:
        if usage is not None and usage > 0:
            amount_per_day = usage / window_days
            estimated_days_left = int(balance_amount / amount_per_day)
            return {
                "amount_per_day": amount_per_day,
                "window_days": window_days,
                "estimated_days_left": estimated_days_left,
                "confidence": confidence,
            }

    if key_data.get("usage_daily") is not None or key_data.get("usage_weekly") is not None or key_data.get("usage_monthly") is not None:
        return {"confidence": "none", "reason": "no_recent_spend"}

    return None


def fetch_openrouter(now=None):
    """Fetch OpenRouter credits and best-effort key usage, returning a provider dict."""
    token = os.environ.get("OPENROUTER_API_KEY")
    if not token:
        return {"ok": False, "kind": "balance", "reason": "no_data"}

    try:
        credits = api_key_http.bearer_get_json(CREDITS_URL, token)
        balance = parse_openrouter_credits(credits)
    except api_key_http.ApiAuthError:
        return {"ok": False, "kind": "balance", "reason": "expired"}
    except api_key_http.ApiRateLimitError:
        return {"ok": False, "kind": "balance", "reason": "rate_limited"}
    except Exception:
        return {"ok": False, "kind": "balance", "reason": "error"}

    key_data = None
    try:
        key_response = api_key_http.bearer_get_json(KEY_URL, token)
        key_data = parse_openrouter_key(key_response)
    except Exception:
        pass

    burn_rate = estimate_from_key_usage(key_data, balance["amount"])
    if burn_rate is None:
        burn_rate = balance_history.record_and_estimate(
            HISTORY_PATH,
            balance["amount"],
            balance["currency"],
            now=now,
        )

    return {
        "ok": True,
        "kind": "balance",
        "balance": {
            "amount": balance["amount"],
            "currency": balance["currency"],
            "available": balance["amount"] > 0,
            "label": "Balance",
        },
        "burn_rate": burn_rate,
    }
