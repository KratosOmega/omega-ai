#!/bin/sh
# The studio-* verbs and the Godot adapter, exercised with a stub Godot so no
# engine is needed. Every project is a fresh temporary directory.
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"

STUDIO="$REPO_ROOT/studios/game-dev"
BIN="$STUDIO/bin"
# Physical path: the adapter scripts resolve the project with pwd -P, so
# assertions that quote $TMP must use the same spelling (/var -> /private/var on macOS).
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

# A stub Godot. It records its arguments, honours --path and
# -gjunit_xml_file=res://… by writing a JUnit file into the project, prints a
# SCRIPT ERROR line when STUB_SCRIPT_ERROR=1, sleeps STUB_SLEEP seconds, and
# exits 1 when STUB_FAILS is greater than 0 (as GUT does with -gexit).
mkdir -p "$TMP/stub"
cat > "$TMP/stub/godot" <<'STUB'
#!/bin/sh
proj="."; xml=""; want=0
printf 'stub godot args: %s\n' "$*"
for a in "$@"; do
  if [ "$want" = 1 ]; then proj="$a"; want=0; continue; fi
  case "$a" in
    --path) want=1 ;;
    -gjunit_xml_file=res://*) xml="${a#-gjunit_xml_file=res://}" ;;
  esac
done
if [ -n "$xml" ]; then
  fails="${STUB_FAILS:-0}"
  mkdir -p "$(dirname "$proj/$xml")"
  {
    printf '<testsuites tests="2" failures="%s">\n' "$fails"
    printf '<testsuite name="res://tests/unit/test_dash.gd">\n'
    printf '<testcase name="test_cooldown" classname="test_dash"></testcase>\n'
    if [ "$fails" -gt 0 ]; then
      printf '<testcase name="test_distance" classname="test_dash"><failure message="expected 3 got 2"/></testcase>\n'
    else
      printf '<testcase name="test_distance" classname="test_dash"></testcase>\n'
    fi
    printf '</testsuite>\n</testsuites>\n'
  } > "$proj/$xml"
fi
if [ "${STUB_SCRIPT_ERROR:-0}" = 1 ]; then
  echo "SCRIPT ERROR: Invalid call. Nonexistent function 'dash' in base 'Node2D'."
fi
echo "Godot Engine v4.3.stable (stub)"
sleep "${STUB_SLEEP:-0}"
[ "${STUB_FAILS:-0}" -eq 0 ]
STUB
chmod +x "$TMP/stub/godot"
GODOT_STUB="$TMP/stub/godot"

# fresh_project NAME — a project directory with project.godot; prints its path.
fresh_project() {
  P="$TMP/proj-$1"
  mkdir -p "$P"
  printf '[application]\nconfig/name="Stub"\n' > "$P/project.godot"
  printf '%s\n' "$P"
}

# with_gut DIR — pretend GUT is installed.
with_gut() {
  mkdir -p "$1/addons/gut"
  : > "$1/addons/gut/gut_cmdln.gd"
}

# verb DIR NAME ARGS… — run bin/NAME inside DIR with the studio root and the
# stub Godot set. Output lands in $TMP/out, exit status in $TMP/status.
verb() {
  _dir="$1"; _name="$2"; shift 2
  status=0
  ( cd "$_dir" && OMEGA_STUDIO_ROOT="$STUDIO" GODOT_PATH="$GODOT_STUB" \
      STUB_FAILS="${STUB_FAILS:-0}" STUB_SCRIPT_ERROR="${STUB_SCRIPT_ERROR:-0}" STUB_SLEEP="${STUB_SLEEP:-0}" \
      sh "$BIN/$_name" "$@" ) > "$TMP/out" 2>&1 || status=$?
  printf '%s\n' "$status" > "$TMP/status"
}

