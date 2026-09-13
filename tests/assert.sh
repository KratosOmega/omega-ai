#!/bin/sh
# Assertion helpers and a minimal test runner. Sourced by test files.

TESTS_RUN=0
TESTS_FAILED=0

_pass() { printf '  ok   %s\n' "$1"; }
_fail() { printf '  FAIL %s\n' "$1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }

assert_eq() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "$1" = "$2" ]; then
    _pass "$3"
  else
    _fail "$3 (expected '$1', got '$2')"
  fi
}

assert_file() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -f "$1" ]; then _pass "$2"; else _fail "$2 (no regular file at $1)"; fi
}

assert_symlink() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -L "$1" ]; then _pass "$2"; else _fail "$2 (not a symlink: $1)"; fi
}

assert_missing() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ ! -e "$1" ] && [ ! -L "$1" ]; then _pass "$2"; else _fail "$2 (still exists: $1)"; fi
}

# assert_status CODE MSG -- cmd...
assert_status() {
  expected="$1"; msg="$2"; shift 3
  TESTS_RUN=$((TESTS_RUN + 1))
  actual=0
  ( "$@" >/dev/null 2>&1 ) || actual=$?
  if [ "$actual" = "$expected" ]; then
    _pass "$msg"
  else
    _fail "$msg (expected exit $expected, got $actual)"
  fi
}

assert_contains() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -f "$1" ] && grep -q -- "$2" "$1"; then
    _pass "$3"
  else
    _fail "$3 (missing '$2' in $1)"
  fi
}

assert_not_contains() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ ! -f "$1" ]; then
    _fail "$3 (no file at $1)"
  elif grep -q -- "$2" "$1"; then
    _fail "$3 (unexpected '$2' in $1)"
  else
    _pass "$3"
  fi
}

run_tests() {
  for _t in "$@"; do
    printf '%s\n' "$_t"
    "$_t"
  done
  printf '\n%s assertions, %s failed\n' "$TESTS_RUN" "$TESTS_FAILED"
  [ "$TESTS_FAILED" -eq 0 ]
}
