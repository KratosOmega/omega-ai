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
unset STUDIO_GATE_POLL_SECONDS STUDIO_SETUP_POLL_SECONDS
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

# A stub Godot. It records its arguments, honours --path and
# -gjunit_xml_file=res://… by writing a JUnit file into the project, prints a
# SCRIPT ERROR line when STUB_SCRIPT_ERROR=1, sleeps STUB_SLEEP seconds, and
# exits 1 when STUB_FAILS is greater than 0 (as GUT does with -gexit).
# STUB_CRASH=mid crashes inside res://tests/unit/test_dash.gd before any report,
# STUB_CRASH=inner inside its inner class TestInner (after test_cooldown.gd ran);
# STUB_CRASH=exit writes a passing report and a Run Summary that lists a script,
# then crashes at shutdown.
# STUB_TESTS=0 writes a report with no tests (GUT found nothing to run);
# STUB_XML_TS=1 adds a timestamp to the report's name, as junit_xml_timestamp does.
mkdir -p "$TMP/stub"
cat > "$TMP/stub/godot" <<'STUB'
#!/bin/sh
proj="."; xml=""; want=0; import=0
printf 'stub godot args: %s\n' "$*"
for a in "$@"; do
  if [ "$want" = 1 ]; then proj="$a"; want=0; continue; fi
  case "$a" in
    --path) want=1 ;;
    --import) import=1 ;;
    -gjunit_xml_file=res://*) xml="${a#-gjunit_xml_file=res://}" ;;
  esac
done
# --import: .godot/ always appears; unless STUB_IMPORT=partial (killed early) or
# STUB_IMPORT=fail (exits 1), every dest_files product and the class cache are written.
# An import run ends there: it runs no tests, so STUB_FAILS does not apply to it.
# Like a real import, it prints an ERROR line along the way.
if [ "$import" = 1 ]; then
  mkdir -p "$proj/.godot/imported"
  echo "ERROR: stub import: an error line any import may print"
  [ "${STUB_IMPORT:-}" = fail ] && exit 1
  if [ "${STUB_IMPORT:-}" != partial ]; then
    : > "$proj/.godot/global_script_class_cache.cfg"
    find "$proj" -name '*.import' -not -path '*/.godot/*' | while read -r f; do
      sed -n '/^dest_files=\[/p' "$f" | grep -o '"res://[^"]*"' | sed 's/^"res:\/\///; s/"$//' | while read -r d; do
        : > "$proj/$d"
        # A hashed product gets its .md5 sidecar, as Godot writes once a file is imported.
        m="$(printf '%s' "$d" | sed -n 's/^\(.*-[0-9a-f]\{32\}\)\..*$/\1.md5/p')"
        [ -z "$m" ] || : > "$proj/$m"
      done
    done
  fi
  exit 0
fi
crash() { printf '\n================================================================\nhandle_crash: Program crashed with signal 11\n'; exit 139; }
if [ "${STUB_CRASH:-}" = mid ]; then printf 'res://tests/unit/test_dash.gd\n'; crash; fi
if [ "${STUB_CRASH:-}" = inner ]; then printf 'res://tests/unit/test_cooldown.gd\nres://tests/unit/test_dash.gd.TestInner\n'; crash; fi
[ "${STUB_XML_TS:-0}" = 1 ] && xml="${xml%.xml}_1759449600.xml"
if [ -n "$xml" ] && [ "${STUB_TESTS:-}" = 0 ]; then
  mkdir -p "$(dirname "$proj/$xml")"
  printf '<testsuites name="GutTests" failures="0" tests="0" >\n</testsuites>\n' > "$proj/$xml"
