#!/bin/sh
# #71 T1: the gate's argv classifier (`studio-gate --classify`), the lane read
# (git top level, then the run's STUDIO_START_DIR) and the load gate in
# bin/gate-class.sh. No lock is taken and no engine runs.
# Test-only knobs exercised here: STUDIO_GATE_LOADAVG and STUDIO_GATE_PHYS_CORES
# (production: unset, the machine is read; test_load_production_defaults).
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"

unset STUDIO_START_DIR STUDIO_GATE_HELD STUDIO_GATE_LANE STUDIO_GATE_DEMOTE STUDIO_UNIT_TAG STUDIO_GATE_MINUTES STUDIO_GATE_SECONDS
mk_tmp gate_class
trap 'rm_tmp "$TMP"' EXIT

BIN="$REPO_ROOT/studios/game-dev/bin"
D="$BIN/studio-dispatch"

# gc_repo NAME — a project at $TMP/NAME ($GR): git repo, GUT files, a web-tools
# node dir with stub bins, and the lane switched on.
gc_repo() {
  GR="$TMP/$1"
  mkdir -p "$GR/tests/unit" "$GR/web-tools/tests" "$GR/web-tools/node_modules/.bin" "$GR/.studio"
  for _f in a b c d; do : > "$GR/tests/unit/$_f.gd"; done
  : > "$GR/web-tools/tests/a.test.ts"; : > "$GR/web-tools/tests/b.test.ts"
  printf '{}\n' > "$GR/web-tools/tsconfig.json"
  for _f in vitest tsc eslint; do
    printf '#!/bin/sh\nexit 0\n' > "$GR/web-tools/node_modules/.bin/$_f"
    chmod +x "$GR/web-tools/node_modules/.bin/$_f"
  done
  printf '{"engine": "godot4", "gate_short_lane": "on"}\n' > "$GR/.studio/config.json"
  ( cd "$GR" && git init -q -b main && git add tests web-tools/tests web-tools/tsconfig.json \
    && git -c user.name=t -c user.email=t@t commit -q -m i ) >/dev/null 2>&1
}

# gcl DIR CMD… — studio-gate --classify -- CMD… from DIR; the line lands in $TMP/gc.out.
gcl() {
  _dir="$1"; shift
  ( cd "$_dir" && sh "$BIN/studio-gate" --classify -- "$@" ) > "$TMP/gc.out" 2>/dev/null
}

# gcx DIR WANT MSG CMD… — assert fields 1-2 of the classification.
gcx() {
  _dir="$1"; _want="$2"; _msg="$3"; shift 3
  gcl "$_dir" "$@"
  assert_eq "$_want" "$(cut -d' ' -f1-2 "$TMP/gc.out")" "$_msg"
}

test_classify_gut_file_runs() {
  gc_repo gut
  gcx "$GR" "short godot" "one file" sh "$D" test --file tests/unit/a.gd
  gcx "$GR" "short godot" "/bin/sh form" /bin/sh "$D" test --file tests/unit/a.gd
  gcx "$GR" "short godot" "three files" sh "$D" test --file tests/unit/a.gd,tests/unit/b.gd,tests/unit/c.gd
  gcx "$GR" "exclusive godot" "four files" sh "$D" test --file tests/unit/a.gd,tests/unit/b.gd,tests/unit/c.gd,tests/unit/d.gd
  gcx "$GR" "exclusive godot" "a trailing word" sh "$D" test --file tests/unit/a.gd extra
  gcx "$GR" "exclusive godot" "an empty list" sh "$D" test --file ''
  gcx "$GR" "exclusive godot" "an empty entry" sh "$D" test --file tests/unit/a.gd,,tests/unit/b.gd
  gcx "$GR" "exclusive godot" "a trailing comma" sh "$D" test --file tests/unit/a.gd,
}

test_classify_whole_suite_and_dir() {
  gc_repo suite
  gcx "$GR" "shareable godot" "a whole suite" sh "$D" test
  gcx "$GR" "shareable godot" "a directory" sh "$D" test tests/unit
  gcx "$GR" "exclusive godot" "a file is not a directory" sh "$D" test tests/unit/a.gd
  gcx "$GR" "exclusive godot" "a missing directory" sh "$D" test tests/nope
  printf '{"engine": "godot4"}\n' > "$GR/.studio/config.json"
  gcl "$GR" sh "$D" test
  assert_eq "exclusive godot lane=off" "$(cut -d' ' -f1-3 "$TMP/gc.out")" "lane absent: the whole suite is exclusive"
  assert_eq "argv=shareable" "$(tr ' ' '\n' < "$TMP/gc.out" | grep '^argv=')" "the argv class is still shareable"
}

