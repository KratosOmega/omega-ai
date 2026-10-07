#!/bin/sh
# overnight-lanes.sh — studio-overnight's manifest mode (D18): the run
# manifest, dependency chains, the manifest preflight, the dry run, and the
# run itself: lane processes, each running its chains' stories one fresh
# session per unit (story_units), then each story's landing.
# Sourced by studio-overnight after its own helpers (say, sq, refuse, state,
# cfg*, deny_rules, model_for, label_for, with_launch_args, print_launch,
# run_unit, row, snapshot, story_units, acquire_run_lock, run_setup, unlock)
# are defined and its preflight has run; it sources overnight-ids.sh itself
# (story ids, #56: ids_check). Never run on its own. Reads studio state and
# the manifest; never writes either. It redefines stop_requested,
# spent_all, spent, run_populate, lock_recheck and the session_* slot calls
# (#39 D19) for manifest mode.
[ -n "${SELF_DIR:-}" ] || { echo "overnight-lanes.sh: sourced by studio-overnight" >&2; exit 2; }
. "$SELF_DIR/overnight-ids.sh"   # story ids (#56): ids_check, used by mf_check and lanes_next

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

# mf_slug — the manifest's `# Run:` slug, a trailing comment stripped.
mf_slug() {
  sed -n 's/^# Run:[ 	]*//p' "$MF" | head -n 1 | sed -e 's/[ 	]#.*$//' -e 's/[ 	]*$//'
}

# mf_load MANIFEST — parse the manifest: sets MF, MF_SLUG, MF_MODE,
# MF_TARGET, MF_DOCS, MF_GOAL and writes $MF_ROWS (set by the caller), one
# TSV row per story: id branch ticket spec plan deps (deps comma-joined, no
# spaces; empty for '-'). Returns 1 (after a refusal) when there is no file.
mf_load() {
  MF="$1"
  case "$MF" in /*) ;; *) MF="$START_DIR/$MF" ;; esac
  [ -f "$MF" ] || { refuse "no manifest at $1"; return 1; }
  MF_SLUG="$(mf_slug)"
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

# mf_rows_clash ROWS HOW — a story id or branch of MF_ROWS that ROWS uses too.
# The NR == FNR pass reads the other run's rows first, then flags this run's.
mf_rows_clash() {
  awk -F'\t' -v how="$2" 'NR == FNR { id[$1] = 1; br[$2] = 1; next }
    ($1 in id) { printf "story %s is used by %s id\n", $1, how }
    ($2 in br) { printf "branch %s is used by %s branch\n", $2, how }' "$1" "$MF_ROWS" 2>/dev/null
}
# mf_conflicts LIVE_ONLY — this manifest (MF_SLUG, MF_ROWS) against the
# other runs (#39 AC8, D39): live runs' rows.tsv and Target, and with
# LIVE_ONLY=0 also stopped records (landed.tsv, no done; rows from the
# newest report dir) and a done record of this slug. One line per conflict.
mf_conflicts() {
  # cut, not IFS=<tab> read: a tab is IFS whitespace, so an empty column (a
  # lock without start=) would collapse and shift the lock path out of field 7.
  runs_live "$STATE_ROOT" | while IFS= read -r _mc_e; do
    _mc_s="$(printf '%s\n' "$_mc_e" | cut -f2)"; _mc_k="$(printf '%s\n' "$_mc_e" | cut -f3)"
    _mc_p="$(printf '%s\n' "$_mc_e" | cut -f4)"; _mc_d="$(printf '%s\n' "$_mc_e" | cut -f5)"
    _mc_l="$(printf '%s\n' "$_mc_e" | cut -f7)"
    [ "$1" = 0 ] || [ "$_mc_l" != "$LOCK" ] || continue   # own lock: only once it is held (re-check)
    [ "$_mc_k" = manifest ] || continue
    _mc_how="live run $_mc_s ($_mc_d, pid $_mc_p) — stop it ($(sq "$SELF_ABS") stop --run $_mc_s) or pick another"
    [ "$_mc_s" != "$MF_SLUG" ] || printf 'slug %s is used by %s slug\n' "$MF_SLUG" "$_mc_how"
    mf_rows_clash "$_mc_d/rows.tsv" "$_mc_how"
    _mc_t="$(runs_mf_header "$_mc_d/manifest.md" Target)"
    if [ -n "$_mc_t" ] && cut -f2 "$MF_ROWS" | grep -qxF -- "$_mc_t"; then
      printf 'branch %s is the Target of %s branch\n' "$_mc_t" "$_mc_how"
    fi
  done
  [ "$1" = 1 ] && return 0
  for _mc_r in "$STATE_ROOT"/.studio/runs/*/landed.tsv; do
    [ -f "$_mc_r" ] || continue
    _mc_s="${_mc_r%/landed.tsv}"; _mc_s="${_mc_s##*/}"
    if [ "$_mc_s" = "$MF_SLUG" ]; then
      if runs_record_done "$STATE_ROOT" "$_mc_s"; then
        printf 'run %s is done: archive its record first: mv %s %s.<utc ts>\n' \
          "$_mc_s" "$(sq "$STATE_ROOT/.studio/runs/$_mc_s")" "$(sq "$STATE_ROOT/.studio/runs/$_mc_s")"
      fi
      continue                                    # own open record: a resume
    fi
    runs_record_open "$STATE_ROOT" "$_mc_s" || continue
    runs_live "$STATE_ROOT" | runs_match "$_mc_s" | grep -q . && continue   # counted above
    _mc_rows="$(runs_rows "$STATE_ROOT" "$_mc_s")" || continue
    # The way out (AC8): resume from its newest report's manifest path (the
    # report's own fallback when unrecorded), or abandon it by archiving the
    # record as a done one is archived.
    _mc_rd="${_mc_rows%/rows.tsv}"; _mc_rec="$STATE_ROOT/.studio/runs/$_mc_s"
    _mc_mf="$(head -n 1 "$_mc_rd/manifest.path" 2>/dev/null)"; [ -n "$_mc_mf" ] || _mc_mf="docs/runs/$_mc_s.md"
    mf_rows_clash "$_mc_rows" "stopped run $_mc_s (record $_mc_rec, report $_mc_rd) — resume it ($(sq "$SELF_ABS") start $_mc_mf) or abandon it (mv $(sq "$_mc_rec") $(sq "$_mc_rec").<utc ts>) or pick another"
  done
}
# mf_overlap_warn — warn (D38, AC9) for each other live run whose unfinished
# tasks' Files: this run's unfinished tasks also name. At most 20 paths per
# run, then `and N more`. Only warns: any failure prints nothing.
mf_overlap_warn() {
  _ow_mine="$MF_TMP/ow-mine"; _ow_peers="$MF_TMP/ow-peers"; : > "$_ow_mine"
  while IFS="$(printf '\t')" read -r _ow_id _ow_b _ow_t _ow_sp _ow_plan _; do
    [ -n "$_ow_id" ] && [ -n "$_ow_plan" ] && [ "$_ow_plan" != - ] || continue
    _ow_k="$(sed -n 's/^task:[[:blank:]]*//p' "$STATE_ROOT/.studio/stories/$_ow_id.md" 2>/dev/null | head -n 1)"
    _ow_k="${_ow_k%%/*}"; case "$_ow_k" in ''|*[!0-9]*) _ow_k=0 ;; esac
    git -C "$START_DIR" show "$MF_DOCS:$_ow_plan" 2>/dev/null | runs_plan_files "$_ow_k" >> "$_ow_mine"
  done < "$MF_ROWS"
  LC_ALL=C sort -u "$_ow_mine" > "$_ow_mine.s" 2>/dev/null || return 0
  [ -s "$_ow_mine.s" ] || return 0
  sh "$SELF_DIR/studio-peers" --files 2>/dev/null | grep -v '^[^ ]*: unreadable$' | awk 'NF' > "$_ow_peers" || return 0
  for _ow_s in $(cut -d' ' -f1 "$_ow_peers" | LC_ALL=C sort -u); do
    awk -v s="$_ow_s" 'index($0, s " ") == 1 { print substr($0, length(s) + 2) }' "$_ow_peers" | LC_ALL=C sort -u > "$_ow_peers.s"
    LC_ALL=C comm -12 "$_ow_mine.s" "$_ow_peers.s" > "$_ow_peers.c"
    _ow_n="$(wc -l < "$_ow_peers.c" | tr -d ' ')"
    [ "$_ow_n" -gt 0 ] || continue
    say "warning — live run $_ow_s is changing files this run's unfinished tasks change too:"
    head -n 20 "$_ow_peers.c" | sed 's/^/  /' >&2
    [ "$_ow_n" -le 20 ] || printf '  and %s more\n' $((_ow_n - 20)) >&2
  done
  return 0
}

# mf_check — the manifest preflight: one refuse per failure (spec 806-815).
mf_check() {
  git_version_ok || refuse "git 2.38 or newer is required (git merge-tree --write-tree); found $(git --version 2>/dev/null)"
  printf '%s\n' "$MF_SLUG" | grep -Eq '^[A-Za-z0-9._-]+$' \
    || refuse "manifest: '# Run: <slug>' must name a slug of [A-Za-z0-9._-], got '$MF_SLUG'"
  case "$MF_SLUG" in
    off) refuse "slug off is reserved (/omega:autopilot off) — pick another" ;;
    *[!0-9]*) ;;
    *) refuse "slug $MF_SLUG is all digits (it reads as a story id) — pick another" ;;
  esac
  # A branch whose / -> - form starts like a run's own branches would collide with them (#39).
  # A Branch that is the default branch or the Target: its story worktree
  # would be the main checkout, and a sync or landing would push to it.
  while IFS="$(printf '\t')" read -r _bf_id _bf_b _; do
    if [ -n "$_bf_b" ] && { [ "$_bf_b" = "$DEFAULT_BRANCH" ] || [ "$_bf_b" = "$MF_TARGET" ]; }; then
      refuse "manifest: $_bf_id: branch $_bf_b is the default branch or the run's Target — pick another"
    fi
    case "$(printf '%s' "$_bf_b" | tr / -)" in
      run-*|integration-*|progress-*) refuse "manifest: $_bf_id: branch $_bf_b collides with a run, integration or progress branch (its / -> - form starts run-, integration- or progress-) — pick another" ;;
    esac
  done < "$MF_ROWS"
  while IFS= read -r _l; do [ -z "$_l" ] || refuse "$_l"; done <<EOF_MC
$(mf_conflicts 0)
EOF_MC
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

  # Origin: one fetch, then the docs revision and the target branch. The
  # setup preflight reuses it (SP_FETCHED): no second fetch of the Target.
  if git_retry -C "$START_DIR" fetch -q origin; then SP_FETCHED="$MF_TARGET"; else refuse "git fetch origin failed"; fi
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
  awk -F'\t' '!($1 in seen) { seen[$1] = 1; print $1 "\t" $5 "\t" $3 }' "$MF_ROWS" > "$MF_TMP/stories"
  while IFS='	' read -r _id _plan _tkt; do
    printf '%s\n' "$_id" | grep -Eq '^[A-Za-z0-9._-]+$' || continue
    # #56 R3: the backstop — the id is checked against the default branch fetched above.
    [ -z "$DEFAULT_BRANCH" ] \
      || ids_check "$_id" "$_tkt" "$MF_SLUG" "${_plan:--}" "$DEFAULT_BRANCH" "$MF_ROWS" refuse < /dev/null || :
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
        # The shipped line is ledgered in the story's own checkout (its
        # worktree), so a resumed shipped story is read from there too.
        idle) _wt="$(story_state "$_id" worktree 2>/dev/null)"
              { printf '%s\n' "$_show"
                [ -z "$_wt" ] || [ ! -d "$_wt" ] || ( cd "$_wt" && STUDIO_STORY="$_id" sh "$STATE_BIN" show 2>/dev/null )
              } | grep -q '^- [0-9-]* shipped ' \
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
      /^## Backlog/ { close_task(); exit }
      /^## / { close_task(); next }
      /^Spec:/ { spec = 1 }
      END { close_task() }
    ' "$MF_TMP/plan" | while IFS= read -r _t; do
      printf '%s\n' "$_id: plan task has no Spec: line ($_t)"
    done > "$MF_TMP/spec-refusals"
    while IFS= read -r _l; do refuse "$_l"; done < "$MF_TMP/spec-refusals"
    # D40: each Context: path (a comma list in the header) is in the Docs revision.
    set -f   # a `*` in a Context path is a name, not a glob
    for _cx in $(sed -n '/^## /q; s/^Context:[[:space:]]*//p' "$MF_TMP/plan" | head -n 1 | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'); do
      git -C "$START_DIR" cat-file -e "$MF_DOCS:$_cx" 2>/dev/null || refuse "$_id: Context file $_cx is not in Docs: $MF_DOCS"
    done
    set +f
  done < "$MF_TMP/stories"
  mf_ready
  mf_overlap_warn
}

# rd_truth — stdin's lines after its last `adopt reset` line (all of them when
# there is none): the truth region every adopt reader uses (#35 D2).
rd_truth() { awk '/^- [0-9-]+ adopt reset /{ n = NR } { l[NR] = $0 } END { for (i = n + 1; i <= NR; i++) print l[i] }'; }

