"""SiliconFlow balance provider.

Fetches user info from ``https://api.siliconflow.com/v1/user/info`` using a
Bearer token from the ``SILICONFLOW_API_KEY`` environment variable.
"""
import os

from . import api_key_http
from . import balance_history

API_URLS = [
    "https://api.siliconflow.com/v1/user/info",
    "https://api.siliconflow.cn/v1/user/info",
]
HISTORY_PATH = "~/.cache/usage-widget/siliconflow-history.jsonl"
DEFAULT_CURRENCY = "CNY"


class BalanceUnavailableError(ValueError):
    """SiliconFlow returned a balance value that should not be displayed."""


def _as_float(value):
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        return float(value.strip())
    raise ValueError(f"Cannot convert {type(value).__name__} to float")


def _normalize_console_amount(key, value):
    amount = _as_float(value)
    if key == "balance" and amount >= 1_000_000_000:
        return amount / 1_000_000_000_000
    return amount


def parse_siliconflow_info(payload, now=None):
    """Map SiliconFlow /v1/user/info JSON -> a balance provider dict."""
    if not isinstance(payload, dict):
        raise ValueError("SiliconFlow response is not an object")

    data = payload.get("data")
    if not isinstance(data, dict):
        raise ValueError("SiliconFlow response missing data")

    currency = data.get("currency") or DEFAULT_CURRENCY
    status = data.get("status", "active")

    amounts = []
    saw_balance_field = False
    for key in ("totalBalance", "chargeBalance", "balance"):
        balance_value = data.get(key)
        if balance_value is None:
            continue
        saw_balance_field = True
        candidate = _as_float(balance_value)
        if candidate >= 0:
            amounts.append(candidate)

    if not amounts:
        if saw_balance_field:
            raise BalanceUnavailableError("SiliconFlow returned a negative API balance")
        raise ValueError("SiliconFlow response missing balance")
    amount = max(amounts)

    return {
        "ok": True,
        "kind": "balance",
        "source": "api_key",
        "balance": {
            "amount": amount,
            "currency": str(currency).upper(),
            "available": str(status).lower() in ("active", "normal", "ok"),
            "label": "Balance",
        },
    }


def parse_console_profile(payload):
    """Map SiliconFlow console wallet profile JSON -> a balance provider dict.

    The console-session provider is intentionally separate from API-key fetches:
    the wallet endpoint is authenticated by a SiliconFlow web console session.
    This parser accepts only the already-sanitized response body.
    """
    if not isinstance(payload, dict):
        raise ValueError("SiliconFlow console response is not an object")

    data = payload.get("data")
    if not isinstance(data, dict):
        raise ValueError("SiliconFlow console response missing data")

    financial_info = data.get("financialInfo")
    if not isinstance(financial_info, dict):
        raise ValueError("SiliconFlow console response missing financialInfo")

    amount = None
    saw_balance_field = False
    for key in ("chargeBalance", "availableBalance", "balance", "totalBalance"):
        balance_value = financial_info.get(key)
        if balance_value is None:
            continue
        saw_balance_field = True
        candidate = _normalize_console_amount(key, balance_value)
        if candidate >= 0:
            amount = candidate
            break

    if amount is None:
        if saw_balance_field:
            raise BalanceUnavailableError("SiliconFlow returned a negative console balance")
        raise ValueError("SiliconFlow console response missing balance")

    currency = financial_info.get("currency") or DEFAULT_CURRENCY
    return {
        "ok": True,
        "kind": "balance",
        "source": "console_session",
        "balance": {
            "amount": amount,
            "currency": str(currency).upper(),
            "available": True,
            "label": "Console Balance",
        },
    }


def fetch_siliconflow(now=None):
    """Fetch SiliconFlow balance and append a history sample."""
    token = os.environ.get("SILICONFLOW_API_KEY")
    if not token:
        return {"ok": False, "kind": "balance", "reason": "no_data"}

    try:
        payload = None
        last_auth_error = False
        last_rate_limit = False
        for url in API_URLS:
            try:
                payload = api_key_http.bearer_get_json(url, token)
                break
            except api_key_http.ApiAuthError:
                last_auth_error = True
            except api_key_http.ApiRateLimitError:
                last_rate_limit = True
        if payload is None:
            if last_rate_limit:
                return {"ok": False, "kind": "balance", "reason": "rate_limited"}
            if last_auth_error:
                return {"ok": False, "kind": "balance", "reason": "expired"}
            return {"ok": False, "kind": "balance", "reason": "error"}
        result = parse_siliconflow_info(payload)
    except BalanceUnavailableError:
        return {"ok": False, "kind": "balance", "reason": "balance_unavailable"}
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
