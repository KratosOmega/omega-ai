#!/bin/sh
# overnight-cleanup.sh — a run whose work is confirmed merged cleans up after
# itself (docs/game-dev/plans/2026-10-27-run-cleanup.md). Sourced by
# studio-overnight after overnight-runs.sh (runs_live, runs_mf_header,
# runs_worktree_of, mx_reap) and overnight-tools.sh (tools_run). Runner shell
# code only: no unit ever runs it (units may still not delete a remote
# branch, overnight-deny.txt).
#
# cleanup_record ROOT SLUG [--dry-run] [--self] [--due] checks the record
# .studio/runs/SLUG against origin, then, when confirmed, runs each step that
# .studio/config.json's "cleanup" object leaves on: record (landed.tsv
# backfilled, done), remote_branches, worktrees (and local branches), jira,
# multica, stories. Every step is best effort and idempotent; a rerun finishes
# what is left. Files in the record: cleaned (nothing left: sweeps skip it),
# cleanup.state (sub-steps done, so nothing is posted twice), cleanup.log
# (every attempt), cleanup.tried (epoch of the last attempt), cleanup.mx (the
# mutex). --dry-run fetches (a read) and prints `would:` lines; it writes
# nothing else.
# Byte collation: under a UTF-8 locale macOS sh matches [a-z] by collation (A-Y too).
unset LC_ALL; LC_COLLATE=C
CL_TAB="$(printf '\t')"

# cl_sq WORD — WORD as one single-quoted shell word.
cl_sq() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
# cl_exec ARGV… — ARGV through tools_run, capped at STUDIO_OVERNIGHT_TOOLS_SECONDS
# (cleanup_record sets it to cleanup.timeout_seconds). tools_run splits its
# arguments on blanks, so ARGV goes in a script of quoted words. Sets TOOLS_RC
# (124 capped, 127 not found) and TOOLS_OUT.
cl_exec() {
  _ce_f="$(mktemp "${TMPDIR:-/tmp}/cl-exec.XXXXXX")" || { TOOLS_RC=125; TOOLS_OUT="mktemp failed"; return 0; }
  { printf 'exec'; for _ce_a in "$@"; do printf ' %s' "$(cl_sq "$_ce_a")"; done; printf '\n'; } > "$_ce_f"
  tools_run sh "$_ce_f"
  rm -f "$_ce_f"
}
# cl_why — the last cl_exec's failure in a few words.
cl_why() {
  case "$TOOLS_RC" in
    124) printf 'timed out after %ss\n' "$STUDIO_OVERNIGHT_TOOLS_SECONDS" ;;
    127) echo "not found" ;;
    *) printf 'exit %s: %s\n' "$TOOLS_RC" "$(printf '%s\n' "$TOOLS_OUT" | grep . | tail -n 1 | cut -c1-160)" ;;
  esac
}

# cl_cfg KEY DEFAULT — KEY of the "cleanup" object in CL_CONFIG (a quoted
# string, or a bare number or word); DEFAULT when absent.
cl_cfg() {
  _cc_v=""
  [ ! -f "$CL_CONFIG" ] || _cc_v="$(awk -v k="$1" '
    { s = s $0 " " }
    END {
      if (!match(s, /"cleanup"[ \t]*:[ \t]*\{[^}]*\}/)) exit
      o = substr(s, RSTART, RLENGTH)
      if (!match(o, "\"" k "\"[ \t]*:[ \t]*(\"[^\"]*\"|[^,} \t]+)")) exit
      v = substr(o, RSTART, RLENGTH); sub(/^"[^"]*"[ \t]*:[ \t]*/, "", v); gsub(/"/, "", v); print v
    }' "$CL_CONFIG")"
  [ -n "$_cc_v" ] || _cc_v="$2"
  printf '%s\n' "$_cc_v"
}
# cl_on STEP — 0 when cleanup.STEP is on (the default); off is a skip line; any
# other value is a left line (the step does not run).
cl_on() {
  _co_v="$(cl_cfg "$1" on)"
  case "$_co_v" in
    on|true) return 0 ;;
    off|false) cl_skip "$1 (cleanup.$1 is off)"; return 1 ;;
    *) cl_left "config cleanup.$1 must be \"on\" or \"off\", got \"$_co_v\" — step not run"; return 1 ;;
  esac
}

# Output: lines in CL_OUT; CL_NLEFT counts what is left.
cl_did() { printf '  %s: %s\n' "$CL_VERB" "$*" >> "$CL_OUT"; }
cl_left() { printf '  left: %s\n' "$*" >> "$CL_OUT"; CL_NLEFT=$((CL_NLEFT + 1)); }
cl_skip() { printf '  skip: %s\n' "$*" >> "$CL_OUT"; }
# cl_append FILE LINE — LINE appended to FILE on a line of its own (a FILE edited by hand may lack its final newline).
cl_append() {
  if [ -s "$1" ] && [ "$(tail -c 1 "$1" | od -An -c | tr -d ' ')" != '\n' ]; then printf '\n' >> "$1"; fi
  printf '%s\n' "$2" >> "$1"
}
# cl_state_has LINE / cl_state_add LINE — cleanup.state, the sub-steps done.
cl_state_has() { grep -qxF -- "$1" "$CL_D/cleanup.state" 2>/dev/null; }
cl_state_add() { [ "$CL_DRY" = 1 ] || printf '%s\n' "$1" >> "$CL_D/cleanup.state"; }

