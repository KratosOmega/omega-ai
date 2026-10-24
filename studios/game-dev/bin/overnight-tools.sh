#!/bin/sh
# overnight-tools.sh — required_tools (#95), sourced by studio-overnight: the
# tools a run needs, from the start checkout's .studio/config.json, probed by
# the preflight. A miss is one refuse line naming the tool and its install
# hint. Needs refuse, say, START_DIR, CONFIG and WORKTREE_SETUP (cfg_nobs).
#   "required_tools": [ { "cmd": "ffmpeg", "hint": "brew install ffmpeg" },
#     { "cmd": ".venv/bin/python", "min_version": "3.10", "hint": "…" } ]
# A cmd with a / is a path relative to the checkout (always run, must exit 0);
# a bare cmd must be on PATH (run only for min_version). version_args
# (default --version) is split on blanks.

# tools_entries CONFIG — required_tools as TSV, one line per entry:
# cmd<TAB>min<TAB>args<TAB>hint. Nothing (exit 0) when the key is absent or [].
# A malformed key is one stderr line `config required_tools: <reason>` and
# exit 1: a backslash anywhere in the array (escapes are not decoded), a
# non-object element, a non-string value, an unknown key, no cmd or hint, a
# cmd outside ^[A-Za-z0-9._/+-]+$ (or starting with - or /, or with a ..
# component: a path entry stays inside the worktree), a bad
# min_version, version_args outside letters, digits, blanks and ._=+/:,-.
tools_entries() {
  [ -f "$1" ] || return 0
  _te_o="$(LC_ALL=C awk '
    function fail(m) { print m; exit 1 }
    function ws() { while (i <= n && index(" \t\r\n", substr(s, i, 1)) > 0) i++ }
    # str — the string starting at s[i] (a quote); i moves past it.
    function str(   j, c) {
      j = i + 1
      while (j <= n) {
        c = substr(s, j, 1)
        if (c == "\"") break
        if (c == "\t" || c == "\n" || c == "\r") fail("a string holds a control character")
        j++
      }
      if (j > n) fail("unterminated string")
      c = substr(s, i + 1, j - i - 1); i = j + 1; return c
    }
    { s = s $0 "\n" }
    END {
      n = length(s); i = 1; found = 0
      # The key, outside strings (other values may hold \" escapes).
      while (i <= n && !found) {
        c = substr(s, i, 1)
        if (c != "\"") { i++; continue }
        j = i + 1
        while (j <= n && substr(s, j, 1) != "\"") j += (substr(s, j, 1) == "\\") ? 2 : 1
        k = substr(s, i + 1, j - i - 1); i = j + 1
        if (k != "required_tools") continue
        j = i; ws()
        if (substr(s, i, 1) == ":") { i++; found = 1 } else i = j
      }
      if (!found) exit 0
      ws()
      if (substr(s, i, 1) != "[") fail("must be an array of objects")
      # Scan to the matching ], outside strings: any backslash is refused.
      d = 0; q = 0
      for (j = i; j <= n; j++) {
        c = substr(s, j, 1)
        if (c == "\\") fail("a backslash is not allowed (a JSON escape is not decoded)")
        if (c == "\"") q = !q
        else if (!q && (c == "[" || c == "{")) d++
        else if (!q && (c == "]" || c == "}")) { d--; if (d == 0) break }
      }
      if (j > n) fail("the array is not closed")
      i++; ne = 0; out = ""
      ws()
      if (substr(s, i, 1) == "]") exit 0
      while (1) {
        ws()
        if (substr(s, i, 1) != "{") fail(sprintf("entry %d is not an object", ne + 1))
        ne++; i++; split("", e)
        ws()
        if (substr(s, i, 1) == "}") i++
        else while (1) {
          ws()
          if (substr(s, i, 1) != "\"") fail(sprintf("entry %d: expected a \"key\": \"string\" pair", ne))
          k = str(); ws()
          if (k in e) fail(sprintf("entry %d: %s given twice", ne, k))
          if (substr(s, i, 1) != ":") fail(sprintf("entry %d: expected : after %s", ne, k))
          i++; ws()
          if (substr(s, i, 1) != "\"") fail(sprintf("entry %d: %s must be a string", ne, k))
          e[k] = str(); ws()
          c = substr(s, i, 1); i++
          if (c == "}") break
          if (c != ",") fail(sprintf("entry %d: expected , or } after %s", ne, k))
        }
        if (!("cmd" in e)) fail(sprintf("entry %d has no cmd", ne))
        cmd = e["cmd"]
        if (cmd !~ /^[A-Za-z0-9._\/+-]+$/ || cmd ~ /^[-\/]/)
          fail(sprintf("entry %d: cmd must be a name or a checkout-relative path of A-Z a-z 0-9 . _ / + -, got \"%s\"", ne, cmd))
        if (("/" cmd "/") ~ /\/\.\.\//) fail(sprintf("cmd %s must stay inside the worktree (entry %d has a .. component)", cmd, ne))
        for (k in e) if (k !~ /^(cmd|hint|min_version|version_args)$/) fail(sprintf("entry %d (%s): unknown key %s", ne, cmd, k))
        if (e["hint"] == "") fail(sprintf("entry %d (%s) has no hint", ne, cmd))
        m = ("min_version" in e) ? e["min_version"] : ""
        if (("min_version" in e) && m !~ /^[0-9]+(\.[0-9]+)*$/)
          fail(sprintf("entry %d (%s): min_version must be numbers and dots, like 3.10, got \"%s\"", ne, cmd, m))
        a = ("version_args" in e) ? e["version_args"] : "--version"
        if (a !~ /^[A-Za-z0-9 ._=+\/:,-]*$/)
          fail(sprintf("entry %d (%s): version_args may hold only letters, digits, blanks and . _ = + / : , -, got \"%s\"", ne, cmd, a))
        out = out cmd "\t" m "\t" a "\t" e["hint"] "\n"
        ws()
        c = substr(s, i, 1); i++
        if (c == "]") break
        if (c != ",") fail(sprintf("expected , or ] after entry %d", ne))
      }
      printf "%s", out
    }' "$1")" || { say "config required_tools: $_te_o"; return 1; }
  [ -z "$_te_o" ] || printf '%s\n' "$_te_o"
}

# tools_run FILE ARGS — FILE run with ARGS split on blanks, stdin /dev/null,
# stdout and stderr to a temp file, in the background and killed after
# STUDIO_OVERNIGHT_TOOLS_SECONDS (default 10, a test knob) as notify_operator
# caps its notifier. Sets TOOLS_RC (124 when capped) and TOOLS_OUT (the output).
tools_run() {
  TOOLS_OUT=""; TOOLS_RC=125
  _tr_f="$(mktemp "${TMPDIR:-/tmp}/tools-run.XXXXXX")" || return 0
  (
    set -f
    "$1" $2 </dev/null >"$_tr_f" 2>&1 &
    _tr_p=$!; echo "$_tr_p" > "$_tr_f.pid"; wait "$_tr_p"; echo "$?" > "$_tr_f.st.tmp"; mv "$_tr_f.st.tmp" "$_tr_f.st"
  ) >/dev/null 2>&1 &
  _tr_sp=$!
  # A bad knob is the preflight's refusal; here it is never an arithmetic error.
  _tr_s="${STUDIO_OVERNIGHT_TOOLS_SECONDS:-10}"; case "$_tr_s" in ''|*[!0-9]*) _tr_s=10 ;; esac
  _tr_i=0; _tr_max=$((_tr_s * 5))
  while [ ! -f "$_tr_f.st" ] && [ "$_tr_i" -lt "$_tr_max" ]; do sleep 0.2; _tr_i=$((_tr_i + 1)); done
  if [ -f "$_tr_f.st" ]; then
    TOOLS_RC="$(cat "$_tr_f.st")"
  else
    TOOLS_RC=124
    kill "$(cat "$_tr_f.pid" 2>/dev/null)" 2>/dev/null; kill "$_tr_sp" 2>/dev/null
  fi
  wait "$_tr_sp" 2>/dev/null
  TOOLS_OUT="$(cat "$_tr_f" 2>/dev/null)"
  rm -f "$_tr_f" "$_tr_f.pid" "$_tr_f.st" "$_tr_f.st.tmp"
}