test_classify_dispatch_identity() {
  gc_repo ident
  mkdir -p "$TMP/ln" "$TMP/cp"
  ln -s "$D" "$TMP/ln/studio-dispatch"
  cp "$D" "$TMP/cp/studio-dispatch"
  gcx "$GR" "short godot" "a symlink to studio-dispatch" sh "$TMP/ln/studio-dispatch" test --file tests/unit/a.gd
  gcx "$GR" "exclusive godot" "a copy of studio-dispatch" sh "$TMP/cp/studio-dispatch" test --file tests/unit/a.gd
  gcx "$GR" "exclusive godot" "a missing dispatch" sh "$TMP/none/studio-dispatch" test --file tests/unit/a.gd
}

test_classify_symlink_cycle_is_bounded() {
  gc_repo cyc
  mkdir -p "$TMP/cy"
  ln -s "$TMP/cy/b" "$TMP/cy/a"
  ln -s "$TMP/cy/a" "$TMP/cy/b"
  gcx "$GR" "exclusive godot" "a 2-link cycle returns exclusive" sh "$TMP/cy/a" test --file tests/unit/a.gd
}

test_classify_non_utf8_list_four_entries() {
  gc_repo nonu
  _bad="$(printf 'tests/unit/\377.gd')"
  gcx "$GR" "exclusive godot" "four entries with a non-UTF-8 byte" sh "$D" test --file "$_bad,tests/unit/a.gd,tests/unit/b.gd,tests/unit/c.gd"
  gcx "$GR" "short godot" "three entries with a non-UTF-8 byte" sh "$D" test --file "$_bad,tests/unit/a.gd,tests/unit/b.gd"
}

test_classify_godot_who_and_spaced_paths() {
  gc_repo who
  gcx "$GR" "exclusive godot" "a studio-gate godot -- command is exclusive" godot --headless --path . -s x.gd
  mkdir -p "$TMP/sp ace/bin"
  ln -s "$D" "$TMP/sp ace/bin/studio-dispatch"
  gc_repo "sp ace"
  gcx "$GR" "short godot" "a spaced dispatch symlink and worktree" sh "$TMP/sp ace/bin/studio-dispatch" test --file tests/unit/a.gd
  assert_contains "$TMP/gc.out" " wt=$(cd "$GR" && pwd -P) " "wt keeps the space"
}

test_classify_vitest_forms() {
  gc_repo vit
  W="$GR/web-tools"
  gcx "$W" "short node" "npx" npx vitest run --minWorkers=1 --maxWorkers=2 tests/a.test.ts tests/b.test.ts
  gcx "$W" "short node" "npx --no-install" npx --no-install vitest run --minWorkers=1 --maxWorkers=1 tests/a.test.ts
  gcx "$W" "short node" "the bin form, flags in the other order" node_modules/.bin/vitest run --maxWorkers=2 --minWorkers=1 tests/a.test.ts
  gcx "$W" "short node" "the ./ bin form" ./node_modules/.bin/vitest run --minWorkers=1 --maxWorkers=2 tests/a.test.ts
  gcx "$W" "short node" "every allowed option" npx vitest run --minWorkers=1 --maxWorkers=2 --reporter=dot --silent --no-color -t 'a b' --testNamePattern=x tests/a.test.ts
}

