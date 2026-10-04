"""Run state, atomic writes, lock, time helpers (#28)."""
from __future__ import annotations

import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

import bridgetest  # noqa: F401  (puts the package on sys.path)
from bridge import state


def entry(origin=None):
    return {"file": "/r/f", "root": "/g", "start": "/g", "run": "/g/.studio/reports/overnight-1",
            "pid": 4242, "started": "2026-10-03T22:14:05Z", "origin": origin}


class StateTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="state-")
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.paths = state.Paths(self.tmp)
        os.makedirs(self.paths.state_dir)

    def test_parse_ts_variants(self):
        want = 1791065645.0  # 2026-10-03T22:14:05Z
        self.assertEqual(state.parse_ts("2026-10-03T22:14:05Z"), want)
        self.assertAlmostEqual(state.parse_ts("2026-10-03T22:14:05.1Z"), want + 0.1, places=6)
        self.assertAlmostEqual(state.parse_ts("2026-10-03T22:14:05.123456789Z"), want + 0.123456789, places=6)
        self.assertEqual(state.parse_ts("2026-10-03T22:14:05+00:00"), want)
        self.assertAlmostEqual(state.parse_ts("2026-10-03T15:14:05.5-07:00"), want + 0.5, places=6)
        self.assertEqual(state.parse_ts("2026-10-04T00:14:05+0200"), want)
        self.assertEqual(state.parse_ts("2026-10-03T22:14:05"), want)
        for bad in ("yesterday", ""):
            with self.assertRaises(ValueError):
                state.parse_ts(bad)

    def test_fmt_since_floors_to_utc_z(self):
        self.assertEqual(state.fmt_since(1791065645.9), "2026-10-03T22:14:05Z")
        self.assertEqual(state.iso_now(1791065645.9), "2026-10-03T22:14:05Z")

    def test_run_key_format(self):
        a = state.run_key("/x/a/.studio/reports/overnight-20261003-2214", "/x/a")
        b = state.run_key("/x/a/.studio/reports/overnight-20261003-2214", "/x/b")
        self.assertRegex(a, r"^overnight-20261003-2214-[0-9a-f]{8}$")
        self.assertNotEqual(a, b)

    def test_atomic_write_leaves_no_temp_and_is_0600(self):
        p = os.path.join(self.paths.state_dir, "k.json")
        state.atomic_write_json(p, {"a": 1})
        state.atomic_write_json(p, {"a": 2})
        self.assertEqual(state.read_json(p), {"a": 2})
        self.assertEqual(os.listdir(self.paths.state_dir), ["k.json"])
        self.assertEqual(stat.S_IMODE(os.stat(p).st_mode), 0o600)
        self.assertEqual(state.read_json(os.path.join(self.tmp, "nope"), "dflt"), "dflt")
        with open(p, "w") as f:
            f.write("{torn")
        self.assertEqual(state.read_json(p, 7), 7)

    def test_retire_moves_state_and_appends_key(self):
        st = state.new_run_state("overnight-1-aaaaaaaa", entry(), 100.0)
        state.save_run(self.paths, st)
        self.assertEqual(state.tracked_keys(self.paths), ["overnight-1-aaaaaaaa"])
        self.assertEqual(state.load_run(self.paths, "overnight-1-aaaaaaaa")["pid"], 4242)
        state.retire(self.paths, st)
        self.assertEqual(state.tracked_keys(self.paths), [])
        self.assertIsNone(state.load_run(self.paths, "overnight-1-aaaaaaaa"))
        self.assertTrue(os.path.isfile(os.path.join(self.paths.retired_dir, "overnight-1-aaaaaaaa.json")))
        self.assertEqual(state.load_retired(self.paths), {"overnight-1-aaaaaaaa"})
        state.retire(self.paths, st)  # idempotent
        with open(self.paths.retired_file) as f:
            self.assertEqual(f.read().split(), ["overnight-1-aaaaaaaa"])

    def test_lock_busy_when_held(self):
        os.makedirs(self.paths.base, exist_ok=True)
        code = ("import fcntl,sys,time\nf=open(sys.argv[1],'a')\nfcntl.flock(f,fcntl.LOCK_EX)\n"
                "print('held',flush=True)\ntime.sleep(30)\n")
        p = subprocess.Popen([sys.executable, "-c", code, self.paths.lock], stdout=subprocess.PIPE)
        self.addCleanup(p.wait)
        self.addCleanup(p.kill)
        self.addCleanup(p.stdout.close)
        self.assertEqual(p.stdout.readline().strip(), b"held")
        with self.assertRaises(state.LockBusy):
            with state.bridge_lock(self.paths, blocking=False):
                pass
        p.kill()
        p.wait()
        with state.bridge_lock(self.paths, blocking=False):
            pass

    def test_new_run_state_has_every_key(self):
        st = state.new_run_state("k", entry("multica:t-1"), 1791000000.0)
        want = {"key", "pid", "started", "origin", "root", "run_dir", "adopted_at", "request", "run_issue",
                "mode", "stories", "story_desc", "story_failed", "story_recreated", "offset", "pending",
                "intended", "last_set", "hands_off", "held_back", "repair_stopped", "catchup", "cursors",
                "cursor_ts", "seen", "posted", "clock_offset", "journal", "ended", "gone_polls", "poll_fails",
                "retire_after_catchup", "retired", "delayed_for", "log_id", "released"}
        self.assertEqual(set(st), want)
        self.assertEqual(st["request"], {"state": "pending", "task": "t-1", "issue": None,
                                         "since": 1791000000.0})
        self.assertEqual(st["run_dir"], "/g/.studio/reports/overnight-1")
        self.assertIsNone(st["delayed_for"])
        json.dumps(st)

    def test_retire_saves_pending_changes(self):
        st = state.new_run_state("overnight-1-aaaaaaaa", entry(), 100.0)
        state.save_run(self.paths, st)
        st["offset"] = 777  # in memory only
        state.retire(self.paths, st)
        with open(os.path.join(self.paths.retired_dir, "overnight-1-aaaaaaaa.json")) as f:
            got = json.load(f)
        self.assertEqual((got["offset"], got["retired"]), (777, True))
        self.assertEqual(state.tracked_keys(self.paths), [])

    def test_new_dirs_are_0700(self):
        tmp = tempfile.mkdtemp(prefix="state-fresh-")
        self.addCleanup(shutil.rmtree, tmp, True)
        paths = state.Paths(tmp)
        st = state.new_run_state("overnight-1-aaaaaaaa", entry(), 100.0)
        state.save_run(paths, st)
        state.retire(paths, st)
        for d in (paths.base, paths.state_dir, paths.retired_dir):
            self.assertEqual(stat.S_IMODE(os.stat(d).st_mode), 0o700, d)

    def test_atomic_write_fsyncs_directory(self):
        real = os.fsync
        calls = []
        def spy(fd):
            calls.append(stat.S_ISDIR(os.fstat(fd).st_mode))
            return real(fd)
        with mock.patch("os.fsync", spy):
            state.atomic_write_json(os.path.join(self.tmp, "x.json"), {"a": 1})
        self.assertEqual(calls, [False, True])

    def test_ctx_holds_rows(self):
        c = state.Ctx("cfg", self.paths, "cli", "log", lambda k, t: None)
        self.assertEqual(c.rows, {})
        self.assertIs(c.now, time.time)


if __name__ == "__main__":
    unittest.main()
