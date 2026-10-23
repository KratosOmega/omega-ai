#!/bin/sh
# Locale guard: macOS sh (bash 3.2) matches a bracket range such as [a-z] by the
# locale's collation, so under en_US.UTF-8 [a-z] also takes A-Y. Every shipped shell
# script that uses a range sets byte collation before its first pattern.
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"
mk_tmp locale_guard_test
trap 'rm_tmp "$TMP"' EXIT
GUARD='unset LC_ALL; LC_COLLATE=C'

# shipped_scripts — tracked sh/bash scripts outside the test trees, one per line.
shipped_scripts() {
  git -C "$REPO_ROOT" ls-files | while IFS= read -r f; do
    case "$f" in tests/*|*/tests/*) continue ;; esac
    [ -f "$REPO_ROOT/$f" ] || continue
    head -n 1 "$REPO_ROOT/$f" | grep -qE '^#!.*[/ ](ba)?sh( |$)' && printf '%s\n' "$f"
  done
}
# uses_range FILE — a non-comment line holds a bracket expression with a letter or digit range.
uses_range() {
  grep -v '^[[:space:]]*#' "$1" | LC_ALL=C grep -qE '\[[^]]*[a-zA-Z0-9]-[a-zA-Z0-9][^]]*\]'
}

test_guard_present_where_ranges_are_used() {
  _n=0
  for f in $(shipped_scripts); do
    uses_range "$REPO_ROOT/$f" || continue
    _n=$((_n + 1))
    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -qxF "$GUARD" "$REPO_ROOT/$f"; then _pass "$f sets byte collation"
    else _fail "$f uses a bracket range but has no '$GUARD' line"; fi
  done
  assert_eq 1 "$([ "$_n" -gt 0 ] && echo 1 || echo 0)" "at least one shipped script uses a range (the scan is not empty)"
}

test_guard_works_under_utf8_locale() {
  _l="$(locale -a 2>/dev/null | grep -iE '^(en_US|C)\.utf-?8$' | head -n 1)"
  if [ -z "$_l" ]; then TESTS_RUN=$((TESTS_RUN + 1)); _pass "no UTF-8 locale installed: nothing to check"; return; fi
  _t='case T in [a-z]) echo lower ;; *) echo other ;; esac'
  for _e in "LANG=$_l" "LC_ALL=$_l" "LC_COLLATE=$_l"; do
    assert_eq other "$(env -i PATH=/usr/bin:/bin "$_e" sh -c "$GUARD; $_t")" "T is not in [a-z] with the guard ($_e)"
  done
}

run_tests test_guard_present_where_ranges_are_used test_guard_works_under_utf8_locale
