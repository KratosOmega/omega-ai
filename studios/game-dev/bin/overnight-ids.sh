#!/bin/sh
# overnight-ids.sh — story ids (#56): a story id, once used in a project, is
# not handed out again (ledgers are keyed by id and outlive the run).
# check-id's four taken rules (ids_reasons, over ids_index), its suggestion
# (ids_suggest), the report every caller shares (ids_check) and the verb
# (cmd_check_id). Sourced by overnight-lanes.sh, so by every manifest-mode
# path; never run on its own. Reads git refs and files only: it never fetches
# and never writes.
# Byte collation: under a UTF-8 locale macOS sh matches [a-z] by collation (A-Y too).
unset LC_ALL; LC_COLLATE=C
[ -n "${SELF_DIR:-}" ] || { echo "overnight-ids.sh: sourced by studio-overnight" >&2; exit 2; }
IDS_PAT='^[A-Za-z0-9._-]+$'

# ids_lc TEXT — TEXT in lower case: ids compare case-insensitively (a macOS
# checkout treats s1.md and S1.md as one file).
ids_lc() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }
# ids_ok TEXT — TEXT matches the id pattern.
ids_ok() { printf '%s\n' "$1" | grep -Eq "$IDS_PAT"; }
# ids_default_branch — <d> from refs/remotes/origin/HEAD, without origin/; 1 when unset.
ids_default_branch() {
  _idb="$(git -C "$START_DIR" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)" || return 1
  _idb="${_idb#origin/}"; [ -n "$_idb" ] || return 1
  git -C "$START_DIR" rev-parse -q --verify "refs/remotes/origin/$_idb" >/dev/null 2>&1 || return 1
  printf '%s\n' "$_idb"
}
# ids_has FILE ID — FILE's first tab-separated column holds ID, in any case.
ids_has() { [ -f "$1" ] && awk -F'\t' -v w="$(ids_lc "$2")" 'tolower($1) == w { f = 1 } END { exit !f }' "$1"; }
# ids_own TEXT PLAN — the ledger TEXT is this story's: PLAN is known and is the
# path of its last `plan approved` line or of its last `adopted <orig> -> <p>`.
ids_own() {
  case "$2" in ''|-) return 1 ;; esac
  [ "$(printf '%s\n' "$1" | sed -n 's/^- [0-9-]* plan approved //p' | tail -n 1)" = "$2" ] \
    || [ "$(printf '%s\n' "$1" | sed -n 's/^- [0-9-]* adopted .* -> //p' | tail -n 1)" = "$2" ]
}
# ids_detail TEXT — " (plan <p>, shipped <v>)" from the ledger TEXT's last such
# lines; either part alone, or nothing when it has neither.
ids_detail() {
  _idp="$(printf '%s\n' "$1" | sed -n 's/^- [0-9-]* plan approved //p' | tail -n 1)"
  _ids="$(printf '%s\n' "$1" | sed -n 's/^- [0-9-]* shipped //p' | tail -n 1)"
  _idd="${_idp:+plan $_idp}"
  [ -z "$_ids" ] || _idd="${_idd:+$_idd, }shipped $_ids"
  [ -z "$_idd" ] || printf ' (%s)' "$_idd"
}