test_dispatch_rejects_unknown_engine() {
  P="$(fresh_project unknown-engine)"
  mkdir -p "$P/.studio"
  printf '{ "engine": "unity6" }\n' > "$P/.studio/config.json"
  verb "$P" studio-test
  assert_eq "2" "$(cat "$TMP/status")" "an engine with no adapter exits 2"
  assert_contains "$TMP/out" "no adapter for engine unity6" "the message names the engine"
  assert_contains "$TMP/out" "engines/unity/" "the message names the directory looked for"
}

test_dispatch_needs_a_studio_root() {
  P="$(fresh_project no-root)"
  status=0
  ( cd "$P" && OMEGA_STUDIO_ROOT="$TMP/nowhere" sh "$BIN/studio-test" ) > "$TMP/out" 2>&1 || status=$?
  assert_eq "2" "$(printf '%s' "$status")" "a missing studio root exits 2"
  assert_contains "$TMP/out" "OMEGA_STUDIO_ROOT" "the message names the variable to set"
}

test_resolve_honours_godot_path() {
  out="$(GODOT_PATH="$GODOT_STUB" sh "$STUDIO/engines/godot/resolve.sh")"
  assert_eq "$GODOT_STUB" "$out" "GODOT_PATH wins when executable"
}

test_resolve_ignores_a_non_executable_godot_path() {
  : > "$TMP/not-exec"
  mkdir -p "$TMP/no-apps"
  status=0
  out="$(GODOT_PATH="$TMP/not-exec" GODOT_APP_DIR="$TMP/no-apps" PATH="/usr/bin:/bin" \
    sh "$STUDIO/engines/godot/resolve.sh" 2>"$TMP/err")" || status=$?
  assert_eq "2" "$status" "a non-executable GODOT_PATH does not resolve"
  assert_contains "$TMP/err" "no Godot binary found; set GODOT_PATH" "the hint names GODOT_PATH"
}

test_resolve_finds_an_app_bundle() {
  mkdir -p "$TMP/apps/Godot_mono.app/Contents/MacOS"
  cp "$GODOT_STUB" "$TMP/apps/Godot_mono.app/Contents/MacOS/Godot"
  out="$(GODOT_PATH="" GODOT_APP_DIR="$TMP/apps" PATH="/usr/bin:/bin" sh "$STUDIO/engines/godot/resolve.sh")"
  assert_eq "$TMP/apps/Godot_mono.app/Contents/MacOS/Godot" "$out" "an app bundle under GODOT_APP_DIR resolves"
}

test_resolve_finds_godot_on_path() {
  mkdir -p "$TMP/onpath" "$TMP/no-apps"
  cp "$GODOT_STUB" "$TMP/onpath/godot"
  out="$(GODOT_PATH="" GODOT_APP_DIR="$TMP/no-apps" PATH="$TMP/onpath:/usr/bin:/bin" sh "$STUDIO/engines/godot/resolve.sh")"
  assert_eq "$TMP/onpath/godot" "$out" "godot on PATH resolves last"
}

test_guide_has_an_install_line() {
  assert_contains "$STUDIO/engines/godot/GUIDE.md" "^Install: git clone --depth 1" "GUIDE.md carries the GUT install command"
  assert_contains "$STUDIO/engines/godot/GUIDE.md" "addons/gut" "the install command lands GUT in addons/gut"
}

test_test_needs_a_project() {
  mkdir -p "$TMP/not-a-project"
  verb "$TMP/not-a-project" studio-test
  assert_eq "1" "$(cat "$TMP/status")" "a directory without project.godot exits 1"
  assert_contains "$TMP/out" "no project.godot" "the message says what is missing"
}

test_test_falls_back_to_studio_json() {
  P="$(fresh_project defaults)"
  with_gut "$P"
  verb "$P" studio-test
  assert_eq "0" "$(cat "$TMP/status")" "no .studio/config.json falls back to studio.json's engine"
}

test_test_exits_3_without_gut() {
  P="$(fresh_project nogut)"
  verb "$P" studio-test
  assert_eq "3" "$(cat "$TMP/status")" "missing GUT exits 3"
  assert_contains "$TMP/out" "addons/gut/gut_cmdln.gd" "the message names the missing file"
  assert_contains "$TMP/out" "git clone --depth 1" "the message prints the install command from GUIDE.md"
}