test_classify_vitest_near_misses() {
  gc_repo vitn
  W="$GR/web-tools"
  gcx "$W" "exclusive godot" "no cap" npx vitest run tests/a.test.ts
  gcx "$W" "exclusive godot" "--maxWorkers=2 alone" npx vitest run --maxWorkers=2 tests/a.test.ts
  gcx "$W" "exclusive godot" "--minWorkers=1 alone" npx vitest run --minWorkers=1 tests/a.test.ts
  gcx "$W" "exclusive godot" "--maxWorkers=3" npx vitest run --minWorkers=1 --maxWorkers=3 tests/a.test.ts
  gcx "$W" "exclusive godot" "--minWorkers=1 twice" npx vitest run --minWorkers=1 --minWorkers=1 --maxWorkers=2 tests/a.test.ts
  gcx "$W" "exclusive godot" "two caps" npx vitest run --minWorkers=1 --maxWorkers=1 --maxWorkers=2 tests/a.test.ts
  gcx "$W" "exclusive godot" "a directory" npx vitest run --minWorkers=1 --maxWorkers=2 tests
  gcx "$W" "exclusive godot" "a glob" npx vitest run --minWorkers=1 --maxWorkers=2 'tests/*.test.ts'
  gcx "$W" "exclusive godot" "no positional" npx vitest run --minWorkers=1 --maxWorkers=2
  gcx "$W" "exclusive godot" "a missing file" npx vitest run --minWorkers=1 --maxWorkers=2 tests/zz.test.ts
  gcx "$W" "exclusive godot" "no run" npx vitest --minWorkers=1 --maxWorkers=2 tests/a.test.ts
  gcx "$W" "exclusive godot" "--watch" npx vitest run --minWorkers=1 --maxWorkers=2 --watch tests/a.test.ts
  gcx "$W" "exclusive godot" "--maxWorkers 2 (space form)" npx vitest run --minWorkers=1 --maxWorkers 2 tests/a.test.ts
  gcx "$W" "exclusive godot" "a bad reporter word" npx vitest run --minWorkers=1 --maxWorkers=2 '--reporter=a;b' tests/a.test.ts
  gcx "$GR" "exclusive godot" "sh -c from the top level" sh -c "cd web-tools && npx vitest run --minWorkers=1 --maxWorkers=2 tests/a.test.ts"
  gcx "$GR" "short node" "the direct form from the top level" npx vitest run --minWorkers=1 --maxWorkers=2 web-tools/tests/a.test.ts
}

test_classify_tsc_forms() {
  gc_repo tsc
  W="$GR/web-tools"
  gcx "$W" "short node" "tsc --noEmit" npx tsc --noEmit
  gcx "$W" "short node" "tsc -p" npx tsc --noEmit -p tsconfig.json
  gcx "$W" "short node" "tsc --pretty false" npx tsc --noEmit --pretty false
  gcx "$W" "short node" "tsc bin form" node_modules/.bin/tsc --noEmit --project tsconfig.json
  gcx "$W" "exclusive godot" "tsc alone" npx tsc
  gcx "$W" "exclusive godot" "tsc -b" npx tsc -b
  gcx "$W" "exclusive godot" "tsc --build" npx tsc --build
  gcx "$W" "exclusive godot" "tsc --watch" npx tsc --noEmit --watch
  gcx "$W" "exclusive godot" "tsc -p missing" npx tsc --noEmit -p missing.json
  gcx "$W" "exclusive godot" "tsc positional" npx tsc --noEmit src/x.ts
}

test_classify_eslint_forms() {
  gc_repo esl
  W="$GR/web-tools"
  gcx "$W" "short node" "eslint a file" npx eslint tests/a.test.ts
  gcx "$W" "short node" "eslint options" npx eslint --max-warnings 0 --format stylish tests/a.test.ts
  gcx "$W" "short node" "eslint bin form" ./node_modules/.bin/eslint tests/a.test.ts tests/b.test.ts
  gcx "$W" "exclusive godot" "eslint a directory" npx eslint tests
  gcx "$W" "exclusive godot" "eslint --fix" npx eslint --fix tests/a.test.ts
  gcx "$W" "exclusive godot" "eslint no file" npx eslint
  gcx "$W" "exclusive godot" "eslint bad max-warnings" npx eslint --max-warnings x tests/a.test.ts
}

test_classify_everything_else_is_exclusive() {
  gc_repo other
  gcx "$GR" "exclusive godot" "npm test" npm test
  gcx "$GR" "exclusive godot" "npm run build" npm run build
  gcx "$GR" "exclusive godot" "env prefix" env X=1 npx vitest run --minWorkers=1 --maxWorkers=2 web-tools/tests/a.test.ts
  gcx "$GR" "exclusive godot" "merge.sh" ./merge.sh 12
  gcx "$GR" "exclusive godot" "run-tests.sh" .github/scripts/run-tests.sh
  gcx "$GR" "exclusive godot" "studio-dispatch run" sh "$D" run --seconds 10
  gcx "$GR" "exclusive godot" "bare Godot" Godot --headless --path . -s x.gd
  gcx "$GR" "exclusive godot" "sh -c true" sh -c true
  gcx "$GR" "exclusive godot" "an unknown command" foo
}

