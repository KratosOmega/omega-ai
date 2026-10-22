# S3 Guard: gate-script bypass, shell indirection, #67 items Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Godot guard also denies a bare run of the project's `gate_command` script (verdict `g`), follows `sh -c`, double-quoted `$(…)` and backticks, and the #67 small items land in the hook, the detector's md mode, `studio-brief` and the runner.
**Architecture:** `hooks/godot-guard.sh` reads `gate_command` once (one `git rev-parse`, one `sed`), passes the guarded script to `bin/godot-cmd.awk` as `-v gs=`. The awk gains a `g` verdict (first-word model, json mode only) and a queue of nested texts that `json_main` drains after the outer text (depth cap 3). md mode gets four parser fixes. `studio-brief` follows symlinks for itself and its target. The runner gets three one-line fixes plus comments.
**Tech Stack:** POSIX sh (dash-clean), awk, python3 where already used (only for the latency probe, never committed).
**Spec:** docs/game-dev/specs/2026-10-21-backlog-sweep.md §6 (with §1-3, §11-13)
**Story branch:** `issue-60-gate-bypass-guard` off integration/backlog-2026-10-21

Paths: `S` = `studios/game-dev`. `AWK` = `S/bin/godot-cmd.awk`, `HOOK` = `S/hooks/godot-guard.sh`, `BRIEF` = `S/bin/studio-brief`, `O` = `S/bin/studio-overnight`, `L` = `S/bin/overnight-lanes.sh`, `HT` = `tests/hook_test.sh`, `BT` = `tests/studio_brief_test.sh`, `OT` = `tests/overnight_test.sh`, `T` = `tests/overnight_lanes_test.sh`. The spec writes `hooks/…` and `bin/…` without the `studios/game-dev/` prefix (see Falsified assumptions, row 1). Line numbers are at 1cfca7f. Relocate each by its `grep -n` anchor before editing, because S2 merges first.

**Run template.** `$WT` is the story worktree and `$SCR` an existing scratch dir outside every repo:
`mkdir -p "$SCR/tmp" && cd "$SCR" && TMPDIR="$SCR/tmp" TESTS_ONLY="<names>" sh "$WT/tests/<suite>.sh"`. Then run the same line with `dash` in place of `sh`, because every suite is in the dash set (run_all.sh:21 `TEST_SH`). Run heavy suites (OT, T) as one background run and wait for its notification.

**Commit trailer** (every commit message ends with):
```
Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01HHd9n1KiKNE9YBptbSEgPL
```

## Global Constraints

- POSIX sh only, clean under dash (`TEST_SH=dash`). No bashisms, no `local`, no `$BASHPID`.
- awk runs under macOS awk (one-true-awk) and gawk, always `LC_ALL=C`. No `{n}` regex intervals.
- The hook exits 0 on every path. It uses no jq, no python and no lib/ (HOOK:17-19 `trap 'exit 0' EXIT`).
- A1: with `gate_command` unset, no `g` verdict ever fires. Ruled exceptions: the `sh -c` / `"$(…)"` / backtick recursion (G5), the c retry's `(keep any cd/env before it)` suffix, and the four md parser fixes (#67).
- `gate_command` sources, first non-empty value wins: `<git top>/.studio/config.json`, then `$STUDIO_START_DIR/.studio/config.json`, then the main worktree's (`dirname` of `git rev-parse --path-format=absolute --git-common-dir`).
- G is the first word, or the first non-`-` word after `sh|bash|zsh|dash`. Quotes are removed. G is guarded only when it contains `/` or ends in `.sh`.
- Matching and recursion run in json mode only. md mode and `out=rewrite` are unchanged by T2 and T3.
- Recursion depth cap 3. Deeper texts are ignored (fail open).
- Hook out=hook lines: 1 = verdicts in the order `b c g a`; 2 = the first c segment; 3 = the first g segment (printed only when there is a g). Both segments are cut to 400 bytes and JSON-escaped.
- g message, exact: ``game-dev: refused a direct run of the project's gate script `<G>` (gate_command): outside the gate it skips the lock, the run cap and gate.times, and status shows the gate free while it runs. Run the suite with studio-test, one file with studio-test --file <tests/unit/x.gd>, or the project gate as studio-gate <who> -- <segment> (keep any cd/env before it).``
- Fail open: a missing config, an unreadable file, `git` failing, an empty or unguarded G, or an awk error each gives no `g` and no output. Godot verdicts keep their own paths.
- Hook latency budget: +15 ms median over 100 calls, measured before and after, recorded in the PR.
- No phoenix change (A3). No reinstall. Landing is mode 2.
- Floors are exact after S2. Run `sh tests/run_all.sh --update-floors` after the rebase (Task 7).

## Review Focus

1. **An unsafe gate_command value.** For example `./x$y.sh` or `./a\b.sh`, or a value whose G holds a quote. G must be unguarded (a charset check), so `-v gs=` never decodes escapes and the deny JSON stays valid. Pin: T2 `test_guard_gate_unsafe_value`.
2. **Shell options that take an argument, or long options.** For example `bash -o pipefail G`, `sh -eo pipefail G`, `bash --norc G` and `bash --norc -c '…'`. `-o` consumes a word. `--long` is neither `-c` nor `-n`. Pin: T3 `test_guard_shell_options`.
3. **Quotes and parens inside `"$(…)"`.** For example `echo "$(echo ")")"; Godot --version` must stay allowed, `echo "$(cd x && (godot -s "a b.gd"))"; ls` is `c`, and an unbalanced `"$(godot -s a.gd` is allowed and exits 0. Pin: inside T3 `test_guard_quoted_subst_and_backticks`.
4. **Hook cwd edge cases.** These are a non-repo cwd, a linked worktree, and a path with a space. Pin: T2 `test_guard_gate_command_sources` (fixture dirs are named `gs <x>`) and `test_guard_gate_fail_open`.
5. **A CRLF brief's heredoc.** In `cat <<Q\r` … `Q\r`, the delimiter and its line both keep `\r` and still match. An unclosed heredoc runs to the fence's end and swallows nothing past it. Pin: T4 `test_godot_cmd_md_fence_heredoc`.

## Waves

Wave A: T1, T5, T6 in parallel (disjoint files). Then T2 → T3 → T4 (all in AWK; T4 also edits BT, after T5). T7 last.
**Risky** (per-task Opus review): T2, T3 (the hook on every call; spec §11). **Mechanical** (final review): T1, T4, T5, T6, T7.

---

### Task 1: Hook basics — stdin first, `\b \f \u00XX`, retry suffix — Mechanical

**Files:**
- `HOOK:19-29`: the stdin read moves before the det check; the `_c` text gains a suffix.
- `AWK:63-74`: `unesc`.
- `HT:874-887` (`godot_guard`, `gg_c`), `HT:947`, `HT:983`, and the run_tests list at `HT:1235-1258`.

