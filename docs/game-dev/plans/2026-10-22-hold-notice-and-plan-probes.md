# Hold notices + plan-time probes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A held story reaches the operator. The Run issue goes Blocked and carries a notice, the kickoff
issue gets a notify-only copy that wakes its agent, and a macOS banner fires for each hold and each
expiry. Separately, the plan skill runs measurements during planning (#86).
**Architecture:** This is bridge-only (`integrations/multica/bridge/`). A new pure module, `notice.py`,
builds every notice text and the held-set step. `mirror.event_writes` emits three more write kinds:
Run `status`/`comment`, `kickoff`, and `banner`. They ride the event's fixed `pending` list, so each one
is posted once. `Cli.add_notice` is the content-checked AC17 exception. The runner scripts do not change.
**Tech Stack:** Python 3.9 (`/usr/bin/python3`), unittest + the stub `multica` CLI, and POSIX sh tests.
**Spec:** `docs/game-dev/specs/2026-10-22-hold-notice-and-plan-probes.md` (AC1-AC18)
**Story branch:** `issue-85-86-hold-notice-plan-probes`, off origin/main cfe29ff. GitHub #85 and #86.
There is no Jira.

Paths: `M` = `integrations/multica/bridge/mirror.py`, `CLI` = `integrations/multica/bridge/multica_cli.py`,
`N` = `integrations/multica/bridge/notice.py` (new), `MT` = `integrations/multica/tests/`, `PL` =
`studios/game-dev/skills/plan/SKILL.md`, `ST` = `tests/studio_test.sh`. Line numbers are as of cfe29ff.
Relocate each one with its `grep -n` anchor before you edit. `$W` is the worktree root.

**Run recipe** (every "Run" below). Use a scratch cwd outside every repo and worktree, and set TMPDIR in
the same command to a directory you have checked exists. Never `rm -rf` outside scratch. A heavy suite
(`tests/run_all.sh`) first takes `mkdir /Users/xinli/GameDev/proj/omega-ai/.git/heavy-suite.lock` and
writes an owner file into it. `run_all.sh` does not take that lock itself (verified: it has no lock
code). Remove the lock when the suite ends. Run each long suite as one background run and wait for its
notification. Never stack pollers.

```sh
S=<your scratchpad>/hold85; mkdir -p "$S/tmp" && test -d "$S/tmp" && cd "$S" && export TMPDIR="$S/tmp"
( cd "$W/integrations/multica/tests" && /usr/bin/python3 -m unittest test_notice -v )   # one module
sh "$W/integrations/multica/tests/run.sh"            # the whole Multica suite (NOT in run_all.sh)
TESTS_ONLY="<names>" sh "$W/tests/studio_test.sh"     # then: dash "$W/tests/studio_test.sh"
```

## Global Constraints

- **No runner change.** `git diff origin/main -- studios/game-dev/bin` stays empty (AC17). A phoenix
  run is live. Never run `install.sh`, never touch the main checkout, never pull.
- Python 3.9: no `match`, and no `X | Y` types outside annotations (`from __future__ import annotations`
  is already at the top of each module).
- Marker: `NOTICE_PREFIX = "studio: [notify only] "`, in `CLI` next to `PREFIX`. It is the only way a
  comment reaches the request issue.
- Notify-only tail (exact): `Notify only: reply with one short line. Run no command; never resume, stop, say to or hold a story.`
- Expiry test: `why` matches `r" \(held \d+h\d+m, no reply\)$"`. The runner's `hm()` prints `%dh%dm`.
- Terminal commands use `--run <os.path.basename(st["run_dir"])>`. A slug works only inside a project.
  The registry branch (`overnight-channel.sh:143`) matches the basename alone.
- Banner kind: `"notice:%s:%s" % (st["key"], st["pending"]["offset"])`, through `ctx.notify`.
- State key `st["held"]`: a list of story ids. Every read is `st.get("held") or []`, because states
  saved before this change have no such key (AC12). Do not add it to `state.new_run_state`. That file
  is untouched.
- A README must contain no `Bash(` (`readme_test.sh` `test_readme_deny_list_by_reference`).
- Implementers commit only their own files: `git commit -m … -- <paths>`.
- **#83 S5 overlap** (merges later, edits M `STATUS` :14-16, `MT/test_mirror_runs.py`:290-305, README
  :225 and `overnight-events.md`): do not edit those lines or that file. Our only edits in
  `test_mirror_runs.py` are the assertion at :331 and the count at :547.
- No section of `PL` is renumbered (S5 cites §7).

## Review Focus

1. **A Run issue someone else owns.** If the Run issue is agent-assigned (hands-off), the notice is
   counted into the catch-up, not posted, and the blocked/in_progress changes land in the catch-up line.
   The kickoff notice and the banner still go out. Test: T2 `test_hands_off_run_issue_still_notifies_kickoff`.
2. **A hold that is over before the bridge reads it** (late adoption, or catch-up after an outage). No
   kickoff wake, no banner, no Run status churn, and it never joins the held set. Without that last
   point, a live hold of another story read in the same poll would never block the Run issue (found by
   Probe 1). Test: T2 `test_superseded_hold_no_kickoff_no_banner`, both fixtures.
