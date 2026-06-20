import os
import pathlib
import tempfile
import unittest
from unittest import mock
from usage import codex

FIX = os.path.join(os.path.dirname(__file__), "fixtures")

# Unix timestamp of the latest fixture event: 2026-06-05T10:38:33.259Z
# python3 -c "from datetime import datetime,timezone; print(int(datetime.fromisoformat('2026-06-05T10:38:33.259+00:00').timestamp()))"
_LATEST_EVENT_TS = int(__import__('datetime').datetime.fromisoformat(
    "2026-06-05T10:38:33.259+00:00").timestamp())


class TestCodex(unittest.TestCase):
    def test_picks_latest_event_by_timestamp(self):
        # Pass a past `now` so windows are not stale
        result = codex.parse_codex(session_dirs=[FIX], days=3650, now=1000)
        self.assertTrue(result["ok"])
        # 最新一条 timestamp 是 10:38:33，pct 应为 7 / 22
        self.assertEqual(result["five_h"]["pct"], 7)
        self.assertEqual(result["five_h"]["resets_at"], 1780673367)
        self.assertEqual(result["weekly"]["pct"], 22)
        self.assertEqual(result["weekly"]["resets_at"], 1781143663)

    def test_maps_windows_by_minutes_not_order(self):
        # primary=300min->5h, secondary=10080min->weekly
        result = codex.parse_codex(session_dirs=[FIX], days=3650, now=1000)
        self.assertEqual(result["five_h"]["pct"], 7)   # 300min
        self.assertEqual(result["weekly"]["pct"], 22)  # 10080min

    def test_no_data_when_no_files(self):
        result = codex.parse_codex(session_dirs=["/nonexistent/path"], days=3650)
        self.assertFalse(result["ok"])
        self.assertEqual(result["reason"], "no_data")

    def test_old_files_skipped_by_mtime_cutoff(self):
        """Files whose mtime is older than `days` days ago must be skipped."""
        line = (
            '{"timestamp":"2020-01-01T00:00:00.000Z","type":"event_msg",'
            '"payload":{"type":"token_count","rate_limits":{'
            '"primary":{"used_percent":5.0,"window_minutes":300,"resets_at":9999},'
            '"secondary":{"used_percent":10.0,"window_minutes":10080,"resets_at":9999}}}}\n'
        )
        with tempfile.TemporaryDirectory() as tmpdir:
            path = os.path.join(tmpdir, "old_session.jsonl")
            with open(path, "w") as f:
                f.write(line)
            # Set mtime to 30 days in the past (older than days=14 cutoff)
            old_time = os.path.getmtime(path) - 30 * 86400
            os.utime(path, (old_time, old_time))
            result = codex.parse_codex(session_dirs=[tmpdir], days=14)
        self.assertFalse(result["ok"])
        self.assertEqual(result["reason"], "no_data")

    def test_skips_credits_only_events_with_null_windows(self):
        """Newer Codex CLIs interleave credits-only events (limit_id
        "premium") whose primary/secondary are null. A later null event must
        not mask the real windowed usage from a "codex" event."""
        windowed = (
            '{"timestamp":"2026-06-12T11:00:00.000Z","type":"event_msg",'
            '"payload":{"type":"token_count","rate_limits":{"limit_id":"codex",'
            '"primary":{"used_percent":82.0,"window_minutes":300,"resets_at":9999},'
            '"secondary":{"used_percent":50.0,"window_minutes":10080,"resets_at":9999}}}}\n'
        )
        credits_only = (
            '{"timestamp":"2026-06-12T11:57:31.000Z","type":"event_msg",'
            '"payload":{"type":"token_count","rate_limits":{"limit_id":"premium",'
            '"primary":null,"secondary":null,'
            '"credits":{"has_credits":false,"unlimited":false,"balance":"0"}}}}\n'
        )
        with tempfile.TemporaryDirectory() as tmpdir:
            path = os.path.join(tmpdir, "session.jsonl")
            with open(path, "w") as f:
                f.write(windowed)
                f.write(credits_only)
            result = codex.parse_codex(session_dirs=[tmpdir], days=3650, now=1000)
        self.assertTrue(result["ok"])
        self.assertEqual(result["five_h"]["pct"], 82)
        self.assertEqual(result["weekly"]["pct"], 50)

    # --- Freshness / staleness tests ---

    def test_as_of_equals_latest_event_timestamp(self):
        result = codex.parse_codex(session_dirs=[FIX], days=3650, now=1000)
        self.assertTrue(result["ok"])
        self.assertEqual(result["as_of"], _LATEST_EVENT_TS)

    def test_stale_true_when_now_far_future(self):
        # resets_at values in fixture: 1780673367, 1781143663 — use now >> both
        now_future = 9_999_999_999
        result = codex.parse_codex(session_dirs=[FIX], days=3650, now=now_future)
        self.assertTrue(result["ok"])
        self.assertTrue(result["five_h"]["stale"])
        self.assertTrue(result["weekly"]["stale"])

    def test_stale_false_when_now_far_past(self):
        # resets_at values in fixture: 1780673367, 1781143663 — use now << both
        now_past = 1000
        result = codex.parse_codex(session_dirs=[FIX], days=3650, now=now_past)
        self.assertTrue(result["ok"])
        self.assertFalse(result["five_h"]["stale"])
        self.assertFalse(result["weekly"]["stale"])