**Interfaces:** Consumes the JSON escapes in a payload. Produces `unesc(s)`, which decodes `\b`→`\010`, `\f`→`\014`, and `\u0001`-`\u007f`→ that byte. Every other `\uXXXX` (including `\u0000`) is kept literally as six bytes. The new `_c` reads `…Run it as: studio-gate godot -- $seg (keep any cd/env before it)`. A new helper var is `DET_AWK="$STUDIO_DIR/bin/godot-cmd.awk"` in HT.

- [ ] **Step 1: Failing tests** (HT, after `test_godot_guard_never_blocks_on_bad_input`; add both to run_tests):
```sh
test_guard_reads_stdin_without_detector() {
  mkdir -p "$TMP/nodet2/hooks"; cp "$GODOT_GUARD" "$TMP/nodet2/hooks/godot-guard.sh"
  awk 'BEGIN { printf "{\"tool_input\":{\"command\":\""; for (i = 0; i < 20000; i++) printf "echo abcdefgh; "; print "\"}}" }' > "$TMP/big.in"
  { cat "$TMP/big.in"; echo "$?" > "$TMP/big.st"; } | sh "$TMP/nodet2/hooks/godot-guard.sh" > "$TMP/ap.out" 2>&1
  assert_eq 0 "$(cat "$TMP/big.st")" "a 300 KB payload is read whole before the no-detector exit (no SIGPIPE)"
  assert_allowed "and the call is allowed"
}
_ue() { printf '%s' "$1" | LC_ALL=C awk -v mode=json -f "$DET_AWK"; }
test_guard_unesc_bf_u() {
  assert_eq "$(printf '1\tc\tgodot -s a.gd')" "$(_ue '{"command":"\u0067odot -s a.gd"}')" "\\u00XX decodes to its byte"
  assert_eq "$(printf '1\tc\tGodot -s a\010b\014c')" "$(_ue '{"command":"Godot -s a\bb\fc"}')" "\\b and \\f decode to BS and FF"
  assert_eq "$(printf '1\tc\tGodot -s \\u4e2d\\u0000')" "$(_ue '{"command":"Godot -s \u4e2d\u0000"}')" "a non-ASCII or NUL \\u stays literal"
  godot_guard '{"command":"Godot -s \u0022a b.gd\u0022"}'; assert_denied "a \\u0022 quote is a quote"
  TESTS_RUN=$((TESTS_RUN + 1)); if json_ok "$TMP/ap.out"; then _pass "valid JSON"; else _fail "valid JSON"; fi
}
```
Update the retry assertions to the suffix:
- `gg_c` (HT:886): `"Run it as: studio-gate godot -- $2 (keep any cd/env before it)\\\\n"`;
- HT:947: `'… --import . (keep any cd/env before it)\\ngame-dev: refused a raw headless'`;
- HT:983: `'… (keep any cd/env before it)\\nRun a test file'`.

Make `godot_guard` hermetic: `( cd "$TMP" && sh "$GODOT_GUARD" ) < "$TMP/gg.in" …`, so no ambient `.studio/config.json` is read after T2.
- [ ] **Step 2: Run, expect FAIL.** Run the template with `TESTS_ONLY="test_guard_reads_stdin_without_detector test_guard_unesc_bf_u test_godot_guard_refuses_script_import test_godot_guard_message_is_valid_json test_godot_guard_redirections"` on HT. Expect the stdin test's status to be 141 or 1, the `\b`/`\u` rows to be wrong, and no suffix.
- [ ] **Step 3: Implement.**
  - HOOK: `input="$(cat …)"` goes first, then `det=…`, then `[ -f "$det" ] || exit 0`.
  - Add the suffix to `_c`.
  - Update the header comment, lines 2-18: "reads all of stdin first".
  - `unesc`: add the `b`, `f` and `u` branches. Use a hex helper `hex2(h)` that returns `index("0123456789abcdef", tolower(c)) - 1` per digit. Emit `sprintf("%c", n)` only for `1 <= n <= 127`; otherwise emit `"\\u" XXXX` unchanged and skip 4.
- [ ] **Step 4: Run, expect PASS** (same names, sh and dash), then the whole HT.
- [ ] **Step 5: Commit** `godot-guard: read stdin first, decode \b \f \u00XX, retry keeps cd/env (#67)`.

---

### Task 2: Verdict `g` — a bare run of the gate_command script (#60) — Risky

**Files:**
- `HOOK:20-37` (`gate_script`, `-v gs`, the `g` sentence, line 3).
- AWK: header `:1-49` (`gs`, `g`, line 3); `BEGIN :50-56` (`GB`); `json_main :75-85` (early return); `check :222-254` (`shell_first`, `is_g`, `add_seg`; the NS recording at :248-253 moves into `add_seg`); `emit_hook :266-276`.
- HT: tests and helpers after the godot_guard block (≈:1090), plus run_tests. `README.md:149-168` (one sentence in the gate-lock bullet) and `README.md:389` (tree line).

**Interfaces:** Consumes `gate_command` (`S/bin/studio-setup:66-69,87` flat-string read) and `STUDIO_START_DIR`. Produces hook global `G` (empty = unguarded); awk var `gs` → global `GB` (basename); verdict `g`; out=hook line 3; awk `is_g(x)`, `shell_first(i)`, `add_seg(v, i)`. T3 extends `shell_first` (enqueue).

- [ ] **Step 1: Failing tests** (HT). Helpers first:
```sh
# gs_proj NAME VALUE — a git repo "$TMP/gs NAME" whose .studio/config.json sets gate_command; sets GQ (physical).
gs_proj() { GQ="$TMP/gs $1"; mkdir -p "$GQ/.studio" "$GQ/.github/scripts"; ( cd "$GQ" && git init -q ) >/dev/null 2>&1
  printf '{\n  "gate_command": "%s"\n}\n' "$2" > "$GQ/.studio/config.json"; GQ="$(cd "$GQ" && pwd -P)"; }
# gs_guard DIR JSON_CMD [START_DIR] — the guard with cwd DIR (and STUDIO_START_DIR); exit 0 asserted; stdout $TMP/ap.out.
gs_guard() { ptu_in Bash "{\"command\":\"$2\"}" > "$TMP/gg.in"; _gst=0
  ( cd "$1" || exit 9; [ -z "${3:-}" ] || { STUDIO_START_DIR="$3"; export STUDIO_START_DIR; }; sh "$GODOT_GUARD" ) \
    < "$TMP/gg.in" > "$TMP/ap.out" 2> "$TMP/ap.err" || _gst=$?
  assert_eq 0 "$_gst" "the Godot guard exits 0"; }
# assert_g_denied MSG [SEGMENT_BRE] — a g deny naming the alternatives (and the retry segment), valid JSON, quiet stderr.
assert_g_denied() { assert_denied "$1"
  assert_contains "$TMP/ap.out" "refused a direct run of the project's gate script" "$1: the g sentence"
  assert_contains "$TMP/ap.out" 'studio-test --file' "$1: names studio-test --file"
  assert_contains "$TMP/ap.out" 'studio-gate <who> -- ' "$1: names studio-gate"
  [ -z "${2:-}" ] || assert_contains "$TMP/ap.out" "studio-gate <who> -- $2 (keep any cd/env before it)\." "$1: the retry is the segment"
  TESTS_RUN=$((TESTS_RUN + 1)); if json_ok "$TMP/ap.out"; then _pass "$1: valid JSON"; else _fail "$1: valid JSON"; fi
  assert_eq "" "$(cat "$TMP/ap.err")" "$1: nothing on stderr"; }
```
Tests:
- `test_guard_gate_script_denied`: `gs_proj d .github/scripts/run-tests.sh`, then:
  - in `$GQ`: `'.github/scripts/run-tests.sh > /tmp/g.log 2>&1; echo $?'` → `assert_g_denied … '\.github/scripts/run-tests\.sh > /tmp/g\.log 2>&1'`;
  - `'sh .github/scripts/run-tests.sh'` → segment `'sh \.github/scripts/run-tests\.sh'`;
  - in `$GQ/.github/scripts`: `'./run-tests.sh'`, `'bash run-tests.sh'` and `'. run-tests.sh'` are each g;
  - `'cd x && env A=1 timeout 60 .github/scripts/run-tests.sh | tail -5'` → segment `'\.github/scripts/run-tests\.sh'`, with the wrappers dropped and the pipe outside;
  - order: `'Godot --import . ; .github/scripts/run-tests.sh'` contains `'(keep any cd/env before it)\\ngame-dev: refused a direct run'`;
  - `'.github/scripts/run-tests.sh; Godot --path .'` contains `'while it runs\..*\\ngame-dev: refused a raw headless'`.
