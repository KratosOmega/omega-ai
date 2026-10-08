#!/bin/sh
# studio-env: the resource readout (#37). Every case reads fake command output
# from a STUDIO_ENV_FIXTURE dir, so macOS and Linux are covered on either OS.
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"
ENV_BIN="$REPO_ROOT/studios/game-dev/bin/studio-env"
mk_tmp studio_env_test
trap 'rm_tmp "$TMP"' EXIT
FX="$TMP/fx"

# mac LOAD5 PRESSURE SWAP_USED — a macOS fixture: 10 cores, 182 GB free, on AC.
# Process 99 is the runner; Godot (30) is its child.
mac() {
  rm -rf "$FX"; mkdir -p "$FX"
  echo Darwin > "$FX/uname"
  echo "{ 1.00 $1 1.00 }" > "$FX/sysctl.vm.loadavg"
  echo 10 > "$FX/sysctl.hw.ncpu"
  echo "$2" > "$FX/sysctl.kern.memorystatus_vm_pressure_level"
  echo "total = 4096.00M  used = $3  free = 1024.00M  (encrypted)" > "$FX/sysctl.vm.swapusage"
  printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/disk3s5 971350180 700000000 190840000 79%% /System/Volumes/Data\n' > "$FX/df"
  printf "Now drawing from 'AC Power'\n -InternalBattery-0 (id=1)\t100%%; charged; 0:00 remaining present: true\n" > "$FX/pmset"
  printf '  PID  PPID      RSS  %%CPU COMM\n 10     1  4300000   2.0 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome\n 11    10   500000   1.0 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome Helper\n 20     1  1250000   0.5 /Applications/Slack.app/Contents/MacOS/Slack\n 30    99   950000  90.0 /Applications/Godot.app/Contents/MacOS/Godot\n 99     1     9000   0.0 /usr/bin/studio-overnight\n' > "$FX/ps"
}
# linux LOAD5 AVAIL_KB — a Linux fixture: 4 cores, 8 GB, no swap in use, 182 GB free.
linux() {
  rm -rf "$FX"; mkdir -p "$FX"
  echo Linux > "$FX/uname"
  echo "0.50 $1 0.50 1/200 123" > "$FX/proc.loadavg"
  echo 4 > "$FX/nproc"
  printf 'MemTotal:        8388608 kB\nMemFree:          100000 kB\nMemAvailable:   %8s kB\nSwapTotal:       2097152 kB\nSwapFree:        2097152 kB\n' "$2" > "$FX/proc.meminfo"
  printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/sda1 971350180 700000000 190840000 79%% /\n' > "$FX/df"
  printf '  PID  PPID   RSS %%CPU COMMAND\n 10 1 3000000 1.0 firefox\n 20 1 500000 80.0 cc1plus\n 99 1 1000 0.0 studio-overnight\n' > "$FX/ps"
}
# env_run [ARGS] — studio-env on the fixture; stdout env.out, exit ENV_RC.
env_run() {
  ENV_RC=0
  STUDIO_ENV_FIXTURE="$FX" sh "$ENV_BIN" "$@" > "$TMP/env.out" 2> "$TMP/env.err" || ENV_RC=$?
}

