#!/bin/sh
# overnight-lanes.sh — studio-overnight's manifest mode (D18): the run
# manifest, dependency chains, the manifest preflight, the dry run, and the
# run itself: lane processes, each running its chains' stories one fresh
# session per unit (story_units), then each story's landing.
# Sourced by studio-overnight after its own helpers (say, sq, refuse, state,
# cfg*, deny_rules, model_for, label_for, with_launch_args, print_launch,
# run_unit, row, snapshot, story_units, acquire_run_lock, run_setup, unlock)
# are defined and its preflight has run; never run on its own. Reads studio
# state and the manifest; never writes either. It redefines stop_requested,
# spent_all and spent for manifest mode.
[ -n "${SELF_DIR:-}" ] || { echo "overnight-lanes.sh: sourced by studio-overnight" >&2; exit 2; }

# git_retry ARGS… — git ARGS, retried up to three times (sleeps 1, 2, 4 s)
# while its stderr says a lock or ref could not be taken (D21). Stdout passes
# through; the last attempt's stderr is printed. Every runner git write
# (fetch, push, worktree add, commit-tree) goes through it.
git_retry() {
  _gr_d=1
  while :; do
    { _gr_err="$(git "$@" 2>&1 1>&3 3>&-)"; _gr_st=$?; } 3>&1
    if [ "$_gr_st" -ne 0 ] && [ "$_gr_d" -le 4 ] \
       && printf '%s\n' "$_gr_err" | grep -Eq 'could not lock|cannot lock ref'; then
      sleep "$_gr_d"; _gr_d=$((_gr_d * 2)); continue
    fi
    [ -z "$_gr_err" ] || printf '%s\n' "$_gr_err" >&2
    return "$_gr_st"
  done
}

# mf_header NAME — the first `NAME:` header line's value, a trailing ` #…`
# comment and trailing blanks stripped (D26; the rule studio-brief uses).
mf_header() {
  sed -n "s/^$1:[ 	]*//p" "$MF" | head -n 1 | sed -e 's/[ 	]#.*$//' -e 's/[ 	]*$//'
}

# mf_load MANIFEST — parse the manifest: sets MF, MF_SLUG, MF_MODE,
# MF_TARGET, MF_DOCS, MF_GOAL and writes $MF_ROWS (set by the caller), one
# TSV row per story: id branch ticket spec plan deps (deps comma-joined, no
# spaces; empty for '-'). Returns 1 (after a refusal) when there is no file.
mf_load() {
  MF="$1"
  case "$MF" in /*) ;; *) MF="$START_DIR/$MF" ;; esac
  [ -f "$MF" ] || { refuse "no manifest at $1"; return 1; }
  MF_SLUG="$(sed -n 's/^# Run:[ 	]*//p' "$MF" | head -n 1 | sed -e 's/[ 	]#.*$//' -e 's/[ 	]*$//')"
  MF_MODE="$(mf_header Mode)"; MF_TARGET="$(mf_header Target)"
  MF_DOCS="$(mf_header Docs)"; MF_GOAL="$(mf_header Goal)"
  awk -F'|' '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    /^\|/ {
      for (i = 1; i <= NF; i++) c[i] = trim($i)
      if (!hdr) { for (i = 1; i <= NF; i++) col[c[i]] = i; if ("Story" in col) hdr = 1; next }
      if (c[2] ~ /^:?-+:?$/) next
      d = c[col["Depends on"]]; gsub(/[ \t]/, "", d); if (d == "-") d = ""
      printf "%s\t%s\t%s\t%s\t%s\t%s\n", c[col["Story"]], c[col["Branch"]], c[col["Ticket"]], c[col["Spec"]], c[col["Plan"]], d }
  ' "$MF" > "$MF_ROWS"
}

# row_field ID FIELD — one cell of ID's (first) row; FIELD is branch,
# ticket, spec, plan or deps.
row_field() {
  case "$2" in
    branch) _rf=2 ;; ticket) _rf=3 ;; spec) _rf=4 ;; plan) _rf=5 ;; deps) _rf=6 ;;
    *) say "row_field: no field $2"; exit 3 ;;
  esac
  awk -F'\t' -v id="$1" -v f="$_rf" '$1 == id { print $f; exit }' "$MF_ROWS"
}

# story_state ID ARGS… — studio-state ARGS for story ID, from START_DIR.
story_state() { _ss_id="$1"; shift; ( cd "$START_DIR" && STUDIO_STORY="$_ss_id" sh "$STATE_BIN" "$@" ); }

# git_version_ok — git is 2.38 or newer (merge-tree --write-tree).
git_version_ok() {
  git --version 2>/dev/null | sed -n 's/^git version \([0-9]*\)\.\([0-9]*\).*/\1 \2/p' \
    | awk '{ exit !($1 > 2 || ($1 == 2 && $2 >= 38)) } END { if (NR == 0) exit 1 }'
}

