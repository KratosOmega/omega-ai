#!/bin/sh
# overnight-channel.sh — the operator channel (#27; spec AC1-8): the verbs
# say, said, unsay, hold, resume and stop <story>, --run, run discovery, the
# inbox lock, ids and the cap; plus the message helpers the runner shares
# (msg_get, msg_body, inbox_lock, inbox_unlock). Sourced by studio-overnight
# before its dispatch; never run on its own. The verbs write only
# inbox/<story>/<id>.msg and control/<story>.<kind> in the live run's dir,
# each by temp file then mv, and never a story record (R1, R27).
[ -n "${SELF_DIR:-}" ] || { echo "overnight-channel.sh: sourced by studio-overnight" >&2; exit 2; }
CH_TAB="$(printf '\t')"

# msg_get KEY FILE — a message header's value (header lines only).
msg_get() { LC_ALL=C sed -n "1,/^--\$/s/^$1: //p" "$2" 2>/dev/null | head -n 1; }
# msg_body FILE — the message text, its newlines folded to spaces.
msg_body() { LC_ALL=C sed '1,/^--$/d' "$1" 2>/dev/null | LC_ALL=C tr '\n' ' ' | LC_ALL=C sed 's/ *$//'; }
# mtime PATH — PATH's modification time in epoch seconds (GNU, else BSD).
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null; }

# inbox_lock DIR WAIT [break] — R10: mkdir DIR/.lock, retried each second
# for up to WAIT seconds, the owner token "<pid> <epoch>" (IL_TOKEN) in
# DIR/.lock/owner. With `break`, a lock whose dir is over 10 s old is renamed
# to a unique name, then removed, or put back when the renamed dir is fresh
# (it was a waiter's new lock). Returns 1 on timeout, 2 when DIR cannot be
# created. A stale lock that cannot be renamed counts against WAIT like any
# other wait. The runner calls it without `break`, so it needs no stat (the
# minimal PATH).
inbox_lock() {
  mkdir -p "$1" 2>/dev/null || return 2
  _il_t=0; _il_c=0
  while ! mkdir "$1/.lock" 2>/dev/null; do
    if [ "${3:-}" = break ] && [ "$_il_c" -lt 20 ] && _il_m="$(mtime "$1/.lock")" && [ -n "$_il_m" ] \
       && [ $(( $(date +%s) - _il_m )) -gt 10 ]; then
      _il_c=$((_il_c + 1))
      _il_s="$1/.lock.stale.$$.$(date +%s)"
      if mv "$1/.lock" "$_il_s" 2>/dev/null; then
        _il_m="$(mtime "$_il_s")"
        if [ -n "$_il_m" ] && [ $(( $(date +%s) - _il_m )) -le 10 ]; then
          [ -e "$1/.lock" ] || mv "$_il_s" "$1/.lock" 2>/dev/null   # a new lock: put it back (never nest it)
        else
          rm -rf "$_il_s"
        fi
        continue
      fi
    fi
    [ "$_il_t" -lt "$2" ] || return 1
    sleep 1; _il_t=$((_il_t + 1))
  done
  IL_TOKEN="$$ $(date +%s)"; printf '%s\n' "$IL_TOKEN" > "$1/.lock/owner" 2>/dev/null
  return 0
}
# inbox_unlock DIR — release DIR/.lock when this process holds it.
inbox_unlock() {
  [ "$(cat "$1/.lock/owner" 2>/dev/null)" != "${IL_TOKEN:-}" ] || rm -rf "$1/.lock"
  IL_TOKEN=""
}

