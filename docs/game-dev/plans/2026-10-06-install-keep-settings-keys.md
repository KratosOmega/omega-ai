# Reinstall Keeps the User's `settings.json` Keys — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A reinstall writes the studio template's top-level keys into the target `settings.json` and keeps every other top-level key already there (`agentPushNotifEnabled` first among them).

**Architecture:** Two small functions in `install.sh` — `settings_python` (find a python3 that runs) and `settings_merge` (an inline `python3 -` heredoc that prints a verdict, the kept keys and the merged document). The merge is computed where the backup step is today, *before* the previous manifest's entries are removed (that removal deletes `settings.json`). The merged document is held in a shell variable and written at the existing write step; when nothing is kept, the template is copied byte for byte as today. Every failure falls back to today's copy with a warning.

**Tech Stack:** POSIX sh (macOS `/bin/sh` = bash 3.2, Linux `dash`); python3 ≥ 3.7 stdlib `json`, optional at run time. No new files besides the docs.

**Spec:** `docs/game-dev/specs/2026-10-06-install-keep-settings-keys.md` (R1–R7).

Story: #53 (GitHub issue). Branch `53-install-keep-settings-keys` (omega-ai has no Jira). **Base:** 6f2445b (origin/main). Line numbers are at that commit; relocate each with its `grep -n`.

## Global Constraints

- POSIX sh only in `install.sh`; must run under macOS `/bin/sh` (bash 3.2) and `dash`. No `jq`, no `plutil`.
- python3 is optional: a missing or broken interpreter, or an unparsable file, never fails the install (R3).
- A fresh install (no `settings.json` in the target) never runs python and writes the template byte for byte (R4). Nor does a reinstall over a file byte-identical to the template (nothing to keep) — python runs only when the bytes differ (D8).
- `~/.claude` is never read for merging: a link at `$TARGET/settings.json` is not merged from (D3).
- `settings.json`'s manifest line, `uninstall.sh` and `doctor.sh` are unchanged (R6).
- Tests assume a working python3 ≥ 3.7 on the test machine, as `integrations/multica/tests` already do.
- Review policy: Task 1 is the only implementation task, so it gets no separate task review — the standalone final whole-branch review on Opus (Task 2) reads the same diff. Re-review only after a Critical, 3+ Importants or a production-bug fix.
- The integrated full gate (`sh tests/run_all.sh`) runs once, after the final fix wave.

## Decisions

R1–R7 are the operator's rulings (spec); these are the details they left to the plan.

