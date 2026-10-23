# Push capability + hold reach Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A run that cannot push is refused before launch. A rejected push stops the story on the first
unit. The runner never counts work that is not on origin as progress. A hold sends a banner at start, and
a reminder (banner, event and bridge notice) at 25% left.
**Architecture:** Runner changes are in `studios/game-dev/bin/studio-overnight`: `push_check` (preflight),
`origin_check` (after each unit in `story_units`), and `notify_operator` plus the reminder (in `hold_wait`).
`overnight-lanes.sh` adds the Target half of `push_check` and its `story_branch` hook. The execute skill's
push rule becomes a stop. The bridge maps a new `hold_reminder` event onto #85's notice paths.
**Tech Stack:** POSIX sh (tests run under sh and dash), Python 3.9 bridge (unittest + stub `multica`).
**Spec:** `docs/game-dev/specs/2026-10-23-push-capability-and-hold-reach.md` (AC1–AC14)
**Branch:** `fix/overnight-push-gaps` (worktree `/Users/xin/game-dev/proj/omega-ai-push-gaps`), off
origin/main d5183d2. One issue per gap (filed before Task 1); one PR, **not merged** until every active
overnight run has ended.

Paths: `SO` = `studios/game-dev/bin/studio-overnight`, `OL` = `studios/game-dev/bin/overnight-lanes.sh`,
`EX` = `studios/game-dev/skills/execute/SKILL.md`, `OT` = `tests/overnight_test.sh`,
`LT` = `tests/overnight_lanes_test.sh`, `ST` = `tests/studio_test.sh`, `M` / `N` =
`integrations/multica/bridge/mirror.py` / `notice.py`, `MT` = `integrations/multica/tests/`,
`EV` = `docs/game-dev/overnight-events.md`. Line numbers are as of d5183d2. Find each one again with
`grep -n` before you edit.

**Run recipe.** This Mac (Mac.lan) is running a live overnight run from the main checkout. Never touch
`/Users/xin/game-dev/proj/omega-ai` (no checkout, pull, install or `.studio` writes there), and never run
`install.sh`. Run everything from a scratch cwd with its own TMPDIR. Keep the load down:
`TEST_JOBS=4` for `run_all.sh`. Run long suites in the background and wait for the notification.

```sh
W=/Users/xin/game-dev/proj/omega-ai-push-gaps; S=<scratchpad>/pg; mkdir -p "$S/tmp" && cd "$S" && export TMPDIR="$S/tmp"
TESTS_ONLY="<names>" sh "$W/tests/overnight_test.sh"          # also: dash "$W/tests/overnight_test.sh"
TESTS_ONLY="<names>" sh "$W/tests/overnight_lanes_test.sh"
TESTS_ONLY="<names>" sh "$W/tests/studio_test.sh"
( cd "$W/integrations/multica/tests" && /usr/bin/python3 -m unittest test_notice test_mirror_hold_notice -v )
sh "$W/integrations/multica/tests/run.sh"                       # whole bridge suite (not in run_all)
TEST_JOBS=4 sh "$W/tests/run_all.sh"                            # the merge gate
```

## Global Constraints

- Never weaken an existing check. An assertion that changes must assert the new, stricter rule.
- POSIX sh only in `bin/`. It must pass under dash. Use no `local`, and prefix helper variables per
  function (`_pc_*`, `_oc_*`, `_no_*`).
- Refusals go through `refuse` (stderr). Passing and warning lines of the push check go to **stdout**,
  printed by `preflight` right before `env_line`.
- Exact refusal text (AC1):
  `gh token for <host> lacks the workflow scope, and this repo has .github/workflows — a push that touches them is rejected. Fix: gh auth refresh -h <host> -s workflow`
- Exact stdout lines: `push: gh token for <host> has the workflow scope` ·
  `push: no .github/workflows — workflow scope not needed` · `push: origin is SSH — no token scope applies` ·
  `push: origin <url> is not https or ssh — not checked` ·
  `push: git does not push to <host> through gh's credential helper — cannot check the workflow scope` ·
  `push: cannot read gh token scopes for <host> — make sure the token may write workflows`.
- The URL that is checked is the **push** URL: `git remote get-url --push origin`.
- `gh auth status` keeps its refusal text `gh auth status failed — log in first`. For an https origin it
  becomes `gh auth status -h <host>`. For any other origin it stays plain `gh auth status`.