# mf_check — the manifest preflight: one refuse per failure (spec 806-815).
mf_check() {
  git_version_ok || refuse "git 2.38 or newer is required (git merge-tree --write-tree); found $(git --version 2>/dev/null)"
  printf '%s\n' "$MF_SLUG" | grep -Eq '^[A-Za-z0-9._-]+$' \
    || refuse "manifest: '# Run: <slug>' must name a slug of [A-Za-z0-9._-], got '$MF_SLUG'"
  case "$MF_MODE" in
    integration) _want="integration/$MF_SLUG" ;;
    direct)
      _want="$DEFAULT_BRANCH"
      [ -n "${MERGE_COMMAND:-}" ] || refuse "manifest: Mode direct needs merge_command in .studio/config.json" ;;
    *) _want=""; refuse "manifest: Mode must be integration or direct, got '$MF_MODE'" ;;
  esac
  [ -z "$_want" ] || [ "$MF_TARGET" = "$_want" ] \
    || refuse "manifest: Target must be $_want for Mode $MF_MODE, got '$MF_TARGET'"
  [ -n "$MF_GOAL" ] || refuse "manifest: no Goal: line"
  [ -s "$MF_ROWS" ] || refuse "manifest: no story rows (a | Story | … | table)"

  # Rows: ids, uniqueness, '-' cells, dependencies on earlier rows only.
  awk -F'\t' '
    { id = $1
      if (id !~ /^[A-Za-z0-9._-]+$/) print "manifest: story id '\''" id "'\'' must match ^[A-Za-z0-9._-]+$"
      if (id in seen) print "manifest: duplicate story " id
      if ($2 == "" || $2 == "-" || $3 == "") print "manifest: " id ": Branch or Ticket is empty"
      if ($4 == "" || $4 == "-" || $5 == "" || $5 == "-") print "manifest: " id ": Spec or Plan is '\''-'\'' (plan every story first)"
      n = split($6, ds, ",")
      for (i = 1; i <= n; i++) if (ds[i] != "" && !(ds[i] in seen))
        print "manifest: " id " depends on " ds[i] ", which is not an earlier row"
      seen[id] = 1 }
  ' "$MF_ROWS" > "$MF_TMP/row-refusals"
  while IFS= read -r _l; do refuse "$_l"; done < "$MF_TMP/row-refusals"

  # Origin: one fetch, then the docs revision and the target branch.
  git_retry -C "$START_DIR" fetch -q origin || refuse "git fetch origin failed"
  _docs_ok=0
  if ! git_retry -C "$START_DIR" fetch -q origin "run/$MF_SLUG" 2>/dev/null; then
    refuse "manifest: origin/run/$MF_SLUG does not exist (push the run branch)"
  elif ! printf '%s\n' "$MF_DOCS" | grep -Eq '^[0-9a-f]{7,40}$'; then
    refuse "manifest: Docs: must be a commit sha, got '$MF_DOCS'"
  elif _full="$(git -C "$START_DIR" rev-parse -q --verify "$MF_DOCS^{commit}" 2>/dev/null)" \
       && git -C "$START_DIR" merge-base --is-ancestor "$_full" "refs/remotes/origin/run/$MF_SLUG" 2>/dev/null; then
    MF_DOCS="$_full"; _docs_ok=1
  else
    refuse "manifest: Docs: $MF_DOCS is not on origin/run/$MF_SLUG"
  fi
  if [ "$MF_MODE" = integration ]; then
    git -C "$START_DIR" rev-parse -q --verify "refs/remotes/origin/integration/$MF_SLUG" >/dev/null \
      || refuse "manifest: origin/integration/$MF_SLUG does not exist (create it from origin/$DEFAULT_BRANCH and push it)"
  fi

  # Per story (first row of each id): state, ledger, and the plan at Docs:.
  awk -F'\t' '!($1 in seen) { seen[$1] = 1; print $1 "\t" $5 }' "$MF_ROWS" > "$MF_TMP/stories"
  while IFS='	' read -r _id _plan; do
    printf '%s\n' "$_id" | grep -Eq '^[A-Za-z0-9._-]+$' || continue
    if [ ! -f "$STATE_ROOT/.studio/stories/$_id.md" ]; then
      refuse "$_id: no story file (.studio/stories/$_id.md; studio-state init with STUDIO_STORY=$_id)"
    else
      _show="$(story_state "$_id" show 2>/dev/null)"
      case "$_plan" in ''|-) ;; *)
        printf '%s\n' "$_show" | sed -n 's/^- [0-9-]* plan approved //p' | grep -qxF -- "$_plan" \
          || refuse "$_id: no 'plan approved $_plan' ledger line" ;;
      esac
      printf '%s\n' "$_show" | grep -qx -- "- [0-9-]* Decisions swept $_id" \
        || refuse "$_id: no 'Decisions swept $_id' ledger line (run the question sweep)"
      _stg="$(story_state "$_id" get stage 2>/dev/null)"
      case "$_stg" in
        plan|execute) ;;
        idle) printf '%s\n' "$_show" | grep -q '^- [0-9-]* shipped ' \
                || refuse "$_id: stage idle with no shipped line: nothing approved to run" ;;
        *) refuse "$_id: stage $_stg: nothing approved to run" ;;
      esac
    fi
    if [ -n "$(git -C "$START_DIR" status --porcelain -- ".studio/ledger/$_id.md" 2>/dev/null)" ]; then
      refuse "$_id: uncommitted ledger change (.studio/ledger/$_id.md) — read the Stop: line, resolve it, commit"
    fi
    case "$_plan" in ''|-) continue ;; esac
    [ "$_docs_ok" -eq 1 ] || continue
    if ! git -C "$START_DIR" show "$MF_DOCS:$_plan" > "$MF_TMP/plan" 2>/dev/null; then
      refuse "$_id: plan $_plan is not in Docs: $MF_DOCS"; continue
    fi
    grep -q '^## Decisions' "$MF_TMP/plan" || refuse "$_id: plan has no ## Decisions section"
    grep -qx "Story: $_id" "$MF_TMP/plan" || refuse "$_id: plan has no 'Story: $_id' line"
    awk '
      function close_task() { if (task != "" && !spec) print task; task = "" }
      /^### Task / { close_task(); task = $0; spec = 0; next }
      /^## / { close_task(); next }
      /^Spec:/ { spec = 1 }
      END { close_task() }
    ' "$MF_TMP/plan" | while IFS= read -r _t; do
      printf '%s\n' "$_id: plan task has no Spec: line ($_t)"
    done > "$MF_TMP/spec-refusals"
    while IFS= read -r _l; do refuse "$_l"; done < "$MF_TMP/spec-refusals"
  done < "$MF_TMP/stories"
}