# ids_index SLUG D — what rules 1-4 read that does not depend on the id, in
# _ix_all, so each id costs one awk (#57: per id, rule 2 listed every
# integration branch and rule 3 read every run record). Built in the calling
# shell and reused while IDS_IX_KEY is this (STATE_ROOT, SLUG, D) and
# _ix_all is set: one mf_check's stories share it (#70). mf_check and cmd_check_id reset the key,
# so each check reads refs and records afresh. Build it outside $( ) (as
# ids_check does): one built in a subshell dies with it. One section per
# header line, in the order ids_reasons answers (D4):
#   #M  `git ls-tree` of origin/D's .studio/ledger/ (rule 1; rule 2's main blobs)
#   #P  <path> TAB <line, lower case>: each line of a plan on origin/D that
#       starts `story: `, any case (rule 4). A name git quotes is left out,
#       as the per-id `git show` of its quoted name found nothing.
#   #I TAB <slug>  `git ls-tree` of another run's integration branch's .studio/ledger/ (rule 2)
#   #R  <row|landed> TAB <id, lower case> TAB <branch> TAB <reason>: each line
#       of another run's record, in glob order (rule 3; a record without
#       rows.tsv: its newest report's rows, D2)
ids_index() {
  [ "${IDS_IX_KEY:-}" != "$STATE_ROOT|$1|$2" ] || [ -z "${_ix_all+x}" ] || return 0
  _ix_sl="$1"; _ix_db="$2"; _ix_ref="refs/remotes/origin/$2"
  _ix_all="$(
    echo '#M'; git -C "$START_DIR" ls-tree "$_ix_ref" -- .studio/ledger/ 2>/dev/null
    # -z: names unquoted, NUL (made \001) after the name; the -l list, quoted
    # as the per-id `git grep -l` gave them, says which names were usable.
    echo '#P'
    { git -C "$START_DIR" -c color.ui=never grep -l -i -E -e '^story: ' "$_ix_ref" -- docs/game-dev/plans 2>/dev/null
      echo
      git -C "$START_DIR" -c color.ui=never grep -z -a -i -E -e '^story: ' "$_ix_ref" -- docs/game-dev/plans 2>/dev/null \
        | tr '\000' '\001'
    } | awk -v p="$_ix_ref:" '
      !z { if ($0 == "") z = 1; else ok[$0] = 1; next }
      { i = index($0, "\001"); n = substr($0, 1, i - 1)
        if (i && (n in ok)) print substr(n, length(p) + 1) "\t" tolower(substr($0, i + 1)) }'
    for _ix_r in $(git -C "$START_DIR" for-each-ref --format='%(refname)' refs/remotes/origin/integration/ 2>/dev/null); do
      _ix_s="${_ix_r#refs/remotes/origin/integration/}"
      [ "$_ix_s" != "$_ix_sl" ] || continue
      printf '#I\t%s\n' "$_ix_s"; git -C "$START_DIR" ls-tree "$_ix_r" -- .studio/ledger/ 2>/dev/null
    done
    echo '#R'
    # The files of rule 3, in glob order, as kind, file and reason lines (the
    # name of a record is a one-line slug) on the stdin of one awk: an argv
    # would grow with every record (archived ones are never pruned), and past
    # ARG_MAX the exec fails, which would leave every record-held id looking
    # free. (No apostrophe here: bash 3.2 misreads one in a comment in $( ).)
    for _ix_d in "$STATE_ROOT"/.studio/runs/*/; do
      [ -d "$_ix_d" ] || continue
      _ix_d="${_ix_d%/}"; _ix_n="${_ix_d##*/}"
      [ "$_ix_n" != "$_ix_sl" ] || continue
      _ix_b="${_ix_n%.[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z}"
      _ix_y="run $_ix_b (record .studio/runs/$_ix_n) lists it"
      if [ -f "$_ix_d/rows.tsv" ]; then printf 'row\n%s\n%s\n' "$_ix_d/rows.tsv" "$_ix_y"
      elif [ "$_ix_b" != "$_ix_sl" ] && _ix_rw="$(runs_rows "$STATE_ROOT" "$_ix_b")"; then
        printf 'row\n%s\n%s\n' "$_ix_rw" "$_ix_y"
      fi
      [ ! -f "$_ix_d/landed.tsv" ] || printf 'landed\n%s\n%s\n' "$_ix_d/landed.tsv" "$_ix_y"
    done | awk '{ k = $0; getline fl; getline y
        while ((getline l < fl) > 0) {
          split(l, f, "\t"); print k "\t" tolower(f[1]) "\t" f[2] "\t" y }
        close(fl) }'
  )"
  IDS_IX_KEY="$STATE_ROOT|$_ix_sl|$_ix_db"
}

