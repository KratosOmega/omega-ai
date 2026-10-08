#!/bin/sh
# Assertion helpers and a minimal test runner. Sourced by test files.
#
# On source: unsets CLAUDECODE, AI_AGENT, CLAUDE_*, OMEGA_*, STUDIO_* and GIT_DIR,
# GIT_WORK_TREE, GIT_INDEX_FILE, GIT_COMMON_DIR, GIT_OBJECT_DIRECTORY,
# GIT_ALTERNATE_OBJECT_DIRECTORIES, GIT_NAMESPACE (a suite never inherits an
# autopilot unit's or a repo's context). TESTS_ONLY and TEST_* are kept.
# Environment (empty = unset):
#   TESTS_ONLY="a b"  run only these (intersected with the partition)
#   TEST_PHASE        unset: every test in listed order · parallel: this shard,
#                     then TESTS_FINAL · exclusive: TESTS_EXCLUSIVE, then TESTS_FINAL
#   TEST_SHARD=k/N    with TEST_PHASE=parallel: eligible test j runs when (j-1) mod N = k-1
#   TEST_TIMING_LOG   append an L row per run_tests call and a T row per test
# Suite declarations before run_tests: TESTS_EXCLUSIVE, TESTS_REAL_CLOCK, TESTS_FINAL
# (space-separated test names) and an optional before_each function (TEST_NAME is set).
# Helpers: is_real_clock, own_group CMD..., mk_msleep, next_second.
for __rt_v in $(env | sed -nE 's/^(CLAUDECODE|AI_AGENT|CLAUDE_[A-Za-z0-9_]*|OMEGA_[A-Za-z0-9_]*|STUDIO_[A-Za-z0-9_]*|GIT_DIR|GIT_WORK_TREE|GIT_INDEX_FILE|GIT_COMMON_DIR|GIT_OBJECT_DIRECTORY|GIT_ALTERNATE_OBJECT_DIRECTORIES|GIT_NAMESPACE)=.*/\1/p'); do
  unset "$__rt_v"
done

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

# own_group CMD... — exec CMD in a process group of its own with SIGINT/SIGQUIT at their
# defaults (what `set -m` gives a background job, but also under dash with no tty). The last
# command of a background subshell: `( cd "$P" && own_group sh "$RUNNER" start ) & PID=$!`.
own_group() { exec perl -e '$SIG{INT}=$SIG{QUIT}="DEFAULT"; setpgrp(0,0); exec @ARGV or die "exec: $!\n"' "$@"; }
# mk_msleep — $TMP/bin/msleep: a sleep whose argv carries $TMP (pgrep -f "$TMP/bin/msleep N$").
# A symlink to sleep, or, where sleep dispatches on argv[0] (busybox), a perl sleeper.
mk_msleep() {
  mkdir -p "$TMP/bin" || return 1
  rm -f "$TMP/bin/msleep"
  ln -s "$(command -v sleep)" "$TMP/bin/msleep" && "$TMP/bin/msleep" 0 2>/dev/null && return 0
  rm -f "$TMP/bin/msleep"
  printf '#!/usr/bin/env perl\nselect(undef, undef, undef, $ARGV[0]);\n' > "$TMP/bin/msleep" \
    && chmod +x "$TMP/bin/msleep" && "$TMP/bin/msleep" 0
}
# next_second — return once `date +%s` has moved on (a new run-dir name); 3 s ceiling.
next_second() {
  __rt_ns=$(date +%s); __rt_ni=0
  while [ "$(date +%s)" = "$__rt_ns" ] && [ "$__rt_ni" -lt 30 ]; do sleep 0.1; __rt_ni=$((__rt_ni + 1)); done
}

__rt_in() { case " $2 " in *" $1 "*) return 0 ;; esac; return 1; }
__rt_row() { [ -z "${TEST_TIMING_LOG:-}" ] || printf '%s\n' "$1" >> "$TEST_TIMING_LOG"; }
__rt_failv() { TESTS_RUN=$((TESTS_RUN + 1)); _fail "$1"; }
is_real_clock() { __rt_in "${TEST_NAME:-}" "${TESTS_REAL_CLOCK:-} ${TESTS_EXCLUSIVE:-}"; }