# cl_load ROOT REC — the record's variables: CL_D, CL_SLUG (REC without an
# archive suffix .YYYYMMDDTHHMMSSZ; CL_ARCH 1 when it had one), CL_RUN (the
# newest report dir of the slug whose rows are all the record's; CL_T/rundirs
# lists every such dir, the runs of this record), CL_MODE,
# CL_TARGET, CL_DOCS, CL_DEF (origin/HEAD), CL_BASE (direct: the Target;
# integration: the default branch, the final PR's base). 1 with CL_WHY.
cl_load() {
  CL_ROOT="$1"; CL_D="$1/.studio/runs/$2"; CL_CONFIG="$1/.studio/config.json"
  CL_SLUG="$(printf '%s\n' "$2" | sed 's/\.[0-9]\{8\}T[0-9]\{6\}Z$//')"
  CL_ARCH=0; [ "$CL_SLUG" = "$2" ] || CL_ARCH=1
  [ -s "$CL_D/rows.tsv" ] || { CL_WHY="no rows.tsv in $CL_D"; return 1; }
  CL_RUN=""; : > "$CL_T/rundirs"
  _cl_c="$(ls -d "$1/.studio/reports/overnight-$CL_SLUG-"[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9] 2>/dev/null | sort -r)"
  while IFS= read -r _cl_r; do
    [ -n "$_cl_r" ] && [ -f "$_cl_r/manifest.md" ] && [ -f "$_cl_r/rows.tsv" ] || continue
    if awk -F'\t' -v r="$CL_D/rows.tsv" 'BEGIN { while ((getline x < r) > 0) { split(x, a, "\t"); k[a[1]] = 1 } }
         $1 != "" && !($1 in k) { bad = 1 } END { exit bad }' "$_cl_r/rows.tsv"; then
      [ -n "$CL_RUN" ] || CL_RUN="$_cl_r"; printf '%s\n' "$_cl_r" >> "$CL_T/rundirs"
    fi
  done <<EOF
$_cl_c
EOF
  [ -n "$CL_RUN" ] || { CL_WHY="no run directory of $CL_SLUG under .studio/reports lists its stories"; return 1; }
  CL_MODE="$(runs_mf_header "$CL_RUN/manifest.md" Mode)"; CL_TARGET="$(runs_mf_header "$CL_RUN/manifest.md" Target)"
  CL_DOCS="$(runs_mf_header "$CL_RUN/manifest.md" Docs)"
  CL_DEF="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"; CL_DEF="${CL_DEF#origin/}"
  [ -n "$CL_DEF" ] || { CL_WHY="origin/HEAD is not set (git remote set-head origin --auto)"; return 1; }
  [ -n "$CL_TARGET" ] || { CL_WHY="the manifest names no Target"; return 1; }
  case "$CL_MODE" in
    direct) CL_BASE="$CL_TARGET" ;;
    integration) CL_BASE="$CL_DEF" ;;
    *) CL_WHY="the manifest's Mode is neither direct nor integration"; return 1 ;;
  esac
}

# cl_in SHA BRANCH — SHA is a commit and an ancestor of origin/BRANCH.
cl_in() {
  case "$1" in ''|-|*[!0-9a-f]*) return 1 ;; esac
  git merge-base --is-ancestor "$1" "refs/remotes/origin/$2" 2>/dev/null
}
# cl_prs BRANCH — BRANCH's PRs (any state) in CL_PRS, a file of TSV lines:
# number state head merge base url (merge `-` when none). One gh call per
# branch per attempt. 1 with CL_WHY when gh fails.
cl_prs() {
  CL_PRS="$CL_T/prs.$(printf '%s' "$1" | tr '/' '%')"
  [ ! -f "$CL_PRS" ] || return 0
  cl_exec gh pr list --head "$1" --state all --limit 50 --json number,state,headRefOid,mergeCommit,baseRefName,url \
    -q '.[] | [(.number|tostring), .state, .headRefOid, (.mergeCommit.oid // "-"), .baseRefName, .url] | @tsv'
  [ "$TOOLS_RC" = 0 ] || { CL_WHY="gh pr list --head $1: $(cl_why)"; CL_PRS=""; return 1; }
  printf '%s\n' "$TOOLS_OUT" | awk -F'\t' 'NF == 6 && $1 ~ /^[0-9]+$/' > "$CL_PRS"
}
# cl_merged_pr BRANCH BASE [HEAD] — the first MERGED PR of BRANCH into BASE
# whose merge commit is in origin/BASE (and whose head is HEAD, when given):
# PR_URL, PR_HEAD, PR_MERGE. 1 none, 2 gh failed (CL_WHY).
cl_merged_pr() {
  cl_prs "$1" || return 2
  while IFS="$CL_TAB" read -r _mp_n _mp_s _mp_h _mp_m _mp_b _mp_u; do
    [ "$_mp_s" = MERGED ] && [ "$_mp_b" = "$2" ] || continue
    [ -z "${3:-}" ] || [ "$_mp_h" = "$3" ] || continue
    cl_in "$_mp_m" "$2" || continue
    PR_URL="$_mp_u"; PR_HEAD="$_mp_h"; PR_MERGE="$_mp_m"; return 0
  done < "$CL_PRS"
  return 1
}
# cl_row_pr BRANCH TARGET — cl_merged_pr for a row landed by hand: the PR's
# head is origin/BRANCH's tip while that branch exists (a reused branch name's
# old PR does not count), and its merge commit is not in the run's Docs
# revision (it merged before the run began).
cl_row_pr() {
  _rp_t="$(git rev-parse -q --verify "refs/remotes/origin/$1^{commit}" 2>/dev/null)"
  cl_merged_pr "$1" "$2" $_rp_t; _rp_rc=$?
  [ "$_rp_rc" = 0 ] || return "$_rp_rc"
  if [ -n "$CL_DOCS" ] && git cat-file -e "$CL_DOCS^{commit}" 2>/dev/null \
     && git merge-base --is-ancestor "$PR_MERGE" "$CL_DOCS" 2>/dev/null; then return 1; fi
  return 0
}
# cl_open_pr BRANCH — the url of an OPEN PR of BRANCH (gh already asked by cl_prs).
cl_open_pr() { awk -F'\t' '$2 == "OPEN" { print $6; exit }' "$CL_PRS"; }
# cl_tip_in TIP BRANCH — TIP is in origin/CL_BASE: an ancestor of it, an
# ancestor of the merged final head (integration), or the head of a merged PR
# of BRANCH into CL_BASE (a squash). 2 when gh failed (CL_WHY).
cl_tip_in() {
  cl_in "$1" "$CL_BASE" && return 0
  [ -z "${CL_FH:-}" ] || ! git merge-base --is-ancestor "$1" "$CL_FH" 2>/dev/null || return 0
  cl_merged_pr "$2" "$CL_BASE" "$1"
}