# rd_adopted ID — the first ledger with an `adopted` line for ID in its truth
# region: START_DIR's, else any worktree's (#50 case b: ledgered from the
# wrong checkout). Nothing when none.
rd_adopted() {
  { printf '%s\n' "$START_DIR"; git -C "$START_DIR" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p'; } \
    | while IFS= read -r _ra_w; do
        _ra_f="$_ra_w/.studio/ledger/$1.md"
        if [ -f "$_ra_f" ] && rd_truth < "$_ra_f" | grep -q '^- [0-9-]* adopted .* -> '; then printf '%s\n' "$_ra_f"; break; fi
      done
}

# mf_ready — #50 D5: the start checkout is ready for this run. One refuse per
# problem: START_DIR has no .studio/run, or one naming no manifest of this run
# (a missing file, or another `# Run:` slug); an adopted story whose branch exists,
# locally or on origin, but whose story ledger (its worktree's, else the
# branch's) has no `adopt-base` line: never seeded, so its first unit would
# start at task 1. A not-started adopted story (no branch yet) is skipped:
# execute §0 records its adopt-base. Reads files and git only (RUN_DIR is not
# set yet, so story_ledger_text cannot be used).
mf_ready() {
  _rd_p="$(head -n 1 "$START_DIR/.studio/run" 2>/dev/null)"
  if [ -z "$_rd_p" ]; then
    refuse "start checkout $START_DIR has no .studio/run — write it there: printf '%s\\n' ${MF#"$START_DIR"/} > .studio/run"
  else
    # The pointer (relative to START_DIR, or absolute) names an existing
    # manifest of this run (its `# Run:` slug), else studio-adopt's lookup
    # misses this run's worktree (#50 final review M2).
    case "$_rd_p" in /*) _rd_f="$_rd_p" ;; *) _rd_f="$START_DIR/$_rd_p" ;; esac
    if [ ! -f "$_rd_f" ] || [ "$(runs_mf_slug "$_rd_f")" != "$MF_SLUG" ]; then
      refuse "start checkout $START_DIR: .studio/run names $_rd_p, not this run's manifest — write it there: printf '%s\\n' ${MF#"$START_DIR"/} > .studio/run"
    fi
  fi
  awk -F'\t' '!($1 in s) { s[$1] = 1; print $1 "\t" $2 }' "$MF_ROWS" > "$MF_TMP/ready"
  while IFS='	' read -r _rd_id _rd_b; do
    printf '%s\n' "$_rd_id" | grep -Eq '^[A-Za-z0-9._-]+$' || continue
    case "$_rd_b" in ''|-) continue ;; esac
    _rd_l="$(rd_adopted "$_rd_id")"; [ -n "$_rd_l" ] || continue
    git -C "$START_DIR" rev-parse -q --verify "refs/heads/$_rd_b^{commit}" >/dev/null 2>&1 \
      || git -C "$START_DIR" rev-parse -q --verify "refs/remotes/origin/$_rd_b^{commit}" >/dev/null 2>&1 \
      || continue
    _rd_w="$(story_state "$_rd_id" worktree 2>/dev/null)" || _rd_w=""
    [ -n "$_rd_w" ] && [ -d "$_rd_w" ] || _rd_w=""   # never hint at a removed worktree (as mf_check)
    { if [ -n "$_rd_w" ] && [ -f "$_rd_w/.studio/ledger/$_rd_id.md" ]; then cat "$_rd_w/.studio/ledger/$_rd_id.md"
      else git -C "$START_DIR" show "refs/heads/$_rd_b:.studio/ledger/$_rd_id.md" \
        || git -C "$START_DIR" show "refs/remotes/origin/$_rd_b:.studio/ledger/$_rd_id.md"
      fi; } 2>/dev/null | rd_truth | grep -q '^- [0-9-]* adopt-base ' && continue
    refuse "$_rd_id: adopted ($_rd_l) but not seeded on $_rd_b — run studio-adopt seed $_rd_id in ${_rd_w:-the $_rd_b worktree}, then STUDIO_STORY=$_rd_id studio-state check --rebuild there"
  done < "$MF_TMP/ready"
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
  _sfl="$(story_state "$1" show 2>/dev/null)"
  SIG_FRD="$(printf '%s\n' "$_sfl" | grep -c '^- [0-9-]* final review done$')"
  # check lines count in D2's truth region: after the last `adopt reset` line.
  _sfl="$(printf '%s\n' "$_sfl" | awk '/^- [0-9-]+ adopt reset /{ n = NR } { l[NR] = $0 } END { for (i = n + 1; i <= NR; i++) print l[i] }')"
  SIG_CHK="$(printf '%s\n' "$_sfl" | grep -c '^- [0-9-]* check done')"
  SIG_CHKREQ="$(printf '%s\n' "$_sfl" | grep -c '^- [0-9-]* check requested$')"
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
  printf '%s\n' "$2" > "$RUN_DIR/stories/.$1.tmp" && mv -f "$RUN_DIR/stories/.$1.tmp" "$RUN_DIR/stories/$1" \
    && state_event "$1" "$2"
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

# ---- Landing (spec 555-585, AC7, AC8): no Claude session for a clean merge ----

# land_lock_take — one attempt at RUN_DIR/land.lock (mkdir; `pid` = LANE_PID)
# under the reclaim mutex land.lock.mutex, studio-gate's rule (T4): the
# mutex is a symlink naming its taker's pid, made in one atomic step and held
# for milliseconds; a mutex naming a dead pid is removed by whoever finds it.
# Under the mutex, a lock whose pid is dead (a zombie lane counts) or missing
# (a taker that died before writing it) is cleared, so a SIGKILLed holder
# never wedges the run. Returns 0 when this lane holds the lock (LAND_HELD=1).
land_lock_take() {
  _ll="$RUN_DIR/land.lock"
  if ! ln -s "$LANE_PID" "$_ll.mutex" 2>/dev/null; then
    _llm="$(readlink "$_ll.mutex" 2>/dev/null)"
    if [ -n "$_llm" ] && ! pid_live "$_llm" && [ "$(readlink "$_ll.mutex" 2>/dev/null)" = "$_llm" ]; then
      rm -f "$_ll.mutex"
    fi
    return 1
  fi
  if [ -d "$_ll" ]; then
    _llh="$(cat "$_ll/pid" 2>/dev/null)"
    { [ -n "$_llh" ] && pid_live "$_llh"; } || rm -rf "$_ll"
  fi
  _llr=1
  if mkdir "$_ll" 2>/dev/null; then
    printf '%s\n' "$LANE_PID" > "$_ll/pid"; LAND_HELD=1; _llr=0
  fi
  rm -f "$_ll.mutex"
  return "$_llr"
}
# land_lock_release — drop the land lock when this lane holds it: renamed
# aside first, so no taker ever sees a half-deleted lock.
land_lock_release() {
  [ "${LAND_HELD:-0}" = 1 ] || return 0
  LAND_HELD=0
  _ll="$RUN_DIR/land.lock"
  [ "$(cat "$_ll/pid" 2>/dev/null)" = "$LANE_PID" ] || return 0
  mv "$_ll" "$_ll.gone.$LANE_PID" 2>/dev/null && rm -rf "$_ll.gone.$LANE_PID"
}

# pr_view REF — `gh pr view REF --json state,mergeCommit,isDraft,number`
# from START_DIR (REF a number or a head branch), fields pulled out by sed:
# PR_STATE, PR_OID (empty before a merge), PR_DRAFT (1|0), PR_NUM. Returns
# 1 when gh fails or names no state (no such PR).
pr_view() {
  _pv="$(cd "$START_DIR" && gh pr view "$1" --json state,mergeCommit,isDraft,number 2>/dev/null)" || return 1
  _pv="$(printf '%s' "$_pv" | tr -d '\n')"
  PR_STATE="$(printf '%s\n' "$_pv" | sed -n 's/.*"state"[[:space:]]*:[[:space:]]*"\([A-Z_]*\)".*/\1/p')"
  PR_OID="$(printf '%s\n' "$_pv" | sed -n 's/.*"mergeCommit"[[:space:]]*:[[:space:]]*{[^}]*"oid"[[:space:]]*:[[:space:]]*"\([0-9a-f]*\)".*/\1/p')"
  PR_NUM="$(printf '%s\n' "$_pv" | sed -n 's/.*"number"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p')"
  PR_DRAFT=0
  printf '%s\n' "$_pv" | grep -q '"isDraft"[[:space:]]*:[[:space:]]*true' && PR_DRAFT=1
  [ -n "$PR_STATE" ]
}

# land_confirm ID [BRANCH] — step 0, "already landed?", with LAND_SHA set.
# BRANCH defaults to ID's manifest row. Direct:
# the PR of BRANCH is MERGED; LAND_SHA is its merge commit. Integration
# (after the caller's fetch): origin/<Branch> exists, is an ancestor of
# origin/<Target>, and its own ledger has a `shipped` line (so a branch with
# no commits of its own never counts); LAND_SHA is the oldest merge on
# `--ancestry-path origin/<Branch>..origin/<Target>`, else the branch head
# (D4: a fast-forward). Reads only; returns 1 when not confirmed.
land_confirm() {
  _lc_b="${2:-$(row_field "$1" branch)}"
  if [ "$MF_MODE" = direct ]; then
    pr_view "$_lc_b" && [ "$PR_STATE" = MERGED ] && [ -n "$PR_OID" ] || return 1
    LAND_SHA="$PR_OID"; return 0
  fi
  _lc_rb="refs/remotes/origin/$_lc_b"; _lc_rt="refs/remotes/origin/$MF_TARGET"
  git -C "$START_DIR" rev-parse -q --verify "$_lc_rb^{commit}" >/dev/null || return 1
  git -C "$START_DIR" merge-base --is-ancestor "$_lc_rb" "$_lc_rt" 2>/dev/null || return 1
  git -C "$START_DIR" show "$_lc_rb:.studio/ledger/$1.md" 2>/dev/null | grep -q '^- [0-9-]* shipped ' || return 1
  LAND_SHA="$(git -C "$START_DIR" log --merges --ancestry-path --format=%H "$_lc_rb..$_lc_rt" | tail -n 1)"
  [ -n "$LAND_SHA" ] || LAND_SHA="$(git -C "$START_DIR" rev-parse "$_lc_rb")"
}

# land_once ID — one landing attempt for shipped story ID; touches no
# checkout. Returns 0 landed (LAND_SHA set) · 3 needs repair (LAND_REPAIR =
# conflict or red:<abs log>) · 4 failed (LAND_WHY set). Integration: fetch;
# step 0 (land_confirm); step 1 `merge-tree --write-tree` of origin/<Target>
# and origin/<Branch> (exit 1 = conflict); step 2 a `commit-tree` --no-ff
# merge pushed to <Target>; a rejected push fetches and goes back to step 0
# once. Test hook: STUDIO_OVERNIGHT_LAND_HOOK is evaluated right after a
# successful push (D20). Direct: land_once_direct. BRANCH defaults to ID's
# manifest row; a caller landing a branch with no row (Task 11's direct
# progress landing) names it.
land_once() {
  LAND_SHA=""; LAND_REPAIR=""; LAND_WHY=""
  _lo_b="${2:-$(row_field "$1" branch)}"
  if [ "$MF_MODE" = direct ]; then land_once_direct "$1" "$_lo_b"; return $?; fi
  _lo_rb="refs/remotes/origin/$_lo_b"; _lo_rt="refs/remotes/origin/$MF_TARGET"
  _lo_rej=0
  while :; do
    git_retry -C "$START_DIR" fetch -q origin || { LAND_WHY="cannot fetch origin"; return 4; }
    land_confirm "$1" "$_lo_b" && return 0
    git -C "$START_DIR" rev-parse -q --verify "$_lo_rb^{commit}" >/dev/null || { LAND_WHY="no origin/$_lo_b"; return 4; }
    _lo_tree="$(git -C "$START_DIR" merge-tree --write-tree "$_lo_rt" "$_lo_rb" 2>/dev/null)"; _lo_st=$?
    case "$_lo_st" in
      0) ;;
      1) LAND_REPAIR=conflict; return 3 ;;
      *) LAND_WHY="merge-tree failed ($_lo_st)"; return 4 ;;
    esac
    _lo_tree="$(printf '%s\n' "$_lo_tree" | head -n 1)"
    _lo_sha="$(git_retry -C "$START_DIR" commit-tree "$_lo_tree" -p "$_lo_rt" -p "$_lo_rb" -m "Merge $_lo_b ($1) into $MF_TARGET")" \
      || { LAND_WHY="commit-tree failed"; return 4; }
    if git_retry -C "$START_DIR" push -q origin "$_lo_sha:refs/heads/$MF_TARGET"; then
      [ -z "${STUDIO_OVERNIGHT_LAND_HOOK:-}" ] || eval "$STUDIO_OVERNIGHT_LAND_HOOK"
      LAND_SHA="$_lo_sha"; return 0
    fi
    _lo_rej=$((_lo_rej + 1))
    [ "$_lo_rej" -lt 2 ] || { LAND_WHY="push to $MF_TARGET rejected twice"; return 4; }
  done
}
# merge_wait ID PID — wait for the merge command PID (studio-gate leading its
# own process group) under session_minutes (STUDIO_OVERNIGHT_SESSION_SECONDS
# overrides), run_unit's watchdog rule: at the deadline TERM the group (the
# gate forwards it to the merge program's group, waits for it and releases
# the gate lock), KILL after GRACE: first the group of each child of the
# gate (the merge program's own, which a GRACE below studio-gate's 10 s
# KILL would orphan), then the gate's. Who ended it is decided once by an atomic
# mkdir of LDIR/ID-land.ended. Under a lane, LDIR/cpid and LDIR/wpid name it
# for lanes_end_sessions. Returns 1 when the watchdog ended it (timed out).
merge_wait() {
  _mw_secs="${STUDIO_OVERNIGHT_SESSION_SECONDS:-$((SESSION_MINUTES * 60))}"
  _mw_claim="${LDIR:-$RUN_DIR}/$1-land.ended"; rmdir "$_mw_claim" 2>/dev/null
  [ -z "${LDIR:-}" ] || printf '%s\n' "$2" > "$LDIR/cpid"
  ( _sp=; trap 'kill $_sp 2>/dev/null; exit 0' TERM
    sleep "$_mw_secs" & _sp=$!; wait "$_sp"
    mkdir "$_mw_claim" 2>/dev/null || [ ! -d "$_mw_claim" ] || exit 0
    kill -TERM -"$2" 2>/dev/null || { pkill -TERM -P "$2"; kill -TERM "$2"; }
    sleep "${GRACE:-30}" & _sp=$!; wait "$_sp"
    for _k in $(pgrep -P "$2"); do kill -KILL -"$_k" 2>/dev/null; done
    kill -KILL -"$2" 2>/dev/null || { pkill -KILL -P "$2"; kill -KILL "$2"; }
  ) > /dev/null 2>&1 &
  _mw_w=$!
  [ -z "${LDIR:-}" ] || printf '%s\n' "$_mw_w" > "$LDIR/wpid"
  while :; do
    wait "$2"
    kill -0 "$2" 2>/dev/null || break
  done
  [ -z "${LDIR:-}" ] || rm -f "$LDIR/cpid"
  _mw_to=0
  mkdir "$_mw_claim" 2>/dev/null || _mw_to=1
  kill "$_mw_w" 2>/dev/null; wait "$_mw_w" 2>/dev/null
  [ -z "${LDIR:-}" ] || rm -f "$LDIR/wpid"
  rmdir "$_mw_claim" 2>/dev/null
  [ "$_mw_to" = 0 ]
}
# land_once_direct ID BRANCH — direct mode's land_once: step 0 the PR is
# MERGED; step 1 `merge-tree` against origin/<default> (exit 1 = conflict);
# step 2 `gh pr ready` for a draft, then MERGE_COMMAND with <pr> = the PR
# number, its program from START_DIR (never the story's copy), run through
# `studio-gate merge` from LAND_DIR when set (the direct progress landing's
# worktree), else the story worktree (else START_DIR), stdin
# /dev/null, output to LDIR/<id>-land.log (RUN_DIR outside a lane), under
# session_minutes (merge_wait: a timeout ends it, then step 3 still runs:
# a merge that landed before it hung is landed, anything else returns 4,
# `merge command timed out`, no repair); step 3,
# whatever its exit code, fetch (a failed fetch returns 4), then the PR is
# MERGED and its merge commit is in origin/<default>: landed. A PR that is
# MERGED never returns 3 (a repair on a landed story): its commit missing
# after a second fetch and view returns 4, as does a failed gh read; a PR
# not MERGED is red:<log>. MERGE_COMMAND is split on blanks (no quoting
# inside it).
land_once_direct() {
  pr_view "$2" || { LAND_WHY="no PR for $2"; return 4; }
  if [ "$PR_STATE" = MERGED ]; then
    [ -n "$PR_OID" ] || { LAND_WHY="PR #$PR_NUM is MERGED with no merge commit"; return 4; }
    LAND_SHA="$PR_OID"; return 0
  fi
  [ "$PR_STATE" = OPEN ] || { LAND_WHY="PR #$PR_NUM is $PR_STATE"; return 4; }
  _ld_n="$PR_NUM"; _ld_rd="refs/remotes/origin/$DEFAULT_BRANCH"
  git_retry -C "$START_DIR" fetch -q origin || { LAND_WHY="cannot fetch origin"; return 4; }
  git -C "$START_DIR" merge-tree --write-tree "$_ld_rd" "refs/remotes/origin/$2" >/dev/null 2>&1; _ld_st=$?
  case "$_ld_st" in
    0) ;;
    1) LAND_REPAIR=conflict; return 3 ;;
    *) LAND_WHY="merge-tree failed ($_ld_st)"; return 4 ;;
  esac
  if [ "$PR_DRAFT" = 1 ]; then
    ( cd "$START_DIR" && gh pr ready "$_ld_n" ) >/dev/null 2>&1 || { LAND_WHY="gh pr ready $_ld_n failed"; return 4; }
  fi
  _ld_log="${LDIR:-$RUN_DIR}/$1-land.log"
  _ld_cmd="$(printf '%s\n' "$MERGE_COMMAND" | sed "s/<pr>/$_ld_n/g")"
  _ld_w="${_ld_cmd%% *}"; _ld_a=""; [ "$_ld_cmd" = "$_ld_w" ] || _ld_a="${_ld_cmd#* }"
  _ld_dir="${LAND_DIR:-$(feature_dir)}"
  set -m 2>/dev/null || true   # own process group, as start_session's session
  ( cd "$_ld_dir" || exit 2
    set -f; set -- $_ld_a; set +f
    exec sh "$SELF_DIR/studio-gate" merge -- "$START_DIR/$_ld_w" "$@" ) > "$_ld_log" 2>&1 < /dev/null &
  _ld_pid=$!
  set +m 2>/dev/null || true
  _ld_to=""; merge_wait "$1" "$_ld_pid" || _ld_to="merge command timed out"
  _ld_try=0
  while :; do
    git_retry -C "$START_DIR" fetch -q origin || { LAND_WHY="${_ld_to:-cannot fetch origin}"; return 4; }
    pr_view "$_ld_n" || { LAND_WHY="${_ld_to:-cannot read PR #$_ld_n after the merge command}"; return 4; }
    if [ "$PR_STATE" = MERGED ] && [ -n "$PR_OID" ] \
       && git -C "$START_DIR" merge-base --is-ancestor "$PR_OID" "$_ld_rd" 2>/dev/null; then
      LAND_SHA="$PR_OID"; return 0
    fi
    [ -z "$_ld_to" ] || [ "$PR_STATE" = MERGED ] || { LAND_WHY="$_ld_to"; return 4; }
    [ "$PR_STATE" = MERGED ] || { LAND_REPAIR="red:$_ld_log"; return 3; }
    _ld_try=$((_ld_try + 1))
    [ "$_ld_try" -lt 2 ] || { LAND_WHY="PR #$_ld_n is MERGED but its merge commit is not in origin/$DEFAULT_BRANCH"; return 4; }
  done
}

