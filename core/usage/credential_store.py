"""Platform-aware, read-only credential source for Claude Code."""

import os
import subprocess
import sys


CLAUDE_KEYCHAIN_SERVICE = "Claude Code-credentials"


def _claude_file_path():
    base = os.environ.get("CLAUDE_CONFIG_DIR") or "~/.claude"
    return os.path.join(os.path.expanduser(base), ".credentials.json")


def read_claude_blob(platform=None):
    """Return the raw Claude credential JSON string, or None."""
    active_platform = sys.platform if platform is None else platform
    if active_platform == "darwin":
        try:
            completed = subprocess.run(
                [
                    "security",
                    "find-generic-password",
                    "-s",
                    CLAUDE_KEYCHAIN_SERVICE,
                    "-w",
                ],
                capture_output=True,
                text=True,
                timeout=10,
            )
            return completed.stdout.strip() or None
        except (OSError, subprocess.SubprocessError):
            return None

    try:
        with open(_claude_file_path()) as handle:
            return handle.read().strip() or None
    except OSError:
        return None
