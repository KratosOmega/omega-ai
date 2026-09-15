#!/bin/sh
# Text contract for shared/omega/skills/delegate/SKILL.md. Sourced by
# tests/omega_test.sh (test_skill_contracts); defines test_delegate_contract.
test_delegate_contract() {
  S="$REPO_ROOT/shared/omega/skills/delegate/SKILL.md"
  P="$REPO_ROOT/shared/omega/skills/parallel/SKILL.md"
  assert_contains "$S" "omega-mode set delegate" "delegate sets its mode on the Skill-tool path"
  assert_contains "$S" "This mode changes how work is scheduled, saved, merged or stopped" "delegate carries the precedence contract"
  assert_eq "$(grep '^> ' "$P")" "$(grep '^> ' "$S")" "delegate's precedence block is byte-identical to parallel's"
  assert_contains "$S" "never fix by hand" "delegate never fixes by hand"
  assert_contains "$S" "Calls \`Edit\`, \`Write\` or \`NotebookEdit\` on a path under the repository" "delegate never edits under the repository"
  assert_contains "$S" "Calls \`Read\`, \`Grep\` or \`Glob\` on repository source" "delegate never searches the repository"
  assert_contains "$S" "heredocs" "delegate closes the Bash and MCP route"
  assert_contains "$S" "fifteen lines" "delegate caps reports at fifteen lines"
  assert_contains "$S" "Explore" "delegate routes lookups to an investigator"
  assert_contains "$S" "sonnet" "delegate keeps the sonnet floor"
  assert_contains "$S" "status command" "delegate runs status commands in the main session"
  assert_contains "$S" "redispatch" "delegate redispatches a failed task"
  assert_contains "$S" "three" "delegate stops after three failed rounds"
  assert_contains "$S" "never reads a diff" "delegate never reads a diff in the main session"
  assert_contains "$S" "executing-plans" "delegate rules out executing-plans"
  assert_contains "$S" "writing-plans" "delegate routes writing-plans to a planner agent"
  assert_not_contains "$S" "Work only in" "delegate keeps the isolation phrase lower-case, the pitfall parallel's own text names"
}
