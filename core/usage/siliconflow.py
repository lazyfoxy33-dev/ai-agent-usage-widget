"""SiliconFlow balance provider.

Fetches user info from ``https://api.siliconflow.com/v1/user/info`` using a
Bearer token from the ``SILICONFLOW_API_KEY`` environment variable.
"""
import os

from . import api_key_http
from . import balance_history

API_URL = "https://api.siliconflow.com/v1/user/info"
HISTORY_PATH = "~/.cache/usage-widget/siliconflow-history.jsonl"
DEFAULT_CURRENCY = "CNY"


def _as_float(value):
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        return float(value.strip())
    raise ValueError(f"Cannot convert {type(value).__name__} to float")


def parse_siliconflow_info(payload, now=None):
    """Map SiliconFlow /v1/user/info JSON -> a balance provider dict."""
    if not isinstance(payload, dict):
        raise ValueError("SiliconFlow response is not an object")

    data = payload.get("data")
    if not isinstance(data, dict):
        raise ValueError("SiliconFlow response missing data")

    total_balance = data.get("totalBalance")
    if total_balance is None:
        total_balance = data.get("balance")
    if total_balance is None:
        raise ValueError("SiliconFlow response missing totalBalance")

    currency = data.get("currency") or DEFAULT_CURRENCY
    status = data.get("status", "active")

    return {
        "ok": True,
        "kind": "balance",
        "balance": {
            "amount": _as_float(total_balance),
            "currency": str(currency).upper(),
            "available": str(status).lower() in ("active", "normal", "ok"),
            "label": "Balance",
        },
    }


def fetch_siliconflow(now=None):
    """Fetch SiliconFlow balance and append a history sample."""
    token = os.environ.get("SILICONFLOW_API_KEY")
    if not token:
        return {"ok": False, "kind": "balance", "reason": "no_data"}

    try:
        payload = api_key_http.bearer_get_json(API_URL, token)
        result = parse_siliconflow_info(payload)
    except api_key_http.ApiAuthError:
        return {"ok": False, "kind": "balance", "reason": "expired"}
    except api_key_http.ApiRateLimitError:
        return {"ok": False, "kind": "balance", "reason": "rate_limited"}
    except Exception:
        return {"ok": False, "kind": "balance", "reason": "error"}

    balance = result["balance"]
    burn_rate = balance_history.record_and_estimate(
        HISTORY_PATH,
        balance["amount"],
        balance["currency"],
        now=now,
    )
    result["burn_rate"] = burn_rate
    return result
