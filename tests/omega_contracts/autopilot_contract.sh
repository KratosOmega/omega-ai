#!/bin/sh
# Text contract for shared/omega/skills/autopilot/SKILL.md. Sourced by
# tests/omega_test.sh (test_skill_contracts); defines test_autopilot_contract.
test_autopilot_contract() {
  S="$REPO_ROOT/shared/omega/skills/autopilot/SKILL.md"
  assert_contains "$S" "This mode changes how work is scheduled, saved, merged or stopped" "autopilot carries the precedence contract"
  assert_contains "$S" "[Nn]ever merge" "autopilot never merges"
  assert_contains "$S" "AskUserQuestion. is never called" "autopilot forbids AskUserQuestion in phase 2"
  assert_contains "$S" "cost if wrong" "autopilot logs rulings with their cost if wrong"
  assert_contains "$S" "## Decisions" "autopilot records the question sweep in the plan"
  assert_contains "$S" "gh auth status" "autopilot's readiness checklist checks gh"
  assert_contains "$S" "KAN-" "autopilot detects a Jira story from the branch"
  assert_contains "$S" "already approved and committed" "autopilot skips design and plan when both are approved and committed"
  assert_contains "$S" "no second PR is opened" "autopilot opens no second PR when the invoking skill opened one"
  assert_contains "$S" "studio-overnight start --dry-run" "the readiness checklist runs the runner's preflight"
  assert_contains "$S" "studio-overnight start" "phase 1 ends by printing the runner command"
  assert_contains "$S" "studio-overnight status" "the user is told how to watch the run"
  assert_contains "$S" '`studio-overnight status` (from any directory) or `studio-overnight watch`' "the user is told status works anywhere and watch repeats it"
  assert_contains "$S" "studio-overnight stop" "off stops a live run"
  assert_contains "$S" "source=env" "phase 2 applies under the runner's environment"
  assert_contains "$S" 'Stop: <reason>' "a hard stop under the runner writes a Stop: line"
  assert_contains "$S" "report.md" "the user is told where the morning report lands"
  assert_contains "$S" "omega-mode clear autopilot" "off and the session-mode disarm clear the mode"
  assert_contains "$S" "omega-mode set autopilot" "outside a studio the mode is set in-session"
  assert_contains "$S" "one unit, then end" "the --one red flag"
  assert_not_contains "$S" "omega-""caffeine" "no keep-awake tool remains"
  assert_not_contains "$S" "Cron""Create" "no heartbeat is armed"
  assert_not_contains "$S" "Cron""Delete" "no heartbeat is deleted"
  assert_not_contains "$S" "heartbeat" "no heartbeat at all"
  assert_not_contains "$S" "on the feature branch, in a worktree" "the worktree readiness line is replaced by the dry run"
  # Outside a studio the checklist has six lines, as the pressure doc's B
  # criterion counts: the worktree and plan lines are two bullets.
  assert_contains "$S" "^   - outside a studio: the feature branch is checked out in a worktree" "outside a studio: the worktree line"
  assert_contains "$S" "^   - outside a studio: the plan is approved and committed" "outside a studio: the plan line, its own bullet"
  assert_contains "$S" "phase 1 does not run" "a runner-started session (OMEGA_AUTOPILOT=1) never runs phase 1's sweep"
  # Task 17 — autopilot in a studio (AC1, AC2, AC3, AC22, AC24; milestone
  # criterion 3).
  assert_contains "$S" 'command -v studio-state' "one written definition of in a studio"
  assert_eq 1 "$(grep -c 'command -v studio-state' "$S")" "the definition is written once (AC2)"
  assert_contains "$S" 'studio-state get stage. exits 0' "the definition's second half"
  assert_eq 1 "$([ "$(grep -c 'in a studio (see' "$S")" -ge 3 ] && echo 1 || echo 0)" "branches cite the definition"
  assert_contains "$S" 'direct or integration' "phase 1 asks the run mode"
  assert_contains "$S" 'direct (listed first, marked Recommended)' "direct is the recommended mode"
  assert_contains "$S" 'without one, list integration first and mark it Recommended' "no merge_command: integration is recommended"
  assert_contains "$S" '\*\*dependencies\*\*' "phase 1 asks the dependencies"
  assert_contains "$S" '\*\*maximize parallelism\*\* (listed first, marked Recommended)' "maximize parallelism is recommended"
  assert_contains "$S" '\*\*chain\*\*: each story depends on the row before it' "chain is the other option"
  assert_contains "$S" 'each row after the first depends on exactly one row, the one directly above it' "the one-chain rule matches the runner's chains"
  assert_contains "$S" 'chain: each row after the first depends on the row before it' "chain proposes the row before"
  assert_contains "$S" 'maximize parallelism: the smallest set' "maximize proposes the smallest dependency set"
  assert_contains "$S" 'how many lanes' "and the lane count"
  assert_contains "$S" 'list .0. first, marked Recommended, under maximize parallelism' "one lane per chain is recommended under maximize"
  assert_contains "$S" 'one .AskUserQuestion. with three questions' "mode, dependencies and lanes in one question"
  assert_contains "$S" 'Overlap check, before the first seed' "plans are checked for overlapping files before seeding"
  assert_contains "$S" 'add a dependency' "an overlap can add a dependency"
  assert_contains "$S" 'keep parallel' "or keep the stories parallel"
  assert_contains "$S" '\*\*add a backfill story\*\*' "step 3 offers a backfill story when one lane is in effect"
  assert_contains "$S" '\*\*run as is\*\*' "or running as is"
  _a="$(grep -n -F -m1 -- '**add a backfill story**' "$S" | cut -d: -f1)"
  _b="$(grep -n -F -m1 -- 'Check that the run worktree has `.studio/run` before the first seed' "$S" | cut -d: -f1)"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -n "$_a" ] && [ -n "$_b" ] && [ "$_a" -lt "$_b" ]; then _pass "the backfill offer comes before the first seed"
  else _fail "the backfill offer comes before the first seed ($_a, $_b)"; fi
  assert_contains "$S" 'Mode: direct ' "the manifest template defaults to direct"
  assert_contains "$S" 'docs/runs/<slug>.md' "the run manifest"
  assert_contains "$S" '> \.studio/run`' "the pointer (anchored: not .studio/runs/)"
  assert_contains "$S" '.studio/runs/<slug>/done' "a done run's pointer is ignored"
  assert_not_contains "$S" 'switch this checkout to' "D1: the checkout is never switched to the default branch"
  assert_contains "$S" 'studio-overnight next' "the planning loop is driven by next"
  assert_contains "$S" 'set stage plan' "STATE.md is set before a plan of an approved spec"
  assert_contains "$S" 'Print .\/clear., then the command' "one stage per session"
  assert_contains "$S" 'reset --keep-ledger' "the spec ledger survives seeding"
  assert_contains "$S" 'check --rebuild' "a half-done story is rebuilt from its ledger (AC24)"
  assert_contains "$S" 'chore(studio): ledger keyed by story' "the spec-slug ledger is moved to the story id"
  assert_contains "$S" "today's date" "seeded lines are re-ledgered (D16)"
  assert_contains "$S" 'origin/<default>:refs/heads/integration/<slug>' "integration creates its branch on origin from the default branch"
  assert_not_contains "$S" 'origin/main:' "the default branch is not hard-coded"
  # Task 17 fix round.
  assert_contains "$S" 'the file the runner.s preflight reads' "seeded ledger lines go to the phase-1 checkout (C1)"
  assert_contains "$S" 'In that worktree, only' "the worktree gets only the move, branch, stage and rebuild (C1)"
  assert_not_contains "$S" 'a half-done one in its worktree' "no seeding ledger lines in the story worktree (C1)"
  assert_not_contains "$S" 'a run is live: stop' "D1: a live run no longer stops discovery"
  assert_contains "$S" '.studio/runs/<slug>/. exists, the run was started: skip to step 4' "a started run is not re-seeded (I1)"
  assert_contains "$S" 'when .STUDIO_RUN. is unset, the base is per .omega:local-merge. §3' "the non-studio PR base is unchanged (I2)"
  assert_contains "$S" 'python3 -c' "max_lanes is merged into config.json (I3)"
  assert_contains "$S" 'every other key is kept' "the merge preserves merge_command (I3)"
  assert_contains "$S" 'an integer from 0 to 8' "max_lanes uses the runner's range (I3)"
  # #71 T5: the autopilot merges the three short-lane keys.
  assert_contains "$S" 'one .AskUserQuestion. with three questions' "the question keeps its three questions (#71)"
  assert_contains "$S" 'four for a .godot4. project' "a godot4 project gets a fourth question (#71)"
  assert_contains "$S" 'short lane' "the short-lane question is named (#71)"
  assert_contains "$S" '"gate_short_lane": "on"' "on writes gate_short_lane (#71)"
  assert_contains "$S" '"user_dir": "per-worktree"' "on writes user_dir (#71)"
  assert_contains "$S" '"test_engine_args": "--fixed-fps 60"' "on writes test_engine_args (#71)"
  assert_contains "$S" "' <n> <on|off>" "the one-liner takes the lane count and on|off (#71)"
  assert_contains "$S" 'studio-vitest <file>' "the targeted vitest verb is a constraint (#71)"
  assert_contains "$S" 'tsc as `studio-tsc`' "the tsc verb is a constraint (#71)"
  assert_not_contains "$S" 'cd <node dir> && studio-gate vitest' "no cd chain into the gate (#71)"
  if python3 -c 'import json' >/dev/null 2>&1; then
    _pf="$TMP/ap-fx"; rm -rf "$_pf"; mkdir -p "$_pf/.studio"
    _prog="$(sed -n "s/.*python3 -c '\([^']*\)' <n> <on|off>.*/\1/p" "$S" | head -n 1)"
    if [ -n "$_prog" ]; then _pass "the one-liner program is extractable (#71)"; else _fail "the one-liner program is extractable (#71)"; fi
    printf '%s\n' '{"merge_command": "./merge.sh", "overnight": {"session_minutes": 90}}' > "$_pf/.studio/config.json"
    ( cd "$_pf" && python3 -c "$_prog" 2 on )
    cp "$_pf/.studio/config.json" "$_pf/a.json"
    _got="$(python3 -c 'import json,sys; c=json.load(open(sys.argv[1])); o=c["overnight"]; print(c["merge_command"], o["session_minutes"], o["max_lanes"], c["test_engine_args"], c["user_dir"], c["gate_short_lane"])' "$_pf/a.json")"
    assert_eq "./merge.sh 90 2 --fixed-fps 60 per-worktree on" "$_got" "(a) on merges the keys and keeps the rest (#71)"
    ( cd "$_pf" && python3 -c "$_prog" 2 on )
    if cmp -s "$_pf/a.json" "$_pf/.studio/config.json"; then _pass "(b) on twice is byte-identical (#71)"; else _fail "(b) on twice is byte-identical (#71)"; fi
    printf '%s\n' '{"merge_command": "./merge.sh", "overnight": {"session_minutes": 90}}' > "$_pf/.studio/config.json"
    ( cd "$_pf" && python3 -c "$_prog" 2 off )
    cp "$_pf/.studio/config.json" "$_pf/c.json"
    ( cd "$_pf" && python3 -c "$_prog" 2 off )
    if cmp -s "$_pf/c.json" "$_pf/.studio/config.json"; then _pass "(c) off twice is byte-identical (#71)"; else _fail "(c) off twice is byte-identical (#71)"; fi
    _got="$(python3 -c 'import json,sys; c=json.load(open(sys.argv[1])); print(sorted(k for k in ("test_engine_args","user_dir","gate_short_lane") if k in c), c["overnight"]["max_lanes"])' "$_pf/c.json")"
    assert_eq "[] 2" "$_got" "(c) off writes none of the three keys (#71)"
    # A5: off equals the pre-#71 one-liner's output on the same input.
    printf '%s\n' '{"merge_command": "./merge.sh", "overnight": {"session_minutes": 90}}' > "$_pf/.studio/config.json"
    ( cd "$_pf" && python3 -c 'import json,sys; p=".studio/config.json"; c=json.load(open(p)); c.setdefault("overnight", {})["max_lanes"]=int(sys.argv[1]); open(p,"w").write(json.dumps(c, indent=2)+"\n")' 2 )
    if cmp -s "$_pf/c.json" "$_pf/.studio/config.json"; then _pass "(c) off equals the pre-#71 one-liner's output (#71 A5)"; else _fail "(c) off equals the pre-#71 one-liner's output (#71 A5)"; fi
    # M9: on keeps values the project already has (setdefault), and adds the rest.
    printf '%s\n' '{"test_engine_args": "--fixed-fps 30", "user_dir": "shared"}' > "$_pf/.studio/config.json"
    ( cd "$_pf" && python3 -c "$_prog" 2 on )
    _got="$(python3 -c 'import json,sys; c=json.load(open(sys.argv[1])); print(c["test_engine_args"], c["user_dir"], c["gate_short_lane"], c["overnight"]["max_lanes"])' "$_pf/.studio/config.json")"
    assert_eq "--fixed-fps 30 shared on 2" "$_got" "(e) on keeps existing test_engine_args and user_dir (#71 M9)"
    rm -f "$_pf/.studio/config.json"
    ( cd "$_pf" && python3 -c "$_prog" 0 on )
    _got="$(python3 -c 'import json,sys; c=json.load(open(sys.argv[1])); print(c["overnight"]["max_lanes"], c["gate_short_lane"], c["user_dir"], c["test_engine_args"])' "$_pf/.studio/config.json")"
    assert_eq "0 on per-worktree --fixed-fps 60" "$_got" "(d) no file and 0 on writes the file and the keys (#71)"
  else
    _fail "python3 is needed for the autopilot merge"
  fi
  assert_contains "$S" 'git add docs/runs/<slug>.md .studio/config.json' "config.json is committed on run/<slug> (I3)"
  assert_contains "$S" 'When .next. exits non-zero' "a failing next stops the loop"
  assert_contains "$S" 'git worktree add <path> run/<slug>. when the branch exists' "an existing run branch gets a worktree"
  # Task 17 fix round 3: the story file (STATE_ROOT, shared) carries N, so a worktree rebuild needs no plan.
  assert_contains "$S" 'plan=.); .set task 0/<N>.' "every story is seeded with task 0/N in the phase-1 checkout"
  assert_contains "$S" "awk '/^## Backlog/ { exit } /^### Task \\[0-9\\]/ { n++ } END { print n + 0 }' <plan>" "N counts only the tasks above ## Backlog"
  assert_not_contains "$S" "grep -c '^### Task" "N is never a bare grep -c (it would count backlog tasks)"
  assert_contains "$S" 'takes .N. from the story file and never needs the plan' "a worktree rebuild reads N, not the plan file"
  assert_contains "$S" 'Write it only in the run worktree' "max_lanes is written in the run worktree"
  assert_contains "$S" 'the lane count' "the run worktree step writes the lane count"
  assert_contains "$S" 'start --detach' "autopilot can start the run detached"
  assert_contains "$S" "start <manifest>" "the printed command names the manifest"
  assert_contains "$S" 'never retries in this session' "a refused detach prints the command"
  assert_contains "$S" 'lid open' "keep the laptop on power with the lid open"
  assert_contains "$S" 'no session-mode .autopilot. is ever set' "no session mode in a studio"
  assert_contains "$S" 'no keep-awake' "no keep-awake in a studio"
  assert_contains "$S" 'nothing executes stories in this session' "no in-session execution in a studio"
  assert_contains "$S" 'drop the story' "does-not-fit options"
  assert_contains "$S" 'A story without a plan is never a stop' "a missing plan enters the planning loop"
  assert_contains "$S" 'no session merges anything in any run mode' "the merge rule"
  assert_contains "$S" 'nothing is merged into .main.' "the merge rule names main"
  assert_contains "$S" 'the runner lands' "the runner lands (AC22)"
  assert_eq 0 "$(grep -i 'never merge' "$S" | grep -vc 'main')" "every never-merge names main (AC22)"
  # Removed: the in-studio planning inside autopilot's own session, the rule
  # that story PRs target the integration branch, and the single-plan
  # studio hand-off.
  assert_not_contains "$S" 'in the game studio' "no studio stage runs inside autopilot's session"
  assert_not_contains "$S" 'local-merge. §3 (the integration branch' "no story PR targets the integration branch"
  assert_not_contains "$S" 'commit only: the run.s first task unit pushes' "the single-plan studio hand-off is gone"
  D="$REPO_ROOT/docs/omega/pressure/autopilot.md"
  assert_contains "$D" "checklist of six lines" "the pressure doc counts six checklist lines"
  assert_contains "$D" "^\*2026-09-15: the arm-step criterion" "the 2026-09-15 dated note is kept (D10)"
  assert_contains "$D" "^\*2026-10-01: the hand-off criterion" "the 2026-10-01 note follows it"
  assert_contains "$D" 'direct or integration' "the scenario expects the mode question"
  assert_contains "$D" 'maximize parallelism' "and the dependencies question"
  assert_contains "$D" 'how many lanes' "and the lane count"
  assert_contains "$D" 'docs/runs/<slug>.md' "and the manifest"
  assert_contains "$D" "^\*2026-10-02: the studio criterion" "the 2026-10-02 note follows"
  # Adopt branch (#35): the source-plan question, the gap check, conversion, seed, sync.
  for lit in 'source plan' 'source spec' 'git ls-files --error-unmatch' 'STUDIO_STORY=<id> studio-state init' \
    'source <plan> spec <spec or ->' \
    'studio-adopt inspect <id> --branch <Branch> --plan <original>' 'gap check' \
    '`adopt` or `plan: <gaps>`' 'verdict adopt' 'verdict plan' 'at most 4 stories per question' \
    'adopted <original> -> <new plan>' "tasks 1..k keep the original's titles and boundaries" \
    'never edits the original' 'Source: <original plan path>' 'Status: Draft (awaiting approval)' \
    '1:1 with the original' '`<original>:L<a>-<b>`' 'pre-flight conflict scan' \
    'studio-gate <who> -- <cmd>' 'docs/game-dev/adopted/<id>/' '\*\*check the built work?\*\*' 'check requested' \
    'studio-adopt seed <id>' "after step 3.2's re-key and before" 'studio-adopt sync <id>' 'superpowers 6.4.1'; do
    assert_contains "$S" "$lit" "autopilot adopt branch: $lit"
  done
  test_autopilot_adopt_order
  test_autopilot_adopt_ready
  test_autopilot_run_worktree
  test_autopilot_story_ids
  test_autopilot_discovery_lists_runs
  test_autopilot_start_from_run_worktree
  test_autopilot_jira_acli
  test_autopilot_off_stop_rule
  test_autopilot_adopt_slug_forms
  # AC1: the manifest commit carries every story's ledger; AC3: step 3 ledgers `adopted` before seeding.
  _a="$(grep -n -F -m1 -- 'git add docs/runs/<slug>.md .studio/config.json .studio/ledger/<id>.md …`, then, only when it succeeded, `git commit -m "docs(run): <slug> manifest"' "$S" | cut -d: -f1)"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -n "$_a" ]; then _pass "manifest commit adds the ledgers"; else _fail "manifest commit adds the ledgers"; fi
  _a="$(grep -n -F -m1 -- 'studio-state ledger "adopted <original> -> <new plan>"' "$S" | cut -d: -f1)"
  _b="$(grep -n -F -m1 -- 'Each story, not-started and half-done alike' "$S" | cut -d: -f1)"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -n "$_a" ] && [ -n "$_b" ] && [ "$_a" -lt "$_b" ]; then _pass "step 3 ledgers adopted before seeding"
  else _fail "step 3 ledgers adopted before seeding ($_a, $_b)"; fi
}