elif [ -n "$xml" ]; then
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
[ "${STUB_CRASH:-}" = exit ] && { printf '==============================================\n= Run Summary\n==============================================\nres://tests/unit/test_menu.gd\n- test_open\n    [Pending]:  not yet\n'; crash; }
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
      STUB_IMPORT="${STUB_IMPORT:-}" STUB_CRASH="${STUB_CRASH:-}" \
      STUB_TESTS="${STUB_TESTS:-}" STUB_XML_TS="${STUB_XML_TS:-0}" \
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
  assert_not_contains "$log" "\-gconfig" "a file target with no config passes none"
}

test_test_targets_a_directory() {
  P="$(fresh_project dir)"
  with_gut "$P"
  mkdir -p "$P/tests/integration"
  verb "$P" studio-test tests/integration
  log="$(ls "$P"/.studio/reports/test-*.log | head -n 1)"
  assert_contains "$log" "\-gdir=res://tests/integration" "a directory argument runs that directory"
}

# with_gutconfig DIR PATH [DIRS] — a GUT config at PATH with a pre-run hook; DIRS (a JSON
# array) becomes its "dirs" entry, or the config names none.
with_gutconfig() {
  mkdir -p "$(dirname "$1/$2")"
  {
    printf '{\n'
    [ -z "${3:-}" ] || printf '  "dirs": %s,\n' "$3"
    printf '  "pre_run_script": "res://tests/helpers/pre_run.gd"\n}\n'
  } > "$1/$2"
}

# last_log DIR — the newest test log in DIR's reports.
last_log() { ls "$1"/.studio/reports/test-*.log | sort | tail -n 1; }

test_test_passes_the_projects_gut_config() {
  P="$(fresh_project gutconfig)"
  with_gut "$P"
  mkdir -p "$P/.godot" "$P/tests/unit"
  : > "$P/tests/unit/test_dash.gd"
  with_gutconfig "$P" tests/.gutconfig.json '["res://tests/unit"]'
  verb "$P" studio-test
  log="$(last_log "$P")"
  assert_contains "$log" "\-gconfig=res://tests/.gutconfig.json" "a tests/.gutconfig.json is passed, so its hooks run"
  assert_not_contains "$log" "\-gdir" "with no PATH the config's own dirs are the suite"
  rm -rf "$P/.studio/reports"
  verb "$P" studio-test tests/unit/test_dash.gd
  log="$(last_log "$P")"
  assert_contains "$log" "\-gconfig=res://tests/.gutconfig.json \-gdir= \-gtest=res://tests/unit/test_dash.gd" "a file target keeps the config and empties its dirs, so only that file runs"
  rm -rf "$P/.studio/reports"
  verb "$P" studio-test tests/unit
  log="$(last_log "$P")"
  assert_contains "$log" "\-gconfig=res://tests/.gutconfig.json \-gdir=res://tests/unit \-ginclude_subdirs" "a directory target keeps the config and replaces its dirs"
}