test_test_exits_2_without_engine() {
  P="$(fresh_project noengine)"
  with_gut "$P"
  mkdir -p "$TMP/no-apps"
  status=0
  ( cd "$P" && OMEGA_STUDIO_ROOT="$STUDIO" GODOT_PATH="" GODOT_APP_DIR="$TMP/no-apps" PATH="/usr/bin:/bin" \
      sh "$BIN/studio-test" ) > "$TMP/out" 2>&1 || status=$?
  assert_eq "2" "$status" "no Godot binary exits 2"
  assert_contains "$TMP/out" "set GODOT_PATH" "the hint names GODOT_PATH"
}

test_test_passes_and_reports() {
  P="$(fresh_project pass)"
  with_gut "$P"
  verb "$P" studio-test
  assert_eq "0" "$(cat "$TMP/status")" "a green suite exits 0"
  assert_contains "$TMP/out" "^studio-test: 2 passed, 0 failed" "summary line counts from the JUnit file"
  xml="$(ls "$P"/.studio/reports/test-*.xml 2>/dev/null | head -n 1)"
  assert_file "$xml" "JUnit XML lands in .studio/reports"
  log="$(ls "$P"/.studio/reports/test-*.log 2>/dev/null | head -n 1)"
  assert_file "$log" "the engine log lands in .studio/reports"
  assert_contains "$log" "\-gdir=res://tests" "the whole suite runs from res://tests"
  assert_contains "$log" "\-ginclude_subdirs" "subdirectories are included"
  assert_contains "$log" "\-gexit" "GUT exits when done"
  assert_contains "$log" "\-\-headless" "the run is headless"
}

test_test_reports_failures() {
  P="$(fresh_project fail)"
  with_gut "$P"
  STUB_FAILS=1 verb "$P" studio-test
  assert_eq "1" "$(cat "$TMP/status")" "a failing suite exits 1"
  assert_contains "$TMP/out" "^studio-test: 1 passed, 1 failed" "summary line counts the failure"
  assert_contains "$TMP/out" "^  FAIL test_distance" "failing test names are echoed"
}

test_test_targets_a_file() {
  P="$(fresh_project file)"
  with_gut "$P"
  mkdir -p "$P/tests/unit"
  : > "$P/tests/unit/test_dash.gd"
  verb "$P" studio-test tests/unit/test_dash.gd
  log="$(ls "$P"/.studio/reports/test-*.log | head -n 1)"
  assert_contains "$log" "\-gtest=res://tests/unit/test_dash.gd" "a file argument runs that test file"
  assert_not_contains "$log" "\-gdir=" "a file argument does not also pass -gdir"
}

test_test_targets_a_directory() {
  P="$(fresh_project dir)"
  with_gut "$P"
  mkdir -p "$P/tests/integration"
  verb "$P" studio-test tests/integration
  log="$(ls "$P"/.studio/reports/test-*.log | head -n 1)"
  assert_contains "$log" "\-gdir=res://tests/integration" "a directory argument runs that directory"
}

test_test_imports_when_dot_godot_is_absent() {
  P="$(fresh_project import)"
  with_gut "$P"
  verb "$P" studio-test
  log="$(ls "$P"/.studio/reports/test-*.log | head -n 1)"
  assert_contains "$log" "^stub godot args: --headless --path $P --import$" "a project without .godot/ is imported before the suite runs"
  P="$(fresh_project imported)"
  with_gut "$P"
  mkdir -p "$P/.godot"
  verb "$P" studio-test
  log="$(ls "$P"/.studio/reports/test-*.log | head -n 1)"
  assert_not_contains "$log" "\-\-import" "a project with .godot/ is not imported again"
}

