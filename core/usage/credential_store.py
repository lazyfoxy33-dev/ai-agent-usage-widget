"""Platform-aware credential store for Claude Code (read + write).

Reading is always safe. Writing is used to persist a refreshed OAuth token so a
desktop-app-only user (whose token nothing else rotates) keeps live usage; it
updates the keychain item in place on macOS and atomically rewrites the
credential file elsewhere. See the Kimi refresh protocol in ``usage/kimi.py``.
"""

import getpass
import os
import subprocess
import sys
import tempfile


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


def write_claude_blob(blob, platform=None):
    """Persist the raw Claude credential JSON string to the platform store.

    macOS updates the keychain item in place (``security add-generic-password
    -U``); the password is passed as ``-w`` because the keychain CLI offers no
    stdin path for it. Other platforms atomically rewrite the credential file
    with owner-only permissions. Raises on failure so callers can fall back
    without corrupting the existing credential.
    """
    active_platform = sys.platform if platform is None else platform
    if active_platform == "darwin":
        completed = subprocess.run(
            [
                "security",
                "add-generic-password",
                "-U",
                "-a",
                getpass.getuser(),
                "-s",
                CLAUDE_KEYCHAIN_SERVICE,
                "-w",
                blob,
            ],
            capture_output=True,
            text=True,
            timeout=10,
        )
        # Avoid surfacing argv (which carries the blob) in any exception.
        if completed.returncode != 0:
            raise RuntimeError("Keychain write failed")
        return

    path = _claude_file_path()
    directory = os.path.dirname(path)
    os.makedirs(directory, exist_ok=True)
    fd, tmp = tempfile.mkstemp(
        prefix=".credentials.json.tmp.", dir=directory, text=True
    )
    try:
        os.chmod(tmp, 0o600)
        with os.fdopen(fd, "w") as handle:
            handle.write(blob)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp, path)
        os.chmod(path, 0o600)
    except Exception:
        try:
            os.close(fd)
        except OSError:
            pass
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
