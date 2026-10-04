"""The bridge service: backoff, delayed note, auth, Keychain, self-test, status, lock, logs (#28, AC26-AC29)."""
from __future__ import annotations

import json
import logging
import os
import pwd
import stat
import subprocess
import sys
import time
import unittest
from unittest import mock

from bridgetest import MirrorCase, TOKEN, TESTS, MULTICA, ev, make_project, make_run
from bridge import service
from bridge import multica_cli as mc

B = "overnight-20261003-2214"
BIN = os.path.join(MULTICA, "bin", "multica-bridge")
ACCOUNT = pwd.getpwuid(os.getuid()).pw_name
FAULTED = ("issue runs", "issue list", "issue get", "issue comment list", "issue comment add",
           "issue create", "issue status")


class ServiceCase(MirrorCase):
    def setUp(self):
        super().setUp()
        self.root = make_project(self.tmp, "game")
        os.makedirs(self.paths.base, exist_ok=True)
        with open(self.cfg_path, encoding="utf-8") as f, open(self.paths.config, "w", encoding="utf-8") as g:
            g.write(f.read())
        self.sec = os.path.join(self.tmp, "sec")
        os.makedirs(self.sec)
        self.set_keychain(TOKEN)
        self.osa_log = os.path.join(self.tmp, "osa.log")
        osa = os.path.join(self.tmp, "osascript")
        with open(osa, "w") as f:
            f.write('#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\n' % self.osa_log)
        os.chmod(osa, 0o755)
        self.so = os.path.join(self.tmp, "so")
        for p in (mock.patch.object(mc, "SECURITY", os.path.join(TESTS, "stub-security")),
                  mock.patch.object(service, "OSASCRIPT", osa),
                  mock.patch.dict(os.environ, {"STUB_SECURITY_DIR": self.sec, "STUB_SO_DIR": self.so})):
            p.start()
            self.addCleanup(p.stop)
        self.slog = logging.getLogger("service-test")
        self.slog.addHandler(logging.NullHandler())

    def set_keychain(self, token):
        with open(os.path.join(self.sec, "omega-multica-bridge-" + ACCOUNT), "w") as f:
            f.write(token + "\n")

    def svc(self):
        return service.Service(self.home, log=self.slog)

    def osa_calls(self):
        if not os.path.exists(self.osa_log):
            return []
        with open(self.osa_log) as f:
            return f.read().splitlines()

    def started(self):
        run = make_run(self.home, self.root, B, True, None)
        run.append(ev("run_started", mode="integration"),
                   ev("story_listed", story="A", chain=1, depends=[]))
        s = self.svc()
        self.assertEqual(s.poll_once(), "ok")
        self.run = run
        self.ri = self.run_issue(run)["identifier"]
        return s, run

    def clock(self, t):
        box = {"t": t}
        p = mock.patch.object(service.time, "time", lambda: box["t"])
        p.start()
        self.addCleanup(p.stop)
        return box

    def break_board(self):
        for cmd in FAULTED:
            self.board.fault(cmd, exit=1, stderr="503 service unavailable", count=-1)

    def fix_board(self):
        os.remove(os.path.join(self.board.state, "faults.json"))

    def client_env(self):
        return dict(os.environ, HOME=self.home, OMEGA_MULTICA_SECURITY=os.path.join(TESTS, "stub-security"))