test_run_clean() {
  P="$(fresh_project run-clean)"
  verb "$P" studio-run --seconds 1
  assert_eq "0" "$(cat "$TMP/status")" "a clean run exits 0"
  assert_contains "$TMP/out" "^studio-run: clean" "a clean run says so"
  log="$(ls "$P"/.studio/reports/run-*.log | head -n 1)"
  assert_file "$log" "the run log lands in .studio/reports"
  assert_contains "$log" "\-\-headless" "the default run is headless"
  assert_contains "$log" "\-\-path $P" "the run targets the project"
}

test_run_detects_script_errors() {
  P="$(fresh_project run-error)"
  mkdir -p "$P/.godot"   # already imported; the stub prints its error line on an import run too
  STUB_SCRIPT_ERROR=1 verb "$P" studio-run --seconds 1
  assert_eq "1" "$(cat "$TMP/status")" "a SCRIPT ERROR line exits 1"
  assert_eq "1" "$(head -n 1 "$TMP/out" | grep -c 'SCRIPT ERROR')" "error lines are echoed first"
  assert_contains "$TMP/out" "^studio-run: 1 error line" "the summary counts error lines"
}

test_run_passes_scene_and_windowed() {
  P="$(fresh_project run-scene)"
  mkdir -p "$P/.godot"   # already imported; an import run is always headless
  verb "$P" studio-run --scene res://levels/test_dash.tscn --seconds 1 --windowed
  log="$(ls "$P"/.studio/reports/run-*.log | head -n 1)"
  assert_contains "$log" "res://levels/test_dash.tscn" "the scene is passed to the engine"
  assert_not_contains "$log" "\-\-headless" "--windowed drops --headless"
}

test_run_terminates_a_long_process() {
  P="$(fresh_project run-long)"
  mkdir -p "$P/.godot"   # already imported; the stub sleeps on an import run too
  start="$(date +%s)"
  STUB_SLEEP=30 verb "$P" studio-run --seconds 1
  elapsed=$(( $(date +%s) - start ))
  assert_eq "0" "$(cat "$TMP/status")" "a process that outlives --seconds is not an error"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "$elapsed" -lt 10 ]; then _pass "the engine is terminated after --seconds"; else _fail "the engine is terminated after --seconds (took ${elapsed}s)"; fi
}

test_run_rejects_bad_options() {
  P="$(fresh_project run-opts)"
  verb "$P" studio-run --frames 3
  assert_eq "1" "$(cat "$TMP/status")" "an unknown option exits 1"
  verb "$P" studio-run --seconds
  assert_eq "1" "$(cat "$TMP/status")" "a missing option value exits 1"
}

test_run_traps_signals_to_avoid_orphaning_the_child() {
  assert_contains "$STUDIO/engines/godot/run.sh" "trap 'kill -TERM \"\$pid\"" "run.sh installs a trap that terminates the backgrounded engine on interrupt"
  assert_contains "$STUDIO/engines/godot/run.sh" "INT TERM HUP" "the trap covers INT, TERM, and HUP"
  assert_contains "$STUDIO/engines/godot/run.sh" "trap - INT TERM HUP" "the trap is cleared after a normal wait"
}

test_run_imports_when_dot_godot_is_absent() {
  P="$(fresh_project run-import)"
  verb "$P" studio-run --seconds 1
  log="$(ls "$P"/.studio/reports/run-*.log | head -n 1)"
  assert_contains "$log" "^stub godot args: --headless --path $P --import$" "a project without .godot/ is imported before the run"
  P="$(fresh_project run-imported)"
  mkdir -p "$P/.godot"
  verb "$P" studio-run --seconds 1
  log="$(ls "$P"/.studio/reports/run-*.log | head -n 1)"
  assert_not_contains "$log" "\-\-import" "a project with .godot/ is not imported again"
}

# lint_stubs DIR — put recording stubs for gdlint and gdformat in DIR. Each
# appends its arguments to DIR/calls and exits with $STUB_LINT_STATUS.
lint_stubs() {
  mkdir -p "$1"
  for tool in gdlint gdformat; do
    cat > "$1/$tool" <<STUB
#!/bin/sh
printf '$tool %s\n' "\$*" >> "$1/calls"
exit "\${STUB_LINT_STATUS:-0}"
STUB
    chmod +x "$1/$tool"
  done
}