# build_chains — $CHAINS from $MF_ROWS by the chain rule (spec 479-487), one
# line per chain: <k>\t<waits csv or ->\t<id> <id> …. A row with exactly one
# dependency that is its chain's last story appends; a fork or several
# dependencies open a waiting chain.
build_chains() {
  awk -F'\t' '
    { id = $1; d = $6
      if (d == "" || d == "-") { open_chain(id, "-"); next }
      n = split(d, ds, ",")
      if (n == 1 && (ds[1] in chainof) && last[chainof[ds[1]]] == ds[1]) {
        k = chainof[ds[1]]; members[k] = members[k] " " id; last[k] = id; chainof[id] = k; next
      }
      open_chain(id, d) }
    function open_chain(id, w) { k = ++nc; members[k] = id; waits[k] = w; last[k] = id; chainof[id] = k }
    END { for (k = 1; k <= nc; k++) printf "%d\t%s\t%s\n", k, waits[k], members[k] }
  ' "$MF_ROWS" > "$CHAINS"
}
# chain_of ID — the chain number holding ID.
chain_of() {
  awk -F'\t' -v id="$1" '{ n = split($3, m, " "); for (i = 1; i <= n; i++) if (m[i] == id) { print $1; exit } }' "$CHAINS"
}
# chain_members K — chain K's ids, space-separated, in order.
chain_members() { awk -F'\t' -v k="$1" '$1 == k { print $3; exit }' "$CHAINS"; }
# chain_waits K — chain K's dependencies, comma-separated, or '-'.
chain_waits() { awk -F'\t' -v k="$1" '$1 == k { print $2; exit }' "$CHAINS"; }

# story_launch_env ID — the env words of a unit launch for story ID (spec
# 686-687), each KEY='value' with the value single-quoted (sq):
# OMEGA_AUTOPILOT STUDIO_RUN (abs RUN_DIR/manifest.md) STUDIO_STORY
# STUDIO_DOCS_REV BASH_DEFAULT_TIMEOUT_MS BASH_MAX_TIMEOUT_MS (both
# session_minutes × 60000).
story_launch_env() {
  _ms=$((SESSION_MINUTES * 60000))
  printf 'OMEGA_AUTOPILOT=%s STUDIO_RUN=%s STUDIO_STORY=%s STUDIO_DOCS_REV=%s BASH_DEFAULT_TIMEOUT_MS=%s BASH_MAX_TIMEOUT_MS=%s' \
    "$(sq 1)" "$(sq "$RUN_DIR/manifest.md")" "$(sq "$1")" "$(sq "$MF_DOCS")" "$(sq "$_ms")" "$(sq "$_ms")"
}

# story_first_label ID — the label of ID's next unit from its studio state
# (label_for's rule); empty for a story at idle (shipped: it only lands).
story_first_label() {
  SIG_STAGE="$(story_state "$1" get stage 2>/dev/null)"; SIG_TASK="$(story_state "$1" get task 2>/dev/null)"
  [ "$SIG_STAGE" != idle ] || return 0
  SIG_FRD="$(story_state "$1" show 2>/dev/null | grep -c '^- [0-9-]* final review done$')"
  label_for
}

# lanes_dry_run — the chains, each chain's first launch line, the deny count.
lanes_dry_run() {
  while IFS='	' read -r _k _w _m; do
    if [ "$_w" = - ]; then printf 'chain %s: %s\n' "$_k" "$_m"
    else printf 'chain %s (waits on %s): %s\n' "$_k" "$_w" "$_m"; fi
  done < "$CHAINS"
  while IFS='	' read -r _k _w _m; do
    _id="${_m%% *}"
    _lbl="$(story_first_label "$_id")"
    if [ -z "$_lbl" ]; then printf '# %s: shipped; it lands with no unit\n' "$_id"; continue; fi
    model_for "$_lbl"
    LAUNCH_ENV="$(story_launch_env "$_id")"
    with_launch_args print_launch
    LAUNCH_ENV=""
  done < "$CHAINS"
  printf 'deny: %s rules\n' "$(deny_rules | grep -c .)"
}