# The AC5 order (spec): the five phrases appear in the skill in this order.
# #50: the run worktree's pointer is re-created, adopted lines and seeds come
# from the run worktree, a failed seed stops, readiness names the new checks.
test_autopilot_adopt_ready() {
  S="$REPO_ROOT/shared/omega/skills/autopilot/SKILL.md"
  for lit in 'a run worktree with no `.studio/run` whose `docs/runs/<slug>.md` is committed' \
    'rewrite the missing pointer first' \
    'ledgered from the run worktree, never from the main checkout' \
    'the run worktree has `.studio/run` before the first seed' \
    'A failed seed stops here' \
    'never run `studio-state check --rebuild`, `next` or the start after it' \
    "the start checkout's \`.studio/run\`" \
    'every adopted story with a branch seeded on it'; do
    assert_contains "$S" "$lit" "autopilot #50: $lit"
  done
}

test_autopilot_adopt_order() {
  S="$REPO_ROOT/shared/omega/skills/autopilot/SKILL.md"
  _prev=0
  for _ph in '`studio-state set spec <spec>`, where `<spec>` is the source spec' \
    'Spec and Plan cells are set to' \
    'so `next_match` and `Docs:` see the plan' \
    '`Decisions swept <id>` after asking' \
    '`adopted <original> -> <converted plan>`'; do
    _n="$(grep -n -F -m1 -- "$_ph" "$S" | cut -d: -f1)"
    [ -n "$_n" ] || _n=0
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$_n" -gt "$_prev" ]; then _pass "adopt order: $_ph"; else _fail "adopt order: $_ph (line $_n after $_prev)"; fi
    _prev=$_n
  done
  # I1: seed needs the pointer's branch, so it runs after `set branch` and before the rebuild
  # (all three sit in step 3.3, so compare offsets inside that line).
  _l="$(grep -F -m1 -- 'In that worktree, only' "$S")"
  _b="$(printf '%s' "$_l" | awk '{ print index($0, "`set branch <Branch>`") }')"
  _s="$(printf '%s' "$_l" | awk '{ print index($0, "`studio-adopt seed <id>`") }')"
  _r="$(printf '%s' "$_l" | awk '{ print index($0, "then `studio-state check --rebuild`") }')"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "$_b" -gt 0 ] && [ "$_s" -gt "$_b" ] && [ "$_r" -gt "$_s" ]; then
    _pass "adopt order: set branch, then seed, then check --rebuild"
  else _fail "adopt order: set branch ($_b), seed ($_s), check --rebuild ($_r)"; fi
}