test_classify_reads_lane_from_toplevel() {
  gc_repo top
  gcl "$GR/web-tools" npx vitest run --minWorkers=1 --maxWorkers=2 tests/a.test.ts
  assert_eq "short node" "$(cut -d' ' -f1-2 "$TMP/gc.out")" "a subdirectory cwd classifies"
  assert_contains "$TMP/gc.out" " lane=on " "the lane is read at the git top level"
  assert_contains "$TMP/gc.out" " wt=$(cd "$GR" && pwd -P) " "wt is the git top level"
}

test_classify_run_fallback() {
  gc_repo fb
  git -C "$GR" worktree add -q -b story "$GR-s" >/dev/null 2>&1
  rm -f "$GR-s/.studio/config.json"
  mkdir -p "$GR-s/.studio"
  ( STUDIO_START_DIR="$GR"; export STUDIO_START_DIR; gcl "$GR-s" sh "$D" test --file tests/unit/a.gd; cat "$TMP/gc.out" > "$TMP/gc.fb" )
  assert_contains "$TMP/gc.fb" " lane=on " "no config here: the run's lane applies"
  assert_eq "short godot" "$(cut -d' ' -f1-2 "$TMP/gc.fb")" "and the class is the effective one"
  printf '{"gate_short_lane": "off"}\n' > "$GR-s/.studio/config.json"
  ( STUDIO_START_DIR="$GR"; export STUDIO_START_DIR; gcl "$GR-s" sh "$D" test --file tests/unit/a.gd; cat "$TMP/gc.out" > "$TMP/gc.fb" )
  assert_contains "$TMP/gc.fb" " lane=off " "the worktree's own off wins"
  rm -f "$GR-s/.studio/config.json"
  gcl "$GR-s" sh "$D" test --file tests/unit/a.gd
  assert_contains "$TMP/gc.out" " lane=off " "STUDIO_START_DIR unset: lane off"
}

test_classify_minified_config() {
  gc_repo mini
  printf '{"engine":"godot4","gate_short_lane":"on"}' > "$GR/.studio/config.json"
  gcl "$GR" sh "$D" test
  assert_contains "$TMP/gc.out" " lane=on " "a one-line config"
  printf '{\n  "gate_short_lane" : "on"\n}\n' > "$GR/.studio/config.json"
  gcl "$GR" sh "$D" test
  assert_contains "$TMP/gc.out" " lane=on " "a space before the colon"
}

# lo CORES LOAD — gate_load_ok with both seams set; prints "<rc> <output>".
lo() {
  (
    . "$BIN/gate-class.sh"
    STUDIO_GATE_PHYS_CORES="$1"; STUDIO_GATE_LOADAVG="$2"; export STUDIO_GATE_PHYS_CORES STUDIO_GATE_LOADAVG
    _o="$(gate_load_ok)"; _rc=$?
    printf '%s %s\n' "$_rc" "$_o"
  )
}

test_load_threshold_from_physical_cores() {
  assert_eq "0 5/8" "$(lo 4 5)" "4 cores, load 5: admitted at 5/8"
  assert_eq "1 5/4" "$(lo 2 5)" "2 cores, load 5: refused at 5/4"
  assert_eq "1 99/8" "$(lo 4 99)" "load 99 is refused"
  assert_eq "0 0/8" "$(lo 4 0)" "load 0 is admitted"
  assert_eq "1 8/8" "$(lo 4 8)" "load at the threshold is refused"
  assert_eq "0 7.99/8" "$(lo 4 7.99)" "load just under the threshold is admitted"
}

test_load_unreadable_refuses() {
  assert_eq "1 ?/8" "$(lo 4 abc)" "an unreadable load refuses"
  assert_eq "1 ?/8" "$(lo 4 '')" "an empty load refuses"
  assert_eq "1 5/?" "$(lo 0 5)" "0 cores refuses"
  assert_eq "1 5/?" "$(lo x 5)" "non-numeric cores refuses"
}

