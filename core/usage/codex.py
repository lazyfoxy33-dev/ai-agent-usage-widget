"""Parse Codex CLI session files into 5h / weekly usage."""
import glob
import json
import os
import shutil
import subprocess
import tempfile
import time
from contextlib import contextmanager
from datetime import datetime

from . import config as usage_config

DEFAULT_DIRS = [
    os.path.expanduser("~/.codex/sessions"),
    os.path.expanduser("~/.codex/archived_sessions"),
]
REFRESH_THROTTLE_PATH = os.path.expanduser(
    "~/.cache/usage-widget/codex-refresh.json"
)
_LOCK_STALE_SECONDS = 10
_LOCK_WAIT_SECONDS = 2


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


@contextmanager
def _portable_lock(path):
    lock_dir = path + ".lock"
    deadline = time.monotonic() + _LOCK_WAIT_SECONDS
    while True:
        try:
            os.mkdir(lock_dir)
            break
        except FileExistsError:
            try:
                if time.time() - os.path.getmtime(lock_dir) > _LOCK_STALE_SECONDS:
                    os.rmdir(lock_dir)
                    continue
            except OSError:
                pass
            if time.monotonic() >= deadline:
                raise TimeoutError("Timed out waiting for Codex refresh lock")
            time.sleep(0.05)
    try:
        yield
    finally:
        try:
            os.rmdir(lock_dir)
        except OSError:
            pass


def _write_json_atomic(path, data):
    directory = os.path.dirname(path)
    fd, temporary = tempfile.mkstemp(
        prefix=os.path.basename(path) + ".tmp.",
        dir=directory,
        text=True,
    )
    try:
        with os.fdopen(fd, "w") as handle:
            json.dump(data, handle)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    except Exception:
        try:
            os.close(fd)
        except OSError:
            pass
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise


def _claim_refresh_slot(path, now, interval):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    try:
        with _portable_lock(path):
            try:
                with open(path) as handle:
                    data = json.load(handle)
                last_refresh = float(data.get("started_at", 0))
            except (OSError, ValueError, TypeError, AttributeError):
                last_refresh = 0
            if now - last_refresh < interval:
                return False
            _write_json_atomic(path, {"started_at": int(now)})
            return True
    except TimeoutError:
        return False


def _codex_executable():
    found = shutil.which("codex")
    if found:
        return found
    candidates = [
        os.path.expanduser("~/.local/bin/codex"),
        "/Applications/Codex.app/Contents/Resources/codex",
    ]
    for candidate in candidates:
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate
    return None


def maybe_active_refresh(
    as_of,
    now=None,
    settings=None,
    throttle_path=None,
):
    """Start an opt-in background Codex probe when data is old."""
    settings = settings or usage_config.load_config()
    if settings.get("codex_active_refresh") is not True:
        return False

    now = time.time() if now is None else now
    interval = max(
        usage_config.MIN_CODEX_REFRESH_INTERVAL,
        int(settings.get(
            "codex_refresh_interval_seconds",
            usage_config.DEFAULT_CODEX_REFRESH_INTERVAL,
        )),
    )
    if as_of is not None and now - float(as_of) < interval:
        return False

    executable = _codex_executable()
    if executable is None:
        return False

    throttle_path = throttle_path or REFRESH_THROTTLE_PATH
    if not _claim_refresh_slot(throttle_path, now, interval):
        return False

    command = [
        executable, "exec",
        "--skip-git-repo-check",
        "--sandbox", "read-only",
        "--color", "never",
        "Reply with exactly: ok",
    ]
    try:
        subprocess.Popen(
            command,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            close_fds=True,
            start_new_session=True,
        )
    except OSError:
        return False
    return True