# tools_probe DIR CMD MIN ARGS HINT — one entry in DIR. A pass prints its
# summary item (`CMD VERSION`, or `CMD found` when no version was read) and
# returns 0; a version that cannot be read for MIN prints the warning line
# first. A miss is one refuse line ending ` — install: HINT` and returns 1.
tools_probe() {
  _tp_c="$2"; _tp_m="$3"; _tp_a="$4"; _tp_h="$5"; _tp_v=""
  case "$_tp_c" in
    */*) _tp_r="$1/$_tp_c"
         [ -f "$_tp_r" ] && [ -x "$_tp_r" ] \
           || { refuse "required tool $_tp_c not found in $1 — install: $_tp_h"; return 1; } ;;
    # A clean sh: the runner's own functions are not tools.
    *) _tp_r="$(sh -c 'command -v "$1"' tools "$_tp_c" 2>/dev/null)" && [ -n "$_tp_r" ] \
         || { refuse "required tool $_tp_c not found on PATH — install: $_tp_h"; return 1; } ;;
  esac
  case "$_tp_c" in */*) ;; *) [ -n "$_tp_m" ] || { printf '%s found\n' "$_tp_c"; return 0; } ;; esac
  tools_run "$_tp_r" "$_tp_a"
  [ "$TOOLS_RC" = 0 ] || { refuse "required tool $_tp_c does not run (exit $TOOLS_RC) — install: $_tp_h"; return 1; }
  _tp_v="$(printf '%s\n' "$TOOLS_OUT" | LC_ALL=C awk 'match($0, /[0-9]+\.[0-9]+(\.[0-9]+)?/) { print substr($0, RSTART, RLENGTH); exit }')"
  if [ -n "$_tp_m" ]; then
    if [ -z "$_tp_v" ]; then
      echo "tools: $_tp_c: cannot read a version from '$_tp_c${_tp_a:+ $_tp_a}' — check it by hand"
    elif ! awk -v a="$_tp_v" -v b="$_tp_m" 'BEGIN {
        na = split(a, x, "."); nb = split(b, y, "."); k = (na > nb) ? na : nb
        for (j = 1; j <= k; j++) { p = (j <= na) ? x[j] + 0 : 0; q = (j <= nb) ? y[j] + 0 : 0
          if (p != q) exit !(p > q) }
        exit 0 }'; then
      refuse "required tool $_tp_c is $_tp_v, needs $_tp_m or later — install: $_tp_h"; return 1
    fi
  fi
  printf '%s %s\n' "$_tp_c" "${_tp_v:-found}"
}