class ServiceTest(ServiceCase):
    def test_next_delay(self):
        self.assertEqual([service.next_delay(15, n) for n in range(0, 8)], [15, 30, 60, 120, 240, 300, 300, 300])
        self.assertEqual(service.next_delay(15, 0), 15)             # reset after ok

    def test_transient_counts_and_resets(self):
        s, _ = self.started()
        self.break_board()
        self.assertEqual([s.poll_once() for _ in range(3)], ["transient"] * 3)
        self.assertEqual(s.st["failures"], 3)
        self.fix_board()
        self.assertEqual(s.poll_once(), "ok")
        self.assertEqual(s.st["failures"], 0)
        self.assertIsNone(s.st["outage_since"])

    def _outage(self, recover_after):
        s, _ = self.started()
        t = 1_900_000_000.0
        box = self.clock(t)
        self.break_board()
        self.assertEqual(s.poll_once(), "transient")
        self.fix_board()
        box["t"] = t + recover_after
        self.assertEqual(s.poll_once(), "ok")
        return s, box

    def test_delayed_note_after_long_outage(self):
        s, box = self._outage(360)
        notes = [c for c in self.comments_on(self.ri) if "board was delayed" in c]
        self.assertEqual(notes, ["studio: board was delayed 6 min"])
        box["t"] += 30
        self.assertEqual(s.poll_once(), "ok")
        self.assertEqual(len([c for c in self.comments_on(self.ri) if "board was delayed" in c]), 1)

    def test_no_delayed_note_for_short_outage(self):
        self._outage(200)
        self.assertEqual([c for c in self.comments_on(self.ri) if "board was delayed" in c], [])

    def test_auth_error_notifies_once_and_waits(self):
        s, _ = self.started()
        self.set_keychain("mul_wrongtoken99999")
        box = self.clock(1_900_000_000.0)
        self.assertEqual(s.poll_once(), "auth")
        self.assertEqual(len(self.osa_calls()), 1)
        n = len(self.board.calls())
        box["t"] += 100
        self.assertEqual(s.poll_once(), "auth")
        self.assertEqual(len(self.board.calls()), n)                # no CLI call inside the wait
        self.assertEqual(len(self.osa_calls()), 1)
        box["t"] += 250
        self.assertEqual(s.poll_once(), "auth")
        self.assertGreater(len(self.board.calls()), n)              # retried after 300 s
        self.assertEqual(len(self.osa_calls()), 1)                  # same outage: no second notification
        self.set_keychain(TOKEN)
        box["t"] += 400
        self.assertEqual(s.poll_once(), "ok")
        self.assertEqual(s.st["auth_until"], 0)

    def test_keychain_locked_reported_separately_no_cli_call(self):
        open(os.path.join(self.sec, "locked"), "w").close()
        s = self.svc()
        self.assertEqual(s.poll_once(), "keychain")
        self.assertEqual(len(self.osa_calls()), 1)
        self.assertIn("Keychain", self.osa_calls()[0])
        self.assertEqual(s.poll_once(), "keychain")
        self.assertEqual(len(self.osa_calls()), 1)
        self.assertFalse(os.path.exists(os.path.join(self.board.state, "calls.jsonl")))

    def test_config_error(self):
        os.remove(self.paths.config)
        self.assertEqual(self.svc().poll_once(), "config")

    def test_token_never_in_logs_state_or_verb_env(self):
        log = service.setup_logging(self.paths)
        s = service.Service(self.home, log=log)
        run = make_run(self.home, self.root, B, True, None)
        run.append(ev("run_started", mode="integration"), ev("story_listed", story="A", chain=1, depends=[]))
        self.assertEqual(s.poll_once(), "ok")
        sa = self.story_issue(run, "A")["identifier"]
        self.board.add_comment(sa, "/say hello")
        self.assertEqual(s.poll_once(), "ok")
        self.board.fault("issue get", exit=1, stderr="oops %s leaked" % TOKEN, count=1)
        s.poll_once()
        s.selftest()
        for h in log.handlers:
            h.flush()
        seen = 0
        for d, _, names in os.walk(os.path.join(self.home, ".claude-gamedev", "multica")):
            for n in names:
                seen += 1
                with open(os.path.join(d, n), "rb") as f:
                    self.assertNotIn(TOKEN.encode(), f.read(), os.path.join(d, n))
        self.assertGreater(seen, 3)
        envs = [n for n in os.listdir(self.so) if n.endswith(".env")]
        self.assertTrue(envs)
        for n in envs:
            with open(os.path.join(self.so, n)) as f:
                self.assertNotIn(TOKEN, f.read())

    # ----- self-test ------------------------------------------------------------

    def test_selftest_ok(self):
        r = self.svc().selftest()
        self.assertTrue(r["ok"], r)
        self.assertEqual(r["interpreter"], os.path.realpath(sys.executable))
        with open(self.paths.selftest) as f:
            self.assertEqual(json.load(f), r)
        self.assertEqual(set(r), {"ok", "error", "kind", "interpreter", "checked_at", "checked"})

    def test_selftest_file_access_error(self):
        with open(self.paths.config, "a") as f:
            f.write("roots=%s\n" % self.root)
        studio = os.path.join(self.root, ".studio")
        os.chmod(studio, 0)
        try:
            r = self.svc().selftest()
        finally:
            os.chmod(studio, 0o755)
        self.assertFalse(r["ok"])
        self.assertEqual(r["kind"], "file-access")
        self.assertIn(studio, r["error"])
        self.assertIn(r["interpreter"], r["error"])
        with open(self.paths.selftest) as f:
            self.assertFalse(json.load(f)["ok"])

    def test_selftest_missing_config_keychain(self):
        with open(self.paths.config, "a") as f:
            f.write("roots=%s\n" % os.path.join(self.tmp, "nope"))
        self.assertEqual(self.svc().selftest()["kind"], "missing")
        os.remove(self.paths.config)
        self.assertEqual(self.svc().selftest()["kind"], "config")
        with open(self.cfg_path) as f, open(self.paths.config, "w") as g:
            g.write(f.read())
        os.remove(os.path.join(self.sec, "omega-multica-bridge-" + ACCOUNT))
        self.assertEqual(self.svc().selftest()["kind"], "keychain")

    def test_selftest_token_mismatch(self):
        d = self.board.data()
        d["user"]["id"] = "m-someone-else"
        self.board.save(d)
        r = self.svc().selftest()
        self.assertEqual((r["ok"], r["kind"]), (False, "token"))
        self.set_keychain("mul_wrongtoken99999")
        self.assertEqual(self.svc().selftest()["kind"], "token")

    def test_selftest_network(self):
        self.board.fault("user profile get", exit=1, stderr="503 service unavailable", count=-1)
        self.assertEqual(self.svc().selftest()["kind"], "network")

    def test_selftest_roots_empty_uses_live_runs(self):
        run = make_run(self.home, self.root, B, True, None)
        r = self.svc().selftest()
        self.assertTrue(r["ok"])
        self.assertIn(os.path.join(self.root, ".studio"), r["checked"])
        run.kill()
        self.assertNotIn(os.path.join(self.root, ".studio"), self.svc().selftest()["checked"])

    def test_selftest_checks_selftest_roots_even_with_empty_roots(self):
        with open(self.paths.config, "a") as f:
            f.write("selftest_roots=%s\n" % self.root)
        studio = os.path.join(self.root, ".studio")
        r = self.svc().selftest()
        self.assertTrue(r["ok"], r)
        self.assertIn(self.root, r["checked"])
        self.assertIn(studio, r["checked"])
        os.chmod(studio, 0)
        try:
            r = self.svc().selftest()
        finally:
            os.chmod(studio, 0o755)
        self.assertEqual(r["kind"], "file-access")
        self.assertIn(studio, r["error"])

    def test_selftest_root_without_studio_dir_is_fine(self):
        bare = os.path.join(self.tmp, "bare")
        os.makedirs(bare)
        with open(self.paths.config, "a") as f:
            f.write("selftest_roots=%s\n" % bare)
        self.assertTrue(self.svc().selftest()["ok"])

    # ----- status, lock, logs -----------------------------------------------------

    def _snapshot(self):
        out = {}
        for d, _, names in os.walk(self.paths.base):
            for n in names:
                p = os.path.join(d, n)
                out[p] = os.stat(p).st_mtime_ns
            out[d] = tuple(sorted(names))
        return out

    def test_status_prints_and_writes_nothing(self):
        s, run = self.started()
        self.svc().selftest()
        run.append(ev("unit_started", story="A", unit=1))
        run.append(ev("unit_ended", story="A", unit=1))
        before = self._snapshot()
        time.sleep(0.01)
        text = self.svc().status_text()
        self.assertEqual(self._snapshot(), before)
        lines = text.splitlines()
        self.assertTrue(lines[0].startswith("cli: 0.6.1"), text)
        self.assertTrue(lines[1].startswith("selftest: ok ("), text)
        self.assertTrue(lines[2].startswith("last poll: 20"), text)
        self.assertIn("run %s: %s, 2 unread events" % (self.key(run), self.ri), text)

    def test_status_lists_a_run_whose_poll_keeps_failing(self):
        s, run = self.started()
        key = self.key(run)
        st = service.state.load_run(self.paths, key)
        st["poll_fails"], st["poll_error"] = 4, "KeyError: 'created_at'"
        service.state.save_run(self.paths, st)
        text = self.svc().status_text()
        self.assertIn("poll failing (4): KeyError: 'created_at'", text)

    def test_status_redacts_an_old_selftest_error(self):
        os.makedirs(self.paths.base, exist_ok=True)
        with open(self.paths.selftest, "w") as f:
            json.dump({"ok": False, "kind": "cli", "error": "bad header mul_oldtoken123456", "checked_at": "t"}, f)
        text = self.svc().status_text()
        self.assertNotIn("mul_oldtoken123456", text)
        self.assertIn("<token>", text)

    def test_status_empty(self):
        text = service.Service(self.home, log=self.slog).status_text()
        self.assertEqual(text.splitlines(), ["cli: unknown", "selftest: not run", "last poll: never",
                                             "no tracked runs"])

    def test_status_command_writes_nothing(self):
        r = subprocess.run([sys.executable, BIN, "status"], env=self.client_env(), capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("cli: unknown", r.stdout)
        self.assertEqual(os.listdir(self.paths.base), ["config"])

    def test_usage(self):
        r = subprocess.run([sys.executable, BIN, "bogus"], capture_output=True, text=True)
        self.assertEqual(r.returncode, 2)
        self.assertIn("usage:", r.stderr)

    def test_bin_is_executable(self):
        self.assertTrue(os.stat(BIN).st_mode & stat.S_IXUSR)

    def test_once_refused_while_lock_held(self):
        code = ("import fcntl,os,sys,time;fd=os.open(sys.argv[1],os.O_RDWR|os.O_CREAT);"
                "fcntl.flock(fd,fcntl.LOCK_EX);print('held',flush=True);time.sleep(30)")
        p = subprocess.Popen([sys.executable, "-c", code, self.paths.lock], stdout=subprocess.PIPE, text=True)
        self.addCleanup(p.stdout.close)
        self.addCleanup(p.wait)
        self.addCleanup(p.kill)
        self.assertEqual(p.stdout.readline().strip(), "held")
        r = subprocess.run([sys.executable, BIN, "once"], env=self.client_env(), capture_output=True,
                           text=True, timeout=60)
        self.assertEqual(r.returncode, 1)
        self.assertIn("another bridge holds the lock", r.stderr)

    def test_once_config_error_exits_1(self):
        os.remove(self.paths.config)
        r = subprocess.run([sys.executable, BIN, "once"], env=self.client_env(), capture_output=True,
                           text=True, timeout=60)
        self.assertEqual(r.returncode, 1)

    def test_log_rotation_settings(self):
        log = service.setup_logging(self.paths)
        hs = [h for h in log.handlers if isinstance(h, service.RotatingFileHandler)]
        self.assertEqual(len(hs), 1)
        self.assertEqual((hs[0].maxBytes, hs[0].backupCount), (1_000_000, 5))
        self.assertEqual(len([h for h in service.setup_logging(self.paths).handlers
                              if isinstance(h, service.RotatingFileHandler)]), 1)
        fresh = service.state.Paths(os.path.join(self.tmp, "fresh"))
        service.setup_logging(fresh)
        self.assertEqual(stat.S_IMODE(os.stat(fresh.base).st_mode), 0o700)
        self.assertTrue(os.path.isdir(fresh.cli_home))

    # ----- fix round: redaction, permanent note errors, status, run loop ----------

    def test_selftest_error_redacts_token(self):
        self.board.fault("user profile get", exit=1, stderr="401 unauthorized: token %s revoked" % TOKEN, count=-1)
        r = self.svc().selftest()
        self.assertNotIn(TOKEN, json.dumps(r))
        with open(self.paths.selftest) as f:
            self.assertNotIn(TOKEN, f.read())
        p = subprocess.run([sys.executable, BIN, "selftest"], env=self.client_env(), capture_output=True,
                           text=True, timeout=60)
        self.assertNotIn(TOKEN, p.stdout + p.stderr)
        self.assertEqual(p.returncode, 1)

    def test_selftest_error_redacts_unprefixed_token(self):
        self.set_keychain("plainsecretvalue42")
        with mock.patch.object(mc.Cli, "profile", side_effect=mc.CliError("boom plainsecretvalue42")):
            r = self.svc().selftest()
        self.assertNotIn("plainsecretvalue42", json.dumps(r))
        self.assertIn("<token>", r["error"])

    def test_redact_uses_explicit_secrets(self):
        self.assertEqual(mc.redact("a plain-secret-xyz b", ["plain-secret-xyz"]), "a <token> b")
        self.assertNotIn("mul_abcdef123456", mc.redact("x mul_abcdef123456", []))

    def test_explicit_secret_without_prefix_not_logged(self):
        self.set_keychain("plainsecretvalue42")
        log = service.setup_logging(self.paths)
        s = service.Service(self.home, log=log)
        self.board.fault("version", exit=1, stderr="weird plainsecretvalue42", count=-1)
        try:
            s.poll_once()
        except Exception:
            pass
        log.error("direct %s", "plainsecretvalue42")
        for h in log.handlers:
            h.flush()
        with open(self.paths.log) as f:
            self.assertNotIn("plainsecretvalue42", f.read())

    def test_once_traceback_redacts_token(self):
        self.board.fault("version", exit=1, stderr="weird failure for %s" % TOKEN, count=-1)
        r = subprocess.run([sys.executable, BIN, "once"], env=self.client_env(), capture_output=True,
                           text=True, timeout=60)
        self.assertEqual(r.returncode, 1)
        self.assertNotIn(TOKEN, r.stdout + r.stderr)
        if os.path.exists(self.paths.log):
            with open(self.paths.log) as f:
                self.assertNotIn(TOKEN, f.read())

    def _long_outage_then(self, **fault):
        s, _ = self.started()
        t = 1_900_000_000.0
        box = self.clock(t)
        self.break_board()
        self.assertEqual(s.poll_once(), "transient")
        self.fix_board()
        self.board.fault("issue comment add", count=-1, **fault)
        box["t"] = t + 360
        return s, box

    def test_permanent_error_on_delayed_note_does_not_wedge(self):
        s, box = self._long_outage_then(exit=1, stderr="404 issue not found")
        self.assertEqual(s.poll_once(), "ok")
        self.assertIsNone(s.st["outage_since"])
        self.assertEqual(s.st["failures"], 0)
        box["t"] += 20
        self.assertEqual(s.poll_once(), "ok")

    def test_permanent_error_delayed_for_set(self):
        s, _ = self._long_outage_then(exit=1, stderr="404 issue not found")
        s.poll_once()
        st = service.state.load_run(self.paths, self.key(self.run))
        self.assertEqual(st["delayed_for"], 1_900_000_000.0)

    def test_status_survives_unreadable_events(self):
        s, run = self.started()
        os.remove(os.path.join(run.run_dir, "events.jsonl"))
        text = self.svc().status_text()
        self.assertIn("run %s: %s, events unreadable" % (self.key(run), self.ri), text)

    def test_status_survives_shrunk_log_and_other_runs_listed(self):
        s, run = self.started()
        other = make_run(self.home, self.root, "overnight-20261004-0100", True, None)
        other.append(ev("run_started", mode="integration"))
        self.assertEqual(s.poll_once(), "ok")
        with open(os.path.join(run.run_dir, "events.jsonl"), "w") as f:
            f.write("")
        text = self.svc().status_text()
        self.assertIn("events unreadable", text)
        self.assertIn("run %s:" % self.key(other), text)
        self.assertIn("unread events", text.split("run %s:" % self.key(other))[1])

    def test_status_command_exits_0_on_bad_log(self):
        s, run = self.started()
        os.remove(os.path.join(run.run_dir, "events.jsonl"))
        r = subprocess.run([sys.executable, BIN, "status"], env=self.client_env(), capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("events unreadable", r.stdout)

    def test_status_uses_log_id_after_replacement(self):
        s, run = self.started()
        events = os.path.join(run.run_dir, "events.jsonl")
        with open(events, "rb") as f:
            body = f.read()
        os.remove(events)
        with open(events, "wb") as f:
            f.write(body * 3)                       # a different file, longer than the saved offset
        self.assertIn("events unreadable", self.svc().status_text())

    # ----- rules the mutants showed untested -----

    def test_notified_resets_after_ok(self):
        s, _ = self.started()
        self.set_keychain("mul_wrongtoken99999")
        box = self.clock(1_900_000_000.0)
        s.poll_once()
        self.set_keychain(TOKEN)
        box["t"] += 400
        self.assertEqual(s.poll_once(), "ok")
        self.assertEqual(s.st["notified"], [])
        self.set_keychain("mul_wrongtoken99999")
        box["t"] += 10
        s.poll_once()
        self.assertEqual(len(self.osa_calls()), 2)          # a second outage notifies again

    def test_outage_span_runs_from_first_failure(self):
        s, _ = self.started()
        t = 1_900_000_000.0
        box = self.clock(t)
        self.break_board()
        s.poll_once()
        box["t"] = t + 200
        s.poll_once()
        self.assertEqual(s.st["outage_since"], t)
        self.fix_board()
        box["t"] = t + 360
        s.poll_once()
        self.assertEqual([c for c in self.comments_on(self.ri) if "board was delayed" in c],
                         ["studio: board was delayed 6 min"])

    def test_delayed_note_boundary(self):
        s, _ = self._outage(300)
        self.assertEqual([c for c in self.comments_on(self.ri) if "board was delayed" in c], [])

    def test_delayed_note_just_over_boundary(self):
        s, _ = self._outage(301)
        self.assertEqual(len([c for c in self.comments_on(self.ri) if "board was delayed" in c]), 1)

    def test_delayed_note_never_doubles_across_a_mid_way_failure(self):
        s, _ = self.started()
        run2 = make_run(self.home, self.root, "overnight-20261004-0100", True, None)
        run2.append(ev("run_started", mode="integration"))
        self.assertEqual(s.poll_once(), "ok")
        ri2 = self.run_issue(run2)["identifier"]
        t = 1_900_000_000.0
        box = self.clock(t)
        self.break_board()
        s.poll_once()
        self.fix_board()
        box["t"] = t + 360
        real = service.mirror.note
        calls = {"n": 0}

        def flaky(ctx, st, text):
            calls["n"] += 1
            if calls["n"] == 2:
                raise mc.TransientError("503 service unavailable")
            return real(ctx, st, text)
        with mock.patch.object(service.mirror, "note", flaky):
            self.assertEqual(s.poll_once(), "transient")
        box["t"] += 10
        self.assertEqual(s.poll_once(), "ok")
        for ident in (self.ri, ri2):
            self.assertEqual(len([c for c in self.comments_on(ident) if "board was delayed" in c]), 1, ident)

    def test_run_without_run_issue_skipped_for_delayed_note(self):
        s, _ = self.started()
        st = service.state.load_run(self.paths, self.key(self.run))
        st["run_issue"] = None
        service.state.save_run(self.paths, st)
        t = 1_900_000_000.0
        box = self.clock(t)
        self.break_board()
        s.poll_once()
        self.fix_board()
        box["t"] = t + 360
        with mock.patch.object(service.mirror, "poll_runs"):           # it would create the Run issue again
            self.assertEqual(s.poll_once(), "ok")
        self.assertIsNone(service.state.load_run(self.paths, self.key(self.run))["delayed_for"])

    def test_status_json_persists_failures_and_auth(self):
        s, _ = self.started()
        self.clock(1_900_000_000.0)
        self.break_board()
        s.poll_once()
        s2 = self.svc()
        self.assertEqual((s2.st["failures"], s2.st["outage_since"]), (1, 1_900_000_000.0))
        self.fix_board()
        self.set_keychain("mul_wrongtoken99999")
        s.poll_once()
        self.assertEqual(self.svc().st["auth_until"], 1_900_000_000.0 + 300)

    def test_new_token_selftest_clears_auth_wait(self):
        s, _ = self.started()
        self.set_keychain("mul_wrongtoken99999")
        self.clock(1_900_000_000.0)
        self.assertEqual(s.poll_once(), "auth")
        self.set_keychain(TOKEN)
        self.assertTrue(self.svc().selftest()["ok"])
        s2 = self.svc()
        self.assertEqual(s2.st["auth_until"], 0)
        self.assertEqual(s2.poll_once(), "ok")
        self.assertEqual(s2.st["notified"], [])           # an ok poll re-arms the notice

    def test_selftest_refreshes_cli_version(self):
        s = self.svc()
        s.st["cli_version"] = "0.0.1"
        s._save()
        s.selftest()
        self.assertEqual(self.svc().st["cli_version"], "0.6.1")

    def test_stale_second_process_does_not_clobber_status(self):
        a, b = self.svc(), self.svc()
        with mock.patch.object(service.mirror, "poll_runs", side_effect=mc.TransientError("503")):
            a.poll_once()
            self.assertEqual(a.st["failures"], 1)
            b.poll_once()                               # b was built before a's write
        self.assertEqual(self.svc().st["failures"], 2)

    def test_keychain_failures_back_off(self):
        open(os.path.join(self.sec, "locked"), "w").close()
        s = self.svc()
        s.poll_once()
        s.poll_once()
        self.assertEqual(s.st["failures"], 2)
        self.assertIsNone(s.st["outage_since"])

    def test_config_failures_back_off(self):
        os.remove(self.paths.config)
        s = self.svc()
        s.poll_once()
        self.assertEqual(s.st["failures"], 1)


class Stop(Exception):
    pass


class RunLoopTest(ServiceCase):
    def drive(self, s, n, mono_step=0.0, poll=None):
        """Run the loop for n sleeps; return (sleeps, self-test count)."""
        sleeps, mono, count = [], {"t": 1000.0}, {"selftest": 0}
        real = s.selftest

        def st():
            count["selftest"] += 1
            return real()

        def sleep(d):
            sleeps.append(d)
            mono["t"] += mono_step
            if len(sleeps) >= n:
                raise Stop()
        s.selftest = st
        if poll:
            s.poll_once = poll
        with self.assertRaises(Stop):
            s.run(sleep=sleep, monotonic=lambda: mono["t"])
        return sleeps, count["selftest"]

    def test_selftest_at_start_and_every_600s(self):
        self.assertEqual(self.drive(self.svc(), 3, mono_step=250.0)[1], 1)     # t = 0, 250, 500
        self.assertEqual(self.drive(self.svc(), 4, mono_step=250.0)[1], 2)     # 750 passes 600
        self.assertEqual(self.drive(self.svc(), 2, mono_step=599.0)[1], 1)     # 599 < 600
        self.assertEqual(self.drive(self.svc(), 2, mono_step=600.0)[1], 2)     # exactly 600 counts

    def test_backoff_delays_under_outage(self):
        s, _ = self.started()
        self.break_board()
        sleeps, _ = self.drive(s, 4)
        self.assertEqual(sleeps, [30, 60, 120, 240])

    def test_auth_waits_300(self):
        s, _ = self.started()
        self.set_keychain("mul_wrongtoken99999")
        sleeps, _ = self.drive(s, 1)
        self.assertEqual(sleeps, [300])

    def test_unexpected_error_logged_and_counted(self):
        s = self.svc()

        def boom():
            raise RuntimeError("kaboom")
        with self.assertLogs(self.slog, "ERROR") as cm:
            sleeps, _ = self.drive(s, 2, poll=boom)
        self.assertEqual(sleeps, [30, 60])
        self.assertEqual(s.st["failures"], 2)
        self.assertIsNotNone(s.st["outage_since"])
        self.assertIn("kaboom", "\n".join(cm.output))

    def test_poll_runs_under_the_lock(self):
        s = self.svc()
        probe = ("import fcntl,os,sys\nfd=os.open(sys.argv[1],os.O_RDWR)\n"
                 "try:\n fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB);print('free')\n"
                 "except OSError:\n print('held')")
        seen = []

        def poll():
            seen.append(subprocess.run([sys.executable, "-c", probe, self.paths.lock], capture_output=True,
                                       text=True).stdout.strip())
            return "ok"
        self.drive(s, 1, poll=poll)
        self.assertEqual(seen, ["held"])
        r = subprocess.run([sys.executable, "-c", probe, self.paths.lock], capture_output=True, text=True)
        self.assertEqual(r.stdout.strip(), "free")           # released between polls

    def test_passing_selftest_never_rearms_auth_notice(self):
        s = self.svc()
        with mock.patch.object(service.mirror, "poll_runs", side_effect=mc.AuthError("401 unauthorized")):
            self.drive(s, 12, mono_step=600.0)           # self-test passes every 600 s, polls keep 401ing
        self.assertEqual(len(self.osa_calls()), 1)

    def test_token_good_saves_under_the_lock_after_the_cli_call(self):
        s = self.svc()
        open(self.paths.lock, "a").close()
        probe = ("import fcntl,os,sys\nfd=os.open(sys.argv[1],os.O_RDWR)\n"
                 "try:\n fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB);print('free')\n"
                 "except OSError:\n print('held')")

        def seen_lock():
            return subprocess.run([sys.executable, "-c", probe, self.paths.lock], capture_output=True,
                                  text=True).stdout.strip()
        seen = {}

        class Cli:
            def version(_):
                seen["cli"] = seen_lock()
                return {"version": "9.9.9"}
        real_save = s._save

        def save():
            seen["save"] = seen_lock()
            real_save()
        s._save = save
        s._token_good(Cli())
        self.assertEqual(seen, {"cli": "free", "save": "held"})

    def test_keychain_failure_survives_unwritable_status(self):
        open(os.path.join(self.sec, "locked"), "w").close()
        s = self.svc()
        with mock.patch.object(s, "_save", side_effect=OSError("disk full")):
            self.assertEqual(s.poll_once(), "keychain")


if __name__ == "__main__":
    unittest.main()
