#!/bin/sh
# test.sh [PATH] — run the GUT suite headless. Invoked by studio-dispatch
# from the project root.
#
#   PATH   a test file (-gtest=res://PATH) or directory (-gdir=res://PATH);
#          default res://tests, subdirectories included
#
# Exit: 0 all passed · 1 failures (or not a project) · 2 no Godot binary ·
#       3 GUT not installed. Prints "studio-test: N passed, M failed", then
#       the failing test names. JUnit XML and the engine log are written to
#       .studio/reports/test-<stamp>.{xml,log}.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$(pwd -P)"

if [ ! -f "$PROJECT/project.godot" ]; then
  echo "studio-test: no project.godot in $PROJECT — run from the project root" >&2
  exit 1
fi

GODOT="$(sh "$HERE/resolve.sh")" || exit 2

if [ ! -f "$PROJECT/addons/gut/gut_cmdln.gd" ]; then
  echo "studio-test: GUT is not installed — addons/gut/gut_cmdln.gd is missing." >&2
  echo "Install it from the project root:" >&2
  sed -n 's/^Install: //p' "$HERE/GUIDE.md" >&2
  exit 3
fi

# Target: a file becomes -gtest, a directory becomes -gdir. Paths are given
# relative to the project root and turned into res:// paths.
target="${1:-tests}"
target="${target#./}"
target="${target%/}"
if [ -f "$PROJECT/$target" ]; then
  set -- "-gtest=res://$target"
else
  set -- "-gdir=res://$target" "-ginclude_subdirs"
fi

mkdir -p "$PROJECT/.studio/reports"
stamp="$(date +%Y%m%d-%H%M%S)"
xml_rel=".studio/reports/test-$stamp.xml"
log="$PROJECT/.studio/reports/test-$stamp.log"

# A project the editor has never opened has no .godot/ (and so no
# global_script_class_cache.cfg); import once so class_name lookups resolve.
if [ ! -d "$PROJECT/.godot" ]; then
  "$GODOT" --headless --path "$PROJECT" --import >>"$log" 2>&1 || true
fi

"$GODOT" --headless --path "$PROJECT" -s addons/gut/gut_cmdln.gd \
  "$@" -gexit "-gjunit_xml_file=res://$xml_rel" >> "$log" 2>&1
engine_status=$?

xml="$PROJECT/$xml_rel"
if [ ! -f "$xml" ]; then
  echo "studio-test: GUT produced no report (engine exit $engine_status); last lines of $log:" >&2
  tail -n 20 "$log" >&2
  exit 1
fi

# Totals come from the <testsuites> attributes; failing names from each
# <testcase> that carries a <failure> or <error> child.
total="$(sed -n 's/.*<testsuites[^>]*tests="\([0-9]*\)".*/\1/p' "$xml" | head -n 1)"
failed="$(sed -n 's/.*<testsuites[^>]*failures="\([0-9]*\)".*/\1/p' "$xml" | head -n 1)"
errors="$(sed -n 's/.*<testsuites[^>]*errors="\([0-9]*\)".*/\1/p' "$xml" | head -n 1)"
total="${total:-0}"; failed="${failed:-0}"; errors="${errors:-0}"
failed=$((failed + errors))
passed=$((total - failed))

printf 'studio-test: %s passed, %s failed\n' "$passed" "$failed"
awk '
  /<testcase/ { name = $0; gsub(/classname="[^"]*"/, "", name); sub(/.*name="/, "", name); sub(/".*/, "", name) }
  /<failure|<error/ { if (name != "") { print "  FAIL " name; name = "" } }
' "$xml"
printf 'report: %s\nlog: %s\n' "$xml_rel" ".studio/reports/test-$stamp.log"

[ "$failed" -eq 0 ] && [ "$engine_status" -eq 0 ]
