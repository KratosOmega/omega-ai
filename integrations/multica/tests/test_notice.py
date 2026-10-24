"""Hold-notice texts, the held-set step and the notify-only CLI door (#85 Task 1)."""
import os
import time
import unittest
from unittest import mock

import bridgetest  # noqa: F401  (puts the bridge package on sys.path)
from bridgetest import BridgeCase
from bridge import multica_cli as mc
from bridge import notice

RUN = "overnight-bat-20261022-142751"
U = "2026-10-04T01:00:00Z"


def _pst(case):
    p = mock.patch.dict(os.environ, {"TZ": "PST8PDT"})
    case.addCleanup(time.tzset)          # LIFO: runs after the env patch is stopped
    p.start()
    case.addCleanup(p.stop)
    time.tzset()


class NoticeTextTest(unittest.TestCase):
    def setUp(self):
        _pst(self)

    def test_reminder_body_story_and_single(self):                             # #92
        self.assertEqual(notice.reminder_body("B", "need art", U),
                         "story B still held — stops at 2026-10-03 18:00 PDT (2026-10-04T01:00:00Z UTC) unless resumed. Why: need art")
        self.assertEqual(notice.reminder_body("-", "need art", U),
                         "the run is still held — stops at 2026-10-03 18:00 PDT (2026-10-04T01:00:00Z UTC) unless resumed. Why: need art")
        self.assertEqual(notice.reminder_body("B", "w", "soon"), "story B still held — stops at soon unless resumed. Why: w")
        self.assertEqual(notice.reminder_body("B", "w", None), "story B still held — stops at ? unless resumed. Why: w")

    def test_until_line_local_and_utc(self):
        self.assertEqual(notice.until_line(U), "Until 2026-10-03 18:00 PDT (2026-10-04T01:00:00Z UTC); then it stops.")

    def test_until_line_unparsable(self):
        for u in ("u", "", None):
            self.assertEqual(notice.until_line(u), "Until %s; then it stops." % (u if u is not None else "?"))

    def test_is_expiry_table(self):
        yes = ["stop: need art (held 8h0m, no reply)", "no progress on T3 (held 0h30m, no reply)",
               "x (held 24h0m, no reply)"]
        no = ["stopped by operator", "stop: need art", "stopped by user (was held: x (held 1h0m, no reply))",
              "x (held 8m, no reply)", "x(held 8h0m, no reply)", "x (held 8h0m, no reply) ", "", None]
        for w in yes:
            self.assertTrue(notice.is_expiry(w), w)
        for w in no:
            self.assertFalse(notice.is_expiry(w), w)

    def test_held_after_table(self):
        h = lambda st, s="A": {"event": "story_state", "story": s, "state": st}
        self.assertEqual(notice.held_after([], h("held")), ["A"])
        self.assertEqual(notice.held_after(["A"], h("held")), ["A"])
        self.assertEqual(notice.held_after(["A", "B"], h("running")), ["B"])
        self.assertEqual(notice.held_after(["B"], h("debug-repair")), ["B"])
        self.assertEqual(notice.held_after(["A"], h("debug-repair")), [])
        self.assertEqual(notice.held_after(["A"], {"event": "unit_started", "story": "A"}), ["A"])
        src = ["A"]
        notice.held_after(src, h("running"))
        self.assertEqual(src, ["A"])

    def test_hold_body_manifest_exact(self):
        self.assertEqual(notice.hold_body("B", "stop: need art", U, "OMEG-117", RUN), "\n".join([
            "story B held: stop: need art",
            "Until 2026-10-03 18:00 PDT (2026-10-04T01:00:00Z UTC); then it stops.",
            "Multica: on OMEG-117 post /say <text>, then /resume — or /stop.",
            "Terminal: studio-overnight say B --run %s -- <text> · studio-overnight resume B --run %s"
            " · studio-overnight stop B --run %s" % (RUN, RUN, RUN)]))

    def test_hold_body_single(self):
        b = notice.hold_body("-", "w", U, "OMEG-12", RUN).split("\n")
        self.assertEqual(b[0], "the run is held: w")
        self.assertEqual(b[2], "Multica: on OMEG-12 post /say <text>, then /resume — or /stop.")
        self.assertIn("studio-overnight resume - --run %s" % RUN, b[3])

    def test_hold_body_routed(self):
        self.assertEqual(notice.hold_body("B", "w", "u", None, RUN).split("\n")[1:3],
                         ["Until u; then it stops.", "Multica: B has no issue — use the terminal."])

    def test_expiry_body(self):
        w = "stop: need art (held 8h0m, no reply)"
        self.assertEqual(notice.expiry_body("B", w), "story B stopped — hold ran out with no reply. Why: " + w)
        self.assertEqual(notice.expiry_body("-", w), "the run stopped — hold ran out with no reply. Why: " + w)

    def test_kickoff_text_marker_and_tail(self):
        t = notice.kickoff_text("story B held: w")
        self.assertTrue(t.startswith("studio: [notify only] story B held: w\n"))
        self.assertTrue(t.endswith("\nNotify only: reply with one short line. Run no command; "
                                   "never resume, stop, say to or hold a story."))

    def test_banner_text(self):
        self.assertEqual(notice.banner_text("B", RUN, "w"), "B held in %s: w" % RUN)
        self.assertEqual(notice.banner_text("-", RUN, "w"), "run held in %s: w" % RUN)
        self.assertEqual(notice.banner_text("B", RUN, expired=True), "B stopped in %s: hold ran out" % RUN)


class NoticeCliTest(BridgeCase):
    def setUp(self):
        super().setUp()
        _pst(self)

    def test_add_notice_bypasses_guard_but_checks_marker(self):
        self.board.add_issue("request")
        self.board.reset_calls()
        self.cli.forbidden.add("OMEG-1")
        c = self.cli.add_notice("OMEG-1", "studio: [notify only] story B held: [x](mention://agent/1)")
        self.assertTrue(c["id"])
        self.assertEqual(self.board.calls("issue comment add")[0]["argv"][:5],
                         ["issue", "comment", "add", "OMEG-1", "--content-stdin"])
        self.assertIn("no-mention:", self.board.comments("OMEG-1")[0]["content"])
        self.assertTrue(self.board.comments("OMEG-1")[0]["content"].startswith("studio: [notify only] "))   # AC4
        for bad in ("studio: held: x", "[notify only] x", " studio: [notify only] x"):
            with self.assertRaises(ValueError):
                self.cli.add_notice("OMEG-1", bad)
        with self.assertRaises(mc.ForbiddenWrite):
            self.cli.add_comment("OMEG-1", "studio: [notify only] x")
        with self.assertRaises(mc.ForbiddenWrite):
            self.cli.set_status("OMEG-1", "done")
        self.assertEqual(len(self.board.calls("issue comment add")), 1)


if __name__ == "__main__":
    unittest.main()
