import os
import tempfile
import unittest
from unittest import mock

from usage import credential_store


class TestClaudeCredentialStore(unittest.TestCase):
    def test_darwin_reads_keychain(self):
        completed = mock.Mock(
            stdout='{"claudeAiOauth":{"accessToken":"keychain-token"}}\n'
        )
        with mock.patch.object(
            credential_store.subprocess, "run", return_value=completed
        ) as run:
            blob = credential_store.read_claude_blob(platform="darwin")

        self.assertIn("keychain-token", blob)
        self.assertEqual(run.call_args.args[0][0], "security")

    def test_non_darwin_reads_config_file(self):
        with tempfile.TemporaryDirectory() as directory:
            path = os.path.join(directory, ".credentials.json")
            with open(path, "w") as handle:
                handle.write(
                    '{"claudeAiOauth":{"accessToken":"file-token"}}'
                )

            with mock.patch.dict(
                os.environ, {"CLAUDE_CONFIG_DIR": directory}, clear=False
            ):
                blob = credential_store.read_claude_blob(platform="win32")

        self.assertIn("file-token", blob)

    def test_missing_non_darwin_file_returns_none(self):
        with tempfile.TemporaryDirectory() as directory:
            missing = os.path.join(directory, "missing")
            with mock.patch.dict(
                os.environ, {"CLAUDE_CONFIG_DIR": missing}, clear=False
            ):
                blob = credential_store.read_claude_blob(platform="linux")

        self.assertIsNone(blob)
