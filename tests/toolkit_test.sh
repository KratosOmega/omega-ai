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

run_tests test_dispatch_rejects_unknown_engine test_dispatch_needs_a_studio_root \
  test_resolve_honours_godot_path test_resolve_ignores_a_non_executable_godot_path \
  test_resolve_finds_an_app_bundle test_resolve_finds_godot_on_path test_guide_has_an_install_line \
  test_test_needs_a_project test_test_falls_back_to_studio_json test_test_exits_3_without_gut \
  test_test_exits_2_without_engine test_test_passes_and_reports test_test_reports_failures \
  test_test_targets_a_file test_test_targets_a_directory test_test_imports_when_dot_godot_is_absent \
  test_run_clean test_run_detects_script_errors test_run_passes_scene_and_windowed \
  test_run_terminates_a_long_process test_run_rejects_bad_options test_run_imports_when_dot_godot_is_absent
