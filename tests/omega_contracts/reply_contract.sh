#!/bin/sh
# Text contract for shared/omega/skills/reply/SKILL.md. Sourced by
# tests/omega_test.sh (test_skill_contracts); defines test_reply_contract.
test_reply_contract() {
  S="$REPO_ROOT/shared/omega/skills/reply/SKILL.md"
  assert_contains "$S" "omega-mode set reply" "reply sets its mode on the Skill-tool path"
  assert_contains "$S" "This mode changes how the session explains itself to the user." \
    "reply carries its own precedence contract"
  assert_contains "$S" "when they disagree about substance, accuracy or a gate, the invoking skill" \
    "reply yields to the invoking skill on substance and gates"
  assert_not_contains "$S" "This mode changes how work is scheduled" \
    "reply does not claim to change how work is scheduled"
  assert_contains "$S" "explain moment" "reply names the explain moment as its trigger"
  assert_contains "$S" "status line" "reply exempts status lines"
  assert_contains "$S" "never gets a scenario, not even a short one" \
    "reply pins the pressure-tested status rule: no scenario, not even a short one"
  assert_contains "$S" "persists outside the conversation" \
    "reply exempts text that persists outside the conversation"
  assert_contains "$S" "One scenario" "reply allows exactly one scenario"
  assert_contains "$S" "What the player sees, feels or does" "reply names the game project's scenario"
  assert_contains "$S" "the user of that thing hits" "reply names the non-game project's scenario"
  assert_contains "$S" "Five short lines" "reply caps an explanation at five lines"
  assert_contains "$S" "Config and" "reply bans config keys from the prose"
  assert_contains "$S" "Raw numbers used as" "reply bans raw threshold values"
  assert_contains "$S" "The pick" "reply's decision shape ends with the recommendation"
  assert_contains "$S" "Test results, counts and every verification claim" \
    "reply never restyles a test result"
  assert_contains "$S" "give it back in its own terms first" \
    "reply pins the pressure-tested result-echo rule: counts and failing line back first"
  assert_contains "$S" "Exact error text" "reply never restyles an error"
  assert_contains "$S" "irreversible" "reply never restyles a destructive-action confirmation"
  assert_contains "$S" "Technical version" "reply has the technical-version escape"
  assert_contains "$S" "Red flags" "reply carries a red-flags table"
}