test_lint_needs_a_project() {
  mkdir -p "$TMP/not-a-project-for-lint"
  lint_stubs "$TMP/lintstubs0"
  status=0
  ( cd "$TMP/not-a-project-for-lint" && OMEGA_STUDIO_ROOT="$STUDIO" PATH="$TMP/lintstubs0:/usr/bin:/bin" \
      sh "$BIN/studio-lint" ) > "$TMP/out" 2>&1 || status=$?
  assert_eq "1" "$status" "a directory without project.godot exits 1, not 3"
  assert_contains "$TMP/out" "no project.godot" "the message says what is missing"
}

test_lint_exits_3_without_gdtoolkit() {
  P="$(fresh_project lint-none)"
  status=0
  ( cd "$P" && OMEGA_STUDIO_ROOT="$STUDIO" PATH="/usr/bin:/bin" sh "$BIN/studio-lint" ) > "$TMP/out" 2>&1 || status=$?
  assert_eq "3" "$status" "no gdlint or gdformat exits 3"
  assert_contains "$TMP/out" 'pip install "gdtoolkit==4.\*"' "the hint prints the pip install command"
}

test_lint_runs_both_tools_over_gd_files() {
  P="$(fresh_project lint-run)"
  mkdir -p "$P/src/player" "$P/addons/gut" "$P/src/my scripts"
  : > "$P/src/player/dash.gd"
  : > "$P/addons/gut/gut.gd"
  : > "$P/src/my scripts/a.gd"
  lint_stubs "$TMP/lintstubs"
  status=0
  ( cd "$P" && OMEGA_STUDIO_ROOT="$STUDIO" PATH="$TMP/lintstubs:/usr/bin:/bin" sh "$BIN/studio-lint" ) > "$TMP/out" 2>&1 || status=$?
  assert_eq "0" "$status" "clean stubs exit 0"
  assert_contains "$TMP/lintstubs/calls" "^gdlint .*src/player/dash.gd" "gdlint sees project scripts"
  assert_contains "$TMP/lintstubs/calls" "^gdformat --check .*src/player/dash.gd" "gdformat runs in check mode"
  assert_not_contains "$TMP/lintstubs/calls" "addons/gut" "addons are not linted"
  assert_contains "$TMP/lintstubs/calls" "src/my scripts/a.gd" "a .gd path with a space is passed whole, not word-split"
}

test_lint_reports_findings() {
  P="$(fresh_project lint-fail)"
  mkdir -p "$P/src"
  : > "$P/src/a.gd"
  lint_stubs "$TMP/lintstubs2"
  status=0
  ( cd "$P" && OMEGA_STUDIO_ROOT="$STUDIO" PATH="$TMP/lintstubs2:/usr/bin:/bin" STUB_LINT_STATUS=1 sh "$BIN/studio-lint" ) > "$TMP/out" 2>&1 || status=$?
  assert_eq "1" "$status" "findings exit 1"
}

test_lint_with_no_scripts_is_clean() {
  P="$(fresh_project lint-empty)"
  lint_stubs "$TMP/lintstubs3"
  status=0
  ( cd "$P" && OMEGA_STUDIO_ROOT="$STUDIO" PATH="$TMP/lintstubs3:/usr/bin:/bin" sh "$BIN/studio-lint" ) > "$TMP/out" 2>&1 || status=$?
  assert_eq "0" "$status" "a project with no .gd files is clean"
  assert_contains "$TMP/out" "no .gd files" "and says so"
}

# ---- studio-gate: one test or gate run at a time per project ----
GATE="$BIN/studio-gate"
gate_proj() { GP="$TMP/gate-$1"; mkdir -p "$GP"; ( cd "$GP" && git init -q -b main && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m i && sh "$BIN/studio-state" init ) >/dev/null 2>&1; }