# cl_confirm — the record's work is in origin, against a fresh fetch. Each
# row: direct, its landed.tsv sha is an ancestor of origin/<its target>, else a
# merged PR of its branch into that target has its merge commit there (the
# row is then backfilled: CL_T/back); integration, its landed sha is an
# ancestor of RECORD/final's head. The final step: integration, that PR is
# MERGED with that head and its merge commit is in origin/<default>
# (runs_settle's rule); direct, when PROGRESS.md exists at Docs, a
# `docs(progress): <slug>` commit is on origin/<Target> after Docs, a row's landed
# commit changed PROGRESS.md, or the progress PR is merged. Writes CL_T/rows (id branch ticket sha target url) and CL_FINAL (the
# head line's tail). 1 with CL_WHY.
cl_confirm() {
  if [ "${CL_FETCHED:-0}" != 1 ]; then   # cleanup_sweep fetches once for all its records
    cl_exec git fetch -q --prune origin
    [ "$TOOLS_RC" = 0 ] || { CL_WHY="cannot fetch origin ($(cl_why))"; return 1; }
    [ -z "${CL_FETCH_MARK:-}" ] || : > "$CL_FETCH_MARK"
  fi
  git rev-parse -q --verify "refs/remotes/origin/$CL_BASE" >/dev/null || { CL_WHY="no origin/$CL_BASE"; return 1; }
  CL_FH=""; CL_FURL=""; CL_FINAL=""
  if [ "$CL_MODE" = integration ]; then
    [ ! -f "$CL_D/final" ] || read -r CL_FH CL_FURL _ < "$CL_D/final"
    case "$CL_FURL" in https://*) ;; *) CL_WHY="no final PR"; return 1 ;; esac
    case "$CL_FH" in ''|*[!0-9a-f]*) CL_WHY="no final PR head"; return 1 ;; esac
  fi
  : > "$CL_T/rows"; : > "$CL_T/back"
  awk -F'\t' '$1 != "" && !s[$1]++' "$CL_D/rows.tsv" > "$CL_T/ids"
  while IFS="$CL_TAB" read -r _cf_id _cf_b _cf_t _; do
    _cf_s="$(awk -F'\t' -v id="$_cf_id" '$1 == id { print $3; exit }' "$CL_D/landed.tsv")"
    _cf_tg="$(awk -F'\t' -v id="$_cf_id" '$1 == id { print $2; exit }' "$CL_D/landed.tsv")"
    [ -n "$_cf_tg" ] || _cf_tg="$CL_TARGET"
    _cf_u=-
    if [ "$CL_MODE" = integration ]; then
      case "$_cf_s" in ''|*[!0-9a-f]*) CL_WHY="$_cf_id: no landing in $CL_TARGET"; return 1 ;; esac
      git merge-base --is-ancestor "$_cf_s" "$CL_FH" 2>/dev/null \
        || { CL_WHY="$_cf_id: its landing is not in the final PR's head"; return 1; }
    elif ! cl_in "$_cf_s" "$_cf_tg"; then
      [ -n "$_cf_b" ] || { CL_WHY="$_cf_id: no branch and no landing in $_cf_tg"; return 1; }
      cl_row_pr "$_cf_b" "$_cf_tg"
      case $? in
        0) _cf_s="$PR_MERGE"; _cf_u="$PR_URL"
           printf '%s\t%s\t%s\t%s\n' "$_cf_id" "$_cf_tg" "$_cf_s" "$_cf_u" >> "$CL_T/back" ;;
        2) return 1 ;;
        *) CL_WHY="$_cf_id: $_cf_b is not merged into $_cf_tg"; return 1 ;;
      esac
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$_cf_id" "${_cf_b:--}" "${_cf_t:--}" "$_cf_s" "$_cf_tg" "$_cf_u" >> "$CL_T/rows"
  done < "$CL_T/ids"
  if [ "$CL_MODE" = integration ]; then
    cl_exec gh pr view "$CL_FURL" --json state,headRefOid,mergeCommit
    [ "$TOOLS_RC" = 0 ] || { CL_WHY="cannot read final PR $CL_FURL ($(cl_why))"; return 1; }
    _cf_v="$(printf '%s\n' "$TOOLS_OUT" | tr '\n' ' ')"
    _cf_st="$(printf '%s\n' "$_cf_v" | sed -n 's/.*"state"[[:space:]]*:[[:space:]]*"\([A-Z]*\)".*/\1/p')"
    _cf_h="$(printf '%s\n' "$_cf_v" | sed -n 's/.*"headRefOid"[[:space:]]*:[[:space:]]*"\([0-9a-f]*\)".*/\1/p')"
    _cf_m="$(printf '%s\n' "$_cf_v" | sed -n 's/.*"mergeCommit"[[:space:]]*:[[:space:]]*{[^}]*"oid"[[:space:]]*:[[:space:]]*"\([0-9a-f]*\)".*/\1/p')"
    [ -n "$_cf_st" ] || { CL_WHY="cannot read the state of final PR $CL_FURL"; return 1; }
    [ "$_cf_st" = MERGED ] || { CL_WHY="final PR $CL_FURL is not merged ($_cf_st)"; return 1; }
    [ "$_cf_h" = "$CL_FH" ] || { CL_WHY="final PR $CL_FURL's head is not the run's final head"; return 1; }
    cl_in "$_cf_m" "$CL_BASE" || { CL_WHY="final PR $CL_FURL's merge commit is not in origin/$CL_BASE"; return 1; }
    CL_FINAL="; final PR $CL_FURL merged"
  elif cl_progress_needed; then
    _cf_lr="refs/remotes/origin/$CL_TARGET"
    ! git cat-file -e "$CL_DOCS^{commit}" 2>/dev/null || _cf_lr="$CL_DOCS..$_cf_lr"
    if git log --format=%s "$_cf_lr" 2>/dev/null \
         | awk -v p="docs(progress): $CL_SLUG" '$0 == p || index($0, p " (#") == 1 { f = 1; exit } END { exit !f }'; then
      CL_FINAL="; progress entry on origin/$CL_TARGET"
    elif _cf_p="$(cl_progress_in_rows)" && [ -n "$_cf_p" ]; then
      CL_FINAL="; progress entry in $_cf_p's landing"
    else
      cl_merged_pr "progress/$CL_SLUG" "$CL_TARGET"
      case $? in
        0) CL_FINAL="; progress PR $PR_URL merged" ;;
        2) return 1 ;;
        *) CL_WHY="the progress entry (progress/$CL_SLUG) is not on $CL_TARGET"; return 1 ;;
      esac
    fi
  fi
}
# cl_progress_in_rows — the first row whose landed commit changed
# docs/game-dev/PROGRESS.md (a story's finish writes its own entry, execute §9).
cl_progress_in_rows() {
  while IFS="$CL_TAB" read -r _pr_id _ _ _pr_s _; do
    git rev-parse -q --verify "$_pr_s^1" >/dev/null 2>&1 || continue
    git diff --quiet "$_pr_s^1" "$_pr_s" -- docs/game-dev/PROGRESS.md 2>/dev/null || { printf '%s\n' "$_pr_id"; return 0; }
  done < "$CL_T/rows"
}
# cl_progress_needed — PROGRESS.md exists at the run's Docs revision (or that revision is unknown here).
cl_progress_needed() {
  [ -n "$CL_DOCS" ] && git cat-file -e "$CL_DOCS^{commit}" 2>/dev/null || return 0
  git cat-file -e "$CL_DOCS:docs/game-dev/PROGRESS.md" 2>/dev/null
}