# land_repair ID — the one repair unit of a landing: stories/ID = repair,
# then `/game-dev:execute --land` (label repair, model_repair; D23) with
# STUDIO_REPAIR=$LAND_REPAIR added to the story's env words. Returns 0 when
# the story ledger (feature checkout) gained a `Repair:` line — retry; else
# writes the ending (`stopped stop: <reason>` for a new Stop: line, `stopped
# repair made no progress [(orphaned: …)]` for neither — `stopped repair timed out (…)` when
# the session cap ended it — the halt reason when the lane must stop) and
# returns 1. Called after studio-gate has exited, so the repair's
# own gate takes the gate lock itself (D17).
land_repair() {
  if lane_halt; then story_write "$1" "stopped $(lane_halt_reason)"; return 1; fi
  story_write "$1" repair
  snapshot "$UNIT_DIR/stops.before"
  _lr_b="$(ledger_of "$FEATURE_DIR" | grep -c '^- [0-9-]* Repair: ')"
  _lr_p="$PROMPT"; _lr_e="$LAUNCH_ENV"
  PROMPT="/game-dev:execute --land"; LAUNCH_ENV="$LAUNCH_ENV STUDIO_REPAIR=$(sq "$LAND_REPAIR")"
  n=$((${n:-0} + 1)); run_unit "$n" repair
  PROMPT="$_lr_p"; LAUNCH_ENV="$_lr_e"
  if [ "$UNIT_HALTED" != 0 ]; then story_write "$1" "stopped $(lane_halt_reason)"; return 1; fi   # D22
  snapshot "$UNIT_DIR/stops.after"
  _lr_new="$(new_stop "$UNIT_DIR/stops.before" "$UNIT_DIR/stops.after")"
  _lr_a="$(ledger_of "$FEATURE_DIR" | grep -c '^- [0-9-]* Repair: ')"
  if [ -n "$_lr_new" ]; then
    row "$n" repair stop; story_write "$1" "stopped stop: ${_lr_new#*Stop: }"; return 1
  fi
  if [ "$_lr_a" -gt "$_lr_b" ]; then
    row "$n" repair progress
    if lane_halt; then story_write "$1" "stopped $(lane_halt_reason)"; return 1; fi
    story_write "$1" landing; return 0
  fi
  _lr_o="$(unit_outcome)"
  if [ "$_lr_o" != "timed out" ]; then row "$n" repair "$_lr_o"; story_write "$1" "stopped repair made no progress$(orphan_note "$_lr_o")"
  else row "$n" repair "timed out"; story_write "$1" "stopped repair timed out (session_minutes $SESSION_MINUTES)"; fi
  return 1
}

# gate_log_of DIR — the log of DIR's red gate (D14): the path the feature
# ledger's newest `Stop:` line ends with (` — log <path>`; a relative path
# is prefixed with DIR/), else the newest studio-test log under
# DIR/.studio/reports (the adapter's test-<stamp>.log); `-` when there is none.
gate_log_of() {
  _gl="$(ledger_of "$1" | grep '^- [0-9-]* Stop: ' | tail -n 1 | sed -n 's/.* — log \(.*\)$/\1/p')"
  case "$_gl" in '') ;; /*) printf '%s\n' "$_gl"; return ;; *) printf '%s\n' "$1/$_gl"; return ;; esac
  _gl="$(ls -t "$1"/.studio/reports/test-*.log 2>/dev/null | head -n 1)"
  printf '%s\n' "${_gl:--}"
}

# gate_repair ID — the gate-repair unit of a story whose finish gate was red
# (`stop: gate red — …`; the finish runs the gate once, and a fix plus a
# full re-run do not fit one session): stories/ID = gate-repair, then
# `/game-dev:execute --gate-repair` (label gate-repair, model_repair) with
# STUDIO_REPAIR=gate:<gate_log_of the feature checkout> added to the story's
# env words. The unit fixes and re-runs only the failing tests. Returns 0
# when the feature ledger gained a `Repair:` line: the caller re-runs
# story_units, whose fresh finish re-runs the full gate. Else returns 1 with
# ENDING set: the halt reason; `stop: run budget` (story_units' rule, before
# any launch); `stop: <reason>` for a new Stop: line (the unit's own `gate
# repair red` is a hard stop); `gate repair made no progress [(orphaned: …)]`; or `gate
# repair timed out (session_minutes N)` — the halt reason instead when the
# lane must stop.
gate_repair() {
  if lane_halt; then ENDING="$(lane_halt_reason)"; return 1; fi
  if run_budget_out; then ENDING="stop: run budget"; return 1; fi
  story_write "$1" gate-repair
  snapshot "$UNIT_DIR/stops.before"
  _gr_b="$(ledger_of "$FEATURE_DIR" | grep -c '^- [0-9-]* Repair: ')"
  _gr_p="$PROMPT"; _gr_e="$LAUNCH_ENV"
  PROMPT="/game-dev:execute --gate-repair"
  LAUNCH_ENV="$LAUNCH_ENV STUDIO_REPAIR=$(sq "gate:$(gate_log_of "$FEATURE_DIR")")"
  n=$((${n:-0} + 1)); run_unit "$n" gate-repair
  PROMPT="$_gr_p"; LAUNCH_ENV="$_gr_e"
  if [ "$UNIT_HALTED" != 0 ]; then ENDING="$(lane_halt_reason)"; return 1; fi   # D22
  snapshot "$UNIT_DIR/stops.after"
  take_new_stop "$UNIT_DIR/stops.before" "$UNIT_DIR/stops.after"
  _gr_a="$(ledger_of "$FEATURE_DIR" | grep -c '^- [0-9-]* Repair: ')"
  if [ -n "$NEW_STOP" ]; then row "$n" gate-repair stop; ENDING="$STOP_ENDING"; return 1; fi
  if [ "$_gr_a" -gt "$_gr_b" ]; then row "$n" gate-repair progress; story_write "$1" running; return 0; fi
  _gr_o="$(unit_outcome)"
  if [ "$_gr_o" != "timed out" ]; then row "$n" gate-repair "$_gr_o"; ENDING="gate repair made no progress$(orphan_note "$_gr_o")"
  else row "$n" gate-repair "timed out"; ENDING="gate repair timed out (session_minutes $SESSION_MINUTES)"; fi
  # A halt that ended the unit (or arrived while it ran) names the story's end.
  ! lane_halt || ENDING="$(lane_halt_reason)"
  return 1
}

# ---- The sync check (#39 AC24-26; D28-D34) ----
# unit_pre LABEL — the sync check before a task unit and the final-review
# unit of a story (retries included); never before a repair unit, the
# finish, landing or the final step (D34), and not once the lane must halt.
# 1 when the story must end (ENDING set).
unit_pre() {
  [ -n "${CUR_ID:-}" ] && [ -n "${LDIR:-}" ] || return 0
  case "$1" in T[0-9]*|final-review) ;; *) return 0 ;; esac
  ! lane_halt || return 0
  sync_check "$CUR_ID"
}
# sync_emit ID MERGED — the merged story_synced event (refs in merge order,
# sha the worktree's new head), when MERGED (comma-joined refs) is not empty.
sync_emit() { [ -z "$2" ] || run_event story_synced "story=$1" "refs[]=$2" "sha=$(git -C "$SY_W" rev-parse HEAD)"; }
# sync_check ID — merge each sync ref (origin/<Target>, then origin/<default>
# when the Target is not the default) that moved past the story branch into
# the story worktree, one `chore(sync): merge <ref> into <Branch>` each, and
# push it to origin/<Branch> (AC24-25). It runs only when the story worktree
# exists on <Branch> (else skipped=no-worktree), is clean (skipped=dirty) and
# is not ahead of origin/<Branch> (skipped=ahead, also when there is none:
# D29). A ref that does not resolve is failed=merge-tree (D28); a refused
# merge is aborted and failed=merge (D31). A skip or failure is a
# story_synced event and never stops the story; a conflict (merge-tree exit
# 1) launches one sync repair and ends the check (D33). Writes no studio
# state. Returns sync_repair's status after a conflict, else 0.
sync_check() {
  _sy_b="$(row_field "$1" branch)"
  SY_W="$(story_state "$1" worktree 2>/dev/null)" && [ -n "$SY_W" ] \
    && [ "$(git -C "$SY_W" symbolic-ref -q --short HEAD 2>/dev/null)" = "$_sy_b" ] \
    || { run_event story_synced "story=$1" skipped=no-worktree; return 0; }
  [ -z "$(git -C "$SY_W" status --porcelain 2>/dev/null)" ] || { run_event story_synced "story=$1" skipped=dirty; return 0; }
  git_retry -C "$SY_W" fetch -q origin || { run_event story_synced "story=$1" failed=fetch; return 0; }
  _sy_a="$(git -C "$SY_W" rev-list --count "refs/remotes/origin/$_sy_b..HEAD" 2>/dev/null)" || _sy_a=x
  [ "$_sy_a" = 0 ] || { run_event story_synced "story=$1" skipped=ahead; return 0; }
  _sy_refs="origin/$MF_TARGET"; [ "$MF_TARGET" = "$DEFAULT_BRANCH" ] || _sy_refs="$_sy_refs origin/$DEFAULT_BRANCH"
  _sy_done=""
  for _sy_r in $_sy_refs; do
    git -C "$SY_W" rev-parse -q --verify "refs/remotes/$_sy_r^{commit}" >/dev/null \
      || { sync_emit "$1" "$_sy_done"; run_event story_synced "story=$1" failed=merge-tree; return 0; }
    ! git -C "$SY_W" merge-base --is-ancestor "refs/remotes/$_sy_r" HEAD || continue
    _sy_rc=0; git -C "$SY_W" merge-tree --write-tree HEAD "refs/remotes/$_sy_r" >/dev/null 2>&1 || _sy_rc=$?
    case "$_sy_rc" in
      0) if ! git -C "$SY_W" merge -q --no-ff --no-edit -m "chore(sync): merge $_sy_r into $_sy_b" "refs/remotes/$_sy_r" >/dev/null 2>&1; then
           git -C "$SY_W" merge --abort >/dev/null 2>&1
           [ -z "$(git -C "$SY_W" status --porcelain 2>/dev/null)" ] \
             || say "sync: $SY_W is not clean after merge --abort — left as is for the next unit"
           sync_emit "$1" "$_sy_done"; run_event story_synced "story=$1" failed=merge; return 0
         fi
         _sy_done="$_sy_done${_sy_done:+,}$_sy_r"
         git_retry -C "$SY_W" push -q origin "HEAD:refs/heads/$_sy_b" \
           || { sync_emit "$1" "$_sy_done"; run_event story_synced "story=$1" failed=push; return 0; } ;;
      1) sync_emit "$1" "$_sy_done"; sync_repair "$1" "$_sy_r"; return $? ;;
      *) sync_emit "$1" "$_sy_done"; run_event story_synced "story=$1" failed=merge-tree; return 0 ;;
    esac
  done
  sync_emit "$1" "$_sy_done"
  return 0
}
# sync_repair ID REF — one sync-repair unit (AC26) through the landing-repair
# path: stories/ID = sync-repair, then `/game-dev:execute --land` (label
# sync-repair, model_repair) with STUDIO_REPAIR=sync:REF added to the story's
# env words. Returns 0 when the feature ledger gained a `Synced:` line: the
# record goes back to running, stops.before is taken again, and the story's
# next unit runs, once op_boundary, the run budget and the stage (plan or
# execute) are checked again (story_units checked them before the repair;
# their endings are story_units'). Else returns 1 with ENDING set, and the
# story stops at once (no retry, no hold): the halt reason; `stop: run budget`; `sync repair:
# stop: <reason>` for a new Stop: line; `sync repair: no progress [(orphaned:
# …)]`; `sync repair: timed out (session_minutes N)` (D32).
sync_repair() {
  if lane_halt; then ENDING="$(lane_halt_reason)"; return 1; fi
  if run_budget_out; then ENDING="stop: run budget"; return 1; fi
  story_write "$1" sync-repair
  snapshot "$UNIT_DIR/sync.before"
  _sr_b="$(ledger_of "$FEATURE_DIR" | grep -c '^- [0-9-]* Synced: ')"
  _sr_p="$PROMPT"; _sr_e="$LAUNCH_ENV"
  PROMPT="/game-dev:execute --land"; LAUNCH_ENV="$LAUNCH_ENV STUDIO_REPAIR=$(sq "sync:$2")"
  n=$((${n:-0} + 1)); run_unit "$n" sync-repair
  PROMPT="$_sr_p"; LAUNCH_ENV="$_sr_e"
  if [ "$UNIT_HALTED" != 0 ]; then ENDING="$(lane_halt_reason)"; return 1; fi   # D22
  snapshot "$UNIT_DIR/sync.after"
  take_new_stop "$UNIT_DIR/sync.before" "$UNIT_DIR/sync.after"
  _sr_a="$(ledger_of "$FEATURE_DIR" | grep -c '^- [0-9-]* Synced: ')"
  if [ -n "$NEW_STOP" ]; then row "$n" sync-repair stop; ENDING="sync repair: $STOP_ENDING"; return 1; fi
  if [ "$_sr_a" -gt "$_sr_b" ]; then
    row "$n" sync-repair progress; story_write "$1" running; snapshot "$UNIT_DIR/stops.before"
    # story_units checked these before the repair; the repair took time,
    # money and maybe the stage, so check them again before the next unit.
    op_boundary "$1" || return 1
    if run_budget_out; then ENDING="stop: run budget"; return 1; fi
    case "$SIG_STAGE" in plan|execute) ;; *) ENDING="stop: unexpected stage $SIG_STAGE"; return 1 ;; esac
    return 0
  fi
  _sr_o="$(unit_outcome)"
  if [ "$_sr_o" != "timed out" ]; then row "$n" sync-repair "$_sr_o"; ENDING="sync repair: no progress$(orphan_note "$_sr_o")"
  else row "$n" sync-repair "timed out"; ENDING="sync repair: timed out (session_minutes $SESSION_MINUTES)"; fi
  # A halt that ended the unit (or arrived while it ran) names the story's end.
  ! lane_halt || ENDING="$(lane_halt_reason)"
  return 1
}

# land_story ID — land shipped story ID: take the land lock (polled every
# STUDIO_OVERNIGHT_POLL_SECONDS s; a halt ends the story with its reason),
# land_once, and on a first conflict or red one repair unit and one retry;
# a second one is `stopped landing failed after repair (<conflict|red>)`.
# The lock is held through the repair and its retry, and released on every
# path (the lane's EXIT trap releases it too). Lock order: the land lock,
# then the gate lock (taken by studio-gate in land_once_direct). Returns 0
# when landed (record_landed); else writes the stopped ending, returns 1.
land_story() {
  until land_lock_take; do
    if lane_halt; then story_write "$1" "stopped $(lane_halt_reason)"; return 1; fi
    sleep "${STUDIO_OVERNIGHT_POLL_SECONDS:-5}"
  done
  _ls_rep=0
  while :; do
    land_once "$1"; _ls_st=$?
    case "$_ls_st" in
      0) record_landed "$1" "$LAND_SHA"; land_lock_release; return 0 ;;
      3) if [ "$_ls_rep" = 1 ]; then
           story_write "$1" "stopped landing failed after repair (${LAND_REPAIR%%:*})"; break
         fi
         _ls_rep=1
         land_repair "$1" || break ;;
      *) story_write "$1" "stopped landing failed (${LAND_WHY:-land_once returned $_ls_st})"; break ;;
    esac
  done
  land_lock_release
  return 1
}

# lanes_resume — before the lanes start: each story whose landing git
# (integration) or GitHub (direct) confirms (land_confirm) is recorded
# landed, its landed.tsv line appended when missing (AC8, AC24). Every other
# story starts from its studio state.
lanes_resume() {
  if [ "$MF_MODE" != direct ]; then git_retry -C "$START_DIR" fetch -q origin || return 0; fi
  for _rs_id in $(cut -f1 "$MF_ROWS" | awk '!seen[$0]++'); do
    if land_confirm "$_rs_id"; then record_landed "$_rs_id" "$LAND_SHA"; fi
  done
}

# Manifest mode's story_units helpers: a stop is the lane's halt, and the
# run budget sums every lane's units.tsv (spec 531-534).
stop_requested() { lane_halt; }
spent_all() {
  cat "$RUN_DIR"/lanes/*/units.tsv "$RUN_DIR"/final/units.tsv 2>/dev/null \
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
# Holds in manifest mode (#27): a halt is the lane's (R28), and the held
# record is the story's record, stories/<id> (R4).
halt_reason() { lane_halt_reason; }
hold_record() { story_write "$1" "$2"; }