- Origin-check ending (exact form):
  `stop: push not on origin — <branch> <local sha7> vs origin <origin sha7|none>`, or
  `stop: push not on origin — <branch> fetch failed`.
- The notifier runs `sh -c "$STUDIO_OVERNIGHT_NOTIFY_CMD" notify "<text>"` when that variable is set.
  Otherwise it runs `terminal-notifier -title studio-overnight -message "<text>"` when that command exists.
  Otherwise, on Darwin only, it runs `osascript -e 'display notification "<text>" with title "studio-overnight"'`,
  with `\` removed and `"` changed to `'`. It is capped at 10 s (background process + kill). On a failure
  it writes one stderr line `notify failed: <why>`. It always returns 0.
- New event: `hold_reminder` with fields `story`, `until` (ISO UTC), `why`.
- Bridge: the reminder text is
  `story <B> still held — stops at <local> (<utc> UTC) unless resumed. Why: <why>`, and in single-plan
  runs `the run is still held — …`. A `studio: ` prefix goes on the Run-issue comment. On the kickoff it
  is `kickoff_text(...)`, which carries #85's marker and tail. The reminder raises **no** bridge banner,
  because the runner raises one.
- The test harnesses must never show a real banner. `OT` and `LT` export
  `STUDIO_OVERNIGHT_NOTIFY_CMD=': '` at setup, next to `STUDIO_OVERNIGHT_HOLD_MINUTES`.
- Commit only your own files: `git commit -m … -- <paths>`. Each message ends with the session's
  attribution lines.

## Review Focus

1. **Every existing single-plan test that isolates** (`ISO1`, `branch`, `legacybranch`, `inplace` in the
   `OT` stub) never pushes, so `origin_check` would stop it. The stub's `branch`, `legacybranch` and
   `inplace` actions must `git push -q -u origin <b>` (Task 2). The whole `OT` suite stays green under
   sh and dash. That is the test.
2. **`LT`'s `ahead` sync case** (`LT`:1708, `localcommit` after a progressing unit) would now hold A
   before the sync check. Adapt it so the sync check's `skipped=ahead` is still reached and asserted,
   with the unpushed commit made by a unit that makes no progress (the origin check runs only on
   progress or done). Also add `test_lanes_origin_check_localcommit_holds`, which pins the new behaviour
   on the old shape.
3. **The in-place default-branch case** (`§7 step 4`: branch == default branch, push nothing). It is
   never checked. Test: Task 2 `test_overnight_origin_check_skips_default_branch`.
4. **A resume after a push-not-on-origin hold**, once the operator has pushed. The next unit runs, and the
   story is not held again by the same check. Test: Task 2 `test_overnight_origin_check_resume_after_push`.
5. **A notifier that hangs.** The hold must still poll, resume and expire on time. Test: Task 4
   `test_overnight_notify_hang_capped`.

---

### Task 1: Gap 1 — `push_check` in the preflight

**Files:**
- Modify: `SO` `preflight()` (:581-689; replace the `gh auth status` line :624), and add `push_check`
  right after `env_line` (:693)
- Modify: `OL` `lanes_start` (:2076-2106): after `mf_check` and the `FAILED` exit, run the Target half
- Test: `OT` (gh stub :122; refusals near :430), `LT` (gh stub :395-412)

**Interfaces:**
- Produces: `push_check BASE…`. It reads `PUSH_HOST` (set by `push_host`) and checks each `BASE` ref
  `refs/remotes/origin/<BASE>` for `.github/workflows`. It refuses through `refuse`, or prints one stdout
  line. `push_host` sets `PUSH_HOST` and `PUSH_KIND` (`https|ssh|other`) from the push URL.
- `preflight` calls `push_host`, then the auth line, then `push_check "$DEFAULT_BRANCH"` (only when
  `DEFAULT_BRANCH` is set). `lanes_start` calls `push_check "$MF_TARGET"` after `mf_check`, but only when
  `MF_TARGET != DEFAULT_BRANCH`, then exits 2 on `FAILED`. It runs before `--check`, `--dry-run` and the
  real start alike.