# #56: a story id once used is not handed out again: the slug and a fetch
# come before the story list; the default id; check-id on every id.
test_autopilot_story_ids() {
  S="$REPO_ROOT/shared/omega/skills/autopilot/SKILL.md"
  assert_contains "$S" 'studio-overnight check-id <id> --ticket <t> --slug <slug> --plan - --branch <Branch>' "the story list checks every id, with its branch"
  assert_contains "$S" 'Exit 2: stop and print its output' "check-id's exit 2 stops: a usage or environment problem"
  assert_contains "$S" 'not a taken id' "exit 2 is not a taken id"
  assert_contains "$S" 'the slug must match `\^\[A-Za-z0-9\._-\]+\$`' "the slug's pattern"
  assert_contains "$S" "a suggestion that is already another row's id in this list is not used" "a suggestion never duplicates a row being built"
  assert_contains "$S" "the plan's \`Story:\` line" "a rename touches the plan's Story: line"
  assert_contains "$S" '`git mv .studio/ledger/<id>.md .studio/ledger/<new id>.md`' "a rename moves the ledger"
  assert_contains "$S" 'the story file `<root>/.studio/stories/<id>.md` moves to `<new id>.md`' "and the story file"
  assert_contains "$S" 'otherwise `<slug>-S<n>`' "the default id when the ticket does not fit"
  assert_contains "$S" '`KAN-1541-1`, `KAN-1541-2`' "rows sharing a ticket"
  assert_contains "$S" 'a story id `check-id` refuses' "a failing next names a taken id"
  _f="$(grep -n -F -m1 -- '**The slug and a fetch, before the story list.**' "$S" | cut -d: -f1)"
  _g="$(grep -n -F -m1 -- 'Then run `git fetch origin`, so the story ids' "$S" | cut -d: -f1)"
  _l="$(grep -n -F -m1 -- 'Then ask the story list' "$S" | cut -d: -f1)"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -n "$_f" ] && [ -n "$_g" ] && [ -n "$_l" ] && [ "$_f" -lt "$_l" ] && [ "$_g" -lt "$_l" ]; then
    _pass "the slug check and the fetch come before the story list"
  else _fail "the slug check and the fetch come before the story list ($_f, $_g, $_l)"; fi
  assert_not_contains "$S" '`git fetch origin`, then `git worktree add' "the run worktree step no longer fetches after the story list"
}

