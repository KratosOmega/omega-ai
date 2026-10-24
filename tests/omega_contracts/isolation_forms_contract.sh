#!/bin/sh
# Text contract: no skill or agent .md under studios/ or shared/omega/ prescribes a
# shell form that Claude Code's worktree isolation refuses (spec E2/E3). Sourced by
# tests/omega_test.sh (test_skill_contracts), which defines test_isolation_forms_contract;
# also runnable alone: sh tests/omega_contracts/isolation_forms_contract.sh.
#
# Forbidden, each reported as file:line:
#   bash "$(sdd-script            git checkout $STUDIO_DOCS_REV        cd <dir> && studio-gate
#   an inline backticked span, or a line inside a fenced block, that runs git (the word
#   "git" followed by a space) and contains &&, ; or |  (so || counts)
#   a $(...) inside such a span or line that runs git or `studio-state ledger`
# Prose that only mentions git outside backticks is not scanned.

# scan_forms DIR...: print "file:line: why" for each forbidden form under the .md files of DIR.
scan_forms() {
  find "$@" -name '*.md' -type f 2>/dev/null | LC_ALL=C sort | while IFS= read -r f; do
    awk -v F="$f" '
      function chain(s) { return s ~ /&&|;|\|/ }
      function rungit(s) { return s ~ /(^|[^A-Za-z0-9_.\/-])git / }
      function bad(s, where) {
        if (rungit(s) && chain(s)) print F ":" NR ": git chained with && ; or | (" where ")"
        else if ((rungit(s) || s ~ /studio-state ledger/) && s ~ /\$\(/) print F ":" NR ": $(...) feeding git or ledger (" where ")"
      }
      /^[ \t]*```/ { fence = !fence; next }
      {
        if ($0 ~ /bash "\$\(sdd-script/) print F ":" NR ": bash \"$(sdd-script"
        if ($0 ~ /git checkout \$STUDIO_DOCS_REV/) print F ":" NR ": git checkout $STUDIO_DOCS_REV"
        if ($0 ~ /cd [^`]*&& *studio-gate/) print F ":" NR ": cd <dir> && studio-gate"
        if (fence) { bad($0, "fenced"); next }
        n = split($0, part, "`")
        for (i = 2; i <= n; i += 2) if (i < n || n % 2 == 1) bad(part[i], "span")
      }' "$f"
  done
}

test_isolation_forms_contract() {
  # Self-test: a bad and a good fixture.
  mk_tmp isolation-forms; fx="$TMP"
  mkdir -p "$fx/studios"
  {
    printf '%s\n' 'Run `git add a && git commit -m x` now.'
    printf '%s\n' 'Run `git rev-parse HEAD | head -n 1`.'
    printf '%s\n' 'Run `studio-state ledger "base $(git rev-parse HEAD)"`.'
    printf '%s\n' '```sh'
    printf '%s\n' 'git switch main 2>/dev/null || git switch --detach x'
    printf '%s\n' '```'
    printf '%s\n' 'bash "$(sdd-script foo)"'
  } > "$fx/studios/bad.md"
  {
    printf '%s\n' 'Run `git add a`, then `git commit -m x`. Git is fine in prose; so is a | b.'
    printf '%s\n' 'Run `ls a && ls b` and `x || y` (no git).'
    printf '%s\n' '```sh'
    printf '%s\n' 'ls a || ls b'
    printf '%s\n' 'git status'
    printf '%s\n' '```'
  } > "$fx/studios/good.md"
  got="$(scan_forms "$fx" | sed "s|^$fx/||")"
  assert_eq "studios/bad.md:1: git chained with && ; or | (span)
studios/bad.md:2: git chained with && ; or | (span)
studios/bad.md:3: \$(...) feeding git or ledger (span)
studios/bad.md:5: git chained with && ; or | (fenced)
studios/bad.md:7: bash \"\$(sdd-script" "$got" "the scanner flags every bad fixture line and none of the good file"
  rm_tmp "$fx"

  # The real tree.
  hits="$(cd "$REPO_ROOT" && scan_forms studios shared/omega)"
  assert_eq "" "$hits" "no skill or agent .md prescribes a refused shell form"

  # E2: the sentence is in execute section 2 and section 0.
  S="$REPO_ROOT/studios/game-dev/skills/execute/SKILL.md"
  e2='Worktree isolation refuses some shell forms\. Run git as one plain command per Bash call\. Never `cd <dir> &&`'
  assert_eq 2 "$(grep -c -E "$e2" "$S")" "execute carries the E2 sentence in section 0 and in section 2"
  sec2="$(sed -n '/^## 2\. /,/^## 3\. /p' "$S")"
  case "$sec2" in
    *'Worktree isolation refuses some shell forms. Run git as one plain command per Bash call.'*) _pass "E2 sentence is inside section 2" ;;
    *) _fail "E2 sentence is inside section 2" ;;
  esac
}

# Run alone.
if ! command -v assert_eq >/dev/null 2>&1; then
  REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
  . "$REPO_ROOT/tests/assert.sh"
  run_tests test_isolation_forms_contract
fi