# ---- The run: lanes and the per-story unit loop (spec 489-499, 517-544) ----

# story_write ID TEXT — RUN_DIR/stories/ID = TEXT (D19), by temp file and mv
# so a reader never sees half a line. Only the lane holding ID writes it,
# plus the parent before the lanes start and in its sweep.
story_write() {
  printf '%s\n' "$2" > "$RUN_DIR/stories/.$1.tmp" && mv -f "$RUN_DIR/stories/.$1.tmp" "$RUN_DIR/stories/$1"
}
# story_get ID — the story's record line (empty when none).
story_get() { cat "$RUN_DIR/stories/$1" 2>/dev/null; }

# record_landed ID SHA — the D27 line `<id>\t<Target>\t<sha>\t<epoch>` in
# RECORD/landed.tsv (only when the id has none), then stories/ID = landed SHA.
record_landed() {
  awk -F'\t' -v id="$1" '$1 == id { f = 1 } END { exit !f }' "$RECORD/landed.tsv" 2>/dev/null \
    || printf '%s\t%s\t%s\t%s\n' "$1" "$MF_TARGET" "$2" "$(date +%s)" >> "$RECORD/landed.tsv"
  story_write "$1" "landed $2"
}

# land_story ID — the stub landing (T10 replaces it): record the story
# branch's head on origin as landed. Returns 0 when landed; else writes the
# story's stopped ending and returns 1.
land_story() {
  _lb="$(row_field "$1" branch)"
  if ! git_retry -C "$START_DIR" fetch -q origin "+refs/heads/$_lb:refs/remotes/origin/$_lb"; then
    story_write "$1" "stopped landing failed (cannot fetch origin/$_lb)"; return 1
  fi
  _lsha="$(git -C "$START_DIR" rev-parse -q --verify "refs/remotes/origin/$_lb^{commit}")" \
    || { story_write "$1" "stopped landing failed (no origin/$_lb)"; return 1; }
  record_landed "$1" "$_lsha"
}