# lp ENV… — gate_load1 and gate_load_peak under the given env words; prints "<l1rc>:<l1> <peakrc>:<peak>".
lp() {
  (
    unset STUDIO_GATE_LOADAVG STUDIO_GATE_LOADAVG_FILE
    for _a in "$@"; do export "$_a"; done
    . "$BIN/gate-class.sh"
    _l="$(gate_load1)"; _lr=$?; _p="$(gate_load_peak)"; _pr=$?
    printf '%s:%s %s:%s\n' "$_lr" "$_l" "$_pr" "$_p"
  )
}

test_load_file_seam_and_peak() {
  assert_eq "0:5 0:5" "$(lp STUDIO_GATE_LOADAVG=5)" "the value seam gives one value for both averages"
  printf '12.5\nignored\n' > "$TMP/load"
  assert_eq "0:12.5 0:12.5" "$(lp STUDIO_GATE_LOADAVG_FILE="$TMP/load" STUDIO_GATE_LOADAVG=1)" "the file seam wins and reads its first line"
  printf '3\n' > "$TMP/load"
  assert_eq "0:3 0:3" "$(lp STUDIO_GATE_LOADAVG_FILE="$TMP/load")" "the file is read again on every reading"
  assert_eq "1: 1:" "$(lp STUDIO_GATE_LOADAVG_FILE="$TMP/no-such-load")" "a missing load file is unreadable"
  assert_eq "1: 1:" "$(lp STUDIO_GATE_LOADAVG=abc)" "a non-numeric load is unreadable"
  case "$(uname -s)" in
    Darwin|Linux)
      _r="$(lp)"
      assert_eq 1 "$(printf '%s\n' "$_r" | grep -Ec '^0:[0-9.]+ 0:[0-9.]+$')" "the machine's averages read ($_r)" ;;
  esac
}

test_load_production_defaults() {
  _pd="$(
    unset STUDIO_GATE_PHYS_CORES STUDIO_GATE_LOADAVG
    . "$BIN/gate-class.sh"
    _c="$(gate_phys_cores)"; _crc=$?
    _l="$(gate_load1)"; _lrc=$?
    printf '%s|%s|%s|%s\n' "$_crc" "$_c" "$_lrc" "$_l"
  )"
  _crc="${_pd%%|*}"; _r="${_pd#*|}"; _c="${_r%%|*}"; _r="${_r#*|}"; _lrc="${_r%%|*}"; _l="${_r#*|}"
  case "$(uname -s)" in
    Darwin)
      assert_eq "$(sysctl -n hw.physicalcpu)" "$_c" "Darwin cores are hw.physicalcpu"
      assert_eq "0" "$_lrc" "Darwin load reads"
      assert_eq "1" "$(printf '%s\n' "$_l" | grep -Ec '^[0-9][0-9]*(\.[0-9]*)?$')" "Darwin load is a decimal" ;;
    Linux)
      assert_eq "$(awk -F: '/^physical id/ { p = $2 } /^core id/ { print p "," $2 }' /proc/cpuinfo | sort -u | wc -l | tr -d ' ')" "$_c" "Linux cores are the distinct (physical id, core id) pairs"
      assert_eq "0" "$_lrc" "Linux load reads"
      assert_eq "1" "$(printf '%s\n' "$_l" | grep -Ec '^[0-9][0-9]*(\.[0-9]*)?$')" "Linux load is a decimal" ;;
    *)
      assert_eq "1" "$_crc" "an unknown OS: cores exit 1"
      assert_eq "1" "$_lrc" "an unknown OS: load exits 1" ;;
  esac
}

# nw CORES [CONFIG_JSON] — gate_node_workers with the cores seam set (CORES "-" =
# unset, "" = set empty) from a bare project dir; prints "<rc> <output> <stderr>".
nw() {
  _nwd="$TMP/nw"; rm -rf "$_nwd"; mkdir -p "$_nwd/.studio"
  [ -z "${2:-}" ] || printf '%s\n' "$2" > "$_nwd/.studio/config.json"
  (
    cd "$_nwd" || exit 9
    . "$BIN/gate-class.sh"
    if [ "$1" != - ]; then STUDIO_GATE_PHYS_CORES="$1"; export STUDIO_GATE_PHYS_CORES; fi
    _o="$(gate_node_workers 2> "$_nwd/err")"; _rc=$?
    printf '%s %s %s\n' "$_rc" "$_o" "$(cat "$_nwd/err")"
  )
}