# ---- Session slots (#39 AC27, AC28; D19-D25) ----
# slot_halt — a wait ends only on a halt (D22): lane_halt in a lane, the stop file for the final step.
slot_halt() { if [ -n "${LANE_PID:-}" ]; then lane_halt; else [ -e "$STOP_FILE" ]; fi; }
# session_acquire LABEL — queue for a project session slot before the unit
# starts (#39 AC27): FIFO, taken before unit_started and the clocks. 1 on a
# halt (the wait entry removed); a queueing that fails is retried, never a
# halt. The first failed try writes slotwait and
# the session_wait event. The key (SESS_ME) is the lane's pid, the runner's
# for a final-step unit, so no two lanes share a mutex key or a wait entry;
# an entry of this key left from an earlier wait goes before queueing.
session_acquire() {
  SESS_ME="${LANE_PID:-$$}"; SESS_RUN="$RUN_DIR"; sess_init
  _sa_story="${CUR_ID:--}"; _sa_lane="${LANE_K:-final}"; _sa_waited=0
  rm -f "$SESS_DIR"/wait/[0-9]*-"$SESS_ME"; SESS_WAIT=""
  # A failed first queueing is not a halt: say it, and the loop queues again.
  sess_enqueue "$_sa_story" "$1" || { SESS_WAIT=""; say "sessions: cannot queue in $STATE_ROOT/.studio/sessions — retrying"; }
  while :; do
    if slot_halt; then sess_wait_cancel; rm -f "$UNIT_DIR/slotwait"; return 1; fi
    if sess_try "$1"; then rm -f "$UNIT_DIR/slotwait"; return 0; fi
    [ -n "$SESS_WAIT" ] || sess_enqueue "$_sa_story" "$1"     # swept: re-queue at the tail
    if [ "$_sa_waited" = 0 ]; then
      _sa_waited=1; date +%H:%M > "$UNIT_DIR/slotwait"
      run_event session_wait "lane=$_sa_lane" "story=$_sa_story" "since=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    fi
    sleep "${STUDIO_OVERNIGHT_SLOT_POLL_SECONDS:-2}"
  done
}
# session_started PID — the slot's owner names the unit's session pid too.
session_started() { sess_session "$1"; }
# session_release — this lane's slot (owner-checked), any wait entry and its
# slotwait go (a HUP or runner error mid-wait must not leave a stale wait).
session_release() { sess_release; sess_wait_cancel; [ -z "${UNIT_DIR:-}" ] || rm -f "$UNIT_DIR/slotwait"; }
# lane_slot_drop K — lanes_end_sessions' part for a dead lane K (AC27): its
# slot and wait entry go, keyed by its pid. Called only after the lane's
# session was ended; a lane still alive releases its own (lane_exit), so a
# slot is never freed under a session that may yet start.
lane_slot_drop() {
  _ld_p="$(cat "$RUN_DIR/lanes/$1/pid" 2>/dev/null)"
  [ -n "$_ld_p" ] && [ -n "${STATE_ROOT:-}" ] && ! pid_live "$_ld_p" || return 0
  SESS_DIR="$STATE_ROOT/.studio/sessions"; SESS_MX="$STATE_ROOT/.studio/sessions.mutex"
  [ -d "$SESS_DIR" ] || return 0
  SESS_ME=$$; sess_drop_owner "$_ld_p"
}
# last_stop_gate_red — the feature ledger's latest Stop: line is a red finish
# gate, `Stop: gate red — …` (the resume's precondition; AC20, R29).
last_stop_gate_red() {
  ledger_of "$FEATURE_DIR" | grep '^- [0-9-]* Stop: ' | tail -n 1 | grep -q '^- [0-9-]* Stop: gate red — '
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
  session_release   # #39 AC27: every exit path, signals included
  land_lock_release
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
# landed; 2 on lane_halt; 3 when the operator stopped ID (control/ID.stop); 1 with BLOCKER=<dep> when a dependency ended
# stopped or skipped, or its chain's claiming lane is dead without its landing.
wait_deps() {
  story_write "$1" waiting
  while :; do
    lane_halt && return 2
    [ ! -f "$RUN_DIR/control/$1.stop" ] || return 3
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
  CPID=""; WPID=""; CUR_ID=""; LANE_BUDGET=0; LAND_HELD=0
  mkdir -p "$LDIR" || exit 3
  sh -c 'echo $PPID' > "$LDIR/pid"; LANE_PID="$(cat "$LDIR/pid")"   # the land lock's holder
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
    # Landed already (lanes_resume confirmed it): nothing to run or wait for.
    case "$(story_get "$_rc_id")" in landed*) _rc_first=0; continue ;; esac
    if [ -n "$_rc_skip" ]; then story_write "$_rc_id" "$_rc_skip"; ctl_clear "$_rc_id"; continue; fi
    if [ "$_rc_first" = 1 ] && [ "$_rc_w" != - ]; then
      CUR_ID="$_rc_id"   # a lane that dies while waiting still ends the story
      wait_deps "$_rc_id" "$_rc_w"; _rc_wd=$?
      CUR_ID=""
      case "$_rc_wd" in
        1) story_write "$_rc_id" "skipped $BLOCKER"; ctl_clear "$_rc_id"; _rc_skip="skipped $_rc_id"; continue ;;
        2) story_write "$_rc_id" "skipped: run stopped"; ctl_clear "$_rc_id"; _rc_skip="skipped: run stopped"; continue ;;
        3) story_write "$_rc_id" "stopped by operator"; ctl_clear "$_rc_id"; _rc_skip="skipped $_rc_id"; continue ;;
      esac
    fi
    _rc_first=0
    # An operator stop that reached a queued story (AC7, R7): it never starts.
    if ctl_take "$_rc_id" stop; then
      story_write "$_rc_id" "stopped by operator"; ctl_clear "$_rc_id"; _rc_skip="skipped $_rc_id"; continue
    fi
    run_story "$_rc_id"
    case "$(story_get "$_rc_id")" in landed*) ;; *) _rc_skip="skipped $_rc_id" ;; esac
  done
}

# story_gate_loop ID — the red-finish repair loop: a `stop: gate red — <line>`
# ending gets a gate-repair unit and the unit loop again, up to gate_repairs
# repairs in all (_rs_rep counts every repair unit of the story, those after
# a resume included); past that, `gate red after <k> repairs — <line>`
# (gate_repairs 0 keeps `stop: gate red — <line>`). The operator boundary
# (R8) runs before each repair unit.
story_gate_loop() {
  while :; do
    case "$ENDING" in "stop: gate red — "*) ;; *) break ;; esac
    if [ "$_rs_rep" -ge "$GATE_REPAIRS" ]; then
      [ "$_rs_rep" -eq 0 ] || ENDING="gate red after $_rs_rep repairs — ${ENDING#stop: gate red — }"
      break
    fi
    op_boundary "$1" || break
    _rs_rep=$((_rs_rep + 1))
    gate_repair "$1" || break
    story_units
  done
}
# run_story ID — bundle 2's unit loop for one story, one fresh session per
# unit, under the story's env; then its landing. A red finish gate (`stop:
# gate red — <line>`, the one repairable stop) gets a gate-repair unit and
# then the unit loop again (a fresh finish: the full gate), up to
# gate_repairs times; past that the story ends `stopped gate red after <k>
# repairs — <line>` (gate_repairs 0: `stopped stop: gate red — <line>`). A
# holdable ending enters the hold loop (hold_wait) instead; an operator stop
# is `stopped by operator`; a story's control files go when it ends.
run_story() {
  CUR_ID="$1"
  STUDIO_STORY="$1"; STUDIO_RUN="$RUN_DIR/manifest.md"; STUDIO_DOCS_REV="$MF_DOCS"
  BASH_DEFAULT_TIMEOUT_MS=$((SESSION_MINUTES * 60000)); BASH_MAX_TIMEOUT_MS="$BASH_DEFAULT_TIMEOUT_MS"
  export STUDIO_STORY STUDIO_RUN STUDIO_DOCS_REV BASH_DEFAULT_TIMEOUT_MS BASH_MAX_TIMEOUT_MS
  LAUNCH_ENV="$(story_launch_env "$1")"
  UNIT_PREFIX=""   # run_unit names files <n>-<id>-<label> from CUR_ID (T5)
  story_write "$1" running
  # A story already shipped (stage idle, a shipped line) only lands: no
  # unit, straight to land_story (resume, AC24). n is the story's unit
  # counter (story_units'); a landing repair takes the next number.
  n=0; STOP_ENDING=""; STOP_SRC=""
  snapshot "$UNIT_DIR/stops.before"
  if [ "$SIG_STAGE" = idle ] && [ "$SIG_SHIPPED" -gt 0 ]; then ENDING=done; else story_units; fi
  _rs_rep=0
  # Hold loop (AC17-25): a holdable ending waits for the operator; a resume
  # runs one gate repair first when the latest Stop is gate red (AC20), then
  # the unit loop, and the post-loop handling again.
  while :; do
    story_gate_loop "$1"
    # story_units says `stopped by user` for any halt; name the real one.
    [ "$ENDING" != "stopped by user" ] || ENDING="$(lane_halt_reason)"
    holdable || break
    hold_wait "$1" || break
    if last_stop_gate_red; then
      op_boundary "$1" || continue
      _rs_rep=$((_rs_rep + 1))
      gate_repair "$1" || continue
    fi
    story_units
  done
  # A halt that raced the operator's hold keeps the halt's reason (hold_wait
  # maps an operator stop of a held story itself).
  [ "$ENDING" != "held by operator" ] || ENDING="$(lane_halt_reason)"
  # A halt also holds back the landing (spec 124-127); so does an operator
  # stop that arrived during the last unit (R5).
  [ "$ENDING" != done ] || ! lane_halt || ENDING="$(lane_halt_reason)"
  [ "$ENDING" != done ] || ! ctl_take "$1" stop || ENDING="stopped by operator"
  case "$ENDING" in
    done) story_write "$1" landing; land_story "$1" ;;
    "stopped by operator") story_write "$1" "$ENDING" ;;
    *) story_write "$1" "stopped $ENDING"
       [ "$ENDING" != "stop: run budget" ] || LANE_BUDGET=1 ;;
  esac
  ctl_clear "$1"
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
# not. The lane's unit watchdog (lanes/K/wpid) and heartbeat (lanes/K/hbpid)
# are ended first, so a dead lane's watchdog never outlives it to signal a
# reused pgid at its deadline. The gates each lane's session left behind are
# reaped in parallel, so the teardown waits one grace, not one per lane.
# Once its session is ended, a dead lane's session slot and wait entry go
# (lane_slot_drop, #39 AC27); a live lane releases its own on exit.
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
    if [ -f "$_es_d/hbpid" ]; then
      _es_h="$(cat "$_es_d/hbpid" 2>/dev/null)"
      [ -z "$_es_h" ] || kill "$_es_h" 2>/dev/null   # its TERM trap ends its sleep
      rm -f "$_es_d/hbpid"
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
  _es_r=""
  for _es_k in "$@"; do
    rm -f "$RUN_DIR/lanes/$_es_k/cpid" "$RUN_DIR/lanes/$_es_k/unit.now"
    # The gates the ended session left behind (run_unit never got to reap them).
    _es_t="$(cat "$RUN_DIR/lanes/$_es_k/utag" 2>/dev/null)"
    if [ -n "$_es_t" ]; then unit_reap "$_es_t" & _es_r="$_es_r $!"; fi
    rm -f "$RUN_DIR/lanes/$_es_k/utag"
    lane_slot_drop "$_es_k"   # its session is ended: a dead lane's slot and wait entry go (AC27)
  done
  if [ -n "$_es_r" ]; then
    wait $_es_r 2>/dev/null
    rmdir "${STATE_ROOT:-}/.studio/gate.units" 2>/dev/null
  fi
  return 0
}

