# godot-cmd.awk — the game-dev studio's Godot command detector, shared by
# hooks/godot-guard.sh (#59 R4, #66 R1) and studio-brief (#66 R4). Data, not
# a command: run it as
#   LC_ALL=C awk -v mode=json|md [-v out=rows|hook|rewrite] [-v nonl=1] -f godot-cmd.awk [FILE]
# LC_ALL=C makes length/substr count bytes under every awk (macOS awk always
# does; gawk does only in the C locale).
#
# Input, slurped and processed in END (a heredoc needs the whole command):
#   mode=json  a PreToolUse payload; its first "command" string is extracted
#              and JSON-unescaped here (no jq, no python).
#   mode=md    markdown; each line inside a ``` or ~~~ fence, and each inline
#              backtick span on any other line, is one command text. Prose
#              outside spans is never read.
# Each command text is split quote-aware at ; & && | || ( ) and newlines;
# >& <& &> &>> (as in 2>&1) are redirections, not separators. A simple
# command is a Godot invocation when its first word (quotes removed; after
# NAME=value assignments, the keywords ! { if then else elif do while until,
# and the wrappers env, exec, command, time, nohup, nice, timeout/gtimeout
# <n>) has a basename starting "godot" in any case, or is $GODOT, $GODOT_PATH
# or $GODOT_BIN (braces allowed). Its verdict:
#   b  a word names gut_cmdln (a hand-built GUT run);
#   c  else -s, --script, --script=… or --import before a bare -- (an
#      unwrapped script/import run; what follows -- is the game's own args);
#   a  else --headless, --path or --path=… and none of -s, --script,
#      --import, -e, --editor, --export*, --version, --doctool, --quit,
#      --quit-after, --help, -h anywhere (a headless boot never exits).
# A refused simple command's segment is its source text from the Godot word
# to its last word (assignments and wrappers dropped, quoting kept).
#
# Output:
#   out=rows (default)  <line>\t<verdict>\t<segment> per refused simple
#                       command, in input order (line: 1-based, where the
#                       segment starts; a newline inside a segment prints as a
#                       space). Nothing when clean.
#   out=hook (json)     line 1: the verdicts present, in the order b c a
#                       (e.g. "ca"); line 2: the first c segment cut to 400
#                       bytes on a UTF-8 boundary ("…" appended when cut),
#                       then JSON-escaped (empty when there is no c).
#                       Nothing when clean.
#   out=rewrite (md)    the input with "studio-gate godot -- " inserted before
#                       each c segment; every other byte unchanged. nonl=1:
#                       the input had no final newline, so none is printed.
BEGIN {
  if (out == "") out = "rows"
  for (i = 128; i < 192; i++) CONT[sprintf("%c", i)] = 1
  for (i = 1; i < 32; i++) CTL[sprintf("%c", i)] = sprintf("\\u%04x", i)
  CTL["\n"] = "\\n"; CTL["\t"] = "\\t"; CTL["\r"] = "\\r"
  NL = 0; NS = 0
}
{ L[++NL] = $0 }
END {
  if (mode == "json") json_main()
  else if (mode == "md") md_main()
}

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
function json_main(   s, i, re, raw, cmd) {
  s = ""
  for (i = 1; i <= NL; i++) s = s (i > 1 ? " " : "") L[i]
  re = "\"command\"[ \t]*:[ \t]*\"([^\"\\\\]|\\\\.)*\""
  if (!match(s, re)) return
  raw = substr(s, RSTART, RLENGTH); sub(/^"command"[ \t]*:[ \t]*"/, "", raw); raw = substr(raw, 1, length(raw) - 1)
  cmd = unesc(raw)
  if (tolower(cmd) !~ /godot/) return
  parse(cmd, 1, 1)
  if (out == "hook") emit_hook(); else emit_rows()
}
function md_main(   i, s, fence, k, n, r, e) {
  fence = 0
  for (i = 1; i <= NL; i++) {
    s = L[i]
    if (s ~ /^[ \t]*(```|~~~)/) { fence = !fence; continue }
    if (tolower(s) !~ /godot/) continue
    if (fence) { parse(s, i, 1); continue }
    n = length(s); k = 1
    while (k <= n) {
      if (substr(s, k, 1) != "`") { k++; continue }
      r = 0; while (substr(s, k + r, 1) == "`") r++
      e = close_run(s, k + r, r)
      if (e == 0) { k += r; continue }
      parse(substr(s, k + r, e - k - r), i, k + r)
      k = e + r
    }
  }
  if (out == "rewrite") emit_rewrite(); else emit_rows()
}
# close_run S FROM R — where the next run of exactly R backticks starts, 0 if none.
function close_run(s, from, r,   n, k, m) {
  n = length(s); k = from
  while (k <= n) {
    if (substr(s, k, 1) != "`") { k++; continue }
    m = 0; while (substr(s, k + m, 1) == "`") m++
    if (m == r) return k
    k += m
  }
  return 0
}
# parse CMD LN COL — split one command text (its first byte is column COL of
# input line LN) into simple commands and check each.
function parse(cmd, ln, col,   n, k, c, q, e, d, hs, h, line, nh) {
  CMD = cmd; CLN = ln; CCOL = col
  n = length(cmd); q = ""; cur = ""; inw = 0; nw = 0; nh = 0
  for (k = 1; k <= n; k++) {
    c = substr(cmd, k, 1)
    if (q == "\047") { if (c == "\047") q = ""; else cur = cur c; we_ = k; continue }
    if (q == "\"") {
      if (c == "\\" && k < n) { k++; cur = cur substr(cmd, k, 1); we_ = k; continue }
      if (c == "\"") q = ""; else cur = cur c
      we_ = k; continue
    }
    if (c == "\\" && k < n) { if (!inw) ws_ = k; k++; cur = cur substr(cmd, k, 1); inw = 1; we_ = k; continue }
    if (c == "\047" || c == "\"") { if (!inw) ws_ = k; q = c; inw = 1; we_ = k; continue }
    if (c == "#" && !inw) { e = index(substr(cmd, k), "\n"); if (e == 0) break; k += e - 2; continue }
    if (c == "<" && substr(cmd, k + 1, 1) == "<" && substr(cmd, k + 2, 1) != "<") {
      k += 2; hs = 0
      if (substr(cmd, k, 1) == "-") { hs = 1; k++ }
      while (substr(cmd, k, 1) == " " || substr(cmd, k, 1) == "\t") k++
      d = ""
      while (k <= n) {
        c = substr(cmd, k, 1)
        if (c == " " || c == "\t" || c == "\n" || c == ";" || c == "&" || c == "|" || c == "(" || c == ")" || c == "<" || c == ">") break
        if (c != "\047" && c != "\"" && c != "\\") d = d c
        k++
      }
      k--; nh++; hd[nh] = d; hstrip[nh] = hs; flush(); continue
    }
    if (c == "\n" && nh > 0) {
      endcmd()
      for (h = 1; h <= nh; h++) {
        for (;;) {
          if (k >= n) break
          e = index(substr(cmd, k + 1), "\n")
          if (e == 0) { line = substr(cmd, k + 1); k = n } else { line = substr(cmd, k + 1, e - 1); k += e }
          if (hstrip[h]) sub(/^\t+/, "", line)
          if (line == hd[h]) break
        }
      }
      nh = 0; continue
    }
    # #66: >& <& &> &>> are redirections (2>&1), part of the word.
    if (c == "&" && (substr(cmd, k - 1, 1) == ">" || substr(cmd, k - 1, 1) == "<" || substr(cmd, k + 1, 1) == ">")) {
      if (!inw) ws_ = k; cur = cur c; inw = 1; we_ = k; continue
    }
    if (c == ";" || c == "&" || c == "|" || c == "\n" || c == "(" || c == ")") { endcmd(); continue }
    if (c == " " || c == "\t") { flush(); continue }
    if (!inw) ws_ = k
    cur = cur c; inw = 1; we_ = k
  }
  endcmd()
}
function flush() { if (inw) { nw++; w[nw] = cur; wsp[nw] = ws_; wep[nw] = we_ }; cur = ""; inw = 0 }
function endcmd() { flush(); if (nw) check(); nw = 0 }
function check(   i, j, t, b, hp, ok, cc, dd, v, pre) {
  i = 1
  while (i <= nw) {
    t = w[i]
    if (t ~ /^[A-Za-z_][A-Za-z0-9_]*=/ || t == "!" || t == "{" || t == "if" || t == "then" || t == "else" || t == "elif" || t == "do" || t == "while" || t == "until") { i++; continue }
    if (t == "env") { i++; while (i <= nw && (w[i] ~ /^-/ || w[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/)) { if (w[i] == "-u") i++; i++ }; continue }
    if (t == "exec" || t == "command" || t == "time" || t == "nohup") { i++; while (i <= nw && w[i] ~ /^-/) i++; continue }
    if (t == "nice") { i++; if (w[i] == "-n") i += 2; else while (i <= nw && w[i] ~ /^-/) i++; continue }
    if (t == "timeout" || t == "gtimeout") { i++; while (i <= nw && w[i] ~ /^-/) { if (w[i] == "-s" || w[i] == "-k") i++; i++ }; i++; continue }
    break
  }
  if (i > nw) return
  b = w[i]; sub(/.*\//, "", b); b = tolower(b)
  if (b !~ /^godot/ && w[i] !~ /^\$\{?(GODOT|GODOT_PATH|GODOT_BIN)\}?$/) return
  hp = 0; ok = 0; cc = 0; dd = 0; v = ""
  for (j = i + 1; j <= nw; j++) {
    t = w[j]
    if (t ~ /gut_cmdln/) v = "b"
    if (t == "--") dd = 1
    if (!dd && (t == "-s" || t == "--script" || t ~ /^--script=/ || t == "--import")) cc = 1
    if (t == "--headless" || t == "--path" || t ~ /^--path=/) hp = 1
    if (t == "-s" || t == "--script" || t == "--import" || t == "-e" || t == "--editor" || t ~ /^--export/ || t == "--version" || t == "--doctool" || t == "--quit" || t == "--quit-after" || t == "--help" || t == "-h") ok = 1
  }
  if (v == "" && cc) v = "c"
  if (v == "" && hp && !ok) v = "a"
  if (v == "") return
  NS++; SV[NS] = v
  SC[NS] = CCOL + wsp[i] - 1
  ST[NS] = substr(CMD, wsp[i], wep[nw] - wsp[i] + 1)
  pre = substr(CMD, 1, wsp[i] - 1); SL[NS] = CLN + gsub(/\n/, "", pre)
}
function emit_rows(   j, s) {
  for (j = 1; j <= NS; j++) { s = ST[j]; gsub(/[\n\r]/, " ", s); print SL[j] "\t" SV[j] "\t" s }
}
function emit_hook(   j, hb, hc, ha, seg) {
  hb = 0; hc = 0; ha = 0; seg = ""
  for (j = 1; j <= NS; j++) {
    if (SV[j] == "b") hb = 1
    else if (SV[j] == "a") ha = 1
    else if (!hc) { hc = 1; seg = ST[j] }
  }
  if (!(hb || hc || ha)) return
  print (hb ? "b" : "") (hc ? "c" : "") (ha ? "a" : "")
  print jesc(cut(seg, 400))
}
# cut S N — S cut to N bytes, backing off to a UTF-8 character boundary, "…" appended when cut.
function cut(s, n,   k) {
  if (length(s) <= n) return s
  k = n; while (k > 0 && (substr(s, k + 1, 1) in CONT)) k--
  return substr(s, 1, k) "\342\200\246"
}
# jesc S — S as JSON string content: \ " and control characters escaped.
function jesc(s,   o, i, n, c) {
  o = ""; n = length(s)
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (c == "\\" || c == "\"") o = o "\\" c
    else if (c in CTL) o = o CTL[c]
    else o = o c
  }
  return o
}
function emit_rewrite(   i, j, s, p, o) {
  j = 1
  for (i = 1; i <= NL; i++) {
    s = L[i]; o = ""; p = 1
    while (j <= NS && SL[j] == i) {
      if (SV[j] == "c") { o = o substr(s, p, SC[j] - p) "studio-gate godot -- "; p = SC[j] }
      j++
    }
    printf "%s", o substr(s, p)
    if (i < NL || !nonl) printf "\n"
  }
}
