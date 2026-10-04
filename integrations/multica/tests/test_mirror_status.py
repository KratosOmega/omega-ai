"""Mirror part 2: intended statuses, hands-off issues, catch-up and repair (#28)."""
from __future__ import annotations

import unittest
from unittest import mock

import bridgetest
from bridgetest import MirrorCase, ev, make_project, make_run
from bridge import multica_cli as mc


class MirrorStatusTest(MirrorCase):
    def setUp(self):
        super().setUp()
        self.root = make_project(self.tmp, "game")

    # ----- helpers -----------------------------------------------------------

    def started(self, with_story=True):
        """A live run with Run issue and story A in_progress on the board."""
        run = make_run(self.home, self.root, "overnight-20261003-2214", True, None)
        events = [ev("run_started", mode="integration")]
        if with_story:
            events += [ev("story_listed", story="A", chain=1, depends=[]), ev("story_state", story="A", state="running")]
        run.append(*events)
        self.poll()
        self.poll()
        self.ri = self.run_issue(run)["identifier"]
        self.sa = self.story_issue(run, "A")["identifier"] if with_story else None
        return run

    def writes_to(self, ident):
        out = []
        for c in self.board.calls():
            a = c["argv"]
            if a[:2] == ["issue", "status"] and a[2] == ident:
                out.append(a)
            if a[:3] == ["issue", "comment", "add"] and a[3] == ident:
                out.append(a)
        return out

    def status_of(self, ident):
        return self.board.issue(ident)["status"]

    def tracked(self):
        return self.state.tracked_keys(self.paths)

    def load(self, run):
        return self.state.load_run(self.paths, self.key(run))

    # ----- the list ----------------------------------------------------------

    def test_one_list_per_run_per_poll_paged(self):
        run = self.started(with_story=False)
        for i in range(120):
            self.board.add_issue("x%d" % i, props={"omega_run": self.key(run), "omega_story": "s%d" % i})
        self.board.reset_calls()
        self.poll()
        lists = [c["argv"] for c in self.board.calls("issue list") if "--offset" in c["argv"]]
        self.assertEqual(len(lists), 2)
        self.assertEqual([a[a.index("--offset") + 1] for a in lists], ["0", "100"])

    # ----- hands-off ---------------------------------------------------------

    def test_agent_assigned_story_gets_zero_writes(self):
        run = self.started()
        self.board.assign(self.sa, "agent", "ag-1")
        self.board.reset_calls()
        run.append(ev("story_state", story="A", state="held", why="w", until="u"),
                   ev("unit_started", story="A", unit="u1", label="work"),
                   ev("unit_ended", story="A", unit="u1", label="work", outcome="done", usd=1),
                   ev("story_state", story="A", state="landed"))
        self.poll()
        self.assertEqual(self.writes_to(self.sa), [])
        self.assertEqual(self.status_of(self.sa), "in_progress")

    def test_squad_assignee_is_hands_off(self):
        self.assertTrue(self.mirror.is_hands_off({"assignee_type": "squad"}))
        self.assertTrue(self.mirror.is_hands_off({"assignee_type": "agent"}))
        run = self.started()
        self.board.assign(self.sa, "squad", "sq-1")
        self.board.reset_calls()
        run.append(ev("unit_started", story="A", unit="u1", label="work"))
        self.poll()
        self.assertEqual(self.writes_to(self.sa), [])

    def test_member_assignee_is_not(self):
        self.assertFalse(self.mirror.is_hands_off({"assignee_type": "member"}))
        self.assertFalse(self.mirror.is_hands_off({"assignee_type": None}))
        run = self.started()
        self.board.assign(self.sa, "member", "m-op")
        run.append(ev("unit_started", story="A", unit="u1", label="work"))
        self.poll()
        self.assertIn("studio: unit u1 (work) started", self.comments_on(self.sa))

    def test_assignee_appears_between_list_and_write(self):
        run = self.started()
        orig = self.mirror.refresh

        def wrapped(ctx, st):
            orig(ctx, st)
            self.board.assign(self.sa, "agent", "ag-1")

        run.append(ev("story_state", story="A", state="held", why="w", until="u"))
        self.board.reset_calls()
        with mock.patch.object(self.mirror, "refresh", wrapped):
            self.poll()
        self.assertTrue(self.board.calls("issue get"))
        self.assertEqual(self.writes_to(self.sa), [])
        self.assertEqual(self.status_of(self.sa), "in_progress")

    def test_run_issue_hands_off_holds_story_closures(self):
        run = self.started()
        self.board.assign(self.ri, "agent", "ag-1")
        run.append(ev("story_state", story="A", state="landed"))
        self.poll()
        self.assertEqual(self.status_of(self.sa), "in_progress")
        self.board.assign(self.ri, None, None)
        self.poll()
        self.assertEqual(self.status_of(self.sa), "done")

    def test_catch_up_on_unassign(self):
        run = self.started()
        self.board.assign(self.sa, "agent", "ag-1")
        run.append(ev("story_state", story="A", state="held", why="w", until="u"),
                   ev("unit_started", story="A", unit="u1", label="work"))
        self.poll()
        self.board.reset_calls()
        self.board.assign(self.sa, None, None)
        self.poll()
        self.assertEqual([t for t in self.comments_on(self.sa) if "while assigned" in t],
                         ["studio: while assigned: in_progress → blocked, 2 unit events"])
        calls = self.writes_to(self.sa)
        self.assertEqual([a[1] for a in calls], ["comment", "status"])
        self.assertEqual(calls[1][3], "blocked")
        self.assertEqual(self.status_of(self.sa), "blocked")
        self.poll()
        self.assertEqual(len(self.writes_to(self.sa)), 2)

    def test_run_ended_while_hands_off_retired_after_catch_up(self):
        run = self.started(with_story=False)
        self.board.assign(self.ri, "agent", "ag-1")
        run.append(ev("run_ended", ending="completed", report="/r/report.md"))
        self.poll()
        self.poll()
        self.assertEqual(self.tracked(), [self.key(run)])
        self.assertNotEqual(self.status_of(self.ri), "done")
        self.board.reset_calls()
        self.board.assign(self.ri, None, None)
        self.poll()
        self.assertEqual([a[1] for a in self.writes_to(self.ri)], ["comment", "comment", "status"])
        texts = [t for t in self.comments_on(self.ri) if t.startswith("studio: while") or "run ended" in t]
        self.assertTrue(texts[0].startswith("studio: run ended: completed"))      # R40: the held end first
        self.assertTrue(texts[1].startswith("studio: while assigned"))
        self.assertEqual(self.status_of(self.ri), "done")
        self.assertEqual(self.tracked(), [])

    TRANSIENT = "Could not connect to the Multica server. Make sure the server address is correct and reachable."

    def test_no_state_changes_text(self):
        run = self.started()
        self.board.assign(self.sa, "agent", "ag-1")
        run.append(ev("unit_started", story="A", unit="u1", label="work"))
        self.poll()
        self.board.assign(self.sa, None, None)
        self.poll()
        got = [t for t in self.comments_on(self.sa) if "while assigned" in t]
        self.assertEqual(got, ["studio: while assigned: no state changes, 1 unit events"])

    def test_stop_note_once_across_transient(self):
        run = self.started()
        self.board.set_status(self.sa, "done")
        run.append(ev("unit_started", story="A", unit="u1", label="work"))
        self.board.fault("issue get", contains=self.sa, exit=2, stderr=self.TRANSIENT)
        with self.assertRaises(mc.TransientError):
            self.poll()
        self.poll()
        notes = [t for t in self.comments_on(self.ri) if "leaves its status alone" in t]
        self.assertEqual(len(notes), 1, notes)

    def test_catch_up_once_across_transient(self):
        run = self.started()
        self.board.assign(self.sa, "agent", "ag-1")
        run.append(ev("story_state", story="A", state="held", why="w", until="u"))
        self.poll()
        self.board.assign(self.sa, None, None)
        self.board.fault("issue status", exit=2, stderr=self.TRANSIENT)
        with self.assertRaises(mc.TransientError):
            self.poll()
        self.poll()
        got = [t for t in self.comments_on(self.sa) if "while assigned" in t]
        self.assertEqual(got, ["studio: while assigned: in_progress → blocked, 1 unit events"])
        self.assertEqual(self.status_of(self.sa), "blocked")

    def test_catch_up_transient_on_the_comment_resumes_without_repeating_the_end(self):
        run = self.started(with_story=False)
        self.board.assign(self.ri, "agent", "ag-1")
        run.append(ev("run_ended", ending="completed", report="/r/report.md"))
        self.poll()
        self.board.assign(self.ri, None, None)
        self.board.fault("issue comment add", exit=2, stderr=self.TRANSIENT)      # the held end is posted first
        with self.assertRaises(mc.TransientError):
            self.poll()
        self.poll()
        texts = self.comments_on(self.ri)
        self.assertEqual(len([t for t in texts if t.startswith("studio: run ended:")]), 1)
        self.assertEqual(len([t for t in texts if "while assigned" in t]), 1)
        self.assertEqual(self.status_of(self.ri), "done")
        self.assertEqual(self.tracked(), [])

    def test_catch_up_4xx_then_next_poll_posts_it_exactly_once(self):
        run = self.started()
        self.board.assign(self.sa, "agent", "ag-1")
        run.append(ev("story_state", story="A", state="held", why="w", until="u"))
        self.poll()
        self.board.assign(self.sa, None, None)
        self.board.fault("issue comment add", exit=1, stderr="Invalid request")
        self.poll()                                   # the 4xx is isolated to the run; no catch-up posted yet
        self.assertEqual([t for t in self.comments_on(self.sa) if "while assigned" in t], [])
        self.poll()
        self.poll()
        self.assertEqual([t for t in self.comments_on(self.sa) if "while assigned" in t],
                         ["studio: while assigned: in_progress → blocked, 1 unit events"])
        self.assertEqual(self.status_of(self.sa), "blocked")

    def test_catch_up_4xx_on_run_issue_keeps_the_held_end(self):
        run = self.started(with_story=False)
        self.board.assign(self.ri, "agent", "ag-1")
        run.append(ev("run_ended", ending="completed", report="/r/report.md"))
        self.poll()
        self.board.assign(self.ri, None, None)
        self.board.fault("issue comment add", exit=1, stderr="Invalid request")
        self.poll()
        self.poll()
        texts = self.comments_on(self.ri)
        self.assertEqual(len([t for t in texts if t.startswith("studio: run ended:")]), 1)
        self.assertEqual(len([t for t in texts if "while assigned" in t]), 1)
        self.assertEqual(self.status_of(self.ri), "done")

    def test_comment_only_event_racing_an_assignment(self):
        run = self.started()
        orig = self.mirror.refresh

        def wrapped(ctx, st):
            orig(ctx, st)
            self.board.assign(self.sa, "agent", "ag-1")

        run.append(ev("unit_started", story="A", unit="u1", label="work"))
        self.board.reset_calls()
        with mock.patch.object(self.mirror, "refresh", wrapped):
            self.poll()
        self.assertTrue(self.board.calls("issue get"))
        self.assertEqual(self.writes_to(self.sa), [])
        self.board.assign(self.sa, None, None)
        self.poll()
        self.assertEqual([t for t in self.comments_on(self.sa) if "while assigned" in t],
                         ["studio: while assigned: no state changes, 1 unit events"])

    def test_agent_closing_a_handed_off_story_draws_no_stop_note(self):
        run = self.started()
        self.board.assign(self.sa, "agent", "ag-1")
        self.board.set_status(self.sa, "done")
        run.append(ev("story_state", story="A", state="held", why="w", until="u"))
        self.board.reset_calls()
        self.poll()
        self.poll()
        self.assertEqual([t for t in self.comments_on(self.ri) if "leaves its status alone" in t], [])
        self.assertEqual(self.writes_to(self.sa), [])

    def test_held_closure_applied_and_run_retired_by_the_catch_up(self):
        run = self.started()
        self.board.assign(self.ri, "agent", "ag-1")
        run.append(ev("story_state", story="A", state="landed"), ev("run_ended", ending="completed", report="/r"))
        self.poll()
        self.poll()
        self.assertEqual(self.status_of(self.sa), "in_progress")
        run.append(ev("unit_started", story="A", unit="u9", label="late"))
        self.board.assign(self.ri, None, None)
        self.poll()
        self.assertEqual(self.status_of(self.sa), "done")
        self.assertEqual(self.status_of(self.ri), "done")
        self.assertEqual(self.tracked(), [])
        self.assertFalse(any("u9" in t for t in self.comments_on(self.sa)))      # retired before the log was read again

    def test_vanished_issue_in_reconcile_is_dropped_not_polled_every_time(self):
        run = self.started()
        st = self.load(run)
        st["intended"][self.sa] = "blocked"
        self.state.save_run(self.paths, st)
        self.board.remove_issue(self.sa)
        self.poll()
        self.assertNotIn(self.sa, self.load(run)["intended"])
        self.board.reset_calls()
        self.poll()
        self.assertEqual([c for c in self.board.calls("issue get") if self.sa in c["argv"]], [])

    def test_reopen_after_timed_out_terminal_write_is_noticed(self):
        run = self.started()
        self.board.fault("issue status", apply=True, exit=1, stderr="503 service unavailable")
        run.append(ev("story_state", story="A", state="landed"))
        with self.assertRaises(mc.TransientError):
            self.poll()
        self.poll()
        self.board.set_status(self.sa, "todo")
        self.board.reset_calls()
        self.poll()
        self.poll()
        self.assertEqual(self.status_calls(), [])
        self.assertEqual(len([t for t in self.comments_on(self.ri) if "reopened by someone else" in t]), 1)

    def test_status_closed_by_someone_between_list_and_write_is_left_alone(self):
        run = self.started()
        orig = self.mirror.refresh

        def wrapped(ctx, st):
            orig(ctx, st)
            self.board.set_status(self.sa, "done")

        run.append(ev("story_state", story="A", state="held", why="w", until="u"))
        self.board.reset_calls()
        with mock.patch.object(self.mirror, "refresh", wrapped):
            self.poll()
        self.assertEqual([a for a in self.status_calls() if a[2] == self.sa], [])
        self.assertEqual(self.status_of(self.sa), "done")
        self.assertEqual(len([t for t in self.comments_on(self.ri) if "leaves its status alone" in t]), 1)

    def test_runner_gone_while_run_issue_hands_off_catches_up_then_retires(self):
        run = self.started(with_story=False)
        self.board.assign(self.ri, "agent", "ag-1")
        run.kill()
        for _ in range(self.mirror.GONE_POLLS + 1):
            self.poll()
        self.assertEqual(self.tracked(), [self.key(run)])
        self.assertEqual([t for t in self.comments_on(self.ri) if "runner gone" in t], [])
        self.board.assign(self.ri, None, None)
        self.poll()
        texts = self.comments_on(self.ri)
        gone = [i for i, t in enumerate(texts) if "runner gone" in t]
        line = [i for i, t in enumerate(texts) if "while assigned" in t]
        self.assertEqual((len(gone), len(line)), (1, 1))
        self.assertLess(gone[0], line[0])
        self.assertEqual(self.tracked(), [])
        self.poll()
        self.assertEqual(len([t for t in self.comments_on(self.ri) if "runner gone" in t]), 1)

    # ----- repair ------------------------------------------------------------

    def test_non_terminal_drag_set_back(self):
        self.started()
        self.board.set_status(self.sa, "todo")
        self.board.reset_calls()
        self.poll()
        self.assertEqual(self.status_of(self.sa), "in_progress")
        calls = self.status_calls()
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0][:5], ["issue", "status", self.sa, "in_progress", "--no-start"])

    def test_done_by_someone_else_left_alone_with_note(self):
        run = self.started()
        self.board.set_status(self.sa, "done")
        self.poll()
        self.board.reset_calls()
        run.append(ev("story_state", story="A", state="held", why="w", until="u"))
        self.poll()
        self.poll()
        notes = [t for t in self.comments_on(self.ri) if "leaves its status alone" in t]
        self.assertEqual(len(notes), 1)
        self.assertEqual([a for a in self.status_calls() if a[2] == self.sa], [])
        self.assertEqual(self.status_of(self.sa), "done")

    def test_reopen_left_alone_with_note(self):
        run = self.started()
        run.append(ev("story_state", story="A", state="landed"))
        self.poll()
        self.assertEqual(self.status_of(self.sa), "done")
        self.board.set_status(self.sa, "todo")
        self.board.reset_calls()
        self.poll()
        self.poll()
        notes = [t for t in self.comments_on(self.ri) if "reopened by someone else" in t]
        self.assertEqual(len(notes), 1)
        self.assertEqual(self.status_calls(), [])
        self.assertEqual(self.status_of(self.sa), "todo")

    def test_timed_out_write_found_applied_counts_success(self):
        run = self.started()
        self.board.fault("issue status", apply=True, exit=1, stderr="503 service unavailable")
        run.append(ev("story_state", story="A", state="held", why="w", until="u"))
        with self.assertRaises(mc.TransientError):
            self.poll()
        self.assertEqual(self.status_of(self.sa), "blocked")
        self.board.reset_calls()
        self.poll()
        self.assertEqual(self.status_calls(), [])
        self.assertTrue(any(t.startswith("studio: held:") for t in self.comments_on(self.sa)))
        self.assertGreater(self.load(run)["offset"], 0)

    def test_custom_status_is_non_terminal(self):
        self.started()
        self.board.set_status(self.sa, "in_review")
        self.board.reset_calls()
        self.poll()
        self.assertEqual(self.status_of(self.sa), "in_progress")

    def test_no_start_on_every_status_call(self):
        run = self.started()
        run.append(ev("story_state", story="A", state="held", why="w", until="u"),
                   ev("story_state", story="A", state="running"),
                   ev("story_state", story="A", state="landed"),
                   ev("run_ended", ending="completed", report="/r"))
        self.board.set_status(self.ri, "todo")
        self.poll()
        calls = self.status_calls()
        self.assertGreaterEqual(len(calls), 4)
        for argv in calls:
            self.assertIn("--no-start", argv)

    # ----- T7 re-review ---------------------------------------------------------

    def _held_end(self):
        run = self.started(with_story=False)
        self.board.assign(self.ri, "agent", "ag-1")
        run.append(ev("run_ended", ending="completed", report="/r/report.md"))
        self.poll()
        self.board.assign(self.ri, None, None)
        return run

    def test_rehandoff_during_a_pending_catch_up_keeps_the_held_end(self):        # N-1
        self._held_end()
        self.board.fault("issue comment add", exit=1, stderr="Invalid request")
        self.poll()
        self.board.assign(self.ri, "agent", "ag-1")
        self.poll()
        self.board.assign(self.ri, None, None)
        self.poll()
        self.poll()
        texts = self.comments_on(self.ri)
        self.assertEqual(len([t for t in texts if t.startswith("studio: run ended:")]), 1, texts)
        self.assertEqual(self.tracked(), [])

    def test_persistent_4xx_on_catch_up_gives_up_after_three_polls(self):          # N-2
        self._held_end()
        self.board.fault("issue comment add", exit=1, stderr="Invalid request", count=-1)
        for _ in range(6):
            self.poll()
        self.assertEqual(self.tracked(), [])
        self.assertEqual(self.status_of(self.ri), "done")

    def test_catch_up_post_is_not_counted_as_a_unit_event(self):                   # N-3
        run = self.started()
        self.board.assign(self.sa, "agent", "ag-1")
        run.append(ev("unit_started", story="A", unit="u1", label="a"), ev("unit_started", story="A", unit="u2", label="b"))
        self.poll()
        self.board.assign(self.sa, None, None)
        orig = self.mirror.catch_up

        def reassigned(ctx, st, ident):
            self.board.assign(self.sa, "agent", "ag-1")
            orig(ctx, st, ident)

        with mock.patch.object(self.mirror, "catch_up", reassigned):
            self.poll()
        self.board.assign(self.sa, None, None)
        self.poll()
        self.assertEqual([t for t in self.comments_on(self.sa) if "while assigned" in t],
                         ["studio: while assigned: no state changes, 2 unit events"])

    def test_transient_on_the_line_does_not_repeat_the_end(self):                  # N-4
        self._held_end()
        real = self.cli.add_comment
        left = [1]

        def flaky(ident, text, parent=None):
            if text.startswith("studio: while assigned") and left[0]:
                left[0] = 0
                raise mc.TransientError("503", "", 1)
            return real(ident, text, parent)

        with mock.patch.object(self.cli, "add_comment", flaky):
            with self.assertRaises(mc.TransientError):
                self.poll()
        self.poll()
        texts = self.comments_on(self.ri)
        self.assertEqual(len([t for t in texts if t.startswith("studio: run ended:")]), 1)
        self.assertEqual(len([t for t in texts if "while assigned" in t]), 1)


if __name__ == "__main__":
    unittest.main()