# Manifest mode's story_units helpers: a stop is the lane's halt, and the
# run budget sums every lane's units.tsv (spec 531-534).
stop_requested() { lane_halt; }
spent_all() {
  cat "$RUN_DIR"/lanes/*/units.tsv 2>/dev/null \
    | awk -F'\t' '$4 != "unknown" { s += $4 } END { printf "%.2f\n", s + 0 }'
}
spent() { spent_all; }

# lane_halt — true when this lane must claim and launch no more: the stop
# file exists, the runner is gone, or the lane hit the run budget.
lane_halt() {
  [ -f "$STOP_FILE" ] || ! kill -0 "$RUNNER_PID" 2>/dev/null || [ "${LANE_BUDGET:-0}" = 1 ]
}
# lane_halt_reason — why lane_halt holds, as a story_units ENDING: a stop
# file's own text (the runner's exit path writes its reason there), else
# `stopped by user` for a requested stop; `stop: runner gone` when the
# runner's pid is gone; `stop: run budget` for the lane's budget.
lane_halt_reason() {
  if [ -f "$STOP_FILE" ]; then
    _hr="$(head -n 1 "$STOP_FILE" 2>/dev/null)"; printf '%s\n' "${_hr:-stopped by user}"
  elif ! kill -0 "$RUNNER_PID" 2>/dev/null; then echo "stop: runner gone"
  elif [ "${LANE_BUDGET:-0}" = 1 ]; then echo "stop: run budget"
  else echo "stopped by user"; fi
}
# lane_stopflag — a signal to a lane requests the run's stop; it never
# truncates a stop file that already carries the runner's reason.
lane_stopflag() { [ -e "$STOP_FILE" ] || : > "$STOP_FILE"; }
# is_ending LINE — true for a story record that is an ending (D19).
is_ending() { case "$1" in landed*|stopped*|skipped*) return 0 ;; esac; return 1; }
# chain_skip_after ID TEXT — every story after ID in ID's chain that has no
# ending yet is written TEXT.
chain_skip_after() {
  _ca_seen=0
  for _ca_id in $(chain_members "$(chain_of "$1")"); do
    if [ "$_ca_seen" = 1 ]; then
      is_ending "$(story_get "$_ca_id")" || story_write "$_ca_id" "$2"
    fi
    [ "$_ca_id" != "$1" ] || _ca_seen=1
  done
}
# lane_exit RC — the lane's EXIT trap: end a live session; a story this lane
# holds that has no ending is `stopped: lane crashed (<rc>)` (D2), and the
# rest of its chain `skipped <id>`.
lane_exit() {
  trap '' INT TERM HUP
  end_session
  [ -z "${LDIR:-}" ] || rm -f "$LDIR/cpid" "$LDIR/wpid"   # ended and reaped: never signal a reused pid
  if [ -n "${CUR_ID:-}" ] && ! is_ending "$(story_get "$CUR_ID")"; then
    story_write "$CUR_ID" "stopped: lane crashed ($1)"
    chain_skip_after "$CUR_ID" "skipped $CUR_ID"
  fi
  exit "$1"
}

# pid_live PID — PID runs (a zombie counts as dead).
pid_live() {
  kill -0 "$1" 2>/dev/null || return 1
  case "$(ps -o stat= -p "$1" 2>/dev/null)" in Z*|'') return 1 ;; esac
}
# dep_landed ID — ID has a line in RECORD/landed.tsv.
dep_landed() { awk -F'\t' -v id="$1" '$1 == id { f = 1 } END { exit !f }' "$RECORD/landed.tsv" 2>/dev/null; }
# wait_deps ID DEPS — the WAITING state of a chain's first story (spec 500-516):
# stories/ID = waiting, then a poll every STUDIO_OVERNIGHT_POLL_SECONDS (D20,
# default 5) s. Returns 0 when every dependency in DEPS (comma-separated) has
# landed; 2 on lane_halt; 1 with BLOCKER=<dep> when a dependency ended
# stopped or skipped, or its chain's claiming lane is dead without its landing.
wait_deps() {
  story_write "$1" waiting
  while :; do
    lane_halt && return 2
    _wd_all=1
    for _wd_d in $(printf '%s\n' "$2" | tr ',' ' '); do
      dep_landed "$_wd_d" && continue
      _wd_all=0
      case "$(story_get "$_wd_d")" in stopped*|skipped*) BLOCKER="$_wd_d"; return 1 ;; esac
      _wd_p="$(cat "$RUN_DIR/claims/$(chain_of "$_wd_d")/pid" 2>/dev/null)"
      if [ -n "$_wd_p" ] && ! pid_live "$_wd_p" && ! dep_landed "$_wd_d"; then
        BLOCKER="$_wd_d"; return 1
      fi
    done
    [ "$_wd_all" = 0 ] || return 0
    sleep "${STUDIO_OVERNIGHT_POLL_SECONDS:-5}"
  done
}

# lane_main K — one lane, in a background subshell: claim chains in order
# (mkdir RUN_DIR/claims/<c>, the lane's pid and number inside) and run each,
# until none is left or lane_halt.
lane_main() {
  trap 'lane_exit $?' EXIT; trap 'lane_stopflag' INT TERM HUP
  LANE_K="$1"; LDIR="$RUN_DIR/lanes/$1"; UNIT_DIR="$LDIR"
  CPID=""; WPID=""; CUR_ID=""; LANE_BUDGET=0
  mkdir -p "$LDIR" || exit 3
  for _c in $(cut -f1 "$CHAINS"); do
    lane_halt && break
    mkdir "$RUN_DIR/claims/$_c" 2>/dev/null || continue
    sh -c 'echo $PPID' > "$RUN_DIR/claims/$_c/pid"   # this subshell's pid (no $BASHPID in sh)
    printf '%s\n' "$LANE_K" > "$RUN_DIR/claims/$_c/lane"
    run_chain "$_c"
  done
  exit 0
}

# run_chain C — chain C's stories in order. A waiting chain's first story
# waits for its dependencies first (wait_deps): a blocked wait skips it
# `skipped <dep>` and the rest `skipped <first id>`; a stop skips it and the
# rest `skipped: run stopped` (D2). A story after one that did not land is
# skipped `skipped <that id>`, and so is the rest of the chain (D19).
run_chain() {
  _rc_skip=""; _rc_first=1
  _rc_w="$(chain_waits "$1")"
  for _rc_id in $(chain_members "$1"); do
    if [ -n "$_rc_skip" ]; then story_write "$_rc_id" "$_rc_skip"; continue; fi
    if [ "$_rc_first" = 1 ] && [ "$_rc_w" != - ]; then
      CUR_ID="$_rc_id"   # a lane that dies while waiting still ends the story
      wait_deps "$_rc_id" "$_rc_w"; _rc_wd=$?
      CUR_ID=""
      case "$_rc_wd" in
        1) story_write "$_rc_id" "skipped $BLOCKER"; _rc_skip="skipped $_rc_id"; continue ;;
        2) story_write "$_rc_id" "skipped: run stopped"; _rc_skip="skipped: run stopped"; continue ;;
      esac
    fi
    _rc_first=0
    run_story "$_rc_id"
    case "$(story_get "$_rc_id")" in landed*) ;; *) _rc_skip="skipped $_rc_id" ;; esac
  done
}

# run_story ID — bundle 2's unit loop for one story, one fresh session per
# unit, under the story's env; then its landing.
run_story() {
  CUR_ID="$1"
  STUDIO_STORY="$1"; STUDIO_RUN="$RUN_DIR/manifest.md"; STUDIO_DOCS_REV="$MF_DOCS"
  BASH_DEFAULT_TIMEOUT_MS=$((SESSION_MINUTES * 60000)); BASH_MAX_TIMEOUT_MS="$BASH_DEFAULT_TIMEOUT_MS"
  export STUDIO_STORY STUDIO_RUN STUDIO_DOCS_REV BASH_DEFAULT_TIMEOUT_MS BASH_MAX_TIMEOUT_MS
  LAUNCH_ENV="$(story_launch_env "$1")"
  UNIT_PREFIX=""   # run_unit names files <n>-<id>-<label> from CUR_ID (T5)
  story_write "$1" running
  # A story already shipped (stage idle, a shipped line) only lands.
  snapshot "$UNIT_DIR/stops.before"
  if [ "$SIG_STAGE" = idle ] && [ "$SIG_SHIPPED" -gt 0 ]; then ENDING=done; else story_units; fi
  # story_units says `stopped by user` for any halt; name the real one. A
  # halt also holds back the landing (spec 124-127).
  [ "$ENDING" != "stopped by user" ] || ENDING="$(lane_halt_reason)"
  [ "$ENDING" != done ] || ! lane_halt || ENDING="$(lane_halt_reason)"
  case "$ENDING" in
    done) story_write "$1" landing; land_story "$1" ;;
    *) story_write "$1" "stopped $ENDING"
       [ "$ENDING" != "stop: run budget" ] || LANE_BUDGET=1 ;;
  esac
  CUR_ID=""; LAUNCH_ENV=""
}

# lanes_wait PID — bundle 2's D7 wait: a trapped signal interrupts `wait`,
# and the loop waits for the same pid again; sets LW_RC.
lanes_wait() {
  while :; do
    wait "$1"; LW_RC=$?
    kill -0 "$1" 2>/dev/null || break
  done
}
# lanes_end_sessions [K…] — TERM the live session of lanes K… (every lane
# when none is named): its process group, else the session's children and
# pid. After up to GRACE s, KILL whatever of it is still alive, group or
# not. The lane's unit watchdog (lanes/K/wpid) is ended first, so a dead
# lane's watchdog never outlives it to signal a reused pgid at its deadline.
# Used by the runner's exit path (lanes then see the stop and end) and by
# the sweep for a lane that died with its session live. Paths are quoted
# throughout (a project path may hold a space); lane names are numbers.
lanes_end_sessions() {
  if [ "$#" -eq 0 ]; then
    for _es_d in "$RUN_DIR"/lanes/*; do [ ! -d "$_es_d" ] || set -- "$@" "${_es_d##*/}"; done
  fi
  _es_pids=""
  for _es_k in "$@"; do
    _es_d="$RUN_DIR/lanes/$_es_k"
    if [ -f "$_es_d/wpid" ]; then
      _es_w="$(cat "$_es_d/wpid" 2>/dev/null)"
      [ -z "$_es_w" ] || kill "$_es_w" 2>/dev/null   # its TERM trap ends its sleep
      rm -f "$_es_d/wpid"
    fi
    [ ! -f "$_es_d/cpid" ] || _es_pids="$_es_pids $(cat "$_es_d/cpid" 2>/dev/null)"
  done
  for _es_p in $_es_pids; do
    kill -TERM -"$_es_p" 2>/dev/null || { pkill -TERM -P "$_es_p"; kill -TERM "$_es_p"; } 2>/dev/null
  done
  _es_g=0
  while [ -n "$_es_pids" ] && [ "$_es_g" -lt "${GRACE:-30}" ]; do
    _es_alive=0
    for _es_p in $_es_pids; do
      { kill -0 -"$_es_p" 2>/dev/null || pid_live "$_es_p"; } && _es_alive=1
    done
    [ "$_es_alive" = 1 ] || break
    sleep 1; _es_g=$((_es_g + 1))
  done
  for _es_p in $_es_pids; do
    kill -KILL -"$_es_p" 2>/dev/null || { pkill -KILL -P "$_es_p"; kill -KILL "$_es_p"; } 2>/dev/null
  done
  for _es_k in "$@"; do rm -f "$RUN_DIR/lanes/$_es_k/cpid"; done
}