- `test_guard_gate_script_allowed`: in `$GQ`, each of these is `assert_allowed`:
  - `'studio-gate t -- .github/scripts/run-tests.sh'`, `'studio-setup gate'`, `'studio-test'`;
  - `'cat .github/scripts/run-tests.sh'`, `'grep x .github/scripts/run-tests.sh'`, `'bash -n .github/scripts/run-tests.sh'`, `'vim .github/scripts/run-tests.sh'`;
  - `'echo run-tests.sh'`, `'ls .github/scripts'`.
- `test_guard_gate_command_sources`:
  - `gs_proj top scripts/top.sh` and `gs_proj start scripts/start.sh`;
  - (1) `scripts/top.sh` in TOP is g;
  - `scripts/start.sh` in TOP with START=start is allowed (the tree wins);
  - (2) a configless repo `"$TMP/gs plain"` with START=start: `scripts/start.sh` is g;
  - (3) `gs_proj main scripts/main.sh`, commit once, `git worktree add -q "$TMP/gs wt"` (the config is untracked, so it is absent in the worktree): `scripts/main.sh` from `"$TMP/gs wt"` is g;
  - an empty top value (`""`) falls through to START;
  - values `npm test`, `make check` and `studio-test` deny nothing (`npm test`, `npm run x` and `make check` are allowed);
  - minified `{"engine":"godot4","gate_command":"sh -x ./ci.sh"}`: both `./ci.sh` and `sh -x ./ci.sh` are g.
- `test_guard_gate_fail_open`:
  - `chmod 000` config → allowed, empty stderr (restore 644);
  - a non-repo dir `"$TMP/gs nogit"` holding a config, with no START → allowed;
  - PATH without git: a dir of links to `awk sed cat dirname`, run as `( cd "$GQ" && PATH="$TMP/gs-path" "$(command -v sh)" "$GODOT_GUARD" )`. The G call is allowed, and `Godot --headless --import .` is still denied as c;
  - `"gate_command": ""` → allowed.
- `test_guard_gate_unsafe_value` (Review Focus 1): for each config value `./x$y.sh`, `./a\\b.sh` (the JSON text holds a backslash; sed does not decode it) and `'./q.sh'`:
  - the first two are unguarded (charset check): running the value's own path is allowed, and `Godot --import .` beside it still gives valid JSON;
  - `'./q.sh'` has its quotes removed, so `./q.sh` is g;
  - each output is valid JSON or empty.
- [ ] **Step 2: Run, expect FAIL** (the five names, HT): no g.
- [ ] **Step 3: Implement.** Hook, full (the hard part):
```sh
# gate_script — set G to the project's guarded gate script (spec §6.1), else empty.
# First non-empty gate_command of: <git top>, $STUDIO_START_DIR, the main worktree.
# One git rev-parse, one sed; any failure leaves G empty (fail open).
gate_script() {
  G=""; _gs_cd=""; set --
  if _gs_r="$(git rev-parse --path-format=absolute --show-toplevel --git-common-dir 2>/dev/null)"; then
    _gs_top="${_gs_r%%
*}"; _gs_cd="${_gs_r#*
}"
    [ ! -r "$_gs_top/.studio/config.json" ] || set -- "$_gs_top/.studio/config.json"
  fi
  [ -z "${STUDIO_START_DIR:-}" ] || [ ! -r "$STUDIO_START_DIR/.studio/config.json" ] || set -- "$@" "$STUDIO_START_DIR/.studio/config.json"
  [ -z "$_gs_cd" ] || [ ! -r "${_gs_cd%/*}/.studio/config.json" ] || set -- "$@" "${_gs_cd%/*}/.studio/config.json"
  [ "$#" -gt 0 ] || return 0
  _gs_v="$(sed -n -e '/"gate_command"[[:space:]]*:[[:space:]]*"[^"]/{' \
    -e 's/.*"gate_command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' -e 'q' -e '}' "$@" 2>/dev/null)" || return 0
  set -f; set -- $_gs_v; set +f
  case "${1:-}" in sh|bash|zsh|dash|*/sh|*/bash|*/zsh|*/dash)
    shift; while [ "$#" -gt 0 ] && [ "${1#-}" != "$1" ]; do shift; done ;; esac
  _gs_g="${1:-}"
  case "$_gs_g" in \'*\') _gs_g="${_gs_g#\'}"; _gs_g="${_gs_g%\'}" ;; esac
  case "$_gs_g" in ''|*[!A-Za-z0-9._/+-]*) return 0 ;; esac
  case "$_gs_g" in */*|*.sh) G="$_gs_g" ;; esac
}
```
Call `gate_script` after `[ -n "$input" ]` (bad input costs no git). Then:
- add `-v gs="$G"` to the awk call;
- `gseg="$(printf '%s\n' "$out" | sed -n 3p)"`, run only when `cls` holds g;
- add the `_g` sentence (the exact text in Global Constraints, `<G>` = `\`$G\``, `<segment>` = `$gseg`);
- insert `case "$cls" in *g*) msg="${msg:+$msg\\n}$_g" ;; esac` between the c and a cases.

