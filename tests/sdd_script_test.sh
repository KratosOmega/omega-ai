#!/bin/sh
# sdd-script: resolves a superpowers skill script path without searching (#41).
# Every case builds a fake config dir under $TMP and points CLAUDE_CONFIG_DIR at it.
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"
BIN="$REPO_ROOT/studios/game-dev/bin/sdd-script"
TMP="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/sdd_script_test.XXXXXX")" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
SDD=skills/subagent-driven-development/scripts

# fresh N — a new empty config dir $CFG
fresh() { CFG="$TMP/cfg dir.$1"; rm -rf "$CFG"; mkdir -p "$CFG/plugins"; }
# cache VERSION — the cached superpowers VERSION directory
cache() { printf '%s' "$CFG/plugins/cache/claude-plugins-official/superpowers/$1"; }
# ver VERSION SKILL NAME… — a cached superpowers VERSION holding those scripts
ver() {
  _v="$1"; _s="$2"; shift 2
  _d="$(cache "$_v")/skills/$_s/scripts"
  mkdir -p "$_d"
  for _n in "$@"; do : > "$_d/$_n"; done
}
# entry VERSION SCOPE — one superpowers registry entry (pretty-printed)
entry() {
  printf '      {\n        "scope": "%s",\n        "installPath": "%s",\n        "version": "%s"\n      }' "$2" "$(cache "$1")" "$1"
}
# registry ENTRY… — installed_plugins.json shaped like the real one: other
# plugins before and after superpowers, pretty-printed
registry() {
  {
    printf '{\n  "version": 2,\n  "plugins": {\n'
    printf '    "caveman@caveman": [\n      {\n        "scope": "user",\n        "installPath": "%s/other/caveman",\n        "version": "1.0.0"\n      }\n    ],\n' "$CFG"
    printf '    "superpowers@claude-plugins-official": [\n'
    _first=1
    for _e in "$@"; do
      [ "$_first" = 1 ] || printf ',\n'
      _first=0
      printf '%s' "$_e"
    done
    printf '\n    ],\n'
    printf '    "godot-prompter@gp": [\n      {\n        "scope": "user",\n        "installPath": "%s/other/gp",\n        "version": "2.0.0"\n      }\n    ]\n  }\n}\n' "$CFG"
  } > "$CFG/plugins/installed_plugins.json"
}
# installed VERSION — installed_plugins.json naming that cached version active
installed() { registry "$(entry "$1" user)"; }
# run ARGS — sdd-script under $CFG; stdout run.out, stderr run.err, exit RC
run() {
  RC=0
  CLAUDE_CONFIG_DIR="$CFG" sh "$BIN" "$@" > "$TMP/run.out" 2> "$TMP/run.err" || RC=$?
}
out() { cat "$TMP/run.out"; }
nonzero() { if [ "$RC" -ne 0 ]; then _pass "$1"; else _fail "$1 (exit was 0)"; fi; TESTS_RUN=$((TESTS_RUN + 1)); }

