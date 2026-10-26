#!/bin/sh
# pointer_skills_plan_test.sh: the plan skill's pointer text.
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"
mk_tmp pointer_skills_plan_test; trap 'rm_tmp "$TMP"' EXIT  # no test uses TMP: it makes the suite fail closed on a bad TMPDIR
P="$REPO_ROOT/studios/game-dev/skills/plan/SKILL.md"

# §6 (Self-review) with its lines joined and spaces squeezed, so a wrapped sentence still matches.
sec6() { sed -n '/^## 6\. /,/^## 7\. /p' "$P" | tr '\n' ' ' | tr -s ' '; }
sec6_has() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if sec6 | grep -qF -- "$1"; then _pass "$2"; else _fail "$2 (missing '$1' in plan §6)"; fi
}

# Unit deadline spec §8 (G8): a task whose verify steps cannot fit one session is split.
test_skill_plan_fits_the_session() {
  sec6_has 'fits the session' "§6 self-review checks each task fits the session"
  sec6_has 'session_minutes / 2' "the bound is half a session"
  sec6_has 'until 0' "an unbounded loop is named"
  sec6_has 'T12' "the T12 worked example"
  sec6_has 'max rounds' "a loop task names its max rounds"
  sec6_has 'a Block or a Stop' "then a Block or a Stop"
}

run_tests test_skill_plan_fits_the_session