awk, full for the verdict:
```awk
# BEGIN:  GB = gs; sub(/.*\//, "", GB)
# json_main: if (tolower(cmd) !~ /godot/ && (GB == "" || !index(cmd, GB))) return
function is_g(x) { sub(/.*\//, "", x); return GB != "" && x == GB }
# add_seg V I — record verdict V for the simple command from word I (the old :248-253 body).
# shell_first I — 1 when word I is a shell, . or source (verdict g recorded when it runs G). T3 adds the -c enqueue.
function shell_first(i,   b, j, t, sc, sn) {
  b = w[i]; sub(/.*\//, "", b)
  if (b == "." || b == "source") { if (i < nw && is_g(w[i + 1])) add_seg("g", i); return 1 }
  if (b != "sh" && b != "bash" && b != "zsh" && b != "dash") return 0
  sc = 0; sn = 0
  for (j = i + 1; j <= nw; j++) {
    t = w[j]
    if (t == "--") { j++; break }
    if (t !~ /^[-+]./) break
    if (t ~ /^-[^-]*c/) sc = 1
    if (t ~ /^-[^-]*n/) sn = 1
    if (t ~ /^[-+][^-]*o$/) j++          # -o NAME, -eo NAME, +o NAME
  }
  if (sc) return 1                        # T3: enqueue(w[j]) when j <= nw
  if (!sn && j <= nw && is_g(w[j])) add_seg("g", i)
  return 1
}
# check(), after `if (i > nw) return`:
#   if (mode == "json") { if (shell_first(i)) return; if (is_g(w[i])) { add_seg("g", i); return } }
```
`emit_hook`:
- add `hg`/`gseg`, with `else if (SV[j] == "g") { if (!hg) { hg = 1; gseg = ST[j] } }` before the c branch;
- line 1 is `(hb?"b":"") (hc?"c":"") (hg?"g":"") (ha?"a":"")`;
- line 2 is unchanged;
- `if (hg) print jesc(cut(gseg, 400))`.

The early-return condition has to include `!(hb||hc||hg||ha)`.

Docs:
- the AWK header: the `gs` var, verdict `g`, out=hook line 3;
- the HOOK header: verdict (g);
- README:149-168: append "The `godot-guard.sh` hook also denies a bare run of the script named by the project's `gate_command` (directly, or as `sh|bash <it>` / `. <it>`), since it would skip the lock; run it through `studio-test`, `studio-setup gate` or `studio-gate <who> -- …`.";
- README:389: "the Godot and gate-script command detector".
- [ ] **Step 4: Run, expect PASS.** The five names under sh and dash, then the whole HT, then `TESTS_ONLY= sh tests/studio_brief_test.sh` (md unchanged).
- [ ] **Step 5: Measure, before vs after.** `git show 1cfca7f:$S/hooks/godot-guard.sh` and `…/bin/godot-cmd.awk` go into `$SCR/old/{hooks,bin}`. Time 100 runs of each hook on `{"tool_input":{"command":"ls -la"}}`, with cwd a `gs_proj`-style repo that has a guarded config (the worst case: git and sed both run). Use a python3 `subprocess`/`time.perf_counter` loop in `$SCR`. Record the median delta in `$SCR/s3-latency.txt` (≤ +15 ms, else profile before T3).
- [ ] **Step 6: Commit** `godot-guard: deny a bare run of the gate_command script (verdict g) (#60)`.

---

### Task 3: Follow `sh -c`, `"$(…)"` and backticks, depth 3 (#63 item 3) — Risky

**Files:** AWK `json_main :75-85` (the drain), `parse :167-219` (json-only recording in the `q == "\""` branch :175-179 and before :181), T2's `shell_first`, the header; HT tests + run_tests.

**Interfaces:** Produces globals `DEPTH NQ QT[] QD[]`; `enqueue(t)`; `subst_end(s, from)` (index of the `)` closing a `$(` whose body starts at `from`, else 0); `tick_end(s, from)` (index of the closing backtick, else 0). Nested segments come from the nested text, so the c and g retries name the inner segment.