# lanes_sweep — the parent's sweep once every lane has exited (D2): in a
# claimed chain, the first story with no ending is `stopped: lane crashed
# (<rc of its lane>)` (that lane's orphaned session ended first) and every
# later one `skipped <that id>`; every story of an unclaimed chain is
# `skipped: run stopped`. Lane rcs are LANE_RC_<k>, set by the wait loop.
lanes_sweep() {
  for _sw_c in $(cut -f1 "$CHAINS"); do
    if [ -d "$RUN_DIR/claims/$_sw_c" ]; then
      for _sw_id in $(chain_members "$_sw_c"); do
        is_ending "$(story_get "$_sw_id")" && continue
        _sw_k="$(cat "$RUN_DIR/claims/$_sw_c/lane" 2>/dev/null)"; _sw_rc=unknown
        case "$_sw_k" in
          ''|*[!0-9]*) ;;
          *) eval "_sw_rc=\${LANE_RC_$_sw_k:-unknown}"; lanes_end_sessions "$_sw_k" ;;
        esac
        story_write "$_sw_id" "stopped: lane crashed ($_sw_rc)"
        chain_skip_after "$_sw_id" "skipped $_sw_id"
        break
      done
    else
      for _sw_id in $(chain_members "$_sw_c"); do
        is_ending "$(story_get "$_sw_id")" || story_write "$_sw_id" "skipped: run stopped"
      done
    fi
  done
}
# lanes_wait_all — lanes_wait each of LANE_PIDS (lane k is the k-th), its rc
# into LANE_RC_<k>; then LANE_PIDS is empty.
lanes_wait_all() {
  _wa_k=1
  for _wa_p in $LANE_PIDS; do
    lanes_wait "$_wa_p"
    eval "[ -n \"\${LANE_RC_$_wa_k:-}\" ] || LANE_RC_$_wa_k=\$LW_RC"   # a re-wait (exit path) keeps the first rc
    _wa_k=$((_wa_k + 1))
  done
  LANE_PIDS=""
}