# cl_record — landed.tsv backfilled (CL_T/back), RECORD/done, and the run
# manifest copy's `Status:` header (when it has one) set to done.
cl_record() {
  cl_on record || return 0
  while IFS="$CL_TAB" read -r _rc_id _rc_tg _rc_s _rc_u; do
    if [ "$CL_DRY" = 0 ]; then
      awk -F'\t' -v id="$_rc_id" '$1 == id { f = 1 } END { exit !f }' "$CL_D/landed.tsv" \
        || cl_append "$CL_D/landed.tsv" "$(printf '%s\t%s\t%s\t%s' "$_rc_id" "$_rc_tg" "$_rc_s" "$(date +%s)")"
    fi
    cl_did "landed.tsv: $_rc_id $_rc_s (PR $_rc_u)"
  done < "$CL_T/back"
  if [ ! -f "$CL_D/done" ]; then
    if [ "$CL_DRY" = 1 ]; then cl_did "mark the record done"
    elif : > "$CL_D/done"; then cl_did "record marked done"
    else cl_left "cannot write $CL_D/done"; fi
  fi
  _rc_m="$CL_RUN/manifest.md"; _rc_v="$(runs_mf_header "$_rc_m" Status)"
  if [ -n "$_rc_v" ] && [ "$_rc_v" != done ]; then
    if [ "$CL_DRY" = 1 ]; then cl_did "set the run manifest's Status to done"
    elif sed '1,/^Status:/s/^Status:.*/Status: done/' "$_rc_m" > "$_rc_m.$$" && mv -f "$_rc_m.$$" "$_rc_m"; then
      cl_did "run manifest Status: done"
    else rm -f "$_rc_m.$$"; cl_left "cannot set the Status of $_rc_m"; fi
  fi
}

# cl_owned — the run's own branches, `kind<TAB>branch`: each row's branch
# (story); unless the record is archived (a newer run of the slug may own
# them): progress/<slug> (direct) or the Target (integration, unless it is the
# default branch), then run/<slug> (run).
cl_owned() {
  cut -f2 "$CL_T/rows" | awk -v d="$CL_DEF" -v t="$CL_TARGET" '$1 != "-" && $1 != "" && $1 != d && $1 != t && !s[$1]++ { print "story\t" $1 }'
  [ "$CL_ARCH" = 0 ] || return 0
  if [ "$CL_MODE" = direct ]; then printf 'progress\tprogress/%s\n' "$CL_SLUG"
  elif [ "$CL_TARGET" != "$CL_DEF" ]; then printf 'final\t%s\n' "$CL_TARGET"; fi
  printf 'run\trun/%s\n' "$CL_SLUG"
}
# cl_foreign BRANCH — another run that may still use BRANCH: a live run's, or a
# record not done (archived ones are dead) listing it. Prints its name.
cl_foreign() {
  for _fo_r in "$CL_ROOT"/.studio/runs/*/rows.tsv; do
    _fo_d="${_fo_r%/rows.tsv}"; _fo_n="${_fo_d##*/}"
    [ -f "$_fo_r" ] && [ "$_fo_d" != "$CL_D" ] || continue
    if ! grep -qxF -- "$_fo_n" "$CL_T/live"; then
      [ ! -f "$_fo_d/done" ] || continue
      case "$_fo_n" in *.[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z) continue ;; esac
    fi
    ! cut -f2 "$_fo_r" | grep -qxF -- "$1" || { printf '%s\n' "$_fo_n"; return 0; }
  done
}
# cl_owned_mine — cl_owned without the branches another run may still use (a skip line each).
cl_owned_mine() {
  runs_live "$CL_ROOT" | cut -f2 > "$CL_T/live"
  [ "${CL_SELF:-0}" = 0 ] || grep -vxF -- "$CL_SLUG" "$CL_T/live" > "$CL_T/live.x" 2>/dev/null; [ ! -f "$CL_T/live.x" ] || mv "$CL_T/live.x" "$CL_T/live"
  cl_owned | while IFS="$CL_TAB" read -r _om_k _om_b; do
    _om_f="$(cl_foreign "$_om_b")"
    if [ -n "$_om_f" ]; then cl_skip "branch $_om_b: run $_om_f lists it too — kept"; continue; fi
    printf '%s\t%s\n' "$_om_k" "$_om_b"
  done
}
# cl_remote — each owned branch on origin is deleted when no PR of it is open
# and its tip is in the base (cl_tip_in); run/<slug> is first tagged
# run-archive/<slug>-<tip12> (pushed), and kept when the tag push fails.
cl_remote() {
  cl_on remote_branches || return 0
  while IFS="$CL_TAB" read -r _cr_k _cr_b; do
    _cr_t="$(git rev-parse -q --verify "refs/remotes/origin/$_cr_b^{commit}" 2>/dev/null)" || continue
    cl_prs "$_cr_b" || { cl_left "origin/$_cr_b: $CL_WHY — kept"; continue; }
    _cr_o="$(cl_open_pr)"; [ -z "$_cr_o" ] || { cl_left "origin/$_cr_b: open PR $_cr_o — kept"; continue; }
    if [ "$_cr_k" = run ]; then
      _cr_g="run-archive/$CL_SLUG-$(printf '%.12s' "$_cr_t")"
      if [ "$CL_DRY" = 1 ]; then cl_did "tag origin/$_cr_b as $_cr_g, then delete origin/$_cr_b"; continue; fi
      cl_exec git push -q origin "$_cr_t:refs/tags/$_cr_g"
      [ "$TOOLS_RC" = 0 ] || { cl_left "origin/$_cr_b: cannot push tag $_cr_g ($(cl_why)) — kept"; continue; }
      git tag "$_cr_g" "$_cr_t" 2>/dev/null || :
      cl_did "tagged origin/$_cr_b as $_cr_g"
    else
      cl_tip_in "$_cr_t" "$_cr_b"
      case $? in
        0) ;;
        2) cl_left "origin/$_cr_b: $CL_WHY — kept"; continue ;;
        *) cl_left "origin/$_cr_b: tip $(printf '%.9s' "$_cr_t") is not merged into $CL_BASE — kept"; continue ;;
      esac
      [ "$CL_DRY" = 0 ] || { cl_did "delete origin/$_cr_b"; continue; }
    fi
    cl_exec git push -q origin --delete "$_cr_b"
    if [ "$TOOLS_RC" = 0 ]; then cl_did "deleted origin/$_cr_b"; else cl_left "origin/$_cr_b: cannot delete it ($(cl_why))"; fi
  done < "$CL_T/owned"
}