- [ ] **Step 1: Failing tests** (HT):
```sh
_wrap() { printf "sh -c '%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
_jstr() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
test_guard_sh_c_recursion() {
  gg_c 'sh -c \"godot -s a.gd\"' 'godot -s a.gd'
  gg_c "bash -lc 'godot --import'" 'godot --import'
  gg_c "sh -c \\\"sh -c 'godot -s x'\\\"" 'godot -s x'
  godot_guard "{\"command\":\"studio-gate x -- sh -c 'godot -s a.gd'\"}"; assert_allowed "a shell under studio-gate is the gate's"
  _d3="$(_wrap "$(_wrap "$(_wrap 'godot -s x')")")"; _d4="$(_wrap "$_d3")"
  godot_guard "{\"command\":\"$(_jstr "$_d3")\"}"; assert_denied "depth 3 is followed"
  assert_contains "$TMP/ap.out" 'studio-gate godot -- godot -s x (keep' "the retry is the innermost segment"
  godot_guard "{\"command\":\"$(_jstr "$_d4")\"}"; assert_allowed "depth 4 is ignored (fail open)"
  gs_proj rc .github/scripts/run-tests.sh
  gs_guard "$GQ" 'sh -c \".github/scripts/run-tests.sh > /tmp/x 2>&1\"'; assert_g_denied "G inside sh -c" '\.github/scripts/run-tests\.sh > /tmp/x 2>&1'
  gs_guard "$GQ" 'echo \"$(.github/scripts/run-tests.sh)\"'; assert_g_denied "G inside \"\$(…)\""
}
test_guard_quoted_subst_and_backticks() {
  gg_c 'echo \"$(godot -s a.gd)\"' 'godot -s a.gd'
  gg_c 'echo `godot -s a.gd`' 'godot -s a.gd'
  gg_c 'x=\"`godot --import`\"' 'godot --import'
  gg_c 'x=$(godot -s a.gd)' 'godot -s a.gd'      # unquoted: the existing ( split, unchanged
  godot_guard '{"command":"echo \"$(cd x && (godot -s \"a b.gd\"))\"; ls"}'; assert_denied "nested parens and quotes in \"\$(…)\""
  for c in 'echo \"$(echo \")\")\"; Godot --version' 'echo \"$((godot))\"' "echo '\$(godot -s a.gd)' '\`godot -s a.gd\`'" \
           'echo \"$(godot -s a.gd' 'echo `godot -s a.gd'; do
    godot_guard "{\"command\":\"$c\"}"; assert_allowed "allowed: $c"; done
}
test_guard_shell_options() {   # Review Focus 2
  gg_c 'bash --norc -c \"godot -s a.gd\"' 'godot -s a.gd'
  gg_c 'sh -e -x -c \"godot --import\"' 'godot --import'
  gs_proj so .github/scripts/run-tests.sh
  for c in 'bash -o pipefail .github/scripts/run-tests.sh' 'sh -eo pipefail .github/scripts/run-tests.sh' 'bash --norc .github/scripts/run-tests.sh' '/bin/sh -- .github/scripts/run-tests.sh'; do
    gs_guard "$GQ" "$c"; assert_g_denied "g: $c"; done
  gs_guard "$GQ" 'sh -n -x .github/scripts/run-tests.sh'; assert_allowed "a syntax check is not a run"
}
test_guard_md_mode_unchanged() {
  printf '```sh\nsh -c "godot -s a.gd"\necho "$(godot -s a.gd)" `godot --import`\n.github/scripts/run-tests.sh\n```\nRun `bash -lc '"'"'godot --import'"'"'` here.\n' > "$TMP/mdu.md"
  assert_eq "" "$(LC_ALL=C awk -v mode=md -v gs=.github/scripts/run-tests.sh -f "$DET_AWK" "$TMP/mdu.md")" "md rows: no nesting, no g"
  LC_ALL=C awk -v mode=md -v out=rewrite -v gs=x.sh -f "$DET_AWK" "$TMP/mdu.md" > "$TMP/mdu.out"
  TESTS_RUN=$((TESTS_RUN + 1)); if cmp -s "$TMP/mdu.md" "$TMP/mdu.out"; then _pass "md rewrite byte-identical"; else _fail "md rewrite byte-identical"; fi
}
```
- [ ] **Step 2: Run, expect FAIL** (the four names): `"$(…)"`, backticks and `sh -c` are allowed today.
- [ ] **Step 3: Implement** (json mode only; every branch is guarded by `mode == "json"`):
```awk
function enqueue(t) { if (DEPTH < 3 && t ~ /[^ \t\n]/) { NQ++; QT[NQ] = t; QD[NQ] = DEPTH + 1 } }
function subst_end(s, from,   n, k, c, q, d) {
  n = length(s); q = ""; d = 1
  for (k = from; k <= n; k++) {
    c = substr(s, k, 1)
    if (q == "\047") { if (c == "\047") q = ""; continue }
    if (c == "\\") { k++; continue }
    if (q == "\"") { if (c == "\"") q = ""; continue }
    if (c == "\047" || c == "\"") { q = c; continue }
    if (c == "(") d++
    else if (c == ")" && --d == 0) return k
  }
  return 0
}
function tick_end(s, from,   n, k, c) {
  n = length(s)
  for (k = from; k <= n; k++) { c = substr(s, k, 1); if (c == "\\") { k++; continue }; if (c == "`") return k }
  return 0
}
# json_main, after the early return:
#   DEPTH = 0; NQ = 0; parse(cmd, 1, 1)
#   for (qi = 1; qi <= NQ; qi++) if (tolower(QT[qi]) ~ /godot/ || (GB != "" && index(QT[qi], GB))) { DEPTH = QD[qi]; parse(QT[qi], 1, 1) }
```
`parse` insertions. Each one appends the whole construct to `cur`, sets `k = e` and `we_ = k`, then `continue`, so the outer quote state is never re-read from the body:
- in the `q == "\""` branch, after the `\` escape line:
  - `c == "$"`, next `(`, the one after not `(`, and `e = subst_end(cmd, k + 2)` > 0 → `enqueue(substr(cmd, k + 2, e - k - 2))`;
  - `` c == "`" `` and `e = tick_end(cmd, k + 1)` > 0 → `enqueue(substr(cmd, k + 1, e - k - 1))`;
- unquoted, before the quote-open line :181: the same backtick rule, with `if (!inw) ws_ = k; inw = 1`.

An unclosed construct falls through to today's handling (fail open). `shell_first`: `if (sc) { if (j <= nw) enqueue(w[j]); return 1 }`. Header: the recursion rules, the depth cap, and "json only".
- [ ] **Step 4: Run, expect PASS.** The four names plus T2's five, sh and dash. Then the whole HT and the whole BT (md byte-identity).
- [ ] **Step 5: Re-measure** the T2 step-5 latency on the final hook. Append the result to `$SCR/s3-latency.txt`; it goes in the PR body.
- [ ] **Step 6: Commit** `godot-guard: follow sh -c, "$(…)" and backticks to depth 3 (#63)`.

---

### Task 4: md mode — fence heredocs, `$ ` prompt, CRLF continuation, blockquote spans (#67) — Mechanical

**Files:** AWK `md_main :86-107` (fence loop :92-96, paragraph join :103), `cont :126`, `parse` md continuation `:173`, `emit_rows` md join `:260`, the header (plus N1: "a stray backtick pairs as CommonMark says; not changed"); BT tests + run_tests (after T5's BT edits).

**Interfaces:** Produces `heredocs(t)`, the delimiters `t` opens (quote-aware; `<<` not `<<<`), each prefixed `-` for `<<-` or `+`, joined by SUBSEP; "" when there are none. Every md edit keeps a command text the **same length** as its source (blanking, not deleting), so `SL`/`SC` and the rewrite columns hold.

- [ ] **Step 1: Failing tests** (BT; each checks rows and the rewrite):
  - `test_godot_cmd_md_fence_heredoc`. Input:
    ```
    printf '```sh\ncat > n.md <<EOF\nGodot --headless --script res://in-body.gd\nEOF\nGodot --import .\ncat <<-X\n\tGodot -s tabbed.gd\n\tX\ncat <<Q\r\nGodot -s crlf-body.gd\r\nQ\r\nGodot -s after-crlf.gd\n```\n```\ncat <<OPEN\nGodot -s unclosed.gd\n```\nGodot -s prose.gd\n'
    ```
    - rows want `5\tc\tGodot --import .` and `12\tc\tGodot -s after-crlf.gd`, nothing else;
    - rewrite want = the input with `studio-gate godot -- ` inserted at the start of lines 5 and 12 (`sed -e '5s/^/studio-gate godot -- /' -e '12s/^/studio-gate godot -- /'`), compared with `cmp`.
  - `test_godot_cmd_md_prompt`. Input:
    ```
    '```console\n$ Godot --headless --script res://a.gd\n  $ godot --import\nx$ Godot -s no.gd\n$Godot -s nospace.gd\n```\nRun `$ Godot -s span.gd` here.\n'
    ```
    - rows `2\tc\tGodot --headless --script res://a.gd` and `3\tc\tgodot --import`;
    - rewrite: line 2 → `$ studio-gate godot -- Godot …`, line 3 → `  $ studio-gate godot -- godot --import`, every other byte the same.
  - `test_godot_cmd_md_crlf_continuation`. Input `'```sh\r\nGodot --headless --path . \\\r\n  --script res://y.gd\r\n```\r\n'`:
    - `cut -f1,2` of the rows = `2	c` (today `2	a`);
    - field 3 matches `^Godot --headless --path \. --script res://y\.gd *$`;
    - the rewrite gates line 2 only.
  - `test_godot_cmd_md_blockquote_span`. Input `'> Run `Godot --headless --path .\n> --script res://q.gd` now.\n\n> Then `Godot --headless\n>--script res://r.gd` too.\n'`:
    - rows `1\tc\tGodot --headless --path . --script res://q.gd` (no `>`) and `4\tc\tGodot --headless --script res://r.gd` (today `4\ta`);
    - the rewrite gates lines 1 and 4; lines 2 and 5 are byte-identical.
- [ ] **Step 2: Run, expect FAIL** (the four names, BT).
- [ ] **Step 3: Implement.**
  - Order per fenced command: blank the prompt, then the `cont` join, then the heredoc join, then `parse`. Add `hds, nd, h, ln, D` to md_main's locals (not `hd`: parse uses a global `hd[]`).
  - The prompt: on each fenced command's first line, `if (match(t, /^[ \t]*\$ /)) t = substr(t, 1, RLENGTH - 2) "  " substr(t, RLENGTH + 1)`.
  - `cont`: `if (substr(s, n, 1) == "\r") n--` first.
  - parse :173: also accept `\` + `\r\n` (skip 2).
  - emit_rows :260: `/[ \t]*\\\r?\n[ \t]*/`, inserting a space when anything besides `\`, `\r` and `\n` matched.
  - The paragraph join :103: `ln = L[i]; if (match(ln, /^[ \t]*>[ ]?/)) ln = blanks(RLENGTH) substr(ln, RLENGTH + 1)`; `t = t "\n" ln`. `blanks(n)` is a loop of n spaces (no `%*s`: one-true-awk support is not assured).
  - The heredoc join, after the `cont` loop in the fence loop (full):
```awk
hds = heredocs(t)
if (hds != "") {
  nd = split(hds, D, SUBSEP)
  for (h = 1; h <= nd; h++)
    while (i < NL && !fence_close(L[i + 1])) {
      i++; t = t "\n" L[i]; ln = L[i]
      if (substr(D[h], 1, 1) == "-") sub(/^\t+/, "", ln)
      if (ln == substr(D[h], 2)) break
    }
}
function heredocs(t,   n, k, c, q, d, r, hs) {
  n = length(t); q = ""; r = ""
  for (k = 1; k <= n; k++) {
    c = substr(t, k, 1)
    if (q != "") { if (c == q) q = ""; else if (q == "\"" && c == "\\") k++; continue }
    if (c == "\\") { k++; continue }
    if (c == "\047" || c == "\"") { q = c; continue }
    if (c == "#" && (k == 1 || substr(t, k - 1, 1) ~ /[ \t;&|()]/)) break
    if (c == "<" && substr(t, k + 1, 2) == "<<") { k += 2; continue }        # here-string
    if (c != "<" || substr(t, k + 1, 1) != "<") continue
    k += 2; hs = 0; if (substr(t, k, 1) == "-") { hs = 1; k++ }
    while (substr(t, k, 1) == " " || substr(t, k, 1) == "\t") k++
    d = ""
    for (; k <= n; k++) { c = substr(t, k, 1); if (c ~ /[ \t\n;&|()<>]/) break; if (c != "\047" && c != "\"" && c != "\\") d = d c }
    k--; if (d != "") r = r (r == "" ? "" : SUBSEP) (hs ? "-" : "+") d
  }
  return r
}
```
The delimiter keeps a trailing `\r` exactly as `parse()` (:188-193) does, so a CRLF delimiter line matches (Review Focus 5). The joined text then goes through the existing `parse`, whose heredoc skip (:196-208) drops the body.
- [ ] **Step 4: Run, expect PASS.** The four names, then the whole BT and the whole HT (sh and dash).
- [ ] **Step 5: Commit** `godot-cmd md: fence heredocs, $ prompts, CRLF continuations, blockquote spans (#67)`.

---

### Task 5: studio-brief — symlinks, read-only brief, header, test order (#67) — Mechanical

**Files:** `BRIEF:44-50` (rewrite help), `:69` (HERE), `:327-343` (in-place rewrite). BT `:443-462`, `:464-480` (fixture writers → helpers), `:597` (calls them), new tests + run_tests.

**Interfaces:** Produces `resolve_link PATH`, which prints PATH with every symlink in its last component followed: the `S/bin/studio-dispatch:31-40` loop, capped at 40 hops. Also `md_ac3_fixture` (writes `$TMP/ac3.md`) and `md_edge_fixture` (writes `$TMP/edge.md` and `$TMP/edge.rw.want`). New warning, exact: `studio-brief: warning: <f> is not writable — not rewritten`, where `<f>` is the caller's `$2`, as in the other rewrite warnings.

- [ ] **Step 1: Failing tests** (BT):
```sh
test_brief_symlinked_self() {
  mkdir -p "$TMP/linkbin" "$TMP/link2"; ln -s "$BRIEF" "$TMP/linkbin/studio-brief"; ln -s ../linkbin/studio-brief "$TMP/link2/studio-brief"
  for b in "$TMP/linkbin/studio-brief" "$TMP/link2/studio-brief"; do
    printf 'x `Godot --script a.gd`\n' | sh "$b" rewrite > "$TMP/ls.out" 2> "$TMP/ls.err"
    assert_eq 'x `studio-gate godot -- Godot --script a.gd`' "$(cat "$TMP/ls.out")" "through $b: the detector is found"
    assert_eq "" "$(cat "$TMP/ls.err")" "through $b: no missing-detector warning"
  done
}
test_brief_rewrite_read_only() {
  mkdir -p "$TMP/rro"; printf 'x `Godot --script a.gd`\n' > "$TMP/rro/b.md"; cp "$TMP/rro/b.md" "$TMP/rro.orig"; chmod 444 "$TMP/rro/b.md"
  ( cd "$TMP/rro" && sh "$BRIEF" rewrite b.md ) 2> "$TMP/rro.err"; st=$?; chmod 644 "$TMP/rro/b.md"
  assert_eq 0 "$st" "a read-only brief: exit 0"
  TESTS_RUN=$((TESTS_RUN + 1)); if cmp -s "$TMP/rro.orig" "$TMP/rro/b.md"; then _pass "left untouched"; else _fail "left untouched"; fi
  assert_eq "studio-brief: warning: b.md is not writable — not rewritten" "$(cat "$TMP/rro.err")" "one exact warning"
  assert_eq "b.md" "$(ls -A "$TMP/rro")" "no temp file"
}
test_brief_rewrite_symlinked_brief() {
  mkdir -p "$TMP/rsl/real" "$TMP/rsl/links"; printf 'x `Godot --script a.gd`\n' > "$TMP/rsl/real/b.md"; ln -s ../real/b.md "$TMP/rsl/links/b.md"
  sh "$BRIEF" rewrite "$TMP/rsl/links/b.md"; st=$?
  assert_eq 0 "$st" "exit 0"; assert_symlink "$TMP/rsl/links/b.md" "the link stays a link"
  assert_eq 'x `studio-gate godot -- Godot --script a.gd`' "$(cat "$TMP/rsl/real/b.md")" "its target is rewritten"
  assert_eq "b.md" "$(ls -A "$TMP/rsl/real")" "no temp beside the target"; assert_eq "b.md" "$(ls -A "$TMP/rsl/links")" "nor beside the link"
}
```
The order fix: `md_ac3_fixture` and `md_edge_fixture` hold today's heredocs verbatim. `test_godot_cmd_md_finds_bare_forms`, `test_godot_cmd_md_span_edges` and `test_brief_rewrite_wraps_only` each call the ones they read.
- [ ] **Step 2: Run, expect FAIL.** `TESTS_ONLY="test_brief_rewrite_wraps_only"` alone fails today (no `$TMP/ac3.md`), and so do the three new tests.
- [ ] **Step 3: Implement.**
  - Add `resolve_link`, then `HERE="$(cd "$(dirname "$(resolve_link "$0")")" && pwd)"`.
  - In-place rewrite, in order: the `-f` check; `_rf="$(resolve_link "$_rf")"`; the detector check; `[ -w "$_rf" ] || { printf 'studio-brief: warning: %s is not writable — not rewritten\n' "$2" >&2; exit 0; }`; then mktemp in `dirname "$_rf"`, `cp -p`, awk, `cmp`, `mv -f` over the target (today a read-only mode copied by `cp -p` makes the awk redirect fail with a misleading "check failed").
  - Help text (:44-50): "A symlinked <file> is rewritten at its target and stays a link; a read-only <file> is left untouched with one warning." Also add "A backtick span is read as a command even in prose, so a sentence quoting a bare Godot run is gated too (accepted, #67)."
- [ ] **Step 4: Run, expect PASS.** The four names, each alone (`TESTS_ONLY` with one name), then the whole BT (sh and dash).
- [ ] **Step 5: Commit** `studio-brief: follow symlinks, warn on a read-only brief, self-contained rewrite test (#67)`.

---

### Task 6: Runner one-liners and the permission-route note tests (#67) — Mechanical

**Files:** `O:1090` (comment), `O:1481` (`deny_note`), `O:579-581` (`preflight` top), `O:466-468` (help); `L:6-8` (header list), `L:656-666` (`land_repair` header); OT new tests after `test_overnight_denied_scan` (:2437-2453) + run_tests :2673; T `test_lanes_sync_repair_stops` loop (:1758-1784) and `test_lanes_permission_route_note` (:3028-3057).

**Interfaces:** Produces the stderr warning `studio-overnight: allow file <ALLOW_FILE> missing — units get no allow rules` (`say` prefix; every `start`, `--dry-run` and manifest start, all via `preflight`, O:1661/1773/1785). An empty denied command prints `-`.

- [ ] **Step 1: Failing tests.**
```sh
test_overnight_denied_note_empty_command() {
  { printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_E","name":"Bash","input":{"command":""}}]}}'
    printf '%s\n' '{"type":"system","subtype":"permission_denied","tool_name":"Bash","tool_use_id":"toolu_E","decision_reason_type":"classifier"}'; } > "$TMP/dnempty.jsonl"
  assert_eq " [permission-route — denied: -]" "$(sh "$RUNNER" activity --denied "$TMP/dnempty.jsonl")" "an empty denied command prints -"
}
test_overnight_allow_file_missing_warns() {
  fixture allowwarn
  cp -R "$REPO_ROOT/studios/game-dev/bin" "$TMP/allowbin2"; rm -f "$TMP/allowbin2/overnight-allow.txt"
  ( cd "$P" && sh "$TMP/allowbin2/studio-overnight" start --dry-run ) > "$TMP/aw.out" 2> "$TMP/aw.err"; st=$?
  assert_eq 0 "$st" "a missing allow file is not a failure"
  assert_contains "$TMP/aw.err" '^studio-overnight: allow file .*/allowbin2/overnight-allow\.txt missing — units get no allow rules$' "it warns on stderr"
  ( cd "$P" && sh "$RUNNER" start --dry-run ) > /dev/null 2> "$TMP/aw2.err"
  assert_not_contains "$TMP/aw2.err" 'allow file' "no warning when the file exists"
}
```
T. `test_lanes_permission_route_note` gains a gate-repair stop case: `LANES_CONFIG` `gate_repairs` 1, `lanes_fixture prgs integration A:-`, `printf 'auto\nauto\nstop gate red — x\n' > "$SCEN/A"`, `printf 'emit %s; stop gate repair red — y\n' "$F" > "$SCEN/A.gate"`, `run_lanes start "$MFP"`, then `stories/A` matches `"^stopped stop: gate repair red — y$N\$"`.

`test_lanes_sync_repair_stops` gives each of its four sync scenarios an `emit $REPO_ROOT/tests/fixtures/overnight-permission-denied.jsonl;` prefix:
- the stall case becomes `emit <PRD>; emit $TMP/stl2.jsonl; hang`. The PRD goes first, so the newest open call is still `Bash: sleep 999` (O:1120 lists newest first; O:1423 takes `head -n 1`).
- Each assertion becomes `"^stopped sync repair: $_want$N\$"`, with N as in `test_lanes_permission_route_note`. This covers the stop, no-progress, timed-out and stalled endings.
- [ ] **Step 2: Run, expect FAIL.**
  - OT: `TESTS_ONLY="test_overnight_denied_note_empty_command test_overnight_allow_file_missing_warns test_overnight_denied_scan test_overnight_launch_allow_rules"` (the last one is the existing :580-617 test, whose missing-file dry run now also warns). Expect the empty test to print `denied: ]` and no warning.
  - T: `TESTS_ONLY="test_lanes_permission_route_note test_lanes_sync_repair_stops"` in the background. These two pass on the code as it is, because L already appends `$UNIT_DENY_NOTE` (L:736, 834-848). If they pass, record "coverage only" in the commit body. They are tests for untested endings, not a fix.
- [ ] **Step 3: Implement.**
  - O:1481: `"${_dn_c:--}"`.
  - O:1090: "count it and keep the id of the first one". No apostrophe: the comment sits inside open_calls' single-quoted awk program (O:1076), so `one's` would end the quote.
  - `preflight`: first line after `FAILED=0`: `[ -f "$ALLOW_FILE" ] || say "allow file $ALLOW_FILE missing — units get no allow rules"`.
  - Help :468: "no file or no rules: no --allowedTools (a missing file is warned about at start and dry run)."
  - L header :7: add `allow_rules` to the helper list. S5 may add repair helper names to the same line later; it unions them with `allow_rules` (preflight fix).
  - `land_repair` header: "Each ending carries the unit's permission-route note (#66 R5)."
- [ ] **Step 4: Run, expect PASS.** The same names, sh and dash. Then `TESTS_ONLY="test_overnight_help"` (OT:283) to show the help assertions still hold.
- [ ] **Step 5: Commit** `overnight: empty denied command prints -, warn on a missing allow file, note-ending tests (#67)`.

---

### Task 7: Rebase, affected suites, exact floors — Mechanical

**Files:** `tests/run_all.sh` (the floors table only), via S2's mechanism.

This task follows S2's "For other stories" recipe exactly (preflight fix: running the suites directly writes no counts file, so `--update-floors` would exit 2 or read stale counts).

- [ ] **Step 1:** `git fetch`, then merge the latest `origin/integration/backlog-2026-10-21` (S2 and any S6/S4 already in) into the story branch. On a floors-table conflict, take the integration branch's whole `tests/run_all.sh` (`git checkout origin/integration/backlog-2026-10-21 -- tests/run_all.sh`). Never hand-merge counts. Resolve the other shared regions per **Merge notes** below.
- [ ] **Step 2:** commit every code and test change. The tree must be clean before Step 3.
- [ ] **Step 3:** `sh tests/run_affected.sh --base origin/integration/backlog-2026-10-21 --list`. Expect HT, BT, OT, T and studio_test (README/bin reverse refs) at least. Then run them through run_all, plus `harness_test` (its exclusive scan must see no `H` row from HT/BT's quoted `<<EOF`/`<<-X`/`<<Q\r`/`<<OPEN` strings), from `$SCR` as one background run at a time:
  ```sh
  cd "$SCR" && TMPDIR="$SCR/tmp" TEST_SUITES="<the listed suites> harness_test" sh "$WT/tests/run_all.sh"
  cd "$SCR" && TMPDIR="$SCR/tmp" TEST_SUITES="<the listed suites> harness_test" TEST_SH=dash sh "$WT/tests/run_all.sh"
  ```
  - Red only with `floor` / `no floors row` lines is expected. Any other red is a real failure: fix it, commit, and redo Step 3.
  - These are partial runs: they never take the heavy-suite lock.
- [ ] **Step 4:** with no commit since Step 3's last run, `sh "$WT/tests/run_all.sh" --update-floors`. Any commit after the run means a re-run first. Then `git add tests/run_all.sh` and commit the table: `tests: floors for S3 guard (#60, #63, #67)`.
- [ ] **Step 5:** The PR body (story → integration) holds:
  - the `$SCR/s3-latency.txt` median delta;
  - the falsified rows below, re-checked at the story's base;
  - "#63 item 3 and #67 closed by this story".

### Merge notes (preflight fix)

Shared regions with other stories, and how each merge resolves them:
- **S2's exclusive scan.** HT/BT add strings with `<<EOF`, `<<-X`, `<<Q\r` and `<<OPEN` inside quotes. S2 Task 3's quote-aware opener ignores them; Task 7 runs `harness_test` to prove no `H` row appears. Build from post-S2 integration.
- **L header :7.** S3 adds `allow_rules`; S5 merges later and unions its repair helper names onto the same line.
- **O near :1084-1091.** S4 inserts functions before `gone()` and edits `val()` and the :1128 gate rule; S3 edits only the open_calls comment at :1091. Neither reflows the other's lines.
- **`run_tests` lists and rulings tails** (HT, BT, OT, T). S1, S4 and S5 append here too. On a conflict, keep both sides; S3 adds its names on its own new continuation line.
- **`tests/run_all.sh` floors.** On a conflict, take the integration branch's `run_all.sh`, then redo Task 7 Steps 3–4.
- **Order.** S3 builds in parallel with S6 and S4 and merges after them (S2's build order).

---

## Falsified assumptions (planner falsify clause, checked at 1cfca7f)

| # | Assumption | Verdict | Evidence |
|---|---|---|---|
| 1 | Spec paths `hooks/godot-guard.sh`, `bin/godot-cmd.awk`, `bin/studio-brief` are repo-root relative | **false** | they live under `studios/game-dev/` (find); plan uses `S/…` |
| 2 | `json_main` returns early unless the text holds `godot` | true (awk:82, spec says :83) | `if (tolower(cmd) !~ /godot/) return` |
| 3 | the first-word skip loop is awk:226-233 and the Godot test awk:234-235 | true | read |
| 4 | `(` `)` are separators, so unquoted `$(…)` is caught (F9) | true (awk:213, spec :211) | probe at 1cfca7f: `x=$(godot -s a.gd)` denied c; `"$(…)"`, backticks, `sh -c` allowed |
| 5 | `unesc` drops `\b \f \u` | true | awk:63-74: only n/r→\n, t→\t; others keep the bare letter |
| 6 | the hook exits before reading stdin with no detector | true | HOOK:21 `[ -f "$det" ] \|\| exit 0` precedes :22 `cat` |
| 7 | out=hook is read as lines 1-2 by `sed -n Np` | true | HOOK:26-27; line 3 slots in |
| 8 | md fence loop, paragraph join, `cont`, md `\`-newline, rows join at :92-96, :103, :126, :173, :260 | true | read |
| 9 | studio-brief `HERE` ignores a symlinked `$0` | true | BRIEF:69 `dirname "$0"`; loop to copy at studio-dispatch:31-40 |
| 10 | `cp -p` at :337 and `mv -f` at :344 | true ±3 | BRIEF:335, :341 |
| 11 | BT:597 depends on earlier tests | true | `test_brief_rewrite_wraps_only` reads `$TMP/ac3.md` (written :444), `edge.md`/`edge.rw.want` (:465, :478) |
| 12 | `deny_note` prints an empty command as `denied: ]` | true | O:1479-1481; open_calls `bash[id]=""` → `1\t` (O:1121) |
| 13 | the O:1090 comment can take "one's" | **false** | it is inside `open_calls`' single-quoted awk (O:1076); task 6 words it without an apostrophe |
| 14 | `allow_rules` is silent on a missing file; one warning site covers start and dry run | true | O:179-181; `preflight` (O:579) is called at O:1661, 1773, 1785 |
| 15 | L's header omits `allow_rules`, used at L:424 | true | L:6-8 |
| 16 | `land_repair` appends the note but its header omits it | true | L:680, 689-691 vs L:656-666; gate_repair's header has it (L:720) |
| 17 | OT:2455-2475 holds a "denied-note loop" that the four endings join | **false** | `test_overnight_permission_route_ending` (OT:2455-2478) has no loop; sync-repair and gate-repair endings are lanes-only (L:736-742, 834-848). Task 6 adds them to T's `test_lanes_sync_repair_stops` loop (already REAL_CLOCK, T:4853) and `test_lanes_permission_route_note`. T is outside the spec's S3 file list |
| 18 | OT stall cases are cheap to add | **false** | idle stall tests are `TESTS_EXCLUSIVE` (OT:2656); task 6 reuses T's existing stall case instead |
| 19 | README has "the guard's row" | **false** | no such row; README:389 is the tree line, README:149-168 the gate-lock bullet; task 2 edits both |
| 20 | `gate_command` is a flat string, first match | true | studio-setup:66-69, :87 |
| 21 | `--path-format=absolute` is safe to rely on | true | used at studio-gate:95, studio-state:73-74 |
| 22 | hooks run with cwd = the project | true | HT:50-53 `run_hook`; worktree-guard tests `cd "$Q"` (HT:1113) |
| 23 | tests must set `STUDIO_START_DIR` themselves | true | assert.sh:17-20 unsets `STUDIO_*` on source |
| 24 | the c retry is asserted at HT:886, :947, :983 only | true | grep `Run it as` / `Run a test file` |
| 25 | the stall note names the newest open call | true | O:1120-1123 iterate `n..1`; O:1423 `head -n 1` |
| 26 | every suite runs in the dash acceptance run | true | run_all.sh:21 `TEST_SH` |
| 27 | `TESTS_ONLY` picks tests within the partition | true | assert.sh:7 |

## Manual acceptance

After the operator installs (no reinstall in this sweep), one live check in a phoenix `claude-gd` session, never during a live run or a final gate: a bare `.github/scripts/run-tests.sh > /tmp/g.log 2>&1` is denied with the g message, and `studio-gate t -- .github/scripts/run-tests.sh` runs and shows in `status` as the gate holder. Fold it into #71's remaining live checks. The auto-mode rule fast-path probe stays out of scope (spec §6.3).
