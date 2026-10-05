"""Mirror part 1: adoption, request issue, Run and story issues, event mapping (#28)."""
from __future__ import annotations

import json
import os
import shutil
from unittest import mock

import bridgetest
from bridgetest import MirrorCase, ev, make_project, make_run
from bridge import multica_cli as mc

RUN_ENDED_COMMENT = "run ended"


class MirrorRunsTest(MirrorCase):
    def setUp(self):
        super().setUp()
        self.root = make_project(self.tmp, "game")

    # ----- helpers -----------------------------------------------------------

    def mk(self, origin=None, basename="overnight-20261003-2214", root=None, live=True):
        return make_run(self.home, root or self.root, basename, live, origin)

    def tracked(self):
        return self.state.tracked_keys(self.paths)

    def load(self, run):
        return self.state.load_run(self.paths, self.key(run))

    def link(self, task, ident=None, agent=None, written=None):
        os.makedirs(self.paths.links, exist_ok=True)
        lines = ["task=" + task]
        if ident:
            lines.append("workdir=/w/ws/%s-6d25f8ec1ce3/workdir" % ident.lower())
        if agent:
            lines.append("agent=" + agent)
        if written:
            lines.append("written=" + written)
        path = os.path.join(self.paths.links, task)
        with open(path, "w") as f:
            f.write("\n".join(lines) + "\n")
        return path

    def stdins(self, prefix="issue comment add"):
        return [c["stdin"] for c in self.board.calls(prefix)]

    def mc_fault(self, cmd, text="503 service unavailable", **kw):
        self.board.fault(cmd, exit=1, stderr=text, **kw)

    # ----- adoption ----------------------------------------------------------

    def test_adopt_live_only(self):
        live = self.mk(basename="overnight-live-1")
        self.mk(basename="overnight-dead-1", live=False)
        self.assertEqual(self.mirror.adopt(self.ctx), [self.key(live)])
        self.assertEqual(self.tracked(), [self.key(live)])

    def test_adopt_respects_roots(self):
        run = self.mk()
        self.cfg.roots = [os.path.join(self.tmp, "elsewhere")]
        self.assertEqual(self.mirror.adopt(self.ctx), [])
        self.cfg.roots = [self.root]
        self.assertEqual(self.mirror.adopt(self.ctx), [self.key(run)])

    def test_retired_never_readopted(self):
        run = self.mk()
        self.mirror.adopt(self.ctx)
        self.mirror.retire(self.ctx, self.load(run))
        self.assertEqual(self.mirror.adopt(self.ctx), [])
        self.assertEqual(self.tracked(), [])

    def test_stored_pid_after_entry_moves_to_last(self):
        run = self.mk()
        self.poll()
        run.end_entry()
        self.poll()
        self.assertEqual(self.tracked(), [self.key(run)])
        run.kill()
        for _ in range(3):
            self.poll()
        self.assertEqual(self.tracked(), [])
        self.assertTrue(any("runner gone" in c for c in self.comments_on(self.run_issue(run)["identifier"])))

    def test_same_basename_two_roots(self):
        other = make_project(self.tmp, "game2")
        r1, r2 = self.mk(), self.mk(root=other)
        self.assertNotEqual(self.key(r1), self.key(r2))
        for r in (r1, r2):
            r.append(ev("run_started", mode="integration"), ev("story_listed", story="A", chain=1, depends=[]))
        self.poll()
        for r in (r1, r2):
            ri, si = self.run_issue(r), self.story_issue(r, "A")
            self.assertIsNotNone(ri)
            self.assertEqual(si["parent_issue_id"], ri["id"])
        self.assertNotEqual(self.run_issue(r1)["id"], self.run_issue(r2)["id"])

    def test_two_runs_one_root_mirrored(self):
        r1, r2 = self.mk(), self.mk(basename="overnight-20261003-2300")
        self.assertNotEqual(self.key(r1), self.key(r2))
        self.assertEqual(sorted(self.mirror.adopt(self.ctx)), sorted([self.key(r1), self.key(r2)]))
        for r in (r1, r2):
            r.append(ev("run_started", mode="integration"), ev("story_listed", story="A", chain=1, depends=[]))
        self.poll()
        for r in (r1, r2):
            self.assertIsNotNone(self.run_issue(r))
            self.assertIsNotNone(self.story_issue(r, "A"))
        self.assertNotEqual(self.run_issue(r1)["id"], self.run_issue(r2)["id"])

    # ----- request issue -----------------------------------------------------

    def _request_issue(self, **kw):
        for _ in range(3):
            self.board.add_issue("filler")
        return self.board.add_issue("Tonight", **kw)

    def test_request_from_link_confirmed(self):
        req = self._request_issue(assignee=("agent", "ag-1"))
        self.board.add_run(req, "task-1", "2026-10-03T22:00:00Z")
        path = self.link("task-1", req, "ag-1")
        run = self.mk(origin="multica:task-1")
        self.poll()
        self.assertEqual(self.run_issue(run)["parent_issue_id"], self.board.issue(req)["id"])
        self.assertIn("--parent", self.board.calls("issue create")[0]["argv"])
        self.assertFalse(os.path.exists(path))

    def test_request_link_refuted_then_assignee_search(self):
        a = self._request_issue(assignee=("agent", "ag-1"))
        b = self.board.add_issue("Other", assignee=("agent", "ag-1"))
        self.board.add_run(b, "task-1", "2026-10-03T22:00:00Z")
        self.link("task-1", a, "ag-1")
        run = self.mk(origin="multica:task-1")
        self.poll()
        self.assertEqual(self.run_issue(run)["parent_issue_id"], self.board.issue(b)["id"])
        self.assertEqual(len([c for c in self.board.calls("issue runs") if c["argv"][2] == a]), 1)

    def test_request_origin_absent_or_foreign_top_level(self):
        runs = [self.mk(origin=o, basename="overnight-x%d" % i)
                for i, o in enumerate((None, "other:x", "multica:a.b"))]
        self.poll()
        self.assertEqual(self.board.calls("issue runs"), [])
        for r in runs:
            self.assertIsNone(self.run_issue(r)["parent_issue_id"])

    def test_request_no_match_top_level(self):
        req = self._request_issue(assignee=("agent", "ag-1"))
        self.link("task-9", req, "ag-1")
        run = self.mk(origin="multica:task-9")
        self.poll()
        self.assertIsNone(self.run_issue(run)["parent_issue_id"])

    def test_request_transient_then_fallback_after_5min(self):
        req = self._request_issue(assignee=("agent", "ag-1"))
        self.board.add_run(req, "task-1", "2026-10-03T22:00:00Z")
        self.link("task-1", req, "ag-1")
        run = self.mk(origin="multica:task-1")
        self.mc_fault("issue runs", count=-1)
        self.poll()
        self.assertIsNone(self.run_issue(run))
        self.skew = 299
        self.poll()
        self.assertIsNone(self.run_issue(run))
        self.skew = 301
        self.poll()
        self.assertIsNone(self.run_issue(run)["parent_issue_id"])

    def test_old_links_pruned(self):
        path = self.link("task-old", written=self.state.iso_now(self.ctx.now() - 25 * 3600))
        fresh = self.link("task-new", written=self.state.iso_now(self.ctx.now()))
        self.poll()
        self.assertFalse(os.path.exists(path))
        self.assertTrue(os.path.exists(fresh))

    # ----- Run issue ---------------------------------------------------------

    def test_run_issue_lookup_reuses(self):
        run = self.mk()
        self.board.add_issue("Run old", props={"omega_run": self.key(run)})
        self.poll()
        self.assertEqual(self.board.calls("issue create"), [])
        self.assertEqual(self.load(run)["run_issue"], self.run_issue(run)["identifier"])

    def test_run_issue_create_args(self):
        run = self.mk()
        self.poll()
        argv = self.board.calls("issue create")[0]["argv"]
        for want in ("--title", "Run " + run.basename, "--status", "todo", "--allow-duplicate",
                     "--property", "omega_run=" + self.key(run), "--description-stdin"):
            self.assertIn(want, argv)
        self.assertNotIn("--assignee-id", argv)
        self.assertNotIn("--stage", argv)
        desc = self.run_issue(run)["description"]
        for want in (run.run_dir, self.root, self.key(run), "/stop run"):
            self.assertIn(want, desc)

    def test_run_issue_parent_create_fails_retries_top_level(self):
        req = self._request_issue(assignee=("agent", "ag-1"))
        self.board.add_run(req, "task-1", "2026-10-03T22:00:00Z")
        self.link("task-1", req, "ag-1")
        run = self.mk(origin="multica:task-1")
        self.mc_fault("issue create", "Invalid request: bad parent", contains="--parent", count=1)
        self.poll()
        creates = self.board.calls("issue create")
        self.assertEqual(len(creates), 2)
        self.assertNotIn("--parent", creates[1]["argv"])
        self.assertIsNone(self.run_issue(run)["parent_issue_id"])

    def test_run_issue_both_fail_retires_and_notifies(self):
        run = self.mk()
        self.mc_fault("issue create", "Invalid request: no", count=-1)
        self.poll()
        self.assertEqual(self.notes, [("create", "omega bridge: could not create the Run issue for " + run.basename)])
        self.assertEqual(self.tracked(), [])
        self.assertIn(self.key(run), self.state.load_retired(self.paths))

    # ----- story issues ------------------------------------------------------

    def test_story_listed_creates_story_issue(self):
        run = self.mk()
        run.append(ev("run_started", mode="integration"),
                   ev("story_listed", story="A", chain=1, depends=[]),
                   ev("story_listed", story="1", chain=2, depends=["A"]))
        self.poll()
        ri = self.run_issue(run)
        a, one = self.story_issue(run, "A"), self.story_issue(run, "1")
        self.assertEqual((a["title"], one["title"]), ("A", "1"))
        for row, story in ((a, "A"), (one, "1")):
            self.assertEqual(row["parent_issue_id"], ri["id"])
            self.assertEqual(self.named_props(row), {"omega_run": self.key(run), "omega_story": story})
        self.assertIn("Chain: 1", a["description"])
        self.assertIn("Depends on: none", a["description"])
        self.assertIn("Depends on: A", one["description"])
        self.assertIn(run.basename, a["description"])

    def test_story_create_failure_routes_to_run_issue(self):
        run = self.mk()
        run.append(ev("run_started", mode="integration"),
                   ev("story_listed", story="A", chain=1, depends=[]),
                   ev("story_listed", story="B", chain=2, depends=[]))
        self.mc_fault("issue create", "Invalid request: no", contains="omega_story=A", count=-1)
        self.poll()
        run.append(ev("story_state", story="A", state="running"),
                   ev("unit_started", story="A", unit="u1", label="work"))
        self.poll()
        ri = self.run_issue(run)["identifier"]
        texts = self.comments_on(ri)
        self.assertEqual(len([t for t in texts if "its issue could not be created" in t]), 1)
        self.assertIn("studio: [A] unit u1 (work) started", texts)
        self.assertIsNotNone(self.story_issue(run, "B"))
        self.assertTrue(all(c[2] == ri for c in self.status_calls()))

    def test_story_issue_missing_recreated_once(self):
        run = self.mk()
        run.append(ev("run_started", mode="integration"), ev("story_listed", story="A", chain=1, depends=[]))
        self.poll()
        first_desc = self.story_issue(run, "A")["description"]
        self.board.remove_issue(self.story_issue(run, "A")["identifier"])
        run.append(ev("unit_started", story="A", unit="u1", label="work"))
        self.poll()
        new = self.story_issue(run, "A")
        self.assertIn("studio: unit u1 (work) started", self.comments_on(new["identifier"]))
        self.assertEqual(new["description"], first_desc)          # the recreate keeps the description
        self.board.remove_issue(new["identifier"])
        run.append(ev("unit_ended", story="A", unit="u1", label="work", outcome="done", usd=1))
        self.poll()                                               # one poll: the second loss routes to the Run issue
        creates = [c for c in self.board.calls("issue create") if "omega_story=A" in " ".join(c["argv"])]
        self.assertEqual(len(creates), 2)
        ri = self.run_issue(run)["identifier"]
        texts = self.comments_on(ri)
        self.assertIn("studio: [A] unit u1 (work) ended: done, $1.00", texts)
        self.assertEqual(len([t for t in texts if "its events go here" in t]), 1)
        self.assertEqual(self.load(run)["offset"], os.path.getsize(run.events))
        self.assertNotIn("A", self.load(run)["stories"])
        self.assertIn("A", self.load(run)["story_failed"])

    # ----- the mapping -------------------------------------------------------

    def test_event_mapping_rows(self):
        run = self.mk()
        run.append(ev("run_started", mode="integration", max_lanes=2, hold_minutes=30),
                   ev("story_listed", story="A", chain=1, depends=[]),
                   ev("story_listed", story="B", chain=2, depends=[]))
        self.poll()
        ri = self.run_issue(run)["identifier"]
        self.assertEqual(self.comments_on(ri), ["studio: run started (integration)"])
        self.assertEqual([c[3] for c in self.status_calls()], ["in_progress"])
        until = "2026-10-04T01:00:00Z"
        rows = [
            (ev("story_state", story="A", state="queued"), None, None),   # the issue is already todo: no write (AC14.4)
            (ev("story_state", story="A", state="running"), "in_progress", None),
            (ev("story_state", story="A", state="waiting"), "todo", None),
            (ev("story_state", story="A", state="repair"), "in_progress", None),
            (ev("story_state", story="A", state="held", why="need art", until=until), "blocked",
             "studio: held: need art — until %s — /say, /resume or /stop" % until),
            (ev("story_state", story="A", state="gate-repair"), "in_progress", None),
            (ev("story_state", story="A", state="held", why="x", until=until), "blocked",
             "studio: held: x — until %s — /say, /resume or /stop" % until),
            (ev("story_state", story="A", state="sync-repair"), "in_progress", None),
            (ev("story_state", story="A", state="held", why="x", until=until), "blocked",
             "studio: held: x — until %s — /say, /resume or /stop" % until),
            (ev("story_state", story="A", state="landing"), "in_progress", None),
            (ev("story_state", story="A", state="landed"), "done", None),
            (ev("story_state", story="A", state="stopped", why="by operator"), "cancelled",
             "studio: stopped: by operator"),
            (ev("story_state", story="B", state="skipped", why="dep stopped"), "cancelled",
             "studio: skipped: dep stopped"),
            (ev("unit_started", story="B", unit="u1", label="repair"), None, "studio: unit u1 (repair) started"),
            (ev("unit_ended", story="B", unit="u1", label="repair", outcome="progress", usd=0.5), None,
             "studio: unit u1 (repair) ended: progress, $0.50"),
            (ev("message_queued", story="B", id=3, scope="story"), None, "studio: message 3 queued (story)"),
            (ev("message_delivered", story="B", id=3, scope="story", unit="u1", via="tool_call"), None,
             "studio: message 3 delivered to unit u1"),
            (ev("message_requeued", story="B", id=3, unit="u1", requeues=1), None,
             "studio: message 3 not recorded by unit u1; requeued (1)"),
            (ev("control", story="B", action="hold"), None, "studio: hold by operator"),
            (ev("story_synced", story="B", refs=["origin/main"], sha="abc1234"), None,
             "studio: synced origin/main (abc1234)"),
            (ev("story_synced", story="B", skipped="dirty"), None, "studio: sync skipped: dirty"),
            (ev("story_synced", story="B", failed="merge"), None, "studio: sync failed: merge"),
            # session_wait is not mirrored: the unit's own unit_started follows
            (ev("session_wait", lane="1", story="B", since="2026-10-04T01:00:00Z"), None, None),
        ]
        for n, (e, status, comment) in enumerate(rows):
            with self.subTest(n=n, event=e["event"], state=e.get("state"), story=e["story"]):
                row = self.story_issue(run, e["story"])["identifier"]
                before_s = len(self.status_calls())
                before_c = len(self.comments_on(row))
                run.append(e)
                self.poll()
                new_s = self.status_calls()[before_s:]
                self.assertEqual([(c[2], c[3]) for c in new_s], [(row, status)] if status else [])
                self.assertEqual(self.comments_on(row)[before_c:], [comment] if comment else [])
        run.append(ev("run_ended", ending="done", report="/r/report.md"))
        self.poll()
        self.assertEqual(self.comments_on(ri)[-1], "studio: run ended: done — report: /r/report.md")
        self.assertEqual(self.board.issue(ri)["status"], "done")

    def test_usd_unknown(self):
        for v in (None, "", "n/a"):
            self.assertEqual(self.mirror.cost(v), "cost unknown")
        self.assertEqual(self.mirror.cost(1.5), "$1.50")
        st = {"mode": "manifest", "story_failed": [], "run_dir": "/x"}
        w = self.mirror.event_writes(st, ev("unit_ended", story="A", unit="u", label="l", outcome="done", usd=None))
        self.assertEqual(w, [("comment", "A", "studio: unit u (l) ended: done, cost unknown")])

    def test_single_plan_routes_to_run_issue(self):
        run = self.mk()
        until = "2026-10-04T01:00:00Z"
        run.append(ev("run_started", mode="single", max_lanes=1, hold_minutes=30),
                   ev("story_listed", story="-", chain=1, depends=[]),
                   ev("story_state", story="-", state="running"),
                   ev("unit_started", story="-", unit="u1", label="work"),
                   ev("story_state", story="-", state="held", why="stop: need art", until=until),
                   ev("story_state", story="-", state="landed"),
                   ev("run_ended", ending="done", report="/r/report.md"))
        self.poll()
        ri = self.run_issue(run)["identifier"]
        _, rows = self._issues()
        self.assertEqual(len(rows), 1)
        self.assertEqual([c[3] for c in self.status_calls()], ["in_progress", "blocked", "done"])
        self.assertIn("studio: held: stop: need art — until %s — /say, /resume or /stop" % until,
                      self.comments_on(ri))
        self.assertIn("studio: unit u1 (work) started", self.comments_on(ri))

    def test_every_comment_prefixed(self):
        run = self.mk()
        run.append(ev("run_started", mode="integration"), ev("story_listed", story="A", chain=1, depends=[]),
                   ev("story_state", story="A", state="held", why="w", until="u"),
                   ev("unit_started", story="A", unit="u", label="l"),
                   ev("run_ended", ending="stop: runner gone", report="/r"))
        self.poll()
        texts = self.stdins()
        self.assertTrue(len(texts) >= 4)
        self.assertTrue(all(t.startswith("studio: ") for t in texts))

    # ----- reading the log ---------------------------------------------------

    def test_torn_last_line_kept(self):
        run = self.mk()
        run.append(ev("run_started", mode="single"))
        full = json.dumps(ev("unit_started", story="-", unit="u1", label="work"), separators=(",", ":"))
        run.append_raw(full[:30])
        self.poll()
        ri = self.run_issue(run)["identifier"]
        first = os.path.getsize(run.events) - 30
        self.assertEqual(self.load(run)["offset"], first)
        self.assertEqual(self.comments_on(ri), ["studio: run started (single)"])
        run.append_raw(full[30:] + "\n")
        self.poll()
        self.poll()
        self.assertEqual(self.comments_on(ri), ["studio: run started (single)", "studio: unit u1 (work) started"])

    def test_offset_kept_after_transient(self):
        run = self.mk()
        self.poll()
        run.append(ev("unit_started", story="-", unit="u1", label="work"))
        self.mc_fault("issue comment add", count=1)
        with self.assertRaises(mc.TransientError):
            self.poll()
        self.assertEqual(self.load(run)["offset"], 0)
        self.poll()
        self.assertEqual(self.comments_on(self.run_issue(run)["identifier"]), ["studio: unit u1 (work) started"])
        self.assertEqual(self.load(run)["offset"], os.path.getsize(run.events))

    def test_partial_event_progress_not_repeated(self):
        run = self.mk()
        self.poll()
        run.append(ev("run_ended", ending="done", report="/r/report.md"))
        self.mc_fault("issue status", count=1)
        with self.assertRaises(mc.TransientError):
            self.poll()
        ri = self.run_issue(run)["identifier"]
        self.assertEqual(len(self.comments_on(ri)), 1)
        before = len(self.status_calls())
        self.poll()
        self.assertEqual(len(self.status_calls()) - before, 1)
        self.assertEqual(len(self.comments_on(ri)), 1)
        self.assertEqual(self.board.issue(ri)["status"], "done")

    def test_permanent_failure_skipped_after_three_polls(self):
        run = self.mk()
        self.poll()
        run.append(ev("unit_started", story="-", unit="u1", label="work"),
                   ev("unit_ended", story="-", unit="u1", label="work", outcome="done", usd=1))
        self.mc_fault("issue comment add", "Invalid request: nope", count=3)
        for _ in range(3):
            self.poll()
        texts = self.comments_on(self.run_issue(run)["identifier"])
        self.assertEqual(len(texts), 2)
        self.assertIn("skipped unit_started (story -) after 3 failed attempts", texts[0])
        self.assertEqual(texts[1], "studio: unit u1 (work) ended: done, $1.00")

    def test_story_chain_zero_renders_as_zero(self):
        run = self.mk()
        run.append(ev("run_started", mode="integration"), ev("story_listed", story="A", chain=0, depends=[]))
        self.poll()
        self.assertIn("Chain: 0.", self.story_issue(run, "A")["description"])

    def test_skipped_run_ended_still_sets_the_run_issue_done(self):
        run = self.mk()
        run.append(ev("run_started", mode="single"))
        self.poll()
        ri = self.run_issue(run)["identifier"]
        run.append(ev("run_ended", ending="done", report="/r/report.md"))
        self.mc_fault("issue comment add", "Invalid request: nope", count=3)
        for _ in range(3):
            self.poll()
        self.assertEqual(self.board.issue(ri)["status"], "done")
        self.assertTrue(any("skipped run_ended" in t for t in self.comments_on(ri)))

    def test_runner_gone_after_two_more_polls(self):
        run = self.mk()
        self.poll()
        ri = self.run_issue(run)["identifier"]
        run.kill()
        for _ in range(2):
            self.poll()
            self.assertEqual(self.comments_on(ri), [])
        self.poll()
        self.assertEqual(len(self.comments_on(ri)), 1)
        self.assertIn("runner gone, no clean end", self.comments_on(ri)[0])
        self.assertEqual(self.tracked(), [])
        self.assertEqual(self.status_calls(), [])

    def test_unknown_event_and_bad_line_skipped(self):
        run = self.mk()
        run.append(ev("run_started", mode="single"), {"v": 1, "event": "future_thing"})
        run.append_raw("not json\n")
        run.append(ev("story_state", story="-", state="weird"), ev("unit_started", story="-", unit="u1", label="w"))
        self.poll()
        self.assertEqual(self.comments_on(self.run_issue(run)["identifier"]),
                         ["studio: run started (single)", "studio: unit u1 (w) started"])
        self.assertEqual(self.load(run)["offset"], os.path.getsize(run.events))

    def test_version_2_stops_and_retires(self):
        run = self.mk()
        self.poll()
        run.append({"v": 2, "event": "run_started"}, ev("unit_started", story="-", unit="u1", label="w"))
        self.poll()
        texts = self.comments_on(self.run_issue(run)["identifier"])
        self.assertEqual(len(texts), 1)
        self.assertIn("version 2 is newer", texts[0])
        self.assertEqual(self.tracked(), [])

    def test_event_log_shrunk_or_vanished_retires(self):
        r1 = self.mk(basename="overnight-a-1")
        r2 = self.mk(basename="overnight-b-1")
        for r in (r1, r2):
            r.append(ev("run_started", mode="single"), ev("unit_started", story="-", unit="u1", label="w"))
        self.poll()
        with open(r1.events, "w"):
            pass
        shutil.rmtree(r2.run_dir)
        self.poll()
        for r in (r1, r2):
            texts = self.comments_on(self.run_issue(r)["identifier"])
            self.assertEqual(texts.count(self.mirror.LOG_GONE), 1)
            self.assertEqual(len(texts), 3)
        self.assertEqual(self.tracked(), [])

    def test_run_ended_comment_before_done(self):
        run = self.mk()
        self.poll()
        run.append(ev("run_ended", ending="done", report="/r/report.md"))
        self.poll()
        calls = self.board.calls()
        ci = [i for i, c in enumerate(calls) if c["argv"][:3] == ["issue", "comment", "add"]
              and RUN_ENDED_COMMENT in c["stdin"]]
        si = [i for i, c in enumerate(calls) if c["argv"][:2] == ["issue", "status"] and c["argv"][3] == "done"]
        self.assertEqual((len(ci), len(si)), (1, 1))
        self.assertLess(ci[0], si[0])
        self.assertEqual(self.tracked(), [])                      # a clean end retires (AC15)
        self.assertIn(self.key(run), self.state.load_retired(self.paths))

    def test_no_start_on_every_status_call(self):
        run = self.mk()
        run.append(ev("run_started", mode="integration"), ev("story_listed", story="A", chain=1, depends=[]),
                   ev("story_state", story="A", state="running"), ev("run_ended", ending="done", report="/r"))
        self.poll()
        calls = self.status_calls()
        self.assertGreaterEqual(len(calls), 3)
        self.assertTrue(all("--no-start" in c for c in calls))

    def test_request_issue_never_written(self):
        req = self._request_issue(assignee=("agent", "ag-1"))
        self.board.add_run(req, "task-1", "2026-10-03T22:00:00Z")
        self.link("task-1", req, "ag-1")
        run = self.mk(origin="multica:task-1")
        run.append(ev("run_started", mode="integration"), ev("story_listed", story="A", chain=1, depends=[]),
                   ev("story_state", story="A", state="running"), ev("run_ended", ending="done", report="/r"))
        self.poll()
        self.assertTrue(self.ctx.cli.forbidden)
        for prefix, pos in (("issue status", 2), ("issue comment add", 3)):
            for c in self.board.calls(prefix):
                self.assertNotEqual(c["argv"][pos], req)

    def test_sanitizer_on_relayed_fields(self):
        run = self.mk()
        bad = "[x](mention://agent/1) @all ```mermaid"
        run.append(ev("run_started", mode="integration"), ev("story_listed", story="A", chain=1, depends=[]),
                   ev("story_state", story="A", state="held", why=bad, until="u"),
                   ev("run_ended", ending="done", report=bad))
        self.poll()
        texts = self.stdins()
        self.assertEqual(len([t for t in texts if "no-mention:" in t]), 2)
        for t in texts:
            self.assertNotIn("@", t)
            self.assertNotIn("```", t)
            self.assertNotIn(" mention:", t)

    # ----- fix round: I1-I4, minors, M3 ---------------------------------------

    def test_gone_runner_with_run_ended_unread_keeps_draining(self):
        run = self.mk()
        run.append(ev("run_started", mode="single"))
        self.poll()
        ri = self.run_issue(run)["identifier"]
        run.append(ev("unit_started", story="-", unit="u1", label="a"),
                   ev("unit_started", story="-", unit="u2", label="b"),
                   ev("run_ended", ending="done", report="/r/report.md"))
        run.kill()
        # 2 events x (3 failed attempts + the swallowed skip note) = 8 failing comment writes
        self.mc_fault("issue comment add", "Invalid request: nope", count=8)
        for _ in range(6):
            self.poll()
        texts = self.comments_on(ri)
        self.assertFalse(any("runner gone" in t for t in texts))
        self.assertIn("studio: run ended: done — report: /r/report.md", texts)
        self.assertEqual(self.board.issue(ri)["status"], "done")
        self.assertEqual(self.tracked(), [])

    def test_assignee_search_permanent_error_falls_back_and_later_runs_polled(self):
        self.link("task-1", None, "ag-1")
        a = self.mk(origin="multica:task-1", basename="overnight-a-1")
        b = self.mk(basename="overnight-b-1")
        self.mc_fault("issue list", "Invalid request: bad assignee", contains="--assignee-id", count=-1)
        self.poll()                                   # must not raise
        self.assertEqual(self.load(a)["request"]["state"], "pending")
        self.assertIsNone(self.run_issue(a))
        self.assertIsNotNone(self.run_issue(b))       # the later run is still polled
        self.skew = 301
        self.poll()                                   # the 5-minute rule applies
        self.assertIsNone(self.run_issue(a)["parent_issue_id"])

    def test_run_issue_lookup_permanent_error_does_not_starve_other_runs(self):
        a = self.mk(basename="overnight-a-1")
        b = self.mk(basename="overnight-b-1")
        self.mc_fault("issue list", "Invalid request: bad property", count=1)
        self.poll()                                   # must not raise
        self.poll()
        self.assertIsNotNone(self.run_issue(a))
        self.assertIsNotNone(self.run_issue(b))

    def test_unreadable_run_does_not_starve_other_runs(self):
        a = self.mk(basename="overnight-a-1")
        b = self.mk(basename="overnight-b-1")
        a.append(ev("run_started", mode="single"))
        b.append(ev("run_started", mode="single"))
        os.chmod(a.events, 0)                         # a macOS file-access block, or a bad mode
        self.addCleanup(os.chmod, a.events, 0o644)
        self.poll()                                   # must not raise
        self.assertEqual(self.board.issue(self.run_issue(b)["identifier"])["status"], "in_progress")
        self.assertIn("studio: run started (single)", self.comments_on(self.run_issue(b)["identifier"]))

    def test_non_cli_error_in_one_run_does_not_starve_other_runs(self):
        a = self.mk(basename="overnight-a-1")
        b = self.mk(basename="overnight-b-1")
        real = self.mirror.apply_events
        errs = iter([ValueError("bad created_at"), KeyError("created_at"), mc.ForbiddenWrite("REQ-1"), TypeError("x")])

        def flaky(ctx, st):
            if st["key"] == self.key(a):
                raise next(errs)
            return real(ctx, st)
        b.append(ev("run_started", mode="single"))
        with mock.patch.object(self.mirror, "apply_events", flaky):
            for _ in range(4):
                self.poll()                           # none of them raises
        self.assertIn("studio: run started (single)", self.comments_on(self.run_issue(b)["identifier"]))

    def test_transient_and_auth_still_propagate_from_a_run(self):
        self.mk(basename="overnight-a-1")
        for err in (mc.TransientError("503"), mc.AuthError("401")):
            with mock.patch.object(self.mirror, "poll_run", side_effect=err):
                with self.assertRaises(type(err)):
                    self.poll()
        with mock.patch.object(self.mirror, "poll_run", side_effect=mc.KeychainError("locked", "locked")):
            with self.assertRaises(mc.KeychainError):
                self.poll()

    def test_run_failing_every_poll_notifies_once_then_recovers(self):
        a = self.mk(basename="overnight-a-1")
        a.append(ev("run_started", mode="single"))
        os.chmod(a.events, 0)
        self.addCleanup(os.chmod, a.events, 0o644)
        for _ in range(6):
            self.poll()
        ri = self.run_issue(a)["identifier"]
        notes = [t for t in self.comments_on(ri) if "keeps failing" in t]
        self.assertEqual(len(notes), 1)
        self.assertIn("3 polls", notes[0])
        os.chmod(a.events, 0o644)
        self.poll()
        self.assertEqual(self.load(a)["poll_fails"], 0)
        self.assertIn("studio: run started (single)", self.comments_on(ri))

    def test_poll_failure_logs_a_redacted_traceback_once_per_streak(self):
        a = self.mk(basename="overnight-a-1")

        def boom_in_apply(ctx, st):
            raise ValueError("bad row mul_secretvalue99")
        with mock.patch.object(self.mirror, "apply_events", boom_in_apply):
            with self.assertLogs("bridgetest", level="ERROR") as cm:
                for _ in range(3):
                    self.poll()
        text = "\n".join(cm.output)
        self.assertIn("Traceback", text)
        self.assertIn("boom_in_apply", text)
        self.assertNotIn("mul_secretvalue99", text)
        self.assertEqual(text.count("Traceback"), 1)          # once per failure streak; later polls log one line
        self.assertEqual(self.load(a)["poll_fails"], 3)
        self.assertEqual(self.load(a)["poll_error"], "ValueError: bad row <token>")

    def test_failing_run_note_survives_a_transient_on_its_post(self):
        a = self.mk(basename="overnight-a-1")
        a.append(ev("run_started", mode="single"))
        self.poll()
        ri = self.run_issue(a)["identifier"]
        os.chmod(a.events, 0)
        self.addCleanup(os.chmod, a.events, 0o644)
        self.poll()
        self.poll()
        self.mc_fault("issue comment add", "HTTP 503", count=1)
        with self.assertRaises(mc.TransientError):
            self.poll()                               # the 3rd failing poll: the note's post hits a transient
        for _ in range(4):
            self.poll()
        notes = [t for t in self.comments_on(ri) if "keeps failing" in t]
        self.assertEqual(len(notes), 1)

    def test_single_plan_landed_and_stopped_set_no_run_status(self):
        run = self.mk()
        run.append(ev("run_started", mode="single"), ev("story_listed", story="-", chain=1, depends=[]),
                   ev("story_state", story="-", state="running"),
                   ev("story_state", story="-", state="held", why="w", until="u"))
        self.poll()
        ri = self.run_issue(run)["identifier"]
        n = len(self.status_calls())
        self.assertEqual(self.board.issue(ri)["status"], "blocked")
        for state_ in ("landed", "stopped"):
            run.append(ev("story_state", story="-", state=state_, why="x"))
            self.poll()
            self.assertEqual(len(self.status_calls()), n, state_)
            self.assertEqual(self.board.issue(ri)["status"], "blocked")
        run.append(ev("run_ended", ending="done", report="/r"))
        self.poll()
        self.assertEqual(self.board.issue(ri)["status"], "done")

    def test_routed_story_status_never_touches_run_issue(self):
        run = self.mk()
        run.append(ev("run_started", mode="integration"), ev("story_listed", story="A", chain=1, depends=[]))
        self.mc_fault("issue create", "Invalid request: no", contains="omega_story=A", count=-1)
        self.poll()
        ri = self.run_issue(run)["identifier"]
        n = len(self.status_calls())
        run.append(ev("story_state", story="A", state="held", why="w", until="u"),
                   ev("story_state", story="A", state="stopped", why="x"))
        self.poll()
        self.assertEqual(len(self.status_calls()), n)
        self.assertEqual(self.board.issue(ri)["status"], "in_progress")
        self.assertIn("studio: [A] held: w — until u — /say, /resume or /stop", self.comments_on(ri))
        self.assertIn("studio: [A] stopped: x", self.comments_on(ri))

    def test_missing_events_file_keeps_live_run(self):
        run = self.mk()
        self.poll()
        os.remove(run.events)
        self.poll()
        self.assertEqual(self.tracked(), [self.key(run)])
        self.assertEqual(self.comments_on(self.run_issue(run)["identifier"]), [])

    def test_story_issue_found_by_properties_not_recreated(self):
        run = self.mk()
        old = self.board.add_issue("A", props={"omega_run": self.key(run), "omega_story": "A"})
        run.append(ev("run_started", mode="integration"), ev("story_listed", story="A", chain=1, depends=[]))
        self.poll()
        self.assertEqual(self.load(run)["stories"], {"A": old})
        self.assertEqual([c for c in self.board.calls("issue create") if "omega_story=A" in " ".join(c["argv"])], [])

    def test_clock_offset_and_posted_recorded(self):
        run = self.mk()
        self.board.set_now(self.t0 + 3600)
        run.append(ev("run_started", mode="single"))
        self.poll()
        st = self.load(run)
        self.assertAlmostEqual(st["clock_offset"], 3600, delta=60)
        ids = [c["id"] for c in self.board.comments(self.run_issue(run)["identifier"])]
        self.assertEqual(len(ids), 1)
        self.assertEqual(st["posted"], ids)

    def test_story_event_without_issue_gets_prefix_on_run_issue(self):
        run = self.mk()
        run.append(ev("run_started", mode="integration"), ev("unit_started", story="Z", unit="u1", label="w"),
                   ev("story_state", story="Z", state="running"))
        self.poll()
        ri = self.run_issue(run)["identifier"]
        self.assertIn("studio: [Z] unit u1 (w) started", self.comments_on(ri))
        self.assertEqual([c[3] for c in self.status_calls()], ["in_progress"])      # Z's status dropped

    def test_event_writes_fixed_when_first_computed(self):
        run = self.mk()
        run.append(ev("run_started", mode="integration"), ev("story_listed", story="A", chain=1, depends=[]))
        self.poll()
        self.board.remove_issue(self.story_issue(run, "A")["identifier"])
        self.mc_fault("issue create", "Invalid request: no", contains="omega_story=A", count=-1)
        # the failed-create note (swallowed) uses the first comment fault, the held comment the transient one
        self.mc_fault("issue comment add", "Invalid request: no", count=1)
        self.mc_fault("issue comment add", count=1)
        run.append(ev("story_state", story="A", state="held", why="w", until="u"))
        with self.assertRaises(mc.TransientError):
            self.poll()
        self.poll()
        self.assertIn("studio: [A] held: w — until u — /say, /resume or /stop",
                      self.comments_on(self.run_issue(run)["identifier"]))

    def test_story_create_success_clears_story_failed(self):
        run = self.mk()
        run.append(ev("run_started", mode="integration"), ev("story_listed", story="A", chain=1, depends=[]))
        self.mc_fault("issue create", "Invalid request: no", contains="omega_story=A", count=1)
        self.poll()
        self.assertIn("A", self.load(run)["story_failed"])
        run.append(ev("story_listed", story="A", chain=1, depends=[]))
        self.poll()
        st = self.load(run)
        self.assertNotIn("A", st["story_failed"])
        self.assertIn("A", st["stories"])

    def test_story_issue_seeded_todo_no_redundant_status(self):
        run = self.mk()
        run.append(ev("run_started", mode="integration"), ev("story_listed", story="A", chain=1, depends=[]),
                   ev("story_state", story="A", state="queued"))
        self.poll()
        a = self.story_issue(run, "A")["identifier"]
        self.assertEqual([c for c in self.status_calls() if c[2] == a], [])
        self.assertEqual(self.load(run)["last_set"][a], "todo")

    def test_cancelled_category_is_terminal(self):
        self.assertTrue(self.mirror.is_terminal({"status": "weird", "status_category": "cancelled"}))

    def test_link_deleted_only_after_resolution_saved(self):
        run = self.mk(origin="multica:task-1")
        self.link("task-1", None, "ag-1")
        order = []
        real_save, real_del = self.state.save_run, self.mirror.studio.delete_link

        def save(paths, st):
            order.append(("save", st["request"]["state"]))
            return real_save(paths, st)

        def delete(paths, task):
            order.append(("delete",))
            return real_del(paths, task)
        self.state.save_run, self.mirror.studio.delete_link = save, delete
        try:
            self.poll()
        finally:
            self.state.save_run, self.mirror.studio.delete_link = real_save, real_del
        d = order.index(("delete",))
        self.assertIn(("save", "none"), order[:d])

    def test_poll_saves_log_identity_and_detects_replacement(self):
        run = self.mk()
        run.append(ev("run_started", mode="single"))
        self.poll()
        from bridge import studio
        self.assertEqual(self.load(run)["log_id"], studio.log_ident(run.events))
        with open(run.events, "rb") as f:
            old = f.read()
        tmp = run.events + ".new"
        with open(tmp, "wb") as f:                    # equal-or-larger: size alone cannot tell
            f.write(old + old)
        os.replace(tmp, run.events)
        self.poll()
        self.assertEqual(self.comments_on(self.run_issue(run)["identifier"]).count(self.mirror.LOG_GONE), 1)
        self.assertEqual(self.tracked(), [])


if __name__ == "__main__":
    import unittest
    unittest.main()
