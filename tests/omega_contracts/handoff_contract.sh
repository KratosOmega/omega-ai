#!/bin/sh
# Text contract for shared/omega/skills/handoff/SKILL.md. Sourced by
# tests/omega_test.sh (test_skill_contracts); defines test_handoff_contract.
test_handoff_contract() {
  S="$REPO_ROOT/shared/omega/skills/handoff/SKILL.md"
  assert_contains "$S" "wip:" "handoff commits red or half-done work as wip:"
  assert_contains "$S" "docs/handoffs" "handoff writes docs/handoffs"
  assert_contains "$S" "AskUserQuestion" "handoff asks once when agents are in flight"
  assert_contains "$S" "resume prompt" "handoff prints a resume prompt"
  assert_contains "$S" "git push -u origin" "handoff pushes the branch"
  assert_contains "$S" "parallel/" "handoff pushes un-integrated task branches"
  assert_not_contains "$S" "studio-state set" "handoff never writes studio state"
  assert_not_contains "$S" "git add -A" "handoff stages by name"
}
