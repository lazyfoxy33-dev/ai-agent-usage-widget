"""DeepSeek balance provider.

Fetches account balance from ``https://api.deepseek.com/user/balance`` using a
Bearer token from the ``DEEPSEEK_API_KEY`` environment variable.
"""
import os

from . import api_key_http
from . import balance_history

API_URL = "https://api.deepseek.com/user/balance"
HISTORY_PATH = "~/.cache/usage-widget/deepseek-history.jsonl"


def _as_float(value):
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        return float(value.strip())
    raise ValueError(f"Cannot convert {type(value).__name__} to float")


def parse_deepseek_balance(payload, now=None):
    """Map DeepSeek /user/balance JSON -> a balance provider dict.

    Uses the first ``balance_infos`` entry. ``now`` is unused but accepted for
    symmetry with other parsers.
    """
    if not isinstance(payload, dict):
        raise ValueError("DeepSeek response is not an object")

    balance_infos = payload.get("balance_infos")
    if not isinstance(balance_infos, list) or not balance_infos:
        raise ValueError("DeepSeek response missing balance_infos")

    info = balance_infos[0]
    if not isinstance(info, dict):
        raise ValueError("DeepSeek balance_infos entry is not an object")

    currency = info.get("currency")
    if not currency:
        raise ValueError("DeepSeek balance missing currency")

    total_balance = info.get("total_balance")
    if total_balance is None:
        raise ValueError("DeepSeek balance missing total_balance")

    return {
        "ok": True,
        "kind": "balance",
        "balance": {
            "amount": _as_float(total_balance),
            "currency": str(currency).upper(),
            "available": bool(payload.get("is_available", True)),
            "label": "Balance",
        },
    }


def fetch_deepseek(now=None):
    """Fetch DeepSeek balance and append a history sample.

    Returns a provider dict. ``fetched_at`` and ``live`` are added by the cache
    wrapper in ``fetch_usage.py``.
    """
    token = os.environ.get("DEEPSEEK_API_KEY")
    if not token:
        return {"ok": False, "kind": "balance", "reason": "no_data"}

    try:
        payload = api_key_http.bearer_get_json(API_URL, token)
        result = parse_deepseek_balance(payload)
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
