#!/bin/sh
# Text contract for shared/omega/skills/autopilot/SKILL.md. Sourced by
# tests/omega_test.sh (test_skill_contracts); defines test_autopilot_contract.
test_autopilot_contract() {
  S="$REPO_ROOT/shared/omega/skills/autopilot/SKILL.md"
  assert_contains "$S" "omega-mode set autopilot" "autopilot sets its mode after the readiness checklist"
  assert_contains "$S" "This mode changes how work is scheduled, saved, merged or stopped" "autopilot carries the precedence contract"
  assert_contains "$S" "[Nn]ever merge" "autopilot never merges"
  assert_contains "$S" "AskUserQuestion. is never called" "autopilot forbids AskUserQuestion in phase 2"
  assert_contains "$S" "omega:handoff" "autopilot ends with handoff"
  assert_contains "$S" "cost if wrong" "autopilot logs rulings with their cost if wrong"
  assert_contains "$S" "## Decisions" "autopilot records the question sweep in the plan"
  assert_contains "$S" "gh auth status" "autopilot's readiness checklist checks gh"
  assert_contains "$S" "KAN-" "autopilot detects a Jira story from the branch"
}