# chan_fail CODE TEXT — one stderr line, exit CODE.
chan_fail() { say "$2"; exit "$1"; }
# chan_lock — take CH_IB's lock (waiting up to the inbox wait) or fail with
# the real reason: busy, or the inbox dir cannot be created.
chan_lock() {
  inbox_lock "$CH_IB" "${STUDIO_OVERNIGHT_INBOX_WAIT:-15}" break && return 0
  if [ "$?" = 2 ]; then chan_fail 1 "cannot create $CH_IB"; fi
  chan_fail 1 "inbox busy: story $CH_STORY (try again)"
}
chan_usage() {
  {
    echo "usage: studio-overnight say <story> [--unit] [--run <run>] '<text>' | say <story> [--unit] [--run <run>] -- <text>"
    echo "       studio-overnight said|hold|resume|stop <story> [--run <run>] | unsay <story> <id> [--run <run>] | stop [--run <run>]"
    echo "       (<story> is - in a single-plan run; <run> is the run dir's basename)"
  } >&2
  exit 2
}
# chan_args ARGS… — A_RUN, A_UNIT, A_DASH, A_TEXT (every word after --,
# joined by spaces), A_N positionals in A_P1..A_P3. Returns 2 on an unknown
# option, --run with no value, or a fourth positional.
chan_args() {
  A_RUN=""; A_UNIT=0; A_DASH=0; A_TEXT=""; A_N=0; A_P1=""; A_P2=""; A_P3=""
  while [ "$#" -gt 0 ]; do
    if [ "$A_DASH" = 1 ]; then A_TEXT="${A_TEXT:+$A_TEXT }$1"; shift; continue; fi
    case "$1" in
      --) A_DASH=1 ;;
      --run) [ "$#" -ge 2 ] || return 2; A_RUN="$2"; shift ;;
      --unit) A_UNIT=1 ;;
      -?*) return 2 ;;
      *) [ "$A_N" -lt 3 ] || return 2; A_N=$((A_N + 1)); eval "A_P$A_N=\$1" ;;
    esac
    shift
  done
}

