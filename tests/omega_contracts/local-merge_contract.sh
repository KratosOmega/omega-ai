#!/bin/sh
# Text contract for shared/omega/skills/local-merge/SKILL.md. Sourced by
# tests/omega_test.sh (test_skill_contracts), which maps the file name's
# hyphen to an underscore; defines test_local_merge_contract.
test_local_merge_contract() {
  S="$REPO_ROOT/shared/omega/skills/local-merge/SKILL.md"
  assert_contains "$S" "omega-mode set local-merge" "local-merge sets its mode on the Skill-tool path"
  assert_contains "$S" "This mode changes how work is scheduled, saved, merged or stopped" "local-merge carries the precedence contract"
  assert_contains "$S" "[-][-]admin" "local-merge merges with gh pr merge --admin"
  assert_contains "$S" "exit 0" "local-merge requires exit 0 from the local CI"
  assert_contains "$S" "merge_commit_sha" "local-merge detects the strategy from merged PRs"
  assert_contains "$S" "Never merge unverified" "local-merge never merges unverified"
  assert_contains "$S" "[-][-]draft" "local-merge opens a draft PR under autopilot"
  assert_contains "$S" "tests/run_all.sh" "local-merge knows this repository's CI convention"
}