# ids_reasons ID PLAN SLUG D BRANCH — why ID is taken, one line per reason
# (the text after "is taken: "), in the order rule 1, 4, 2, 3 (D4); nothing
# when free. PLAN is this story's plan ('-' or empty: unknown), SLUG this
# run's slug (may be empty), D the default branch, BRANCH this story's Branch
# ('-', empty or absent: unknown, so no record row is excepted). One awk over
# ids_index prints rule 1's candidate ledgers as L<path> and every other
# reason as =<text>. ID, PLAN and D reach it raw (ENVIRON); BRANCH by -v, as
# the per-record awk compared it.
ids_reasons() {
  ids_index "$3" "$4"
  _ir_ref="refs/remotes/origin/$4"
  printf '%s\n' "$_ix_all" | _ir_ei="$1" _ir_ep="$2" _ir_ed="$4" awk -F'\t' -v br="${5:-}" '
    BEGIN { id = ENVIRON["_ir_ei"]; pl = ENVIRON["_ir_ep"]; d = ENVIRON["_ir_ed"]
            w = tolower(id); lp = ".studio/ledger/" w ".md"; sl = "story: " w }
    /^#/ { x = substr($0, 2, 1); if (x == "I") s = substr($0, 4); next }
    # 1. A ledger on the default branch (the loop below judges whose).
    x == "M" { split($1, a, " "); mo[$2] = a[3]; if (tolower($2) == lp) print "L" $2; next }
    # 4. A plan on the default branch, other than PLAN, with the whole line
    #    `Story: <id>` in any case; once per plan.
    x == "P" { if (NF == 2 && $2 == sl && !($1 in ps)) {
                 ps[$1] = 1; if ($1 "" != pl) print "=origin/" d ":" $1 " says '\''Story: " id "'\''" }
               next }
    # 2. A ledger on the integration branch of another run, unless it is the
    #    blob main has there (those branches are cut from main and inherit
    #    its ledgers; rule 1 judges those). An absent path on main counts as
    #    differing.
    x == "I" { if (tolower($2) == lp) {
                 split($1, a, " ")
                 if (a[3] == "" || a[3] "" != mo[$2] "")
                   print "=origin/integration/" s ":" $2 " belongs to run " s "'\''s integration branch" }
               next }
    # 3. The record of another run: live, stopped, done or archived
    #    <slug>.<ts> (D2, D3), except a row on BRANCH (the same story carried
    #    over, FI1); landed.tsv holds no story branch, so a landed id always
    #    counts. Once per record. Ids compare as strings; the branch as the
    #    per-record awk compared it (field against -v).
    x == "R" { if ($2 "" == w && ($1 == "landed" || br == "" || br == "-" || $3 != br)) {
                 r = substr($0, length($1 $2 $3) + 4); if (!(r in rs)) { rs[r] = 1; print "=" r } } }
  ' | while IFS= read -r _ir_l; do
    case "$_ir_l" in
      L*) # 1. … that is not this story's own.
        _ir_p="${_ir_l#L}"
        _ir_t="$(git -C "$START_DIR" show "$_ir_ref:$_ir_p" 2>/dev/null)"
        ids_own "$_ir_t" "$2" && continue
        [ -n "$3" ] && ids_has "$STATE_ROOT/.studio/runs/$3/landed.tsv" "$1" && continue
        printf 'origin/%s:%s belongs to another story%s\n' "$4" "$_ir_p" "$(ids_detail "$_ir_t")" ;;
      *) printf '%s\n' "${_ir_l#=}" ;;
    esac
  done
}

# ids_suggest ID TICKET SLUG PLAN D ROWS BRANCH — the first candidate that
# matches the id pattern, is not ID, is not a row id in ROWS (any case) and is
# free by ids_reasons: TICKET (when not ID), TICKET-2 … TICKET-9, then
# SLUG-S1 … SLUG-S9. TICKET '-' or empty: none. 1 when no candidate is left.
# The candidates share one index (the caller's, or one built here).
ids_suggest() {
  ids_index "$3" "$5"
  _is_c=""
  case "$2" in ''|-) ;; *)
    _is_c="$2"
    for _is_n in 2 3 4 5 6 7 8 9; do _is_c="$_is_c
$2-$_is_n"; done ;;
  esac
  if [ -n "$3" ]; then
    for _is_n in 1 2 3 4 5 6 7 8 9; do _is_c="$_is_c
$3-S$_is_n"; done
  fi
  _is_o="$(printf '%s\n' "$_is_c" | while IFS= read -r _is_k; do
    [ -n "$_is_k" ] && ids_ok "$_is_k" || continue
    [ "$(ids_lc "$_is_k")" != "$(ids_lc "$1")" ] || continue
    [ -z "$6" ] || ! ids_has "$6" "$_is_k" || continue
    [ -z "$(ids_reasons "$_is_k" "$4" "$3" "$5" "${7:-}" < /dev/null)" ] || continue
    printf '%s\n' "$_is_k"; break
  done)"
  [ -n "$_is_o" ] || return 1
  printf '%s\n' "$_is_o"
}

