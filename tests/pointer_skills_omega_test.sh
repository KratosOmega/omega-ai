#!/bin/sh
# Pins for the omega handoff and autopilot skill text and the memory note under
# the per-checkout stage pointer (#42, AC19, AC36, AC44).
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"
mk_tmp pointer_skills_omega_test; trap 'rm_tmp "$TMP"' EXIT  # no test uses TMP: it makes the suite fail closed on a bad TMPDIR

test_skill_omega_handoff_no_adopt() {
  f="$REPO_ROOT/shared/omega/skills/handoff/SKILL.md"
  total="$(grep -c 'studio-state \(show\|get\)' "$f")"
  bare="$(grep 'studio-state \(show\|get\)' "$f" | grep -vc 'STUDIO_STATE_NO_ADOPT=1')"
  assert_eq "0" "$bare" "every handoff studio-state read passes STUDIO_STATE_NO_ADOPT=1"
  [ "$total" -ge 2 ] && assert_eq "ok" "ok" "handoff has >=2 studio-state reads" \
    || assert_eq ">=2" "$total" "handoff has >=2 studio-state reads"
  assert_contains "$f" 'so reading never moves a story (studio-state AC18)' "handoff says why"
}

test_skill_autopilot_no_force() {
  f="$REPO_ROOT/shared/omega/skills/autopilot/SKILL.md"
  assert_contains "$f" 'studio-state init --local' "autopilot seeds the run pointer"
  assert_contains "$f" 'studio-state set stage plan' "autopilot sets the stage"
  assert_contains "$f" 'studio-state set spec <spec>' "autopilot sets the spec"
  n="$(grep 'studio-state set' "$f" | grep -c -- '--force')"
  assert_eq "0" "$n" "no --force on any studio-state set line"
}

test_memory_stage_pointer_note() {
  d="$REPO_ROOT/studios/game-dev/memory"
  f="$d/stage-pointer-is-per-checkout.md"
  assert_file "$f" "note exists"
  assert_contains "$f" 'name: stage-pointer-is-per-checkout' "note name"
  assert_contains "$f" 'type: feedback' "note type"
  assert_contains "$f" 'studio-state handoff' "note names handoff"
  assert_contains "$f" 'studio-state take <spec>' "note names take"
  assert_contains "$f" 'studio-state stories' "note names stories"
  assert_contains "$f" 'never `--force`' "note forbids --force"
  assert_contains "$f" '.superpowers/sdd/' "note names the SDD ledger"
  n="$(grep -c '(stage-pointer-is-per-checkout.md)' "$d/MEMORY.md")"
  assert_eq "1" "$n" "MEMORY.md links the note once"
}

run_tests test_skill_omega_handoff_no_adopt test_skill_autopilot_no_force \
  test_memory_stage_pointer_note