test_env_mac_normal() {
  mac 3.1 1 "410.00M"
  env_run --dir "$TMP"
  assert_eq 0 "$ENV_RC" "exit 0"
  assert_eq "env: cpu 3.1/10 · memory ok (swap 0.4 GB) · disk 182 GB free · power AC" "$(cat "$TMP/env.out")" "one summary line and no warning block"
}
test_env_mac_pressure() {
  mac 3.1 2 "3277.00M"
  env_run --dir "$TMP" --run-pid 99
  assert_eq 0 "$ENV_RC" "exit 0 on a warning"
  assert_contains "$TMP/env.out" "^env: cpu 3.1/10 · memory warn (swap 3.2 GB) · disk" "summary says warn"
  assert_contains "$TMP/env.out" "^⚠ memory pressure high, swap 3.2 GB — close something; top by memory:$" "warning line"
  assert_contains "$TMP/env.out" "^    Google Chrome 4.1 GB · Slack 1.2 GB · Godot 0.9 GB (this run) · Google Chrome Helper 0.5 GB · studio-overnight 0.0 GB (this run)$" "top 5 by memory, with the runner's tree marked"
  mac 3.1 4 "100.00M"
  env_run --dir "$TMP"
  assert_contains "$TMP/env.out" "memory critical (swap 0.1 GB)" "pressure 4 is critical"
  assert_contains "$TMP/env.out" "^⚠ memory pressure critical" "critical warning"
}
test_env_mac_top_five_only() {
  mac 3.1 2 "100.00M"
  printf ' 40 1 800000 0.0 /x/Six\n' >> "$FX/ps"
  env_run --dir "$TMP"
  assert_contains "$TMP/env.out" "^    Google Chrome 4.1 GB · Slack 1.2 GB · Godot 0.9 GB · Six 0.8 GB · Google Chrome Helper 0.5 GB · …$" "only 5 are listed, then an ellipsis"
}
test_env_mac_swap_alone() {
  mac 3.1 1 "3277.00M"
  env_run --dir "$TMP"
  assert_contains "$TMP/env.out" "^⚠ swap 3.2 GB in use — close something; top by memory:$" "swap over 2 GB warns by itself"
}
test_env_mac_battery() {
  mac 3.1 1 "0.00M"
  printf "Now drawing from 'Battery Power'\n -InternalBattery-0 (id=1)\t80%%; discharging; 4:00 remaining present: true\n" > "$FX/pmset"
  env_run --dir "$TMP"
  assert_contains "$TMP/env.out" "power battery" "summary says battery"
  assert_contains "$TMP/env.out" "^⚠ on battery — plug in (caffeinate does not stop lid-close sleep)$" "battery warning"
}
test_env_mac_cpu() {
  mac 25.0 1 "0.00M"
  env_run --dir "$TMP"
  assert_contains "$TMP/env.out" "^env: cpu 25.0/10 " "load over 2x cores"
  assert_contains "$TMP/env.out" "^⚠ cpu load 25.0 on 10 cores — something is busy; top by cpu:$" "cpu warning"
  assert_contains "$TMP/env.out" "^    Godot 90% cpu · " "the busiest process first"
  mac 12.0 1 "0.00M"
  env_run --dir "$TMP"
  assert_contains "$TMP/env.out" "^⚠ cpu load 12.0 on 10 cores" "load over cores is a warning"
  mac 10.0 1 "0.00M"
  env_run --dir "$TMP"
  assert_not_contains "$TMP/env.out" "⚠" "load equal to cores is fine"
}
test_env_linux() {
  linux 1.5 6000000
  env_run --dir "$TMP"
  assert_eq "env: cpu 1.5/4 · memory ok (swap 0.0 GB) · disk 182 GB free" "$(cat "$TMP/env.out")" "linux: no power field"
  linux 1.5 600000
  env_run --dir "$TMP"
  assert_contains "$TMP/env.out" "memory warn" "7% available is a warning"
  assert_contains "$TMP/env.out" "^⚠ memory low (7% available)" "linux memory words"
  assert_contains "$TMP/env.out" "firefox 2.9 GB" "top by memory"
  linux 1.5 300000
  env_run --dir "$TMP"
  assert_contains "$TMP/env.out" "memory critical" "3% available is critical"
  linux 9.0 6000000
  env_run --dir "$TMP"
  assert_contains "$TMP/env.out" "^⚠ cpu load 9.0 on 4 cores" "linux high load"
  linux 0.5 6000000
  printf 'MemTotal: 8388608 kB\nMemAvailable: 6000000 kB\nSwapTotal: 8388608 kB\nSwapFree: 2097152 kB\n' > "$FX/proc.meminfo"
  env_run --dir "$TMP"
  assert_contains "$TMP/env.out" "^⚠ swap 6.0 GB in use" "linux swap is SwapTotal minus SwapFree"
}
test_env_disk() {
  linux 1.0 6000000
  printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/sda1 971350180 700000000 12582912 79%% /\n' > "$FX/df"
  env_run --dir "$TMP"
  assert_contains "$TMP/env.out" "^⚠ disk 12 GB free on $TMP" "under 20 GB warns"
  printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/sda1 971350180 700000000 2097152 79%% /\n' > "$FX/df"
  env_run --dir "$TMP"
  assert_contains "$TMP/env.out" "^⚠ disk 2 GB free on $TMP — critical" "under 5 GB is critical"
}
test_env_unknowns() {
  mac 3.1 1 "0.00M"
  rm "$FX/sysctl.vm.loadavg" "$FX/df" "$FX/sysctl.kern.memorystatus_vm_pressure_level" "$FX/pmset"
  env_run --dir "$TMP"
  assert_eq 0 "$ENV_RC" "unreadable sources never fail"
  assert_eq "env: cpu ? · memory ? (swap 0.0 GB) · disk ? · power ?" "$(cat "$TMP/env.out")" "each is shown as ?"
  rm -rf "$FX"; mkdir -p "$FX"
  env_run
  assert_eq 0 "$ENV_RC" "an empty fixture dir exits 0"
  assert_contains "$TMP/env.out" "^env: " "and still prints a summary"
}
test_env_this_run() {
  mac 3.1 2 "3277.00M"
  env_run --dir "$TMP" --run-pid 99
  assert_contains "$TMP/env.out" "studio-overnight 0.0 GB (this run)" "the runner itself is marked"
  assert_contains "$TMP/env.out" "Godot 0.9 GB (this run)" "its child is marked"
  assert_not_contains "$TMP/env.out" "Slack 1.2 GB (this run)" "an unrelated process is not"
  printf '  PID  PPID      RSS  %%CPU COMM\n 5 1 100000 1.0 /bin/runner\n 6 5 3000000 1.0 /x/child\n 7 6 2000000 1.0 /x/grandchild\n 8 1 1000000 1.0 /x/other\n' > "$FX/ps"
  env_run --dir "$TMP" --run-pid 5
  assert_contains "$TMP/env.out" "child 2.9 GB (this run)" "a child of the runner"
  assert_contains "$TMP/env.out" "grandchild 1.9 GB (this run)" "a grandchild of the runner"
  assert_contains "$TMP/env.out" "other 1.0 GB ·" "a sibling is not marked"
  assert_not_contains "$TMP/env.out" "other 1.0 GB (this run)" "a sibling is not marked"
}
test_env_args() {
  mac 3.1 1 "0.00M"
  env_run --bogus
  assert_eq 0 "$ENV_RC" "an unknown option still exits 0"
  assert_contains "$TMP/env.out" "^env: " "and prints the summary"
}
test_env_real_machine() {
  ENV_RC=0
  sh "$ENV_BIN" --dir "$TMP" > "$TMP/real.out" 2>&1 || ENV_RC=$?
  assert_eq 0 "$ENV_RC" "the real machine: exit 0"
  assert_contains "$TMP/real.out" "^env: cpu " "a summary line"
}

test_env_option_values_consumed() {
  # An option's value is consumed with it, whatever the value looks like.
  linux 0.5 4000000
  env_run --run-pid 99 --dir "$TMP"
  assert_contains "$TMP/env.out" "^env: cpu 0.5/4 · .* · disk 182 GB free" "both separate-value options read"
  env_run --dir --run-pid
  assert_eq 0 "$ENV_RC" "an option missing its value still exits 0"
}

run_tests test_env_mac_normal test_env_mac_pressure test_env_mac_top_five_only test_env_mac_swap_alone \
  test_env_mac_battery test_env_mac_cpu test_env_linux test_env_disk test_env_unknowns test_env_this_run \
  test_env_args test_env_real_machine \
  test_env_option_values_consumed
