#!/usr/bin/env python3
"""Entry point for the Übersicht widget. Prints combined usage JSON to stdout."""
import json
import os

from usage import codex, claude
from usage import cache

CACHE_PATH = os.path.expanduser("~/.cache/usage-widget/claude.json")
CACHE_TTL = 300  # 5 min


def claude_with_cache():
    cached = cache.read(CACHE_PATH, ttl=CACHE_TTL)
    if cached is not None:
        return cached
    result = claude.fetch_claude()
    if result.get("ok"):
        cache.write(CACHE_PATH, result)
        return result
    # API failed: fall back to stale cache if any, marked stale
    stale = cache.read_stale(CACHE_PATH)
    if stale is not None:
        stale = dict(stale)
        stale["reason"] = "stale"
        return stale
    return result


def build_payload():
    return json.dumps({
        "codex": codex.parse_codex(),
        "claude": claude_with_cache(),
    })


if __name__ == "__main__":
    print(build_payload())
