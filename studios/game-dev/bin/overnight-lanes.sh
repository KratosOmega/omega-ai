#!/bin/sh
# overnight-lanes.sh — studio-overnight's manifest mode (D18): the run
# manifest, dependency chains, the manifest preflight and the dry run.
# Sourced by studio-overnight after its own helpers (say, sq, refuse, state,
# cfg*, deny_rules, model_for, label_for, with_launch_args, print_launch) are
# defined and its preflight has run; never run on its own. Reads studio state
# and the manifest; never writes either.
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

# lanes_start [--dry-run] MANIFEST — manifest mode's start, after
# studio-overnight's preflight (which deferred its exit to here).
lanes_start() {
  _ls_dry=0; _ls_mf=""
  for _a in "$@"; do
    case "$_a" in --dry-run) _ls_dry=1 ;; *) _ls_mf="$_a" ;; esac
  done
  MF_TMP="$STATE_ROOT/.studio/tmp.$$"
  mkdir -p "$MF_TMP" || { say "cannot create $MF_TMP"; exit 2; }
  trap 'rm -rf "$MF_TMP"' EXIT
  MF_ROWS="$MF_TMP/rows.tsv"; CHAINS="$MF_TMP/chains"
  if mf_load "$_ls_mf"; then mf_check; fi
  [ "$FAILED" -eq 0 ] || exit 2
  build_chains
  RUN_DIR="$REPORTS/overnight-$MF_SLUG-$(date +%Y%m%d-%H%M%S)"
  if [ "$_ls_dry" -eq 1 ]; then
    lanes_dry_run
    exit 0
  fi
  say "manifest runs are not available yet: use start --dry-run <manifest>"
  exit 2
}