# chan_find_run — R2: CH_RUN, CH_ROOT, CH_START, CH_PID of the one live run
# this verb acts on, or exit 1. Inside a project: the lock's run, which
# --run must name exactly. Outside: the live registry entries, filtered by
# --run.
chan_find_run() {
  CH_RUN=""; CH_ROOT=""; CH_START=""; CH_PID=""
  if [ -n "$STATE_ROOT" ] && [ -d "$STATE_ROOT/.studio" ]; then
    if lock_live; then CH_RUN="$(sed -n 's/^run=//p' "$LOCK" | head -n 1)"; CH_PID="$(lock_pid)"; fi
    if [ -n "$A_RUN" ] && [ "${CH_RUN##*/}" != "$A_RUN" ]; then chan_fail 1 "run $A_RUN is not live"; fi
    [ -n "$CH_RUN" ] || chan_fail 1 "no live run in $STATE_ROOT"
    CH_ROOT="$STATE_ROOT"; CH_START="$START_DIR"
    for _cf_e in "$REGISTRY"/overnight-*; do
      [ -f "$_cf_e" ] && [ "$(reg_get run "$_cf_e")" = "$CH_RUN" ] || continue
      _cf_s="$(reg_get start "$_cf_e")"; [ -z "$_cf_s" ] || CH_START="$_cf_s"
      break
    done
    return 0
  fi
  _cf_n=0; _cf_names=""
  for _cf_e in "$REGISTRY"/overnight-*; do
    [ -f "$_cf_e" ] && reg_live "$_cf_e" || continue
    _cf_r="$(reg_get run "$_cf_e")"
    [ -z "$A_RUN" ] || [ "${_cf_r##*/}" = "$A_RUN" ] || continue
    _cf_n=$((_cf_n + 1)); _cf_names="${_cf_names:+$_cf_names, }${_cf_r##*/}"
    CH_RUN="$_cf_r"; CH_ROOT="$(reg_get root "$_cf_e")"; CH_START="$(reg_get start "$_cf_e")"; CH_PID="$(reg_get pid "$_cf_e")"
  done
  if [ "$_cf_n" -eq 0 ]; then
    [ -z "$A_RUN" ] || chan_fail 1 "run $A_RUN is not live"
    chan_fail 1 "no live run (run the verb in the run's project, or name the run with --run)"
  fi
  [ "$_cf_n" -eq 1 ] || chan_fail 1 "$_cf_n live runs ($_cf_names): name one with --run"
}
# chan_open VERB STORY — R3, AC4, AC6: the run's channel file, the story's
# membership and record (CH_REC), and its paths. Exit 1 on any refusal.
chan_open() {
  CH_NAME="${CH_RUN##*/}"; CH_STORY="$2"
  [ -f "$CH_RUN/channel" ] || chan_fail 1 "run $CH_NAME predates the operator channel (restart it to use $1)"
  CH_HOLD_MIN="$(sed -n 's/^hold_minutes=//p' "$CH_RUN/channel" | head -n 1)"
  CH_DCHARS="$(sed -n 's/^directive_chars=//p' "$CH_RUN/channel" | head -n 1)"
  # a malformed value falls back to the default (config range 500-16000)
  case "$CH_DCHARS" in ''|*[!0-9]*) CH_DCHARS=4000 ;; esac
  { [ "$CH_DCHARS" -ge 500 ] && [ "$CH_DCHARS" -le 16000 ]; } || CH_DCHARS=4000
  if [ -f "$CH_RUN/rows.tsv" ]; then
    CH_MODE=manifest
    awk -F'\t' -v id="$2" '$1 == id { f = 1 } END { exit !f }' "$CH_RUN/rows.tsv" \
      || chan_fail 1 "story $2 is not in run $CH_NAME"
    CH_REC="$(cat "$CH_RUN/stories/$2" 2>/dev/null)"
  else
    CH_MODE=single
    [ "$2" = - ] || chan_fail 1 "run $CH_NAME is a single-plan run: its story is -"
    CH_REC="$(cat "$CH_RUN/control/-.held" 2>/dev/null)"; [ -n "$CH_REC" ] || CH_REC=running
  fi
  case "$CH_REC" in landed*|stopped*|skipped*) chan_fail 1 "story $2 has ended: $CH_REC" ;; esac
  CH_IB="$CH_RUN/inbox/$2"; CH_CTL="$CH_RUN/control"
}
# chan_ledger — the story's feature-ledger lines (`- <date> <text>`), read in
# its feature checkout when one exists, else in the start checkout. Never
# the verb's cwd (R22).
chan_ledger() {
  ( cd "$CH_START" 2>/dev/null || exit 0
    if [ "$CH_STORY" = - ]; then unset STUDIO_STORY; else STUDIO_STORY="$CH_STORY"; export STUDIO_STORY; fi
    _cl_w="$(sh "$STATE_BIN" worktree 2>/dev/null)"
    [ -z "$_cl_w" ] || [ ! -d "$_cl_w" ] || cd "$_cl_w"
    sh "$STATE_BIN" show 2>/dev/null ) | sed -n '/^## Feature ledger: /,$p' | sed 1d
}
# chan_list DIR — the story's directives and messages, one TSV row each,
# `id state scope text target`, in id order. It reads the ledger lines in
# CH_LEDGER (exported) and DIR's pending and delivered files. States:
# active and retiring (ledgered); pending (any scope); delivered (a story
# message not yet ledgered, or a retire whose target is not yet retired).
# Retired directives and spent unit messages are not listed.
chan_list() {
  _cl_d="$1"; set --
  for _cl_f in "$_cl_d"/[0-9]*.msg "$_cl_d"/delivered/*/[0-9]*.msg; do [ -f "$_cl_f" ] && set -- "$@" "$_cl_f"; done
  [ "$#" -gt 0 ] || set -- /dev/null
  awk '
    function out(a, b, c, d, e) { print a "\t" b "\t" c "\t" d "\t" e }
    BEGIN {
      n = split(ENVIRON["CH_LEDGER"], L, "\n")
      for (i = 1; i <= n; i++) {
        l = L[i]
        if (match(l, /^- [0-9-]+ Directive [0-9]+: /)) {
          h = substr(l, 1, RLENGTH - 2); sub(/.* /, "", h)
          if (!(h in act)) act[h] = substr(l, RLENGTH + 1)
        } else if (l ~ /^- [0-9-]+ Directive [0-9]+ retired *$/) {
          h = l; sub(/^- [0-9-]+ Directive /, "", h); sub(/ .*/, "", h); ret[h] = 1
        }
      }
    }
    FILENAME == "/dev/null" { next }
    FNR == 1 { f = FILENAME; F[++nf] = f; inb[f] = 0; tg[f] = "-"; dl[f] = (f ~ /\/delivered\//) }
    !inb[f] {
      if ($0 == "--") { inb[f] = 1; next }
      if (match($0, /^[a-z]+: /)) {
        k = substr($0, 1, RLENGTH - 2); v = substr($0, RLENGTH + 1)
        if (k == "id") id[f] = v; else if (k == "scope") sc[f] = v; else if (k == "target") tg[f] = v
      }
      next
    }
    { gsub(/\t/, " "); tx[f] = (tx[f] == "" ? $0 : tx[f] " " $0) }
    END {
      for (i = 1; i <= nf; i++) { f = F[i]; if (sc[f] == "retire" && !(tg[f] in ret)) rt[tg[f]] = id[f] }
      for (h in act) if (!(h in ret)) out(h, (h in rt) ? "retiring" : "active", "story", act[h], "-")
      for (i = 1; i <= nf; i++) {
        f = F[i]
        if (!dl[f]) out(id[f], "pending", sc[f], tx[f], tg[f])
        else if (sc[f] == "story" && !(id[f] in act) && !(id[f] in ret)) out(id[f], (id[f] in rt) ? "retiring" : "delivered", "story", tx[f], "-")
        else if (sc[f] == "retire" && !(tg[f] in ret)) out(id[f], "delivered", "retire", tx[f], tg[f])
      }
    }' "$@" | sort -t "$CH_TAB" -k1,1n
}
# chan_next_id DIR — one more than the highest id among CH_LEDGER's
# Directive lines and DIR's message files, pending first, then delivered
# (R10, R11).
chan_next_id() {
  _ni_d="$1"; set --
  for _ni_f in "$_ni_d"/[0-9]*.msg "$_ni_d"/delivered/*/[0-9]*.msg; do [ -f "$_ni_f" ] && set -- "$@" "${_ni_f##*/}"; done
  { printf '%s\n' "$CH_LEDGER" | sed -n 's/^- [0-9-]* Directive \([0-9][0-9]*\)[: ].*/\1/p'
    for _ni_b in "$@"; do printf '%s\n' "${_ni_b%.msg}"; done
  } | awk '$1 + 0 > m { m = $1 + 0 } END { print m + 1 }'
}
# chan_write_msg ID SCOPE TARGET TEXT — CH_IB/ID.msg, by temp file then mv.
chan_write_msg() {
  _wm_t="$CH_IB/.say.$$"
  printf 'id: %s\nscope: %s\ntarget: %s\nstory: %s\nqueued: %s\nrequeues: 0\n--\n%s\n' \
    "$1" "$2" "$3" "$CH_STORY" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$4" 2>/dev/null > "$_wm_t" \
    && mv -f "$_wm_t" "$CH_IB/$1.msg" && return 0
  rm -f "$_wm_t"; return 1
}
# chan_event EVENT FIELD… — studio-event into the run's log; a failure is
# one line in hook.log, never fatal (AC29).
chan_event() { sh "$SELF_DIR/studio-event" "$CH_RUN" "$@" 2>> "$CH_RUN/hook.log" || true; }
# chan_chars — the character count of stdin (UTF-8 lead bytes; R13).
chan_chars() { LC_ALL=C tr -d '\200-\277' | wc -c | tr -d ' '; }