class TestCodexLive(unittest.TestCase):
    SNAP = {
        "limitId": "codex",
        "primary": {"usedPercent": 1.4, "windowDurationMins": 300, "resetsAt": 2000},
        "secondary": {"usedPercent": 16.0, "windowDurationMins": 10080, "resetsAt": 9999},
    }

    def test_parse_maps_windows_by_duration(self):
        r = codex.parse_rate_limit_snapshot(self.SNAP, now=1000)
        self.assertTrue(r["ok"])
        self.assertEqual(r["five_h"]["pct"], 1)
        self.assertEqual(r["five_h"]["resets_at"], 2000)
        self.assertEqual(r["weekly"]["pct"], 16)
        self.assertEqual(r["weekly"]["resets_at"], 9999)
        self.assertEqual(r["as_of"], 1000)

    def test_parse_maps_by_duration_not_position(self):
        snap = {
            "primary": {"usedPercent": 16, "windowDurationMins": 10080, "resetsAt": 9},
            "secondary": {"usedPercent": 1, "windowDurationMins": 300, "resetsAt": 8},
        }
        r = codex.parse_rate_limit_snapshot(snap, now=1)
        self.assertEqual(r["five_h"]["pct"], 1)
        self.assertEqual(r["weekly"]["pct"], 16)

    def test_parse_null_windows_returns_no_data(self):
        snap = {"limitId": "premium", "primary": None, "secondary": None,
                "credits": {"balance": "0"}}
        r = codex.parse_rate_limit_snapshot(snap, now=1)
        self.assertFalse(r["ok"])
        self.assertEqual(r["reason"], "no_data")

    def test_parse_marks_stale_when_window_already_reset(self):
        snap = {
            "primary": {"usedPercent": 5, "windowDurationMins": 300, "resetsAt": 50},
            "secondary": {"usedPercent": 5, "windowDurationMins": 10080, "resetsAt": 9999},
        }
        r = codex.parse_rate_limit_snapshot(snap, now=100)
        self.assertTrue(r["five_h"]["stale"])
        self.assertFalse(r["weekly"]["stale"])

    def test_fetch_live_uses_snapshot(self):
        with mock.patch.object(codex, "_app_server_read_snapshot",
                               return_value=self.SNAP):
            r = codex.fetch_codex_live(now=1000)
        self.assertTrue(r["ok"])
        self.assertEqual(r["five_h"]["pct"], 1)
        self.assertEqual(r["weekly"]["pct"], 16)

    def test_fetch_live_failure_returns_error(self):
        with mock.patch.object(codex, "_app_server_read_snapshot",
                               return_value=None):
            r = codex.fetch_codex_live(now=1000)
        self.assertFalse(r["ok"])
        self.assertEqual(r["reason"], "error")


class TestCodexActiveRefresh(unittest.TestCase):
    def test_module_does_not_require_posix_fcntl(self):
        source = pathlib.Path(codex.__file__).read_text()
        self.assertNotIn("import fcntl", source)

    def test_default_config_never_starts_a_model_request(self):
        with mock.patch.object(codex.subprocess, "Popen") as popen:
            started = codex.maybe_active_refresh(
                as_of=None,
                settings={
                    "codex_active_refresh": False,
                    "codex_refresh_interval_seconds": 1800,
                },
            )

        self.assertFalse(started)
        popen.assert_not_called()

    def test_explicit_opt_in_starts_read_only_background_probe(self):
        with tempfile.TemporaryDirectory() as tmp, \
             mock.patch.object(codex, "_codex_executable",
                               return_value="codex"), \
             mock.patch.object(codex.subprocess, "Popen") as popen:
            started = codex.maybe_active_refresh(
                as_of=1000,
                now=3000,
                settings={
                    "codex_active_refresh": True,
                    "codex_refresh_interval_seconds": 1800,
                },
                throttle_path=os.path.join(tmp, "refresh.json"),
            )

        self.assertTrue(started)
        command = popen.call_args.args[0]
        self.assertEqual(command[:2], ["codex", "exec"])
        self.assertIn("read-only", command)
        self.assertEqual(
            popen.call_args.kwargs["stdout"],
            codex.subprocess.DEVNULL,
        )

    def test_recent_session_skips_probe(self):
        with mock.patch.object(codex.subprocess, "Popen") as popen:
            started = codex.maybe_active_refresh(
                as_of=2500,
                now=3000,
                settings={
                    "codex_active_refresh": True,
                    "codex_refresh_interval_seconds": 1800,
                },
            )

        self.assertFalse(started)
        popen.assert_not_called()

    def test_throttle_prevents_duplicate_probe(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "refresh.json")
            settings = {
                "codex_active_refresh": True,
                "codex_refresh_interval_seconds": 1800,
            }
            with mock.patch.object(codex, "_codex_executable", return_value="codex"), \
                 mock.patch.object(codex.subprocess, "Popen") as popen:
                first = codex.maybe_active_refresh(
                    None, now=3000, settings=settings, throttle_path=path
                )
                second = codex.maybe_active_refresh(
                    None, now=3001, settings=settings, throttle_path=path
                )

        self.assertTrue(first)
        self.assertFalse(second)
        self.assertEqual(popen.call_count, 1)

    def test_missing_codex_binary_skips_without_claiming_throttle(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "refresh.json")
            with mock.patch.object(codex, "_codex_executable",
                                   return_value=None), \
                 mock.patch.object(codex.subprocess, "Popen") as popen:
                started = codex.maybe_active_refresh(
                    None,
                    now=3000,
                    settings={
                        "codex_active_refresh": True,
                        "codex_refresh_interval_seconds": 1800,
                    },
                    throttle_path=path,
                )

        self.assertFalse(started)
        self.assertFalse(os.path.exists(path))
        popen.assert_not_called()
