#!/bin/sh
# pointer_skills_execute_test.sh (#42, AC33): the execute skill's pointer text.
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"
mk_tmp pointer_skills_execute_test; trap 'rm_tmp "$TMP"' EXIT  # no test uses TMP: it makes the suite fail closed on a bad TMPDIR
S="$REPO_ROOT/studios/game-dev/skills/execute/SKILL.md"

test_skill_execute_handoff_at_isolation() {
  assert_contains "$S" 'studio-state handoff "<that path>"' "hand-off at isolation (c)"
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

# Section text with its lines joined and spaces squeezed, so a wrapped sentence still matches.
sec() { sed -n "/^$1/,/^$2/p" "$S" | tr '\n' ' ' | tr -s ' '; }
# sec_has START END TEXT MSG: the section holds TEXT, as a fixed string.
sec_has() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if sec "$1" "$2" | grep -qF -- "$3"; then _pass "$4"; else _fail "$4 (missing '$3' between '$1' and '$2')"; fi
}
# in_order TEXT FROM A B …: in TEXT, after the first FROM, A comes before B, and so on.
in_order() {
  _t="$1"; _f="$2"; shift 2
  printf '%s' "$_t" | awk -v f="$_f" -v list="$(printf '%s\034' "$@")" '
    { t = t $0 } END {
      i = index(t, f); if (!i) exit 1; t = substr(t, i)
      n = split(list, w, "\034"); p = 0
      for (k = 1; k < n; k++) { j = index(substr(t, p + 1), w[k]); if (!j) exit 1; p += j }
    }'
}
# ok_if MSG CMD…: one assertion that passes when CMD succeeds.
ok_if() { _m="$1"; shift; TESTS_RUN=$((TESTS_RUN + 1)); if "$@"; then _pass "$_m"; else _fail "$_m"; fi; }

test_skill_execute_deadline() {
  sec_has '## 0\. ' '## 1\. ' 'STUDIO_UNIT_WRAP_AT' "§0 names the wrap time"
  sec_has '## 0\. ' '## 1\. ' 'studio-deadline fits' "§0 checks a run fits before starting it"
  sec_has '## 0\. ' '## 1\. ' 'WRAP-UP' "§0 names the hook's wrap notice"
  ok_if "§0: a run that does not fit, or the wrap notice, ends the turn" \
    in_order "$(sec '## 0\. ' '## 1\. ')" 'studio-deadline fits' 'WRAP-UP' 'end the turn'
  sec_has '## 2\. ' '## 3\. ' 'Return to the orchestrator by `$STUDIO_UNIT_WRAP_AT` (`studio-deadline` prints it) with what is done and what is left. Never start a command that cannot finish by then: `studio-deadline fits <gate>` answers that. Pass `timeout` only on gate-routed commands (`studio-test`, `studio-run`, `studio-setup`, `studio-gate`); never on `sh tools/…`, `python`, `git` or any other command — a raised timeout lets a hung command outlive its cap.' "§2: every brief carries the wrap time and the timeout rule"
  sec_has '## 4a\. ' '## 5\. ' 'commit each fix that passes its owning tests as it lands (and push under a lane); never batch fixes to the end of the task' "§4a: green fixes are committed as they land"
}
test_skill_execute_checkpoint() {
  sec_has '## 8\. ' '## 9\. ' 'a `T<n> checkpoint:` part in `studio-brief task <n>`, or a `RUNNER NOTE` block, goes in the implementer'"'"'s brief: `previous attempt: <text> — continue from "next"; do not redo "done" steps unless a file their evidence names has changed since`' "§8 Inputs: the previous attempt reaches the implementer"
  sec_has '## 8\. ' '## 9\. ' '**Wrap-up' "§8 has a Wrap-up bullet"
  ok_if "Wrap-up order: green fixes, checkpoint line, ledger add, checkpoint commit, push, end" \
    in_order "$(sec '## 8\. ' '## 9\. ')" '**Wrap-up' 'commit' \
    'studio-state ledger "T<n> checkpoint: done <steps/evidence paths>; left <steps>; next <first action>"' \
    'git add .studio/ledger' 'git commit -m "chore(studio): checkpoint T<n>"' 'push' 'end the turn'
  sec_has '## 8\. ' '## 9\. ' 'final-review checkpoint: ' "a final-review unit's checkpoint"
  sec_has '## 8\. ' '## 9\. ' 'Stop: <kind> repair out of time — done …; left …' "a repair unit stops with done/left"
  sec_has '## 8\. ' '## 9\. ' 'never the words `in progress`' "a checkpoint never says in progress (studio-adopt's)"
}
test_skill_execute_direct_finish_gate() {
  sec_has '## 7\. ' '## 8\. ' 'step 1 runs as under **Integration**' "§7 Direct runs the finish gate"
  assert_not_contains "$S" 'Direct mode runs no finish gate' "the no-finish-gate sentence is gone"
}
test_skill_execute_operator_scopes() {
  sec_has '### Operator messages' '## 9\. ' '- `task` —' "operator messages: task scope"
  sec_has '### Operator messages' '## 9\. ' "studio-state ledger 'Directive <id> T<n>: <text>'" "a task directive's ledger line"
  sec_has '### Operator messages' '## 9\. ' '- `note` —' "operator messages: note scope"
  sec_has '### Operator messages' '## 9\. ' 'RUNNER NOTE' "the note block is named"
}

run_tests test_skill_execute_handoff_at_isolation test_skill_execute_resume_via_stories \
  test_skill_execute_deadline test_skill_execute_checkpoint test_skill_execute_direct_finish_gate \
  test_skill_execute_operator_scopes
