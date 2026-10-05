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
  assert_contains "$S" 'integration or direct' "phase 1 asks the run mode"
  assert_contains "$S" 'how many lanes' "and the lane count"
  assert_contains "$S" 'one .AskUserQuestion. with two questions' "mode and lanes in one question"
  assert_contains "$S" 'docs/runs/<slug>.md' "the run manifest"
  assert_contains "$S" '> \.studio/run`' "the pointer (anchored: not .studio/runs/)"
  assert_contains "$S" '.studio/runs/<slug>/done' "a done run's pointer is ignored"
  assert_contains "$S" 'switch this checkout to .<default>. first' "D11: run/<slug> needs the default branch"
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
  assert_contains "$S" '.studio-overnight status. exits 0, a run is live: stop' "discovery never re-seeds a live run (I1)"
  assert_contains "$S" '.studio/runs/<slug>/. exists, the run was started: skip to step 4' "a started run is not re-seeded (I1)"
  assert_contains "$S" 'when .STUDIO_RUN. is unset, the base is per .omega:local-merge. §3' "the non-studio PR base is unchanged (I2)"
  assert_contains "$S" 'python3 -c' "max_lanes is merged into config.json (I3)"
  assert_contains "$S" 'every other key is kept' "the merge preserves merge_command (I3)"
  assert_contains "$S" 'an integer from 0 to 8' "max_lanes uses the runner's range (I3)"
  assert_contains "$S" 'git add docs/runs/<slug>.md .studio/config.json' "config.json is committed on run/<slug> (I3)"
  assert_contains "$S" 'When .next. exits non-zero' "a failing next stops the loop"
  assert_contains "$S" 'git switch run/<slug>. when it already exists' "an existing run branch is switched to"
  # Task 17 fix round 3: the story file (STATE_ROOT, shared) carries N, so a worktree rebuild needs no plan.
  assert_contains "$S" 'plan=.); .set task 0/<N>.' "every story is seeded with task 0/N in the phase-1 checkout"
  assert_contains "$S" "awk '/^## Backlog/ { exit } /^### Task \\[0-9\\]/ { n++ } END { print n + 0 }' <plan>" "N counts only the tasks above ## Backlog"
  assert_not_contains "$S" "grep -c '^### Task" "N is never a bare grep -c (it would count backlog tasks)"
  assert_contains "$S" 'takes .N. from the story file and never needs the plan' "a worktree rebuild reads N, not the plan file"
  assert_contains "$S" 'Write it only after the switch to .run/<slug>.' "max_lanes is written after the run branch switch"
  assert_contains "$S" 'Then, on .run/<slug>., write the lane count' "the run-branch step writes the lane count"
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
  assert_contains "$D" 'integration or direct' "the scenario expects the mode question"
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
  # AC1: the manifest commit carries every story's ledger; AC3: step 3 ledgers `adopted` before seeding.
  _a="$(grep -n -F -m1 -- 'git add docs/runs/<slug>.md .studio/config.json .studio/ledger/<id>.md … && git commit -m "docs(run): <slug> manifest"' "$S" | cut -d: -f1)"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -n "$_a" ]; then _pass "manifest commit adds the ledgers"; else _fail "manifest commit adds the ledgers"; fi
  _a="$(grep -n -F -m1 -- 'studio-state ledger "adopted <original> -> <new plan>"' "$S" | cut -d: -f1)"
  _b="$(grep -n -F -m1 -- 'Each story, not-started and half-done alike' "$S" | cut -d: -f1)"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -n "$_a" ] && [ -n "$_b" ] && [ "$_a" -lt "$_b" ]; then _pass "step 3 ledgers adopted before seeding"
  else _fail "step 3 ledgers adopted before seeding ($_a, $_b)"; fi
}

# The AC5 order (spec): the five phrases appear in the skill in this order.
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