test_installpath_wins() {
  fresh 1
  ver 6.3.0 subagent-driven-development review-package
  ver 6.4.1 subagent-driven-development review-package
  ver 6.10.0 subagent-driven-development review-package
  installed 6.4.1
  run review-package
  assert_eq 0 "$RC" "installPath: exit 0"
  assert_eq "$(cache 6.4.1)/$SDD/review-package" "$(out)" "installPath beats a higher cached version"
}
test_highest_version() {
  fresh 2
  ver 6.3.0 subagent-driven-development review-package
  ver 6.4.1 subagent-driven-development review-package sdd-workspace
  ver 6.10.0 subagent-driven-development review-package
  run review-package
  assert_eq "$(cache 6.10.0)/$SDD/review-package" "$(out)" "no installed_plugins.json: 6.10.0 beats 6.4.1 and 6.3.0"
  rm -rf "$(cache 6.10.0)"
  run review-package
  assert_eq "$(cache 6.4.1)/$SDD/review-package" "$(out)" "6.4.1 beats 6.3.0"
}
test_stale_installed() {
  fresh 3
  ver 6.3.0 subagent-driven-development review-package
  ver 6.4.1 subagent-driven-development review-package
  installed 9.9.9
  run review-package
  assert_eq "$(cache 6.4.1)/$SDD/review-package" "$(out)" "stale installPath falls back to the highest cached version"
  echo 'not json' > "$CFG/plugins/installed_plugins.json"
  run review-package
  assert_eq "$(cache 6.4.1)/$SDD/review-package" "$(out)" "garbage installed_plugins.json falls back"
}
test_skill_flag() {
  fresh 4
  ver 6.4.1 executing-plans task-start task-done
  ver 6.4.1 subagent-driven-development review-package
  installed 6.4.1
  run --skill executing-plans task-start
  assert_eq "$(cache 6.4.1)/skills/executing-plans/scripts/task-start" "$(out)" "--skill executing-plans task-start"
  run --skill=executing-plans task-done
  assert_eq "$(cache 6.4.1)/skills/executing-plans/scripts/task-done" "$(out)" "--skill=NAME form"
}
test_missing_script() {
  fresh 5
  ver 6.4.1 subagent-driven-development review-package
  installed 6.4.1
  run no-such-script
  nonzero "missing script exits non-zero"
  assert_contains "$TMP/run.err" "no-such-script" "stderr names the script"
  assert_eq "" "$(out)" "nothing on stdout"
}
test_no_superpowers() {
  fresh 6
  run review-package
  nonzero "no superpowers: non-zero"
  assert_contains "$TMP/run.err" "superpowers" "message says superpowers is missing"
  assert_contains "$TMP/run.err" "CLAUDE_CONFIG_DIR" "message hints at CLAUDE_CONFIG_DIR"
}
test_home_fallback() {
  fresh 7
  H="$TMP/home"; rm -rf "$H"
  mkdir -p "$H/.claude/plugins/cache/x/superpowers/6.4.1/$SDD"
  : > "$H/.claude/plugins/cache/x/superpowers/6.4.1/$SDD/task-brief"
  RC=0
  env -u CLAUDE_CONFIG_DIR HOME="$H" sh "$BIN" task-brief > "$TMP/run.out" 2> "$TMP/run.err" || RC=$?
  assert_eq "$H/.claude/plugins/cache/x/superpowers/6.4.1/$SDD/task-brief" "$(out)" "unset CLAUDE_CONFIG_DIR uses \$HOME/.claude"
}
test_usage() {
  fresh 8
  run
  nonzero "no name: non-zero"
}

test_multi_entries() {
  fresh 9
  ver 6.3.0 subagent-driven-development review-package
  ver 6.4.1 subagent-driven-development review-package
  ver 6.5.0 subagent-driven-development review-package
  registry "$(entry 6.5.0 project)" "$(entry 6.3.0 user)" "$(entry 6.4.1 project)"
  run review-package
  assert_eq "$(cache 6.3.0)/$SDD/review-package" "$(out)" "several entries: the user-scope entry wins"
  registry "$(entry 6.4.1 project)" "$(entry 6.5.0 project)"
  run review-package
  assert_eq "$(cache 6.4.1)/$SDD/review-package" "$(out)" "no user-scope entry: the first entry wins, not the last"
}
test_prerelease_order() {
  fresh 10
  ver 6.4.1 subagent-driven-development review-package
  ver 6.4.1-beta subagent-driven-development review-package
  ver 6.4.0 subagent-driven-development review-package
  run review-package
  assert_eq "$(cache 6.4.1)/$SDD/review-package" "$(out)" "6.4.1 ranks above 6.4.1-beta"
}
test_empty_highest() {
  fresh 11
  ver 6.4.1 subagent-driven-development review-package
  mkdir -p "$(cache 9.0.0)"
  run review-package
  assert_eq "$(cache 6.4.1)/$SDD/review-package" "$(out)" "an empty highest version folder is skipped"
}
test_space_in_config_dir() {
  fresh 12
  ver 6.4.1 subagent-driven-development review-package
  installed 6.4.1
  run review-package
  case "$CFG" in *" "*) _pass "config dir path contains a space" ; TESTS_RUN=$((TESTS_RUN + 1)) ;; *) _fail "no space in $CFG"; TESTS_RUN=$((TESTS_RUN + 1)) ;; esac
  assert_eq "$(cache 6.4.1)/$SDD/review-package" "$(out)" "registry path resolved under a config dir with a space"
}

run_tests test_installpath_wins test_highest_version test_stale_installed test_skill_flag \
  test_missing_script test_no_superpowers test_home_fallback test_usage \
  test_multi_entries test_prerelease_order test_empty_highest test_space_in_config_dir