# #39 AC15: a new run gets its own run worktree; the main checkout is never switched.
test_autopilot_run_worktree() {
  S="$REPO_ROOT/shared/omega/skills/autopilot/SKILL.md"
  assert_contains "$S" 'git worktree add --no-track -b run/<slug> <root>/.claude/worktrees/run-<slug> origin/<default>' "run worktree is created from origin/<default>"
  assert_contains "$S" 'git worktree add <path> run/<slug>' "an existing run branch gets a worktree"
  assert_contains "$S" 'Enter the feature checkout' "the run worktree is entered by execute's procedure"
  assert_contains "$S" 'git rev-parse --show-toplevel' "the entered worktree is checked"
  assert_contains "$S" 'studio-state init --local' "the run worktree is initialised locally"
  assert_contains "$S" 'worktree_setup' "the setup hook runs in the run worktree"
  assert_contains "$S" "The main checkout's branch is never switched" "the main checkout is untouched"
  assert_contains "$S" 'not `off`, not all digits' "slug rules: off and all-digit"
  assert_contains "$S" 'all digits' "slug rule: all-digit"
  assert_contains "$S" '.studio/runs/<slug>.$(date -u +%Y%m%dT%H%M%SZ)' "a done record is archived under a utc timestamp"
  assert_contains "$S" 'an id or branch that another run uses' "the story list refuses ids and branches of other runs (AC8)"
}