# cl_dirty WT — WT's changes besides the runner's own untracked .studio/run and .studio/STATE.md.
cl_dirty() { git -C "$1" status --porcelain --untracked-files=all 2>&1 | grep -vxF '?? .studio/run' | grep -vxF '?? .studio/STATE.md'; }
# cl_wt_rm WT — remove the worktree WT unless it is dirty; 1 when it is kept.
# A worktree already handled in this attempt (CL_T/wtdone) is not looked at again.
cl_wt_rm() {
  _wr_s="$(awk -F'\t' -v w="$1" '$1 == w { print $2; exit }' "$CL_T/wtdone" 2>/dev/null)"
  [ -z "$_wr_s" ] || return "$_wr_s"
  cl_wt_rm1 "$1"; _wr_s=$?; printf '%s\t%s\n' "$1" "$_wr_s" >> "$CL_T/wtdone"; return "$_wr_s"
}
cl_wt_rm1() {
  if [ ! -d "$1" ]; then
    [ "$CL_DRY" = 1 ] || git worktree prune 2>/dev/null
    cl_did "prune the missing worktree $1"; return 0
  fi
  [ -z "$(cl_dirty "$1")" ] || { cl_left "worktree $1 has uncommitted changes — kept"; return 1; }
  [ "$CL_DRY" = 0 ] || { cl_did "remove worktree $1"; return 0; }
  _wr_e="$(git worktree remove --force "$1" 2>&1)" || { cl_left "worktree $1: $(printf '%s\n' "$_wr_e" | tail -n 1)"; return 1; }
  cl_did "removed worktree $1"
}
# cl_keep_wt WT — WT is a live run's start dir, or (outside the run's own
# finish) this process's START_DIR: never removed.
cl_keep_wt() {
  [ "${CL_SELF:-0}" = 1 ] || [ -z "${START_DIR:-}" ] || [ "$(cd "$START_DIR" 2>/dev/null && pwd -P)" != "$1" ] || return 0
  runs_live "$CL_ROOT" | cut -f6 | while IFS= read -r _kw; do
    [ -n "$_kw" ] && [ "$(cd "$_kw" 2>/dev/null && pwd -P)" = "$1" ] && exit 0
  done && return 1
  return 0
}
# cl_run_tip_ok TIP — TIP is in run/<slug>'s archive tag or in origin/run/<slug>.
cl_run_tip_ok() {
  for _rt_r in $(git for-each-ref --format='%(objectname)' "refs/tags/run-archive/$CL_SLUG-????????????") \
               $(git rev-parse -q --verify "refs/remotes/origin/run/$CL_SLUG" 2>/dev/null); do
    ! git merge-base --is-ancestor "$1" "$_rt_r" 2>/dev/null || return 0
  done
  return 1
}
# cl_worktrees — each owned local branch whose tip is in the base (run/<slug>:
# in its archive tag or origin/run/<slug>): its worktree removed when clean,
# then the branch deleted; a branch not merged keeps its worktree. Then the
# run's detached worktrees (integration-, progress-, run-<slug>, unless
# archived) whose HEAD is in the base. Never the main checkout, a live run's
# start dir, or START_DIR (but in the run's own finish).
cl_worktrees() {
  cl_on worktrees || return 0
  _cw_main="$(pwd -P)"
  while IFS="$CL_TAB" read -r _cw_k _cw_b; do
    _cw_t="$(git rev-parse -q --verify "refs/heads/$_cw_b^{commit}" 2>/dev/null)" || continue
    if [ "$_cw_k" = run ]; then
      cl_run_tip_ok "$_cw_t" || { cl_left "local branch $_cw_b has commits on no remote — kept"; continue; }
    else
      cl_tip_in "$_cw_t" "$_cw_b"
      case $? in
        0) ;;
        2) cl_left "local branch $_cw_b: $CL_WHY — kept"; continue ;;
        *) cl_left "local branch $_cw_b: tip $(printf '%.9s' "$_cw_t") is not merged into $CL_BASE — kept"; continue ;;
      esac
    fi
    _cw_w="$(runs_worktree_of "$_cw_b")"
    if [ -n "$_cw_w" ]; then
      [ "$_cw_w" != "$_cw_main" ] || { cl_skip "branch $_cw_b is checked out in the main checkout — kept"; continue; }
      ! cl_keep_wt "$_cw_w" || { cl_skip "worktree $_cw_w is a live run's checkout — kept"; continue; }
      cl_wt_rm "$_cw_w" || continue
    fi
    [ "$CL_DRY" = 0 ] || { cl_did "delete local branch $_cw_b"; continue; }
    _cw_e="$(git branch -D "$_cw_b" 2>&1)" && cl_did "deleted local branch $_cw_b" \
      || cl_left "local branch $_cw_b: $(printf '%s\n' "$_cw_e" | tail -n 1)"
  done < "$CL_T/owned"
  [ "$CL_ARCH" = 0 ] || return 0
  git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' > "$CL_T/wtlist"
  for _cw_n in integration progress run; do
    _cw_p="$(cd "$CL_ROOT/.claude/worktrees/$_cw_n-$CL_SLUG" 2>/dev/null && pwd -P)" || continue
    grep -qxF -- "$_cw_p" "$CL_T/wtlist" && [ "$_cw_p" != "$_cw_main" ] || continue
    git -C "$_cw_p" symbolic-ref -q HEAD >/dev/null 2>&1 && continue   # on a branch: the loop above
    ! cl_keep_wt "$_cw_p" || continue
    _cw_h="$(git -C "$_cw_p" rev-parse -q --verify HEAD 2>/dev/null)"
    if cl_in "$_cw_h" "$CL_BASE" || { [ -n "${CL_FH:-}" ] && git merge-base --is-ancestor "$_cw_h" "$CL_FH" 2>/dev/null; } \
       || cl_run_tip_ok "$_cw_h"; then cl_wt_rm "$_cw_p" || :
    else cl_left "worktree $_cw_p: its detached HEAD $(printf '%.9s' "$_cw_h") is not merged — kept"; fi
  done
}