test_test_gut_config_lookup() {
  P="$(fresh_project gutconfig-root)"
  with_gut "$P"
  mkdir -p "$P/.godot"
  with_gutconfig "$P" .gutconfig.json '["res://tests/unit"]'
  with_gutconfig "$P" tests/.gutconfig.json '["res://tests/other"]'
  verb "$P" studio-test
  assert_contains "$(last_log "$P")" "\-gconfig=res://.gutconfig.json" "GUT's default root config wins over tests/"
  P="$(fresh_project gutconfig-nodirs)"
  with_gut "$P"
  mkdir -p "$P/.godot"
  with_gutconfig "$P" tests/.gutconfig.json
  verb "$P" studio-test
  assert_contains "$(last_log "$P")" "\-gconfig=res://tests/.gutconfig.json \-gdir=res://tests \-ginclude_subdirs" "a config naming no dirs still runs res://tests"
  P="$(fresh_project gutconfig-none)"
  with_gut "$P"
  mkdir -p "$P/.godot"
  verb "$P" studio-test
  assert_not_contains "$(last_log "$P")" "\-gconfig" "no config: none is passed"
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

# with_asset DIR NAME [HASH] — an imported asset: art/NAME, and art/NAME.import naming one
# product, .godot/imported/NAME-HASH.ctex (HASH defaults to 0a1b, too short to carry a sidecar).
with_asset() {
  mkdir -p "$1/art"
  : > "$1/art/$2"
  printf '[remap]\n\nimporter="texture"\n\n[deps]\n\nsource_file="res://art/%s"\ndest_files=["res://.godot/imported/%s-%s.ctex"]\n' "$2" "$2" "${3:-0a1b}" > "$1/art/$2.import"
}

test_test_reimports_a_partial_cache() {
  P="$(fresh_project partial)"
  with_gut "$P"
  with_asset "$P" hero.png
  mkdir -p "$P/.godot/imported"   # what a killed import leaves: the directory, no products
  verb "$P" studio-test
  assert_eq "0" "$(cat "$TMP/status")" "a cache missing products is re-imported, then the suite runs"
  assert_contains "$TMP/out" "^studio-test: import cache incomplete (1 missing) — importing" "the re-import is announced with the missing count"
  assert_file "$P/.godot/imported/hero.png-0a1b.ctex" "the missing product is imported"
  log="$(ls "$P"/.studio/reports/test-*.log | head -n 1)"
  assert_contains "$log" "^stub godot args: --headless --path $P --import$" "the import runs before the suite"
}

test_test_skips_import_when_the_cache_is_complete() {
  P="$(fresh_project complete)"
  with_gut "$P"
  with_asset "$P" hero.png
  mkdir -p "$P/.godot/imported"
  : > "$P/.godot/imported/hero.png-0a1b.ctex"
  mkdir -p "$P/old"
  printf '[deps]\n\nsource_file="res://old/gone.png"\ndest_files=["res://.godot/imported/gone.png-ffff.ctex"]\n' > "$P/old/gone.png.import"
  verb "$P" studio-test
  log="$(ls "$P"/.studio/reports/test-*.log | head -n 1)"
  assert_not_contains "$log" "\-\-import" "every product present (an orphan .import with no source ignored): no import"
  assert_not_contains "$TMP/out" "import cache incomplete" "and nothing is announced"
}

test_test_reimports_a_product_without_its_md5() {
  P="$(fresh_project nomd5)"
  with_gut "$P"
  h=b06b736de5fc6ebcd1337dfd9abfd984
  with_asset "$P" hero.png "$h"
  mkdir -p "$P/.godot/imported"
  : > "$P/.godot/imported/hero.png-$h.ctex"   # written, but the import was cut off before its .md5
  verb "$P" studio-test
  assert_contains "$TMP/out" "^studio-test: import cache incomplete (1 missing) — importing" "a product without its .md5 sidecar counts as missing"
  assert_file "$P/.godot/imported/hero.png-$h.md5" "the re-import completes it"
  rm -rf "$P/.studio/reports"   # a second run in the same second would append to the same log
  verb "$P" studio-test
  log="$(ls "$P"/.studio/reports/test-*.log | head -n 1)"
  assert_not_contains "$log" "\-\-import" "a product with its .md5 is complete: no import"
}

test_test_names_a_crash() {
  P="$(fresh_project crash)"
  with_gut "$P"
  mkdir -p "$P/.godot"
  STUB_CRASH=mid verb "$P" studio-test
  assert_eq "1" "$(cat "$TMP/status")" "a crash before the report exits 1"
  assert_contains "$TMP/out" "^studio-test: Godot crashed (signal 11) while running res://tests/unit/test_dash.gd$" "the crash names its signal and the script that was running"
  rm -rf "$P/.studio/reports"
  STUB_CRASH=inner verb "$P" studio-test
  assert_contains "$TMP/out" "^studio-test: Godot crashed (signal 11) while running res://tests/unit/test_dash.gd$" "a crash in an inner class names its .gd file"
  rm -rf "$P/.studio/reports"
  STUB_CRASH=exit verb "$P" studio-test
  assert_eq "1" "$(cat "$TMP/status")" "a crash at shutdown after a passing report exits 1"
  assert_contains "$TMP/out" "^studio-test: Godot crashed (signal 11) at shutdown, after the run$" "the shutdown crash is named as one"
  assert_not_contains "$TMP/out" "while running" "and not pinned on a script the Run Summary lists"
  assert_contains "$TMP/out" "^studio-test: Godot exited 139 after writing the report$" "with the engine's exit"
  rm -rf "$P/.studio/reports"
  verb "$P" studio-test
  assert_not_contains "$TMP/out" "Godot crashed" "a clean run reports no crash"
}

test_test_imports_when_the_class_cache_is_missing() {
  P="$(fresh_project classcache)"
  with_gut "$P"
  mkdir -p "$P/.godot" "$P/scripts"
  printf 'class_name Hero\nextends Node\n' > "$P/scripts/hero.gd"
  verb "$P" studio-test
  log="$(ls "$P"/.studio/reports/test-*.log | head -n 1)"
  assert_contains "$log" "\-\-import" "a class_name script with no global_script_class_cache.cfg is imported"
}

test_test_warns_when_the_import_leaves_products_missing() {
  P="$(fresh_project stays-partial)"
  with_gut "$P"
  with_asset "$P" hero.png
  STUB_IMPORT=partial verb "$P" studio-test
  assert_eq "0" "$(cat "$TMP/status")" "an import that exits 0 but leaves products missing does not stop the suite"
  assert_contains "$TMP/out" "^studio-test: WARNING: the import finished but left 1 import product(s) missing" "it warns that products are missing"
  assert_contains "$TMP/out" "hero.png-0a1b.ctex" "and names a missing product"
  log="$(ls "$P"/.studio/reports/test-*.log | head -n 1)"
  assert_contains "$log" "gut_cmdln" "the suite runs"
  rm -rf "$P/.studio/reports" "$P/.godot"
  STUB_IMPORT=fail verb "$P" studio-test
  assert_eq "1" "$(cat "$TMP/status")" "an import that exits non-zero exits 1"
  assert_contains "$TMP/out" "^studio-test: the asset import did not complete (engine exit 1)" "the message carries the engine's exit"
}

# with_import DIR SRC PRODUCT… — an asset DIR/SRC and its SRC.import, whose dest_files
# lists each PRODUCT under .godot/imported/, as Godot writes a multi-entry list.
with_import() {
  _wd="$1"; _ws="$2"; shift 2
  mkdir -p "$(dirname "$_wd/$_ws")"
  : > "$_wd/$_ws"
  _wl=""
  for _wp in "$@"; do _wl="${_wl:+$_wl, }\"res://.godot/imported/$_wp\""; done
  printf '[remap]\n\nimporter="texture"\n\n[deps]\n\nsource_file="res://%s"\ndest_files=[%s]\n' "$_ws" "$_wl" > "$_wd/$_ws.import"
}

# made DIR FILE… — create each FILE under DIR/.godot/imported.
made() { _md="$1"; shift; mkdir -p "$_md/.godot/imported"; for _mf in "$@"; do : > "$_md/.godot/imported/$_mf"; done; }

test_test_import_check_reads_every_dest_files_entry() {
  h=b06b736de5fc6ebcd1337dfd9abfd984
  hex=0123456789abcdef0123456789abcdef
  P="$(fresh_project dest-files)"
  with_gut "$P"
  with_import "$P" art/tiles.png "tiles.png-$h.s3tc.ctex" "tiles.png-$h.etc2.ctex"
  with_import "$P" "art/Hit, Loud.wav" "Hit, Loud.wav-$h.sample"
  with_import "$P" "art/tile-$hex.png" "tile-$hex.png-$h.ctex"
  made "$P" "tiles.png-$h.s3tc.ctex" "tiles.png-$h.etc2.ctex" "tiles.png-$h.md5" \
    "Hit, Loud.wav-$h.sample" "Hit, Loud.wav-$h.md5" "tile-$hex.png-$h.ctex" "tile-$hex.png-$h.md5"
  verb "$P" studio-test
  assert_not_contains "$TMP/out" "import cache incomplete" "a multi-entry list, a comma in a name and a hex source name all read as complete"
  log="$(last_log "$P")"
  assert_not_contains "$log" "\-\-import" "so no import runs"
  rm -rf "$P/.studio/reports"
  rm -f "$P/.godot/imported/tiles.png-$h.etc2.ctex"
  verb "$P" studio-test
  assert_contains "$TMP/out" "^studio-test: import cache incomplete (1 missing) — importing" "a missing second entry is found"
  assert_file "$P/.godot/imported/tiles.png-$h.etc2.ctex" "and imported"
}

test_test_import_check_skips_dirs_godot_does_not_scan() {
  P="$(fresh_project unscanned)"
  with_gut "$P"
  mkdir -p "$P/.godot/imported" "$P/raw" "$P/demo"
  : > "$P/raw/.gdignore"
  with_import "$P" raw/big.png "big.png-0a1b.ctex"
  printf '[application]\nconfig/name="Demo"\n' > "$P/demo/project.godot"
  with_import "$P" demo/icon.png "icon.png-0a1b.ctex"
  verb "$P" studio-test
  assert_not_contains "$TMP/out" "import cache incomplete" "a .import under a .gdignore'd dir or a nested project is not checked"
  assert_eq "0" "$(cat "$TMP/status")" "and the suite runs"
}

test_test_class_cache_counts_addons() {
  P="$(fresh_project class-addons)"
  with_gut "$P"
  mkdir -p "$P/.godot"
  printf 'class_name GutTest\nextends Node\n' > "$P/addons/gut/test.gd"
  STUB_IMPORT=partial verb "$P" studio-test
  assert_contains "$TMP/out" "^studio-test: import cache incomplete (no class cache) — importing" "a class_name under addons/ counts, and the reason is the class cache"
  assert_not_contains "$TMP/out" "0 missing" "no product count when only the class cache is missing"
  assert_contains "$TMP/out" "^studio-test: WARNING: the import finished but left no .godot/global_script_class_cache.cfg" "the class cache is checked again after the import"
  assert_eq "0" "$(cat "$TMP/status")" "and the suite still runs"
}

test_test_no_tests_ran_is_not_green() {
  P="$(fresh_project no-tests)"
  with_gut "$P"
  mkdir -p "$P/.godot"
  STUB_TESTS=0 verb "$P" studio-test tests/nope.gd
  assert_eq "1" "$(cat "$TMP/status")" "a PATH that matches nothing exits 1"
  assert_contains "$TMP/out" "^studio-test: no tests ran (check PATH or the config's dirs)$" "and says no tests ran"
  assert_contains "$(last_log "$P")" "\-gdir=res://tests/nope.gd \-ginclude_subdirs" "a nonexistent PATH is passed as a directory"
}

test_test_finds_a_timestamped_report() {
  P="$(fresh_project xml-ts)"
  with_gut "$P"
  mkdir -p "$P/.godot"
  STUB_XML_TS=1 verb "$P" studio-test
  assert_eq "0" "$(cat "$TMP/status")" "a report GUT named with junit_xml_timestamp is found"
  assert_contains "$TMP/out" "^report: .studio/reports/test-[0-9-]*_1759449600.xml$" "and named"
}

test_slowest_reports_files_and_tests() {
  P="$(fresh_project slowest)"
  mkdir -p "$P/.studio/reports"
  cat > "$P/.studio/reports/test-20260101-000000.xml" <<'XML'
<testsuites name="GutTests" failures="0" tests="9" >
  <testsuite name="tests/unit/test_old.gd" tests="1" time="99.0" >
      <testcase name="test_old" status="pass" classname="tests/unit/test_old.gd" time="99.0" >
      </testcase>
  </testsuite>
</testsuites>
XML
  cat > "$P/.studio/reports/test-20260102-000000.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<testsuites name="GutTests" failures="0" tests="5" >
  <testsuite name="tests/unit/test_menu.gd" tests="2" failures="0" skipped="0" time="8.5" >
      <testcase name="test_open" assertions="1" status="pass" classname="tests/unit/test_menu.gd" time="4.25" >
      </testcase>
      <testcase name="test_close" assertions="1" status="pass" classname="tests/unit/test_menu.gd" time="4.25" >
      </testcase>
  </testsuite>
  <testsuite name="tests/unit/test_fast.gd" tests="2" failures="0" skipped="0" time="0.02" >
      <testcase name="test_a" assertions="1" status="pass" classname="tests/unit/test_fast.gd" time="0.01" >
      </testcase>
      <testcase name="test_b" assertions="1" status="pass" classname="tests/unit/test_fast.gd" time="0.01" >
      </testcase>
  </testsuite>
  <testsuite name="tests/unit/test_hoist.gd" tests="1" failures="0" skipped="0" time="6.0" >
      <testcase name="test_lift" assertions="1" status="pass" classname="tests/unit/test_hoist.gd" time="6.0" >
      </testcase>
  </testsuite>
</testsuites>
XML
  verb "$P" studio-test --slowest 2
  assert_eq "0" "$(cat "$TMP/status")" "--slowest exits 0"
  assert_contains "$TMP/out" "test-20260102-000000.xml — 5 tests in 3 files, 14.5 s" "the newest report is read and totalled"
  assert_eq "tests/unit/test_menu.gd" "$(awk '/^slowest files/ { f = 1; next } f { print $NF; exit }' "$TMP/out")" "files are ranked by total time"
  assert_contains "$TMP/out" "8.5 s *2 tests *4.25 s/test *tests/unit/test_menu.gd" "a file row has time, count and mean"
  assert_eq "test_lift" "$(awk '/^slowest tests/ { f = 1; next } f { print $NF; exit }' "$TMP/out")" "tests are ranked by time"
  assert_not_contains "$TMP/out" "test_fast.gd" "only N rows are shown"
  assert_not_contains "$TMP/out" "test_old" "an older report is ignored"
  assert_contains "$TMP/out" "^tests at 0.5 s or more: 3 of 5, 14.5 s (100% of the time)" "the slow-test share is summarised"
}

test_slowest_does_not_wait_for_the_gate() {
  gate_proj slowest-gate
  mkdir -p "$GP/.studio/reports" "$GP/.studio/gate.lock"
  printf '<testsuites tests="1">\n<testsuite name="t.gd">\n<testcase name="test_x" classname="t.gd" time="1.0">\n</testcase>\n</testsuite>\n</testsuites>\n' > "$GP/.studio/reports/test-20260101-000000.xml"
  sleep 30 & holder=$!
  echo "$holder" > "$GP/.studio/gate.lock/pid"; echo studio-test > "$GP/.studio/gate.lock/who"
  verb "$GP" studio-test --slowest
  kill "$holder" 2>/dev/null; rm -rf "$GP/.studio/gate.lock"
  assert_eq "0" "$(cat "$TMP/status")" "--slowest reads the report while a run holds the gate"
  assert_not_contains "$TMP/out" "gate: waiting" "and never waits for the lock"
}

test_slowest_with_an_empty_report() {
  P="$(fresh_project slowest-empty)"
  mkdir -p "$P/.studio/reports"
  printf '<testsuites name="GutTests" failures="0" tests="0" >\n</testsuites>\n' > "$P/.studio/reports/test-20260101-000000.xml"
  verb "$P" studio-test --slowest
  assert_eq "0" "$(cat "$TMP/status")" "a report with no testcases exits 0"
  assert_contains "$TMP/out" "test-20260101-000000.xml — 0 tests in 0 files, 0.0 s" "and totals nothing"
  assert_not_contains "$TMP/out" "% of the time" "with no shares of a zero total"
}

test_slowest_without_a_report_or_with_bad_n() {
  P="$(fresh_project slowest-none)"
  verb "$P" studio-test --slowest
  assert_eq "1" "$(cat "$TMP/status")" "no report exits 1"
  assert_contains "$TMP/out" "no JUnit report in .studio/reports" "and says to run studio-test first"
  verb "$P" studio-test --slowest ten
  assert_eq "1" "$(cat "$TMP/status")" "a non-numeric N exits 1"
  assert_contains "$TMP/out" "usage: studio-test --slowest \[N\]" "and prints the usage"
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
  log="$(ls "$P"/.studio/reports/import-*.log | head -n 1)"
  assert_contains "$log" "^stub godot args: --headless --path $P --import$" "a project without .godot/ is imported before the run, into its own log"
  assert_eq "0" "$(cat "$TMP/status")" "the import's ERROR lines are not counted as the run's script errors"
  assert_not_contains "$(ls "$P"/.studio/reports/run-*.log | head -n 1)" "ERROR:" "the run log holds only the run"
  P="$(fresh_project run-imported)"
  mkdir -p "$P/.godot"
  verb "$P" studio-run --seconds 1
  log="$(ls "$P"/.studio/reports/run-*.log | head -n 1)"
  assert_not_contains "$log" "\-\-import" "a project with .godot/ is not imported again"
  P="$(fresh_project run-partial)"
  with_asset "$P" hero.png
  mkdir -p "$P/.godot/imported"
  verb "$P" studio-run --seconds 1
  assert_file "$P/.godot/imported/hero.png-0a1b.ctex" "studio-run re-imports a cache missing products"
  rm -f "$P/.godot/imported/hero.png-0a1b.ctex"
  STUB_IMPORT=partial verb "$P" studio-run --seconds 1
  assert_eq "0" "$(cat "$TMP/status")" "studio-run runs on after an import that exits 0 with products missing"
  assert_contains "$TMP/out" "^studio-run: WARNING: the import finished but left 1 import product(s) missing" "with a warning in studio-run's own prefix"
  STUB_IMPORT=fail verb "$P" studio-run --seconds 1
  assert_eq "1" "$(cat "$TMP/status")" "studio-run stops on an import that exits non-zero"
  assert_contains "$TMP/out" "^studio-run: the asset import did not complete (engine exit 1)" "naming the engine's exit"
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
test_gate_poll_keeps_budget() {
  gate_proj pollb
  ( cd "$GP" && sh "$GATE" holder -- sleep 13 ) >/dev/null 2>&1 &
  _i=0; while [ ! -s "$GP/.studio/gate.lock/pid" ] && [ "$_i" -lt 100 ]; do sleep 0.1; _i=$((_i + 1)); done
  _rc=0
  ( cd "$GP" && STUDIO_GATE_POLL_SECONDS=0.1 sh "$GATE" waiter -- true ) 2> "$TMP/gw.err" || _rc=$?
  wait
  assert_eq 0 "$_rc" "the waiter exits 0 once the holder is done"
  assert_eq 1 "$(grep -c '^gate: waiting for' "$TMP/gw.err")" "one waiting line in 13 s: the 60 s cadence is not scaled"
}
test_gate_poll_rejects_bad_value() {
  gate_proj pollx
  _rc=0
  ( cd "$GP" && STUDIO_GATE_POLL_SECONDS=2 sh "$GATE" x -- true ) 2> "$TMP/gx.err" || _rc=$?
  assert_eq 2 "$_rc" "a bad poll value exits 2"
  assert_contains "$TMP/gx.err" '^studio-gate: STUDIO_GATE_POLL_SECONDS must be 1, 0.5, 0.2 or 0.1, got 2$' "naming the knob and the value"
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
  assert_contains "$GP/.studio/gate.times" '^[0-9][0-9]* sig [0-9][0-9]* 143$' "a signalled run is logged too, with 128+n"
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
      i=0; while [ ! -s .studio/gate.units/run-1-3-finish/* ] && [ \$i -lt 50 ]; do sleep 0.1; i=\$((i + 1)); done
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

# #35 AC19: setup lines never push out studio-test lines.
test_gate_times_window_per_who() {
  gate_proj gtw
  { i=1; while [ "$i" -le 10 ]; do echo "$i studio-test 7 0"; i=$((i + 1)); done
    i=1; while [ "$i" -le 60 ]; do echo "$i setup 1 0"; i=$((i + 1)); done; } > "$GP/.studio/gate.times"
  ( cd "$GP" && sh "$GATE" setup -- true ) >/dev/null 2>&1
  assert_eq 10 "$(grep -c ' studio-test ' "$GP/.studio/gate.times")" "every studio-test line is kept"
  assert_eq 50 "$(grep -c ' setup ' "$GP/.studio/gate.times")" "setup keeps its newest 50"
  assert_contains "$GP/.studio/gate.times" '^[0-9][0-9]* setup [0-9][0-9]* 0$' "the new run is logged"
  assert_not_contains "$GP/.studio/gate.times" '^11 setup ' "the oldest setup lines went"
}

run_tests test_gate_times_window_per_who test_gate_no_overlap test_gate_status_and_held test_gate_stale_reclaim_race \
  test_gate_waiting_message test_gate_poll_keeps_budget test_gate_poll_rejects_bad_value test_gate_records_pid_and_who test_gate_without_a_project_just_runs \
  test_gate_signal_waits_for_child_then_releases test_gate_three_reclaimers_never_overlap \
  test_gate_signal_reaches_the_grandchild test_gate_unit_registration_and_times test_gate_wraps_test_and_run \
  test_dispatch_rejects_unknown_engine test_dispatch_needs_a_studio_root \
  test_resolve_honours_godot_path test_resolve_ignores_a_non_executable_godot_path \
  test_resolve_finds_an_app_bundle test_resolve_finds_godot_on_path test_guide_has_an_install_line \
  test_test_needs_a_project test_test_falls_back_to_studio_json test_test_exits_3_without_gut \
  test_test_exits_2_without_engine test_test_passes_and_reports test_test_reports_failures \
  test_test_targets_a_file test_test_targets_a_directory test_test_imports_when_dot_godot_is_absent \
  test_test_reimports_a_partial_cache test_test_skips_import_when_the_cache_is_complete \
  test_test_reimports_a_product_without_its_md5 test_test_names_a_crash \
  test_test_passes_the_projects_gut_config test_test_gut_config_lookup \
  test_test_imports_when_the_class_cache_is_missing test_test_warns_when_the_import_leaves_products_missing \
  test_test_import_check_reads_every_dest_files_entry test_test_import_check_skips_dirs_godot_does_not_scan \
  test_test_class_cache_counts_addons test_test_no_tests_ran_is_not_green test_test_finds_a_timestamped_report \
  test_slowest_reports_files_and_tests test_slowest_does_not_wait_for_the_gate test_slowest_with_an_empty_report \
  test_slowest_without_a_report_or_with_bad_n \
  test_run_clean test_run_detects_script_errors test_run_passes_scene_and_windowed \
  test_run_terminates_a_long_process test_run_rejects_bad_options \
  test_run_traps_signals_to_avoid_orphaning_the_child test_run_imports_when_dot_godot_is_absent \
  test_lint_needs_a_project test_lint_exits_3_without_gdtoolkit test_lint_runs_both_tools_over_gd_files \
  test_lint_reports_findings test_lint_with_no_scripts_is_clean
