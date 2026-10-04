"""One end-to-end run: the bridge as a subprocess in `once` mode between event appends (#28)."""
from __future__ import annotations

import os
import pwd
import subprocess
import sys
import unittest

from bridgetest import MirrorCase, TOKEN, TESTS, MULTICA, ev, make_project, make_run

B = "overnight-20261003-2214"
BIN = os.path.join(MULTICA, "bin", "multica-bridge")


class EndToEndTest(MirrorCase):
    def setUp(self):
        super().setUp()
        self.root = make_project(self.tmp, "game")
        os.makedirs(self.paths.base, exist_ok=True)
        with open(self.cfg_path, encoding="utf-8") as f, open(self.paths.config, "w", encoding="utf-8") as g:
            g.write(f.read())
        self.sec = os.path.join(self.tmp, "sec")
        os.makedirs(self.sec)
        with open(os.path.join(self.sec, "omega-multica-bridge-" + pwd.getpwuid(os.getuid()).pw_name), "w") as f:
            f.write(TOKEN + "\n")
        self.so = os.path.join(self.tmp, "so")
        self.env = dict(os.environ, HOME=self.home, OMEGA_MULTICA_SECURITY=os.path.join(TESTS, "stub-security"),
                        STUB_SECURITY_DIR=self.sec, OMEGA_MULTICA_OSASCRIPT="/usr/bin/true",
                        STUB_SO_DIR=self.so)

    def once(self):
        r = subprocess.run([sys.executable, BIN, "once"], env=self.env, capture_output=True, text=True,
                           timeout=120)
        self.assertEqual(r.returncode, 0, r.stderr)

    def verbs(self):
        out = []
        n = 0
        p = os.path.join(self.so, "n")
        if os.path.exists(p):
            with open(p) as f:
                n = int(f.read())
        for i in range(1, n + 1):
            with open(os.path.join(self.so, "%d.argv" % i), "rb") as f:
                out.append([a.decode("utf-8") for a in f.read().split(b"\0")[:-1]])
        return out

    def replies(self, ident):
        return [c["content"] for c in self.board.comments(ident) if c["parent_id"]]

    def test_whole_run_one_poll_per_step(self):
        run = make_run(self.home, self.root, B, True, None)
        run.append(ev("run_started", mode="integration"),
                   ev("story_listed", story="A", chain=1, depends=[]),
                   ev("story_listed", story="B", chain=1, depends=[]))
        self.once()
        ri = self.run_issue(run)["identifier"]
        sa, sb = self.story_issue(run, "A")["identifier"], self.story_issue(run, "B")["identifier"]
        self.assertEqual(self.board.issue(ri)["status"], "in_progress")
        self.assertTrue(sa and sb)

        run.append(ev("story_state", story="A", state="running"),
                   ev("unit_started", story="A", unit="u1", label="work"))
        self.once()
        self.assertEqual(self.board.issue(sa)["status"], "in_progress")
        self.assertIn("studio: unit u1 (work) started", self.comments_on(sa))

        cid = self.board.add_comment(sa, "/say hello")
        self.once()
        self.assertEqual(self.verbs(), [["say", "--run", B, "A", "--", "hello"]])
        self.assertEqual(self.replies(sa), ["studio: ✓ ok"])
        self.assertTrue(cid)

        run.append(ev("message_queued", story="A", id=1, scope="story"),
                   ev("message_delivered", story="A", id=1, scope="story", unit="u1", via="tool_call"))
        self.once()
        self.assertIn("studio: message 1 queued (story)", self.comments_on(sa))
        self.assertIn("studio: message 1 delivered to unit u1", self.comments_on(sa))

        self.board.add_comment(sb, "/hold")
        self.once()
        self.assertEqual(self.verbs()[-1], ["hold", "--run", B, "B"])
        self.assertEqual(self.replies(sb), ["studio: ✓ ok"])

        run.append(ev("story_state", story="B", state="held", why="need art", until="2026-10-04T08:00:00Z"))
        self.once()
        self.assertEqual(self.board.issue(sb)["status"], "blocked")
        self.assertTrue(any(c.startswith("studio: held: need art") for c in self.comments_on(sb)))

        self.board.add_comment(sb, "/resume")
        self.once()
        self.assertEqual(self.verbs()[-1], ["resume", "--run", B, "B"])
        self.assertEqual(self.replies(sb), ["studio: ✓ ok", "studio: ✓ ok"])

        run.append(ev("run_ended", ending="done", report="/r/report.md"))
        self.once()
        self.assertEqual(self.comments_on(ri)[-1], "studio: run ended: done — report: /r/report.md")
        self.assertEqual(self.board.issue(ri)["status"], "done")

        self.once()
        self.assertIn(self.key(run), self.state.load_retired(self.paths))
        self.assertEqual(self.state.tracked_keys(self.paths), [])
        self.assertTrue(os.path.exists(self.paths.status))


if __name__ == "__main__":
    unittest.main()
