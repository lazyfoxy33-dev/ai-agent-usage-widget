"""Tiny TTL file cache (stdlib only)."""
import json
import os
import time


def write(path, data, now=None):
    now = time.time() if now is None else now
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump({"ts": now, "data": data}, f)
    os.replace(tmp, path)


def _load(path):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def read(path, ttl, now=None):
    """Return cached data if younger than ttl seconds, else None."""
    now = time.time() if now is None else now
    blob = _load(path)
    if not blob:
        return None
    if now - blob.get("ts", 0) > ttl:
        return None
    return blob.get("data")


def read_stale(path):
    """Return cached data regardless of age, else None."""
    blob = _load(path)
    return blob.get("data") if blob else None
