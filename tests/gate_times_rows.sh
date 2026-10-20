# gate_times_rows.sh — sourced by suites that read STATE_ROOT/.studio/gate.times (not a suite).
# gt_rows FILE WHO RC — 8-field gate.times rows of WHO with rc RC (#71 R6).
gt_rows() { awk -v w="$2" -v r="$3" 'NF == 8 && $2 == w && $4 == r { n++ } END { print n + 0 }' "$1" 2>/dev/null; }
# gt_row FILE WHO — the newest 8-field row of WHO.
gt_row() { awk -v w="$2" 'NF == 8 && $2 == w { l = $0 } END { print l }' "$1" 2>/dev/null; }
