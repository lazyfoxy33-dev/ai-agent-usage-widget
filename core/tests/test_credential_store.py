import json
import os
import stat
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


class TestClaudeCredentialWrite(unittest.TestCase):
    def test_darwin_updates_keychain_in_place(self):
        completed = mock.Mock(returncode=0)
        with mock.patch.object(
            credential_store.subprocess, "run", return_value=completed
        ) as run:
            credential_store.write_claude_blob('{"claudeAiOauth":{}}', platform="darwin")

        argv = run.call_args.args[0]
        self.assertEqual(argv[0], "security")
        self.assertIn("add-generic-password", argv)
        self.assertIn("-U", argv)
        self.assertIn(credential_store.CLAUDE_KEYCHAIN_SERVICE, argv)

    def test_darwin_failure_raises_without_leaking_argv(self):
        completed = mock.Mock(returncode=1)
        with mock.patch.object(
            credential_store.subprocess, "run", return_value=completed
        ):
            with self.assertRaises(RuntimeError) as ctx:
                credential_store.write_claude_blob("secret-blob", platform="darwin")
        self.assertNotIn("secret-blob", str(ctx.exception))

    def test_non_darwin_writes_atomically_and_tightens_mode(self):
        blob = '{"claudeAiOauth":{"accessToken":"new"},"other":"keep"}'
        with tempfile.TemporaryDirectory() as directory:
            with mock.patch.dict(
                os.environ, {"CLAUDE_CONFIG_DIR": directory}, clear=False
            ):
                credential_store.write_claude_blob(blob, platform="linux")
                path = os.path.join(directory, ".credentials.json")
                with open(path) as handle:
                    stored = json.load(handle)

            self.assertEqual(stored["claudeAiOauth"]["accessToken"], "new")
            self.assertEqual(stored["other"], "keep")
            self.assertEqual(stat.S_IMODE(os.stat(path).st_mode), 0o600)
