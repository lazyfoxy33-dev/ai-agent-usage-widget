#!/usr/bin/env python3
"""Fail CI when credential material reaches this repository.

Scans every blob reachable from every ref (branches, tags, remote-tracking
refs) so that a secret added and then removed inside the same pull request is
still caught. Matches are reported masked: the scanner never prints a value.

CI scans the final tree plus every blob touched by the pushed range, so a
credential that was added and then removed inside one push is still caught.

Run locally with:

    python3 .github/scripts/secret_scan.py                      # tracked files, as committed
    python3 .github/scripts/secret_scan.py --range main...HEAD  # one range
    python3 .github/scripts/secret_scan.py --all                # full audit (may report
                                                                # long-removed history)
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys

# (name, pattern, hint). Patterns must never be relaxed to "fix" a failure:
# move the value into a Keychain entry, an environment variable, or a placeholder.
RULES: list[tuple[str, re.Pattern[bytes], str]] = [
    ("provider API key", re.compile(rb"sk-[A-Za-z0-9_\-]{20,}"), "rotate it and keep it out of the repo"),
    ("OpenRouter key", re.compile(rb"sk-or-v1-[A-Za-z0-9]{20,}"), "rotate it and keep it out of the repo"),
    ("Anthropic key", re.compile(rb"sk-ant-[A-Za-z0-9_\-]{20,}"), "rotate it and keep it out of the repo"),
    ("GitHub token", re.compile(rb"(gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})"), "revoke the token"),
    ("JWT", re.compile(rb"eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\."), "treat the token as compromised"),
    ("bearer literal", re.compile(rb"Bearer\s+[A-Za-z0-9_\-\.]{30,}"), "use config-file auth instead of an inline token"),
    ("private key", re.compile(rb"-----BEGIN [A-Z ]*PRIVATE KEY-----"), "never commit key material"),
    ("AWS access key", re.compile(rb"AKIA[0-9A-Z]{16}"), "rotate it"),
    ("Slack token", re.compile(rb"xox[baprs]-[A-Za-z0-9\-]{10,}"), "revoke the token"),
    (
        "cookie/session value",
        re.compile(rb"(session|cookie|cf_clearance|token)[\"']?\s*[:=]\s*[\"'][A-Za-z0-9%_\-\.]{30,}[\"']", re.I),
        "session credentials belong in the Keychain",
    ),
    (
        "harness credential",
        re.compile(rb"(DEEPSEEK_API_KEY|OPENROUTER_API_KEY|SILICONFLOW_API_KEY|KIMI_CODING_API_KEY)\s*:\s*[A-Za-z0-9_\-]{20,}"),
        "reference the key by name instead of storing the value",
    ),
    ("home directory path", re.compile(rb"/Users/[A-Za-z0-9._\-]+/"), "use ~ or $HOME"),
    (
        "personal email",
        re.compile(rb"[A-Za-z0-9._%+\-]+@(gmail|qq|outlook|hotmail|icloud|163|126|foxmail)\.", re.I),
        "use the GitHub noreply address",
    ),
    ("Apple team id", re.compile(rb"\b(?!YOUR)[A-Z0-9]{10}\b(?=[\"'\s]|$)"), None),  # refined below
    ("device identifier", re.compile(rb"\b[0-9A-F]{8}-[0-9A-F]{16}\b"), "remove the hardware id"),
]

# The generic 10-character token rule is only useful next to a team-id marker,
# so replace it with a contextual one.
RULES = [rule for rule in RULES if rule[0] != "Apple team id"]
RULES.append((
    "Apple team id",
    re.compile(rb"(team[_-]?id|TEAM_ID|_TEAM)[\"'\s:=]*([A-Z0-9]{10})\b", re.I),
    "use a YOUR_TEAM_ID placeholder",
))

PLACEHOLDERS = re.compile(
    rb"YOUR|EXAMPLE|PLACEHOLDER|XXXX|<.*>|\b(TEST|FAKE|DUMMY|SAMPLE|REDACTED|NOT[-_]?REAL)\b",
    re.I,
)


def mask(value: bytes) -> str:
    text = value.decode("utf-8", "replace").strip()
    if len(text) <= 8:
        return text[:2] + "…"
    return text[:4] + "…" + text[-2:]


def scan_blob(body: bytes, label: str, findings: list[tuple[str, str, str]]) -> None:
    if b"\x00" in body[:8000]:  # binary
        return
    for name, pattern, hint in RULES:
        for match in pattern.finditer(body):
            if PLACEHOLDERS.search(match.group(0)):
                continue
            findings.append((name, label, hint or ""))


def tracked_files() -> list[tuple[str, str]]:
    out = subprocess.run(["git", "ls-files"], capture_output=True, text=True, check=True).stdout
    return [(path, path) for path in out.split("\n") if path]


def blob_sources(rev_args: list[str]) -> list[tuple[str, str]]:
    """Every blob reachable from the given `git rev-list` arguments."""
    listed = subprocess.run(
        ["git", "rev-list", "--objects", *rev_args], capture_output=True, check=True
    ).stdout
    shas: list[str] = []
    names: dict[str, str] = {}
    for line in listed.split(b"\n"):
        if not line.strip():
            continue
        parts = line.split(b" ", 1)
        sha = parts[0].decode()
        shas.append(sha)
        if len(parts) > 1:
            names[sha] = parts[1].decode("utf-8", "replace")
    if not shas:
        return []
    batch = subprocess.run(
        ["git", "cat-file", "--batch"], input="\n".join(shas).encode(), capture_output=True, check=True
    ).stdout
    blobs: list[tuple[str, str]] = []
    index = 0
    while index < len(batch):
        newline = batch.find(b"\n", index)
        if newline == -1:
            break
        header = batch[index:newline].split()
        if len(header) < 3:
            break
        sha, kind, size = header[0].decode(), header[1].decode(), int(header[2])
        body = batch[newline + 1 : newline + 1 + size]
        index = newline + 1 + size + 1
        if kind == "blob":
            blobs.append((names.get(sha, sha[:8]), body))
    return blobs


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--all", action="store_true", help="scan every ref (full audit)")
    parser.add_argument("--range", help="scan the blobs touched by a git revision range")
    args = parser.parse_args()

    findings: list[tuple[str, str, str]] = []

    # Always check the tree as committed; ranges additionally catch secrets that
    # were added and removed inside the same push.
    sources = [(label, open(path, "rb").read()) for path, label in tracked_files() if _readable(path)]

    if args.all:
        sources += blob_sources(["--all"])
    elif args.range:
        sources += blob_sources([args.range])

    for label, body in sources:
        scan_blob(body, label, findings)

    if not findings:
        print(f"secret scan: clean ({len(sources)} file/blob contents checked)")
        return 0

    print(f"secret scan: {len(findings)} finding(s)\n")
    for name, label, hint in findings:
        print(f"  {name}: {label} — {hint}")
    print("\nRemove the value, rotate the credential, and re-run. See AGENTS.md.")
    return 1


def _readable(path: str) -> bool:
    try:
        with open(path, "rb"):
            return True
    except OSError:
        return False


if __name__ == "__main__":
    sys.exit(main())