# cl_ticket_shared KEY — why KEY must stay open: other records listing it
# whose row is not done (its record has no done, or no landed.tsv line for
# it). Empty when none.
cl_ticket_shared() {
  for _ts_r in "$CL_ROOT"/.studio/runs/*/rows.tsv; do
    _ts_d="${_ts_r%/rows.tsv}"
    [ -f "$_ts_r" ] && [ "$_ts_d" != "$CL_D" ] || continue
    awk -F'\t' -v k="$1" '$3 == k && !s[$1]++ { print $1 }' "$_ts_r" | while IFS= read -r _ts_id; do
      if [ ! -f "$_ts_d/done" ]; then printf 'also the ticket of %s (run %s, not done)\n' "$_ts_id" "${_ts_d##*/}"
      elif ! awk -F'\t' -v id="$_ts_id" '$1 == id { f = 1 } END { exit !f }' "$_ts_d/landed.tsv" 2>/dev/null; then
        printf 'also the ticket of %s (run %s, not landed)\n' "$_ts_id" "${_ts_d##*/}"
      fi
    done
  done | awk '{ o = o (NR > 1 ? "; " : "") $0 } END { print o }'
}
# cl_jira_body KEY — the comment: each of this run's rows with KEY, its PR and merge sha.
cl_jira_body() {
  if [ "$CL_MODE" = integration ]; then printf 'Merged into %s through the final PR %s of overnight run %s:\n' "$CL_DEF" "$CL_FURL" "$CL_SLUG"
  else printf 'Merged into %s by overnight run %s:\n' "$CL_TARGET" "$CL_SLUG"; fi
  awk -F'\t' -v k="$1" '$3 == k' "$CL_T/rows" | while IFS="$CL_TAB" read -r _jb_id _jb_b _ _jb_s _jb_tg _jb_u; do
    if [ "$_jb_u" = - ] && [ "$_jb_b" != - ] && [ "$CL_MODE" = direct ] && cl_merged_pr "$_jb_b" "$_jb_tg"; then _jb_u="$PR_URL"; fi
    [ "$_jb_u" != - ] || _jb_u="no PR"
    printf -- '- %s: %s, merge %s\n' "$_jb_id" "$_jb_u" "$(printf '%.12s' "$_jb_s")"
  done
}
# cl_jira_cli — the acli to use: cleanup.jira_cli (a path, or a name on PATH), else ~/.local/bin/acli.
cl_jira_cli() {
  _jc="$(cl_cfg jira_cli acli)"
  case "$_jc" in
    */*) [ ! -x "$_jc" ] || printf '%s\n' "$_jc" ;;
    *) command -v "$_jc" 2>/dev/null \
         || { [ "$_jc" != acli ] || [ ! -x "$HOME/.local/bin/acli" ] || printf '%s\n' "$HOME/.local/bin/acli"; } ;;
  esac
}
# cl_jira — each Jira key of the rows (column 3, KEY-<n>) to cleanup.jira_done_status,
# with one comment first, unless shared with a row not done or it has open children.
cl_jira() {
  cut -f3 "$CL_T/rows" | grep -E '^[A-Z][A-Z0-9_]+-[0-9]+$' | awk '!s[$0]++' > "$CL_T/keys"
  [ -s "$CL_T/keys" ] || return 0
  cl_on jira || return 0
  _cj_done="$(cl_cfg jira_done_status Done)"; _cj_a="$(cl_jira_cli)"
  [ -n "$_cj_a" ] || { cl_left "Jira $(tr '\n' ' ' < "$CL_T/keys" | sed 's/ $//'): $(cl_cfg jira_cli acli) not found — not updated"; return 0; }
  while IFS= read -r _cj_k; do
    cl_state_has "jira-done $_cj_k" && continue
    _cj_w="$(cl_ticket_shared "$_cj_k")"; [ -z "$_cj_w" ] || { cl_left "Jira $_cj_k kept open: $_cj_w"; continue; }
    cl_exec "$_cj_a" jira workitem view "$_cj_k" --fields status --json
    if [ "$TOOLS_RC" != 0 ] && printf '%s\n' "$TOOLS_OUT" | grep -qi 'does not exist'; then
      cl_skip "Jira $_cj_k: Jira has no such issue (or no access to it) — not a Jira ticket here"; continue
    fi
    [ "$TOOLS_RC" = 0 ] || { cl_left "Jira $_cj_k: cannot read it ($(cl_why))"; continue; }
    _cj_s="$(printf '%s\n' "$TOOLS_OUT" | awk '{ s = s $0 " " }
      END { i = index(s, "\"status\""); if (!i) exit; s = substr(s, i + 8)
            if (match(s, /"name"[ \t]*:[ \t]*"[^"]*"/)) { v = substr(s, RSTART, RLENGTH); sub(/^"name"[ \t]*:[ \t]*"/, "", v); sub(/"$/, "", v); print v } }')"
    [ -n "$_cj_s" ] || { cl_left "Jira $_cj_k: cannot read its status"; continue; }
    _cj_g="$(printf '%s\n' "$TOOLS_OUT" | awk '{ s = s $0 " " }
      END { i = index(s, "\"statusCategory\""); if (!i) exit; s = substr(s, i + 16)
            if (match(s, /"key"[ \t]*:[ \t]*"[^"]*"/)) { v = substr(s, RSTART, RLENGTH); sub(/^"key"[ \t]*:[ \t]*"/, "", v); sub(/"$/, "", v); print v } }')"
    if [ "$_cj_g" = done ] || [ "$(printf '%s' "$_cj_s" | tr 'A-Z' 'a-z')" = "$(printf '%s' "$_cj_done" | tr 'A-Z' 'a-z')" ]; then
      cl_skip "Jira $_cj_k is already $_cj_s"; cl_state_add "jira-done $_cj_k"; continue
    fi
    cl_exec "$_cj_a" jira workitem search --jql "parent = $_cj_k AND statusCategory != Done" --fields key --json
    [ "$TOOLS_RC" = 0 ] || { cl_left "Jira $_cj_k: cannot list its children ($(cl_why))"; continue; }
    _cj_c="$(printf '%s\n' "$TOOLS_OUT" | grep -o '"key"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/' | tr '\n' ' ' | sed 's/ $//')"
    [ -z "$_cj_c" ] || { cl_left "Jira $_cj_k kept open: open children $_cj_c"; continue; }
    _cj_body="$(cl_jira_body "$_cj_k")"
    if [ "$CL_DRY" = 1 ]; then cl_did "Jira $_cj_k $_cj_s → $_cj_done, comment: $(printf '%s' "$_cj_body" | tr '\n' ' ')"; continue; fi
    if ! cl_state_has "jira-comment $_cj_k"; then
      cl_exec "$_cj_a" jira workitem comment create --key "$_cj_k" --body "$_cj_body"
      [ "$TOOLS_RC" = 0 ] || { cl_left "Jira $_cj_k: comment failed ($(cl_why))"; continue; }
      cl_state_add "jira-comment $_cj_k"
    fi
    cl_exec "$_cj_a" jira workitem transition --key "$_cj_k" --status "$_cj_done" --yes
    [ "$TOOLS_RC" = 0 ] || { cl_left "Jira $_cj_k: transition to $_cj_done failed ($(cl_why))"; continue; }
    cl_state_add "jira-done $_cj_k"; cl_did "Jira $_cj_k $_cj_s → $_cj_done (comment posted)"
  done < "$CL_T/keys"
}

# cl_multica — each row's Multica story issue (the bridge's state files under
# ~/.claude-gamedev/multica/state, retired ones included, whose run dir is
# one of this record's runs: CL_T/rundirs) set to done with `multica issue status <id> done --no-start`. The
# bridge writes its JSON with no final newline: awk 1 ends each file's lines.
cl_multica() {
  _cm_h="$HOME/.claude-gamedev/multica/state"; : > "$CL_T/mirror"
  for _cm_f in "$_cm_h"/*.json "$_cm_h"/retired/*.json; do
    [ -f "$_cm_f" ] || continue
    [ "$(sed -n 's/.*"root": "\([^"]*\)".*/\1/p' "$_cm_f")" = "$CL_ROOT" ] || continue
    _cm_r="$(sed -n 's/.*"run_dir": "\([^"]*\)".*/\1/p' "$_cm_f")"
    grep -qxF -- "$_cm_r" "$CL_T/rundirs" || continue
    sed -n 's/.*"stories": {\([^}]*\)}.*/\1/p' "$_cm_f" | tr ',' '\n' \
      | sed -n 's/^ *"\([^"]*\)": *"\([^"]*\)" *$/\1	\2/p' | awk 1 >> "$CL_T/mirror"
  done
  awk -F'\t' 'NR == FNR { k[$1] = 1; next } ($1 in k) && !s[$2]++ { print $2 }' "$CL_T/rows" "$CL_T/mirror" > "$CL_T/idents"
  [ -s "$CL_T/idents" ] || return 0
  cl_on multica || return 0
  _cm_c="$(cl_cfg multica_cli multica)"; _cm_x="$(command -v "$_cm_c" 2>/dev/null)"
  [ -n "$_cm_x" ] || { cl_left "Multica $(tr '\n' ' ' < "$CL_T/idents" | sed 's/ $//'): $_cm_c not found — not updated"; return 0; }
  while IFS= read -r _cm_i; do
    cl_state_has "multica-done $_cm_i" && continue
    [ "$CL_DRY" = 0 ] || { cl_did "Multica $_cm_i → done"; continue; }
    cl_exec "$_cm_x" issue status "$_cm_i" done --no-start
    if [ "$TOOLS_RC" = 0 ]; then cl_state_add "multica-done $_cm_i"; cl_did "Multica $_cm_i → done"
    else cl_left "Multica $_cm_i: $(cl_why)"; fi
  done < "$CL_T/idents"
}

# cl_open_elsewhere ID — a non-archived record other than this one that lists ID and is not done.
cl_open_elsewhere() {
  for _oe_r in "$CL_ROOT"/.studio/runs/*/rows.tsv; do
    _oe_d="${_oe_r%/rows.tsv}"
    [ -f "$_oe_r" ] && [ "$_oe_d" != "$CL_D" ] && [ ! -f "$_oe_d/done" ] || continue
    case "${_oe_d##*/}" in *.[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z) continue ;; esac
    ! cut -f1 "$_oe_r" | grep -qxF -- "$1" || { printf '%s\n' "${_oe_d##*/}"; return 0; }
  done
}
# cl_stories — each row's .studio/stories/<id>.md gets a `merged` ledger line
# and moves to .studio/stories/done/ (kept while another live record lists it).
cl_stories() {
  cl_on stories || return 0
  while IFS="$CL_TAB" read -r _cs_id _ _ _cs_s _cs_tg _; do
    _cs_f="$CL_ROOT/.studio/stories/$_cs_id.md"; [ -f "$_cs_f" ] || continue
    _cs_o="$(cl_open_elsewhere "$_cs_id")"
    [ -z "$_cs_o" ] || { cl_skip "story pointer $_cs_id kept: run $_cs_o lists it and is not done"; continue; }
    [ "$CL_DRY" = 0 ] || { cl_did "archive story pointer $_cs_id (.studio/stories/done/$_cs_id.md)"; continue; }
    if cl_append "$_cs_f" "- $(date +%Y-%m-%d) merged $_cs_s into $_cs_tg (run $CL_SLUG)" \
       && mkdir -p "$CL_ROOT/.studio/stories/done" && mv -f "$_cs_f" "$CL_ROOT/.studio/stories/done/$_cs_id.md"; then
      cl_did "archived story pointer $_cs_id (.studio/stories/done/$_cs_id.md)"
    else cl_left "story pointer $_cs_id: cannot archive it"; fi
  done < "$CL_T/rows"
}

# cleanup_record ROOT REC [--dry-run] [--self] [--due] — see the header.
# Prints a head line (`run REC: confirmed — …` or `run REC: not confirmed —
# <why>`), the step lines (`  done:`, `  would:`, `  left:`, `  skip:`) and a
# tail line. Returns 0 cleaned (dry run: nothing would be left; or already
# cleaned), 1 not confirmed or something left, 2 no record, 3 skipped (a live
# run without --self, another cleanup holds the record, or not due: --due and
# tried within cleanup.retry_minutes).
cleanup_record() {
  (
    _cr_root="$1"; _cr_rec="$2"; shift 2
    CL_DRY=0; _cr_self=0; _cr_due=0
    for _cr_a in "$@"; do case "$_cr_a" in --dry-run) CL_DRY=1 ;; --self) _cr_self=1 ;; --due) _cr_due=1 ;; esac; done
    cd "$_cr_root" || exit 2
    CL_D="$_cr_root/.studio/runs/$_cr_rec"; CL_CONFIG="$_cr_root/.studio/config.json"
    [ -f "$CL_D/landed.tsv" ] || { printf 'run %s: no record (.studio/runs/%s/landed.tsv)\n' "$_cr_rec" "$_cr_rec"; exit 2; }
    if [ -f "$CL_D/cleaned" ]; then [ "$_cr_due" = 1 ] || printf 'run %s: already cleaned up\n' "$_cr_rec"; exit 0; fi
    if [ "$_cr_due" = 1 ] && [ -f "$CL_D/cleanup.tried" ]; then
      _cr_m="$(cl_cfg retry_minutes 60)"; case "$_cr_m" in ''|*[!0-9]*) _cr_m=60 ;; esac
      _cr_t="$(cat "$CL_D/cleanup.tried" 2>/dev/null)"; case "$_cr_t" in ''|*[!0-9]*) _cr_t=0 ;; esac
      [ $(( $(date +%s) - _cr_t )) -ge $((_cr_m * 60)) ] || exit 3
    fi
    case "$_cr_rec" in *.[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z) ;; *)
      if [ "$_cr_self" = 0 ] && runs_live "$_cr_root" | cut -f2 | grep -qxF -- "$_cr_rec"; then
        printf 'run %s: live — not cleaned up\n' "$_cr_rec"; exit 3
      fi ;;
    esac
    _cr_mx="$CL_D/cleanup.mx"; CL_SELF="$_cr_self"
    if [ "$CL_DRY" = 1 ]; then _cr_mx=""   # a dry run writes nothing, not even the mutex
    elif ! ln -s "$$" "$_cr_mx" 2>/dev/null; then
      _cr_o="$(readlink "$_cr_mx" 2>/dev/null)"
      if [ -n "$_cr_o" ] && ! kill -0 "$_cr_o" 2>/dev/null && mx_reap "$_cr_mx" "$_cr_o" && ln -s "$$" "$_cr_mx" 2>/dev/null; then :
      else printf 'run %s: busy — another cleanup holds it\n' "$_cr_rec"; exit 3; fi
    fi
    CL_T="$(mktemp -d "${TMPDIR:-/tmp}/cleanup.XXXXXX")" || { [ -z "$_cr_mx" ] || rm -f "$_cr_mx"; exit 1; }
    trap '[ -z "$_cr_mx" ] || rm -f "$_cr_mx"; rm -rf "$CL_T"' EXIT
    CL_OUT="$CL_T/out"; : > "$CL_OUT"; CL_NLEFT=0; CL_VERB=done; [ "$CL_DRY" = 0 ] || CL_VERB=would
    STUDIO_OVERNIGHT_TOOLS_SECONDS="$(cl_cfg timeout_seconds 60)"
    case "$STUDIO_OVERNIGHT_TOOLS_SECONDS" in ''|0|*[!0-9]*)
      cl_left "config cleanup.timeout_seconds must be a whole number above 0, got \"$STUDIO_OVERNIGHT_TOOLS_SECONDS\" — using 60"
      STUDIO_OVERNIGHT_TOOLS_SECONDS=60 ;;
    esac
    [ "$CL_DRY" = 1 ] || date +%s > "$CL_D/cleanup.tried"
    if cl_load "$_cr_root" "$_cr_rec" && cl_confirm; then
      _cr_h="run $_cr_rec: confirmed — every story is in origin/$CL_TARGET$CL_FINAL"
      cl_owned_mine > "$CL_T/owned"
      cl_record; cl_remote; cl_worktrees; cl_jira; cl_multica; cl_stories
      if [ "$CL_DRY" = 1 ]; then
        if [ "$CL_NLEFT" = 0 ]; then _cr_z="run $_cr_rec: dry run — nothing would be left"
        else _cr_z="run $_cr_rec: dry run — $CL_NLEFT would be left"; fi
      elif [ "$CL_NLEFT" = 0 ]; then : > "$CL_D/cleaned"; _cr_z="run $_cr_rec: cleaned up"
      else _cr_z="run $_cr_rec: $CL_NLEFT left — rerun: studio-overnight settle $_cr_rec"; fi
      _cr_rc=1; [ "$CL_NLEFT" != 0 ] || _cr_rc=0
    else
      _cr_h="run $_cr_rec: not confirmed — $CL_WHY"; _cr_z=""; _cr_rc=1
    fi
    { printf '%s\n' "$_cr_h"; cat "$CL_OUT"; [ -z "$_cr_z" ] || printf '%s\n' "$_cr_z"; } > "$CL_T/all"
    cat "$CL_T/all"
    [ "$CL_DRY" = 1 ] || { printf '== %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"; cat "$CL_T/all"; } >> "$CL_D/cleanup.log"
    exit "$_cr_rc"
  )
}