# ids_check ID TICKET SLUG PLAN D ROWS EMIT BRANCH — 0 when ID is free.
# Taken: EMIT (say or refuse) once per reason, then once with the suggestion;
# 1. The here-document keeps EMIT in this shell, so refuse's FAILED=1 sticks.
# The index is built here, in the caller's shell, so the $( ) below and the
# next story's check reuse it (ids_index).
ids_check() {
  ids_index "$3" "$5"
  _ic_r="$(ids_reasons "$1" "$4" "$3" "$5" "${8:-}" < /dev/null)"
  [ -n "$_ic_r" ] || return 0
  while IFS= read -r _ic_l; do
    "$7" "story id '$1' is taken: $_ic_l"
  done <<EOF_IC
$_ic_r
EOF_IC
  if _ic_s="$(ids_suggest "$1" "$2" "$3" "$4" "$5" "$6" "${8:-}" < /dev/null)"; then
    "$7" "use '$_ic_s' instead"
  else
    "$7" "pick an unused id: the ticket, or <run slug>-S<n>"
  fi
  return 1
}

# cmd_check_id ARGS — `check-id <id> [--plan <path>|-] [--ticket <ticket>|-]
# [--slug <slug>] [--branch <branch>|-]` (R2). Defaults (D6): the row of
# .studio/run's manifest that lists <id> (any case). 0 free · 1 taken · 2 usage.
cmd_check_id() {
  _cc_id=""; _cc_p=""; _cc_t=""; _cc_s=""; _cc_b=""; _cc_hp=0; _cc_ht=0; _cc_hs=0; _cc_hb=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --plan|--ticket|--slug|--branch)
        [ "$#" -ge 2 ] && [ -n "$2" ] || { usage >&2; return 2; }
        case "$1" in
          --plan) _cc_p="$2"; _cc_hp=1 ;;
          --ticket) _cc_t="$2"; _cc_ht=1 ;;
          --branch) _cc_b="$2"; _cc_hb=1 ;;
          *) _cc_s="$2"; _cc_hs=1; [ "$_cc_s" != - ] || { _cc_s=""; _cc_hs=2; } ;;
        esac
        shift 2 ;;
      -*) usage >&2; return 2 ;;
      *) [ -z "$_cc_id" ] || { usage >&2; return 2; }; _cc_id="$1"; shift ;;
    esac
  done
  [ -n "$_cc_id" ] || { usage >&2; return 2; }
  ids_ok "$_cc_id" || { say "check-id: story id '$_cc_id' must match $IDS_PAT"; return 2; }
  [ "$_cc_hs" != 1 ] || ids_ok "$_cc_s" || { say "check-id: slug '$_cc_s' must match $IDS_PAT"; return 2; }
  [ -n "$START_DIR" ] || { say "no studio state here (run from the project checkout)"; return 2; }
  _cc_d="$(ids_default_branch)" || { say "origin/HEAD is not set — run: git remote set-head origin --auto"; return 2; }
  MF_ROWS="$(mktemp "${TMPDIR:-/tmp}/check-id.XXXXXX")" || return 2
  trap 'rm -f "$MF_ROWS"' EXIT
  _cc_m="$(head -n 1 "$START_DIR/.studio/run" 2>/dev/null)"
  case "$_cc_m" in ''|/*) ;; *) _cc_m="$START_DIR/$_cc_m" ;; esac
  # The row's own spelling of the id: ids compare in any case (row_field does not).
  if [ -n "$_cc_m" ] && [ -f "$_cc_m" ] && mf_load "$_cc_m" \
     && _cc_r="$(awk -F'\t' -v w="$(ids_lc "$_cc_id")" 'tolower($1) == w { print $1; exit }' "$MF_ROWS")" \
     && [ -n "$_cc_r" ]; then
    [ "$_cc_hp" = 1 ] || _cc_p="$(row_field "$_cc_r" plan)"
    [ "$_cc_ht" = 1 ] || _cc_t="$(row_field "$_cc_r" ticket)"
    [ "$_cc_hb" = 1 ] || _cc_b="$(row_field "$_cc_r" branch)"
    [ "$_cc_hs" != 0 ] || _cc_s="$MF_SLUG"
  else
    : > "$MF_ROWS"
  fi
  [ -n "$_cc_p" ] || _cc_p=-
  [ -n "$_cc_b" ] || _cc_b=-
  IDS_IX_KEY=""   # a fresh index: refs and records as they are now (ids_index)
  if ids_check "$_cc_id" "$_cc_t" "$_cc_s" "$_cc_p" "$_cc_d" "$MF_ROWS" say "$_cc_b"; then
    echo "check-id: $_cc_id is free"
    return 0
  fi
  return 1
}
