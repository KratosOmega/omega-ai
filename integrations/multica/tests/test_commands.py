"""Comment commands: parsing, the call table, cursors, the journal, replies (#28, AC20-AC25)."""
from __future__ import annotations

import os
import re
import time
import unittest
from unittest import mock

import bridgetest
from bridgetest import MirrorCase, ev, make_project, make_run
from bridge import commands, studio
from bridge import multica_cli as mc

B = "overnight-20261003-2214"


class ParseTest(unittest.TestCase):
    def test_command_crlf_and_leading_blank_lines(self):
        self.assertEqual(commands.parse("\r\n\r\n  /SAY  hello\r\nworld\r\n"), ("say", "hello\nworld"))

    def test_plain_text_and_inner_slash_ignored(self):
        self.assertEqual(commands.parse("hi\n/stop run"), (None, None))
        self.assertEqual(commands.parse(""), (None, None))
        self.assertEqual(commands.parse("  \n \n"), (None, None))

    def test_plan_call_table(self):
        def story(word, text=""):
            return commands.plan_call(word, text, "story", "A", False, B)

        def run(word, text="", single=False):
            return commands.plan_call(word, text, "run", None, single, B)

        usage = lambda w: ("reply", "studio: ✗ usage: /%s <text>" % w)  # noqa: E731
        unsay_usage = ("reply", "studio: ✗ usage: /unsay <id> — the id is the number /said lists")
        rows = [
            ("story say", story("say", "hi there"), ("call", ["say", "--run", B, "A", "--", "hi there"])),
            ("story unit", story("unit", "do x"), ("call", ["say", "--run", B, "A", "--unit", "--", "do x"])),
            ("story hold, text ignored", story("hold", "x"), ("call", ["hold", "--run", B, "A"])),
            ("story resume", story("resume"), ("call", ["resume", "--run", B, "A"])),
            ("story stop", story("stop"), ("call", ["stop", "--run", B, "A"])),
            ("story unsay", story("unsay", "3"), ("call", ["unsay", "--run", B, "A", "3"])),
            ("story said", story("said"), ("call", ["said", "--run", B, "A"])),
            ("run stop run", run("stop", "run"), ("call", ["stop", "--run", B])),
            ("run STOP RUN", run("stop", "RUN"), ("call", ["stop", "--run", B])),
            ("single say", run("say", "t", True), ("call", ["say", "--run", B, "-", "--", "t"])),
            ("single bare stop", run("stop", "", True), ("call", ["stop", "--run", B, "-"])),
            ("single stop run", run("stop", "run", True), ("call", ["stop", "--run", B])),
            ("single hold", run("hold", "", True), ("call", ["hold", "--run", B, "-"])),
            ("empty say", story("say"), usage("say")),
            ("empty unit", story("unit"), usage("unit")),
            ("unsay x", story("unsay", "x"), unsay_usage),
            ("unsay full-width", story("unsay", "３"), unsay_usage),
            ("unsay empty", story("unsay"), unsay_usage),
            ("hold on manifest run", run("hold"), ("reply", "studio: ✗ /hold goes on the story's own issue")),
            ("stop run on story", story("stop", "run"),
             ("reply", "studio: ✗ /stop run works on the Run issue; /stop here stops this story")),
            ("bare stop on manifest run", run("stop"),
             ("reply", "studio: ✗ on the Run issue use /stop run; /stop on a story issue stops that story")),
            ("unknown word", story("deploy"), ("ignore", None)),
        ]
        for name, got, want in rows:
            with self.subTest(name):
                self.assertEqual(got, want)

    def test_text_with_shell_characters_is_one_argument(self):
        for text in ("$HOME `id` 'a' \"b\"", "line1\nline2", "-n hi", "--run x", "--unit", "a;b|c&d > e"):
            with self.subTest(text):
                kind, argv = commands.plan_call("say", text, "story", "A", False, B)
                self.assertEqual(kind, "call")
                self.assertEqual(argv[-2:], ["--", text])

    def test_near_miss(self):
        for w in ("sya", "hodl", "stp"):
            with self.subTest(w):
                self.assertEqual(commands.plan_call(w, "", "story", "A", False, B), ("reply", commands.HELP))
        for w in ("deploy", ""):
            with self.subTest(w):
                self.assertEqual(commands.plan_call(w, "", "story", "A", False, B), ("ignore", None))
        self.assertEqual(commands.parse("/"), ("", ""))
        self.assertEqual(commands.plan_call("", "", "story", "A", False, B), ("ignore", None))
        self.assertEqual(commands.parse("plain"), (None, None))

    def test_format_reply(self):
        self.assertEqual(commands.format_reply(0, "delivered\n", "noise", False), "studio: ✓ delivered")
        self.assertEqual(commands.format_reply(1, "out", "not held\n", False), "studio: ✗ not held")
        cut = commands.format_reply(0, "x" * 1500, "", False)
        self.assertEqual(cut, "studio: ✓ " + "x" * 1000 + "…")
        self.assertEqual(commands.format_reply(0, "", "", False), "studio: ✓ done")
        self.assertEqual(commands.format_reply(3, "", "", False), "studio: ✗ exit 3")
        self.assertEqual(commands.format_reply(0, "partial", "", True), "studio: ✗ timed out after 30 s")
        self.assertEqual(commands.format_reply(0, "x", "partial", True), "studio: ✗ partial\ntimed out after 30 s")