test_gate_no_overlap() {
  gate_proj overlap
  rm -f "$TMP/iv"
  for i in 1 2 3; do
    ( cd "$GP" && sh "$GATE" t$i -- sh -c "echo s \$(date +%s) >> '$TMP/iv'; sleep 2; echo e \$(date +%s) >> '$TMP/iv'" ) 2>/dev/null &
  done
  wait
  # Intervals in order s e s e s e: no s follows an s.
  assert_eq "s e s e s e" "$(awk '{printf "%s%s", sep, $1; sep=" "}' "$TMP/iv")" "three holders never overlap"
  assert_missing "$GP/.studio/gate.lock" "the lock is released after the last holder"
}
test_gate_status_and_held() {
  gate_proj held
  st=0; ( cd "$GP" && sh "$GATE" x -- sh -c 'exit 7' ) 2>/dev/null || st=$?
  assert_eq 7 "$st" "the child's exit status is passed through"
  ( cd "$GP" && sh "$GATE" outer -- sh -c "sh '$GATE' inner -- sh -c 'echo \$STUDIO_GATE_HELD'" ) > "$TMP/nest" 2>&1
  assert_eq 1 "$(grep -c '^[0-9][0-9]*$' "$TMP/nest")" "a holder's child runs without re-taking the lock"
  assert_not_contains "$TMP/nest" "gate: waiting" "the nested call never waits"
  assert_status 2 "no -- is usage" -- sh "$GATE" who
  assert_status 2 "no command is usage" -- sh "$GATE" who --
}
test_gate_stale_reclaim_race() {
  gate_proj stale
  rm -f "$TMP/sr"
  mkdir -p "$GP/.studio/gate.lock"; echo 999999 > "$GP/.studio/gate.lock/pid"; echo dead > "$GP/.studio/gate.lock/who"
  ( cd "$GP" && sh "$GATE" a -- sh -c "echo s >> '$TMP/sr'; sleep 1; echo e >> '$TMP/sr'" ) 2>/dev/null &
  ( cd "$GP" && sh "$GATE" b -- sh -c "echo s >> '$TMP/sr'; sleep 1; echo e >> '$TMP/sr'" ) 2>/dev/null &
  wait
  assert_eq "s e s e" "$(tr '\n' ' ' < "$TMP/sr" | sed 's/ $//')" "a dead holder is reclaimed once; the two do not overlap"
}
test_gate_waiting_message() {
  gate_proj msg
  ( cd "$GP" && sh "$GATE" first -- sleep 3 ) 2>/dev/null &
  sleep 1
  ( cd "$GP" && sh "$GATE" second -- true ) 2> "$TMP/gm"
  wait
  assert_contains "$TMP/gm" "^gate: waiting for first" "a waiter names the holder"
}
test_gate_records_pid_and_who() {
  gate_proj files
  ( cd "$GP" && sh "$GATE" me -- sh -c "cp .studio/gate.lock/who '$TMP/gwho'; cp .studio/gate.lock/pid '$TMP/gpid'; echo \$STUDIO_GATE_HELD > '$TMP/ghold'" ) 2>/dev/null
  assert_eq me "$(cat "$TMP/gwho")" "the lock names its holder"
  assert_eq "$(cat "$TMP/gpid")" "$(cat "$TMP/ghold")" "STUDIO_GATE_HELD is the lock's pid"
  assert_eq "" "${STUDIO_GATE_HELD:-}" "the hold is not exported to the caller"
}
test_gate_without_a_project_just_runs() {
  mkdir -p "$TMP/gate-bare"
  st=0; ( cd "$TMP/gate-bare" && sh "$GATE" w -- sh -c 'exit 5' ) 2>/dev/null || st=$?
  assert_eq 5 "$st" "outside a .studio project the command just runs"
}
test_gate_signal_waits_for_child_then_releases() {
  gate_proj sig
  rm -f "$TMP/gsigpid"
  ( cd "$GP" && sh "$GATE" sig -- sh -c "echo \$\$ > '$TMP/gsigpid'; exec sleep 30" ) >/dev/null 2>&1 &
  _i=0; while [ ! -s "$TMP/gsigpid" ] && [ "$_i" -lt 50 ]; do sleep 0.2; _i=$((_i + 1)); done
  _gp="$(cat "$GP/.studio/gate.lock/pid")"
  _cp="$(cat "$TMP/gsigpid")"
  kill -TERM "$_gp"
  wait
  _alive=no; kill -0 "$_cp" 2>/dev/null && _alive=yes
  [ "$_alive" = yes ] && kill -KILL "$_cp" 2>/dev/null
  assert_eq no "$_alive" "TERM to studio-gate reaches the child"
  assert_missing "$GP/.studio/gate.lock" "the lock is gone once the child is"
}
# Three contenders on a dead holder's lock. Each cmd marks "s <pid>" and
# "e <pid>"; an s while another cmd is open means two ran at once. A slow `mv`
# on PATH (1 s before it acts) and staggered starts open the old race window:
# a reads the dead pid and reclaims; b reads the same dead pid before a's mv
# lands, so b's mv moves a's live lock aside; c then finds no lock and runs.
test_gate_three_reclaimers_never_overlap() {
  gate_proj three
  rm -f "$TMP/g3"
  mkdir -p "$TMP/slowmv"
  printf '#!/bin/sh\nsleep 1\nexec /bin/mv "$@"\n' > "$TMP/slowmv/mv"; chmod +x "$TMP/slowmv/mv"
  mkdir -p "$GP/.studio/gate.lock"; echo 999999 > "$GP/.studio/gate.lock/pid"
  for _w in a b c; do
    case "$_w" in b) sleep 0.6 ;; c) sleep 1.3 ;; esac
    ( cd "$GP" && PATH="$TMP/slowmv:$PATH" sh "$GATE" $_w -- sh -c "echo \"s \$\$\" >> '$TMP/g3'; sleep 2; echo \"e \$\$\" >> '$TMP/g3'" ) 2>/dev/null &
  done
  wait
  _bad="$(awk '$1=="s"{if(open!="")bad=bad" "NR; open=$2} $1=="e"{if(open!=$2)bad=bad" "NR; open=""} END{print bad}' "$TMP/g3")"
  assert_eq "" "$_bad" "no two commands run at once (overlapping lines of the marks file)"
  assert_eq 3 "$(grep -c '^s ' "$TMP/g3")" "all three contenders run"
  assert_missing "$GP/.studio/gate.lock" "no lock is left behind"
}
# The cmd starts a grandchild; TERM to studio-gate must reach it too, and the
# lock must outlive it.
test_gate_signal_reaches_the_grandchild() {
  gate_proj group
  rm -f "$TMP/ggc"
  ( cd "$GP" && sh "$GATE" grp -- sh -c "sleep 30 & echo \$! > '$TMP/ggc'; wait" ) >/dev/null 2>&1 &
  _i=0; while [ ! -s "$TMP/ggc" ] && [ "$_i" -lt 50 ]; do sleep 0.2; _i=$((_i + 1)); done
  _gc="$(cat "$TMP/ggc")"
  _gp="$(cat "$GP/.studio/gate.lock/pid")"
  kill -TERM "$_gp"
  # Watch while studio-gate lives: the lock must not vanish before the grandchild.
  _early=no; _i=0
  while kill -0 "$_gp" 2>/dev/null && [ "$_i" -lt 200 ]; do
    if [ ! -e "$GP/.studio/gate.lock" ] && kill -0 "$_gc" 2>/dev/null; then _early=yes; fi
    sleep 0.05; _i=$((_i + 1))
  done
  wait
  _alive=no; kill -0 "$_gc" 2>/dev/null && _alive=yes
  if [ "$_alive" = yes ]; then _early=yes; kill -KILL "$_gc" 2>/dev/null; fi
  assert_eq no "$_alive" "TERM to studio-gate reaches the cmd's grandchild"
  assert_eq no "$_early" "the lock is not released while the grandchild lives"
  assert_missing "$GP/.studio/gate.lock" "the lock is released afterwards"
}
# Under an overnight unit (STUDIO_UNIT_TAG), the gate registers itself and
# its command's pid for the runner's reaper, records the unit and start time
# in the lock, and logs the run's seconds to gate.times; the registration is
# gone once the command ends.
test_gate_unit_registration_and_times() {
  gate_proj unit
  ( cd "$GP" && STUDIO_UNIT_TAG="run-1-3-finish" sh "$GATE" studio-test -- sh -c "
      cp .studio/gate.lock/unit '$TMP/gunit'; cp .studio/gate.lock/since '$TMP/gsince'
      ls .studio/gate.units/run-1-3-finish > '$TMP/greg'
      cat .studio/gate.units/run-1-3-finish/* > '$TMP/gchild'; echo \$\$ > '$TMP/gself'" ) 2>/dev/null
  assert_eq run-1-3-finish "$(cat "$TMP/gunit")" "the lock names the unit"
  assert_contains "$TMP/gsince" '^[0-9][0-9]*$' "the lock records when it was taken"
  assert_eq 1 "$(wc -l < "$TMP/greg" | tr -d ' ')" "the gate registers one entry under the unit's tag"
  assert_eq "$(cat "$TMP/gself")" "$(cat "$TMP/gchild")" "the entry holds the command's pid"
  assert_missing "$GP/.studio/gate.units/run-1-3-finish" "the entry is removed when the gate ends"
  assert_contains "$GP/.studio/gate.times" '^[0-9][0-9]* studio-test [0-9][0-9]* 0$' "gate.times gains the run's seconds and status"
  assert_eq "" "$(git -C "$GP" status --porcelain --untracked-files=all | grep 'gate\.')" "the gate's files stay out of git"
  ( cd "$GP" && STUDIO_UNIT_TAG="../x" sh "$GATE" w -- true ) 2>/dev/null
  assert_missing "$GP/.studio/x" "an unsafe tag is ignored, never a path"
  for _i in $(seq 1 55); do echo "1 w 1 0"; done > "$GP/.studio/gate.times"
  ( cd "$GP" && sh "$GATE" w -- true ) 2>/dev/null
  assert_eq 50 "$(wc -l < "$GP/.studio/gate.times" | tr -d ' ')" "gate.times keeps the newest 50 lines"
}
test_gate_wraps_test_and_run() {
  assert_contains "$BIN/studio-test" 'studio-gate" studio-test --' "studio-test goes through studio-gate"
  assert_contains "$BIN/studio-run" 'studio-gate" studio-run --' "studio-run goes through studio-gate"
}

run_tests test_gate_no_overlap test_gate_status_and_held test_gate_stale_reclaim_race \
  test_gate_waiting_message test_gate_records_pid_and_who test_gate_without_a_project_just_runs \
  test_gate_signal_waits_for_child_then_releases test_gate_three_reclaimers_never_overlap \
  test_gate_signal_reaches_the_grandchild test_gate_unit_registration_and_times test_gate_wraps_test_and_run \
  test_dispatch_rejects_unknown_engine test_dispatch_needs_a_studio_root \
  test_resolve_honours_godot_path test_resolve_ignores_a_non_executable_godot_path \
  test_resolve_finds_an_app_bundle test_resolve_finds_godot_on_path test_guide_has_an_install_line \
  test_test_needs_a_project test_test_falls_back_to_studio_json test_test_exits_3_without_gut \
  test_test_exits_2_without_engine test_test_passes_and_reports test_test_reports_failures \
  test_test_targets_a_file test_test_targets_a_directory test_test_imports_when_dot_godot_is_absent \
  test_run_clean test_run_detects_script_errors test_run_passes_scene_and_windowed \
  test_run_terminates_a_long_process test_run_rejects_bad_options \
  test_run_traps_signals_to_avoid_orphaning_the_child test_run_imports_when_dot_godot_is_absent \
  test_lint_needs_a_project test_lint_exits_3_without_gdtoolkit test_lint_runs_both_tools_over_gd_files \
  test_lint_reports_findings test_lint_with_no_scripts_is_clean
