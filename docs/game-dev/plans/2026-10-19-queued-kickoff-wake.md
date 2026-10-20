# Queued Kickoff End-of-Run Wake — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When the bridge has a run's Run issue and the request issue gets no sub-issue wake (it is not agent-assigned, or the Run issue is not its sub-issue), the bridge arms one Multica wakeup rule on the request issue that fires when the Run issue ends. It arms it once per run, never doubles a rule that already exists, and leaves the operator a note with the hand command when it cannot arm it.

**Architecture:** Two new `Cli` methods (`list_wakeups`, read; `create_wakeup`, the one unguarded write: the AC17 carve-out) and the matching `stub-multica` commands come first. Then a new mirror step `ensure_end_wake(ctx, st)` runs in `poll_run` right after `refresh`. It records its decision in a new per-run key `st["end_wake"]` and saves it the moment the create returns. The docs (README queue recipe, agent instructions, Known risks, PROGRESS) are a separate task.

**Tech Stack:** Python ≥ 3.9 (`/usr/bin/python3`, stdlib `unittest`, not pytest), the offline `stub-multica`, POSIX sh contract tests (`tests/assert.sh`).

**Spec:** `docs/game-dev/specs/2026-10-19-queued-kickoff-wake-design.md`

Story: GitHub issue #72. Branch `issue-72-queued-kickoff-wake` (omega-ai has no Jira). **Base:** 989c36f. Line numbers are at that commit. Find each one again with its `grep -n`.

## Global Constraints

- Rule flags, exactly: `issue wakeup create <REQ> --until-issue <RUN> --until-issue-state ended --agent-id <AGENT> --mode once --expires-in 336h --instruction <TEXT>` (+ the `--output json` that `Cli.call` appends). Real Multica 0.6.1 accepts this form (verified live).
- `issue wakeup list <REQ> --output json` returns a JSON list of rules. Keys used: `id`, `enabled`, `condition` (`{"type": "other_issue", "identifier": "OMEG-101", "issue_id": "<uuid>", "state": "ended"}` or `null`). `create` returns one rule object.
- Instruction text, exactly (`%s` = the Run issue identifier):
  `The overnight run's Run issue %s has ended. Read its "studio: run ended:" comment and the report it names, then do what this issue's description says comes after the run.`
- Failure note on the Run issue, exactly (`REQ`, `WHY`, `REQ`, `RUN`, `AGENT`; `AGENT` is the literal `<agent id>` when unknown):
  ``studio: could not arm the end-of-run wake on REQ (WHY). Arm it by hand: `multica issue wakeup create REQ --until-issue RUN --until-issue-state ended --agent-id AGENT --mode once --expires-in 336h` ``
- `st["end_wake"]`: `None` (undecided; also what a missing key means, read with `st.get("end_wake")`) or `{"outcome": "armed"|"skipped"|"failed", "why": str, "rule": str|None}`.
- AC17 still holds for comments and statuses: `set_status`/`add_comment` on the request issue raise `ForbiddenWrite`. Only `create_wakeup` skips `_guard`.
- Hand-run suites: the cwd is a scratch dir outside every repo and worktree, and TMPDIR is set in the same command to a directory you have checked exists. Never `rm -rf` outside the scratch dir. Make it once per session:
  `S="$(mktemp -d "<your scratchpad>/mb72.XXXXXX")" && [ -d "$S" ] && echo "$S"`. Use `$WT` for your task worktree's absolute path. The command forms:
  - one file: `cd "$S" && TMPDIR="$S" PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 -m unittest discover -s "$WT/integrations/multica/tests" -t "$WT/integrations/multica/tests" -p '<file>.py' -v` (add `-k <name>` for one test)
  - a sh suite: `cd "$S" && TMPDIR="$S" sh "$WT/integrations/multica/tests/<name>_test.sh"`
  - the integration gate: `cd "$S" && TMPDIR="$S" sh "$WT/integrations/multica/tests/run.sh"`
  - `test_mirror_runs.py` takes about 100 s. Run each long suite once, in the background, and wait for its notification. Never stack poll loops.
- Review policy: T1 and T2 are risky (T1: a new seam, the AC17 carve-out, and a new stub data shape; T2: a cross-system mirror step and a state-schema change). Each gets its own Opus review. T3 is mechanical and folds into the final review. A standalone whole-branch Opus review always runs at the end (T4). Re-review only after a Critical, 3+ Importants or a production-bug fix; never a third pass.
- Nothing is installed or pulled into the main checkout while a phoenix overnight run is live. Land by PR merge only.

## Execution shape

| Task | Depends on | Wave | Review | Files |
|------|------------|------|--------|-------|
| T1 CLI wakeup methods + stub commands + fixtures | — | 1 | task (Opus) | `bridge/multica_cli.py`, `tests/stub-multica`, `tests/bridgetest.py`, `tests/fixtures/cli/wakeup-*.json`, `tests/fixtures/cli/README.md`, `tests/test_cli.py` |
| T2 `ensure_end_wake` + state key | T1 | 2 | task (Opus) | `bridge/mirror.py`, `bridge/state.py`, new `tests/test_mirror_end_wake.py`, `tests/test_state.py`, `tests/test_mirror_runs.py` (197-207 only) |
| T3 docs + README contract | T1 | 2 | final | `agent-instructions.md`, `README.md`, `tests/readme_test.sh`, `docs/game-dev/PROGRESS.md` |
| T4 final review, fix wave, full gate, PR | T1–T3 | 3 | — | — |

