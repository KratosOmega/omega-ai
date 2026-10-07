#!/bin/sh
# overnight-ids.sh — story ids (#56): a story id, once used in a project, is
# not handed out again (ledgers are keyed by id and outlive the run).
# check-id's four taken rules (ids_reasons), its suggestion (ids_suggest),
# the report every caller shares (ids_check) and the verb (cmd_check_id).
# Sourced by overnight-lanes.sh, so by every manifest-mode path; never run on
# its own. Reads git refs and files only: it never fetches and never writes.
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
  printf '%s\n' "$_idb"
}
# ids_has FILE ID — FILE's first tab-separated column holds ID, in any case.
ids_has() { [ -f "$1" ] && awk -F'\t' -v w="$(ids_lc "$2")" 'tolower($1) == w { f = 1 } END { exit !f }' "$1"; }
# ids_ledgers REF ID — the .studio/ledger/<ID>.md paths on REF, matched in any
# case by listing the directory (a case-sensitive `git show` would miss s1.md).
ids_ledgers() {
  git -C "$START_DIR" ls-tree --name-only "$1" -- .studio/ledger/ 2>/dev/null \
    | awk -v w="$(ids_lc ".studio/ledger/$2.md")" 'tolower($0) == w'
}
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

# ids_reasons ID PLAN SLUG D — why ID is taken, one line per reason (the text
# after "is taken: "), in the order rule 1, 4, 2, 3 (D4); nothing when free.
# PLAN is this story's plan ('-' or empty: unknown), SLUG this run's slug
# (may be empty), D the default branch.
ids_reasons() {
  _ir_ref="refs/remotes/origin/$4"
  # 1. A ledger on the default branch that is not this story's own.
  for _ir_p in $(ids_ledgers "$_ir_ref" "$1"); do
    _ir_t="$(git -C "$START_DIR" show "$_ir_ref:$_ir_p" 2>/dev/null)"
    ids_own "$_ir_t" "$2" && continue
    [ -n "$3" ] && ids_has "$STATE_ROOT/.studio/runs/$3/landed.tsv" "$1" && continue
    printf 'origin/%s:%s belongs to another story%s\n' "$4" "$_ir_p" "$(ids_detail "$_ir_t")"
  done
  # 4. A plan on the default branch, other than this story's, with the line
  #    `Story: <id>` (git grep has no -x: each hit is re-tested whole-line).
  git -C "$START_DIR" grep -l -i -F -e "Story: $1" "$_ir_ref" -- docs/game-dev/plans 2>/dev/null \
    | while IFS= read -r _ir_h; do
        _ir_p="${_ir_h#"$_ir_ref":}"
        [ "$_ir_p" != "$2" ] || continue
        git -C "$START_DIR" show "$_ir_ref:$_ir_p" 2>/dev/null | grep -qixF -- "Story: $1" || continue
        printf "origin/%s:%s says 'Story: %s'\n" "$4" "$_ir_p" "$1"
      done
  # 2. A ledger on another run's integration branch.
  for _ir_r in $(git -C "$START_DIR" for-each-ref --format='%(refname)' refs/remotes/origin/integration/ 2>/dev/null); do
    _ir_s="${_ir_r#refs/remotes/origin/integration/}"
    [ "$_ir_s" != "$3" ] || continue
    for _ir_p in $(ids_ledgers "$_ir_r" "$1"); do
      printf "origin/integration/%s:%s belongs to run %s's integration branch\n" "$_ir_s" "$_ir_p" "$_ir_s"
    done
  done
  # 3. Another run's record: live, stopped, done or archived <slug>.<ts> (D2, D3).
  for _ir_d in "$STATE_ROOT"/.studio/runs/*/; do
    [ -d "$_ir_d" ] || continue
    _ir_d="${_ir_d%/}"; _ir_n="${_ir_d##*/}"
    [ "$_ir_n" != "$3" ] || continue
    _ir_b="$(printf '%s\n' "$_ir_n" | sed 's/\.[0-9]\{8\}T[0-9]\{6\}Z$//')"
    if ids_has "$_ir_d/rows.tsv" "$1" || ids_has "$_ir_d/landed.tsv" "$1" \
       || { [ ! -f "$_ir_d/rows.tsv" ] && [ "$_ir_b" != "$3" ] \
            && _ir_rw="$(runs_rows "$STATE_ROOT" "$_ir_b")" && ids_has "$_ir_rw" "$1"; }; then
      printf 'run %s (record .studio/runs/%s) lists it\n' "$_ir_b" "$_ir_n"
    fi
  done
}