- [ ] **Step 1: Extend both gh stubs.** `auth status [-h H]`: exit `${GH_STATUS:-0}`. Print to stdout
  `  - Token scopes: <$GH_SCOPES>` when `GH_SCOPES` is set, and print no scopes line when `GH_SCOPES=-`.
  Default: `'repo', 'workflow'`. Log argv to `$CALLS/gh.argv` (`OT`). `LT` already logs to `$GH/calls`.
- [ ] **Step 2: Write the failing tests** (`OT`). Each uses a fixture whose **push** URL is
  `https://github.com/t/t.git` (`git remote set-url --push origin …`; fetch stays local), with
  `git config credential.https://github.com.helper '!gh auth git-credential'`. A committed
  `.github/workflows/ci.yml` is pushed to origin/main where a test says so.
  - `test_overnight_push_check_refuses_without_workflow`: `GH_SCOPES="'repo'"` and workflows present.
    `start` exits 2, stderr contains `Fix: gh auth refresh -h github.com -s workflow`, there is no run dir
    under `.studio/reports`, and `calls` = 0. `start --dry-run` gives the same exit and the same line.
  - `test_overnight_push_check_ok_line`: the default scopes. `--dry-run` exits 0, and stdout contains
    `^push: gh token for github.com has the workflow scope$`.
  - `test_overnight_push_check_no_workflows`: `GH_SCOPES="'repo'"` and no workflows: exit 0, plus the
    "not needed" line.
  - `test_overnight_push_check_ssh`: push URL `git@github.com:t/t.git` and `GH_SCOPES="'repo'"`: exit 0,
    plus the SSH line. `gh.argv` has `auth status` with no `-h`.
  - `test_overnight_push_check_unknown_scopes`: `GH_SCOPES=-`: exit 0, plus the "cannot read" line.
  - `test_overnight_push_check_other_helper`: helper `osxkeychain` and `GH_SCOPES="'repo'"`: exit 0,
    plus the helper line.
  - The existing `r7` (`GH_STATUS=1` → "gh auth status") stays as it is, and still passes.
- [ ] **Step 3: Write the failing lanes test** (`LT`): `test_lanes_push_check_target_workflows`.
  Integration mode, workflows committed only on `origin/integration/<slug>`, https push URL, gh helper,
  `GH_SCOPES="'repo'"`. `start --dry-run M` exits 2 with the fix line, and `start --detach M` exits 2
  with no child (no lock).
- [ ] **Step 4: Run them; expect FAIL** (there is no push check yet).
- [ ] **Step 5: Implement `push_host`, `push_check`, the preflight auth line, and the `lanes_start` call.**
  Host parsing: `https://[user@]host[:port]/…` → host. `git@host:…` and `ssh://[user@]host/…` → ssh.
  Read the helper with `git -C "$START_DIR" config --get-urlmatch credential.helper "https://$PUSH_HOST"`
  and match it on `*"gh auth git-credential"*`. Read the scopes from `gh auth status -h "$PUSH_HOST" 2>&1`.
  Use the first `Token scopes:` line after the line holding `Active account: true`. When gh prints no
  account lines, use the first `Token scopes:` line. A value of `none` or no line means unknown.
  Workflows exist when `git -C "$START_DIR" cat-file -e "refs/remotes/origin/$b:.github/workflows"` is
  true for any `b`. Gate the scope read on that check: when no base has workflows, print the "not needed"
  line and skip gh.
- [ ] **Step 6: Run Task 1's tests and the existing preflight tests**
  (`test_overnight_preflight_refusals`, `test_overnight_preflight_all_failures`, `test_overnight_dry_run*`,
  the `LT` dry-run and detach tests). Under sh and dash: PASS.
- [ ] **Step 7: Commit** `feat(overnight): preflight refuses a run whose gh token cannot push workflows (#<gap1>)`.

### Task 2: Gap 2b — `origin_check`: work not on origin is not progress

**Files:**
- Modify: `SO`: a new `story_branch` hook (single plan: `state get branch`) and `origin_check`, both near
  `snapshot` (:769). `story_units` (:1594-1628): call the check after the new-Stop check (:1614) and
  before the done and progress rows (:1615, :1620). `holdable` (:930-942): add the ending.
- Modify: `OL`: redefine `story_branch` as `row_field "$CUR_ID" branch`, next to `hold_record` (:926).
- Test: `OT` stub (:50-67 `branch`/`legacybranch`/`inplace`); new tests in `OT` and `LT`.

