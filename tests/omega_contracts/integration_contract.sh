#!/bin/sh
# Text contract for shared/omega/skills/integration/SKILL.md. Sourced by
# tests/omega_test.sh (test_skill_contracts); defines test_integration_contract.
test_integration_contract() {
  S="$REPO_ROOT/shared/omega/skills/integration/SKILL.md"
  assert_contains "$S" "omega-mode set integration slug=" "integration sets its mode with the slug"
  assert_contains "$S" "This mode changes how work is scheduled, saved, merged or stopped" "integration carries the precedence contract"
  assert_contains "$S" "docs/integrations" "integration tracks the set in docs/integrations"
  assert_contains "$S" "integration/" "integration names its branch integration/<slug>"
  assert_contains "$S" "Refuse" "integration finish refuses with unmerged rows"
  assert_contains "$S" "| Story | Branch | Ticket | Depends on | Status | PR |" "integration writes the story table"
  assert_contains "$S" "omega-mode clear integration" "integration finish clears the mode"
  assert_contains "$S" "origin/main" "integration branches off origin/main"
}