class CommandsTest(MirrorCase):
    def setUp(self):
        super().setUp()
        self.root = make_project(self.tmp, "game")
        self.so = os.path.join(self.tmp, "so")
        p = mock.patch.dict(os.environ, {"STUB_SO_DIR": self.so})
        p.start()
        self.addCleanup(p.stop)

    # ----- helpers -----------------------------------------------------------

    def started(self, root=None, mode="integration", behind=None):
        """A live run with stories A and B (or single mode), polled so the issues exist."""
        root = root or self.root
        if behind is not None:
            self.board.set_now(time.time() - behind)
        run = make_run(self.home, root, B, True, None)
        if mode == "single":
            run.append(ev("run_started", mode="single"))
        else:
            run.append(ev("run_started", mode="integration"),
                       ev("story_listed", story="A", chain=1, depends=[]),
                       ev("story_listed", story="B", chain=1, depends=[]))
        self.poll()
        self.poll()
        self.run = run
        self.ri = self.run_issue(run)["identifier"]
        if mode != "single":
            self.sa = self.story_issue(run, "A")["identifier"]
            self.sb = self.story_issue(run, "B")["identifier"]
        return run

    def load(self, run=None):
        return self.state.load_run(self.paths, self.key(run or self.run))

    def mutate(self, fn, run=None):
        st = self.load(run)
        fn(st)
        self.state.save_run(self.paths, st)

    def say(self, ident, content, **kw):
        return self.board.add_comment(ident, content, **kw)

    def verbs(self):
        n = 0
        p = os.path.join(self.so, "n")
        if os.path.exists(p):
            with open(p) as f:
                n = int(f.read())
        out = []
        for i in range(1, n + 1):
            with open(os.path.join(self.so, "%d.argv" % i), "rb") as f:
                argv = [a.decode("utf-8") for a in f.read().split(b"\0")[:-1]]
            with open(os.path.join(self.so, "%d.pwd" % i)) as f:
                pwd = f.read().strip()
            out.append((argv, pwd))
        return out

    def script(self, verb, text):
        os.makedirs(self.so, exist_ok=True)
        with open(os.path.join(self.so, verb + ".script"), "w", encoding="utf-8") as f:
            f.write(text)

    def replies(self, ident):
        return [c for c in self.board.comments(ident) if c["content"].startswith("studio: ")
                and c["parent_id"]]

    def list_sinces(self, ident):
        return [c["argv"][c["argv"].index("--since") + 1] for c in self.board.calls("issue comment list")
                if c["argv"][3] == ident]

    def new_ctx(self):
        self.ctx = self.state.Ctx(self.cfg, self.paths, self.cli, self.log,
                                  lambda kind, text: self.notes.append((kind, text)),
                                  now=lambda: time.time() + self.skew)

    # ----- verbs and replies ---------------------------------------------------

    def test_say_reaches_core_and_replies_threaded(self):
        self.started()
        cid = self.say(self.sa, "/say hello")
        self.poll()
        calls = self.verbs()
        self.assertEqual([c[0] for c in calls], [["say", "--run", B, "A", "--", "hello"]])
        self.assertEqual(os.path.realpath(calls[0][1]), os.path.realpath(self.root))
        rep = self.replies(self.sa)
        self.assertEqual([(r["content"], r["parent_id"]) for r in rep], [("studio: ✓ ok", cid)])
        adds = [c["argv"] for c in self.board.calls("issue comment add") if "studio: ✓ ok" in c["argv"]
                or c["argv"][3] == self.sa and "--parent" in c["argv"]]
        self.assertTrue(any(a[a.index("--parent") + 1] == cid for a in adds))
        # a command that is itself a reply threads under its own parent
        root = self.say(self.sa, "thread start")
        cid2 = self.say(self.sa, "/said", parent=root)
        self.poll()
        self.assertEqual([r["parent_id"] for r in self.replies(self.sa)][-1], root)
        self.assertNotEqual(root, cid2)
        self.assertEqual(len(self.verbs()), 2)

    def test_verb_runs_in_its_own_root(self):
        root2 = make_project(self.tmp, "game2")
        run1 = self.started(root=self.root)
        ra = self.sb
        run2 = self.started(root=root2)
        rb = self.sb
        self.assertNotEqual(self.key(run1), self.key(run2))
        self.say(ra, "/hold")
        self.say(rb, "/hold")
        self.poll()
        calls = self.verbs()
        self.assertEqual(len(calls), 2)
        self.assertEqual({os.path.realpath(p) for _, p in calls},
                         {os.path.realpath(self.root), os.path.realpath(root2)})
        self.assertTrue(all(a == ["hold", "--run", B, "B"] for a, _ in calls))

    def test_unicode_text_roundtrip(self):
        self.started()
        self.say(self.sa, "/say héllo 🎮 世界\n/stop run")
        self.poll()
        self.assertEqual([a for a, _ in self.verbs()], [["say", "--run", B, "A", "--", "héllo 🎮 世界\n/stop run"]])

    def test_author_filter(self):
        self.started()
        self.say(self.sa, "/stop", author_type="agent", author_id="ag-1")
        self.say(self.sa, "/stop", author_id="m-other")
        self.say(self.ri, "/stop run", author_type="agent", author_id="ag-1")
        self.say(self.sa, "studio: /stop run")

        def bridge_post(st):
            c = self.mirror.post_comment(self.ctx, st, self.sa, "studio: /stop run")
            self.assertIsNotNone(c)
            self.assertTrue(c["id"] in st["posted"])
            # the posted-id guard on its own, without the prefix rule
            plain = dict(c, content="/stop run")
            self.assertFalse(commands._actionable(self.ctx, st, plain))
            self.assertTrue(commands._actionable(self.ctx, st, dict(plain, id="cm-other")))

        self.mutate(bridge_post)
        self.poll()
        self.assertEqual(self.verbs(), [])

    def test_first_cursor_is_issue_created_at(self):
        run = make_run(self.home, self.root, B, True, None)
        run.append(ev("run_started", mode="integration"), ev("story_listed", story="A", chain=1, depends=[]))
        self.board.set_now(1_000_000_000)
        self.poll()
        self.poll()
        ra = self.story_issue(run, "A")["identifier"]
        created = self.board.issue(ra)["created_at"]
        self.board.reset_calls()
        self.mutate(lambda st: (st["cursors"].clear(), st["cursor_ts"].clear(), st["seen"].clear()), run)
        self.say(ra, "/hold", at=bridgetest.stub.fmt(1_000_000_000 - 5))
        self.say(ra, "/said", at=bridgetest.stub.fmt(1_000_000_000))
        self.board.set_now(None)
        self.poll()
        self.assertEqual(self.list_sinces(ra)[0], created)
        self.assertEqual([a[0] for a, _ in self.verbs()], ["said"])

    def test_cursor_overlap_and_dedup(self):
        self.started()
        self.say(self.sa, "/hold")
        snap = max(self.state.parse_ts(c["created_at"]) for c in self.board.comments(self.sa))
        self.poll()
        self.poll()
        self.poll()
        sinces = self.list_sinces(self.sa)
        self.assertEqual(sinces[-2], self.state.fmt_since(snap - 60))
        self.assertEqual(len(self.verbs()), 1)

    def test_since_format(self):
        self.started()
        d = self.board.data()
        for r in d["issues"]:
            r["created_at"] = "2026-10-04T01:02:03.123456Z"
        self.board.save(d)
        self.mutate(lambda st: (st["cursors"].clear(), st["cursor_ts"].clear(), st["seen"].clear()))
        self.board.reset_calls()
        self.say(self.sa, "/said")
        self.poll()
        self.poll()
        sinces = [s for i in (self.ri, self.sa, self.sb) for s in self.list_sinces(i)]
        self.assertTrue(sinces)
        for s in sinces:
            self.assertRegex(s, r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$")

    def test_hands_off_issue_commands_never_run(self):
        self.started()
        self.board.assign(self.sa, "agent", "ag-1")
        self.say(self.sa, "/say nope")
        self.poll()
        self.assertEqual(self.verbs(), [])
        self.board.assign(self.sa, None, None)
        self.poll()
        self.poll()
        self.assertEqual(self.verbs(), [])

    def test_reply_post_fails_then_reposted_once(self):
        self.started()
        self.say(self.sa, "/say hi")
        self.board.fault("issue comment add", exit=1, stderr="503 service unavailable", count=1)
        with self.assertRaises(mc.TransientError):
            self.poll()
        self.assertEqual(self.replies(self.sa), [])
        self.poll()
        self.poll()
        self.assertEqual([r["content"] for r in self.replies(self.sa)], ["studio: ✓ ok"])
        self.assertEqual(len(self.verbs()), 1)

    def test_crash_before_core_call_gives_warn(self):
        self.started()
        self.say(self.sa, "/say hi")
        with mock.patch.object(studio, "call_verb", side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                self.poll()
        self.new_ctx()
        self.poll()
        self.assertEqual([r["content"] for r in self.replies(self.sa)], [commands.WARN])
        self.assertEqual(self.verbs(), [])
        self.poll()
        self.assertEqual(len(self.replies(self.sa)), 1)

    def test_crash_after_core_before_result_gives_warn(self):
        self.started()
        self.say(self.sa, "/say hi")
        with mock.patch.object(commands, "format_reply", side_effect=bridgetest.Crash("boom")):
            with self.assertRaises(bridgetest.Crash):
                self.poll()
        self.new_ctx()
        self.poll()
        self.assertEqual([r["content"] for r in self.replies(self.sa)], [commands.WARN])
        self.assertEqual(len(self.verbs()), 1)

    def test_crash_after_reply_before_done_no_second_reply(self):
        self.started()
        self.say(self.sa, "/say hi")
        real = self.mirror.post_comment

        def post_then_die(*a, **kw):
            real(*a, **kw)
            raise bridgetest.Crash("died after posting")

        with mock.patch.object(self.mirror, "post_comment", post_then_die):
            with self.assertRaises(bridgetest.Crash):
                self.poll()
        self.new_ctx()
        self.poll()
        self.poll()
        self.assertEqual([r["content"] for r in self.replies(self.sa)], ["studio: ✓ ok"])
        self.assertEqual(len(self.verbs()), 1)

    def test_repost_ignores_identical_older_reply(self):
        # D5 (#27 R11): two /hold commands in one thread give identical replies; the first
        # reply must not hide a missing second one.
        self.started()
        thread = self.say(self.sa, "thread start")
        self.say(self.sa, "/hold", parent=thread)
        self.poll()
        self.assertEqual(len(self.replies(self.sa)), 1)
        self.skew = 100.0                                   # the second command is 100 s later locally
        self.say(self.sa, "/hold", parent=thread)
        self.board.fault("issue comment add", exit=1, stderr="503 service unavailable", count=1)
        with self.assertRaises(mc.TransientError):
            self.poll()
        self.poll()
        self.poll()
        self.assertEqual([(r["content"], r["parent_id"]) for r in self.replies(self.sa)],
                         [("studio: ✓ ok", thread)] * 2)
        self.assertEqual(len(self.verbs()), 2)

    def test_stale_command_uses_clock_offset(self):
        self.started(behind=3600)                           # the server clock is 1 h behind local
        self.skew = 700.0                                   # ...and 700 s pass
        server_now = time.time() + self.skew - 3600
        self.board.set_now(server_now)
        fresh = self.say(self.sa, "/say fresh", at=bridgetest.stub.fmt(server_now - 300))
        old = self.say(self.sa, "/say old", at=bridgetest.stub.fmt(server_now - 660))
        self.poll()
        self.assertEqual([a[-1] for a, _ in self.verbs()], ["fresh"])
        got = {r["parent_id"]: r["content"] for r in self.replies(self.sa)}
        self.assertEqual(got[old], "studio: ✗ too old, repost")
        self.assertEqual(got[fresh], "studio: ✓ ok")

    def test_timeout_kills_group_and_replies(self):
        self.started()
        self.script("say", "spawn\nsleep 60\n")
        self.say(self.sa, "/say slow")
        with mock.patch.object(studio, "VERB_TIMEOUT", 5):
            self.poll()
        rep = self.replies(self.sa)
        self.assertEqual(len(rep), 1)
        self.assertTrue(rep[0]["content"].startswith("studio: ✗ "))
        self.assertTrue(rep[0]["content"].endswith("timed out after 5 s"))
        with open(os.path.join(self.so, "grandchild.pid")) as f:
            pid = int(f.read())
        self.assertTrue(bridgetest.wait_gone(pid), "the grandchild survived the group kill")

    def test_reply_cut_and_sanitized(self):
        self.started()
        self.script("say", "out @all mention://member/1 " + "y" * 3000 + "\n")
        self.say(self.sa, "/say big")
        self.poll()
        body = self.replies(self.sa)[0]["content"]
        # sanitize first, then cut: the brief's 1001-character cap holds on the posted text
        self.assertLessEqual(len(body), len("studio: ✓ ") + 1001)
        self.assertNotIn("@", body)
        self.assertIn("no-mention:", body)

    def test_journal_pruned_after_a_day(self):
        self.started()
        cid = self.say(self.sa, "/said")
        self.poll()
        self.assertEqual(self.load()["journal"][cid]["state"], "done")
        self.mutate(lambda st: st["journal"][cid].update(at=time.time() - 90000))
        self.poll()
        self.assertNotIn(cid, self.load()["journal"])
        self.assertEqual(len(self.verbs()), 1)

    # ----- fix round (T8 review) ---------------------------------------------------

    def test_command_posted_while_assigned_never_runs_after_unassign(self):
        # R43 (I1): the comment lands after the last hands-off poll and before the unassign
        self.started()
        self.board.assign(self.sa, "agent", "ag-1")
        self.poll()
        self.say(self.sa, "/say posted while assigned")
        self.board.assign(self.sa, None, None)
        self.skew = 10.0                                    # the unassign is noticed 10 s later (frozen test clock)
        self.poll()
        self.poll()
        self.assertEqual(self.verbs(), [])
        self.say(self.sa, "/say later", at=bridgetest.stub.fmt(time.time() + 30))
        self.poll()
        self.assertEqual([a[-1] for a, _ in self.verbs()], ["later"])

    def test_identical_replies_one_failed_post_both_replied(self):
        # m1: reply 1's id is in st["posted"], so it can never stand in for reply 2
        self.started()
        thread = self.say(self.sa, "thread start")
        self.say(self.sa, "/said", parent=thread)
        self.say(self.sa, "/said", parent=thread)
        real, n = self.mirror.post_comment, []

        def second_fails(*a, **kw):
            n.append(1)
            if len(n) == 2:
                raise mc.TransientError("503", "", 1)
            return real(*a, **kw)

        with mock.patch.object(self.mirror, "post_comment", second_fails):
            with self.assertRaises(mc.TransientError):
                self.poll()
        self.poll()
        self.poll()
        self.assertEqual(len(self.verbs()), 2)
        self.assertEqual([r["parent_id"] for r in self.replies(self.sa)], [thread, thread])

    def test_core_cannot_start_replies_cross_not_warn(self):
        # m2: Popen failure or a NUL in the text: the verb certainly did not run
        self.started()
        for exc in (FileNotFoundError("no such file"), ValueError("embedded null byte")):
            self.say(self.sa, "/say hi")
            with mock.patch.object(studio, "call_verb", side_effect=exc):
                self.poll()
        got = [r["content"] for r in self.replies(self.sa)]
        self.assertEqual(len(got), 2)
        self.assertTrue(all(g.startswith("studio: ✗ cannot run studio-overnight: ") for g in got), got)

    def _pending_reply(self):
        self.started()
        cid = self.say(self.sa, "/said")
        self.board.fault("issue comment add", exit=1, stderr="503 service unavailable", count=1)
        with self.assertRaises(mc.TransientError):
            self.poll()
        self.assertEqual(self.load()["journal"][cid]["attempts"], 1)
        return cid

    def test_hands_off_pending_reply_costs_no_attempt_and_no_list_call(self):
        cid = self._pending_reply()
        self.board.assign(self.sa, "agent", "ag-1")
        self.board.reset_calls()
        self.poll()
        self.poll()
        e = self.load()["journal"][cid]
        self.assertEqual((e["state"], e["attempts"]), ("result", 1))
        # only the two ordinary reads of the issue's comments; no extra list for the pending reply
        self.assertEqual(len([c for c in self.board.calls("issue comment list") if c["argv"][3] == self.sa]), 2)
        self.board.assign(self.sa, None, None)
        self.poll()
        self.poll()
        self.assertEqual([r["content"] for r in self.replies(self.sa)], ["studio: ✓ ok"])

    def test_permanent_post_error_drops_the_reply_after_three_attempts(self):
        self.started()
        cid = self.say(self.sa, "/said")
        self.board.fault("issue comment add", exit=1, stderr="invalid request body", count=3)
        for _ in range(4):
            self.poll()
        e = self.load()["journal"][cid]
        self.assertEqual((e["state"], e["attempts"]), ("done", 3))
        self.assertEqual(self.replies(self.sa), [])
        self.assertEqual(len(self.verbs()), 1)

    def test_reply_pending_at_retirement_is_posted_first(self):
        # m4: the run ends while a reply still waits: it is posted before the state retires
        self._pending_reply()
        self.run.append(ev("run_ended", ending="done", report="/r/report.md"))
        self.poll()
        self.assertTrue(self.load() is None or self.load().get("retired"))
        self.assertEqual([r["content"] for r in self.replies(self.sa)], ["studio: ✓ ok"])

    def test_agent_authored_comment_with_the_operator_id_is_ignored(self):
        self.started()
        self.say(self.sa, "/hold", author_type="agent", author_id=bridgetest.OPERATOR)
        self.poll()
        self.assertEqual(self.verbs(), [])

    def test_lone_cr_is_a_line_break(self):
        self.assertEqual(commands.parse("/say a\rb"), ("say", "a\nb"))

    def test_repost_check_under_a_nonzero_clock_offset(self):
        # m5: the server clock is 1 h behind; the reply is on the board, the journal says not done
        self.started(behind=3600)
        self.say(self.sa, "/say hi")
        real = self.mirror.post_comment

        def post_then_die(*a, **kw):
            real(*a, **kw)
            raise bridgetest.Crash("died after posting")

        with mock.patch.object(self.mirror, "post_comment", post_then_die):
            with self.assertRaises(bridgetest.Crash):
                self.poll()
        self.assertLess(self.load()["clock_offset"], -3000)
        self.new_ctx()
        self.poll()
        self.poll()
        self.assertEqual([r["content"] for r in self.replies(self.sa)], ["studio: ✓ ok"])
        self.assertEqual(len(self.verbs()), 1)


if __name__ == "__main__":
    unittest.main()