# ids_suggest ID TICKET SLUG PLAN D ROWS — the first candidate that matches
# the id pattern, is not ID, is not a row id in ROWS (any case) and is free by
# ids_reasons: TICKET (when not ID), TICKET-2 … TICKET-9, then SLUG-S1 …
# SLUG-S9. TICKET '-' or empty: none. 1 when no candidate is left.
ids_suggest() {
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
    [ -z "$(ids_reasons "$_is_k" "$4" "$3" "$5" < /dev/null)" ] || continue
    printf '%s\n' "$_is_k"; break
  done)"
  [ -n "$_is_o" ] || return 1
  printf '%s\n' "$_is_o"
}

# ids_check ID TICKET SLUG PLAN D ROWS EMIT — 0 when ID is free. Taken: EMIT
# (say or refuse) once per reason, then once with the suggestion; 1. The
# here-document keeps EMIT in this shell, so refuse's FAILED=1 sticks.
ids_check() {
  _ic_r="$(ids_reasons "$1" "$4" "$3" "$5" < /dev/null)"
  [ -n "$_ic_r" ] || return 0
  while IFS= read -r _ic_l; do
    "$7" "story id '$1' is taken: $_ic_l"
  done <<EOF_IC
$_ic_r
EOF_IC
  if _ic_s="$(ids_suggest "$1" "$2" "$3" "$4" "$5" "$6" < /dev/null)"; then
    "$7" "use '$_ic_s' instead"
  else
    "$7" "pick an unused id: the ticket, or <run slug>-S<n>"
  fi
  return 1
}

# cmd_check_id ARGS — `check-id <id> [--plan <path>|-] [--ticket <ticket>|-]
# [--slug <slug>]` (R2). Defaults (D6): the row of .studio/run's manifest
# that lists <id>. 0 free · 1 taken · 2 usage.
cmd_check_id() {
  _cc_id=""; _cc_p=""; _cc_t=""; _cc_s=""; _cc_hp=0; _cc_ht=0; _cc_hs=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --plan|--ticket|--slug)
        [ "$#" -ge 2 ] && [ -n "$2" ] || { usage >&2; return 2; }
        case "$1" in
          --plan) _cc_p="$2"; _cc_hp=1 ;;
          --ticket) _cc_t="$2"; _cc_ht=1 ;;
          *) _cc_s="$2"; _cc_hs=1 ;;
        esac
        shift 2 ;;
      -*) usage >&2; return 2 ;;
      *) [ -z "$_cc_id" ] || { usage >&2; return 2; }; _cc_id="$1"; shift ;;
    esac
  done
  [ -n "$_cc_id" ] || { usage >&2; return 2; }
  ids_ok "$_cc_id" || { say "check-id: story id '$_cc_id' must match $IDS_PAT"; return 2; }
  [ "$_cc_hs" = 0 ] || ids_ok "$_cc_s" || { say "check-id: slug '$_cc_s' must match $IDS_PAT"; return 2; }
  [ -n "$START_DIR" ] || { say "no studio state here (run from the project checkout)"; return 2; }
  _cc_d="$(ids_default_branch)" || { say "origin/HEAD is not set — run: git remote set-head origin --auto"; return 2; }
  MF_ROWS="$(mktemp "${TMPDIR:-/tmp}/check-id.XXXXXX")" || return 2
  trap 'rm -f "$MF_ROWS"' EXIT
  _cc_m="$(head -n 1 "$START_DIR/.studio/run" 2>/dev/null)"
  case "$_cc_m" in ''|/*) ;; *) _cc_m="$START_DIR/$_cc_m" ;; esac
  if [ -n "$_cc_m" ] && [ -f "$_cc_m" ] && mf_load "$_cc_m" \
     && awk -F'\t' -v id="$_cc_id" '$1 == id { f = 1 } END { exit !f }' "$MF_ROWS"; then
    [ "$_cc_hp" = 1 ] || _cc_p="$(row_field "$_cc_id" plan)"
    [ "$_cc_ht" = 1 ] || _cc_t="$(row_field "$_cc_id" ticket)"
    [ "$_cc_hs" = 1 ] || _cc_s="$MF_SLUG"
  else
    : > "$MF_ROWS"
  fi
  [ -n "$_cc_p" ] || _cc_p=-
  if ids_check "$_cc_id" "$_cc_t" "$_cc_s" "$_cc_p" "$_cc_d" "$MF_ROWS" say; then
    echo "check-id: $_cc_id is free"
    return 0
  fi
  return 1
}
