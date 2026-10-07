#!/bin/sh
# Tests for tests/run_affected.sh (R9). Each test builds a fixture git repo with
# a bare origin and a copy of the real script; only --list is used, so run_all
# is never run. TEST_SH selects the shell for the nested script (dash run).
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/run_affected_test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# repo NAME: R9 mini layout on main, pushed to a bare origin. Sets R.
repo() {
  R="$TMP/$1"
  mkdir -p "$R" "$TMP/$1.git"
  git init -q --bare "$TMP/$1.git"
  (
    cd "$R" || exit 1
    git init -q -b main . && git config user.email t@t && git config user.name t
    mkdir -p lib tests bin docs
    echo 'common' > lib/common.sh
    echo 'assert' > tests/assert.sh
    echo 'run_all' > tests/run_all.sh
    echo 'uses bin/tool' > tests/a_test.sh
    echo 'reads docs/y.md' > tests/b_test.sh
    echo '. bin/lib.sh' > bin/tool
    echo 'lib' > bin/lib.sh
    echo x > docs/x.md
    echo y > docs/y.md
    echo u > unknown.txt
    git add -A && git commit -q -m init
    git remote add origin "$TMP/$1.git"
    git push -q origin main 2>/dev/null
    git fetch -q origin
    cp "$REPO_ROOT/tests/run_affected.sh" tests/run_affected.sh
    echo tests/run_affected.sh >> .git/info/exclude   # the copy is not a change
  )
}

# list: sorted suite column on one line; stderr to $TMP/err, full output to $TMP/o.
list() {
  ( cd "$R" && ${TEST_SH:-sh} tests/run_affected.sh --list 2> "$TMP/err" ) > "$TMP/o"
  cut -f1 "$TMP/o" | sort | tr '\n' ' ' | sed 's/ $//'
}

test_affected_suite_change_maps_to_itself() {
  repo s1
  echo more >> "$R/tests/b_test.sh"
  assert_eq "b_test" "$(list)" "a changed suite maps to itself"
  assert_contains "$TMP/err" "run_affected: base origin/main" "base sha goes to stderr"
  assert_contains "$TMP/o" "b_test	itself" "reason is itself, tab separated"
}

test_affected_shared_files_map_to_all() {
  repo s2
  echo m >> "$R/tests/assert.sh"
  assert_eq "a_test b_test" "$(list)" "assert.sh maps to all"
  git -C "$R" checkout -q tests/assert.sh
  echo m >> "$R/tests/run_all.sh"
  assert_eq "a_test b_test" "$(list)" "run_all.sh maps to all"
  git -C "$R" checkout -q tests/run_all.sh
  echo m >> "$R/lib/common.sh"
  assert_eq "a_test b_test" "$(list)" "lib/common.sh maps to all"
  assert_contains "$TMP/o" "a_test	shared: lib/common.sh" "shared reason names the file"
}

test_affected_sourced_lib_maps_through_closure() {
  repo s3
  echo m >> "$R/bin/lib.sh"
  assert_eq "a_test" "$(list)" "bin/lib.sh -> bin/tool -> a_test"
  assert_contains "$TMP/o" "a_test	via bin/lib.sh" "closure reason is via <file>"
}

test_affected_docs_map_to_readers_or_none() {
  repo s4
  echo m >> "$R/docs/y.md"
  assert_eq "b_test" "$(list)" "a doc named by a suite maps to it"
  assert_contains "$TMP/o" "b_test	reads docs/y.md" "reads reason names the doc"
  git -C "$R" checkout -q docs/y.md
  echo m >> "$R/docs/x.md"
  assert_eq "" "$(list)" "a doc nobody reads maps to nothing (docs/y.md is not the dir docs)"
  assert_contains "$TMP/err" "no suite reads docs/x.md" "names the unread doc"
}

test_affected_unknown_maps_to_all() {
  repo s5
  echo m >> "$R/unknown.txt"
  assert_eq "a_test b_test" "$(list)" "an unreferenced file maps to all"
  assert_contains "$TMP/o" "unknown: unknown.txt" "unknown reason names the file"
}

test_affected_deleted_and_untracked_files() {
  repo s6
  rm "$R/bin/lib.sh"
  assert_eq "a_test" "$(list)" "a deleted file still maps through its readers"
  git -C "$R" checkout -q bin/lib.sh
  echo t > "$R/tests/c_test.sh"
  assert_eq "c_test" "$(list)" "an untracked suite maps to itself"
}

test_affected_rename_counts_both_paths() {
  repo s7
  git -C "$R" checkout -q -b feat
  git -C "$R" mv bin/lib.sh bin/lib2.sh
  git -C "$R" commit -q -m rename
  assert_eq "a_test" "$(list)" "the old path of a rename reaches its readers"
}

test_affected_missing_base_exits_2() {
  repo s8
  _rc=0
  ( cd "$R" && ${TEST_SH:-sh} tests/run_affected.sh --base nope --list ) > "$TMP/o" 2>&1 || _rc=$?
  assert_eq 2 "$_rc" "missing base exits 2"
  assert_contains "$TMP/o" "run_affected: base nope not found — git fetch, or pass --base" "R9 message"
}

test_affected_no_changes() {
  repo s9
  _rc=0
  ( cd "$R" && ${TEST_SH:-sh} tests/run_affected.sh --list ) > "$TMP/o" 2>&1 || _rc=$?
  assert_eq 0 "$_rc" "no changes exits 0"
  assert_contains "$TMP/o" "no changes against origin/main" "says so"
}

run_tests test_affected_suite_change_maps_to_itself test_affected_shared_files_map_to_all \
  test_affected_sourced_lib_maps_through_closure test_affected_docs_map_to_readers_or_none \
  test_affected_unknown_maps_to_all test_affected_deleted_and_untracked_files \
  test_affected_rename_counts_both_paths test_affected_missing_base_exits_2 \
  test_affected_no_changes