# chan_say TEXT — AC1, AC5: the next id, the cap (story scope only), the
# message, a message_queued event; prints the id.
chan_say() {
  _cs_sc=story; [ "$A_UNIT" = 0 ] || _cs_sc=unit
  CH_LEDGER="$(chan_ledger)"; export CH_LEDGER
  chan_lock
  if [ "$_cs_sc" = story ]; then
    _cs_l="$(chan_list "$CH_IB")"
    _cs_used="$(printf '%s\n' "$_cs_l" | awk -F'\t' '$3 == "story" { printf "%s", $4 }' | chan_chars)"
    _cs_new="$(printf '%s' "$1" | tr '\n' ' ' | chan_chars)"
    if [ $((_cs_used + _cs_new)) -gt "$CH_DCHARS" ]; then
      inbox_unlock "$CH_IB"
      say "say: story $CH_STORY would carry $((_cs_used + _cs_new)) directive characters, over directive_chars $CH_DCHARS — retire one (unsay) first:"
      printf '%s\n' "$_cs_l" | awk -F'\t' '$3 == "story" { printf "  %s  %s  %s\n", $1, $2, $4 }' >&2
      exit 1
    fi
  fi
  _cs_id="$(chan_next_id "$CH_IB")"
  chan_write_msg "$_cs_id" "$_cs_sc" - "$1" || { inbox_unlock "$CH_IB"; chan_fail 1 "cannot write $CH_IB/$_cs_id.msg"; }
  inbox_unlock "$CH_IB"
  chan_event message_queued "story=$CH_STORY" "id:=$_cs_id" "scope=$_cs_sc"
  printf '%s\n' "$_cs_id"
}
# chan_said — AC3, R15.
chan_said() {
  CH_LEDGER="$(chan_ledger)"; export CH_LEDGER
  _sd="$(chan_list "$CH_IB" | awk -F'\t' '$3 == "retire" { next }
    { s = $2; if (s == "pending" && $3 == "unit") s = "pending (unit)"; printf "%s  %s  %s\n", $1, s, $4 }')"
  if [ -n "$_sd" ]; then printf '%s\n' "$_sd"; else echo "(no directives)"; fi
}
# chan_unsay ID — AC2, R12.
chan_unsay() {
  CH_LEDGER="$(chan_ledger)"; export CH_LEDGER
  chan_lock
  _us="$(chan_list "$CH_IB" | awk -F'\t' -v id="$1" '$1 == id { print $2 "\t" $3; exit }')"
  _us_st="${_us%%"$CH_TAB"*}"; _us_sc="${_us#*"$CH_TAB"}"
  case "$_us_st:$_us_sc" in
    pending:retire) inbox_unlock "$CH_IB"; chan_fail 1 "message $1 is a retire message: unsay retires directives, not retires" ;;
    pending:*)
      if rm "$CH_IB/$1.msg" 2>/dev/null; then
        inbox_unlock "$CH_IB"
        echo "removed message $1 (it was not delivered)"; return 0
      fi
      inbox_unlock "$CH_IB"; chan_fail 1 "unsay: message $1 was just delivered; run unsay $1 again to retire it" ;;
    active:story|delivered:story)
      _us_id="$(chan_next_id "$CH_IB")"
      chan_write_msg "$_us_id" retire "$1" "retire directive $1" || { inbox_unlock "$CH_IB"; chan_fail 1 "cannot write $CH_IB/$_us_id.msg"; }
      inbox_unlock "$CH_IB"
      chan_event message_queued "story=$CH_STORY" "id:=$_us_id" scope=retire
      echo "retire queued: message $_us_id retires directive $1"; return 0 ;;
    retiring:*) inbox_unlock "$CH_IB"; chan_fail 1 "directive $1 is already retiring" ;;
    delivered:retire) inbox_unlock "$CH_IB"; chan_fail 1 "message $1 is a retire message: unsay retires directives, not retires" ;;
  esac
  inbox_unlock "$CH_IB"
  if printf '%s\n' "$CH_LEDGER" | grep -q "^- [0-9-]* Directive $1 retired *\$"; then chan_fail 1 "directive $1 is already retired"; fi
  for _us_f in "$CH_IB"/delivered/*/"$1.msg"; do
    [ -f "$_us_f" ] && chan_fail 1 "message $1 was for one unit only and is spent: nothing to retire"
  done
  chan_fail 1 "no message or directive $1 for story $CH_STORY"
}
# chan_stop_run — bare `stop --run <run>`: today's stop, aimed by --run.
chan_stop_run() {
  { : > "$CH_ROOT/.studio/overnight.stop"; } 2>/dev/null || chan_fail 1 "cannot write $CH_ROOT/.studio/overnight.stop"
  echo "stop requested: the run ends after its running unit (pid $CH_PID)"
}

# chan_ctl_write KIND — control/<story>.KIND, by temp file then mv, and a
# control event. Writing it again is the same success (R22).
chan_ctl_write() {
  mkdir -p "$CH_CTL" 2>/dev/null
  _cw_t="$CH_CTL/.$CH_STORY.$1.$$"
  if { date -u +%Y-%m-%dT%H:%M:%SZ > "$_cw_t"; } 2>/dev/null && mv -f "$_cw_t" "$CH_CTL/$CH_STORY.$1"; then
    chan_event control "story=$CH_STORY" "action=$1"; return 0
  fi
  rm -f "$_cw_t"; chan_fail 1 "cannot write $CH_CTL/$CH_STORY.$1"
}
# chan_holds_on — AC8: hold and resume exit 1 when the run's hold_minutes is 0.
chan_holds_on() { [ "${CH_HOLD_MIN:-0}" -gt 0 ] 2>/dev/null || chan_fail 1 "holds are off: hold_minutes 0"; }
# chan_hold — AC7's hold column.
chan_hold() {
  chan_holds_on
  case "$CH_REC" in
    held*) chan_fail 1 "story $CH_STORY is already held" ;;
    landing*|repair*) chan_fail 1 "story $CH_STORY is landing: landing holds the land lock" ;;
  esac
  chan_ctl_write hold
  case "$CH_REC" in
    queued*|waiting*) echo "hold requested: $CH_STORY holds when it would start" ;;
    *) echo "hold requested: $CH_STORY holds at its next unit boundary" ;;
  esac
}
# chan_resume — AC7's resume column, AC21's dirty check (R22: the run's
# start checkout, never the cwd).
chan_resume() {
  chan_holds_on
  case "$CH_REC" in held*) ;; *) chan_fail 1 "story $CH_STORY is not held ($CH_REC)" ;; esac
  if [ "$CH_MODE" = single ]; then _cr_p=.studio/ledger; else _cr_p=".studio/ledger/$CH_STORY.md"; fi
  _cr_d="$(git -C "$CH_START" status --porcelain -- "$_cr_p" 2>/dev/null | head -n 1)"
  [ -z "$_cr_d" ] || chan_fail 1 "resume refused: ${_cr_d#???} has uncommitted changes in $CH_START (a restart would refuse it too)"
  chan_ctl_write resume
  echo "resume requested: $CH_STORY resumes within one poll"
}
# chan_stop — AC7's stop column; AC23.
chan_stop() {
  case "$CH_REC" in landing*|repair*) chan_fail 1 "story $CH_STORY is landing: landing holds the land lock" ;; esac
  chan_ctl_write stop
  case "$CH_REC" in
    queued*|waiting*) echo "stop requested: $CH_STORY stops when its lane reaches it" ;;
    held*) echo "stop requested: $CH_STORY stops within one poll" ;;
    *) echo "stop requested: $CH_STORY stops after its running unit" ;;
  esac
}

# chan_main VERB ARGS… — parse, check usage (exit 2, before any run lookup),
# find the run, open the story, act. Never returns.
chan_main() {
  CH_VERB="$1"; shift
  chan_args "$@" || chan_usage
  [ "$CH_VERB" = say ] || { [ "$A_UNIT" = 0 ] && [ "$A_DASH" = 0 ]; } || chan_usage
  case "$CH_VERB" in
    say)
      if [ "$A_DASH" = 1 ]; then [ "$A_N" -eq 1 ] || chan_usage; _cm_t="$A_TEXT"
      else [ "$A_N" -eq 2 ] || chan_usage; _cm_t="$A_P2"; fi
      chan_text_check "$_cm_t" ;;
    said) [ "$A_N" -eq 1 ] || chan_usage ;;
    unsay) [ "$A_N" -eq 2 ] || chan_usage
           case "$A_P2" in ''|0*|*[!0-9]*) chan_usage ;; esac ;;
    hold|resume) [ "$A_N" -eq 1 ] || chan_usage ;;
    stop) [ "$A_N" -le 1 ] || chan_usage ;;
    *) chan_usage ;;
  esac
  chan_find_run
  if [ "$CH_VERB" = stop ] && [ "$A_N" -eq 0 ]; then chan_stop_run; exit 0; fi
  chan_open "$CH_VERB" "$A_P1"
  case "$CH_VERB" in
    say) chan_say "$_cm_t" ;;
    said) chan_said ;;
    unsay) chan_unsay "$A_P2" ;;
    hold) chan_hold ;;
    resume) chan_resume ;;
    stop) chan_stop ;;
  esac
  exit 0
}
# chan_text_check TEXT — R14: exit 2 when TEXT has no non-blank character.
# (A function, so the case pattern never sits inside $(...).)
chan_text_check() {
  case "$1" in *[![:space:]]*) return 0 ;; esac
  say "say: empty text"; exit 2
}