# run_tests NAME... — see the header. Fails loudly on a bad phase/shard (no test runs) or a
# tag naming an unlisted test (every selected test still runs); a listed name that is not a
# function fails too, so a test can never drop out of a suite silently.
run_tests() {
  __rt_suite="$(basename "$0" .sh)"; __rt_ph="${TEST_PHASE:-}"; __rt_sh="${TEST_SHARD:-}"
  __rt_k=1; __rt_n=1; __rt_bad=""
  case "$__rt_ph" in
    ''|parallel|exclusive) ;;
    *) __rt_bad="bad TEST_PHASE '$__rt_ph' (want parallel or exclusive)" ;;
  esac
  if [ -z "$__rt_bad" ] && [ -n "$__rt_sh" ]; then
    if [ "$__rt_ph" != parallel ]; then
      __rt_bad="TEST_SHARD needs TEST_PHASE=parallel"
    else
      case "$__rt_sh" in
        */*) ;;
        *) __rt_bad="bad TEST_SHARD '$__rt_sh' (want k/N with 1 <= k <= N)" ;;
      esac
      if [ -z "$__rt_bad" ]; then
        __rt_k="${__rt_sh%%/*}"; __rt_n="${__rt_sh#*/}"
        case "$__rt_k/$__rt_n" in
          */*/*|*[!0-9/]*|/*|*/|0*|*/0*) __rt_bad="bad TEST_SHARD '$__rt_sh' (want k/N with 1 <= k <= N)" ;;
          *) [ "$__rt_k" -le "$__rt_n" ] || __rt_bad="bad TEST_SHARD '$__rt_sh' (want k/N with 1 <= k <= N)" ;;
        esac
      fi
    fi
  fi
  if [ -n "$__rt_bad" ]; then __rt_part=bad
  elif [ "$__rt_ph" = parallel ]; then __rt_part="p${__rt_k}of${__rt_n}"
  elif [ "$__rt_ph" = exclusive ]; then __rt_part=x
  else __rt_part=all; fi
  [ -z "$__rt_ph" ] || printf 'partition %s\n' "$__rt_part"
  [ -z "$__rt_bad" ] || __rt_failv "$__rt_bad"
  for __rt_v in TESTS_EXCLUSIVE TESTS_REAL_CLOCK TESTS_FINAL; do
    eval "__rt_l=\${$__rt_v:-}"
    for __rt_w in $__rt_l; do
      __rt_in "$__rt_w" "$*" || __rt_failv "$__rt_v names unknown test $__rt_w"
    done
  done
  for __rt_w in ${TESTS_EXCLUSIVE:-}; do
    if __rt_in "$__rt_w" "${TESTS_FINAL:-}"; then __rt_failv "$__rt_w is both exclusive and final"; fi
  done
  # Selection: "idx:name" words. A phase runs the finals after its own tests.
  __rt_sel=""; __rt_fsel=""; __rt_fin=""; __rt_i=0; __rt_j=0
  for __rt_t in "$@"; do
    __rt_i=$((__rt_i + 1))
    if __rt_in "$__rt_t" "${TESTS_FINAL:-}"; then
      __rt_fin="$__rt_fin${__rt_fin:+,}$__rt_i"; __rt_fsel="$__rt_fsel $__rt_i:$__rt_t"
      [ -z "$__rt_ph" ] || continue
    fi
    [ -z "$__rt_bad" ] || continue
    case "$__rt_ph" in
      '') __rt_sel="$__rt_sel $__rt_i:$__rt_t" ;;
      exclusive)
        if __rt_in "$__rt_t" "${TESTS_EXCLUSIVE:-}"; then __rt_sel="$__rt_sel $__rt_i:$__rt_t"; fi ;;
      parallel)
        if ! __rt_in "$__rt_t" "${TESTS_EXCLUSIVE:-}"; then
          __rt_j=$((__rt_j + 1))
          if [ $(( (__rt_j - 1) % __rt_n )) -eq $((__rt_k - 1)) ]; then __rt_sel="$__rt_sel $__rt_i:$__rt_t"; fi
        fi ;;
    esac
  done
  if [ -n "$__rt_ph" ] && [ -z "$__rt_bad" ]; then __rt_sel="$__rt_sel$__rt_fsel"; fi
  __rt_row "$(printf 'L\t%s\t%s\t%s\t%s' "$__rt_suite" "$__rt_part" "$#" "${__rt_fin:--}")"
  for __rt_e in $__rt_sel; do
    __rt_t="${__rt_e#*:}"
    if [ -n "${TESTS_ONLY:-}" ] && ! __rt_in "$__rt_t" "$TESTS_ONLY"; then continue; fi
    printf '%s\n' "$__rt_t"
    TEST_NAME="$__rt_t"
    __rt_r0=$TESTS_RUN; __rt_f0=$TESTS_FAILED; __rt_s0=$(date +%s)
    case "$(type before_each 2>/dev/null)" in *function*) before_each ;; esac
    case "$(type "$__rt_t" 2>/dev/null)" in
      *function*) "$__rt_t" ;;
      *) __rt_failv "no test function $__rt_t" ;;
    esac
    __rt_row "$(printf 'T\t%s\t%s\t%s\t%s\t%s\t%s\t%s' "$__rt_suite" "$__rt_part" "${__rt_e%%:*}" "${__rt_e#*:}" \
      $(( $(date +%s) - __rt_s0 )) $((TESTS_RUN - __rt_r0)) $((TESTS_FAILED - __rt_f0)))"
  done
  printf '\n%s assertions, %s failed\n' "$TESTS_RUN" "$TESTS_FAILED"
  [ "$TESTS_FAILED" -eq 0 ]
}