# #39 AC16: discovery lists runs.
test_autopilot_discovery_lists_runs() {
  S="$REPO_ROOT/shared/omega/skills/autopilot/SKILL.md"
  assert_contains "$S" 'runs being planned' "discovery lists runs being planned"
  assert_contains "$S" 'started runs' "discovery lists started runs"
  assert_contains "$S" 'branch refs/heads/run/' "planned runs come from the run worktrees"
  assert_contains "$S" 'each run, and .new run.' "one question with each run and new run"
  assert_contains "$S" '/omega:autopilot <slug>. skips the question' "a slug skips the question"
  assert_contains "$S" 'A live run never stops discovery' "a live run never stops discovery"
}

# #39 AC15/AC18: the run starts from its run worktree.
test_autopilot_start_from_run_worktree() {
  S="$REPO_ROOT/shared/omega/skills/autopilot/SKILL.md"
  assert_contains "$S" "cd '<run worktree>' && '<abs>' start --detach <manifest>" "the detached start runs from the run worktree"
  assert_contains "$S" "cd '<run worktree>' && '<abs>' start <manifest>" "the printed command runs from the run worktree"
  assert_contains "$S" 'baseline test run is green.*run worktree.*worktree_setup' "the baseline test runs in the run worktree after setup"
  # Automatic run cleanup (2026-10-27): the runner, never a session, cleans up once every story is confirmed merged.
  assert_not_contains "$S" 'nothing removes the worktree automatically' "the worktree is no longer left for the user"
  assert_contains "$S" 'the runner itself, never a session, closes the run' "the runner cleans up, not a session"
  assert_contains "$S" 'once every story is confirmed merged into its target (against origin' "cleanup waits for every story confirmed merged against origin"
  assert_contains "$S" '`run/<slug>` after its tip is tagged `run-archive/<slug>-<tip12>`' "run/<slug> is archived as a tag before deletion"
  assert_contains "$S" 'nor one with an open PR' "a branch with an open PR is never deleted"
  assert_contains "$S" '`studio-overnight settle <slug>` does it (try `--dry-run` first)' "a hand landing is settled by studio-overnight settle"
  assert_contains "$S" 'A worktree with uncommitted changes is kept and reported' "a dirty worktree is kept"
  assert_contains "$S" "the report's \`## Cleanup\` says what was done and what is left" "the report's Cleanup section reports"
  assert_contains "$S" 'no session deletes a remote branch' "a session still never deletes a remote branch"
  assert_contains "$S" '^  delete a remote branch; no destructive' "phase 2 still forbids deleting a remote branch"
}