3. **A kickoff issue that is gone or refuses writes** (404 or 4xx). The notice is logged and dropped, and
   the run's mirroring is not held back three polls. Test: T2 `test_kickoff_notice_permanent_error_dropped`.
4. **An `until` that does not parse** (`"u"` in old fixtures) and a story with no issue (routed, AC12).
   The text still forms. Tests: T1 `test_until_line_unparsable`, `test_hold_body_routed`; T2
   `test_routed_story_notice_says_use_terminal`.
5. **A stop that only looks like an expiry**: `stopped by user (was held: … (held 1h0m, no reply))`,
   `stopped by operator`, or a rule stop of a held story. Only a why that *ends* with the suffix
   counts. Test: T1 `test_is_expiry_table`.

## Falsified assumptions (planner falsify clause)

| Assumption (brief) | Verdict | Evidence |
|---|---|---|
| Expiry why ends `(held <h>m, no reply)` | **Corrected**: `(held <h>h<m>m, no reply)`, e.g. `(held 8h0m, no reply)` | `studio-overnight`:957 `hm()` `%dh%dm`; :982 |
| Expiry is a `stopped` story_state in both modes | True. Lanes write `stopped <ENDING>`. Single-plan write_report writes `stopped <ending>`. state_event takes why from `"stopped "*` | `overnight-lanes.sh`:1158-1161; `studio-overnight`:1514-1518, :851-861 |
| No separate expiry event | True | `studio-overnight`:982 sets ENDING only |
| Single-plan held already goes to the Run issue | True (`single` → `tgt="run"`, blocked is not terminal) | M:46-48, :63-66 |
| Manifest Run issue gets nothing on hold | True | M:62-72 |
| `--run` takes the full run name | **Refined**: inside a project the slug or the basename works. Outside a project, the registry branch matches only the basename, so the notice uses the basename | `overnight-channel.sh`:109-112, :143; `overnight-runs.sh`:54 |
| Verb syntax `say <story> --run <run> -- <text>` | True; chan_args takes options in any order; `-` is a positional | `overnight-channel.sh`:76-77, :85-98 |
| Writes are once per event, survive restarts | True: `pending.writes` is fixed at first compute; `done[]` is saved after each write; offset after the event | M:480-492, :475-477 |
| Bridge comments use the operator token, so they wake an assigned agent | True (probe 7) | spec 2026-10-03 :808-812; README:238-240 |
| The kickoff notice wakes the kickoff agent | **Falsified for queued kickoffs**: a queued kickoff (#72) is **unassigned**, so a comment wakes no one. The design keeps the notice (a record, plus a wake when assigned) and states the limit. The operator must decide about waking queued kickoffs | spec 2026-10-19 :10-16; M:658-660 (`is_hands_off(req_row)`) |
| `agent-instructions.md` reaches the live agent | **Falsified**: install copies it only when it creates an agent ("exists — skipped"). The guard text therefore also goes in `agent-context.md`, which `omega-multica-agent` appends to every session | `integrations/multica/install.sh`:368-376; `bin/omega-multica-agent`:70-77; README:272 |
| Who reads `multica-deny.txt` | `claude-multica` (mode 2) and `omega-multica-agent` (mode 3), both Multica agent runtimes. The operator's terminal (mode 1) does not. The new rules remove no operator verb | `bin/wrapper-lib.sh`:9, :17-30; README:13-14 |
| Operator-only filter covers agent `/resume` | Partly. Agent `/stop` and agent `/hold` (with the operator's id) are pinned, but `/resume` and `/say` are not. T3 adds them | `MT/test_commands.py`:217-221, :506-510; `bridge/commands.py`:166-168 |
| `notify` is once per outage | True; `notified` resets on every ok poll. A per-event kind makes it per event | `bridge/service.py`:80-90, :139 |
| Commands are never read on the request issue | True; only the Run and story issues are polled | `bridge/commands.py`:101-111 |
| `run_all.sh` takes the heavy-suite lock | **False**: there is no lock code. Take it by hand | `tests/run_all.sh` (grep `lock`: only comments about jobs) |
| Plan skill §6 starts at L166 and the approval stop is `Reply **approve**` | True (L166 heading, L181 stop, L168-172 self-review list) | `PL`:166-182 |
| Existing tests are untouched by the new Run writes | **False**: measured, see *Measured inputs* | probe below |

## Measured inputs

**Probe 1: which existing bridge tests change.** A throwaway copy of `integrations/multica` got a
prototype of the Run-issue writes: `blocked` on the first hold, a `studio: PROTO` comment per hold, and
`in_progress` when the set empties, with the held set kept in `apply_events`. The whole unittest suite
then ran.

```
cd <scratch>/proto/multica/tests && /usr/bin/python3 -m unittest discover -s . -p 'test_*.py' -t .
FAIL: test_event_mapping_rows (test_mirror_runs.MirrorRunsTest) (n=4 held, 5 gate-repair, 6 held, 7 sync-repair, 8 held, 9 landing)
FAIL: test_routed_story_status_never_touches_run_issue (test_mirror_runs.MirrorRunsTest)
FAIL: test_timed_out_write_found_applied_counts_success (test_mirror_status.MirrorStatusTest)
ERROR: 6 test_config + 3 test_config_fix tests — "studio_overnight: required outside a checkout"
Ran 326 tests in 373.396s   FAILED (failures=8, errors=9)
```

How to read it:
- The 9 config ERRORs come from where the copy sat (outside a git checkout), not from the change. In
  the worktree they pass.
- `test_routed_story_status_never_touches_run_issue` (:702-715) reads a hold and its stop in **one**
  poll. Under the superseded rule (T2) that hold writes no Run status, so the test must pass
  **unchanged**. That rule was added because of this probe: without it, a superseded hold would also
  keep a second live hold from blocking the Run issue.
- The prototype's comment did not carry the why, so it could not trip `test_sanitizer_on_relayed_fields`
  (:541-552). The real notice does, and its count goes from 2 to 3 (predicted, not measured).
- No hands-off catch-up test in `test_mirror_status.py` failed, so no `while assigned:` line changes.

**Expected set after T2's code, before Step 6:** `test_event_mapping_rows`,
`test_timed_out_write_found_applied_counts_success` and `test_sanitizer_on_relayed_fields`, and no
other test. T2 Step 5 re-runs the suite to check this. A different set is a BLOCK: stop and report.

**Probe 2: local-time format.** `TZ=PST8PDT /usr/bin/python3 -I -c` with
`time.strftime("%Y-%m-%d %H:%M %Z", time.localtime(calendar.timegm(time.strptime("2026-10-04T01:00:00Z", "%Y-%m-%dT%H:%M:%SZ"))))`
→ `2026-10-03 18:00 PDT`. `os.environ["TZ"]="UTC"; time.tzset()` → `2026-10-04 01:00 UTC`. Python 3.9.6.
T1's test pins these strings.

## Tasks

Groups that may run in parallel worktrees (no Touches overlap): **{T1 → T2}**, **T3**, **T4**, **T5**.
T2 needs T1's interfaces. T4's text follows the spec, not code. **Risky** (per-task Opus review): T1
(the AC17 seam), T2 (cross-system: the held set and the write pipeline). **Mechanical** (folded into the
final review): T3, T4, T5. A final whole-branch Opus review and the full gate (below) close the branch.

---

### Task 1: `notice.py` texts and the held-set step; `Cli.add_notice`. Risky

**Touches:** `N` (create), `CLI` (add `NOTICE_PREFIX` after `PREFIX` :14; `add_notice` after
`add_comment` :262-268), `MT/test_notice.py` (create).

**Interfaces (Produces):**
- `CLI.NOTICE_PREFIX: str = "studio: [notify only] "`
- `Cli.add_notice(self, ident: str, text: str) -> dict`: if `text` does not start with
  `NOTICE_PREFIX`, raise `ValueError`. Otherwise run `["issue","comment","add",ident,"--content-stdin"]`
  with `stdin=self._clean(text)`. It has **no** `_guard`. Its docstring names the carve-out and cites
  the spec, as `create_wakeup`'s does (:270-273).
- `notice.NOTICE_TAIL: str` (the exact tail in Global Constraints).
- `notice.until_line(until: str) -> str`: `"Until <local> (<until> UTC); then it stops."`, or
  `"Until <until>; then it stops."` when `state.parse_ts` raises `ValueError`/`TypeError`/`AttributeError`.
- `notice.is_expiry(why) -> bool`: the regex from Global Constraints, on `str(why or "")`.
- `notice.held_after(held: list, ev: dict) -> list`: a new list. For a `story_state` that is `held`, the
  story is added if absent. For any other state it is removed. A non-`story_state` event leaves the list
  unchanged. Order is kept.
- `notice.hold_body(story: str, why, until, issue, run: str) -> str`: the held text **without** the
  leading `studio: `. `story == "-"` is the single-plan form. `issue` is the identifier the Multica line
  names: the Run issue for single-plan, the story issue for manifest, or `None` (routed).
- `notice.expiry_body(story: str, why) -> str`, without `studio: `.
- `notice.kickoff_text(body: str) -> str` = `NOTICE_PREFIX + body + "\n" + NOTICE_TAIL`.
- `notice.banner_text(story: str, run: str, why=None, expired: bool = False) -> str`.

- [ ] **Step 1: Write `MT/test_notice.py` (failing).** It holds two classes: `NoticeTextTest(unittest.TestCase)`
  and `NoticeCliTest(bridgetest.BridgeCase)`. A `setUp` patches `TZ=PST8PDT` with
  `mock.patch.dict(os.environ, …)` + `time.tzset()`, and `addCleanup` re-runs `time.tzset()` after the
  patch stops.

```python
RUN = "overnight-bat-20261022-142751"
U = "2026-10-04T01:00:00Z"

def test_until_line_local_and_utc(self):
    self.assertEqual(notice.until_line(U), "Until 2026-10-03 18:00 PDT (2026-10-04T01:00:00Z UTC); then it stops.")

def test_until_line_unparsable(self):
    for u in ("u", "", None):
        self.assertEqual(notice.until_line(u), "Until %s; then it stops." % (u if u is not None else "?"))

def test_is_expiry_table(self):
    yes = ["stop: need art (held 8h0m, no reply)", "no progress on T3 (held 0h30m, no reply)", "x (held 24h0m, no reply)"]
    no = ["stopped by operator", "stop: need art", "stopped by user (was held: x (held 1h0m, no reply))",
          "x (held 8m, no reply)", "x (held 8h0m, no reply) ", "", None]
    for w in yes: self.assertTrue(notice.is_expiry(w), w)
    for w in no: self.assertFalse(notice.is_expiry(w), w)

def test_held_after_table(self):
    h = lambda st, s="A": {"event": "story_state", "story": s, "state": st}
    self.assertEqual(notice.held_after([], h("held")), ["A"])
    self.assertEqual(notice.held_after(["A"], h("held")), ["A"])
    self.assertEqual(notice.held_after(["A", "B"], h("running")), ["B"])
    self.assertEqual(notice.held_after(["B"], h("debug-repair")), ["B"])      # another story: unchanged
    self.assertEqual(notice.held_after(["A"], h("debug-repair")), [])         # unknown state still ends the hold
    self.assertEqual(notice.held_after(["A"], {"event": "unit_started", "story": "A"}), ["A"])
    src = ["A"]; notice.held_after(src, h("running")); self.assertEqual(src, ["A"])   # pure

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
    self.assertTrue(t.endswith("\nNotify only: reply with one short line. Run no command; never resume, stop, say to or hold a story."))

def test_banner_text(self):
    self.assertEqual(notice.banner_text("B", RUN, "w"), "B held in %s: w" % RUN)
    self.assertEqual(notice.banner_text("-", RUN, "w"), "run held in %s: w" % RUN)
    self.assertEqual(notice.banner_text("B", RUN, expired=True), "B stopped in %s: hold ran out" % RUN)

# NoticeCliTest
def test_add_notice_bypasses_guard_but_checks_marker(self):
    self.board.add_issue("request"); self.board.reset_calls()
    self.cli.forbidden.add("OMEG-1")
    c = self.cli.add_notice("OMEG-1", "studio: [notify only] story B held: [x](mention://agent/1)")
    self.assertTrue(c["id"])
    self.assertEqual(self.board.calls("issue comment add")[0]["argv"][:5], ["issue", "comment", "add", "OMEG-1", "--content-stdin"])
    self.assertIn("no-mention:", self.board.comments("OMEG-1")[0]["content"])        # sanitized like every post
    for bad in ("studio: held: x", "[notify only] x", " studio: [notify only] x"):
        with self.assertRaises(ValueError):
            self.cli.add_notice("OMEG-1", bad)
    with self.assertRaises(mc.ForbiddenWrite):
        self.cli.add_comment("OMEG-1", "studio: [notify only] x")                   # the old door stays shut
    with self.assertRaises(mc.ForbiddenWrite):
        self.cli.set_status("OMEG-1", "done")
    self.assertEqual(len(self.board.calls("issue comment add")), 1)
```

- [ ] **Step 2: Run it.** `( cd "$W/integrations/multica/tests" && /usr/bin/python3 -m unittest test_notice -v )`.
  Expected: an ImportError / AttributeError on `bridge.notice` and `add_notice`.
- [ ] **Step 3: Implement `N` and the two `CLI` additions** to the interfaces above. `N` imports
  `state` (for `parse_ts`) and `multica_cli` (for `NOTICE_PREFIX`), and nothing else from the bridge.
  It reads no files and makes no calls.
- [ ] **Step 4: Run Step 2's command, then `sh "$W/integrations/multica/tests/run.sh"`.** Expected:
  `test_notice` OK, the suite green, and `test_cli.test_request_issue_writes_forbidden` unchanged.
- [ ] **Step 5: Commit.** `git commit -m "feat(multica): notice texts and the notify-only CLI door (#85)" -- integrations/multica/bridge/notice.py integrations/multica/bridge/multica_cli.py integrations/multica/tests/test_notice.py`

---

### Task 2: Mirror wiring: Run issue held set, kickoff notice, banner. Risky

**Touches:** `M` (`event_writes` story_state branch :62-72, plus a new `notice_writes` beside it;
`post_notice` after `note()` :260-271; `_do_write` :386-391; `apply_events` :454-477; `_apply_one`
:480-485), `MT/test_mirror_hold_notice.py` (create), and the existing-test assertion updates that
Probe 1 predicts: `MT/test_mirror_runs.py` only at :331 and :547, and `MT/test_mirror_status.py` only at :394.

**Interfaces:**
- Consumes (T1): `notice.*`, `mc.NOTICE_PREFIX`, `Cli.add_notice`.
- Produces:
  - `event_writes(st, ev, superseded: bool = False) -> list`. It stays pure. The story_state branch
    appends `notice_writes(st, ev, superseded)` after today's writes, and today's writes do not change.
  - `notice_writes(st, ev, superseded=False) -> list` of `(kind, target, value)`:
    - manifest (not `single`): if the state is `held`, the event is not `superseded`, and
      `st.get("held")` is empty, add `("status","run","blocked")`. If the state is not `held`, the story is in the held set,
      `held_after(...) == []` and `not st.get("ended")`, add `("status","run","in_progress")`.
    - a hold, or an expiry (`state == "stopped" and notice.is_expiry(why)`): in a manifest run add
      `("comment","run", mc.PREFIX + body)`. Then, unless `superseded`: if `st["request"].get("issue")`
      is set, add `("kickoff","request", notice.kickoff_text(body))`. Always add
      `("banner","-", notice.banner_text(...))`.
    - `issue` for `hold_body`: in a single-plan run `st["run_issue"]`, otherwise `st["stories"].get(story)`.
      `run` = `os.path.basename(st["run_dir"].rstrip("/"))`.
  - `_do_write` handles `kind == "kickoff"` → `post_notice(ctx, st, value)` and `kind == "banner"` →
    `ctx.notify("notice:%s:%s" % (st["key"], (st.get("pending") or {}).get("offset")), value)`. Both
    come before the `tgt == "run"` branch.
  - `post_notice(ctx, st, text) -> None`: `ident = st["request"].get("issue")`. If it is empty, return.
    Otherwise `ctx.cli.add_notice(ident, text)`, and append the id to `st["posted"]` (POSTED_KEEP cut)
    as `post_comment` does. `mc.PermanentError` → `ctx.log.error(...)` and return; the notice is
    dropped. Transient and auth errors propagate. Hands-off is **not** checked: the kickoff is
    agent-assigned on purpose.
  - `apply_events`: iterate with an index. For a held `story_state`, `superseded` = some later line
    in this read is a `story_state` for the same story (`b"story_state" in raw`, then
    `studio.parse_event`). Pass it to `_apply_one(ctx, st, offset, ev, superseded=False)`, which hands
    it to `event_writes` only when it builds a new `pending`. After `_apply_one` returns True:
    `st["held"] = notice.held_after(st.get("held") or [], ev)`, **except for a superseded hold**,
    which never joins the set. On `run_ended`, `st["held"] = []`. Both happen before the existing
    offset save. A retried pending event recomputes `superseded` from the same, still-unread lines,
    so it gets the same value.

- [ ] **Step 1: Write `MT/test_mirror_hold_notice.py` (failing).** `class HoldNoticeTest(MirrorCase)`.
  Its `setUp` sets `TZ=PST8PDT` the way T1 does. Its helper is `start(events=(), request=True,
  assignee=("agent","ag-1"))`. It is a copy of `test_mirror_end_wake.py:24-34`'s `start`; with
  `request=False` it uses `make_run` without an origin. Add the small helpers
  `kick(req) = self.comments_on(req)`, `run_status() = [c[3] for c in self.status_calls() if c[2] == RI]`
  and `banners() = [n for n in self.notes if n[0].startswith("notice:")]`. Each test's assertions are
  listed below. `U = "2026-10-04T01:00:00Z"`, `X = "stop: need art (held 8h0m, no reply)"`.
  **Poll after each event**, unless a row says "one read". Two `story_state`s for the same story in
  one read make the first one superseded (AC11), which changes what the hold writes.

| Test | Events after `run_started(integration)` + `story_listed` A (and B) | Asserts |
|---|---|---|
| `test_first_hold_blocks_run_issue_and_resume_unblocks` (AC1) | A running; A held why=w until=U; poll; A running; poll | Run statuses `["in_progress","blocked"]` after the first poll, then `+["in_progress"]`. Run comments include `"studio: " + notice.hold_body("A","w",U,<A's ident>,run.basename)` exactly once |
| `test_two_holds_one_blocked_last_resume_unblocks` (AC2) | A held; B held; poll; A running; poll; B running; poll | Run statuses: one `blocked`; nothing new after the A resume; `in_progress` after the B resume. Two hold notices on the Run issue |
| `test_run_end_while_held_ends_done` (AC3) | A held; run_ended; poll | Run statuses end `["blocked","done"]`, with no `in_progress` after `blocked`; the saved state (or the retired one) has `held == []` |
| `test_kickoff_notice_once_per_hold_and_expiry` (AC4, AC7) | A held; poll; poll; A stopped why=X; poll | `kick(req)` == `[notice.kickoff_text(hold_body(...)), notice.kickoff_text(notice.expiry_body("A", X))]`; Run comments include `"studio: " + expiry_body("A", X)` |
| `test_no_request_issue_no_kickoff_notice` (AC4) | `request=False`; A held; A stopped why=X; poll | no `issue comment add` whose argv[3] is outside the Run and story issues; `banners()` has 2 |
| `test_request_issue_only_ever_gets_notices` (AC6) | A running; unit_started/ended; A held; A running; B held; B stopped why=X; message_queued; run_ended; poll after each | no `issue status` call with argv[2]==req; every `issue comment add` with argv[3]==req has stdin starting `studio: [notify only] ` (3 of them); `self.board.wakeups(req)` is what `ensure_end_wake` made (skipped for the assigned sub-issue case: `[]`) |
| `test_operator_and_halt_stops_post_no_expiry_notice` (AC7) | A held; A stopped why="by operator"; B held; B stopped why="stopped by user (was held: w)"; poll | `kick(req)` holds only the two hold notices; `banners()` has 2 |
| `test_hold_notice_text_exact` (AC8) | A held why="stop: need art" until=U | the Run comment equals the spec's four lines (built by hand in the test, not by calling `notice`), with `--run overnight-20261003-2214` and A's real identifier |
| `test_single_plan_adds_kickoff_and_banner_only` (AC9) | mode single; `-` running; `-` held; `-` landed; run_ended | Run statuses `["in_progress","blocked","done"]` (as in `test_single_plan_routes_to_run_issue`); Run comments contain no `the run is held:` line; `kick(req)` == `[kickoff_text(hold_body("-", …, RI, base))]`; `banners()` has 1 |
| `test_banner_once_per_event_across_restart` (AC10) | A held; poll; then `self.ctx = state.Ctx(…same…)`, poll twice | `banners()` has 1, its kind `"notice:%s:%d" % (key, offset of the held line)`; `kick(req)` still has 1 |
| `test_superseded_hold_no_kickoff_no_banner` (AC11) | A held; A running (one poll reads both) | `kick(req) == []`, `banners() == []`; Run statuses `["in_progress"]` only; the Run notice is posted. Second fixture: A held, B held, A running in one read: Run statuses gain exactly one `blocked`, and the kickoff has B's notice only |
| `test_state_without_held_key_polls` (AC12) | poll once; `st.pop("held")` from the saved state; A held; poll | no exception; Run `blocked` |
| `test_routed_story_notice_says_use_terminal` (RF4) | fault `issue create` for story A (as `test_mirror_runs.py`:700-715); A held | the Run comment contains `Multica: A has no issue — use the terminal.` |
| `test_hands_off_run_issue_still_notifies_kickoff` (RF1) | `self.board.assign(RI, "agent", "ag-9")`; poll; A held; poll | no new comment on RI; `kick(req)` has 1; `banners()` has 1 |
| `test_kickoff_notice_permanent_error_dropped` (RF3) | fault `issue comment add` exit 1 `Invalid request` only for argv[3]==req (the stub's `fault` match; read `bridgetest.Board.fault` :153-162); A held; poll | `offset` == file size after one poll; A's story comment posted; `banners()` has 1; an error is logged |

- [ ] **Step 2: Run it.** `( cd "$W/integrations/multica/tests" && /usr/bin/python3 -m unittest test_mirror_hold_notice -v )`.
  Expected: FAIL (no run status / kickoff writes).
- [ ] **Step 3: Implement the Interfaces block in `M`.** Add `from . import notice`. Leave `STATUS` (:14-16) untouched.
- [ ] **Step 4: Run Step 2's command.** Expected: OK.
- [ ] **Step 5: Run the whole suite** (`sh "$W/integrations/multica/tests/run.sh"`, in the background).
  Expected: failures in **exactly** the tests listed in Probe 1, and in no others. Any other failure is
  a BLOCK.
- [ ] **Step 6: Update those assertions.** These are the only edits allowed:
  - `test_mirror_runs.py:331` (`test_event_mapping_rows`): filter the story's status calls with
    `[(c[2], c[3]) for c in new_s if c[2] == row]`. Do not touch the rows table (:290-305, S5's).
  - `test_mirror_runs.py:547` (`test_sanitizer_on_relayed_fields`): `2` → `3`. The Run-issue notice
    relays the bad why too. Keep the three `assertNotIn`s.
  - `test_mirror_status.py:394` (`test_timed_out_write_found_applied_counts_success`): the retry
    poll now also writes the Run issue's `blocked`. Assert
    `[c for c in self.status_calls() if c[2] == self.sa] == []`, with a
    `# #85: the Run issue now follows holds` comment.
  Re-run the suite. Expected: green.
- [ ] **Step 7: Commit.** `git commit -m "feat(multica): a hold reaches the Run issue, the kickoff and a banner (#85)" -- integrations/multica/bridge/mirror.py integrations/multica/tests/test_mirror_hold_notice.py <the updated test files>`

---

### Task 3: Notify-only guards: agent text, deny rules, agent-authored commands. Mechanical

**Touches:** `integrations/multica/agent-context.md`, `integrations/multica/agent-instructions.md`,
`integrations/multica/multica-deny.txt`, `MT/wrappers_test.sh`, `MT/test_commands.py`.

- [ ] **Step 1: Write the failing tests.**
  - `MT/wrappers_test.sh`, a new `test_multica_deny_hold_verbs`. Register it in `run_tests` (:532-540).
    It does three things. First, `grep -Fxq` each of `Bash(*studio-overnight say*)`,
    `Bash(*studio-overnight unsay*)`, `Bash(*studio-overnight hold*)`, `Bash(*studio-overnight resume*)`
    and `Bash(*studio-overnight stop*)` in `$DENY`. Second, it strips every `Bash(…)` rule of `$DENY` to
    its inner pattern and checks with an unquoted `case "$cmd" in $pat)` that each of
    `studio-overnight resume B --run r`, `/x/bin/studio-overnight stop B`, `sh studio-overnight say B -- hi`,
    `studio-overnight unsay B 3` and `studio-overnight hold B` matches some rule. Third, it checks that
    none of `studio-overnight start --detach docs/runs/x.md`, `studio-overnight status`,
    `studio-overnight said B` and `studio-overnight next` matches any rule.
  - `MT/wrappers_test.sh`, a new `test_agent_notify_only_rule`. Register it the same way.
    `assert_contains "$CTXSRC" '^- A comment starting `studio: \[notify only\]`'` and the same on
    `agent-instructions.md`. Then `assert_contains` both for `never resume, stop, say to or hold a story`.
  - `MT/test_commands.py`, a new `test_agent_authored_resume_and_say_ignored`, next to
    `test_agent_authored_comment_with_the_operator_id_is_ignored` (:506). It calls `self.started()`, then
    `self.say(self.sa, "/resume", author_type="agent", author_id=bridgetest.OPERATOR)` and
    `self.say(self.sa, "/say go on", author_type="agent", author_id="ag-1")`, then `self.poll()`.
    Assert `self.verbs() == []` and `self.replies(self.sa) == []`.
- [ ] **Step 2: Run them.** `TESTS_ONLY="test_multica_deny_hold_verbs test_agent_notify_only_rule" sh "$W/integrations/multica/tests/wrappers_test.sh"`
  and `( cd "$W/integrations/multica/tests" && /usr/bin/python3 -m unittest test_commands -v )`.
  Expected: the two sh tests FAIL. The Python test passes already (it pins existing behaviour; AC13).
  If `wrappers_test.sh` has no `TESTS_ONLY`, run it whole.
- [ ] **Step 3: Edit the three text files.**
  - `multica-deny.txt`: append a `# #85: …` comment line ("a woken agent never rules on a hold; the
    operator's terminal does not read this file"), then the five rules, in the order above.
  - `agent-context.md`: after the last line, add
    `` - A comment starting `studio: [notify only]` is a notice for the operator: reply on that issue with one short line that repeats its first line, then stop. Run no command; never resume, stop, say to or hold a story. ``
  - `agent-instructions.md`: the same bullet, before the last bullet (`- Never change the status …`).
    Do not rewrap the neighbouring lines: `readme_test.sh`:155-159 pins two of them.
- [ ] **Step 4: Re-run Step 2's commands.** Then run the whole `wrappers_test.sh` and `readme_test.sh`. Expected: green.
- [ ] **Step 5: Commit** those five paths.

---

### Task 4: Docs. Mechanical

**Touches:** `integrations/multica/README.md` (avoid :225), `MT/readme_test.sh`,
`docs/game-dev/specs/2026-10-03-multica-integration.md`, `docs/game-dev/PROGRESS.md`.

- [ ] **Step 1: Write a failing `test_readme_hold_notices`** in `MT/readme_test.sh` and register it.
  It runs `assert_contains "$R" 'studio: \[notify only\]'`, `assert_contains "$R" 'An unassigned (queued) kickoff'`,
  and `assert_contains "$SPEC" 'Exception (#85)'`. Define `SPEC` the way the file defines its other paths.
  Run `sh "$W/integrations/multica/tests/readme_test.sh"`. Expected: FAIL.
- [ ] **Step 2: Edit the docs.**
  - README step 3, **Steer (phone)** (:133-135). Add: "A hold also turns the Run issue Blocked and
    posts a notice there and on your request issue; the kickoff agent's one-line reply is what reaches
    your phone."
  - README *What the board shows*: a bullet after the Run-issue status bullet (:228-229), not inside
    the table. It names the notice contents, the `studio: [notify only]` marker, the macOS banner, and
    "An unassigned (queued) kickoff wakes no agent; the banner is then the only alert."
  - README Troubleshooting phone line (:257-258) and Known risks (:274): one clause each, pointing at
    the hold notice. Write no `Bash(` anywhere.
  - Spec 2026-10-03 AC17 (:437-438). Append: "Exception (#85): hold and expiry notices, comments
    starting `studio: [notify only] ` and posted only through `Cli.add_notice`, which checks that prefix
    (specs/2026-10-22-hold-notice-and-plan-probes.md). Status and assignee stay forbidden; the #72
    wakeup rule is the other carve-out."
  - `PROGRESS.md`: a new top log entry, `### 2026-10-22 — Holds reach the operator; plans measure
    before approval (#85, #86)`, with 4-6 bullets: the Run issue blocked/in_progress, the kickoff
    notice and its limit, the banner, the guards, #86's rule. Add no install line; the controller adds
    that after merge.
- [ ] **Step 3: Re-run `readme_test.sh`.** Expected: green.
- [ ] **Step 4: Commit** those four paths.

---

### Task 5: #86 plan-time probes rule. Mechanical

**Touches:** `PL` (§6, between the heading :166 and "Run the writing-plans self-review" :168; the
self-review sentence :168-172), `ST` (new test; `run_tests` :853-861).

- [ ] **Step 1: Write the failing `test_plan_probe_rule`** in `ST`, after `test_plan_gated_godot_forms`.
  Append it to the last `run_tests` line.

```sh
test_plan_probe_rule() {
  PL="$REPO_ROOT/studios/game-dev/skills/plan/SKILL.md"
  assert_contains "$PL" '^\*\*Plan-time probes\.\*\* When the plan defines a measurement of engine or' "the rule opens §6"
  assert_contains "$PL" 'later task pins numbers from it or branches on its' "its trigger"
  assert_contains "$PL" 'Run it in the planning checkout, through the gated forms' "planning checkout, gated forms"
  assert_contains "$PL" 'as a measured input: the command and its output' "measured-input block"
  assert_contains "$PL" 'Restore any tracked file the probe regenerates, or commit it as an input' "regenerated files"
  assert_contains "$PL" 'mismatch is a BLOCK' "execute re-measures"
  assert_contains "$PL" "port the engine's own algorithm" "port, don't fit"
  assert_contains "$PL" 'Godot MCP) stays a run task' "the headless exception"
  assert_contains "$PL" 'every plan-time probe has a measured-input block, or is a run task with every outcome stated' "the self-review check"
  _p="$(grep -n -F -m1 -- '**Plan-time probes.**' "$PL" | cut -d: -f1)"
  _h="$(grep -n -F -m1 -- '## 6. Self-review, then gate' "$PL" | cut -d: -f1)"
  _r="$(grep -n -F -m1 -- 'Run the writing-plans self-review' "$PL" | cut -d: -f1)"
  _a="$(grep -n -F -m1 -- 'Reply **approve**' "$PL" | cut -d: -f1)"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -n "$_p" ] && [ -n "$_h" ] && [ -n "$_r" ] && [ -n "$_a" ] && [ "$_h" -lt "$_p" ] && [ "$_p" -lt "$_r" ] && [ "$_r" -lt "$_a" ]; then
    _pass "the probe rule sits under §6, before the self-review and the approval stop"
  else _fail "probe rule order ($_h < $_p < $_r < $_a)"; fi
  assert_eq 1 "$(grep -c '^## 7\. Sweep, for a manifest story' "$PL")" "§7 keeps its number"
}
```

- [ ] **Step 2: Run it.** `TESTS_ONLY=test_plan_probe_rule sh "$W/tests/studio_test.sh"`. Expected: FAIL.
- [ ] **Step 3: Edit `PL`.** Insert exactly this (exact copy; the voice of its neighbours) after the
  `## 6.` heading's blank line:

```
**Plan-time probes.** When the plan defines a measurement of engine or
tool behaviour, and a later task pins numbers from it or branches on its
result, run it now, before the approval stop:

- Run it in the planning checkout, through the gated forms
  (`studio-gate godot -- <Godot command>`, `studio-test --file <test file>`).
- Put the result in the plan as a measured input: the command and its output.
- Restore any tracked file the probe regenerates, or commit it as an input.
- The execute-time task re-measures and must equal the plan's values (a
  mismatch is a BLOCK); it never discovers them.
- Where the plan models the behaviour, port the engine's own algorithm; do
  not fit a formula.

A probe that cannot run headless at plan time (it needs a window or the
Godot MCP) stays a run task, and the plan states what happens for each
possible outcome.
```

  In the self-review sentence, after "every task has a `Spec:` line and a `Review:` line", add:
  "; every plan-time probe has a measured-input block, or is a run task with every outcome stated".
  Keep the sentence one sentence. Rewrap only that paragraph. The other `test_plan_*` pins
  (`run \`studio-brief validate <plan path>\``, `also fails on a bare Godot script/import run`) must
  still match on one line.
- [ ] **Step 4: Run all of `ST` under sh and dash.** Expected: green. Its floor is 741, and it only grows.
- [ ] **Step 5: Commit** `PL` and `ST`.

---

## Final gate (after the final review's fix wave)

1. `git diff origin/main --stat -- studios/game-dev/bin` prints nothing (AC17).
2. `sh "$W/integrations/multica/tests/run.sh"` is green.
3. Take the heavy-suite lock. Then `sh "$W/tests/run_all.sh"` and `TEST_SH=dash sh "$W/tests/run_all.sh"`
   (one at a time, each as a background run) must both be green. Release the lock.

## Needs the operator (after merge, not in this plan)

- Install, when no live run is reading the main checkout. Then a live check: hold a story and confirm
  three things. The Run issue goes Blocked with the notice. An agent-assigned kickoff's agent replies
  one line, and that reply rings the phone. The banner shows.
- Decide how a **queued (unassigned) kickoff** gets woken: a mention of the kickoff agent in the notice
  (an AC18 carve-out) or a once-only wakeup rule keyed on the Run issue going `blocked` (needs a probe of
  `--until-issue-state blocked`). Today it is only a record, and the banner alerts.
- An existing agent keeps its old `agent-instructions.md`. `agent-context.md` carries the same rule into
  every session, so no update is required.