# lanes_sweep — the parent's sweep once every lane has exited (D2): in a
# claimed chain, the first story with no ending is `stopped: lane crashed
# (<rc of its lane>)` (that lane's orphaned session ended first) and every
# later one `skipped <that id>`; every story of an unclaimed chain is
# `skipped: run stopped`. Lane rcs are LANE_RC_<k>, set by the wait loop.
# SWEEP_WHY, when set, replaces the crash text (lanes_reap: the runner died).
# Every dead lane's session slot and wait entry go (lane_slot_drop), only
# once its session is ended (a lane with a cpid left is ended above first).
lanes_sweep() {
  for _sw_c in $(cut -f1 "$CHAINS"); do
    if [ -d "$RUN_DIR/claims/$_sw_c" ]; then
      for _sw_id in $(chain_members "$_sw_c"); do
        is_ending "$(story_get "$_sw_id")" && continue
        # A lane killed between a landing's push and its record: git or
        # GitHub confirms the landing (Review Focus 1), so it is landed.
        case "$(story_get "$_sw_id")" in
          landing|repair)
            if { [ "$MF_MODE" = direct ] || git_retry -C "$START_DIR" fetch -q origin; } && land_confirm "$_sw_id"; then
              record_landed "$_sw_id" "$LAND_SHA"; continue
            fi ;;
        esac
        _sw_k="$(cat "$RUN_DIR/claims/$_sw_c/lane" 2>/dev/null)"; _sw_rc=unknown
        case "$_sw_k" in
          ''|*[!0-9]*) ;;
          *) eval "_sw_rc=\${LANE_RC_$_sw_k:-unknown}"; lanes_end_sessions "$_sw_k" ;;
        esac
        story_write "$_sw_id" "${SWEEP_WHY:-stopped: lane crashed ($_sw_rc)}"
        chain_skip_after "$_sw_id" "skipped $_sw_id"
        break
      done
    else
      for _sw_id in $(chain_members "$_sw_c"); do
        is_ending "$(story_get "$_sw_id")" || story_write "$_sw_id" "skipped: run stopped"
      done
    fi
  done
  # A dead lane with no session left (no cpid) still frees its slot and wait entry (#39 AC27).
  for _sw_d in "$RUN_DIR"/lanes/*; do
    [ -d "$_sw_d" ] && [ ! -f "$_sw_d/cpid" ] || continue
    lane_slot_drop "${_sw_d##*/}"
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

# ---- Run endings, status and report.md (spec 283-292, 537-553; AC15-AC18) ----

# lanes_counts — over the manifest's stories: LC_N landed, LC_S stopped,
# LC_K skipped; LC_ALL is 1 when every story landed.
lanes_counts() {
  LC_N=0; LC_S=0; LC_K=0; LC_ALL=1
  for _lc in $(cut -f1 "$MF_ROWS" | awk '!seen[$0]++'); do
    case "$(story_get "$_lc")" in
      landed*) LC_N=$((LC_N + 1)) ;;
      stopped*) LC_S=$((LC_S + 1)); LC_ALL=0 ;;
      skipped*) LC_K=$((LC_K + 1)); LC_ALL=0 ;;
      *) LC_ALL=0 ;;
    esac
  done
}
# final_ok — the final step ran and reached its goal: integration, the final
# PR is open and green (a red gate or a red step is not); direct, the step
# returned 0 (the progress PR landed, or there is no PROGRESS.md).
final_ok() {
  [ "${FINAL_RAN:-0}" = 1 ] || return 1
  if [ "$MF_MODE" = direct ]; then [ "${FINAL_RC:-1}" = 0 ]
  else [ -n "${FINAL_PR:-}" ] && [ "${FINAL_COLOR:-}" = green ]; fi
}
# lanes_ending — the run's ending: `done` when every story landed and the
# final step reached its goal (final_ok); else `stopped by user` when a stop
# was requested; else `partial: <n> landed, <m> stopped, <k> skipped`, with
# `; final PR red`, `; no final PR` or `; progress PR not landed` when the
# final step ran and fell short.
lanes_ending() {
  lanes_counts
  if [ "$LC_ALL" = 1 ] && final_ok; then echo done; return 0; fi
  if [ -e "$STOP_FILE" ]; then echo "stopped by user"; return 0; fi
  _le="partial: $LC_N landed, $LC_S stopped, $LC_K skipped"
  if [ "${FINAL_RAN:-0}" = 1 ] && ! final_ok; then
    if [ "$MF_MODE" = direct ]; then _le="$_le; progress PR not landed"
    elif [ -n "${FINAL_PR:-}" ]; then _le="$_le; final PR red"
    else _le="$_le; no final PR"; fi
  fi
  printf '%s\n' "$_le"
}

# story_why RECORD — the `Not landed:` text of a story record that is not
# `landed`: a skip names its blocking dependency (`skipped — waits on A`).
story_why() {
  case "$1" in
    'skipped: '*) printf 'skipped — %s\n' "${1#skipped: }" ;;
    'skipped '*) printf 'skipped — waits on %s\n' "${1#skipped }" ;;
    stopped:*) printf '%s\n' "$1" ;;
    'stopped '*) printf 'stopped — %s\n' "${1#stopped }" ;;
    '') echo "no ending" ;;
    *) printf 'no ending (%s)\n' "$1" ;;
  esac
}
# story_ledger_text ID — ID's whole feature ledger: from its story worktree, else its branch (local, then origin), else its
# merge commit's second parent, else the landed commit itself.
story_ledger_text() {
  _sl_b="$(row_field "$1" branch)"; _sl_f=".studio/ledger/$1.md"; _sl_sha=""
  case "$(story_get "$1")" in "landed "*) _sl_sha="$(story_get "$1")"; _sl_sha="${_sl_sha#landed }" ;; esac
  _sl_w="$(story_state "$1" worktree 2>/dev/null)"
  { if [ -n "$_sl_w" ] && [ -f "$_sl_w/$_sl_f" ]; then cat "$_sl_w/$_sl_f"
    else git -C "$START_DIR" show "refs/heads/$_sl_b:$_sl_f" \
      || git -C "$START_DIR" show "refs/remotes/origin/$_sl_b:$_sl_f" \
      || { [ -n "$_sl_sha" ] && { git -C "$START_DIR" show "$_sl_sha^2:$_sl_f" || git -C "$START_DIR" show "$_sl_sha:$_sl_f"; }; }
    fi; } 2>/dev/null
}
story_ledger_lines() { story_ledger_text "$1" | grep -E '^- [0-9-]+ (([^ ]+ )?Ruling: |P[0-9]+ Play: )'; }
# story_units_table ID — ID's rows of every lane's units.tsv (the label is
# `<id>-<unit label>`) as a markdown table; `(no units)` when none ran.
story_units_table() {
  cat "$RUN_DIR"/lanes/*/units.tsv 2>/dev/null | awk -F'\t' -v p="$1-" '
    index($2, p) == 1 && substr($2, length(p) + 1) ~ /^(T[0-9]+|check|final-review|finish|repair|gate-repair|sync-repair)(-retry)?$/ {
      if (!n++) print "| # | Unit | Exit | Cost | Minutes | Timed out | Outcome |\n|---|------|------|------|---------|-----------|---------|"
      printf "| %s | %s | %s | %s | %s | %s | %s |\n", $1, $2, $3, $4, $5, $6, $7 }
    END { if (!n) print "(no units)" }'
}
# final_why ENDING — why there is no final PR.
final_why() {
  if [ "${FINAL_RAN:-0}" = 1 ]; then
    if [ "$MF_MODE" = direct ] && [ -z "${FINAL_COLOR:-}" ]; then echo "no PROGRESS.md"
    else printf '%s\n' "${FINAL_NOTE:-the final step opened none}"; fi
  elif [ "$LC_N" = 0 ]; then echo "no story landed"
  elif [ "$1" = "stopped by user" ]; then echo "the run was stopped"
  else printf 'the final step did not run: %s\n' "$1"; fi
}
# shell_word TEXT — TEXT as it is when it is a plain path, else single-quoted.
shell_word() {
  case "$1" in *[!A-Za-z0-9._/-]*|'') sq "$1" ;; *) printf '%s' "$1" ;; esac
}
# lanes_report ENDING — RUN_DIR/report.md, the morning report, on every
# ending: the head (ending, mode, target, spend, times, story counts, the
# final PR), direct mode's `## Landed`, a `## <id>` section per story in
# manifest order (its ending, branch, landed sha or why not, units, rulings
# and play list), integration mode's open bundle-2 PRs (named, never
# closed), `## Resume` when not done, and `## Cleanup`: the one command that
# deletes the run's remote branches. The run itself never deletes one.
lanes_report() {
  lanes_counts
  _r_unk="$(cat "$RUN_DIR"/lanes/*/units.tsv "$RUN_DIR"/final/units.tsv 2>/dev/null \
    | awk -F'\t' '$4 == "unknown" { n++ } END { print n + 0 }')"
  _r_sp="$(spent_all)"; [ "$_r_unk" -eq 0 ] || _r_sp="$_r_sp (cost unknown for $_r_unk unit(s))"
  _r_st=""
  [ "$(sed -n 's/^run=//p' "$LOCK" 2>/dev/null | head -n 1)" != "$RUN_DIR" ] \
    || _r_st="$(sed -n 's/^started=//p' "$LOCK" 2>/dev/null | head -n 1)"
  _r_mf="$(cat "$RUN_DIR/manifest.path" 2>/dev/null)"; [ -n "$_r_mf" ] || _r_mf="docs/runs/$MF_SLUG.md"
  _r_ids="$(cut -f1 "$MF_ROWS" | awk '!seen[$0]++')"
  {
    printf '# Overnight run — %s\n\n' "$MF_SLUG"
    printf 'Ending: %s\n' "$1"
    printf 'Mode: %s\nTarget: %s\n' "$MF_MODE" "$MF_TARGET"
    printf 'Spent: $%s\n' "$_r_sp"
    printf 'Started: %s · Ended: %s\n' "${_r_st:-unknown}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'Stories: %s landed, %s stopped, %s skipped\n' "$LC_N" "$LC_S" "$LC_K"
    if [ -n "${FINAL_PR:-}" ]; then printf 'Final PR: %s (%s)\n' "$FINAL_PR" "${FINAL_COLOR:-red}"
    else printf 'Final PR: none (%s)\n' "$(final_why "$1")"; fi
    [ -z "${FINAL_NOTE:-}" ] || printf 'Final note: %s\n' "$FINAL_NOTE"
    printf 'Run: %s\n' "$RUN_DIR"
    if [ "$MF_MODE" = direct ]; then
      printf '\n## Landed\n\n'
      _r_any=0
      for _r_id in $_r_ids; do
        case "$(story_get "$_r_id")" in "landed "*) _r_any=1; printf '%s %s\n' "$_r_id" "$(story_get "$_r_id" | cut -d' ' -f2)" ;; esac
      done
      [ "$_r_any" = 1 ] || echo "(none)"
      if [ -n "${FINAL_PR:-}" ]; then
        if [ "${FINAL_RC:-1}" = 0 ]; then printf 'Progress PR: %s (landed)\n' "$FINAL_PR"
        else printf 'Progress PR: %s (left open)\n' "$FINAL_PR"; fi
      else printf 'Progress PR: none (%s)\n' "$(final_why "$1")"; fi
    fi
    for _r_id in $_r_ids; do
      _r_s="$(story_get "$_r_id")"
      printf '\n## %s\n\n' "$_r_id"
      printf 'Ending: %s\n' "${_r_s:-no ending}"
      printf 'Branch: %s\n' "$(row_field "$_r_id" branch)"
      case "$_r_s" in
        "landed "*) printf 'Landed: %s\n' "${_r_s#landed }" ;;
        *) printf 'Not landed: %s\n' "$(story_why "$_r_s")" ;;
      esac
      _r_orig="$(story_ledger_text "$_r_id" | sed -n 's/^- [0-9-]* adopted \(.*\) -> .*$/\1/p' | tail -n 1)"
      if [ -n "$_r_orig" ]; then
        case "$_r_s" in
          "landed "*) printf 'Adopted from %s; landed on %s — continue dependent stories from there\n' "$_r_orig" "$MF_TARGET" ;;
          *) _r_w="$(story_state "$_r_id" worktree 2>/dev/null)"
             [ -n "$_r_w" ] || _r_w="$STATE_ROOT/.claude/worktrees/$(row_field "$_r_id" branch | tr / -)"
             printf 'Adopted from %s. To continue the standard way: cd %s && %s sync %s\n' \
               "$_r_orig" "$(sq "$_r_w")" "$(sq "$SELF_DIR/studio-adopt")" "$_r_id" ;;
        esac
      fi
      printf '\n'; story_units_table "$_r_id"
      _r_l="$(story_ledger_lines "$_r_id")"
      [ -z "$_r_l" ] || printf '\n%s\n' "$_r_l"
      _r_m="$(msgs_left "$_r_id")"
      [ -z "$_r_m" ] || printf '\nOperator messages left:\n%s\n' "$_r_m"
    done
    if [ "$MF_MODE" != direct ]; then
      printf '\n## Open bundle-2 PRs\n\n'
      _r_any=0
      for _r_id in $_r_ids; do
        _r_b="$(row_field "$_r_id" branch)"
        final_pr_open "$_r_b"
        case $? in
          0) _r_any=1; printf -- '- %s: %s (%s into %s) — left open; the run never closes it\n' "$_r_id" "$FP_URL" "$_r_b" "$DEFAULT_BRANCH" ;;
          2) _r_any=1; printf -- '- %s: gh pr list failed for %s\n' "$_r_id" "$_r_b" ;;
        esac
      done
      [ "$_r_any" = 1 ] || echo "(none)"
    fi
    if [ "$1" != done ]; then
      printf '\n## Resume\n\ncd %s && %s start %s\n' "$(sq "$START_DIR")" "$(sq "$SELF_ABS")" "$(shell_word "$_r_mf")"
    fi
    _r_del="run/$MF_SLUG"
    if [ "$MF_MODE" = direct ]; then
      ! git -C "$START_DIR" rev-parse -q --verify "refs/remotes/origin/progress/$MF_SLUG" >/dev/null \
        || _r_del="$_r_del progress/$MF_SLUG"
    else
      _r_del="$_r_del $MF_TARGET"
    fi
    for _r_id in $_r_ids; do
      case "$(story_get "$_r_id")" in "landed "*) _r_del="$_r_del $(row_field "$_r_id" branch)" ;; esac
    done
    printf '\n## Cleanup\n\nRun this after the final PR is landed; the run itself never deletes a remote branch.\n\n'
    printf 'cd %s && git push origin --delete %s\n' "$(sq "$START_DIR")" "$_r_del"
  } > "$RUN_DIR/report.md"
  run_event run_ended "ending=$1" "report=$RUN_DIR/report.md"
}
# lanes_finish ENDING — report; RECORD/done on `done` (removed on any other
# ending); unlock; exit 0 only for done.
lanes_finish() {
  lanes_report "$1"
  if [ "$1" = done ]; then : > "$RECORD/done"; else rm -f "$RECORD/done"; fi
  unlock
  REPORTED=1
  [ "$1" = done ] && exit 0
  exit 1
}

