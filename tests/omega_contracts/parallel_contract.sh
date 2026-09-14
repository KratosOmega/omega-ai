#!/bin/sh
# Text contract for shared/omega/skills/parallel/SKILL.md. Sourced by
# tests/omega_test.sh (test_skill_contracts); defines test_parallel_contract.
test_parallel_contract() {
  S="$REPO_ROOT/shared/omega/skills/parallel/SKILL.md"
  assert_contains "$S" "omega-mode set parallel" "parallel sets its mode on the Skill-tool path"
  assert_contains "$S" "This mode changes how work is scheduled, saved, merged or stopped" "parallel carries the precedence contract"
  assert_contains "$S" "cherry-pick" "parallel cherry-picks task commits onto the feature branch"
  assert_contains "$S" "git worktree add" "parallel isolates each task in a worktree"
  assert_contains "$S" "parallel/" "parallel names task branches parallel/<feature>/task-<n>"
  assert_contains "$S" "sonnet" "parallel states the sonnet floor for worktree agents"
  assert_contains "$S" "fifteen lines" "parallel caps subagent reports at fifteen lines"
  assert_contains "$S" "waves.md" "parallel writes a wave table"
  assert_contains "$S" "Only now" "parallel runs the invoking skill's bookkeeping after integration"
}
