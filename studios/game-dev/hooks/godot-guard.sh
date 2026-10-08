#!/bin/sh
# PreToolUse hook for the game-dev studio (matcher Bash), active in every
# session (#59 R4). Refuses a hand-built Godot call that the gate verbs exist
# to replace: phoenix T7 (2026-10-07) ran `Godot --headless --path . -gtest=…`
# without `-s gut_cmdln.gd`; Godot booted the main scene headless, never
# exited, and the unit lost 3 hours. Denied, per simple command:
#   (a) a Godot invocation with --path or --headless and none of -s, --script,
#       --import, -e, --editor, --export*, --version, --doctool, --quit,
#       --quit-after, --help, -h (a headless boot never exits);
#   (b) a Godot invocation that names gut_cmdln (a hand-built GUT run skips
#       the gate lock, and without -gdir= runs the whole suite).
# A Godot invocation is a first word (quotes removed; after NAME=value
# assignments and the wrappers env, exec, command, time, nice, timeout <n>)
# whose basename starts with "godot" in any case, or a $GODOT…/${GODOT…}
# variable. The command is JSON-unescaped, then split quote-aware at ; && ||
# | & ( ) and newlines. The engine adapters run Godot inside their own
# scripts, which this hook never sees.
#
# Exit 0 on every path and print nothing to allow: a parse problem never
# blocks a call. Self-contained on purpose (no jq, no python, no lib/).
trap 'exit 0' EXIT

input="$(cat 2>/dev/null || true)"
[ -n "${input:-}" ] || exit 0

verdict="$(printf '%s' "$input" | tr '\n' ' ' | awk '
  function unesc(s,   o, c, i, n) {
    o = ""; n = length(s)
    for (i = 1; i <= n; i++) {
      c = substr(s, i, 1)
      if (c == "\\" && i < n) {
        i++; c = substr(s, i, 1)
        if (c == "n" || c == "r") c = "\n"; else if (c == "t") c = "\t"
      }
      o = o c
    }
    return o
  }
  function flush() { if (inw) { nw++; w[nw] = cur }; cur = ""; inw = 0 }
  function endcmd() { flush(); if (nw) check(); nw = 0; split("", w) }
  function check(   i, j, t, b, hp, ok) {
    i = 1
    while (i <= nw) {
      t = w[i]
      if (t ~ /^[A-Za-z_][A-Za-z0-9_]*=/ || t == "!" || t == "{" || t == "if" || t == "then" || t == "else" || t == "elif" || t == "do" || t == "while" || t == "until") { i++; continue }
      if (t == "env") { i++; while (i <= nw && (w[i] ~ /^-/ || w[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/)) i++; continue }
      if (t == "exec" || t == "command" || t == "time") { i++; while (i <= nw && w[i] ~ /^-/) i++; continue }
      if (t == "nice") { i++; if (w[i] == "-n") i += 2; else while (i <= nw && w[i] ~ /^-/) i++; continue }
      if (t == "timeout") { i++; while (i <= nw && w[i] ~ /^-/) { if (w[i] == "-s" || w[i] == "-k") i++; i++ }; i++; continue }
      break
    }
    if (i > nw) return
    b = w[i]; sub(/.*\//, "", b); b = tolower(b)
    if (b !~ /^godot/ && w[i] !~ /^\$\{?GODOT/) return
    hp = 0; ok = 0
    for (j = i + 1; j <= nw; j++) {
      t = w[j]
      if (t ~ /gut_cmdln/) { verdict = "b"; return }
      if (t == "--headless" || t == "--path" || t ~ /^--path=/) hp = 1
      if (t == "-s" || t == "--script" || t == "--import" || t == "-e" || t == "--editor" || t ~ /^--export/ || t == "--version" || t == "--doctool" || t == "--quit" || t == "--quit-after" || t == "--help" || t == "-h") ok = 1
    }
    if (hp && !ok && verdict == "") verdict = "a"
  }
  {
    re = "\"command\"[ \t]*:[ \t]*\"([^\"\\\\]|\\\\.)*\""
    if (!match($0, re)) exit
    raw = substr($0, RSTART, RLENGTH); sub(/^"command"[ \t]*:[ \t]*"/, "", raw); raw = substr(raw, 1, length(raw) - 1)
    cmd = unesc(raw); n = length(cmd); q = ""; cur = ""; inw = 0; nw = 0; verdict = ""
    for (k = 1; k <= n; k++) {
      c = substr(cmd, k, 1)
      if (q == "\x27") { if (c == "\x27") q = ""; else cur = cur c; continue }
      if (q == "\"") {
        if (c == "\\" && k < n) { k++; cur = cur substr(cmd, k, 1); continue }
        if (c == "\"") q = ""; else cur = cur c
        continue
      }
      if (c == "\\" && k < n) { k++; cur = cur substr(cmd, k, 1); inw = 1; continue }
      if (c == "\x27" || c == "\"") { q = c; inw = 1; continue }
      if (c == ";" || c == "&" || c == "|" || c == "\n" || c == "(" || c == ")") { endcmd(); if (verdict == "b") break; continue }
      if (c == " " || c == "\t") { flush(); continue }
      cur = cur c; inw = 1
    }
    endcmd()
    print verdict
    exit
  }' 2>/dev/null)"

deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
}
_use="Run a test file with studio-test --file <tests/unit/x.gd> (repeatable), the suite with studio-test, the game with studio-run."
case "${verdict:-}" in
  a) deny "game-dev: refused a raw headless Godot command (--path or --headless without -s, --import, --export, --version or --quit): it boots the main scene and never exits. $_use" ;;
  b) deny "game-dev: refused a hand-built GUT run (gut_cmdln): it skips the gate lock that keeps Godot runs one at a time across lanes, and without -gdir= it runs the whole suite. $_use" ;;
esac
exit 0