(All paths but PROGRESS are under `integrations/multica/`.)

T2 and T3 run at the same time, each in its own worktree branched from the story branch once T1 is on it. Both are cherry-picked onto the story branch, in either order. They share no file. T3 depends on T1 only because the README's new Multica flags are checked against `bridge/multica_cli.py` (D5).

## Decisions

- **D1 — Check order (fewest reads).** (1) `get_issue(REQ)`; if `is_hands_off` and the Run row's `parent_issue_id == req_row["id"]` → `skipped`, with no list call. (2) `list_wakeups(REQ)`; any matching rule → `skipped`. (3) `issue_runs(REQ)` → agent; none → `failed`. (4) `create_wakeup` → `armed`, then save at once.
- **D2 — The Run issue row.** `ctx.rows.get(RUN)`, else `ctx.cli.get_issue(RUN)` (the list right after a create may lag). The request row is **not** put in `ctx.rows`.
- **D3 — The matching rule doubles as idempotency.** A create that timed out but landed is found by the next poll's list and recorded `skipped`. So a `TransientError` on create records nothing and retries safely.
- **D4 — Failure order.** Set `st["end_wake"]` to `failed`, log, `note()`, `ctx.notify("wake", …)`, then `state.save_run`. A transient during the note leaves the decision unsaved, so the next poll redoes it and the note is still posted once. This is the `_poll_failed` pattern ("only after note() returned").
- **D5 — README flags.** `test_readme_flags_exist` requires every `--flag` in the README to appear in install/uninstall `--help`. The queue recipe names the Multica flags `--until-issue`, `--until-issue-state`, `--agent-id`, `--mode`, `--expires-in` and `--instruction`. The spec missed this. The check also accepts a flag that appears in `bridge/multica_cli.py`, the adapter that sends it. That keeps the rule "documented flags exist in code".
- **D6 — Hand command (spec deviation, deliberate).** It adds `--mode once` to the spec's text, so a hand-armed rule matches the bridge's rule. It is wrapped in single backticks, so `<agent id>` is not eaten as an HTML tag. `sanitize` only breaks fences of 3 or more backticks.
- **D7 — `_clean` on the instruction.** `create_wakeup` passes the instruction through `self._clean` (redact, then sanitize), as every outgoing text does. The fixed text has no `@`, no mention and no fence, so it is sent unchanged, and the tests assert the exact text.
- **D8 — `why` strings.** skipped: `"agent-assigned; the Run issue is its sub-issue"` or `"rule <id> already wakes on <RUN>"`. armed: `"no sub-issue wake covers it"`. failed: the redacted first line of the error, at most 200 chars (`mc.redact(e, [ctx.cli.token]).splitlines()[0][:200]`), or `"no agent id for task <task> in issue runs <REQ>"`.
- **D9 — Spec erratum.** The test at `test_mirror_runs.py:197-207` (`test_run_issue_parent_create_fails_retries_top_level`) has an **agent-assigned** request, not an unassigned one. Its Run issue falls back to top level, so the spec's rule still arms it. T2 adds the armed assertions there. Nothing in it fails as it stands: `calls("issue create")` does not match `issue wakeup create`.
- **D10 — Queue recipe's `<prior>`.** The README calls it "the issue whose finishing should start this run (normally the kickoff issue of the run ahead)". The spec does not say which issue it is.

## Review Focus

1. **A create that timed out but landed** must not make a second rule. Expected: the next poll finds it and records `skipped`. Pinned by `test_create_landed_despite_transient_is_not_repeated` (T2).
2. **The Run issue row is missing from the poll's `issue list`** (list lag right after the create). Expected: the bridge reads it with `issue get`, so an agent-assigned sub-issue still skips. Pinned by `test_run_row_missing_from_list_is_read` (T2).
3. **A transient on the failure note.** Expected: no decision saved, the next poll posts the note once. Pinned by `test_failure_note_transient_retries_once` (T2).
4. **The OMEG-92 hand rule written in another case, or matched only by UUID.** Expected: `skipped`, no create. Pinned in `test_existing_matching_rule_skips` (T2, lowercase and issue_id-only sub-cases).
5. **The request issue was deleted before the decision** (`issue get` → not found). Expected: `failed`, one note, no retry. Pinned by `test_request_issue_gone_fails` (T2).

---

### Task 1: CLI wakeup methods, stub commands, fixtures (risky)

**Files:**
- Modify: `integrations/multica/bridge/multica_cli.py` (reads at 192-232: add `list_wakeups` after `issue_runs`; writes at 235-265: add `create_wakeup` after `add_comment`)
- Modify: `integrations/multica/tests/stub-multica` (SPEC 39-61, `make_run` 157-164, a new `make_wakeup` after it, two handlers before `HANDLERS`, `HANDLERS` 527-535)
- Modify: `integrations/multica/tests/bridgetest.py` (`Board.__init__` board dict 43-47; `add_run` 116-121; new `add_wakeup`, `wakeups`)
- Create: `integrations/multica/tests/fixtures/cli/wakeup-list.json`, `wakeup-create.json`; modify `fixtures/cli/README.md` (one paragraph)
- Test: `integrations/multica/tests/test_cli.py` (CONFORMANCE 242-257, `test_stub_conformance` 266-280, `test_stub_rows_carry_bridge_keys` 282-295, new tests)