# lanes_ending — done when every story landed, else partial with counts.
lanes_ending() {
  _n=0; _s=0; _k=0; _all=1
  for _id in $(cut -f1 "$MF_ROWS" | awk '!seen[$0]++'); do
    case "$(story_get "$_id")" in
      landed*) _n=$((_n + 1)) ;;
      stopped*) _s=$((_s + 1)); _all=0 ;;
      skipped*) _k=$((_k + 1)); _all=0 ;;
      *) _all=0 ;;
    esac
  done
  if [ "$_all" = 1 ]; then echo done; else echo "partial: $_n landed, $_s stopped, $_k skipped"; fi
}
# lanes_report ENDING — a minimal report.md (T12 writes the full one).
lanes_report() {
  {
    printf '# Overnight run — %s\n\n' "$(basename "$RUN_DIR")"
    printf 'Ending: %s\n' "$1"
    printf 'Mode: %s\nTarget: %s\n' "$MF_MODE" "$MF_TARGET"
    printf 'Spent: $%s\n\n## Stories\n\n' "$(spent_all)"
    for _id in $(cut -f1 "$MF_ROWS" | awk '!seen[$0]++'); do
      printf -- '- %s: %s\n' "$_id" "$(story_get "$_id")"
    done
  } > "$RUN_DIR/report.md"
}
# lanes_finish ENDING — report, unlock, exit (0 only for done).
lanes_finish() {
  lanes_report "$1"
  unlock
  REPORTED=1
  [ "$1" = done ] && exit 0
  exit 1
}
# lanes_on_exit RC — the one EXIT trap of manifest mode: removes the
# preflight's scratch dir; once lanes run, an exit that never reached
# lanes_finish stops the lanes, ends their sessions, waits for them, and
# still writes the report and unlocks (a runner error, or SIGHUP). The stop
# file carries the reason, so each lane's story ends with it (not "by user"),
# and the sweep gives every other story its ending.
lanes_on_exit() {
  [ -z "${MF_TMP:-}" ] || rm -rf "$MF_TMP"
  [ "${LANES_LIVE:-0}" = 1 ] || return 0
  [ "$REPORTED" = 1 ] && return 0
  trap '' HUP INT TERM
  if [ "$HUP_REQ" = 1 ]; then _oe_why="stop: terminal closed (SIGHUP)"
  else _oe_why="stop: runner error (exit $1)"; fi
  printf '%s\n' "$_oe_why" > "$STOP_FILE"
  lanes_end_sessions
  lanes_wait_all
  lanes_sweep
  lanes_report "$_oe_why"
  unlock
  exit 1
}

# lanes_run — the run path, once the manifest preflight passed.
lanes_run() {
  acquire_run_lock
  mkdir -p "$RUN_DIR/claims" "$RUN_DIR/stories" "$RUN_DIR/lanes" \
    && cp "$MF" "$RUN_DIR/manifest.md" && cp "$MF_ROWS" "$RUN_DIR/rows.tsv" && cp "$CHAINS" "$RUN_DIR/chains" \
    || { rm -f "$LOCK"; say "cannot populate $RUN_DIR"; exit 2; }
  MF_ROWS="$RUN_DIR/rows.tsv"; CHAINS="$RUN_DIR/chains"
  rm -rf "$MF_TMP"; MF_TMP=""
  RECORD="$STATE_ROOT/.studio/runs/$MF_SLUG"
  mkdir -p "$RECORD" && touch "$RECORD/landed.tsv" || { rm -f "$LOCK"; say "cannot create $RECORD"; exit 2; }
  for _id in $(cut -f1 "$MF_ROWS" | awk '!seen[$0]++'); do story_write "$_id" queued; done
  LANES_LIVE=1; LANE_PIDS=""
  trap '[ -e "$STOP_FILE" ] || : > "$STOP_FILE"' INT TERM
  trap 'HUP_REQ=1; exit 129' HUP
  run_setup
  # The record is this machine's run state, like the lock: kept out of git.
  grep -qxF .studio/runs/ "$_excl" 2>/dev/null || printf '%s\n' .studio/runs/ >> "$_excl"
  RUNNER_PID=$$
  _nch="$(wc -l < "$CHAINS" | tr -d ' ')"
  _L="$_nch"
  [ "$MAX_LANES" -eq 0 ] || [ "$MAX_LANES" -ge "$_nch" ] || _L="$MAX_LANES"
  _k=1
  while [ "$_k" -le "$_L" ]; do
    ( lane_main "$_k" ) &
    LANE_PIDS="$LANE_PIDS $!"
    _k=$((_k + 1))
  done
  lanes_wait_all
  lanes_sweep
  # T11: the final step.
  lanes_finish "$(lanes_ending)"
}

