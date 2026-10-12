"""JSONL balance history and burn-rate estimation.

History files contain only compact, non-secret records:
    {"ts": 1781234567, "amount": 88.88, "currency": "USD"}
"""
import json
import os
import time

# The burn rate averages recent behaviour only: a week-old balance says nothing
# about today's pace, so samples older than the window are not used at all.
_WINDOW_SECONDS = 24 * 3600
# Below this a day-scale estimate is meaningless (a handful of minutes cannot
# establish a daily burn rate).
_MIN_SPAN_SECONDS = 6 * 3600
# Keep a week of samples; longer history is never consulted.
_MAX_AGE_DAYS = 7
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


def _recent_point(records, now):
    """The oldest sample inside the recent window.

    Everything older than the window is ignored — the estimate is an average of
    recent behaviour, not of the account's whole history. When the history is
    shorter than the window this is simply the oldest sample, so a young history
    still produces an estimate (flagged as low confidence).
    """
    cutoff = now - _WINDOW_SECONDS
    window = [r for r in records if cutoff <= r["ts"] <= now]
    if not window:
        return None
    return min(window, key=lambda r: r["ts"])


def estimate(history, current_amount, currency, now):
    """Estimate burn rate from ``history`` against the current balance.

    Args:
        history: Iterable of records already on disk (older than now).
        current_amount: Current balance amount.
        currency: Currency code of the current balance.
        now: Current Unix timestamp.

    The comparison point is the oldest sample inside the trailing 24-hour window,
    so the rate reflects recent behaviour and never a week-old balance.

    Returns:
        A dict describing the burn-rate estimate. When the estimate is not
        useful, ``estimated_days_left`` is omitted and a ``reason`` is included.
    """
    same_currency = [
        r for r in history
        if r["currency"] == currency and r["ts"] <= now
    ]

    point = _recent_point(same_currency, now)
    if point is None or now - point["ts"] < _MIN_SPAN_SECONDS:
        return {"confidence": "none", "reason": "insufficient_history"}

    elapsed_seconds = now - point["ts"]
    elapsed_days = elapsed_seconds / _SECONDS_PER_DAY

    spend = point["amount"] - float(current_amount)
    if spend <= 0:
        reason = "balance_increased" if point["amount"] < float(current_amount) else "no_recent_spend"
        return {"confidence": "none", "reason": reason}

    amount_per_day = spend / elapsed_days
    estimated_days_left = int(float(current_amount) / amount_per_day)

    # A near-full day of samples is as good as this gets; more history is not used.
    confidence = "medium" if elapsed_seconds >= 18 * 3600 else "low"

    return {
        "amount_per_day": amount_per_day,
        # Rounded so a ~23-hour window still reads as "近 1 日".
        "window_days": int(round(elapsed_days)),
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
