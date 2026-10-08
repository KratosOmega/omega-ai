#!/bin/sh
# test.sh [PATH] — run the GUT suite headless. Invoked by studio-dispatch
# from the project root.
#
#   PATH   a test file (-gtest=res://PATH) or directory (-gdir=res://PATH);
#          default the GUT config's dirs, else res://tests, subdirectories
#          included. The project's .gutconfig.json (root or tests/) is always
#          passed, so its hooks run.
# test.sh --file A,B   only those test files (comma list of project-relative
#          paths, each must exist): -gdir= -gtest=res://A,res://B.
#
# Exit: 0 all passed · 1 failures, no tests run, a crash, a failed import (or
#       not a project) · 2 no Godot binary · 3 GUT not installed · 4 a missing
#       test file (--file). Prints
#       "studio-test: N passed, M failed", then the failing test names. JUnit
#       XML and the engine log are written to .studio/reports/test-<stamp>.{xml,log}.
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

# The project's own GUT config: res://.gutconfig.json (GUT's default), else
# res://tests/.gutconfig.json. It carries the project's pre/post-run hooks —
# phoenix's pins its heavy resources for the run and watches for leaks —
# so running without it is slower and less isolated, not just different.
gutconfig=""
for c in .gutconfig.json tests/.gutconfig.json; do
  if [ -f "$PROJECT/$c" ]; then gutconfig="$c"; break; fi
done

# Target: a file becomes -gtest, a directory becomes -gdir. Paths are given
# relative to the project root and turned into res:// paths. Command-line
# options win over the config's, and GUT runs the config's dirs as well as any
# -gtest, so a targeted run empties dirs (-gdir=). With no PATH, the config's
# own dirs are the suite when it names any.
target="${1:-}"
target="${target#./}"
target="${target%/}"
if [ "$target" = --file ]; then
  # File run (#59 R3). Probe 2026-10-07, GUT 9.6.0: GUT auto-loads
  # res://.gutconfig.json even without -gconfig, and the config's dirs run as
  # well unless -gdir= empties them. So with a config the file form is always
  # -gconfig + -gdir= + -gtest (comma list); never "simplify" it by dropping
  # -gconfig — that runs the whole suite. See the spec
  # docs/game-dev/specs/2026-10-07-overnight-hardening.md (Probe).
  _tf=""; _tf_ifs="$IFS"; IFS=,; set -f
  for _tf_p in ${2:-}; do
    IFS="$_tf_ifs"
    [ -f "$PROJECT/$_tf_p" ] || { echo "studio-test: no such test file $_tf_p" >&2; exit 4; }
    _tf="${_tf:+$_tf,}res://$_tf_p"
  done
  IFS="$_tf_ifs"; set +f
  [ -n "$_tf" ] || { echo "studio-test: --file needs a test file" >&2; exit 4; }
  set -- "-gtest=$_tf"
  [ -z "$gutconfig" ] || set -- "-gdir=" "$@"
elif [ -n "$target" ] && [ -f "$PROJECT/$target" ]; then
  set -- "-gtest=res://$target"
  [ -z "$gutconfig" ] || set -- "-gdir=" "$@"
elif [ -n "$target" ] || [ -z "$gutconfig" ] || ! grep -q '"dirs"' "$PROJECT/$gutconfig"; then
  set -- "-gdir=res://${target:-tests}" "-ginclude_subdirs"
else
  set --
fi
[ -z "$gutconfig" ] || set -- "-gconfig=res://$gutconfig" "$@"

mkdir -p "$PROJECT/.studio/reports"
stamp="$(date +%Y%m%d-%H%M%S)"
xml_rel=".studio/reports/test-$stamp.xml"
log="$PROJECT/.studio/reports/test-$stamp.log"

# An absent or incomplete import cache (a fresh worktree, a killed import, a
# branch that adds assets with their .import files) is imported first; an
# import that fails stops here rather than minutes into the suite (import.sh).
. "$HERE/import.sh"
ensure_import "$GODOT" "$PROJECT" "$log" studio-test || exit 1

"$GODOT" --headless --path "$PROJECT" -s addons/gut/gut_cmdln.gd \
  "$@" -gexit "-gjunit_xml_file=res://$xml_rel" >> "$log" 2>&1
engine_status=$?

# A Godot crash prints "handle_crash: Program crashed with signal N"; GUT prints
# each test script's res:// path on a line of its own as it starts it (an inner
# class as res://x.gd.Inner), so the last such line before the crash names the
# script that was running. Once GUT prints its Run Summary or "Results saved
# to", the run is over: the paths it lists then are a summary, not a run, and a
# crash after them is one at shutdown.
crash_line() {
  awk '
    /= Run Summary/ || /^Results saved to / { script = ""; after = 1 }
    !after && /^res:\/\/.*\.gd(\.[A-Za-z0-9_]+)?$/ { script = $0; sub(/\.gd\.[A-Za-z0-9_]+$/, ".gd", script) }
    /handle_crash: Program crashed with signal/ { sig = $NF; at = script; late = after; exit }
    END {
      if (sig == "") exit
      if (late) printf "studio-test: Godot crashed (signal %s) at shutdown, after the run\n", sig
      else printf "studio-test: Godot crashed (signal %s)%s\n", sig, (at != "" ? " while running " at : "")
    }
  ' "$log"
}

# GUT names the report -gjunit_xml_file, or adds a timestamp to it when the
# config sets junit_xml_timestamp; the newest match is this run's.
xml="$(ls "$PROJECT/.studio/reports/test-$stamp"*.xml 2>/dev/null | sort | tail -n 1)"
if [ -n "$xml" ]; then xml_rel="${xml#"$PROJECT"/}"; fi
if [ -z "$xml" ]; then
  crash_line >&2
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
# The report can be whole while the engine still failed (a crash at shutdown).
if [ "$engine_status" -ne 0 ]; then
  crash_line
  printf 'studio-test: Godot exited %s after writing the report%s\n' "$engine_status" \
    "${gutconfig:+ (a post-run hook in $gutconfig can fail the run; see the log)}"
fi
# GUT passes a run that found nothing to run: a mistyped PATH, or a config
# whose dirs are empty. A gate that ran no tests is not green.
if [ "$total" -eq 0 ]; then
  echo "studio-test: no tests ran (check PATH or the config's dirs)"
  exit 1
fi

[ "$failed" -eq 0 ] && [ "$engine_status" -eq 0 ]