**Interfaces:**
- Consumes: `snapshot`'s `FEATURE_DIR`, `SIG`, `SIG_STAGE`, `SIG_SHIPPED`, and `DEFAULT_BRANCH`.
- Produces: `origin_check`. It returns 0 when the check passes or does not apply. Otherwise it returns 1
  and sets `ORIGIN_WHY`, which is the text after `stop: `.

- [ ] **Step 1: Make the `OT` stub push like a real unit.** After `set branch` in `branch`, `legacybranch`
  and `inplace`, run `git push -q -u origin "$b"` from the new checkout (`inplace`: `feat`). Run the whole
  `OT` suite under sh: it stays green (nothing checks origin yet).
- [ ] **Step 2: Write the failing tests** (`OT`, holds on where noted). A new stub action `unpushed`
  makes an empty commit in the story worktree (`git -C "$(sh "$STUB_STATE_BIN" worktree)" commit -q
  --allow-empty -m unpushed`) and does not push. A new action `pushwt` pushes the worktree branch.
  - `test_overnight_origin_check_holds_unpushed` (holds_on 60): scenario `"$ISO1; unpushed"`. It is held
    (`wait_held`). `control/-.held` matches `^held stop: push not on origin — feat [0-9a-f]{7} vs origin [0-9a-f]{7} until `.
    The units.tsv outcome of unit 1 is `stop`, there is exactly 1 call, and there is no `progress` row.
  - `test_overnight_origin_check_ends_without_holds`: the same scenario with holds off. The report says
    `^Ending: stop: push not on origin — feat `, and there is 1 call.
  - `test_overnight_origin_check_resume_after_push` (holds_on 60): scenario `"$ISO1; unpushed"` then
    `"task 2/2; wtledger T2 complete c..d"`. After `wait_held`, the test pushes the worktree's branch
    itself (`git -C <wt> push -q origin feat`). Then `verb resume -`, and unit 2 runs with row
    `progress`. It is not held again by this check.
  - `test_overnight_origin_check_skips_default_branch`: a fixture where the stub works in place on
    `main`. A new stub action `onmain` runs `set branch main` with no push and makes an empty commit. The
    scenario is `"stage execute; onmain; task 1/2"` then `"task 2/2"`. Both rows are `progress`.
  - `test_overnight_origin_check_noprog_not_checked`: `"$ISO1"` then `"unpushed"` (no state change) then
    `"pushwt; task 2/2"`. Row 2 is `noprog` (a retry), and row 3 is `progress`.
- [ ] **Step 3: Write the failing lanes tests** (`LT`).
  - `test_lanes_push_rejected_first_unit_holds`. Install a `pre-receive` hook in the story's bare origin
    that rejects `refs/heads/<A's branch>` (`exit 1`). With holds on, the first unit of A ends `stop`, A
    is `held` (the record and the event), and no second unit of A is launched before the test stops the
    run.
  - `test_lanes_origin_check_localcommit_holds`: A's first unit is `auto; localcommit`, and A holds with
    `stop: push not on origin — `.
  - Adapt the `ahead` case (`LT`:1708) per Review Focus 2. It still asserts `skipped=ahead`.
- [ ] **Step 4: Run; expect FAIL.**
- [ ] **Step 5: Implement.** In `origin_check`, skip (return 0) when any of these hold: the branch is
  empty or `-`; the branch == `DEFAULT_BRANCH`; or `git -C "$FEATURE_DIR" symbolic-ref -q --short HEAD`
  != the branch. Otherwise fetch with `git_retry` when `command -v git_retry`, else plain
  `git -C "$FEATURE_DIR" fetch -q origin "$b"`. A failed fetch is `push not on origin — <b> fetch failed`.
  Then run `merge-base --is-ancestor HEAD refs/remotes/origin/<b>`; a missing ref fails. In `story_units`,
  call it only when the unit would be `done` or `progress`. On failure:
  `row "$n" "$_base$suffix" stop; ENDING="stop: $ORIGIN_WHY$UNIT_DENY_NOTE"; return 0`.
  In `holdable`, add the case `"stop: push not on origin — "*) isolated; return $? ;;` before the general
  `"stop: "*` case.