# Automatic run cleanup (2026-10-27): the Jira story comment goes through acli first.
test_autopilot_jira_acli() {
  S="$REPO_ROOT/shared/omega/skills/autopilot/SKILL.md"
  assert_contains "$S" 'through `acli` first (on `PATH`, or' "Jira goes through acli first"
  assert_contains "$S" '`~/.local/bin/acli`' "acli's fallback path"
  assert_contains "$S" 'acli jira workitem comment create --key <KEY> --body "<text>"' "the acli comment command"
  assert_contains "$S" 'without `acli`, through the Atlassian MCP' "the Atlassian MCP is the fallback"
}

# #39 AC19: off applies the bare-stop rule.
test_autopilot_off_stop_rule() {
  S="$REPO_ROOT/shared/omega/skills/autopilot/SKILL.md"
  assert_contains "$S" '`off`: `omega-mode clear autopilot`; then a bare `studio-overnight stop`' "off clears the mode, then a bare stop"
  assert_contains "$S" 'stop --run <slug>' "off names stop --run with several runs"
  assert_contains "$S" 'stop --all' "off names stop --all with several runs"
  # #39 final review N2: a live run no longer blocks a start (AC19), and a
  # bare stop refuses with two live runs.
  assert_not_contains "$S" 'direct mode, no live run)' "the dry run no longer checks for no live run"
  assert_contains "$S" 'no conflicting live or stopped run (slug, story, branch)' "the dry run checks for conflicting runs"
  assert_contains "$S" '`studio-overnight stop --run <slug>` (from the project)' "the user ends the run with stop --run"
}

# #39 AC14/#35: adopt steps print slug-qualified ids.
test_autopilot_adopt_slug_forms() {
  S="$REPO_ROOT/shared/omega/skills/autopilot/SKILL.md"
  assert_contains "$S" '/game-dev:plan <slug>/<id>' "adopt prints the plan command with slug/id"
  assert_contains "$S" '/game-dev:brainstorm <slug>/<id>' "adopt prints the brainstorm command with slug/id"
  assert_not_contains "$S" '/game-dev:plan <id>' "no bare-id plan command"
  assert_not_contains "$S" '/game-dev:brainstorm <id>' "no bare-id brainstorm command"
}