**Interfaces (Produces):**
- `Cli.list_wakeups(self, ident: str) -> list[dict]`: `rows(self.call(["issue", "wakeup", "list", ident]))`.
- `Cli.create_wakeup(self, issue: str, until_issue: str, state: str, agent_id: str, expires: str, instruction: str) -> dict`: calls `["issue", "wakeup", "create", issue, "--until-issue", until_issue, "--until-issue-state", state, "--agent-id", agent_id, "--mode", "once", "--expires-in", expires, "--instruction", self._clean(instruction)]`. **No `_guard`.** The docstring says it is the AC17 carve-out: a wakeup rule is neither a comment nor a status, starts no run when created, and is the bridge's one write on a request issue. It cites `docs/game-dev/specs/2026-10-19-queued-kickoff-wake-design.md`.
- stub: `make_run(issue_id, run_id, started_at, completed_at=None, status="completed", agent_id="ag-1")`; `make_wakeup(board, issue_row, agent_id, condition, mode="once", instruction="", expires_at=None, enabled=True, fire_count=0) -> dict`. The rule's key set is exactly `{"agent_id", "agent_name", "condition", "created_by_agent", "enabled", "expires_at", "fire_count", "id", "instruction", "issue_id", "kind", "mode"}`. `id` is `"wk-%d" % next_n(board, "wakeup")`, `kind` is `"condition"`, `created_by_agent` is `False`, and `agent_name` is the name from `board["agents"]` with that id, else `None`. Rules live in `board["wakeups"]` (a list; handlers use `board.setdefault`).
- stub SPEC: `("issue", "wakeup", "list"): ((), (), 1)` and `("issue", "wakeup", "create"): (("--until-issue", "--until-issue-state", "--agent-id", "--mode", "--expires-in", "--instruction"), (), 1)`.
- stub `h_wakeup_create`: `find_issue` for the positional and for `--until-issue` (a missing one → `not-found`, exit 4). It raises `usage(...)` when `--until-issue`, `--until-issue-state` or `--agent-id` is missing, when the state is not in `("done", "cancelled", "ended")`, or when `--expires-in` is not `<digits>h` (`v.endswith("h") and v[:-1].isdigit()`; the stub does not import `re`). Usage errors exit 2 with `Error: …`, which `classify` turns into a `PermanentError`. Their text must not contain "not found", "deleted" or "archived". `condition = {"type": "other_issue", "identifier": until["identifier"], "issue_id": until["id"], "state": state}`. `expires_at = fmt(base + hours*3600)`, where `base` is `board["now"]`, or `time.time()` when that is None. Returns the rule. `h_wakeup_list` returns the plain list of rules whose `issue_id` is the issue's `id`.
- `Board.add_run(..., agent_id="ag-1")` (passed to `make_run`). `Board.add_wakeup(self, ident, condition=None, enabled=True, fire_count=0, agent_id="ag-1") -> str` (the rule id). `Board.wakeups(self, ident) -> list`. `Board.__init__` adds `"wakeups": []`.

- [ ] **Step 1: Write the failing tests** in `test_cli.py` (class of `test_request_issue_writes_forbidden`, a `BridgeCase`):

```python
INSTR = 'The overnight run\'s Run issue OMEG-2 has ended. Read its "studio: run ended:" comment and the report ' \
        'it names, then do what this issue\'s description says comes after the run.'

def test_create_wakeup_args_and_not_guarded(self):
    self.board.add_issue("request"); self.board.add_issue("run")
    self.board.reset_calls()
    self.cli.forbidden.add("OMEG-1")
    rule = self.cli.create_wakeup("OMEG-1", "OMEG-2", "ended", "ag-1", "336h", INSTR)
    self.assertEqual(self.board.calls("issue wakeup create")[0]["argv"],
                     ["issue", "wakeup", "create", "OMEG-1", "--until-issue", "OMEG-2", "--until-issue-state", "ended",
                      "--agent-id", "ag-1", "--mode", "once", "--expires-in", "336h", "--instruction", INSTR,
                      "--output", "json"])
    self.assertEqual(rule["condition"], {"type": "other_issue", "identifier": "OMEG-2", "issue_id": "iss-2", "state": "ended"})
    self.assertEqual([r["id"] for r in self.cli.list_wakeups("OMEG-1")], [rule["id"]])
    with self.assertRaises(ForbiddenWrite):
        self.cli.set_status("OMEG-1", "done")
    with self.assertRaises(ForbiddenWrite):
        self.cli.add_comment("OMEG-1", "studio: hi")

def test_stub_wakeup_errors(self):
    self.board.add_issue("request")
    with self.assertRaises(NotFoundError):
        self.cli.create_wakeup("OMEG-1", "OMEG-9", "ended", "ag-1", "336h", "x")
    with self.assertRaises(PermanentError):
        self.cli.create_wakeup("OMEG-1", "OMEG-1", "in_progress", "ag-1", "336h", "x")
    self.assertEqual(self.cli.list_wakeups("OMEG-1"), [])
```

