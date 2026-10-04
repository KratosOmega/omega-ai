"""The studio side: registry, liveness, links, event reader, verb calls (#28)."""
from __future__ import annotations

import json
import os
import subprocess
import time
from unittest import mock

import bridgetest
from bridge import state, studio
from bridgetest import BridgeCase, ev, make_project, make_run

STUB = os.path.join(bridgetest.TESTS, "stub-studio-overnight")


class StudioTest(BridgeCase):
    def setUp(self):
        super().setUp()
        self.root = make_project(self.tmp, "game")
        self.paths = state.Paths(self.home)

    def test_read_registry_parses_and_skips_malformed(self):
        r = make_run(self.home, self.root)
        reg = r.registry
        with open(os.path.join(reg, "overnight-bad-1"), "w") as f:
            f.write("root=/x\nrun=/y\npid=abc\n")
        with open(os.path.join(reg, "overnight-noroot-2"), "w") as f:
            f.write("run=/y\npid=3\n")
        with open(os.path.join(reg, "overnight-dup-3"), "w") as f:
            f.write("root=/a\nroot=/b\nrun=/y\npid=3\nstart=/s\nstarted=t\n")
        r.end_entry()  # runs/last must never be read
        rows = studio.read_registry(self.home)
        self.assertEqual([x["root"] for x in rows], ["/a"])
        self.assertEqual(rows[0]["pid"], 3)
        self.assertEqual(set(rows[0]), {"file", "root", "start", "run", "pid", "started", "origin"})
        self.assertEqual(studio.read_registry(os.path.join(self.tmp, "nohome")), [])
        r2 = make_run(self.home, self.root, basename="overnight-20261004-0100")
        row = [x for x in studio.read_registry(self.home) if x["pid"] == r2.pid][0]
        self.assertEqual(row["run"], r2.run_dir)
        self.assertEqual(row["file"], r2.entry)

    def test_read_registry_origin(self):
        r1 = make_run(self.home, self.root, basename="overnight-a", origin="multica:t-1")
        r2 = make_run(self.home, self.root, basename="overnight-b")
        r3 = make_run(self.home, self.root, basename="overnight-c", origin="other:x")
        by = {x["pid"]: x["origin"] for x in studio.read_registry(self.home)}
        self.assertEqual(by, {r1.pid: "multica:t-1", r2.pid: None, r3.pid: "other:x"})

    def test_origin_task(self):
        self.assertEqual(studio.origin_task("multica:01a1-x"), "01a1-x")
        for bad in (None, "", "other:x", "multica:", "MULTICA:x", "multica:a.b", "multica:a:b"):
            self.assertIsNone(studio.origin_task(bad), bad)

    def test_new_run_state_request_from_origin(self):
        entry = {"file": "f", "root": "/g", "start": "/g", "run": "/g/r", "pid": 1, "started": "s"}
        a = state.new_run_state("k", dict(entry, origin="multica:t-9"), 5.0)
        self.assertEqual((a["request"]["state"], a["request"]["task"]), ("pending", "t-9"))
        b = state.new_run_state("k", dict(entry, origin=None), 5.0)
        self.assertEqual((b["request"]["state"], b["request"]["task"]), ("none", None))
        c = state.new_run_state("k", dict(entry, origin="other:x"), 5.0)
        self.assertEqual(c["request"]["state"], "none")
        self.assertEqual(c["origin"], "other:x")

    def test_runner_live_for_studio_dummy(self):
        r = make_run(self.home, self.root)
        self.assertTrue(studio.runner_live(r.pid))
        r.kill()
        self.assertFalse(studio.runner_live(r.pid))

    def test_pid_reused_by_other_process(self):
        p = subprocess.Popen(["sleep", "60"])
        self.addCleanup(p.wait)
        self.addCleanup(p.kill)
        self.assertFalse(studio.runner_live(p.pid))
        p.kill()
        p.wait()
        self.assertFalse(studio.runner_live(p.pid))
        self.assertFalse(studio.runner_live(0))

    def test_read_link_and_prune(self):
        os.makedirs(self.paths.links)
        now = 1791065645.0

        def link(name, text, age=None):
            p = os.path.join(self.paths.links, name)
            with open(p, "w") as f:
                f.write(text)
            if age is not None:
                os.utime(p, (now - age, now - age))
        link("t1", "root=/g\ntask=t1\nagent=a1\nworkdir=/w/omeg-4-6d25f8ec1ce3/workdir\n"
                   "written=2026-10-03T22:14:05Z\n")
        link("t2", "root=/g\nagent=a1\n")
        link("old", "task=old\nwritten=2026-10-01T00:00:00Z\n")
        link("oldmt", "task=oldmt\n", age=25 * 3600)
        link("fresh", "task=fresh\n", age=3600)
        l1 = studio.read_link(self.paths, "t1")
        self.assertEqual((l1["task"], l1["root"], l1["agent"]), ("t1", "/g", "a1"))
        self.assertIsNone(studio.read_link(self.paths, "t2"))
        self.assertIsNone(studio.read_link(self.paths, "missing"))
        studio.prune_links(self.paths, now)
        self.assertEqual(sorted(os.listdir(self.paths.links)), ["fresh", "t1", "t2"])
        studio.delete_link(self.paths, "t1")
        studio.delete_link(self.paths, "t1")
        self.assertFalse(os.path.exists(os.path.join(self.paths.links, "t1")))

    def test_issue_from_workdir(self):
        f = studio.issue_from_workdir
        self.assertEqual(f("/x/omeg-4-6d25f8ec1ce3/workdir"), "OMEG-4")
        self.assertEqual(f("/x/ab2-17-6d25f8ec1ce3/workdir"), "AB2-17")
        self.assertEqual(f("/x/OMEG-4-6D25F8EC1CE3/workdir"), "OMEG-4")
        self.assertIsNone(f("/x/omeg-4/workdir"))
        self.assertIsNone(f("/x/omeg-4-zzz/workdir"))

    def test_read_lines_complete_only(self):
        r = make_run(self.home, self.root)
        r.append(ev("run_started", mode="single", why="é—ü"))
        r.append_raw('{"v":1,"torn')
        rows = studio.read_lines(r.events, 0)
        self.assertEqual(len(rows), 1)
        start, end, line = rows[0]
        self.assertEqual(start, 0)
        self.assertEqual(end, os.path.getsize(r.events) - len('{"v":1,"torn'))
        self.assertTrue(line.startswith(b'{"v":1'))
        self.assertEqual(studio.unread_count(r.events, 0), 1)
        r.append_raw('"}\n')
        r.append(ev("run_ended", ending="done"))
        rows2 = studio.read_lines(r.events, end)
        self.assertEqual(rows2[0][0], end)
        self.assertEqual(rows2[-1][1], os.path.getsize(r.events))
        self.assertEqual(studio.unread_count(r.events, end), 2)
        self.assertEqual(studio.read_lines(r.events, os.path.getsize(r.events)), [])
        with self.assertRaises(FileNotFoundError):
            studio.read_lines(os.path.join(self.tmp, "none"), 0)

    def test_read_lines_shrunk(self):
        r = make_run(self.home, self.root)
        r.append(ev("run_started", mode="single"))
        with self.assertRaises(studio.LogShrunk):
            studio.read_lines(r.events, os.path.getsize(r.events) + 1)

    def test_read_lines_replaced_by_larger_file(self):
        r = make_run(self.home, self.root)
        r.append(ev("run_started", mode="single"))
        ident = studio.log_ident(r.events)
        off = os.path.getsize(r.events)
        self.assertEqual(studio.read_lines(r.events, off, ident), [])
        new = r.events + ".new"
        with open(new, "wb") as f:
            f.write(b"x" * (off + 50) + b"\n")
        os.replace(new, r.events)
        with self.assertRaises(studio.LogShrunk):
            studio.read_lines(r.events, off, ident)
        with self.assertRaises(studio.LogShrunk):
            studio.unread_count(r.events, off, ident)

    def test_runner_live_garbage_pid(self):
        for pid in (99999999999999999999, "9" * 40, "x", None, -5, 0):
            self.assertFalse(studio.runner_live(pid))

    def test_kv_splits_only_on_newline(self):
        p = os.path.join(self.tmp, "kv")
        with open(p, "w", encoding="utf-8") as f:
            f.write("root=/a\u2028b\x0cc\nrun=/y\n")
        self.assertEqual(studio._kv(p), {"root": "/a\u2028b\x0cc", "run": "/y"})

    def test_call_verb_missing_binary_or_root(self):
        d = self._so("m")
        with mock.patch.dict(os.environ, {"STUB_SO_DIR": d}):
            a = studio.call_verb(os.path.join(self.tmp, "nope"), self.root, ["say"])
            b = studio.call_verb(STUB, os.path.join(self.tmp, "no-root"), ["say"])
        for res in (a, b):
            self.assertEqual(res[0], 127)
            self.assertIn("cannot run studio-overnight", res[2])
            self.assertFalse(res[3])

    def test_parse_event_kinds(self):
        def j(d):
            return json.dumps(d).encode()
        self.assertEqual(studio.parse_event(j(ev("run_started")))[0], "ok")
        self.assertEqual(studio.parse_event(j(ev("run_started", extra=1)))[1]["extra"], 1)
        self.assertEqual(studio.parse_event(b"nope")[0], "bad")
        self.assertEqual(studio.parse_event(b"[1]")[0], "bad")
        self.assertEqual(studio.parse_event(b"")[0], "bad")
        self.assertEqual(studio.parse_event(j(dict(ev("run_started"), v=2)))[0], "version")
        self.assertEqual(studio.parse_event(j(ev("future_thing")))[0], "unknown")
        self.assertEqual(studio.parse_event(j({"v": 1}))[0], "unknown")
        for k in studio.KNOWN_EVENTS:
            self.assertEqual(studio.parse_event(j(ev(k)))[0], "ok")
        self.assertEqual(len(studio.KNOWN_EVENTS), 10)

    def _so(self, name):
        d = os.path.join(self.tmp, "so-" + name)
        os.makedirs(d)
        return d

    def test_call_verb_argv_cwd_env(self):
        d = self._so("a")
        r, w = os.pipe()  # our own fd 0 holds data for the call: a leak into the verb would show
        os.write(w, b"leak\n")
        os.close(w)
        saved = os.dup(0)
        os.dup2(r, 0)
        try:
            with mock.patch.dict(os.environ, {"STUB_SO_DIR": d, "MULTICA_TOKEN": "mul_secret1234"}):
                code, out, err, to = studio.call_verb(STUB, self.root, ["say", "S1", "--", "hi\nthere", "x y"])
        finally:
            os.dup2(saved, 0)
            os.close(saved)
            os.close(r)
        self.assertEqual((code, out.strip(), err, to), (0, "ok", "", False))
        with open(os.path.join(d, "1.argv"), "rb") as f:
            self.assertEqual(f.read().split(b"\0")[:-1], [b"say", b"S1", b"--", b"hi\nthere", b"x y"])
        with open(os.path.join(d, "1.pwd")) as f:
            self.assertEqual(f.read().strip(), os.path.realpath(self.root))
        with open(os.path.join(d, "1.env")) as f:
            self.assertEqual(f.read(), "")
        with open(os.path.join(d, "1.stdin")) as f:
            self.assertEqual(f.read(), "")
        with open(os.path.join(d, "1.ids")) as f:
            pid, pgid = f.read().split()
        self.assertEqual(pid, pgid)

    def test_call_verb_exit_and_stderr(self):
        d = self._so("b")
        with open(os.path.join(d, "hold.script"), "w") as f:
            f.write("err not held\nexit 1\n")
        with mock.patch.dict(os.environ, {"STUB_SO_DIR": d}):
            code, out, err, to = studio.call_verb(STUB, self.root, ["hold", "S1"])
        self.assertEqual((code, out, err.strip(), to), (1, "", "not held", False))

    def test_call_verb_timeout_kills_group(self):
        d = self._so("c")
        with open(os.path.join(d, "default.script"), "w") as f:
            f.write("spawn\nsleep 60\n")
        t0 = time.time()
        with mock.patch.dict(os.environ, {"STUB_SO_DIR": d}), mock.patch.object(studio, "VERB_TIMEOUT", 5):
            code, out, err, to = studio.call_verb(STUB, self.root, ["say"])
        self.assertTrue(to)
        self.assertLess(time.time() - t0, 55)         # the sleep is 60 s: the kill, not the sleep, ended it
        with open(os.path.join(d, "grandchild.pid")) as f:
            gc = int(f.read())
        self.assertTrue(bridgetest.wait_gone(gc), "the grandchild survived the group kill")