test_node_workers_auto() {
  assert_eq "0 2 " "$(nw 4)" "4 cores: 2 workers"
  assert_eq "0 6 " "$(nw 12)" "12 cores: 6 workers"
  assert_eq "0 2 " "$(nw 2)" "2 cores: floor of 2"
  assert_eq "0 2 " "$(nw 1)" "1 core: floor of 2"
  assert_eq "0 2 " "$(nw '')" "unreadable cores (set, empty): 2"
}

test_node_workers_config() {
  assert_eq "0 8 " "$(nw 12 '{"node_workers": 8}')" "a number sets it"
  assert_eq "0 8 " "$(nw 12 '{"node_workers": "8"}')" "a quoted number sets it"
  assert_eq "0 1 " "$(nw 12 '{"node_workers": 1}')" "1 is the floor"
  assert_eq "0 32 " "$(nw 4 '{"node_workers": 32}')" "32 is the cap"
  assert_eq "0 6 " "$(nw 12 '{"node_workers": "auto"}')" "auto is the machine's value"
  assert_eq "0 6 " "$(nw 12 '{"engine": "godot4"}')" "absent is auto"
  assert_eq "1  gate: node_workers must be auto or 1-32, got 33" "$(nw 12 '{"node_workers": 33}')" "33 is refused"
  assert_eq "1  gate: node_workers must be auto or 1-32, got 0" "$(nw 12 '{"node_workers": 0}')" "0 is refused"
  assert_eq "1  gate: node_workers must be auto or 1-32, got many" "$(nw 12 '{"node_workers": "many"}')" "a word is refused"
}

test_classify_takes_no_lock() {
  GP="$TMP/gate-nolock"; mkdir -p "$GP"
  ( cd "$GP" && git init -q -b main && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m i && sh "$BIN/studio-state" init ) >/dev/null 2>&1
  gcl "$GP" sh "$D" test
  assert_eq "exclusive godot" "$(cut -d' ' -f1-2 "$TMP/gc.out")" "a project without the lane classifies"
  assert_missing "$GP/.studio/gate.lock" "no gate.lock"
  assert_missing "$GP/.studio/gate.short" "no gate.short"
  assert_missing "$GP/.studio/gate.wantx" "no gate.wantx"
  assert_missing "$GP/.studio/gate.times" "no gate.times"
}

test_classify_needs_no_studio_dir() {
  mkdir -p "$TMP/bare"
  gcl "$TMP/bare" foo
  assert_eq "exclusive godot lane=off" "$(cut -d' ' -f1-3 "$TMP/gc.out")" "a bare directory classifies"
}

test_classify_usage() {
  mkdir -p "$TMP/us"
  assert_status 2 "--classify alone exits 2" -- sh -c "cd '$TMP/us' && sh '$BIN/studio-gate' --classify"
  assert_status 2 "--classify -- alone exits 2" -- sh -c "cd '$TMP/us' && sh '$BIN/studio-gate' --classify --"
  ( cd "$TMP/us" && sh "$BIN/studio-gate" --classify ) > /dev/null 2> "$TMP/us.err"
  assert_contains "$TMP/us.err" "usage: studio-gate --classify -- <cmd> \[args...\]" "the usage line"
  ( cd "$TMP/us" && sh "$BIN/studio-gate" --classify -- ) > /dev/null 2> "$TMP/us.err"
  assert_contains "$TMP/us.err" "usage: studio-gate --classify -- <cmd> \[args...\]" "the usage line after --"
}

run_tests test_classify_gut_file_runs test_classify_whole_suite_and_dir test_classify_dispatch_identity \
  test_classify_symlink_cycle_is_bounded test_classify_non_utf8_list_four_entries test_classify_godot_who_and_spaced_paths \
  test_classify_vitest_forms test_classify_vitest_near_misses test_classify_tsc_forms test_classify_eslint_forms \
  test_classify_everything_else_is_exclusive test_classify_reads_lane_from_toplevel test_classify_run_fallback \
  test_classify_minified_config test_load_threshold_from_physical_cores test_load_unreadable_refuses test_load_file_seam_and_peak \
  test_load_production_defaults test_node_workers_auto test_node_workers_config test_classify_takes_no_lock test_classify_needs_no_studio_dir test_classify_usage