# lanes_start [--dry-run] MANIFEST — manifest mode's start, after
# studio-overnight's preflight (which deferred its exit to here).
lanes_start() {
  _ls_dry=0; _ls_mf=""
  for _a in "$@"; do
    case "$_a" in --dry-run) _ls_dry=1 ;; *) _ls_mf="$_a" ;; esac
  done
  MF_TMP="$STATE_ROOT/.studio/tmp.$$"
  mkdir -p "$MF_TMP" || { say "cannot create $MF_TMP"; exit 2; }
  trap 'lanes_on_exit $?' EXIT
  MF_ROWS="$MF_TMP/rows.tsv"; CHAINS="$MF_TMP/chains"
  if mf_load "$_ls_mf"; then mf_check; fi
  [ "$FAILED" -eq 0 ] || exit 2
  build_chains
  RUN_DIR="$REPORTS/overnight-$MF_SLUG-$(date +%Y%m%d-%H%M%S)"
  if [ "$_ls_dry" -eq 1 ]; then
    lanes_dry_run
    exit 0
  fi
  lanes_run
}

# next_match KIND ID — the one tracked *.md file for story ID: KIND spec = a
# `## Stories` table whose first column equals ID; plan = a line exactly
# `Story: ID`. Prints the path (relative to START_DIR), nothing for none;
# two matches refuse with the stated message and return 1.
next_match() {
  _nm_hits="$(git -C "$START_DIR" ls-files '*.md' | while IFS= read -r _nm_f; do
    [ -f "$START_DIR/$_nm_f" ] || continue
    if [ "$1" = spec ]; then
      awk -F'|' -v id="$2" '
        /^## / { in_s = ($0 ~ /^## Stories[ \t]*$/); next }
        in_s && /^\|/ { c = $2; gsub(/^[ \t]+|[ \t]+$/, "", c); if (c == id) { f = 1 } }
        END { exit f ? 0 : 1 }' "$START_DIR/$_nm_f" && printf '%s\n' "$_nm_f"
    else
      grep -qxF "Story: $2" "$START_DIR/$_nm_f" && printf '%s\n' "$_nm_f"
    fi
  done)"
  case "$_nm_hits" in
    *'
'*) say "next: $2 matches two ${1}s: $(printf '%s\n' "$_nm_hits" | sed -n 1p), $(printf '%s\n' "$_nm_hits" | sed -n 2p)"; return 1 ;;
  esac
  printf '%s' "$_nm_hits"
  return 0
}

# lanes_next MANIFEST — classify each row (brainstorm | plan | planned) from
# files and ledger lines alone and print one line per row, then the one next
# command. Pure read: no preflight, no studio state written.
lanes_next() {
  MF_ROWS="$(mktemp "${TMPDIR:-/tmp}/lanes-next.XXXXXX")" || exit 2
  trap 'rm -f "$MF_ROWS"' EXIT
  mf_load "$1" || exit 2
  _ln_bs=""; _ln_pl=""
  while IFS="$(printf '\t')" read -r _ln_id _ln_b _ln_t _ln_spec _ln_plan _ln_d; do
    [ -n "$_ln_id" ] || continue
    if [ "$_ln_spec" = - ] || [ -z "$_ln_spec" ]; then
      _ln_spec="$(next_match spec "$_ln_id")" || exit 2
    fi
    if [ "$_ln_plan" = - ] || [ -z "$_ln_plan" ]; then
      _ln_plan="$(next_match plan "$_ln_id")" || exit 2
    fi
    _ln_class=brainstorm
    if [ -n "$_ln_spec" ]; then
      _ln_slug="$(basename "$_ln_spec" | sed -e 's/\.md$//' -e 's/^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}-//')"
      _ln_led="$START_DIR/.studio/ledger/$_ln_slug.md"
      if [ -f "$_ln_led" ] && grep -qF "spec approved $_ln_spec" "$_ln_led"; then
        _ln_class=plan
        if [ -n "$_ln_plan" ] && grep -qF "plan approved $_ln_plan" "$_ln_led" \
           && grep -qF "Decisions swept $_ln_id" "$_ln_led"; then
          _ln_class=planned
        fi
      fi
    fi
    printf '%s  %s  spec=%s  plan=%s\n' "$_ln_id" "$_ln_class" "${_ln_spec:--}" "${_ln_plan:--}"
    case "$_ln_class" in
      brainstorm) [ -n "$_ln_bs" ] || _ln_bs="$_ln_id" ;;
      plan) [ -n "$_ln_pl" ] || _ln_pl="$_ln_id" ;;
    esac
  done < "$MF_ROWS"
  if [ -n "$_ln_bs" ]; then echo "next: /game-dev:brainstorm $_ln_bs"
  elif [ -n "$_ln_pl" ]; then echo "next: /game-dev:plan $_ln_pl"
  else echo "next: /omega:autopilot"; fi
  rm -f "$MF_ROWS"
}
