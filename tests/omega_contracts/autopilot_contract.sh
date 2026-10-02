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
  D="$REPO_ROOT/docs/omega/pressure/autopilot.md"
  assert_contains "$D" "checklist of six lines" "the pressure doc counts six checklist lines"
  assert_contains "$D" "^\*2026-09-15: the arm-step criterion" "the 2026-09-15 dated note is kept (D10)"
  assert_contains "$D" "^\*2026-10-01: the hand-off criterion" "the 2026-10-01 note follows it"
}