- **D1 — Python resolution and the test hook.** `OMEGA_INSTALL_PYTHON` when set and non-empty, else `command -v python3`, else `/usr/bin/python3`; the result must pass `"$PY" -c 'import sys; sys.exit(sys.version_info < (3, 7))'` (3.7: the first version whose `dict` keeps insertion order, which R2's output order relies on). The run check is borrowed from `integrations/multica/install.sh:251`; the PATH lookup is not (see Falsify 3) — install.sh runs from the user's own shell, so their PATH python3 is the right one. `OMEGA_INSTALL_PYTHON` is the test hook R1 needs: the fallback cannot be forced through PATH, because `/usr/bin/python3` is an absolute fallback. It is also a legitimate override, so the usage text lists it. On a Mac without developer tools, the `/usr/bin/python3` stub may show its install dialog once; the probe then fails and the fallback applies.
- **D2 — The helper is inline, in `install.sh`.** A top-level shell function whose body is `"$1" - "$2" "$3" <<'PY' … PY`. One consumer, ~25 lines of python, nothing to keep in sync with a second file, and copy mode needs no extra path (install.sh always runs from the checkout). It is a *top-level function called from `$( )`*, never a heredoc written inside `$( )`: bash 3.2 mis-parses a quoted heredoc holding an apostrophe inside a command substitution (Falsify 7).
- **D3 — A link at `$TARGET/settings.json` is not merged from.** It is replaced by the template as today (and backed up as today when it differs). Its keys belong to whatever it points at — often `~/.claude/settings.json` — and copying them into the studio root would break the isolation the studio exists for.
- **D4 — Backups: only when something would be lost.** With a successful merge, the existing file is backed up iff its parsed content differs from the merged content (compared as `json.dumps(…, sort_keys=True)`, so key order and formatting do not count, and `1` vs `true` does). So a file that differs from the template only by kept keys, or only by formatting (Claude Code rewrote it), gets no new `.bak`; a changed template-owned value still does. Why: the backup exists to save what the install discards; the merge now discards only template-owned values, and eleven redundant backups already piled up. Every fallback path (no python, invalid JSON, a link) keeps today's rule: back up iff `cmp` says the bytes differ from the template.
- **D5 — Nothing kept, template bytes.** When the merge succeeds but keeps no key, the template is copied with `cp`, not re-serialized. This keeps every existing test fixture that installs a hand-written one-line template byte-identical, and keeps a fresh-looking reinstall identical to a fresh install.
- **D6 — The merged document travels in a shell variable**, not a temp file: `settings_merge` prints `same|differs`, the kept keys, then the document; the shell splits on the first two newlines with `${var%%"$nl"*}` / `${var#*"$nl"}` and writes with `printf '%s\n'` (the command substitution stripped the one trailing newline). No `mktemp`, no EXIT trap. Python writes bytes (`sys.stdout.buffer.write(….encode("utf-8"))`) and reads with `encoding="utf-8"`, so a non-UTF-8 locale cannot garble or crash it; kept key names in the report line are JSON-escaped ASCII.
- **D7 — Messages** (warnings via `warn`, i.e. stderr `warning: …`; the rest via `log`, stdout):
  - kept (after writing): `settings.json: kept your keys: <k1>, <k2>`
  - backup (unchanged text): `existing settings.json differed; backed up to <path>`
  - fallback, only when a backup was made (byte-identical files lose nothing): `settings.json: <why> — installing the studio template as is; your previous file is <backup>`, where `<why>` is `python3 not found or not working`, `not a valid JSON object`, or `could not merge (python3 exit <rc>)`
  - dry run: `DRY  merge <target>/settings.json (keeping your keys: <k1>, <k2>)` when keys would be kept, else today's `DRY  copy <target>/settings.json`; a dry-run fallback warns `settings.json: <why> — the studio template would be installed as is` (when the bytes differ). The dry run still makes no backup and prints none, as today.
- **D8 — Python runs only when the bytes differ.** A target byte-identical to the template has nothing to keep and nothing to back up, so `cmp` decides it as today and python is never started — the common reinstall pays nothing, and a Mac whose `/usr/bin/python3` is the developer-tools stub sees no dialog unless there is something to merge.

## Review Focus

1. **A `settings.json` that is a link into `~/.claude`** — the user expects the studio root to stay isolated: the linked file's keys must not appear in the studio's settings, and the linked file must stay untouched. Pinned by the assertion added to `test_install_replaces_symlinked_files`.
2. **Non-ASCII content under a C locale** (a `statusLine` command with `→`, a name with `é`) — expected byte-exact UTF-8 in the merged file and no crash. Pinned by `test_install_settings_non_ascii`.
3. **Claude Code rewrote the file with other formatting but the same content** — no backup pile-up, the template's bytes back. Pinned in `test_install_settings_no_backup_for_kept_keys` (the compact `{"model":"opus"}` case).
4. **An empty or truncated `settings.json`** (a crash mid-write) — the install must still succeed, with the old bytes backed up. Pinned by the `''` and `{"model": "opus",` cases of `test_install_settings_invalid_json_falls_back`.
5. **The macOS developer-tools stub as python3** (present, but exits non-zero) — same fallback as no python at all. Pinned by the `broken-python` case of `test_install_settings_no_python_falls_back`.

Known and accepted: neither studio template defines `hooks`, `permissions` or `env` (Falsify 9), so such keys in the target are now kept where they used to be dropped. That is R2's rule — they are the user's own settings.

## File Structure

- Modify `install.sh` — usage text (`:6-29`); two new functions after `usage()`; the settings decision replaces the backup block (`:122-131`); the write step (`:194-203`).
- Modify `tests/install_test.sh` — `bak_count` helper, eight new tests, one assertion in `test_install_replaces_symlinked_files` (`:973-990`), the `run_tests` list (`:1233-1257`).
- Modify `README.md` — the install paragraph (`:21-22`) and the reinstall sentences (`:49-51`).
- Modify `docs/game-dev/PROGRESS.md` — one dated log entry.

---

### Task 1: Merge `settings.json` on reinstall

Review: final whole-branch review only (Global Constraints). Touches: `install.sh`, `tests/install_test.sh`, `README.md`, `docs/game-dev/PROGRESS.md`.

**Interfaces:**
- Produces (in `install.sh`): `settings_python` — prints a working interpreter's path, returns 1 when none; `settings_merge PY TEMPLATE EXISTING` — stdout line 1 `same|differs`, line 2 kept keys `", "`-joined (empty when none), then the merged document; exit 0, 3 (EXISTING not a JSON object), 4 (TEMPLATE not one), other (python failed). Globals `SETTINGS`, `SETTINGS_DOC`, `SETTINGS_KEPT`, `SETTINGS_SAME`, `SETTINGS_WHY`, `SETTINGS_BAK`. Env hook `OMEGA_INSTALL_PYTHON`.
- Consumes: `STUDIO_DIR`, `TARGET`, `MANIFEST`, `DRY_RUN`, `log`, `warn`, `manifest_add` (`lib/common.sh:4-5,221`).

Anchors: `grep -n '^usage()\|^USAGE\|settings.json is the one installed\|^_prev_shim=\|settings.json is copied, never linked' install.sh`; `grep -n '^test_install_replaces_symlinked_files\|^run_tests' tests/install_test.sh`.

- [ ] **Step 1: Write the failing tests** in `tests/install_test.sh`, after `test_settings_backup`, and add all eight names to the `run_tests` list right after `test_settings_backup` (an unknown name fails the suite):

```sh
# #53: settings.json backups in DIR.
bak_count() { ls "$1"/settings.json.bak-* 2>/dev/null | wc -l | tr -d ' '; }
# same_bytes A B — 0 when the files are byte-identical, else 1.
same_bytes() { cmp -s "$1" "$2" && echo 0 || echo 1; }

# #53: a reinstall keeps the top-level keys the template does not define,
# after the template's own keys, which take the template's values. The
# expected bytes assume studios/general/settings.json is {"model": "opus"}.
test_install_settings_keeps_user_keys() {
  sh "$REPO_ROOT/install.sh" general --target "$TMP/sk" --shim-dir "$TMP/bin-sk" >/dev/null 2>&1
  printf '{"zeta": 1, "model": "stale", "agentPushNotifEnabled": true}\n' > "$TMP/sk/settings.json"
  status=0
  sh "$REPO_ROOT/install.sh" general --target "$TMP/sk" --shim-dir "$TMP/bin-sk" > "$TMP/sk.out" 2>&1 || status=$?
  assert_eq 0 "$status" "the reinstall succeeds"
  printf '{\n  "model": "opus",\n  "zeta": 1,\n  "agentPushNotifEnabled": true\n}\n' > "$TMP/sk.want"
  assert_eq 0 "$(same_bytes "$TMP/sk.want" "$TMP/sk/settings.json")" \
    "template keys first with the template's values, then the kept keys in their order"
  assert_contains "$TMP/sk.out" "^settings.json: kept your keys: zeta, agentPushNotifEnabled$" "one line names the kept keys"
  assert_eq 1 "$(bak_count "$TMP/sk")" "a template-owned value changed, so the old file is backed up"
  assert_contains "$TMP/sk"/settings.json.bak-* '"model": "stale"' "the backup holds the old value"
  assert_contains "$TMP/sk/.omega-ai-manifest" "^$TMP/sk/settings.json$" "the manifest still records settings.json"
}

# #53: a template-owned object is replaced whole; doctor reads the merged
# file as it read the template; uninstall removes it through the manifest.
test_install_settings_merged_doctor_clean() {
  sh "$REPO_ROOT/install.sh" game-dev --target "$TMP/sd" --shim-dir "$TMP/bin-sd" >/dev/null 2>&1
  printf '{ "agentPushNotifEnabled": true, "enabledPlugins": { "mine@market": true } }\n' > "$TMP/sd/settings.json"
  status=0
  sh "$REPO_ROOT/install.sh" game-dev --target "$TMP/sd" --shim-dir "$TMP/bin-sd" > "$TMP/sd.out" 2>&1 || status=$?
  assert_eq 0 "$status" "a merged install passes its own doctor run"
  assert_contains "$TMP/sd/settings.json" '"agentPushNotifEnabled": true' "the user's key is kept"
  assert_not_contains "$TMP/sd/settings.json" "mine@market" "a template-owned object is replaced whole, not deep-merged"
  status=0
  sh "$REPO_ROOT/doctor.sh" game-dev --target "$TMP/sd" > "$TMP/sd-doc.out" 2>&1 || status=$?
  assert_eq 0 "$status" "doctor passes on the merged file"
  assert_contains "$TMP/sd-doc.out" "superpowers@claude-plugins-official enabled" "doctor reads superpowers as enabled"
  assert_contains "$TMP/sd-doc.out" "godot-prompter@skillsmith enabled" "doctor reads godot-prompter as enabled"
  sh "$REPO_ROOT/uninstall.sh" game-dev --target "$TMP/sd" --shim-dir "$TMP/bin-sd" >/dev/null 2>&1
  assert_missing "$TMP/sd/settings.json" "uninstall removes the merged settings.json"
}

# #53: a fresh install never consults python3 and copies the template.
test_install_settings_fresh_unchanged() {
  status=0
  OMEGA_INSTALL_PYTHON="$TMP/no-such-python" \
    sh "$REPO_ROOT/install.sh" game-dev --target "$TMP/sf" --shim-dir "$TMP/bin-sf" > "$TMP/sf.out" 2>&1 || status=$?
  assert_eq 0 "$status" "a fresh install succeeds"
  assert_eq 0 "$(same_bytes "$REPO_ROOT/studios/game-dev/settings.json" "$TMP/sf/settings.json")" \
    "a fresh install copies the template byte for byte"
  assert_not_contains "$TMP/sf.out" "settings.json:" "nothing merged, nothing reported, python3 not consulted"
  assert_eq 0 "$(bak_count "$TMP/sf")" "no backup"
}

# #53: a file that is not a JSON object falls back to the template, backed up.
test_install_settings_invalid_json_falls_back() {
  n=0
  for body in '{"model": "opus",' '[1, 2]' ''; do
    n=$((n + 1)); t="$TMP/sij$n"
    mkdir -p "$t"
    printf '%s' "$body" > "$t/settings.json"
    status=0
    sh "$REPO_ROOT/install.sh" general --target "$t" --shim-dir "$t-bin" > "$t.out" 2>&1 || status=$?
    assert_eq 0 "$status" "case $n: the install does not fail"
    assert_contains "$t.out" "settings.json: not a valid JSON object — installing the studio template as is; your previous file is $t/settings.json.bak-" \
      "case $n: the warning names the backup"
    assert_eq 0 "$(same_bytes "$REPO_ROOT/studios/general/settings.json" "$t/settings.json")" "case $n: the template is installed as is"
    assert_eq 1 "$(bak_count "$t")" "case $n: the old bytes are backed up"
  done
}

# #53: no python3, or one that does not run (macOS's developer-tools stub):
# the template is installed as today and the warning names the backup.
test_install_settings_no_python_falls_back() {
  printf '#!/bin/sh\nexit 1\n' > "$TMP/broken-python"; chmod +x "$TMP/broken-python"
  for py in "$TMP/no-such-python" "$TMP/broken-python"; do
    c="$(basename "$py")"; t="$TMP/snp-$c"
    mkdir -p "$t"
    printf '{"model": "opus", "agentPushNotifEnabled": true}\n' > "$t/settings.json"
    status=0
    OMEGA_INSTALL_PYTHON="$py" sh "$REPO_ROOT/install.sh" general --target "$t" --shim-dir "$t-bin" > "$t.out" 2>&1 || status=$?
    assert_eq 0 "$status" "$c: the install does not fail"
    assert_contains "$t.out" "settings.json: python3 not found or not working — installing the studio template as is; your previous file is $t/settings.json.bak-" \
      "$c: the warning names the backup"
    assert_eq 0 "$(same_bytes "$REPO_ROOT/studios/general/settings.json" "$t/settings.json")" "$c: the template is installed as is"
    assert_contains "$t"/settings.json.bak-* agentPushNotifEnabled "$c: the backup keeps the key"
  done
}

# #53: --dry-run names the keys it would keep and touches nothing.
test_install_settings_dry_run_reports_kept() {
  sh "$REPO_ROOT/install.sh" general --target "$TMP/sdr" --shim-dir "$TMP/bin-sdr" >/dev/null 2>&1
  printf '{"model": "stale", "agentPushNotifEnabled": true}\n' > "$TMP/sdr/settings.json"
  cp "$TMP/sdr/settings.json" "$TMP/sdr.before"
  status=0
  sh "$REPO_ROOT/install.sh" general --target "$TMP/sdr" --shim-dir "$TMP/bin-sdr" --dry-run > "$TMP/sdr.out" 2>&1 || status=$?
  assert_eq 0 "$status" "the dry run succeeds"
  assert_contains "$TMP/sdr.out" "^DRY  merge $TMP/sdr/settings.json (keeping your keys: agentPushNotifEnabled)$" \
    "the dry run names the keys it would keep"
  assert_eq 0 "$(same_bytes "$TMP/sdr.before" "$TMP/sdr/settings.json")" "the dry run writes nothing"
  assert_eq 0 "$(bak_count "$TMP/sdr")" "the dry run backs nothing up"
  assert_not_contains "$TMP/sdr.out" "kept your keys" "no claim that keys were kept"
}

# #53: a file that differs from the template only by kept keys, or only by
# formatting, is not backed up — eleven redundant backups piled up before.
test_install_settings_no_backup_for_kept_keys() {
  sh "$REPO_ROOT/install.sh" general --target "$TMP/snb" --shim-dir "$TMP/bin-snb" >/dev/null 2>&1
  printf '{"model": "opus", "agentPushNotifEnabled": true}\n' > "$TMP/snb/settings.json"
  sh "$REPO_ROOT/install.sh" general --target "$TMP/snb" --shim-dir "$TMP/bin-snb" > "$TMP/snb.out" 2>&1
  assert_eq 0 "$(bak_count "$TMP/snb")" "only a kept key differs: no backup"
  assert_contains "$TMP/snb.out" "^settings.json: kept your keys: agentPushNotifEnabled$" "the key is kept"
  cp "$TMP/snb/settings.json" "$TMP/snb.first"
  sh "$REPO_ROOT/install.sh" general --target "$TMP/snb" --shim-dir "$TMP/bin-snb" >/dev/null 2>&1
  assert_eq 0 "$(bak_count "$TMP/snb")" "a second reinstall: still no backup"
  assert_eq 0 "$(same_bytes "$TMP/snb.first" "$TMP/snb/settings.json")" "the second reinstall writes the same bytes"
  printf '{"model":"opus"}' > "$TMP/snb/settings.json"
  sh "$REPO_ROOT/install.sh" general --target "$TMP/snb" --shim-dir "$TMP/bin-snb" >/dev/null 2>&1
  assert_eq 0 "$(bak_count "$TMP/snb")" "same content, other formatting: no backup"
  assert_eq 0 "$(same_bytes "$REPO_ROOT/studios/general/settings.json" "$TMP/snb/settings.json")" \
    "nothing kept: the template's own bytes"
}

# #53: non-ASCII survives byte for byte, even under a C locale.
test_install_settings_non_ascii() {
  mkdir -p "$TMP/sna"
  printf '{"model": "opus", "statusLine": {"type": "command", "command": "echo \342\206\222 caf\303\251"}}\n' > "$TMP/sna/settings.json"
  status=0
  LC_ALL=C sh "$REPO_ROOT/install.sh" general --target "$TMP/sna" --shim-dir "$TMP/bin-sna" > "$TMP/sna.out" 2>&1 || status=$?
  assert_eq 0 "$status" "the install succeeds under LC_ALL=C"
  printf '{\n  "model": "opus",\n  "statusLine": {\n    "type": "command",\n    "command": "echo \342\206\222 caf\303\251"\n  }\n}\n' > "$TMP/sna.want"
  assert_eq 0 "$(same_bytes "$TMP/sna.want" "$TMP/sna/settings.json")" "the kept value is written as UTF-8, unescaped"
  assert_eq 0 "$(bak_count "$TMP/sna")" "only a kept key differs: no backup"
}
```

And in `test_install_replaces_symlinked_files`, after the `settings.json is a regular file after install` check:

```sh
  assert_not_contains "$TMP/sym/settings.json" "mine" "a linked settings.json is replaced, never merged from"
```

- [ ] **Step 2: Run them; they fail.** `TESTS_ONLY="test_install_settings_keeps_user_keys test_install_settings_merged_doctor_clean test_install_settings_fresh_unchanged test_install_settings_invalid_json_falls_back test_install_settings_no_python_falls_back test_install_settings_dry_run_reports_kept test_install_settings_no_backup_for_kept_keys test_install_settings_non_ascii test_install_replaces_symlinked_files test_settings_backup" sh tests/install_test.sh`. Expected: the kept-key, dry-run, no-backup, non-ASCII, merged-doctor and fallback-warning assertions FAIL (today's install drops the keys and prints none of the new lines); `fresh_unchanged`, the symlink test and `test_settings_backup` already pass — they guard behaviour that must not change.

- [ ] **Step 3: The two functions**, in `install.sh` directly after `usage()`'s closing `}` (top level — D2):

```sh
# settings_python — print a python3 that actually runs (3.7+: ordered dicts);
# return 1 when there is none. OMEGA_INSTALL_PYTHON names one instead (tests
# point it at a missing or broken interpreter). macOS's /usr/bin/python3 can
# be a stub that only offers to install the developer tools, hence a probe
# that runs it rather than a presence check.
settings_python() {
  if [ -n "${OMEGA_INSTALL_PYTHON:-}" ]; then
    _py="$OMEGA_INSTALL_PYTHON"
  else
    _py="$(command -v python3 2>/dev/null || true)"
    [ -n "$_py" ] || _py=/usr/bin/python3
  fi
  "$_py" -c 'import sys; sys.exit(sys.version_info < (3, 7))' >/dev/null 2>&1 || return 1
  printf '%s\n' "$_py"
}

# settings_merge PY TEMPLATE EXISTING — the reinstall's settings.json (#53):
# the template's top-level keys with the template's values, then every other
# top-level key of EXISTING, in its order. Prints "same" (EXISTING already
# holds exactly that content) or "differs", then the kept keys ", "-joined
# (empty when none), then the merged document. Exit 3: EXISTING is not a
# JSON object; 4: TEMPLATE is not. A top-level function, never a heredoc
# inside $( ): bash 3.2 mis-parses that.
settings_merge() {
  "$1" - "$2" "$3" <<'PY'
import json, sys

def load(path, code):
    try:
        with open(path, encoding="utf-8") as f:
            doc = json.load(f)
    except (OSError, ValueError):
        sys.exit(code)
    if not isinstance(doc, dict):
        sys.exit(code)
    return doc

template = load(sys.argv[1], 4)
existing = load(sys.argv[2], 3)
merged = dict(template)
kept = [k for k in existing if k not in template]
for k in kept:
    merged[k] = existing[k]
canon = lambda d: json.dumps(d, sort_keys=True)
out = "same" if canon(existing) == canon(merged) else "differs"
out += "\n" + ", ".join(json.dumps(k)[1:-1] for k in kept)
out += "\n" + json.dumps(merged, indent=2, ensure_ascii=False) + "\n"
sys.stdout.buffer.write(out.encode("utf-8"))
PY
}
```

- [ ] **Step 4: The decision and the backup.** Replace `install.sh:122-131` (the `if [ "$DRY_RUN" != "1" ]; then … backup … fi` block; keep the manifest comment at `:118-121` above it) with:

```sh
# settings.json is the one installed file Claude Code mutates in-session, and
# the previous manifest records it, so what this install writes there is
# decided now, before the old entries are removed (#53). The template's
# top-level keys take its values; every other top-level key already in the
# file is kept. A link there is replaced, never merged from: its keys belong
# to whatever it points at (~/.claude, say). A copy is backed up only when
# something would be lost — with a merge, when a template-owned value
# changes; otherwise, as before, when the bytes differ from the template.
# Bytes identical to the template need no python: nothing to keep.
SETTINGS="$TARGET/settings.json"
SETTINGS_DOC=""   # the merged document; empty: install the template as is
SETTINGS_KEPT=""  # the kept keys, ", "-joined
SETTINGS_WHY=""   # why no merge happened, for the fallback warning
SETTINGS_BAK=""
SETTINGS_SAME=1
[ ! -f "$SETTINGS" ] || cmp -s "$STUDIO_DIR/settings.json" "$SETTINGS" || SETTINGS_SAME=0
if [ "$SETTINGS_SAME" = 0 ] && [ ! -L "$SETTINGS" ]; then
  if ! _py="$(settings_python)"; then
    SETTINGS_WHY="python3 not found or not working"
  else
    _rc=0
    _out="$(settings_merge "$_py" "$STUDIO_DIR/settings.json" "$SETTINGS")" || _rc=$?
    case "$_rc" in
      0)
        _nl='
'
        if [ "${_out%%"$_nl"*}" = same ]; then SETTINGS_SAME=1; else SETTINGS_SAME=0; fi
        _out="${_out#*"$_nl"}"
        SETTINGS_KEPT="${_out%%"$_nl"*}"
        if [ -n "$SETTINGS_KEPT" ]; then SETTINGS_DOC="${_out#*"$_nl"}"; fi
        ;;
      3) SETTINGS_WHY="not a valid JSON object" ;;
      *) SETTINGS_WHY="could not merge (python3 exit $_rc)" ;;
    esac
  fi
fi
if [ "$SETTINGS_SAME" = 0 ]; then
  if [ "$DRY_RUN" = "1" ]; then
    [ -z "$SETTINGS_WHY" ] || warn "settings.json: $SETTINGS_WHY — the studio template would be installed as is"
  else
    SETTINGS_BAK="$TARGET/settings.json.bak-$(date +%Y%m%d%H%M%S)"
    cp "$SETTINGS" "$SETTINGS_BAK"
    warn "existing settings.json differed; backed up to $SETTINGS_BAK"
    [ -z "$SETTINGS_WHY" ] || warn "settings.json: $SETTINGS_WHY — installing the studio template as is; your previous file is $SETTINGS_BAK"
  fi
fi
```

(`[ -z … ] || warn …` is safe under `set -e`: an `||` list's left side never trips it. Keep every `if` above as written — a bare `[ … ] && x` as the last command of a `case` branch is the shape bash 3.2's `set -e` has mishandled.)

- [ ] **Step 5: The write.** Replace the `settings.json` write block (`install.sh:194-203`) with:

```sh
# settings.json is copied, never linked: Claude Code writes to it in-session.
# What to write, and any backup, was decided above, before the old
# manifest's entries were removed.
if [ "$DRY_RUN" = "1" ]; then
  if [ -n "$SETTINGS_DOC" ]; then
    log "DRY  merge $SETTINGS (keeping your keys: $SETTINGS_KEPT)"
  else
    log "DRY  copy $SETTINGS"
  fi
else
  rm -f "$SETTINGS"
  if [ -n "$SETTINGS_DOC" ]; then
    printf '%s\n' "$SETTINGS_DOC" > "$SETTINGS"
    log "settings.json: kept your keys: $SETTINGS_KEPT"
  else
    cp "$STUDIO_DIR/settings.json" "$SETTINGS"
  fi
  manifest_add "$MANIFEST" "$SETTINGS"
fi
```

- [ ] **Step 6: Usage and README.** In `usage()`, after the `-h, --help` line, add:

```
A reinstall keeps every top-level settings.json key the studio's template
does not define (agentPushNotifEnabled, say); the template's own keys take
its values. The merge needs python3; without it the template is installed
as is and the previous file is backed up.

Environment:
  OMEGA_INSTALL_PYTHON  the python3 for that merge (default: python3 on
                        PATH, else /usr/bin/python3)
```

In `README.md`, after the reinstall sentence ending `…before writing anew.` (`:49-51`), add: `A reinstall keeps every top-level key you or Claude Code added to settings.json that the studio's template does not define, such as agentPushNotifEnabled, and names them; the template's own keys take its values. A copy whose template-owned values changed is still backed up to settings.json.bak-<timestamp>. The merge needs python3 — without it, or when the file is not valid JSON, the template is installed as is, with a warning naming the backup.` (backticks around file and key names, in the README's style).

- [ ] **Step 7: Run them; they pass.** The Step 2 command. Then the whole `sh tests/install_test.sh`, then the same file under dash: `dash tests/install_test.sh` (install.sh is invoked as `sh` inside it, so also run one merge case by hand under dash: `dash install.sh general --target "$(mktemp -d)/t" --shim-dir "$(mktemp -d)" --dry-run`, after writing a `settings.json` with an extra key there — expect the `DRY  merge` line).

- [ ] **Step 8: PROGRESS.** Add a dated entry at the top of the Log in `docs/game-dev/PROGRESS.md`, in its existing style (read the newest entry first): `### 2026-10-06 — Reinstall keeps your settings.json keys (#53)` — the template's keys win, others are kept and named, backups only when a template-owned value changes, python3 optional with a warned fallback; the three lost `agentPushNotifEnabled` reinstalls as the reason.

- [ ] **Step 9: Commit** — `git commit -m 'fix(install): a reinstall keeps the user'"'"'s top-level settings.json keys (#53)' -- install.sh tests/install_test.sh README.md docs/game-dev/PROGRESS.md`

**Acceptance:** all Step 1 tests pass; the whole `tests/install_test.sh` passes under `sh` and `dash`; `git diff 6f2445b -- doctor.sh uninstall.sh lib/` is empty.

---

### Task 2: Final whole-branch review, fix wave, gate, PR

- [ ] Standalone whole-branch review on Opus over `6f2445b..HEAD` against the spec and this plan (D1–D7, Review Focus).
- [ ] One fresh fixer for the findings (minors batched); re-review only per the Global Constraints rule.
- [ ] Full gate once on the integrated branch: `sh tests/run_all.sh` and `sh integrations/multica/tests/run.sh`.
- [ ] PR `Closes #53`, body with D3 (links not merged from) and D4 (backup only when a template-owned value changes) and their reasons; merge once green (operator's standing merge authority for omega-ai). Do not reinstall or pull into the main checkout while an overnight run is live — check `studio-overnight status` first; otherwise leave the reinstall as a noted follow-up. After the reinstall, `grep agentPushNotifEnabled ~/.claude-gamedev/settings.json` should still find it.

## Falsify — load-bearing claims at 6f2445b

1. **The bug is where the issue says.** `install.sh:126-129` backs up a differing copy (`cmp -s` template vs target, then `cp` to `settings.json.bak-<stamp>`); `install.sh:200-201` does `rm -f` + `cp` of the template. True.
2. **The existing file is gone before the write step.** The previous manifest records `$TARGET/settings.json` (`install.sh:202`), and `manifest_remove` (`install.sh:144`, `lib/common.sh:279-321`) runs `rm -rf` on every in-scope entry. So the merge must read the file before `:139-144` — the plan computes it in place of the backup block (`:122-131`). True; a plan that merged at `:200` would have read nothing.
3. **The multica python idiom.** The brief said multica resolves `command -v python3`, else `/usr/bin/python3`. **False as stated:** `integrations/multica/install.sh:250-252` uses its `--python` flag, else `/usr/bin/python3` — never PATH — and checks it with `"$PY" -c 'import sys; sys.exit(sys.version_info < (3, 9))'`; `uninstall.sh:21` hard-codes `/usr/bin/python3`. Handled: D1 keeps R1's order (PATH first; install.sh runs in the user's shell, unlike multica's launchd service), adds the `OMEGA_INSTALL_PYTHON` override in the role of multica's `--python`, and borrows multica's run probe with a 3.7 floor.
4. **No jq.** `studios/game-dev/hooks/operator-inbox.sh:27` — `(R19: no jq)`. True.
5. **Neither doctor nor uninstall compares `settings.json` with the template.** `doctor.sh:49` checks presence only; `:115` greps `"<id>"[[:space:]]*:[[:space:]]*true` on one line and `:130` lists every `"x@y": true`; `uninstall.sh` never names `settings.json` (it removes manifest entries). `json.dumps(indent=2)` puts each `enabledPlugins` entry on its own `"id": true` line, so the doctor grep still matches. True — pinned by `test_install_settings_merged_doctor_clean`.
6. **Both templates are already python-canonical.** `json.dumps(json.load(f), indent=2, ensure_ascii=False) + "\n"` is byte-identical to `studios/game-dev/settings.json` and `studios/general/settings.json` (checked, python3 3.9.6). Not load-bearing (D5 copies template bytes when nothing is kept), but it means a merged file's template part reads exactly like the template.
7. **bash 3.2 and heredocs in `$( )`.** `sh -c 'x="$(f(){ cat <<'"'"'PY'"'"' … a)'"'"'b … PY … }; f)"'` fails with `command substitution: … syntax error: unexpected end of file` under macOS `/bin/sh` — checked. A top-level function holding a `<<'PY'` heredoc, called as `r="$(m python3 3)" || rc=$?` under `set -eu`, works in `/bin/sh` and `/bin/dash`: `rc=3`, both stdout lines captured, `set -e` not tripped — checked. The full Step 3–4 logic was prototyped under both shells on the six inputs of the tests (keep+overwrite, compact-equal, non-ASCII under `LC_ALL=C`, `[1]`, empty file, missing python): every verdict, kept list and output byte matched the expected values above.
8. **Existing tests stay green.** `test_settings_backup` (`tests/install_test.sh:440-456`) writes `{"model":"stale"}`: verdict `differs`, nothing kept → backup made and the template's bytes installed, so its three assertions hold. `test_install_replaces_symlinked_files` (`:973-990`): a link is not merged from (D3) and still `rm -f`'d before the write, so the linked file stays `{"mine":true}`. `test_doctor_matches_plugin_ids_literally` (`:1053-1081`) installs fresh, and `test_doctor_plugin_report` (`:653`, its write at `:677`) edits the file after install and runs only the doctor — no merge in either. `test_install_dry_run_previews_removal` (`:1190`) dry-runs over a byte-identical file — `cmp` says same, python never runs (D8), `DRY  copy` as today. True.
9. **The templates define no `hooks`/`permissions`.** game-dev: `model`, `enabledPlugins`, `extraKnownMarketplaces`; general: `model`. So "the template owns hooks/permissions as today" does not hold — such keys in a target are now kept (R2's rule). Recorded under Review Focus as accepted.
10. **The harness reaches a real python3.** `tests/install_test.sh:36` prepends `$STUBS` to PATH and keeps the rest; `NO_ENGINE_PATH` (`:39`) includes `/usr/bin`. So the merge tests resolve a real interpreter, and the broken stub must live outside `$STUBS` (it is `$TMP/broken-python`, not `$STUBS/python3`). True.
11. **`run_tests` rejects unknown names** (`tests/assert.sh:68-…`) — every new test must be listed, or the suite fails loudly. True.
12. **`dict` and `json.load` keep insertion order** from Python 3.7 — R2's order rests on it; D1's probe enforces 3.7.