# lanes_load_run DIR — the variables of manifest run DIR, from its own copies
# (manifest.md, rows.tsv, chains), for `status` and the stale-run reap.
lanes_load_run() {
  RUN_DIR="$1"; MF="$RUN_DIR/manifest.md"; MF_ROWS="$RUN_DIR/rows.tsv"; CHAINS="$RUN_DIR/chains"
  MF_SLUG="$(mf_slug)"; MF_MODE="$(mf_header Mode)"; MF_TARGET="$(mf_header Target)"
  MF_DOCS="$(mf_header Docs)"; MF_GOAL="$(mf_header Goal)"
  RECORD="$STATE_ROOT/.studio/runs/$MF_SLUG"
  if [ -z "${DEFAULT_BRANCH:-}" ]; then
    DEFAULT_BRANCH="$(git -C "$START_DIR" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"
    DEFAULT_BRANCH="${DEFAULT_BRANCH#origin/}"
  fi
  FINAL_PR=""; FINAL_COLOR=""; FINAL_NOTE=""; FINAL_RAN=0; FINAL_RC=1
  # A runner killed after its final step left RECORD/final: the PR it names
  # (while the record's head is still origin/<Target>'s) is the run's final PR.
  if [ -f "$RECORD/final" ]; then
    _lr_s=""; _lr_u=""; _lr_c=""
    read -r _lr_s _lr_u _lr_c < "$RECORD/final"
    _lr_h="$(git -C "$START_DIR" rev-parse -q --verify "refs/remotes/origin/$MF_TARGET^{commit}" 2>/dev/null)"
    if [ -n "$_lr_u" ] && [ "$_lr_s" = "$_lr_h" ]; then
      FINAL_PR="$_lr_u"; FINAL_COLOR="${_lr_c:-red}"; FINAL_RAN=1; FINAL_RC=0
    fi
  fi
}
# lanes_live_lanes — the pids of RUN_DIR's lanes that still run (a lane is a
# subshell of studio-overnight: its args name it).
lanes_live_lanes() {
  for _ll in "$RUN_DIR"/lanes/*/pid; do
    [ -f "$_ll" ] || continue
    _ll_p="$(cat "$_ll" 2>/dev/null)"
    [ -n "$_ll_p" ] && pid_live "$_ll_p" && ps -o args= -p "$_ll_p" 2>/dev/null | grep -q studio-overnight \
      && printf '%s ' "$_ll_p"
  done
}
# lanes_reap — RUN_DIR (loaded) is a run whose runner died without its
# report (a SIGKILL; AC16): once none of its lanes runs, every story with no
# ending gets one (lanes_sweep: a claimed chain's `stopped: runner gone`, an
# unclaimed chain's `skipped: run stopped`, D2), then report.md. Returns 1,
# writing nothing, while a lane still runs (LR_LIVE names them).
lanes_reap() {
  LR_LIVE="$(lanes_live_lanes)"
  [ -z "$LR_LIVE" ] || return 1
  EV_ON=1
  SWEEP_WHY="stopped: runner gone"
  lanes_sweep
  SWEEP_WHY=""
  lanes_report "stop: runner gone"
}
# lanes_reap_at LOCKFILE — a stale lock (its holder dead) naming a manifest
# run with no report.md gets lanes_reap, in a subshell (it loads that run's
# own variables) with LOCK set to LOCKFILE and START_DIR from the run's
# recorded start dir (D12), so its Resume line names its own checkout.
# Returns 1 after a refusal while that run's lanes still run.
lanes_reap_at() {
  [ -f "$1" ] && ! runs_lock_live "$1" || return 0
  _rs_d="$(runs_kv run "$1")"
  [ -n "$_rs_d" ] && [ -f "$_rs_d/manifest.md" ] && [ ! -f "$_rs_d/report.md" ] || return 0
  _rs_sd="$(runs_start_dir "$1")"; [ -n "$_rs_sd" ] && [ -d "$_rs_sd" ] || _rs_sd="$START_DIR"
  ( LOCK="$1"; START_DIR="$_rs_sd"; lanes_load_run "$_rs_d"
    lanes_reap || { say "the last run's lanes still run (pids $LR_LIVE) — start again once they end"; exit 1; } )
}
# lanes_reap_stale — before a start takes the lock: this run's own per-run
# lock (after run_paths), reaped when stale (lanes_reap_at).
lanes_reap_stale() { lanes_reap_at "$LOCK"; }
# lanes_reap_old — the same for a dead old-style manifest run on
# .studio/overnight.lock (AC31).
lanes_reap_old() { lanes_reap_at "$STATE_ROOT/.studio/overnight.lock"; }
# lanes_status_lines — one line per story in manifest order: `<id>  lane
# <k|->  <state>  unit <label|->  task <k/N|->`. The lane is its chain's
# claim; the state, the first word of stories/<id>; the unit, lanes/<k>/current
# as written when it names this story and the story has no ending; the task,
# the story's studio state. A story whose unit is running gets a second line,
# indented: `    <unit> · <elapsed> · <last activity>` (unit_now_line); a
# final-step unit, `final: …`. A unit waiting for a session slot (its lane's
# slotwait, #39 D23) gets `    waiting for a session slot since <hh:mm>`
# instead (`final: waiting …`). Then the gate lock (gate_line) and the spend.
lanes_status_lines() {
  # $1 is 1 for a live run: the progress line (first) then has an ETA, and
  # each story line ends with its own bar (progress_story, #37).
  progress_compute manifest "${1:-0}" || true
  progress_overall
  for _st_id in $(cut -f1 "$MF_ROWS" | awk '!seen[$0]++'); do
    _st_k="$(cat "$RUN_DIR/claims/$(chain_of "$_st_id")/lane" 2>/dev/null)"; [ -n "$_st_k" ] || _st_k=-
    _st_r="$(story_get "$_st_id")"; _st_s="${_st_r%% *}"; _st_s="${_st_s%:}"; [ -n "$_st_s" ] || _st_s=-
    _st_u=-
    if [ "$_st_k" != - ] && ! is_ending "$_st_r"; then
      _st_c="$(cat "$RUN_DIR/lanes/$_st_k/current" 2>/dev/null)"
      case "$_st_c" in "$_st_id "*) _st_u="$_st_c" ;; esac
    fi
    _st_t="$(progress_task "$_st_id" 2>/dev/null)" || _st_t="$(story_state "$_st_id" get task 2>/dev/null)"
    [ -n "$_st_t" ] || _st_t=-
    printf '%s  lane %s  %s  unit %s  task %s%s\n' "$_st_id" "$_st_k" "$_st_s" "$_st_u" "$_st_t" "$(progress_story "$_st_id")"
    case "$_st_r" in
      "held "*) printf '    %s\n' "$(held_line "$_st_r" "$_st_id")" ;;
      *) if [ "$_st_u" != - ] && [ -f "$RUN_DIR/lanes/$_st_k/slotwait" ]; then
           printf '    waiting for a session slot since %s\n' "$(cat "$RUN_DIR/lanes/$_st_k/slotwait" 2>/dev/null)"
         elif [ "$_st_u" != - ]; then
           _st_n="$(unit_now_line "$RUN_DIR/lanes/$_st_k")"
           [ -z "$_st_n" ] || printf '    %s\n' "$_st_n"
         fi ;;
    esac
  done
  if [ -f "$RUN_DIR/final/slotwait" ]; then
    printf 'final: waiting for a session slot since %s\n' "$(cat "$RUN_DIR/final/slotwait" 2>/dev/null)"
  else
    _st_n="$(unit_now_line "$RUN_DIR/final")"; [ -z "$_st_n" ] || printf 'final: %s\n' "$_st_n"
  fi
  gate_line "$RUN_DIR"
  printf 'spent: $%s\n' "$(spent_all)"
  progress_done
}
# lanes_status DIR [live] — the `status` verb for manifest run DIR. Live:
# the lines, `pid: <runner pid>` and the run dir; exit 0. Not live: a stale
# run with no report is reaped first (lanes_reap); `no run — the last run:
# DIR`, its ended_line, the lines, then the report's path (or the lanes
# still finishing).
lanes_status() {
  lanes_load_run "$1"
  if [ "${2:-}" = live ]; then
    lanes_status_lines 1
    printf 'pid: %s\nrun: %s\n' "$(lock_pid)" "$RUN_DIR"
    env_line "$(lock_pid)"
    return 0
  fi
  LR_LIVE=""
  [ -f "$RUN_DIR/report.md" ] || lanes_reap
  printf 'no run — the last run: %s\n' "$RUN_DIR"
  [ ! -f "$RUN_DIR/report.md" ] || ended_line "$RUN_DIR/report.md"
  lanes_status_lines 0
  if [ -n "$LR_LIVE" ]; then printf 'pid: none (the runner is gone; lanes still finishing: %s)\n' "$LR_LIVE"
  else printf 'report: %s\n' "$RUN_DIR/report.md"; fi
  return 1
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
  end_session   # a final-step unit the runner itself is waiting on
  session_release
  lanes_end_sessions
  lanes_wait_all
  lanes_sweep
  lanes_report "$_oe_why"
  rm -f "$RECORD/done"
  unlock
  exit 1
}

# ---- The final step (spec 587-626, AC9; D5, D13, D17, D21, D23) ----
# Run by the parent once every lane has exited, no stop was requested and at
# least one story landed. Integration: final_integration. Direct:
# progress_direct, only when PROGRESS.md exists. Results for the report:
# FINAL_PR (url), FINAL_COLOR (green|red), FINAL_NOTE. Nothing is ever
# merged into the default branch by the integration step, and its PR is
# never merged by the run.

# any_landed — at least one story of the run ended landed.
any_landed() {
  for _al in $(cut -f1 "$MF_ROWS" | awk '!seen[$0]++'); do
    case "$(story_get "$_al")" in landed*) return 0 ;; esac
  done
  return 1
}
# progress_exists — docs/game-dev/PROGRESS.md exists at the Docs revision.
progress_exists() { git -C "$START_DIR" cat-file -e "$MF_DOCS:docs/game-dev/PROGRESS.md" 2>/dev/null; }
# final_note TEXT — append TEXT to FINAL_NOTE ("; "-joined).
final_note() { FINAL_NOTE="${FINAL_NOTE:+$FINAL_NOTE; }$1"; }
# final_stopped STEP — true (with a note) when a stop arrived during the
# final step: the step ends before STEP, nothing more is launched or pushed.
final_stopped() {
  [ -e "$STOP_FILE" ] || return 1
  FINAL_COLOR=red; final_note "stopped before $1"
}

# final_unit LABEL PROMPT [ENV_WORDS] — one unit run by the parent (label
# progress or final-repair; model by model_for, D23) with cwd FINAL_W
# (UNIT_CWD) and its files under RUN_DIR/final (UNIT_DIR). Env words:
# OMEGA_AUTOPILOT, STUDIO_RUN, STUDIO_DOCS_REV and the Bash timeouts, plus
# ENV_WORDS (KEY='value', sq-quoted); never STUDIO_STORY. Its row in
# final/units.tsv is `progress` when FINAL_W's HEAD moved, else `noprog`
# (`timed out` when the session cap ended it, `orphaned` when print mode
# killed its background work).
# Returns 1, launching nothing, when a stop was requested (before the unit or
# while it waited for a session slot, `stopped before <label>`) or the run budget
# (story_units' rule: spent_all + SESSION_USD > RUN_USD) refuses it, with a
# note. Returns 2 when the unit left FINAL_W dirty: the uncommitted work is
# discarded (reset --hard, clean -fd) and the step is red, so no gate ever
# tests work that HEAD, and so the push, does not hold.
final_unit() {
  [ ! -e "$STOP_FILE" ] || return 1
  if awk -v r="$RUN_USD" 'BEGIN { exit !(r > 0) }' \
     && awk -v s="$(spent_all)" -v u="$SESSION_USD" -v r="$RUN_USD" 'BEGIN { exit !(s + u > r) }'; then
    final_note "run budget: no $1 unit"; return 1
  fi
  UNIT_DIR="$RUN_DIR/final"; UNIT_PREFIX=""; CUR_ID=""
  mkdir -p "$UNIT_DIR" || return 1
  _fu_ms=$((SESSION_MINUTES * 60000))
  LAUNCH_ENV="OMEGA_AUTOPILOT=$(sq 1) STUDIO_RUN=$(sq "$RUN_DIR/manifest.md") STUDIO_DOCS_REV=$(sq "$MF_DOCS") BASH_DEFAULT_TIMEOUT_MS=$(sq "$_fu_ms") BASH_MAX_TIMEOUT_MS=$(sq "$_fu_ms")${3:+ $3}"
  _fu_p="$PROMPT"; PROMPT="$2"; UNIT_CWD="$FINAL_W"
  _fu_h0="$(git -C "$FINAL_W" rev-parse HEAD 2>/dev/null)"
  FINAL_N=$((${FINAL_N:-0} + 1)); run_unit "$FINAL_N" "$1"
  PROMPT="$_fu_p"; UNIT_CWD=""; LAUNCH_ENV=""
  # A stop while it waited for a session slot (D22): nothing ran.
  if [ "$UNIT_HALTED" != 0 ]; then FINAL_COLOR=red; final_note "stopped before $1"; return 1; fi
  if [ "$(git -C "$FINAL_W" rev-parse HEAD 2>/dev/null)" != "$_fu_h0" ]; then row "$FINAL_N" "$1" progress
  else row "$FINAL_N" "$1" "$(unit_outcome)"; fi
  if [ -n "$(git -C "$FINAL_W" status --porcelain 2>&1)" ]; then
    FINAL_COLOR=red; final_note "the $1 unit left uncommitted changes (discarded)"
    git -C "$FINAL_W" merge --abort >/dev/null 2>&1
    git -C "$FINAL_W" reset -q --hard HEAD >/dev/null 2>&1
    git -C "$FINAL_W" clean -fdq >/dev/null 2>&1
    return 2
  fi
  return 0
}

# final_gate_cmds — the full gate's shell text: execute §7 step 1's
# commands and exit rules (studio-lint's exit 3, no linter, is not red).
# The test hook STUDIO_OVERNIGHT_GATE_CMD replaces its engine part; the
# project's gate_command (studio-setup gate) follows either way (D10).
final_gate_cmds() {
  if [ -n "${STUDIO_OVERNIGHT_GATE_CMD:-}" ]; then _fg_part="$STUDIO_OVERNIGHT_GATE_CMD"
  else
    _fg_part="$(printf 'sh %s && { sh %s; _lint=$?; [ "$_lint" -eq 0 ] || [ "$_lint" -eq 3 ]; } && sh %s --seconds 10' \
      "$(sq "$SELF_DIR/studio-test")" "$(sq "$SELF_DIR/studio-lint")" "$(sq "$SELF_DIR/studio-run")")"
  fi
  # D10: the project's gate_command always follows (studio-setup gate is silent when unset).
  printf '{ %s\n} && sh %s gate\n' "$_fg_part" "$(sq "$SELF_DIR/studio-setup")"
}
# gate_signalled RC — RC is studio-gate's own exit on a signal (HUP 129,
# INT 130, TERM 143): an interrupted gate, not a result.
gate_signalled() { case "$1" in 129|130|143) return 0 ;; esac; return 1; }
# final_gate LOG — the full gate in FINAL_W under the gate lock (studio-gate
# final-gate, D17), stdin /dev/null, output to LOG. Its exit code.
final_gate() {
  _fg_c="$(final_gate_cmds)"
  ( cd "$FINAL_W" && exec sh "$SELF_DIR/studio-gate" final-gate -- sh -c "$_fg_c" ) > "$1" 2>&1 < /dev/null
}

# final_pr_open BRANCH — the open PR of BRANCH into the default branch
# (`gh pr list`): FP_NUM and FP_URL. 0 found · 1 none · 2 gh failed.
final_pr_open() {
  FP_NUM=""; FP_URL=""
  _fp="$(cd "$START_DIR" && gh pr list --head "$1" --base "$DEFAULT_BRANCH" --state open --json number,url 2>/dev/null)" || return 2
  _fp="$(printf '%s' "$_fp" | tr -d '\n')"
  FP_NUM="$(printf '%s\n' "$_fp" | sed -n 's/^[^{]*{[^}]*"number"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p')"
  FP_URL="$(printf '%s\n' "$_fp" | sed -n 's/^[^{]*{[^}]*"url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  [ -n "$FP_NUM" ]
}

# final_body FILE HEAD — the final PR's body, assembled with git and sed (no
# session): per landed story a `## <id>` section with its spec's `## Purpose`
# at the Docs revision, its ledger's `Ruling:` and `P<k> Play:` lines (from
# origin/<Branch>; a deleted branch's from its merge commit's second parent,
# a fast-forward's from the commit itself) and its merge sha; `## Not
# landed` with every other story's ending; the gate line.
final_body() {
  _fb_nl=""
  {
    for _fb_id in $(cut -f1 "$MF_ROWS" | awk '!seen[$0]++'); do
      _fb_s="$(story_get "$_fb_id")"
      case "$_fb_s" in
        landed*) ;;
        *) _fb_nl="$_fb_nl- $_fb_id: ${_fb_s:-no ending}
"; continue ;;
      esac
      _fb_sha="${_fb_s#landed }"; _fb_b="$(row_field "$_fb_id" branch)"
      printf '## %s\n\n' "$_fb_id"
      git -C "$START_DIR" show "$MF_DOCS:$(row_field "$_fb_id" spec)" 2>/dev/null \
        | awk '/^## / { p = ($0 ~ /^## Purpose[ \t]*$/); next } p'
      { git -C "$START_DIR" show "refs/remotes/origin/$_fb_b:.studio/ledger/$_fb_id.md" 2>/dev/null \
          || git -C "$START_DIR" show "$_fb_sha^2:.studio/ledger/$_fb_id.md" 2>/dev/null \
          || git -C "$START_DIR" show "$_fb_sha:.studio/ledger/$_fb_id.md" 2>/dev/null; } \
        | grep -E '^- [0-9-]+ (([^ ]+ )?Ruling: |P[0-9]+ Play: )'
      printf '\nMerge: %s\n\n' "$_fb_sha"
    done
    [ -z "$_fb_nl" ] || printf '## Not landed\n\n%s\n' "$_fb_nl"
    printf 'Gate: %s on %s (studio-test, studio-lint, studio-run --seconds 10)\n' "$FINAL_GATE" "$2"
    [ -z "$FINAL_NOTE" ] || printf '\nFailure: %s\n' "$FINAL_NOTE"
  } > "$1"
}

# final_integration — the integration final step in FINAL_W =
# STATE_ROOT/.claude/worktrees/integration-<slug>, idempotent per step (D5):
# 0 RECORD/final names origin/<Target>'s head and its PR is open: skip.
# 1 add the worktree --detach (else, clean, keep a HEAD that descends from
#   origin/<Target>, or switch to it); merge origin/<default>. A conflict:
#   abort, one final-repair unit (STUDIO_REPAIR=conflict: the worktree is
#   clean at the unmerged head; the unit redoes `git merge --no-edit
#   origin/<default>`, resolves and commits); still unmerged: red, back to
#   origin/<Target>'s head.
# 2 PROGRESS.md at the Docs revision and no `docs(progress): <slug>` subject
#   yet: one progress unit.
# 3 unless RECORD/gate names HEAD: the full gate (RUN_DIR/final-gate.log);
#   red: one final-repair unit (STUDIO_REPAIR=red:<that log>), the gate once
#   more (final-gate-2.log); none when step 1 already ran the step's one
#   final-repair unit (AC9), no second gate when the repair left W dirty.
#   RECORD/gate = `<HEAD> green|red`.
# 4 push HEAD to <Target>. 5 the body; `gh pr edit` the open PR, else `gh pr
#   create --draft` into the default branch; `[red] ` when red.
# 6 RECORD/final = `<head> <url> <color>`.
# setup_note STATUS TEXT — the note for a failed studio-setup (D11/D12): the
# last line of its stderr TEXT (`worktree setup failed — exit <n> — log
# <path>`) with a relative log path put under FINAL_W by parameter expansion
# (a `#` or `&` in FINAL_W is no special case); when TEXT is empty (a signal
# death), a note naming the exit STATUS. Never empty.
setup_note() {
  _sn_l="$(printf '%s\n' "$2" | tail -n 1)"
  case $_sn_l in
    "") printf 'worktree setup failed — exit %s — no output, log unknown\n' "$1" ;;
    *" — log "[!/]*) printf '%s — log %s/%s\n' "${_sn_l%% — log *}" "$FINAL_W" "${_sn_l#* — log }" ;;
    *) printf '%s\n' "$_sn_l" ;;
  esac
}

final_integration() {
  _fi_rep=0
  _fi_b="$MF_TARGET"; _fi_rb="refs/remotes/origin/$MF_TARGET"; _fi_m="origin/$DEFAULT_BRANCH"
  FINAL_W="$STATE_ROOT/.claude/worktrees/integration-$MF_SLUG"; FINAL_GATE=red
  git_retry -C "$START_DIR" fetch -q origin || { FINAL_COLOR=red; final_note "cannot fetch origin"; return 1; }
  _fi_h0="$(git -C "$START_DIR" rev-parse -q --verify "$_fi_rb^{commit}")" \
    || { FINAL_COLOR=red; final_note "no origin/$_fi_b"; return 1; }
  # Step 0.
  if [ -f "$RECORD/final" ]; then
    _fi_rs=""; _fi_ru=""; _fi_rc=""
    read -r _fi_rs _fi_ru _fi_rc < "$RECORD/final"
    if [ "$_fi_rs" = "$_fi_h0" ] && final_pr_open "$_fi_b" && [ "$FP_URL" = "$_fi_ru" ]; then
      FINAL_PR="$_fi_ru"; FINAL_COLOR="${_fi_rc:-red}"; final_note "unchanged since the last final step"
      return 0
    fi
  fi
  # Step 1.
  if [ ! -d "$FINAL_W" ]; then
    git_retry -C "$START_DIR" worktree prune
    mkdir -p "$(dirname "$FINAL_W")" \
      && git_retry -C "$START_DIR" worktree add -q --detach "$FINAL_W" "$_fi_rb" >/dev/null \
      || { FINAL_COLOR=red; final_note "cannot add the worktree $FINAL_W"; return 1; }
  else
    [ -z "$(git -C "$FINAL_W" status --porcelain 2>&1)" ] \
      || { FINAL_COLOR=red; final_note "the worktree $FINAL_W is not clean"; return 1; }
    if ! git -C "$FINAL_W" merge-base --is-ancestor "$_fi_rb" HEAD 2>/dev/null; then
      git_retry -C "$FINAL_W" switch -q --detach "$_fi_rb" \
        || { FINAL_COLOR=red; final_note "cannot switch $FINAL_W to origin/$_fi_b"; return 1; }
    fi
  fi
  if ! git -C "$FINAL_W" merge-base --is-ancestor "$_fi_m" HEAD 2>/dev/null \
     && ! git_retry -C "$FINAL_W" merge -q --no-edit "$_fi_m" > "$RUN_DIR/final-merge.log" 2>&1; then
    git -C "$FINAL_W" merge --abort 2>/dev/null
    _fi_rep=1
    final_unit final-repair "/omega:integration repair $MF_SLUG" "STUDIO_REPAIR=$(sq conflict)"
    if git -C "$FINAL_W" rev-parse -q --verify MERGE_HEAD >/dev/null \
       || ! git -C "$FINAL_W" merge-base --is-ancestor "$_fi_m" HEAD 2>/dev/null; then
      git -C "$FINAL_W" merge --abort 2>/dev/null
      git_retry -C "$FINAL_W" switch -q --discard-changes --detach "$_fi_rb" \
        || { FINAL_COLOR=red; final_note "cannot reset $FINAL_W to origin/$_fi_b"; return 1; }
      FINAL_COLOR=red; final_note "$_fi_m does not merge cleanly"
    fi
  fi
  # D11: the project's worktree setup, once the worktree is in place. A
  # failure is a red final gate (Step 3); Step 2 still runs.
  # Failure is tracked by exit status (_fi_su), never by the note's text.
  final_stopped "the worktree setup" && return 1
  _fi_su=0; _fi_sn=""
  _fi_se="$( cd "$FINAL_W" && sh "$SELF_DIR/studio-setup" 2>&1 >/dev/null )" \
    || { _fi_su=$?; _fi_sn="$(setup_note "$_fi_su" "$_fi_se")"; }
  # Step 2.
  final_stopped "the progress unit" && return 1
  if progress_exists && ! git -C "$FINAL_W" log --format=%s HEAD | grep -qxF "docs(progress): $MF_SLUG"; then
    final_unit progress "/game-dev:execute --progress"
    git -C "$FINAL_W" log --format=%s HEAD | grep -qxF "docs(progress): $MF_SLUG" \
      || final_note "the progress unit made no docs(progress): $MF_SLUG commit"
  fi
  # Step 3.
  final_stopped "the full gate" && return 1
  _fi_h="$(git -C "$FINAL_W" rev-parse HEAD)"
  _fi_gs=""; _fi_gc=""
  [ ! -f "$RECORD/gate" ] || read -r _fi_gs _fi_gc < "$RECORD/gate"
  if [ "$_fi_su" != 0 ]; then
    FINAL_GATE=red; _fi_log="the setup log"; final_note "$_fi_sn"
  elif [ "$_fi_gs" = "$_fi_h" ] && [ -n "$_fi_gc" ]; then
    FINAL_GATE="$_fi_gc"; _fi_log="(recorded)"
  else
    # An interrupted gate (a stop arrived, or studio-gate's own signal exit
    # 129/130/143) is no result: nothing is recorded, so a resume runs it
    # again. Any other exit, an engine crash's 134/139 included, is red.
    _fi_log="$RUN_DIR/final-gate.log"; _fi_int=0
    final_gate "$_fi_log"; _fi_rc=$?
    if [ "$_fi_rc" = 0 ]; then FINAL_GATE=green
    elif [ -e "$STOP_FILE" ] || gate_signalled "$_fi_rc"; then
      FINAL_GATE=red; _fi_int=1; final_note "the full gate was interrupted (exit $_fi_rc): no result recorded"
    else
      FINAL_GATE=red
      if [ "$_fi_rep" = 1 ]; then final_note "the conflict used the step's one final-repair unit"
      elif final_unit final-repair "/omega:integration repair $MF_SLUG" "STUDIO_REPAIR=$(sq "red:$_fi_log")"; then
        _fi_log="$RUN_DIR/final-gate-2.log"
        final_gate "$_fi_log"; _fi_rc=$?
        if [ "$_fi_rc" = 0 ]; then FINAL_GATE=green
        elif [ -e "$STOP_FILE" ] || gate_signalled "$_fi_rc"; then
          _fi_int=1; final_note "the full gate was interrupted (exit $_fi_rc): no result recorded"
        fi
      fi
    fi
    _fi_h="$(git -C "$FINAL_W" rev-parse HEAD)"
    [ "$_fi_int" = 1 ] || printf '%s %s\n' "$_fi_h" "$FINAL_GATE" > "$RECORD/gate"
  fi
  if [ "$FINAL_GATE" != green ]; then
    FINAL_COLOR=red
    [ "$_fi_su" != 0 ] || final_note "the full gate is red (log: $_fi_log)"
  fi
  final_stopped "the push" && return 1
  # Step 4.
  _fi_pushed=1
  git_retry -C "$FINAL_W" push -q origin "HEAD:refs/heads/$_fi_b" \
    || { _fi_pushed=0; FINAL_COLOR=red; final_note "push to $_fi_b failed"; }
  # Step 5.
  _fi_t="$MF_SLUG: $MF_GOAL"; [ "$FINAL_COLOR" = green ] || _fi_t="[red] $_fi_t"
  final_body "$RUN_DIR/final-body.md" "$_fi_h"
  final_pr_open "$_fi_b"
  case $? in
    0) FINAL_PR="$FP_URL"
       ( cd "$START_DIR" && gh pr edit "$FP_NUM" --title "$_fi_t" --body-file "$RUN_DIR/final-body.md" ) >/dev/null 2>&1 \
         || final_note "gh pr edit $FP_NUM failed" ;;
    1) FINAL_PR="$( cd "$START_DIR" && gh pr create --draft --base "$DEFAULT_BRANCH" --head "$_fi_b" \
         --title "$_fi_t" --body-file "$RUN_DIR/final-body.md" 2>/dev/null | tail -n 1 )"
       [ -n "$FINAL_PR" ] || final_note "gh pr create failed" ;;
    *) final_note "gh pr list failed" ;;
  esac
  # Step 6.
  if [ "$_fi_pushed" = 1 ] && [ -n "$FINAL_PR" ]; then
    printf '%s %s %s\n' "$_fi_h" "$FINAL_PR" "$FINAL_COLOR" > "$RECORD/final"
  fi
}

# progress_direct — direct mode's one PROGRESS entry (D13): the branch
# progress/<slug> from origin/<default> in STATE_ROOT/.claude/worktrees/
# progress-<slug> (an existing branch is reused), one progress unit there
# (skipped when HEAD already has the `docs(progress): <slug>` commit), push,
# a ready PR into the default branch (reused when open), then land_once's
# direct steps 0-4 with the id `progress`, no repair. A PR already MERGED is
# landed. A refusal leaves the PR open and named in FINAL_NOTE.
progress_direct() {
  _pd_b="progress/$MF_SLUG"
  FINAL_W="$STATE_ROOT/.claude/worktrees/progress-$MF_SLUG"
  if pr_view "$_pd_b" && [ "$PR_STATE" = MERGED ]; then
    FINAL_PR="#$PR_NUM"; final_note "progress landed ${PR_OID:-}"; return 0
  fi
  git_retry -C "$START_DIR" fetch -q origin || { FINAL_COLOR=red; final_note "cannot fetch origin"; return 1; }
  if [ ! -d "$FINAL_W" ]; then
    git_retry -C "$START_DIR" worktree prune
    mkdir -p "$(dirname "$FINAL_W")" || { FINAL_COLOR=red; final_note "cannot create $(dirname "$FINAL_W")"; return 1; }
    if git -C "$START_DIR" rev-parse -q --verify "refs/heads/$_pd_b" >/dev/null; then
      git_retry -C "$START_DIR" worktree add -q "$FINAL_W" "$_pd_b" >/dev/null
    else
      git_retry -C "$START_DIR" worktree add -q --no-track -b "$_pd_b" "$FINAL_W" "origin/$DEFAULT_BRANCH" >/dev/null
    fi || { FINAL_COLOR=red; final_note "cannot add the worktree $FINAL_W"; return 1; }
  else
    [ -z "$(git -C "$FINAL_W" status --porcelain 2>&1)" ] \
      || { FINAL_COLOR=red; final_note "the worktree $FINAL_W is not clean"; return 1; }
  fi
  # D12: the project's worktree setup; a failure is a red final, before any unit.
  _pd_se="$( cd "$FINAL_W" && sh "$SELF_DIR/studio-setup" 2>&1 >/dev/null )" \
    || { _pd_su=$?; FINAL_COLOR=red; final_note "$(setup_note "$_pd_su" "$_pd_se")"; return 1; }
  if ! git -C "$FINAL_W" log --format=%s HEAD | grep -qxF "docs(progress): $MF_SLUG"; then
    final_stopped "the progress unit" && return 1
    final_unit progress "/game-dev:execute --progress"
    git -C "$FINAL_W" log --format=%s HEAD | grep -qxF "docs(progress): $MF_SLUG" \
      || { FINAL_COLOR=red; final_note "the progress unit made no docs(progress): $MF_SLUG commit"; return 1; }
  fi
  final_stopped "the progress landing" && return 1
  git_retry -C "$FINAL_W" push -q origin "HEAD:refs/heads/$_pd_b" \
    || { FINAL_COLOR=red; final_note "push to $_pd_b failed"; return 1; }
  final_pr_open "$_pd_b"
  case $? in
    0) FINAL_PR="$FP_URL" ;;
    1) FINAL_PR="$( cd "$START_DIR" && gh pr create --base "$DEFAULT_BRANCH" --head "$_pd_b" \
         --title "docs(progress): $MF_SLUG" --body "The run's PROGRESS entry ($MF_SLUG)." 2>/dev/null | tail -n 1 )"
       [ -n "$FINAL_PR" ] || { FINAL_COLOR=red; final_note "gh pr create for $_pd_b failed"; return 1; } ;;
    *) FINAL_COLOR=red; final_note "gh pr list failed"; return 1 ;;
  esac
  LAND_DIR="$FINAL_W"; land_once progress "$_pd_b"; _pd_st=$?; LAND_DIR=""
  if [ "$_pd_st" = 0 ]; then final_note "progress landed $LAND_SHA"; return 0; fi
  case "$_pd_st" in
    3) _pd_why="${LAND_REPAIR%%:*}" ;;
    *) _pd_why="${LAND_WHY:-land_once returned $_pd_st}" ;;
  esac
  FINAL_COLOR=red; final_note "progress PR $FINAL_PR left open: landing failed ($_pd_why)"
  return 1
}

# final_step — the run's final step: FINAL_PR, FINAL_COLOR, FINAL_NOTE.
final_step() {
  FINAL_PR=""; FINAL_COLOR=green; FINAL_NOTE=""; FINAL_N=0
  unset STUDIO_STORY   # the final units are the run's, never a story's
  if [ "$MF_MODE" = direct ]; then
    progress_exists || { FINAL_COLOR=""; return 0; }
    progress_direct
  else
    final_integration
  fi
}

# run_paths SLUG — a manifest run's own lock and stop flag (AC4, D5):
# .studio/runs/SLUG/lock and .studio/runs/SLUG/stop. SLUG is mf_check's.
run_paths() {
  LOCK="$STATE_ROOT/.studio/runs/$1/lock"; STOP_FILE="$STATE_ROOT/.studio/runs/$1/stop"; RUN_SLUG="$1"
}
# run_populate — acquire_run_lock's step between take_lock and the re-check
# (D9): the run dir's claims, stories and lanes dirs, and its own copies of
# the manifest, rows and chains, so a later start's re-check sees them.
run_populate() {
  mkdir -p "$RUN_DIR/claims" "$RUN_DIR/stories" "$RUN_DIR/lanes" \
    && cp "$MF" "$RUN_DIR/manifest.md" && cp "$MF_ROWS" "$RUN_DIR/rows.tsv" && cp "$CHAINS" "$RUN_DIR/chains"
}
# lock_recheck — the manifest run's re-check under runs.mutex (D8): a live
# single-plan run (any lock but this one) refuses this start with today's
# text, then the live runs' slug, ids and branches (mf_conflicts 1); either
# sets RECHECK_WHY.
lock_recheck() {
  _lc="$(runs_live "$STATE_ROOT" | awk -F'\t' -v me="$LOCK" '$7 != me && $3 == "single"' | head -n 1)"
  if [ -n "$_lc" ]; then
    RECHECK_WHY="a run is live (pid $(printf '%s\n' "$_lc" | cut -f4)) — $(sq "$SELF_ABS") status"
    return 1
  fi
  _rc="$(mf_conflicts 1)"
  [ -n "$_rc" ] || return 0
  RECHECK_WHY="lost the start race: $(printf '%s\n' "$_rc" | head -n 1)"
  return 1
}

# lanes_run — the run path, once the manifest preflight passed.
lanes_run() {
  lanes_reap_stale || exit 2
  lanes_reap_old || exit 2
  acquire_run_lock
  printf '%s\n' "${MF#"$START_DIR"/}" > "$RUN_DIR/manifest.path"   # the report's resume command
  MF_ROWS="$RUN_DIR/rows.tsv"; CHAINS="$RUN_DIR/chains"
  rm -rf "$MF_TMP"; MF_TMP=""
  RECORD="$STATE_ROOT/.studio/runs/$MF_SLUG"
  # the record keeps the run's rows: check-id's rule 3 (#56 D2)
  mkdir -p "$RECORD" && touch "$RECORD/landed.tsv" && cp "$MF_ROWS" "$RECORD/rows.tsv" || { rm -f "$LOCK"; say "cannot create $RECORD"; exit 2; }
  for _id in $(cut -f1 "$MF_ROWS" | awk '!seen[$0]++'); do story_write "$_id" queued; done
  lanes_resume
  LANES_LIVE=1; LANE_PIDS=""
  trap '[ -e "$STOP_FILE" ] || : > "$STOP_FILE"' INT TERM
  trap 'HUP_REQ=1; exit 129' HUP
  run_setup   # its run_excludes keeps the record (.studio/runs/) and the final step's worktrees out of git
  RUNNER_PID=$$
  _nch="$(wc -l < "$CHAINS" | tr -d ' ')"
  _L="$_nch"
  [ "$MAX_LANES" -eq 0 ] || [ "$MAX_LANES" -ge "$_nch" ] || _L="$MAX_LANES"
  run_event run_started "mode=$MF_MODE" "max_lanes:=$_L" "hold_minutes:=$HOLD_MINUTES"
  for _id in $(awk -F'\t' '!seen[$1]++ { print $1 }' "$MF_ROWS"); do
    run_event story_listed "story=$_id" "chain:=$(chain_of "$_id")" "depends[]=$(row_field "$_id" deps)"
  done
  EV_ON=1
  for _id in $(awk -F'\t' '!seen[$1]++ { print $1 }' "$MF_ROWS"); do state_event "$_id" "$(story_get "$_id")"; done
  _k=1
  while [ "$_k" -le "$_L" ]; do
    ( lane_main "$_k" ) &
    LANE_PIDS="$LANE_PIDS $!"
    _k=$((_k + 1))
  done
  lanes_wait_all
  lanes_sweep
  # The final step: only when no stop was requested and a story landed (AC9).
  FINAL_RAN=0; FINAL_RC=1
  if [ ! -e "$STOP_FILE" ] && any_landed; then FINAL_RAN=1; final_step; FINAL_RC=$?; fi
  lanes_finish "$(lanes_ending)"
}

# lanes_start [--dry-run | --check] MANIFEST — manifest mode's start, after
# studio-overnight's preflight (which deferred its exit to here). --check
# (detach's foreground step): the manifest checks and the setup preflight;
# prints the checked commit only.
lanes_start() {
  _ls_dry=0; _ls_chk=0; _ls_mf=""
  for _a in "$@"; do
    case "$_a" in --dry-run) _ls_dry=1 ;; --check) _ls_chk=1 ;; *) _ls_mf="$_a" ;; esac
  done
  MF_TMP="$STATE_ROOT/.studio/tmp.$$"
  mkdir -p "$MF_TMP" || { say "cannot create $MF_TMP"; exit 2; }
  trap 'lanes_on_exit $?' EXIT
  MF_ROWS="$MF_TMP/rows.tsv"; CHAINS="$MF_TMP/chains"
  if mf_load "$_ls_mf"; then mf_check; fi
  [ "$FAILED" -eq 0 ] || exit 2
  run_paths "$MF_SLUG"
  build_chains
  if [ "$_ls_chk" -eq 1 ]; then
    setup_preflight "$MF_TARGET"
    printf '%s\n' "$SP_SHA"
    exit 0
  fi
  RUN_DIR="$REPORTS/overnight-$MF_SLUG-$(date +%Y%m%d-%H%M%S)"
  if [ "$_ls_dry" -eq 1 ]; then
    setup_preflight_note "$MF_TARGET"
    lanes_dry_run
    exit 0
  fi
  setup_preflight "$MF_TARGET"
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

# ln_has FILE TEXT — FILE has a ledger line whose text after `- <date> ` is
# exactly TEXT (#56 R4: `Decisions swept S10` is not `Decisions swept S1`,
# and `plan approved <plan>.old` does not approve <plan>).
ln_has() { sed -n 's/^- [0-9-]* //p' "$1" 2>/dev/null | grep -qxF -- "$2"; }

# lanes_next MANIFEST — classify each row (brainstorm | plan | planned) from
# files and ledger lines alone and print one line per row, then the one next
# command. Pure read: no preflight, no studio state written.
lanes_next() {
  MF_ROWS="$(mktemp "${TMPDIR:-/tmp}/lanes-next.XXXXXX")" || exit 2
  trap 'rm -f "$MF_ROWS"' EXIT
  mf_load "$1" || exit 2
  _ln_db="$(ids_default_branch)" || { say "origin/HEAD is not set — run: git remote set-head origin --auto"; exit 2; }
  _ln_bs=""; _ln_pl=""
  while IFS="$(printf '\t')" read -r _ln_id _ln_b _ln_t _ln_spec _ln_plan _ln_d; do
    [ -n "$_ln_id" ] || continue
    # #56 R3: a story id used before in this project is refused before classification.
    if ids_ok "$_ln_id"; then
      ids_check "$_ln_id" "$_ln_t" "$MF_SLUG" "${_ln_plan:--}" "$_ln_db" "$MF_ROWS" say < /dev/null || exit 2
    fi
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
      if [ -f "$_ln_led" ] && ln_has "$_ln_led" "spec approved $_ln_spec"; then
        _ln_class=plan
        if [ -n "$_ln_plan" ] && ln_has "$_ln_led" "plan approved $_ln_plan" \
           && ln_has "$_ln_led" "Decisions swept $_ln_id"; then
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
  if [ -n "$_ln_bs" ]; then echo "next: /game-dev:brainstorm $MF_SLUG/$_ln_bs"
  elif [ -n "$_ln_pl" ]; then echo "next: /game-dev:plan $MF_SLUG/$_ln_pl"
  else echo "next: /omega:autopilot $MF_SLUG"; fi
  rm -f "$MF_ROWS"
}