# cleanup_sweep ROOT [--dry-run] [--skip SLUG] — cleanup_record --due for
# every record not yet cleaned (but SLUG: the run being started), after one
# fetch for them all; prints only the records that are confirmed (the rest wait).
cleanup_sweep() {
  _sw_root="$1"; shift; _sw_x=""; _sw_k=""
  while [ "$#" -gt 0 ]; do
    case "$1" in --dry-run) _sw_x=--dry-run ;; --skip) _sw_k="${2:-}"; shift ;; esac
    shift
  done
  _sw_l=""
  for _sw_f in "$_sw_root"/.studio/runs/*/landed.tsv; do
    _sw_d="${_sw_f%/landed.tsv}"
    [ -f "$_sw_f" ] && [ ! -f "$_sw_d/cleaned" ] && [ "${_sw_d##*/}" != "$_sw_k" ] || continue
    _sw_l="$_sw_l${_sw_d##*/}
"
  done
  [ -n "$_sw_l" ] || return 0
  # The first record that fetches writes the mark; the rest use that fetch.
  _sw_m="$(mktemp "${TMPDIR:-/tmp}/cleanup-fetch.XXXXXX")" && rm -f "$_sw_m" || _sw_m=""
  printf '%s' "$_sw_l" | while IFS= read -r _sw_s; do
    [ -n "$_sw_s" ] || continue
    _sw_o="$(CL_FETCH_MARK="$_sw_m"; CL_FETCHED=0; [ -z "$_sw_m" ] || [ ! -f "$_sw_m" ] || CL_FETCHED=1
             cleanup_record "$_sw_root" "$_sw_s" $_sw_x --due 2>&1)"
    case "$_sw_o" in *": confirmed — "*) printf '%s\n' "$_sw_o" ;; esac
  done
  [ -z "$_sw_m" ] || rm -f "$_sw_m"
}