`NotFoundError` and `PermanentError` are already imported (`test_cli.py:15-16`). `INSTR` is a module constant. Add to CONFORMANCE: `"wakeup-list.json": ["issue", "wakeup", "list", "OMEG-1"]` and `"wakeup-create.json": ["issue", "wakeup", "create", "OMEG-1", "--until-issue", "OMEG-1", "--until-issue-state", "ended", "--agent-id", "ag-1", "--mode", "once", "--expires-in", "336h", "--instruction", "x"]`. In `test_stub_conformance`, after the `add_run` line, add `self.board.add_wakeup("OMEG-1", {"type": "other_issue", "identifier": "OMEG-1", "issue_id": "iss-1", "state": "ended"})`: the list mapping runs before the create, and an empty list cannot pin a shape. In `test_stub_rows_carry_bridge_keys`, add a `"run"` key `"agent_id"` and a `"wakeup"` entry `("id", "enabled", "condition")`, checked against `self.cli.list_wakeups("OMEG-1")[0]` after a `self.board.add_wakeup("OMEG-1")`.

- [ ] **Step 2: Run, expect FAIL** (`AttributeError: 'Cli' object has no attribute 'create_wakeup'`, and the conformance test's "fixture without a stub mapping" once the fixtures exist):
  `cd "$S" && TMPDIR="$S" PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 -m unittest discover -s "$WT/integrations/multica/tests" -t "$WT/integrations/multica/tests" -p 'test_cli.py' -v`

- [ ] **Step 3: Write the fixtures.** `wakeup-create.json` is one rule object with exactly the key set above. It uses synthetic UUID-form ids in the style of `issue-runs.json` (`00000000-0000-4000-8000-…`), `"agent_name": "gd-probe"`, `"mode": "once"`, `"kind": "condition"`, `"created_by_agent": false`, `"fire_count": 0`, `"expires_at"` as a Z timestamp, and the condition of a Run issue. `wakeup-list.json` is a one-element list of the same shape. The README paragraph says the two wakeup fixtures carry the subset of keys known from the 2026-10-19 live 0.6.1 output (that output has more keys, which the bridge does not read), and that a live `issue wakeup list --output json` can refresh them.

- [ ] **Step 4: Implement** the stub SPEC entries, `make_wakeup`, `make_run`'s `agent_id`, the two handlers and their `HANDLERS` entries; the `Board` changes; then the two `Cli` methods.

- [ ] **Step 5: Run, expect PASS:** the Step 2 command, then `test_state.py` and `test_mirror_runs.py` (the `add_run`/`make_run` default keeps `"ag-1"`, so they must stay green). Run `test_mirror_runs.py` once, in the background.

- [ ] **Step 6: Commit**
```bash
git add integrations/multica/bridge/multica_cli.py integrations/multica/tests/stub-multica integrations/multica/tests/bridgetest.py integrations/multica/tests/fixtures/cli integrations/multica/tests/test_cli.py
git commit -m "multica: wakeup list/create in the CLI adapter and stub (#72)"
```

---

### Task 2: `ensure_end_wake` in the poll, `end_wake` state (risky)

**Files:**
- Modify: `integrations/multica/bridge/mirror.py`: constants after line 23; `_wakes_on_end`, `_end_wake`, `ensure_end_wake` in a new `# ----- the end-of-run wake (#72) -----` section before `# ----- the poll -----` (~625); one call in `poll_run` (627-649)
- Modify: `integrations/multica/bridge/state.py`: `new_run_state` (125-143) gains `"end_wake": None`
- Create: `integrations/multica/tests/test_mirror_end_wake.py`
- Modify: `integrations/multica/tests/test_state.py:97-109`: add `"end_wake"` to `want`, and assert `st["end_wake"] is None`
- Modify: `integrations/multica/tests/test_mirror_runs.py:197-207`: append the armed assertions (D9)

**Interfaces:**
- Consumes (T1): `ctx.cli.list_wakeups(ident) -> list[dict]`; `ctx.cli.create_wakeup(issue, until_issue, state, agent_id, expires, instruction) -> dict`; `Board.add_run(..., agent_id=)`, `Board.add_wakeup(ident, condition=None, enabled=True, fire_count=0, agent_id="ag-1") -> str`, `Board.wakeups(ident) -> list`.
- Existing, unchanged: `note(ctx, st, text)`, `ctx.notify(kind, text)`, `is_hands_off(row)`, `ctx.cli.get_issue(ident) -> dict`, `ctx.cli.issue_runs(ident) -> list[dict]` (a run row's `id` is the task id; its `agent_id` is the agent), `state.save_run(paths, st)`.
- Produces: `WAKE_STATE = "ended"`, `WAKE_EXPIRES = "336h"`, `WAKE_INSTRUCTION` (Global Constraints text, one `%s`), `WAKE_FAILED_NOTE` (Global Constraints text, five `%s`). Also `_wakes_on_end(rule, run_ident: str, run_uuid: str | None) -> bool` and `_end_wake(ctx, st, outcome: str, why: str, rule: str | None = None) -> None`, which sets the key and saves. And `ensure_end_wake(ctx, st) -> None`.

**`poll_run` placement** (spec §Where): right after `refresh(ctx, st)` and its `if st["retired"]: return`, before `reconcile`:
```python
    refresh(ctx, st)
    if st["retired"]:
        return
    ensure_end_wake(ctx, st)
    reconcile(ctx, st)
```

**The algorithm** (the hard part; D1–D4, D8):
```python
def _wakes_on_end(rule, run_ident, run_uuid) -> bool:
    c = rule.get("condition") if isinstance(rule, dict) else None
    if not isinstance(c, dict) or c.get("type") != "other_issue" or c.get("state") not in ("done", "ended"):
        return False
    return str(c.get("identifier") or "").upper() == run_ident.upper() or bool(run_uuid and c.get("issue_id") == run_uuid)


def ensure_end_wake(ctx, st):
    """#72: a request issue no sub-issue wake covers gets one end-of-run wakeup rule (the AC17 carve-out)."""
    rq, run = st["request"], st.get("run_issue")
    if rq["state"] != "found" or not rq.get("issue") or not run or st.get("end_wake") is not None:
        return
    req, agent = rq["issue"], None
    try:
        req_row = ctx.cli.get_issue(req)
        run_row = ctx.rows.get(run) or ctx.cli.get_issue(run)
        if is_hands_off(req_row) and run_row.get("parent_issue_id") == req_row.get("id"):
            return _end_wake(ctx, st, "skipped", "agent-assigned; the Run issue is its sub-issue")
        for rule in ctx.cli.list_wakeups(req):
            if _wakes_on_end(rule, run, run_row.get("id")):
                return _end_wake(ctx, st, "skipped", "rule %s already wakes on %s" % (rule.get("id"), run))
        agent = next((r.get("agent_id") for r in ctx.cli.issue_runs(req) if r.get("id") == rq["task"]), None)
        if agent:
            made = ctx.cli.create_wakeup(req, run, WAKE_STATE, agent, WAKE_EXPIRES, WAKE_INSTRUCTION % run)
            return _end_wake(ctx, st, "armed", "no sub-issue wake covers it",
                             made.get("id") if isinstance(made, dict) else None)
        why = "no agent id for task %s in issue runs %s" % (rq["task"], req)
    except mc.PermanentError as e:          # NotFoundError included; Transient/Auth propagate, nothing recorded
        why = (mc.redact(e, [ctx.cli.token]).splitlines() or [""])[0][:200]
    st["end_wake"] = {"outcome": "failed", "why": why, "rule": None}
    ctx.log.error("run %s: end-of-run wake on %s not armed: %s", st["key"], req, why)
    note(ctx, st, WAKE_FAILED_NOTE % (req, why, req, run, agent or "<agent id>"))
    ctx.notify("wake", "omega bridge: could not arm the end-of-run wake on %s, see Run issue %s" % (req, run))
    state.save_run(ctx.paths, st)           # only after note() returned: a transient on the post retries it (D4)
```

**Test helper** for `test_mirror_end_wake.py` (`class EndWakeTest(bridgetest.MirrorCase)`; `setUp` adds `self.root = make_project(self.tmp, "game")`):
```python
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
```
`self.creates()` = `self.board.calls("issue wakeup create")`. `INSTR` is the instruction template, as in T1.

- [ ] **Step 1: Write the failing tests.** Each line is a test name and what it asserts:
  1. `test_unassigned_request_arms_once`: `start()`, poll. One create, `argv == ["issue","wakeup","create",req,"--until-issue",RUN,"--until-issue-state","ended","--agent-id","ag-run","--mode","once","--expires-in","336h","--instruction",INSTR % RUN,"--output","json"]` with `RUN = self.run_issue(run)["identifier"]`. `end_wake(run) == {"outcome": "armed", "why": "no sub-issue wake covers it", "rule": self.board.wakeups(req)[0]["id"]}`. Then `reset_calls()` and poll again: `calls("issue wakeup") == []` and no `issue get` call has `req` in its argv.
  2. `test_agent_id_from_issue_runs_not_link`: the create argv has `"--agent-id", "ag-run"` and not `ag-link`.
  3. `test_agent_assigned_sub_issue_skips`: `start(assignee=("agent", "ag-1"))`. No create, no `issue wakeup list` call, outcome `skipped`, why `"agent-assigned; the Run issue is its sub-issue"`.
  4. `test_agent_assigned_top_level_fallback_arms`: as 3, plus `self.board.fault("issue create", exit=1, stderr="Invalid request: bad parent", contains="--parent", count=1)`. The Run issue's `parent_issue_id` is None, one create, `armed`. A subTest covers a reused top-level Run issue (`reuse_run_issue(run, None)`, no fault): armed.
  5. `test_member_assigned_request_arms`: `start(assignee=("member", bridgetest.OPERATOR))`. Armed.
  6. `test_existing_matching_rule_skips`: `start()`, `RUN = reuse_run_issue(run, req)`. One subTest per rule (each on a fresh setUp; use a helper that rebuilds, or one test method per case): `{"type":"other_issue","identifier":RUN,"issue_id":"x","state":"ended"}` enabled; the same with `"done"`, `enabled=False, fire_count=1`; `identifier=RUN.lower()`; `identifier="OMEG-999"` with `issue_id` = the Run issue's `id`. Each gives no create, `skipped`, and a why that starts `"rule "`.
  7. `test_non_matching_rule_still_arms`: the rules `condition=None`; `{"type":"other_issue","identifier":"OMEG-999","issue_id":"x","state":"ended"}`; and the same identifier as the Run issue with `"state":"todo"`. One create, armed.
  8. `test_request_none_or_pending_records_nothing`: a run with no origin, and a run whose `issue runs` faults `503 service unavailable` with `count=-1` (it stays pending). Both have `end_wake(run) is None` and `calls("issue wakeup") == []`.
  9. `test_transient_on_create_retries_next_poll`: fault `"issue wakeup create"` exit 1, `503 service unavailable`, count 1. `with self.assertRaises(mc.TransientError): self.poll()`. Then `end_wake(run) is None`. The next poll arms, `len(self.board.wakeups(req)) == 1`.
  10. `test_create_landed_despite_transient_is_not_repeated`: the same fault plus `apply=True`. The first poll raises TransientError. The second poll gives `len(creates) == 1`, `skipped`, one rule (D3).
  11. `test_permanent_error_fails_once_with_note`: fault `"issue wakeup create"` with `"Invalid request: bad agent"`, `count=-1`. Poll: `failed`, why contains `bad agent`, `self.notes` has one `("wake", …)`. The Run issue has exactly one comment starting `"studio: could not arm the end-of-run wake on %s (" % req` and containing `` "`multica issue wakeup create %s --until-issue %s --until-issue-state ended --agent-id ag-run --mode once --expires-in 336h`" % (req, RUN) ``. A second poll leaves the creates at 1 and that comment's count at 1.
  12. `test_permanent_error_on_list_fails`: fault `"issue wakeup list"` permanent `count=-1`. `failed`, the note has `--agent-id <agent id>` (the agent is not read yet), no create.
  13. `test_unknown_agent_fails_with_note`: `start(run_agent=None)`. No create, `failed`, why `"no agent id for task task-1 in issue runs %s" % req`, the note has `--agent-id <agent id>`.
  14. `test_request_issue_gone_fails`: `start()`. Poll once with a transient fault on `"issue wakeup list"` (count 1, expect TransientError). Then `self.board.remove_issue(req)` and poll: `failed`, one note. A third poll adds no note.
  15. `test_state_without_end_wake_loads_and_arms`: a transient fault on `"issue wakeup list"` (count 1), poll (TransientError). Rewrite the state file with `end_wake` popped (`state.load_run` / `atomic_write_json` on `paths.state_dir/<key>.json`). Poll: armed.
  16. `test_run_ending_in_first_poll_arms_then_retires`: `start(events=(ev("run_started", mode="integration"), ev("run_ended", ending="done", report="/r")))`. After one poll, one rule whose condition identifier is the Run issue, the Run issue's status is `done`, the key is in `self.state.load_retired(self.paths)`, and the retired copy (`paths.retired_dir/<key>.json`) has `end_wake.outcome == "armed"`.
  17. `test_create_not_refused_by_request_guard`: after an armed poll, `req` is in `self.cli.forbidden` (case-insensitive), the create call has `exit == 0`, and `self.cli.set_status(req, "done")` and `self.cli.add_comment(req, "studio: x")` both raise `mc.ForbiddenWrite`.
  18. `test_run_row_missing_from_list_is_read`: `start(assignee=("agent", "ag-1"))`, `with mock.patch.object(self.cli, "run_issues", return_value=[]): self.poll()`. Outcome `skipped` (the parent came from `issue get <RUN>`).
  19. `test_failure_note_transient_retries_once`: a permanent fault on create (`count=-1`) and `self.board.fault("issue comment add", exit=1, stderr="503 service unavailable", count=1)` (no events, so the note is the first comment). The first poll raises TransientError, `end_wake is None`. The second poll gives `failed` and exactly one failure comment.

  Plus `test_state.py::test_new_run_state_has_every_key` (`"end_wake"` in `want`, value None) and, in `test_mirror_runs.py::test_run_issue_parent_create_fails_retries_top_level`, the lines `self.assertEqual(self.load(run)["end_wake"]["outcome"], "armed")` and `self.assertEqual(len(self.board.wakeups(req)), 1)`.

- [ ] **Step 2: Run, expect FAIL** (`AttributeError`, or no `end_wake` key):
  `... -p 'test_mirror_end_wake.py' -v`, then `-p 'test_state.py'`.

- [ ] **Step 3: Implement** the constants, `_wakes_on_end`, `_end_wake`, `ensure_end_wake` and the `poll_run` call in `mirror.py`, and `"end_wake": None` in `new_run_state`.

- [ ] **Step 4: Run, expect PASS:** `test_mirror_end_wake.py`, `test_state.py`, then (once, in the background) `test_mirror_runs.py`, `test_mirror_status.py`, `test_commands.py`.

- [ ] **Step 5: Commit**
```bash
git add integrations/multica/bridge/mirror.py integrations/multica/bridge/state.py integrations/multica/tests/test_mirror_end_wake.py integrations/multica/tests/test_state.py integrations/multica/tests/test_mirror_runs.py
git commit -m "multica: the bridge arms a queued kickoff's end-of-run wake (#72)"
```

---

### Task 3: Docs, README contract, PROGRESS (mechanical)

**Files:**
- Modify: `integrations/multica/agent-instructions.md:12`
- Modify: `integrations/multica/README.md`: new section between `## Nightly workflow` (103) and `## Commands` (158); the wake bullet at 214-215; the Known risks line at 251-252, plus four limit lines
- Modify: `integrations/multica/tests/readme_test.sh`: `test_readme_flags_exist` (77-89), two new tests, `run_tests` (158-161)
- Modify: `docs/game-dev/PROGRESS.md`: one entry inserted right under `## Log` (line 15), above `### 2026-10-09`

**Interfaces:** Consumes (T1): the flag strings in `bridge/multica_cli.py` `create_wakeup`.

- [ ] **Step 1: Write the failing contract tests** in `readme_test.sh`:
```sh
test_agent_instructions_wake_line() {
  assert_contains "$M/agent-instructions.md" "^- When you are woken because the sub-issues closed or the Run issue ended, read the Run issue's$" "#72 wake line"
}

test_readme_queue_section() {
  TESTS_RUN=$((TESTS_RUN + 1))
  q="$(grep -n -x -F -- "## Queue a run behind another" "$R" | sed -n 1p | cut -d: -f1)"
  c="$(grep -n -x -F -- "## Commands" "$R" | sed -n 1p | cut -d: -f1)"
  if [ -n "$q" ] && [ -n "$c" ] && [ "$q" -lt "$c" ]; then _pass "queue section before Commands"; else _fail "no queue section before Commands"; fi
  assert_contains "$R" "--until-issue-state done" "queue recipe: start after the prior is done"
  assert_contains "$R" "the bridge arms the end-of-run wake" "queue recipe: the bridge arms the wake"
  assert_contains "$R" "Do not assign a queued kickoff" "queue recipe: never assign"
}
```
Add both to `run_tests`. In `test_readme_flags_exist`, change the existence grep to `grep -q -F -- "$f" "$TMP/ih" "$TMP/uh" "$M/bridge/multica_cli.py"` and its comment to "…exists in a help output or in the CLI adapter that sends it…" (D5).

- [ ] **Step 2: Run, expect FAIL** (wake line and queue section missing): `cd "$S" && TMPDIR="$S" sh "$WT/integrations/multica/tests/readme_test.sh"`

- [ ] **Step 3: Edit the docs.**
  - `agent-instructions.md` line 12 becomes `- When you are woken because the sub-issues closed or the Run issue ended, read the Run issue's`. Lines 13-15 stay unchanged.
  - README new section (exact copy):
```markdown
## Queue a run behind another

To start a run only when another has finished, queue its kickoff instead of assigning it:

1. Create the kickoff issue for the new run as in step 2 of the nightly workflow, but leave it
   **unassigned**. Assigning an issue starts the agent at once. Do not assign a queued kickoff,
   not even later.
2. Add a wakeup rule that starts it when the prior issue is done. The prior issue is the one whose
   finishing should start this run, normally the kickoff issue of the run ahead. Get the agent id
   from `multica agent list`:
   `multica issue wakeup create <new> --until-issue <prior> --until-issue-state done --agent-id <agent id> --expires-in 336h --instruction "Start the overnight run this issue describes."`

When the queued run's Run issue exists, the bridge arms the end-of-run wake on the kickoff by
itself: a once-only rule that wakes the agent when the Run issue ends (done or cancelled), so it
can post the summary and do what the kickoff says comes after the run. The kickoff needs no extra
step. If the bridge cannot arm it, it posts the exact command to run by hand on the Run issue.
```
  - README 214-215 becomes: `- When the Run issue closes, the game-dev agent wakes once on the request issue and posts a short summary of the report. An agent-assigned request issue is woken by Multica when its last sub-issue closes. A queued (unassigned) one is woken by the rule the bridge arms (see [Queue a run behind another](#queue-a-run-behind-another)).`
  - Known risks 251-252 becomes two lines: `- Closing the Run issue of an agent-assigned request issue wakes the game-dev agent once on it. Reopening and closing it again wakes it again.` and `- A queued kickoff is woken by a once-only rule. Reopening and closing its Run issue does not wake it again.` Then one line per spec limit: (a) the bridge decides once, so assigning an armed kickoff later wakes it twice and unassigning a skipped one leaves nothing to wake it; the fix is one `multica issue wakeup delete` or `wakeup create`. (b) A queued kickoff is found only by the task's workdir name. If that misses, the Run issue goes top level and nothing is armed. (c) A runner that dies with no clean end never closes its Run issue, so the rule never fires (as for an assigned kickoff). (d) An agent created before this change keeps its old instructions until you update them, and the rule's own instruction says what to do anyway.
  - Read the new text against `test_readme_commands_match_code`: no backticked `/word` may appear, and every `--flag` must be one of `create_wakeup`'s.
  - PROGRESS entry (one self-contained block plus a blank line, inserted at line 16; no other line changes):
```markdown
### 2026-10-19 — A queued kickoff wakes when its run ends (#72)

- Incident: OMEG-92 (phoenix combat-vfx-library) was queued (unassigned, started by a wakeup
  rule), so nobody woke it when its Run issue OMEG-101 closed: no summary, PR or merge, and the
  queue stalled. It was fixed by hand with an `--until-issue-state ended` rule.
- The bridge now arms that rule itself (`ensure_end_wake`, right after `refresh`) when the
  request issue is not agent-assigned or the Run issue is not its sub-issue. It runs once per run
  (`end_wake` in the run state, saved as soon as the create returns) and skips an existing
  matching rule. A failure leaves one Run-issue note with the hand command.
- `create_wakeup` is the AC17 carve-out: the one unguarded write on a request issue. Comments and
  statuses stay forbidden.
- README: "Queue a run behind another" (the queue recipe); agent instructions cover the Run-issue wake.
- Spec `specs/2026-10-19-queued-kickoff-wake-design.md`; plan `plans/2026-10-19-queued-kickoff-wake.md`.
```

- [ ] **Step 4: Run, expect PASS:** `readme_test.sh`, then `install_test.sh` (install reads `agent-instructions.md`).

- [ ] **Step 5: Commit**
```bash
git add integrations/multica/agent-instructions.md integrations/multica/README.md integrations/multica/tests/readme_test.sh docs/game-dev/PROGRESS.md
git commit -m "docs: queue recipe and the end-of-run wake (#72)"
```

---

### Task 4: Final review, fix wave, full gate, PR

- [ ] **Step 1:** Cherry-pick T2 and T3 onto the story branch (they share no file). Run the whole integration gate once: `cd "$S" && TMPDIR="$S" sh "$WT/integrations/multica/tests/run.sh"` (background, one notification). Expect exit 0.
- [ ] **Step 2:** `sh tests/run_affected.sh --list` from the worktree. If it lists suites, take `<omega-ai>/.git/heavy-suite.lock` (mkdir plus an owner file; never break someone else's lock: hand back "blocked on heavy-suite.lock" instead), run `sh tests/run_all.sh` once, then release the lock.
- [ ] **Step 3:** A standalone whole-branch Opus review against the spec and this plan's Review Focus. Then one fix wave given the findings and the diff range. Re-review only per the Global Constraints rule.
- [ ] **Step 4:** Push and open the PR ("A queued kickoff wakes when its run ends (#72)", body `Closes #72`). After it merges: reinstall when no phoenix run is live; update omega phoenix's agent instructions on the board (spec Known limits); drop the worktree.

---

## Falsify log

What I checked against the code at 989c36f, and what changed because of it:

- **Test runner:** the suite is stdlib `unittest` (`run.sh` runs `unittest discover -s . -p 'test_*.py' -t .`), not pytest. `discover -s <abs> -t <abs>` from a scratch cwd with `TMPDIR` set ran `test_mirror_runs.py` green (58 tests, 99 s). `readme_test.sh` from a scratch cwd: 101 assertions, 0 failed.
- **`Cli.call`** appends `--output json` when `parse=True`, so the exact argv ends `"--output", "json"`. `rows(list)` returns the list. `_guard` compares case-insensitively. `classify`: `Invalid request: …` with exit 1 is `PermanentError`, `503 service unavailable` is `TransientError`, and `AuthError` is not a `PermanentError` subclass (it propagates).
- **stub dispatch:** `parse` matches 3-, then 2-, then 1-word commands against `SPEC`, so `("issue", "wakeup", "create")` works. A value flag's value is never itself parsed as a flag. `take_fault` with `apply` runs the handler, saves, then exits non-zero ("landed but failed"), which test 10 relies on. `contains` matches argv only, not stdin (comment text is stdin), so test 19 uses a bare count-1 fault.
- **stub `usage()`** is `Exit(2, err="Error: " + msg)`, which classifies as `PermanentError` (code 2, no auth, not-found or transient text). `fail(d, "not-found")` exits 4, which classifies as `NotFoundError`.
- **Conformance:** `test_stub_conformance` asserts that every `*.json` fixture has a CONFORMANCE entry and that the top-level key sets match. An empty list fails `shape`, hence the `add_wakeup` seed.
- **`make_run`** hard-codes `"agent_id": "ag-1"`. A keyword default keeps every existing caller unchanged.
- **`test_state.py:97-109`** asserts `set(st) == want` exactly: `end_wake` is added there.
- **`test_mirror_runs.py:197-207`:** the request is agent-assigned (`assignee=("agent", "ag-1")`), not unassigned as the spec says (D9). It still arms, and its existing assertions are unaffected (`calls("issue create")` matches argv prefix `["issue","create"]` only).
- **Other request-found tests** (`:118-166`, `:526-536`) have an agent-assigned request with the Run issue as its sub-issue, so they get `skipped` with one extra `issue get`. No test there counts `issue get` or forbids extra reads. `test_mirror_status.py`, `test_commands.py`, `test_service.py` and `test_end_to_end.py` set no `multica:` origin, so `request` is `none` and `ensure_end_wake` returns at once.
- **`test_link_deleted_only_after_resolution_saved`** patches `state.save_run` and only checks the order before `delete`. Extra saves are harmless.
- **Signatures:** `note(ctx, st, text)` posts through `post_comment(ctx, st, ident, text, parent=None, count_held=True)`. It swallows `PermanentError`/`ForbiddenWrite` and lets `TransientError` through (D4 relies on that). `ctx.notify(kind, text)`: the service dedupes per kind. `is_hands_off(row)` is agent or squad.
- **`poll_run` order:** resolve → `ensure_run_issue` → `refresh` (+retired check) → [new] → `reconcile` → `apply_events` → commands → `check_end_or_gone`. `refresh` fills `ctx.rows` from `issue list --property omega_run=<key>` by identifier; stub rows carry `parent_issue_id`. A run that ends in its first poll sets `ended` in `apply_events` and retires in `check_end_or_gone`, both after the new step. `state.retire` writes the in-memory state to `retired_dir/<key>.json` (test 16 reads it there).
- **`resolve_request`:** a found request needs `issue runs <REQ>` to have a row whose `id` is the task. That is also where the agent id is read, so "unknown agent" is a row with `agent_id: None` (test 13), not a missing row (that would resolve to `none`).
- **README contract:** `test_readme_flags_exist` would reject the recipe's Multica flags. Fixed by D5 (the check also reads `bridge/multica_cli.py`), which makes T3 depend on T1. `test_readme_commands_match_code` rejects any backticked `/word` that is not a bridge command, so the new text has none.
