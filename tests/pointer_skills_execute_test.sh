#!/bin/sh
# pointer_skills_execute_test.sh (#42, AC33): the execute skill's pointer text.
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"
mk_tmp pointer_skills_execute_test; trap 'rm_tmp "$TMP"' EXIT  # no test uses TMP: it makes the suite fail closed on a bad TMPDIR
S="$REPO_ROOT/studios/game-dev/skills/execute/SKILL.md"

test_skill_execute_handoff_at_isolation() {
  assert_contains "$S" 'studio-state handoff "$(git rev-parse --show-toplevel)"' "hand-off at isolation (c)"
  assert_contains "$S" "is not the main checkout" "hand-off only outside the main checkout"
  assert_contains "$S" "any non-zero exit" "a failed hand-off stops"
  assert_contains "$S" "no hand-off runs" "in place runs no hand-off"
  assert_contains "$S" "worktree-born story" "a worktree-born story runs no hand-off"
}
test_skill_execute_resume_via_stories() {
  assert_contains "$S" "studio-state stories" "stories step in the main checkout"
  assert_contains "$S" 'a `run` line never counts' "run lines never count"
  assert_contains "$S" "studio-state take <spec>" "take on a pointer-less worktree"
  assert_contains "$S" 'a resume that found no `branch`' "take then resume without branch"
  assert_contains "$S" "the gate commits are not in this worktree" "missing gate commits stop"
  assert_contains "$S" 'any resume whose feature ledger has no `base' "missing base recorded on any resume"
  assert_contains "$S" "main checkout's current branch" "base for a story-branch note"
  assert_contains "$S" "Any other exit 1" "other worktree exit 1 stops"
  assert_not_contains "$S" "keeps the pointer in the project's main checkout" "old pointer sentence gone"
}

run_tests test_skill_execute_handoff_at_isolation test_skill_execute_resume_via_stories
