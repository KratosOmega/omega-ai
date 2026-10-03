#!/bin/sh
# slowest.sh [N] — where the suite's time goes, from the newest JUnit report
# test.sh wrote (.studio/reports/test-<stamp>.xml). Invoked by studio-dispatch
# (`studio-test --slowest [N]`) from the project root; reads only, so it runs
# while a test run holds the gate.
#
# Prints the report's totals, the N slowest files (total time, test count,
# mean per test) and the N slowest tests (default N 10), then the share of the
# time spent in the top N files and in tests of 0.5 s or more.
# Exit: 0 · 1 no report, or N not a number.
set -u

N="${1:-10}"
case "$N" in
  ''|*[!0-9]*|0) echo "usage: studio-test --slowest [N]" >&2; exit 1 ;;
esac
[ $# -le 1 ] || { echo "usage: studio-test --slowest [N]" >&2; exit 1; }

# The stamp sorts by time, so the last name is the newest report.
xml="$(ls .studio/reports/test-*.xml 2>/dev/null | sort | tail -n 1)"
if [ -z "$xml" ]; then
  echo "studio-test: no JUnit report in .studio/reports — run studio-test first" >&2
  exit 1
fi

# GUT writes one element per line. Each <testcase> becomes "time<TAB>file<TAB>name".
cases="$(awk '
  function attr(line, key,   m) {
    if (match(line, " " key "=\"[^\"]*\"")) { m = substr(line, RSTART, RLENGTH); sub(/^ [a-z_]*="/, "", m); sub(/"$/, "", m); return m }
    return ""
  }
  /<testsuite / { file = attr($0, "name") }
  /<testcase / { f = attr($0, "classname"); if (f == "") f = file; printf "%s\t%s\t%s\n", attr($0, "time") + 0, f, attr($0, "name") }
' "$xml")"

printf '%s\n' "$cases" | awk -F '\t' -v n="$N" -v xml="$xml" '
  NF < 3 { next }
  { t[$2] += $1; c[$2]++; total += $1; tests++; if ($1 >= 0.5) { slow++; slowt += $1 } }
  END {
    files = 0; for (f in t) files++
    printf "studio-test --slowest: %s — %d tests in %d files, %.1f s\n", xml, tests, files, total
    # Selection sort over at most n rows: n is small, files may be thousands.
    print "slowest files:"
    for (k = 1; k <= n; k++) {
      best = ""; for (f in t) if (!(f in done) && (best == "" || t[f] > t[best])) best = f
      if (best == "") break
      done[best] = 1; top += t[best]
      printf "  %8.1f s  %5d tests  %6.2f s/test  %s\n", t[best], c[best], t[best] / c[best], best
    }
    if (total > 0) {
      printf "top %d files: %.1f s (%d%% of the time)\n", k - 1, top, top * 100 / total + 0.5
      printf "tests at 0.5 s or more: %d of %d, %.1f s (%d%% of the time)\n", slow, tests, slowt, slowt * 100 / total + 0.5
    }
  }'
echo "slowest tests:"
printf '%s\n' "$cases" | awk -F '\t' 'NF >= 3' | sort -t "$(printf '\t')" -k1,1 -g -r | head -n "$N" |
  awk -F '\t' '{ printf "  %8.2f s  %s  %s\n", $1, $2, $3 }'
