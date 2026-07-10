"""JSONL balance history and burn-rate estimation.

History files contain only compact, non-secret records:
    {"ts": 1781234567, "amount": 88.88, "currency": "USD"}
"""
import json
import os
import time

_MAX_AGE_DAYS = 45
_MAX_RECORDS = 500
_SECONDS_PER_DAY = 86400


def _history_path(path):
    return os.path.expanduser(path)


def _read_jsonl(path):
    """Return a list of history records from ``path``; tolerate missing files."""
    try:
        with open(path) as f:
            records = []
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    record = json.loads(line)
                except ValueError:
                    continue
                if not isinstance(record, dict):
                    continue
                ts = record.get("ts")
                amount = record.get("amount")
                currency = record.get("currency")
                if ts is None or amount is None or not currency:
                    continue
                try:
                    records.append({
                        "ts": int(ts),
                        "amount": float(amount),
                        "currency": str(currency),
                    })
                except (TypeError, ValueError):
                    continue
            return records
    except (OSError, ValueError):
        return []


def _write_jsonl(path, records):
    """Atomically write compact JSONL records to ``path``."""
    directory = os.path.dirname(path)
    if directory:
        os.makedirs(directory, exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        for record in records:
            f.write(json.dumps(record, separators=(",", ":")) + "\n")
    os.replace(tmp, path)


def _prune(records, now):
    """Drop records older than ``_MAX_AGE_DAYS`` and cap at ``_MAX_RECORDS``."""
    cutoff = now - _MAX_AGE_DAYS * _SECONDS_PER_DAY
    records = [r for r in records if r["ts"] >= cutoff]
    records.sort(key=lambda r: r["ts"])
    if len(records) > _MAX_RECORDS:
        records = records[-_MAX_RECORDS:]
    return records


def _pick_comparison_point(records, now):
    """Choose the historical record used to compute spend.

    Preference order:
    1. Newest record at least 7 days older than ``now``.
    2. Newest record at least 24 hours older than ``now``.
    3. Oldest available record.
    """
    day_ago = now - _SECONDS_PER_DAY
    week_ago = now - 7 * _SECONDS_PER_DAY

    week_candidates = [r for r in records if r["ts"] <= week_ago]
    if week_candidates:
        return max(week_candidates, key=lambda r: r["ts"])

    day_candidates = [r for r in records if r["ts"] <= day_ago]
    if day_candidates:
        return max(day_candidates, key=lambda r: r["ts"])

    if records:
        return min(records, key=lambda r: r["ts"])

    return None


def estimate(history, current_amount, currency, now):
    """Estimate burn rate from ``history`` against the current balance.

    Args:
        history: Iterable of records already on disk (older than now).
        current_amount: Current balance amount.
        currency: Currency code of the current balance.
        now: Current Unix timestamp.

    Returns:
        A dict describing the burn-rate estimate. When the estimate is not
        useful, ``estimated_days_left`` is omitted and a ``reason`` is included.
    """
    same_currency = [
        r for r in history
        if r["currency"] == currency and r["ts"] < now
    ]

    if not same_currency:
        return {"confidence": "none", "reason": "insufficient_history"}

    point = _pick_comparison_point(same_currency, now)
    elapsed_seconds = now - point["ts"]
    elapsed_days = elapsed_seconds / _SECONDS_PER_DAY

    spend = point["amount"] - float(current_amount)
    if spend <= 0:
        reason = "balance_increased" if point["amount"] < float(current_amount) else "no_recent_spend"
        return {"confidence": "none", "reason": reason}

    amount_per_day = spend / elapsed_days
    estimated_days_left = int(float(current_amount) / amount_per_day)

    if elapsed_days >= 7:
        confidence = "high"
    elif elapsed_days >= 1 and len(same_currency) >= 3:
        confidence = "medium"
    else:
        confidence = "low"

    return {
        "amount_per_day": amount_per_day,
        "window_days": int(elapsed_days),
        "estimated_days_left": estimated_days_left,
        "confidence": confidence,
    }


def record_and_estimate(path, amount, currency, now=None):
    """Append a sample, prune history, and return a burn-rate estimate.

    Args:
        path: JSONL file path. ``~`` is expanded.
        amount: Current balance amount.
        currency: Currency code.
        now: Current Unix timestamp; defaults to ``time.time()``.

    Returns:
        Estimate dict from ``estimate()`` using the history *before* the new
        sample is appended.
    """
    now = time.time() if now is None else now
    now = int(now)
    full_path = _history_path(path)

    records = _read_jsonl(full_path)
    records = _prune(records, now)

    result = estimate(records, amount, currency, now)

    records.append({
        "ts": now,
        "amount": float(amount),
        "currency": str(currency),
    })
    records = _prune(records, now)
    _write_jsonl(full_path, records)

    return result
