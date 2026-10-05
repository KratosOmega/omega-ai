#!/bin/sh
# Pins for the router, brainstorm and plan skill text under the per-checkout
# stage pointer (#42, AC30-AC32).
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"
SK="$REPO_ROOT/studios/game-dev/skills"

test_skill_router_lists_stories() {
  f="$SK/studio/SKILL.md"
  assert_contains "$f" 'studio-state stories' "router runs stories from main"
  assert_contains "$f" 'in the checkout you are in' "router shows this checkout"
  assert_contains "$f" 'continue <spec> in <path>' "router names the checkout to continue in"
  assert_contains "$f" 'abandon it in <path>' "router names where to abandon another checkout's story"
}

test_skill_router_run_lines_and_adopt_note() {
  f="$SK/studio/SKILL.md"
  assert_contains "$f" 'run in progress in <path>' "run line is not a story"
  assert_contains "$f" 'one-time adopt' "router notes the one-time adopt"
  assert_contains "$f" 'never `/game-dev:execute`' "take-hint Next never names execute"
}

test_skill_brainstorm_tests_pointer_not_file() {
  f="$SK/brainstorm/SKILL.md"
  assert_contains "$f" '`studio-state get stage` exits 0' "state test is the pointer"
  assert_not_contains "$f" 'If `.studio/STATE.md` does not exist' "no file-presence test"
}

test_skill_brainstorm_revise_same_story() {
  f="$SK/brainstorm/SKILL.md"
  assert_contains "$f" 'or start a new story in its own worktree?' "revise question"
  assert_contains "$f" 'studio-state set --force stage brainstorm' "revise forces the stage"
  assert_contains "$f" 'EnterWorktree' "exit 4 suggests EnterWorktree"
}

test_skill_plan_take_hint() {
  f="$SK/plan/SKILL.md"
  assert_contains "$f" '`studio-state take <spec>` here' "plan offers take here"
  assert_contains "$f" 'is waiting' "plan names the waiting story"
  assert_contains "$f" 'exit 4' "plan stops on exit 4"
}

run_tests test_skill_router_lists_stories test_skill_router_run_lines_and_adopt_note \
  test_skill_brainstorm_tests_pointer_not_file test_skill_brainstorm_revise_same_story \
  test_skill_plan_take_hint
