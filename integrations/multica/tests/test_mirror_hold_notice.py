"""Mirror: hold notices on the Run issue and the kickoff issue, and the per-event banner (#85 Task 2)."""
from __future__ import annotations

import json
import os
import time
from unittest import mock

import bridgetest  # noqa: F401  (puts the bridge package on sys.path)
from bridgetest import MirrorCase, ev, make_project, make_run
from bridge import multica_cli as mc
from bridge import notice

U = "2026-10-04T01:00:00Z"
X = "stop: need art (held 8h0m, no reply)"
BASE = "overnight-20261003-2214"


def held(story, why="w", until=U):
    return ev("story_state", story=story, state="held", why=why, until=until)


def state_(story, s, **kw):
    return ev("story_state", story=story, state=s, **kw)


class HoldNoticeTest(MirrorCase):
    def setUp(self):
        super().setUp()
        p = mock.patch.dict(os.environ, {"TZ": "PST8PDT"})
        self.addCleanup(time.tzset)          # LIFO: runs after the env patch is stopped
        p.start()
        self.addCleanup(p.stop)
        time.tzset()
        self.root = make_project(self.tmp, "game")

    # ----- helpers -----------------------------------------------------------

    def start(self, events=(), request=True, assignee=("agent", "ag-1")):
        for _ in range(3):
            self.board.add_issue("filler")
        req = self.board.add_issue("Tonight", assignee=assignee)
        self.board.add_run(req, "task-1", "2026-10-03T22:00:00Z", agent_id="ag-run")
        if request:
            os.makedirs(self.paths.links, exist_ok=True)
            with open(os.path.join(self.paths.links, "task-1"), "w") as f:
                f.write("task=task-1\nworkdir=/w/ws/%s-6d25f8ec1ce3/workdir\nagent=ag-link\n" % req.lower())
            run = make_run(self.home, self.root, origin="multica:task-1")
        else:
            run = make_run(self.home, self.root)
        run.append(*events)
        return req, run

    def begin(self, stories=("A", "B"), mode="integration", **kw):
        """A polled run: Run issue and the stories' issues exist. Sets self.req, self.run, self.RI."""
        events = [ev("run_started", mode=mode)]
        events += [ev("story_listed", story=s, chain=1, depends=[]) for s in stories]
        self.req, self.run = self.start(events, **kw)
        self.poll()
        self.RI = self.run_issue(self.run)["identifier"]
        return self.run

    def add(self, *events, poll=True):
        """Append each event and poll after it (poll=False: one read for all of them)."""
        for e in events:
            self.run.append(e)
            if poll:
                self.poll()
        if not poll:
            self.poll()

    def ident(self, story):
        return self.story_issue(self.run, story)["identifier"]

    def body(self, story, why="w", until=U, issue=None):
        return notice.hold_body(story, why, until, issue or self.ident(story), BASE)

    def kick(self, req=None):
        return self.comments_on(req or self.req)

    def run_status(self):
        return [c[3] for c in self.status_calls() if c[2] == self.RI]

    def banners(self):
        return [n for n in self.notes if n[0].startswith("notice:")]

    def saved(self):
        st = self.state.load_run(self.paths, self.key(self.run))
        if st is None:
            with open(os.path.join(self.paths.retired_dir, self.key(self.run) + ".json"), encoding="utf-8") as f:
                st = json.load(f)
        return st

    # ----- the Run issue (AC1-3) ---------------------------------------------

    def test_first_hold_blocks_run_issue_and_resume_unblocks(self):            # AC1
        self.begin()
        self.add(state_("A", "running"), held("A"))
        self.assertEqual(self.run_status(), ["in_progress", "blocked"])
        self.add(state_("A", "running"))
        self.assertEqual(self.run_status(), ["in_progress", "blocked", "in_progress"])
        self.assertEqual(self.comments_on(self.RI).count("studio: " + self.body("A")), 1)

    def test_two_holds_one_blocked_last_resume_unblocks(self):                 # AC2
        self.begin()
        self.add(held("A"), held("B"))
        self.assertEqual(self.run_status(), ["in_progress", "blocked"])
        self.add(state_("A", "running"))
        self.assertEqual(self.run_status(), ["in_progress", "blocked"])
        self.add(state_("B", "running"))
        self.assertEqual(self.run_status(), ["in_progress", "blocked", "in_progress"])
        notices = [c for c in self.comments_on(self.RI) if c in ("studio: " + self.body("A"), "studio: " + self.body("B"))]
        self.assertEqual(len(notices), 2)

    def test_run_end_while_held_ends_done(self):                               # AC3
        self.begin()
        self.add(held("A"), ev("run_ended", ending="done", report="/r"), poll=False)
        self.assertEqual(self.run_status()[-2:], ["blocked", "done"])
        statuses = self.run_status()
        self.assertNotIn("in_progress", statuses[statuses.index("blocked"):])
        self.assertEqual(self.saved()["held"], [])

    # ----- the kickoff notice (AC4, AC6, AC7) --------------------------------

    def test_kickoff_notice_once_per_hold_and_expiry(self):                    # AC4, AC7
        self.begin()
        self.add(held("A"))
        self.poll()
        self.add(state_("A", "stopped", why=X))
        self.assertEqual(self.kick(), [notice.kickoff_text(self.body("A")),
                                       notice.kickoff_text(notice.expiry_body("A", X))])
        self.assertIn("studio: " + notice.expiry_body("A", X), self.comments_on(self.RI))

    def test_no_request_issue_no_kickoff_notice(self):                         # AC4
        self.begin(request=False)
        self.add(held("A"), state_("A", "stopped", why=X))
        mine = {self.RI, self.ident("A"), self.ident("B")}
        self.assertEqual([c["argv"] for c in self.board.calls("issue comment add") if c["argv"][3] not in mine], [])
        self.assertEqual(len(self.banners()), 2)

    def test_request_issue_only_ever_gets_notices(self):                       # AC6
        self.begin()
        self.add(state_("A", "running"),
                 ev("unit_started", story="A", unit="u1", label="work"),
                 ev("unit_ended", story="A", unit="u1", label="work", outcome="progress", usd=1),
                 held("A"), state_("A", "running"), held("B"), state_("B", "stopped", why=X),
                 ev("message_queued", story="B", id=1, scope="story"),
                 ev("run_ended", ending="done", report="/r"))
        self.assertEqual([c for c in self.board.calls("issue status") if c["argv"][2] == self.req], [])
        posts = [c for c in self.board.calls("issue comment add") if c["argv"][3] == self.req]
        self.assertEqual(len(posts), 3)
        for c in posts:
            self.assertTrue(c["stdin"].startswith(mc.NOTICE_PREFIX), c["stdin"])
        self.assertEqual(self.board.wakeups(self.req), [])          # assigned, Run issue is its sub-issue: skipped
        self.assertEqual(self.saved()["end_wake"]["outcome"], "skipped")

    def test_request_issue_unassigned_still_arms_wake(self):                   # AC6: the #72 rule still arms
        self.begin(assignee=None)
        self.add(held("A"), ev("run_ended", ending="done", report="/r"))
        self.assertEqual(len(self.board.wakeups(self.req)), 1)
        self.assertEqual(self.kick(), [notice.kickoff_text(self.body("A"))])

    def test_operator_and_halt_stops_post_no_expiry_notice(self):              # AC7
        self.begin()
        self.add(held("A"), state_("A", "stopped", why="by operator"),
                 held("B"), state_("B", "stopped", why="stopped by user (was held: w)"))
        self.assertEqual(self.kick(), [notice.kickoff_text(self.body("A")), notice.kickoff_text(self.body("B"))])
        self.assertEqual(len(self.banners()), 2)
        self.assertFalse([c for c in self.comments_on(self.RI) if "hold ran out" in c])

    # ----- the text (AC8), single-plan (AC9) ---------------------------------

    def test_hold_notice_text_exact(self):                                     # AC8
        self.begin()
        self.add(held("A", why="stop: need art"))
        a, r = self.ident("A"), "--run " + BASE
        want = "\n".join([
            "studio: story A held: stop: need art",
            "Until 2026-10-03 18:00 PDT (2026-10-04T01:00:00Z UTC); then it stops.",
            "Multica: on %s post /say <text>, then /resume — or /stop." % a,
            "Terminal: studio-overnight say A %s -- <text> · studio-overnight resume A %s · "
            "studio-overnight stop A %s" % (r, r, r)])
        self.assertIn(want, self.comments_on(self.RI))

    def test_single_plan_adds_kickoff_and_banner_only(self):                   # AC9
        self.begin(stories=(), mode="single")
        self.add(state_("-", "running"), held("-", why="stop: need art"), state_("-", "landed"),
                 ev("run_ended", ending="done", report="/r"))
        self.assertEqual(self.run_status(), ["in_progress", "blocked", "done"])
        self.assertIn("studio: held: stop: need art — until %s — /say, /resume or /stop" % U, self.comments_on(self.RI))
        self.assertFalse([c for c in self.comments_on(self.RI) if "the run is held:" in c])
        self.assertEqual(self.kick(), [notice.kickoff_text(notice.hold_body("-", "stop: need art", U, self.RI, BASE))])
        self.assertEqual(len(self.banners()), 1)
        self.assertEqual(self.banners()[0][1], notice.banner_text("-", BASE, "stop: need art"))

    # ----- once per event (AC10), superseded (AC11), old state (AC12) --------

    def test_banner_once_per_event_across_restart(self):                       # AC10
        self.begin()
        offset = os.path.getsize(self.run.events)
        self.add(held("A"))
        self.ctx = self.state.Ctx(self.cfg, self.paths, self.cli, self.log,
                                  lambda kind, text: self.notes.append((kind, text)),
                                  now=lambda: self.t0 + self.skew)
        self.poll()
        self.poll()
        self.assertEqual(self.banners(), [("notice:%s:%d" % (self.key(self.run), offset),
                                           notice.banner_text("A", BASE, "w"))])
        self.assertEqual(len(self.kick()), 1)

    def test_superseded_hold_no_kickoff_no_banner(self):                       # AC11
        self.begin()
        self.add(held("A"), state_("A", "running"), poll=False)
        self.assertEqual(self.kick(), [])
        self.assertEqual(self.banners(), [])
        self.assertEqual(self.run_status(), ["in_progress"])
        self.assertIn("studio: " + self.body("A"), self.comments_on(self.RI))
        self.assertEqual(self.saved()["held"], [])

    def test_superseded_hold_beside_live_hold_still_blocks(self):              # AC11, second fixture
        self.begin()
        self.add(held("A"), held("B"), state_("A", "running"), poll=False)
        self.assertEqual(self.run_status(), ["in_progress", "blocked"])
        self.assertEqual(self.kick(), [notice.kickoff_text(self.body("B"))])
        self.assertEqual(len(self.banners()), 1)
        self.assertEqual(self.saved()["held"], ["B"])

    def test_superseded_flag_kept_across_retry(self):
        self.begin()
        self.board.fault("issue comment add", exit=1, stderr="503 service unavailable", contains=self.RI, count=1)
        self.run.append(held("A"))
        with self.assertRaises(mc.TransientError):
            self.poll()
        self.run.append(state_("A", "running"))      # now the retried hold has a later line: it stays live
        self.poll()
        self.poll()
        self.assertEqual(self.run_status(), ["in_progress", "blocked", "in_progress"])
        self.assertEqual(len(self.kick()), 1)

    def test_banner_first_survives_multica_outage(self):                       # final review: banner first
        self.begin()
        self.board.fault("issue comment add", exit=1, stderr="503 service unavailable", contains=self.RI, count=1)
        self.run.append(held("A"))
        with self.assertRaises(mc.TransientError):
            self.poll()
        self.assertEqual(len(self.banners()), 1)
        self.poll()
        self.assertEqual(len(self.banners()), 1)
        self.assertEqual(len(self.kick()), 1)

    def test_state_without_held_key_polls(self):                               # AC12
        self.begin()
        st = self.state.load_run(self.paths, self.key(self.run))
        st.pop("held", None)
        self.state.save_run(self.paths, st)
        self.add(held("A"))
        self.assertEqual(self.run_status(), ["in_progress", "blocked"])

    # ----- review findings ---------------------------------------------------

    def test_routed_story_notice_says_use_terminal(self):                      # RF4
        self.req, self.run = self.start([ev("run_started", mode="integration"),
                                         ev("story_listed", story="A", chain=1, depends=[])])
        self.board.fault("issue create", exit=1, stderr="Invalid request: no", contains="omega_story=A", count=-1)
        self.poll()
        self.RI = self.run_issue(self.run)["identifier"]
        self.add(held("A"))
        notices = [c for c in self.comments_on(self.RI) if c.startswith("studio: story A held: w\n")]
        self.assertEqual(len(notices), 1)
        self.assertIn("Multica: A has no issue — use the terminal.", notices[0])
        self.assertIn("blocked", self.run_status())                 # the AC12 change, pinned on purpose
        self.assertIn("blocked", [c[3] for c in self.status_calls() if c[2] == self.RI])   # catch-up lands blocked

    def test_hands_off_run_issue_still_notifies_kickoff(self):                 # RF1
        self.begin()
        self.board.assign(self.RI, "agent", "ag-9")
        self.poll()
        n = len(self.comments_on(self.RI))
        self.add(held("A"))
        self.assertEqual(len(self.comments_on(self.RI)), n)
        self.assertEqual(len(self.kick()), 1)
        self.assertEqual(len(self.banners()), 1)

    def test_kickoff_notice_permanent_error_dropped(self):                     # RF3
        self.begin()
        self.board.fault("issue comment add", exit=1, stderr="Invalid request", contains=self.req, count=-1)
        self.run.append(held("A"))
        with self.assertLogs("bridgetest", "ERROR") as logs:
            self.poll()
        self.assertTrue(any(self.req in m for m in logs.output), logs.output)
        self.assertEqual(self.saved()["offset"], os.path.getsize(self.run.events))
        self.assertTrue(any(c.startswith("studio: held: w") for c in self.comments_on(self.ident("A"))))
        self.assertEqual(self.kick(), [])
        self.assertEqual(len(self.banners()), 1)

    def test_permanent_comment_failure_still_notifies(self):
        self.begin()
        self.board.fault("issue comment add", exit=1, stderr="Invalid request", contains=self.ident("A"), count=3)
        self.run.append(held("A"))
        for _ in range(3):
            self.poll()
        self.assertEqual(len(self.banners()), 1)
        self.assertEqual(len(self.kick()), 1)
        self.assertIn("blocked", self.run_status())
