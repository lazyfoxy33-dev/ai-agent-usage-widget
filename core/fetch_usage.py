#!/usr/bin/env python3
"""Entry point for the Übersicht widget. Prints combined usage JSON to stdout."""
import json
import os
import time

from usage import codex, claude, kimi
from usage import cache

CACHE_PATH = os.path.expanduser("~/.cache/usage-widget/claude.json")
KIMI_CACHE_PATH = os.path.expanduser("~/.cache/usage-widget/kimi.json")
CACHE_TTL = 300  # 5 min
CODEX_FRESH_TTL = 1800  # 30 min


def _fresh_result(data, fetched_at):
    result = dict(data)
    result["fetched_at"] = int(fetched_at)
    result["live"] = True
    return result


def _failed_result(data):
    result = dict(data)
    result["fetched_at"] = None
    result["live"] = False
    return result


def _provider_with_cache(path, fetch):
    cached = cache.read_entry(path, ttl=CACHE_TTL)
    if cached is not None:
        return _fresh_result(cached["data"], cached["ts"])

    result = fetch()
    if result.get("ok"):
        fetched_at = int(time.time())
        result = _fresh_result(result, fetched_at)
        cache.write(path, result, now=fetched_at)
        return result

    stale = cache.read_stale_entry(path)
    if stale is None:
        return _failed_result(result)

    fallback = dict(stale["data"])
    fallback["reason"] = "stale"
    fallback["upstream_reason"] = result.get("reason", "error")
    fallback["fetched_at"] = int(stale["ts"])
    fallback["live"] = False
    return fallback


def claude_with_cache():
    return _provider_with_cache(CACHE_PATH, claude.fetch_claude)


def kimi_with_cache():
    return _provider_with_cache(KIMI_CACHE_PATH, kimi.fetch_kimi)


def codex_result(now=None):
    now = time.time() if now is None else now
    result = codex.parse_codex()
    if not result.get("ok"):
        codex.maybe_active_refresh(None, now=now)
        return _failed_result(result)
    fetched_at = result.get("as_of")
    codex.maybe_active_refresh(fetched_at, now=now)
    normalized = dict(result)
    normalized["fetched_at"] = int(fetched_at) if fetched_at is not None else None
    normalized["live"] = (
        fetched_at is not None and now - float(fetched_at) <= CODEX_FRESH_TTL
    )
    return normalized


def _ensure_contract(data):
    result = dict(data)
    result.setdefault("fetched_at", None)
    result.setdefault("live", False)
    return result


def build_payload():
    return json.dumps({
        "schema_version": 1,
        "codex": _ensure_contract(codex_result()),
        "claude": _ensure_contract(claude_with_cache()),
        "kimi": _ensure_contract(kimi_with_cache()),
    })


if __name__ == "__main__":
    print(build_payload())