- [ ] **Step 6: Run** Task 2's tests, then all of `OT` and `LT`, under sh and dash: PASS.
- [ ] **Step 7: Commit** `feat(overnight): a unit whose work is not on origin ends held, not progress (#<gap2>)`.

### Task 3: Gap 2a — the execute skill stops on a rejected push

**Files:**
- Modify: `EX` §8 (:803, the sentence) and §7 step 4 (:656-658)
- Test: `ST` (:454 asserts the old sentence)

- [ ] **Step 1: Change the test first** (`ST`, the test holding :454). Replace the old assertion with
  these:
  - contains `` Under `--one`, a push that fails for any reason is a stop the first time ``;
  - contains `Stop: push rejected — <git's last error line>`;
  - contains `never writes a \`Ruling:\` about a push`;
  - does **not** contain `A rejected push is a \`Ruling:\` line, not a stop`;
  - §7 step 4's sentence contains `outside \`--one\``.
- [ ] **Step 2: Run; expect FAIL.**
- [ ] **Step 3: Edit `EX`.**
  - §8: replace the sentence with: ``Under `--one`, a push that fails for any reason is a stop the first
    time it happens: run `studio-state ledger "Stop: push rejected — <git's last error line>"`, commit it
    as stops are committed, do not retry the push, and end the turn. This unit and every later unit
    never writes a `Ruling:` about a push. An earlier `Ruling: push rejected` line is a record only; it
    is not a stop and not a reason to skip a push.``
  - §7 step 4: the "a rejected push … continue" bullet starts ``Outside `--one` (an interactive
    finish): …``, and gains a closing clause ``under `--one`, §8's push rule applies``.
  - §9, §11 and the sync-repair form: wherever "push" appears as a success step, add
    ``(a rejected push: §8's push rule)`` once per section.
- [ ] **Step 4: Run** `ST` (whole) under sh and dash: PASS.
- [ ] **Step 5: Commit** `fix(execute): a rejected push under --one is a Stop, never a Ruling (#<gap2>)`.

### Task 4: Gap 3 (runner) — `notify_operator`, the start banner and the reminder

**Files:**
- Modify: `SO`: add `notify_operator` after `iso_utc` (:865). In `hold_wait` (:967-987), add a banner after
  `hold_record`, and a reminder in the poll loop.
- Modify: `EV` (the event table :97-110): a `hold_reminder` row. If the doc has a lifecycle note on holds,
  add one line there too.
- Test: `OT` (holds tests :1737-1815); harness setup in `OT` and `LT` (Global Constraints).

**Interfaces:**
- Produces: `notify_operator TEXT` (always returns 0), and the event
  `hold_reminder story=<id> until=<iso> why=<why>`. Task 5 consumes that event.

- [ ] **Step 1: Write the failing tests** (`OT`). Use a logging notifier,
  `STUDIO_OVERNIGHT_NOTIFY_CMD='printf "%s\n" "$1" >> "$CALLS/notify"'`.
  - `test_overnight_hold_notifies_once`: holds_on 60, then `wait_held`, then `sleep 2`. `$CALLS/notify`
    has exactly 1 line, matching `^run held in overnight-[0-9-]*: stop: need art — until [0-9][0-9]:[0-9][0-9]$`.
    Then `verb resume -` before the reminder: the file still has 1 line, and there is no `hold_reminder`
    event.
  - `test_overnight_hold_reminder_before_expiry`: holds_on 8, which puts the reminder at ≤ 2 s left. Let
    it expire. The file has exactly 2 lines; line 2 matches
    `^run still held in overnight-[0-9-]* — stops at [0-9][0-9]:[0-9][0-9] unless resumed: stop: need art$`
    (the spec's reminder text).
    `events.jsonl` has exactly one `"event":"hold_reminder","story":"-"`, and it comes before the
    `stopped` story_state. The ending is unchanged
    (`stop: need art (held 0h0m, no reply)`).
  - `test_overnight_notify_failure_not_fatal`: `STUDIO_OVERNIGHT_NOTIFY_CMD='exit 1'`, holds_on 2. The
    run ends exactly as `test_overnight_hold_deadline` does, and stderr has
    `^studio-overnight: notify failed: exit 1$`.
  - `test_overnight_notify_hang_capped`: `STUDIO_OVERNIGHT_NOTIFY_CMD='sleep 30'`, holds_on 2. The run
    ends within 30 s with the same ending, and stderr has `notify failed: timed out`.
- [ ] **Step 2: Run; expect FAIL.**
- [ ] **Step 3: Implement.** The text uses `CUR_ID` or `run` as `who`, the basename of `RUN_DIR` as the
  run, and `hhmm_local` for the time. Reminder point: `_hw_rm=$(( _hw_dl - HOLD_SECS / 4 ))`. Fire it
  once (a flag) on the first poll with `now >= _hw_rm` and `now < _hw_dl`. The cap: run the command in
  the background, poll every 0.2 s for up to 10 s (or `STUDIO_OVERNIGHT_NOTIFY_SECONDS`, a test knob),
  then `kill` it. Its stdout and stderr go to /dev/null. Add the `export STUDIO_OVERNIGHT_NOTIFY_CMD=': '`
  harness default in `OT` and `LT`.
- [ ] **Step 4: Run** Task 4's tests plus every `hold` test in `OT` and `LT`, under sh and dash: PASS.
- [ ] **Step 5: Commit** `feat(overnight): a hold raises a banner at start and a reminder at 25% left (#<gap3>)`.

### Task 5: Gap 3 (bridge) — `hold_reminder` reaches the Run and kickoff issues

**Files:**
- Modify: `N`: `reminder_body(story, why, until) -> str`
- Modify: `M` `event_writes` (:40-100): an `if e == "hold_reminder":` branch that returns #85's
  Run-comment and kickoff write kinds. Use the same tuple kinds `notice_writes` uses for a hold, so
  the `pending` once-per-event rule and `Cli.add_notice` apply unchanged. Do not change the status, the
  held set or the banner.
- Test: `MT/test_notice.py`, `MT/test_mirror_hold_notice.py`

**Interfaces:**
- Consumes: Task 4's event. Use `notice.until_line`'s local and UTC formatting rule for `<local>` and
  `<utc>`.

- [ ] **Step 1: Write the failing tests.**
  - `test_notice.py::test_reminder_body_story_and_single`: covers the exact texts in Global
    Constraints, plus the unparsable `until` (`stops at ?` → the raw value, as `until_line` does).
  - `test_mirror_hold_notice.py::test_reminder_posts_run_and_kickoff_once`: a manifest run, B held, then
    `hold_reminder` B. Exactly one Run-issue comment starting `studio: story B still held — stops at `,
    and one kickoff comment starting `studio: [notify only] story B still held`. No status call and no
    banner. A re-poll, and a fresh `Ctx` on the same state, repeat nothing.
  - `test_reminder_no_request_issue`: posts nothing on a kickoff, and nothing fails.
  - `test_reminder_single_plan`: the Run issue gets `studio: the run is still held — …`, and the
    kickoff its notify-only form.
- [ ] **Step 2: Run; expect FAIL.**
- [ ] **Step 3: Implement** the branch and the `reminder_body` text builder.
- [ ] **Step 4: Run** `sh "$W/integrations/multica/tests/run.sh"`: PASS.
- [ ] **Step 5: Commit** `feat(multica): a hold reminder reaches the Run and kickoff issues (#<gap3>)`.

### Task 6: Docs and the full gate

**Files:** `docs/game-dev/PROGRESS.md` (a new top log entry), `integrations/multica/README.md` (one line
on the reminder next to #85's notices), `studios/game-dev/bin/studio-overnight` usage text (if it lists
preflight checks; `grep -n 'gh auth' SO`).

- [ ] **Step 1:** PROGRESS entry `### 2026-10-23 — A run that cannot push stops at once; holds remind (#…)`.
  It covers the incident in 3 bullets, the three fixes, the limits (no @-mention; banner duplicates the
  bridge's on a Mac with both), and a closing bullet: `Install is pending: merge and reinstall once every
  active overnight run has ended.` Add one note bullet: `Kickoff texts: resolve the project path on the
  target machine (OMEG-118 carried /Users/xinli/... from the other laptop) — follow-up.`
- [ ] **Step 2:** `TEST_JOBS=4 sh "$W/tests/run_all.sh"` and `sh "$W/integrations/multica/tests/run.sh"`:
  both green. Paste the summary lines into the PR.
- [ ] **Step 3: Commit** `docs: push capability and hold reach (#…)`.