# tools_check MODE — the preflight's required_tools check; MODE is start, dry
# or `paths-in DIR`. start: bare entries in START_DIR, and path entries too
# when WORKTREE_SETUP is unset (else setup_preflight probes them after the
# setup, with paths-in). dry: every entry in START_DIR, plus the path-entries
# note when WORKTREE_SETUP is set. paths-in DIR: path entries only, in DIR.
# Prints one `tools: …` summary line of the passes (none when nothing passed).
# Returns 1 (FAILED=1) on any refusal or a malformed key.
tools_check() {
  case "$1" in
    start) _tc_d="$START_DIR"; _tc_b=1; _tc_p=1; [ -z "${WORKTREE_SETUP:-}" ] || _tc_p=0 ;;
    dry) _tc_d="$START_DIR"; _tc_b=1; _tc_p=1 ;;
    "paths-in "?*) _tc_d="${1#paths-in }"; _tc_b=0; _tc_p=1 ;;
    *) refuse "tools_check: unknown mode $1"; return 1 ;;
  esac
  _tc_e="$(tools_entries "$CONFIG")" || { FAILED=1; return 1; }
  [ -n "$_tc_e" ] || return 0
  _tc_t="$(printf '\t')"; _tc_nl='
'
  _tc_s=""; _tc_rc=0; _tc_pe=0
  while IFS= read -r _tc_l; do
    _tc_c="${_tc_l%%"$_tc_t"*}"; _tc_l="${_tc_l#*"$_tc_t"}"
    _tc_m="${_tc_l%%"$_tc_t"*}"; _tc_l="${_tc_l#*"$_tc_t"}"
    _tc_a="${_tc_l%%"$_tc_t"*}"; _tc_h="${_tc_l#*"$_tc_t"}"
    case "$_tc_c" in
      */*) _tc_pe=1; [ "$_tc_p" -eq 1 ] || continue ;;
      *) [ "$_tc_b" -eq 1 ] || continue ;;
    esac
    _tc_i="$(tools_probe "$_tc_d" "$_tc_c" "$_tc_m" "$_tc_a" "$_tc_h")" || { FAILED=1; _tc_rc=1; continue; }
    case "$_tc_i" in *"$_tc_nl"*) printf '%s\n' "${_tc_i%"$_tc_nl"*}"; _tc_i="${_tc_i##*"$_tc_nl"}" ;; esac
    _tc_s="${_tc_s:+$_tc_s, }$_tc_i"
  done <<EOF
$_tc_e
EOF
  [ -z "$_tc_s" ] || echo "tools: $_tc_s"
  [ "$1" != dry ] || [ -z "${WORKTREE_SETUP:-}" ] || [ "$_tc_pe" -eq 0 ] \
    || echo "tools: path entries checked in the start checkout; start re-checks them after worktree_setup"
  return "$_tc_rc"
}
