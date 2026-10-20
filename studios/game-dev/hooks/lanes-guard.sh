#!/bin/sh
# PreToolUse hook for the game-dev studio (matcher Bash) (#71 T11). Refuses a
# `git commit` whose repo carries the per-worktree user:// lines
# (config/use_custom_user_dir, config/custom_user_dir_name) in a project.godot
# that HEAD lacks: merged, they would move user:// for every checkout. The
# detector is engines/godot/isolate.sh --leaks DIR (0 clean, 3 leak, 1 error).
#
# Per simple command (split at ; & | and newlines, quotes respected): `cd P`
# sets the dir for later segments; `git [-C P] [-c kv] [--no-pager] commit`
# is a target, its dir the cwd, cd-ed and -C-adjusted. Each target's repo top
# level is checked.
#
# By design it also denies when an unstaged working-tree project.godot carries
# the lanes lines (the commit may take them with `-a`), not only a staged one.
#
# Exit 0 on every path and print nothing to allow: unparseable input, a missing
# isolate.sh, or any error never blocks a call. No jq, no python, no lib/.
trap 'exit 0' EXIT
ISO="$(dirname "$0")/../engines/godot/isolate.sh"
[ -f "$ISO" ] || exit 0
input="$(cat 2>/dev/null || true)"
[ -n "${input:-}" ] || exit 0
case "$input" in *git*commit*) ;; *) exit 0 ;; esac
case "$input" in *'"tool_name":"Bash"'*|*'"tool_name": "Bash"'*) ;; *) exit 0 ;; esac
cwd="$(printf '%s' "$input" | sed -n 's/.*"cwd" *: *"\([^"]*\)".*/\1/p' | sed -n 1p)"
[ -n "$cwd" ] || cwd="$(pwd -P)"
dirs="$(printf '%s' "$input" | LC_ALL=C awk -v cwd="$cwd" '
  function unq(s,   o, i, c, n) {
    o = ""; n = length(s)
    for (i = 1; i <= n; i++) {
      c = substr(s, i, 1)
      if (c == "\\" && i < n) {
        i++; c = substr(s, i, 1)
        if (c == "n") o = o "\n"
        else if (c == "t") o = o " "
        else o = o c
      } else o = o c
    }
    return o
  }
  function res(base, p) { return (substr(p, 1, 1) == "/") ? p : base "/" p }
  function flush() { if (nt > 0) seg(); nt = 0 }
  function seg(   k, i, d) {
    k = 1
    while (k <= nt && tok[k] ~ /^[A-Za-z_][A-Za-z0-9_]*=/) k++
    if (k > nt) return
    if (tok[k] == "cd") { if (k < nt && tok[k + 1] != "-") dir = res(dir, tok[k + 1]); return }
    if (tok[k] != "git" && tok[k] !~ /\/git$/) return
    d = dir; i = k + 1
    while (i <= nt) {
      if (tok[i] == "-C" && i < nt) { d = res(d, tok[i + 1]); i += 2 }
      else if (tok[i] == "-c" && i < nt) i += 2
      else if (tok[i] == "--no-pager") i++
      else break
    }
    if (i <= nt && tok[i] == "commit") print d
  }
  { raw = raw $0 "\n" }
  END {
    p = index(raw, "\"command\"")
    if (p == 0) exit
    s = substr(raw, p + 9)
    sub(/^[ \t]*:[ \t]*"/, "", s)
    body = ""; n = length(s)
    for (i = 1; i <= n; i++) {
      c = substr(s, i, 1)
      if (c == "\\") { body = body substr(s, i, 2); i++ }
      else if (c == "\"") break
      else body = body c
    }
    cmd = unq(body); dir = unq(cwd)
    nt = 0; cur = ""; have = 0; q = ""
    n = length(cmd)
    for (i = 1; i <= n; i++) {
      c = substr(cmd, i, 1)
      if (q != "") {
        if (c == q) q = ""
        else if (q == "\"" && c == "\\" && i < n) { i++; cur = cur substr(cmd, i, 1) }
        else cur = cur c
      } else if (c == "\"" || c == "\047") { q = c; have = 1 }
      else if (c == "\\" && i < n) { i++; cur = cur substr(cmd, i, 1); have = 1 }
      else if (c == " " || c == "\t") { if (have) { tok[++nt] = cur; cur = ""; have = 0 } }
      else if (c == ";" || c == "&" || c == "|" || c == "\n" || c == "(" || c == ")" || c == "{" || c == "}") {
        if (have) { tok[++nt] = cur; cur = ""; have = 0 }
        flush()
      } else { cur = cur c; have = 1 }
    }
    if (have) tok[++nt] = cur
    flush()
  }' 2>/dev/null)" || exit 0
[ -n "$dirs" ] || exit 0
printf '%s\n' "$dirs" | while IFS= read -r d; do
  [ -n "$d" ] || continue
  top="$(git -C "$d" rev-parse --show-toplevel 2>/dev/null)" || continue
  [ -n "$top" ] || continue
  out="$(sh "$ISO" --leaks "$top" 2>/dev/null)"; rc=$?
  [ "$rc" = 3 ] || continue
  line="$(printf '%s\n' "$out" | sed -n 1p)"
  path="$(printf '%s' "$line" | sed 's/project\.godot: .*/project.godot/')"
  keys="$(printf '%s' "$line" | sed 's/^.*project\.godot: //')"
  path="$(printf '%s' "$path" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  keys="$(printf '%s' "$keys" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"game-dev: refused a commit: %s gains the per-worktree user:// setting (%s) that HEAD lacks; merged, it would move user:// for every checkout. Run studio-dispatch isolate --scrub in that worktree, then commit."}}\n' "$path" "$keys"
  exit 0
done
exit 0
