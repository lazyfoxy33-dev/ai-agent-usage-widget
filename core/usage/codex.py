"""Parse Codex CLI session files into 5h / weekly usage."""
import glob
import json
import os
import time
from datetime import datetime

DEFAULT_DIRS = [
    os.path.expanduser("~/.codex/sessions"),
    os.path.expanduser("~/.codex/archived_sessions"),
]


def _parse_ts(s):
    # "2026-06-05T10:38:33.259Z" -> aware datetime
    return datetime.fromisoformat(s.replace("Z", "+00:00"))


def _iter_rate_limit_events(session_dirs, days=14):
    """Yield (timestamp_datetime, rate_limits_dict) for every token_count event.

    Files whose filesystem mtime is older than *days* days before now are
    skipped entirely, avoiding a full re-read of stale Codex history on every
    refresh cycle.
    """
    cutoff = time.time() - days * 86400
    for d in session_dirs:
        for path in glob.glob(os.path.join(d, "**", "*.jsonl"), recursive=True):
            try:
                if os.path.getmtime(path) < cutoff:
                    continue
                with open(path, "r", errors="ignore") as f:
                    for line in f:
                        if "rate_limits" not in line:
                            continue
                        try:
                            obj = json.loads(line)
                        except ValueError:
                            continue
                        payload = obj.get("payload") or {}
                        if payload.get("type") != "token_count":
                            continue
                        rl = payload.get("rate_limits")
                        ts = obj.get("timestamp")
                        if not rl or not ts:
                            continue
                        try:
                            yield _parse_ts(ts), rl
                        except ValueError:
                            continue
            except OSError:
                continue


def _window(rl, minutes):
    """Return the primary/secondary block whose window_minutes == minutes."""
    for key in ("primary", "secondary"):
        block = rl.get(key)
        if block and block.get("window_minutes") == minutes:
            return block
    # fallback by position: primary=5h, secondary=weekly
    return rl.get("primary" if minutes == 300 else "secondary")


def parse_codex(session_dirs=None, days=14, now=None):
    """Return latest 5h/weekly usage from Codex sessions, or {ok:False}.

    now: unix timestamp used for staleness check (default: time.time()).
    Each window dict includes a ``stale`` bool: True when resets_at < now,
    meaning the window has already reset and the percent figure is outdated.
    Top-level ``as_of`` is the unix timestamp of the latest event processed.
    """
    if now is None:
        now = time.time()
    dirs = session_dirs if session_dirs is not None else DEFAULT_DIRS
    latest = None
    for ts, rl in _iter_rate_limit_events(dirs, days=days):
        if latest is None or ts > latest[0]:
            latest = (ts, rl)
    if latest is None:
        return {"ok": False, "reason": "no_data"}
    latest_ts, rl = latest
    five = _window(rl, 300)
    week = _window(rl, 10080)
    if not five or not week:
        return {"ok": False, "reason": "no_data"}
    # as_of: unix timestamp of the latest event's datetime
    as_of = int(latest_ts.timestamp())
    return {
        "ok": True,
        "as_of": as_of,
        "five_h": {
            "pct": round(five["used_percent"]),
            "resets_at": five["resets_at"],
            "stale": five["resets_at"] < now,
        },
        "weekly": {
            "pct": round(week["used_percent"]),
            "resets_at": week["resets_at"],
            "stale": week["resets_at"] < now,
        },
    }
