"""Mirror: the end-of-run wake on a request issue no sub-issue wake covers (#72)."""
from __future__ import annotations

import json
import os
from unittest import mock

import bridgetest
from bridgetest import MirrorCase, ev, make_project, make_run
from bridge import multica_cli as mc

INSTR = 'The overnight run\'s Run issue %s has ended. Read its "studio: run ended:" comment and the report ' \
        'it names, then do what this issue\'s description says comes after the run.'
SKIP_SUB = "agent-assigned; the Run issue is its sub-issue"


class EndWakeTest(MirrorCase):
    def setUp(self):
        super().setUp()
        self.root = make_project(self.tmp, "game")

    # ----- helpers -----------------------------------------------------------

    def start(self, assignee=None, run_agent="ag-run", events=()):
        for _ in range(3):
            self.board.add_issue("filler")
        req = self.board.add_issue("Tonight", assignee=assignee)
        self.board.add_run(req, "task-1", "2026-10-03T22:00:00Z", agent_id=run_agent)
        os.makedirs(self.paths.links, exist_ok=True)
        with open(os.path.join(self.paths.links, "task-1"), "w") as f:     # agent= differs from run_agent on purpose
            f.write("task=task-1\nworkdir=/w/ws/%s-6d25f8ec1ce3/workdir\nagent=ag-link\n" % req.lower())
        run = make_run(self.home, self.root, origin="multica:task-1")
        run.append(*events)
        return req, run

    def reuse_run_issue(self, run, parent):      # the Run issue exists before the first poll (ensure_run_issue reuses it)
        return self.board.add_issue("Run " + run.basename, parent=parent, props={"omega_run": self.key(run)})

    def end_wake(self, run):
        return (self.state.load_run(self.paths, self.key(run)) or {}).get("end_wake")

    def creates(self):
        return self.board.calls("issue wakeup create")

    def fail_comments(self, req, run):
        prefix = "studio: could not arm the end-of-run wake on %s (" % req
        return [c for c in self.comments_on(self.run_issue(run)["identifier"]) if c.startswith(prefix)]

    # ----- arming ------------------------------------------------------------

    def test_unassigned_request_arms_once(self):
        req, run = self.start()
        self.poll()
        RUN = self.run_issue(run)["identifier"]
        creates = self.creates()
        self.assertEqual(len(creates), 1)
        self.assertEqual(creates[0]["argv"], [
            "issue", "wakeup", "create", req, "--until-issue", RUN, "--until-issue-state", "ended",
            "--agent-id", "ag-run", "--mode", "once", "--expires-in", "336h",
            "--instruction", INSTR % RUN, "--output", "json"])
        self.assertEqual(self.end_wake(run), {"outcome": "armed", "why": "no sub-issue wake covers it",
                                              "rule": self.board.wakeups(req)[0]["id"]})
        self.board.reset_calls()
        self.poll()
        self.assertEqual(self.board.calls("issue wakeup"), [])
        self.assertFalse([c for c in self.board.calls("issue get") if req in c["argv"]])

    def test_agent_id_from_issue_runs_not_link(self):
        req, run = self.start()
        self.poll()
        argv = self.creates()[0]["argv"]
        self.assertEqual(argv[argv.index("--agent-id") + 1], "ag-run")
        self.assertNotIn("ag-link", argv)

    def test_agent_assigned_sub_issue_skips(self):
        req, run = self.start(assignee=("agent", "ag-1"))
        self.poll()
        self.assertEqual(self.creates(), [])
        self.assertEqual(self.board.calls("issue wakeup list"), [])
        self.assertEqual(self.end_wake(run), {"outcome": "skipped", "why": SKIP_SUB, "rule": None})

    def test_agent_assigned_top_level_fallback_arms(self):
        req, run = self.start(assignee=("agent", "ag-1"))
        self.board.fault("issue create", exit=1, stderr="Invalid request: bad parent", contains="--parent", count=1)
        self.poll()
        self.assertIsNone(self.run_issue(run)["parent_issue_id"])
        self.assertEqual(len(self.creates()), 1)
        self.assertEqual(self.end_wake(run)["outcome"], "armed")

    def test_agent_assigned_reused_top_level_run_issue_arms(self):
        req, run = self.start(assignee=("agent", "ag-1"))
        self.reuse_run_issue(run, None)
        self.poll()
        self.assertEqual(len(self.creates()), 1)
        self.assertEqual(self.end_wake(run)["outcome"], "armed")

    def test_member_assigned_request_arms(self):
        req, run = self.start(assignee=("member", bridgetest.OPERATOR))
        self.poll()
        self.assertEqual(len(self.creates()), 1)
        self.assertEqual(self.end_wake(run)["outcome"], "armed")

    # ----- rules that already cover it --------------------------------------

    def _cond(self, ident, uuid, state="ended"):
        return {"type": "other_issue", "identifier": ident, "issue_id": uuid, "state": state}

    def _skips_with(self, make_cond, **kw):
        req, run = self.start()
        RUN = self.reuse_run_issue(run, req)
        rid = self.board.add_wakeup(req, make_cond(RUN, self.board.issue(RUN)["id"]), **kw)
        self.poll()
        self.assertEqual(self.creates(), [])
        ew = self.end_wake(run)
        self.assertEqual(ew["outcome"], "skipped")
        self.assertEqual(ew["why"], "rule %s already wakes on %s" % (rid, RUN))

    def test_existing_matching_rule_skips_ended(self):
        self._skips_with(lambda r, u: self._cond(r, "x"))

    def test_existing_matching_rule_skips_done_disabled(self):
        self._skips_with(lambda r, u: self._cond(r, "x", "done"), enabled=False, fire_count=1)

    def test_existing_matching_rule_skips_lowercase(self):
        self._skips_with(lambda r, u: self._cond(r.lower(), "x"))

    def test_existing_matching_rule_skips_uuid_only(self):
        self._skips_with(lambda r, u: self._cond("OMEG-999", u))

    def test_non_matching_rule_still_arms(self):
        req, run = self.start()
        RUN = self.reuse_run_issue(run, req)
        self.board.add_wakeup(req, None)
        self.board.add_wakeup(req, self._cond("OMEG-999", "x"))
        self.board.add_wakeup(req, self._cond(RUN, "x", "todo"))
        self.poll()
        self.assertEqual(len(self.creates()), 1)
        self.assertEqual(self.end_wake(run)["outcome"], "armed")

    # ----- nothing decided ---------------------------------------------------

    def test_request_none_records_nothing(self):
        run = make_run(self.home, self.root, "overnight-none-1")
        self.poll()
        self.assertIsNone(self.end_wake(run))
        self.assertEqual(self.board.calls("issue wakeup"), [])

    def test_request_pending_records_nothing(self):
        req, run = self.start()
        self.board.fault("issue runs", exit=1, stderr="503 service unavailable", count=-1)
        self.poll()
        self.assertIsNone(self.end_wake(run))
        self.assertEqual(self.board.calls("issue wakeup"), [])

    # ----- errors ------------------------------------------------------------

    def test_transient_on_create_retries_next_poll(self):
        req, run = self.start()
        self.board.fault("issue wakeup create", exit=1, stderr="503 service unavailable", count=1)
        with self.assertRaises(mc.TransientError):
            self.poll()
        self.assertIsNone(self.end_wake(run))
        self.poll()
        self.assertEqual(self.end_wake(run)["outcome"], "armed")
        self.assertEqual(len(self.board.wakeups(req)), 1)

    def test_create_landed_despite_transient_is_not_repeated(self):
        req, run = self.start()
        self.board.fault("issue wakeup create", exit=1, stderr="503 service unavailable", count=1, apply=True)
        with self.assertRaises(mc.TransientError):
            self.poll()
        self.poll()
        self.assertEqual(len(self.creates()), 1)
        self.assertEqual(self.end_wake(run)["outcome"], "skipped")
        self.assertEqual(len(self.board.wakeups(req)), 1)

    def test_permanent_error_fails_once_with_note(self):
        req, run = self.start()
        self.board.fault("issue wakeup create", exit=1, stderr="Invalid request: bad agent", count=-1)
        self.poll()
        RUN = self.run_issue(run)["identifier"]
        ew = self.end_wake(run)
        self.assertEqual(ew["outcome"], "failed")
        self.assertIn("bad agent", ew["why"])
        self.assertEqual([k for k, _ in self.notes].count("wake"), 1)
        self.assertEqual(len(self.fail_comments(req, run)), 1)
        self.assertIn("`multica issue wakeup create %s --until-issue %s --until-issue-state ended "
                      "--agent-id ag-run --mode once --expires-in 336h`" % (req, RUN), self.fail_comments(req, run)[0])
        self.poll()
        self.assertEqual(len(self.creates()), 1)
        self.assertEqual(len(self.fail_comments(req, run)), 1)

    def test_permanent_error_on_list_fails(self):
        req, run = self.start()
        self.board.fault("issue wakeup list", exit=1, stderr="Invalid request: nope", count=-1)
        self.poll()
        self.assertEqual(self.end_wake(run)["outcome"], "failed")
        self.assertIn("--agent-id <agent id>", self.fail_comments(req, run)[0])
        self.assertEqual(self.creates(), [])

    def test_unknown_agent_fails_with_note(self):
        req, run = self.start(run_agent=None)
        self.poll()
        self.assertEqual(self.creates(), [])
        ew = self.end_wake(run)
        self.assertEqual(ew["outcome"], "failed")
        self.assertEqual(ew["why"], "no agent id for task task-1 in issue runs %s" % req)
        self.assertIn("--agent-id <agent id>", self.fail_comments(req, run)[0])

    def test_request_issue_gone_fails(self):
        req, run = self.start()
        self.board.fault("issue wakeup list", exit=1, stderr="503 service unavailable", count=1)
        with self.assertRaises(mc.TransientError):
            self.poll()
        self.board.remove_issue(req)
        self.poll()
        self.assertEqual(self.end_wake(run)["outcome"], "failed")
        self.assertEqual(len(self.fail_comments(req, run)), 1)
        self.poll()
        self.assertEqual(len(self.fail_comments(req, run)), 1)

    def test_state_without_end_wake_loads_and_arms(self):
        req, run = self.start()
        self.board.fault("issue wakeup list", exit=1, stderr="503 service unavailable", count=1)
        with self.assertRaises(mc.TransientError):
            self.poll()
        st = self.state.load_run(self.paths, self.key(run))
        st.pop("end_wake", None)
        self.state.atomic_write_json(os.path.join(self.paths.state_dir, self.key(run) + ".json"), st)
        self.poll()
        self.assertEqual(self.end_wake(run)["outcome"], "armed")

    def test_run_ending_in_first_poll_arms_then_retires(self):
        req, run = self.start(events=(ev("run_started", mode="integration"),
                                      ev("run_ended", ending="done", report="/r")))
        self.poll()
        row = self.run_issue(run)
        rules = self.board.wakeups(req)
        self.assertEqual(len(rules), 1)
        self.assertEqual(rules[0]["condition"]["identifier"], row["identifier"])
        self.assertEqual(row["status"], "done")
        self.assertIn(self.key(run), self.state.load_retired(self.paths))
        with open(os.path.join(self.paths.retired_dir, self.key(run) + ".json")) as f:
            self.assertEqual(json.load(f)["end_wake"]["outcome"], "armed")

    def test_create_not_refused_by_request_guard(self):
        req, run = self.start()
        self.poll()
        self.assertIn(req.upper(), {f.upper() for f in self.cli.forbidden})
        self.assertEqual(self.creates()[0]["exit"], 0)
        with self.assertRaises(mc.ForbiddenWrite):
            self.cli.set_status(req, "done")
        with self.assertRaises(mc.ForbiddenWrite):
            self.cli.add_comment(req, "studio: x")

    def test_run_row_missing_from_list_is_read(self):
        req, run = self.start(assignee=("agent", "ag-1"))
        with mock.patch.object(self.cli, "run_issues", return_value=[]):
            self.poll()
        self.assertEqual(self.end_wake(run)["outcome"], "skipped")

    def test_failure_note_transient_retries_once(self):
        req, run = self.start()
        self.board.fault("issue wakeup create", exit=1, stderr="Invalid request: bad agent", count=-1)
        self.board.fault("issue comment add", exit=1, stderr="503 service unavailable", count=1)
        with self.assertRaises(mc.TransientError):
            self.poll()
        self.assertIsNone(self.end_wake(run))
        self.poll()
        self.assertEqual(self.end_wake(run)["outcome"], "failed")
        self.assertEqual(len(self.fail_comments(req, run)), 1)


if __name__ == "__main__":
    import unittest
    unittest.main()
