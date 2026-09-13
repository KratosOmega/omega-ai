# Game Studio Plan 1 — Review Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the review findings on PR #1 that have real value — two data-loss paths in the installer, the execute stage's broken state model, orphaned agents, and the doctor's blind spots — so Plan 1 ships usable, without pulling Plan 2/3 stages forward.

**Architecture:** The installer keeps its manifest-driven shape and gains a two-line manifest header (`# mode=…`, `# shim=…`) that `uninstall.sh` and `doctor.sh` read instead of guessing. State splits by lifetime: the spec, the plan and a per-feature ledger (`.studio/ledger/<feature>.md`) are committed at each approval gate and travel into worktrees; the stage/task pointer (`.studio/STATE.md`) is local, gitignored, and always resolved to the project's main checkout, so one project has one stage however many worktrees are open. Stage skills dispatch the studio's own agents where they exist (`feel-tuner`, `tech-artist`, `game-designer`) and godot-prompter's agents for the rest until Plan 2; execute ends with a headless smoke boot and never names a merge path.

**Tech Stack:** POSIX `sh`, the existing `lib/common.sh` helpers and `tests/assert.sh` harness, git ≥ 2.31 (`git rev-parse --path-format=absolute`), Claude Code plugin conventions (`hooks.json` PreToolUse/SessionStart, `@path` imports in `CLAUDE.md`), Markdown skills.

**Spec:** `docs/game-dev/specs/2026-09-13-game-studio-design.md` — Task 22 amends its "State and configuration", "Agents" and `/game-dev:execute` sections to match the decisions below. Decisions taken with the user on 2026-09-13: (1) spec + plan + per-feature ledger tracked in git, pointer local; (2) studio memory loaded through a `CLAUDE.md` import, Claude's per-project auto memory untouched; (3) agents renamed and wired, godot-prompter agents as the interim for roles without a studio agent; (4) execute finishes with a smoke boot and an unverified list, never a merge.

## Global Constraints

- POSIX `sh` only, no bash-isms, no new dependencies (`jq` only when present). `bin/` and `hooks/` scripts stay self-contained: copy mode ships them without `lib/common.sh`.
- `sh tests/run_all.sh` is green after every task's commit. Every new test runs against a temporary root or a fake `$HOME`; nothing under the real `~/.claude`, `~/.claude-gamedev` or `~/.local/bin` is created, modified or deleted.
- `guard_target` semantics are unchanged. `canon_path` is the only path canonicalizer.
- Skill frontmatter: `name` equals the directory, `description` starts with "Use when". Agent frontmatter: `name` equals the file stem, `description` starts with "Use when", a `tools:` line, `model: inherit`.
- Every `superpowers:` or `godot-prompter:` name referenced under `studios/game-dev/{skills,agents}` appears in `studios/game-dev/requires.txt` (`tests/studio_test.sh` enforces it). Real names only — godot-prompter agents: `godot-game-dev`, `godot-game-architect`, `godot-ui-designer`, `godot-code-reviewer`, `godot-csharp-engineer`; godot-prompter skills used here: `gdscript-patterns`, `state-machine`, `event-bus`, `resource-pattern`, `component-system`, `dependency-injection`, `scene-organization`, `player-controller`, `input-handling`, `physics-system`, `camera-system`, `tween-animation`, `animation-system`, `godot-ui`, `hud-system`, `responsive-ui`, `2d-essentials`, `assets-pipeline`, `godot-testing`, `godot-code-review`.
- `studio-state` keys stay `stage spec plan task last_playtest milestone`; stages and milestones unchanged. Exit codes: 0 ok; 1 no `.studio/` (except `init` and `root`), bad key, bad value, bad usage, or a `check` that found a mismatch.
- Ledger phrases other skills search for: `spec written <path>`, `spec approved <path>`, `plan written <path>`, `plan approved <path>`, `T<n> complete <range>`, `T<n> Ruling:`, `T<n> Review:`, `T<n> Playtest item:`, `T<n> Visual:`, `abandoned <spec>`.
- Manifest header lines are exactly `# mode=<symlink|copy>` and `# shim=<absolute shim path>`, the first two lines of `.omega-ai-manifest`; `manifest_remove` never treats a `#` line as a path.
- Never mention `superpowers:finishing-a-development-branch` in `skills/execute/SKILL.md`.
- Commit after every task, on the current branch `worktree-game-studio`, never push. Every commit message ends with the two trailer lines:

  ```
  Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01EXbiTV13oWT2MjvbFXAuB2
  ```

## File structure

| Path | Responsibility after this plan |
|------|-------------------------------|
| `lib/common.sh` | Gains `studio_arg`, `manifest_meta`, `shim_owned`; `manifest_remove` skips header lines and honours `DRY_RUN`. |
| `install.sh` | Validates every input before touching the previous install; canonical target; replaces symlinked files; writes the manifest header; imports studio memory into `CLAUDE.md`; reports the doctor result last. |
| `uninstall.sh` | Purge requires a manifest and purges the physical root; removes the shim the manifest recorded, only when it launches this root. |
| `doctor.sh` | Reads the manifest header: shim identity, copy-mode plugin dir; fails on missing files, a stale pre-plugin layout, and leaks judged on canonical paths. |
| `sync-memory.sh` | Unchanged behaviour; studio name normalized. |
| `README.md` | Memory model, upgrade path, corrected flags. |
| `studios/game-dev/bin/studio-state` | Pointer in the main checkout, per-feature ledger in the working checkout; `root`, `check`, `reset`. |
| `studios/game-dev/hooks/session-start.sh` | Fails loud without `bootstrap.md`; strips control characters; injects the stage line. |
| `studios/game-dev/hooks/guard-state.sh` | PreToolUse hook: state files are written only through `studio-state`. |
| `studios/game-dev/hooks/hooks.json` | SessionStart + PreToolUse. |
| `studios/game-dev/hooks/bootstrap.md` | Precedence and state wording. |
| `studios/game-dev/agents/{feel-tuner,tech-artist,game-designer}.md` | Renamed, wired, `feel-tuner` can run the game. |
| `studios/game-dev/requires.txt` | Every godot-prompter skill and agent the stage skills name. |
| `studios/game-dev/skills/{execute,plan,brainstorm,studio}/SKILL.md` | Committed-at-gate state, role dispatch table, verify lists, smoke boot, reconcile/abandon routes. |
| `studios/game-dev/CLAUDE.md` | Event-bus and test-framework rules reworded. |
| `tests/{lib,install,state,hook,studio}_test.sh` | One test per fixed defect. |
| `docs/game-dev/specs/2026-09-13-game-studio-design.md`, `plans/…plan-2…`, `plans/…plan-3…`, `PROGRESS.md` | Reconciled with what shipped. |

---

### Task 1: Studio name and target are normalized once, for all four scripts

**Files:**
- Modify: `lib/common.sh` (after `need_value`)
- Modify: `install.sh:58-62`, `uninstall.sh:27-30`, `doctor.sh:18-21`, `sync-memory.sh:21-24`
- Test: `tests/lib_test.sh`, `tests/install_test.sh`

**Interfaces:**
- Produces: `studio_arg NAME` — prints the name with a trailing slash stripped; dies on an empty name or a name containing `/`. `TARGET` in all four scripts is the `canon_path` of the resolved target (absolute, no trailing slash). Later tasks assume `$TARGET` is canonical.

- [ ] **Step 1: Write the failing lib test**

Append to `tests/lib_test.sh` before `run_tests`:

```sh
test_studio_arg() {
  assert_eq "general" "$(studio_arg general)" "studio_arg passes a plain name through"
  assert_eq "general" "$(studio_arg general/)" "studio_arg strips a trailing slash"
  assert_status 1 "studio_arg refuses a path" -- studio_arg studios/general
  assert_status 1 "studio_arg refuses an empty name" -- studio_arg ""
}
```

Add `test_studio_arg` to the `run_tests` list.

- [ ] **Step 2: Run it to see it fail**

Run: `sh tests/lib_test.sh`
Expected: `FAIL studio_arg passes a plain name through` (studio_arg: not found).

- [ ] **Step 3: Add the helper**

In `lib/common.sh`, after `need_value`:

```sh
# studio_arg NAME — the studio name as typed, with a trailing slash stripped
# (tab completion adds one; it used to install fine and then fail the
# doctor's name check). A name with a slash inside it, or an empty one, dies.
studio_arg() {
  _s="${1%/}"
  [ -n "$_s" ] || die "no studio given"
  case "$_s" in */*) die "studio must be a name, not a path: $1" ;; esac
  printf '%s\n' "$_s"
}
```

- [ ] **Step 4: Run the lib test**

Run: `sh tests/lib_test.sh`
Expected: all pass, including the four new assertions.

- [ ] **Step 5: Write the failing install test**

`tests/install_test.sh` compares paths textually against `$TMP`; once the target is canonical, `/var/…` and `/private/var/…` must agree. Replace line 7 `TMP="$(mktemp -d)"` with:

```sh
# Physical path: the installer canonicalizes the target, so assertions that
# quote $TMP must use the same spelling (/var -> /private/var on macOS).
TMP="$(cd "$(mktemp -d)" && pwd -P)"
```

Append before `run_tests`:

```sh
# A relative --target used to be baked into the shim and the manifest as
# typed, so the install only worked from the directory it was run in; a
# trailing slash on the studio name installed and then failed the doctor.
test_install_normalizes_name_and_target() {
  status=0
  sh "$REPO_ROOT/install.sh" general/ --target "$TMP/slash" --shim-dir "$TMP/bin-slash" \
    > "$TMP/slash.out" 2>&1 || status=$?
  assert_eq "0" "$status" "a studio name with a trailing slash installs and passes the doctor"
  assert_not_contains "$TMP/slash.out" "does not match" "no plugin-name mismatch is reported"
  assert_contains "$TMP/slash/CLAUDE.md" "studios/general/CLAUDE.md" "the rendered header names the studio cleanly"
  assert_status 1 "a studio given as a path is refused" -- \
    sh "$REPO_ROOT/install.sh" studios/general --target "$TMP/slash2" --shim-dir "$TMP/bin-slash"

  mkdir -p "$TMP/relcwd"
  ( cd "$TMP/relcwd" && sh "$REPO_ROOT/install.sh" general --target rel/root --shim-dir rel/bin ) >/dev/null 2>&1
  assert_file "$TMP/relcwd/rel/root/CLAUDE.md" "a relative --target installs under the current directory"
  assert_contains "$TMP/relcwd/rel/bin/claude-gen" "CLAUDE_CONFIG_DIR=\"$TMP/relcwd/rel/root\"" \
    "the shim carries the absolute config root"
  assert_contains "$TMP/relcwd/rel/root/.omega-ai-manifest" "^$TMP/relcwd/rel/root/CLAUDE.md" \
    "the manifest records absolute paths"
  ( cd "$TMP" && sh "$REPO_ROOT/uninstall.sh" general --target "$TMP/relcwd/rel/root" \
      --shim-dir "$TMP/relcwd/rel/bin" ) >/dev/null 2>&1
  assert_missing "$TMP/relcwd/rel/root/CLAUDE.md" "uninstall from another directory removes the install"
  assert_missing "$TMP/relcwd/rel/bin/claude-gen" "uninstall from another directory removes the shim"

  sh "$REPO_ROOT/install.sh" general --target "$TMP/trail/" --shim-dir "$TMP/bin-trail" >/dev/null 2>&1
  assert_contains "$TMP/trail/.omega-ai-manifest" "^$TMP/trail/CLAUDE.md" \
    "a trailing slash on --target is not doubled in the manifest"
}
```

Add `test_install_normalizes_name_and_target` to `run_tests`.

- [ ] **Step 6: Run it to see it fail**

Run: `sh tests/install_test.sh`
Expected: FAIL on "a studio name with a trailing slash installs and passes the doctor" (exit 1, `does not match`) and on "the shim carries the absolute config root".

- [ ] **Step 7: Normalize in all four scripts**

`install.sh` — replace lines 58–62 with:

```sh
[ -n "$STUDIO" ] || { usage; die "no studio given"; }
STUDIO="$(studio_arg "$STUDIO")"
case "$MODE" in symlink|copy) ;; *) die "unknown mode: $MODE" ;; esac

STUDIO_DIR="$REPO_ROOT/studios/$STUDIO"
# The target is canonical so the shim and the manifest carry a path that is
# valid from any directory; a relative --target used to be recorded as typed.
TARGET="$(canon_path "$(resolve_studio_target "$STUDIO_DIR" "$TARGET_OVERRIDE")")"
```

`uninstall.sh` — replace lines 27–30 with:

```sh
[ -n "$STUDIO" ] || die "no studio given"
STUDIO="$(studio_arg "$STUDIO")"

STUDIO_DIR="$REPO_ROOT/studios/$STUDIO"
TARGET="$(canon_path "$(resolve_studio_target "$STUDIO_DIR" "$TARGET_OVERRIDE")")"
```

`doctor.sh` — replace lines 18–21 with:

```sh
[ -n "$STUDIO" ] || die "no studio given"
STUDIO="$(studio_arg "$STUDIO")"

STUDIO_DIR="$REPO_ROOT/studios/$STUDIO"
TARGET="$(canon_path "$(resolve_studio_target "$STUDIO_DIR" "$TARGET_OVERRIDE")")"
```

`sync-memory.sh` — replace lines 21–24 with:

```sh
[ -n "$STUDIO" ] || die "no studio given"
STUDIO="$(studio_arg "$STUDIO")"

STUDIO_DIR="$REPO_ROOT/studios/$STUDIO"
TARGET="$(canon_path "$(resolve_studio_target "$STUDIO_DIR" "$TARGET_OVERRIDE")")"
```

- [ ] **Step 8: Run the whole suite**

Run: `sh tests/run_all.sh`
Expected: every file `0 failed`.

- [ ] **Step 9: Commit**

```bash
git add lib/common.sh install.sh uninstall.sh doctor.sh sync-memory.sh tests/lib_test.sh tests/install_test.sh
git commit -m "fix: normalize the studio name and canonicalize the target in every script" -m "Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01EXbiTV13oWT2MjvbFXAuB2"
```

---

### Task 2: install never writes through a pre-existing symlink

**Files:**
- Modify: `install.sh` (the `CLAUDE.md` render block and the `settings.json` copy)
- Test: `tests/install_test.sh`

**Interfaces:**
- Consumes: nothing new.
- Produces: `$TARGET/CLAUDE.md` and `$TARGET/settings.json` are always regular files after an install.

- [ ] **Step 1: Write the failing test**

Append to `tests/install_test.sh` before `run_tests`:

```sh
# CLAUDE.md and settings.json used to be written through whatever was at the
# destination: a symlink there (a user's own link into ~/.claude, say) had
# the linked file overwritten while the link survived. install_entries
# removes its destination first; the two rendered files must do the same.
test_install_replaces_symlinked_files() {
  mkdir -p "$TMP/outside-cfg" "$TMP/sym"
  printf 'my global claude.md\n' > "$TMP/outside-cfg/CLAUDE.md"
  printf '{"mine":true}\n' > "$TMP/outside-cfg/settings.json"
  ln -s "$TMP/outside-cfg/CLAUDE.md" "$TMP/sym/CLAUDE.md"
  ln -s "$TMP/outside-cfg/settings.json" "$TMP/sym/settings.json"
  sh "$REPO_ROOT/install.sh" general --target "$TMP/sym" --shim-dir "$TMP/bin-sym" >/dev/null 2>&1
  assert_eq "my global claude.md" "$(cat "$TMP/outside-cfg/CLAUDE.md")" \
    "the file a CLAUDE.md link pointed at is untouched"
  assert_eq '{"mine":true}' "$(cat "$TMP/outside-cfg/settings.json")" \
    "the file a settings.json link pointed at is untouched"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -L "$TMP/sym/CLAUDE.md" ]; then _fail "CLAUDE.md is a regular file after install"; else _pass "CLAUDE.md is a regular file after install"; fi
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -L "$TMP/sym/settings.json" ]; then _fail "settings.json is a regular file after install"; else _pass "settings.json is a regular file after install"; fi
  assert_contains "$TMP/sym/CLAUDE.md" "General Studio" "CLAUDE.md is rendered in place"
}
```

Add `test_install_replaces_symlinked_files` to `run_tests`.

- [ ] **Step 2: Run it to see it fail**

Run: `sh tests/install_test.sh`
Expected: FAIL "the file a CLAUDE.md link pointed at is untouched" (it now contains the rendered studio text).

- [ ] **Step 3: Remove the destination before writing**

In `install.sh`, in the `else` branch of the `CLAUDE.md` render block, before the `{` that opens the redirect group:

```sh
  # A link at the destination would be written through; remove it first, as
  # install_entries does for memory/ and bin/.
  rm -f "$TARGET/CLAUDE.md"
```

In the `settings.json` block, before `cp "$STUDIO_DIR/settings.json" "$TARGET/settings.json"`:

```sh
  rm -f "$TARGET/settings.json"
```

- [ ] **Step 4: Run the whole suite**

Run: `sh tests/run_all.sh`
Expected: all green (`test_settings_backup` still passes — the backup happens before the removal).

- [ ] **Step 5: Commit**

```bash
git add install.sh tests/install_test.sh
git commit -m "fix: install replaces a symlinked CLAUDE.md or settings.json instead of writing through it" -m "Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01EXbiTV13oWT2MjvbFXAuB2"
```

---

### Task 3: `--purge` requires a manifest and purges the physical root

**Files:**
- Modify: `uninstall.sh:45-55`
- Test: `tests/install_test.sh`

**Interfaces:**
- Consumes: `canon_path`, `guard_target` (unchanged).
- Produces: purge refuses a root with no `.omega-ai-manifest`; on a symlinked target it removes the directory the link names, then the link.

- [ ] **Step 1: Write the failing tests**

Append to `tests/install_test.sh` before `run_tests`:

```sh
# --purge used to rm -rf any directory that passed guard_target, installed
# or not; and on a symlinked target it removed only the link.
test_uninstall_purge_requires_manifest() {
  mkdir -p "$TMP/notours/important"
  printf 'keep\n' > "$TMP/notours/important/file.txt"
  status=0
  sh "$REPO_ROOT/uninstall.sh" general --target "$TMP/notours" --shim-dir "$TMP/bin-no" --purge --yes \
    > "$TMP/notours.out" 2>&1 || status=$?
  assert_eq "1" "$status" "purge refuses a directory with no manifest"
  assert_file "$TMP/notours/important/file.txt" "a refused purge deletes nothing"
  assert_contains "$TMP/notours.out" "no manifest" "the refusal names the missing manifest"
}

test_uninstall_purge_symlinked_target() {
  mkdir -p "$TMP/realroot"
  ln -s "$TMP/realroot" "$TMP/linkroot"
  sh "$REPO_ROOT/install.sh" general --target "$TMP/linkroot" --shim-dir "$TMP/bin-link" >/dev/null 2>&1
  assert_file "$TMP/realroot/CLAUDE.md" "install through a link lands in the real root"
  sh "$REPO_ROOT/uninstall.sh" general --target "$TMP/linkroot" --shim-dir "$TMP/bin-link" --purge --yes >/dev/null 2>&1
  assert_missing "$TMP/realroot" "purge removes the real root behind the link"
  assert_missing "$TMP/linkroot" "purge removes the link too"
  assert_missing "$TMP/bin-link/claude-gen" "purge removes the shim"
}
```

Add both to `run_tests`.

- [ ] **Step 2: Run them to see them fail**

Run: `sh tests/install_test.sh`
Expected: FAIL "purge refuses a directory with no manifest" (exit 0, directory gone) and FAIL "purge removes the real root behind the link".

- [ ] **Step 3: Rewrite the purge branch**

Replace `uninstall.sh` lines 45–55 with:

```sh
if [ "$PURGE" = "1" ]; then
  # Only a root this installer wrote may be purged; the manifest is the proof.
  [ -f "$MANIFEST" ] || die "no manifest at $MANIFEST — not an omega-ai config root, refusing to purge"
  if [ "$ASSUME_YES" != "1" ]; then
    printf 'Delete the entire config root %s, including sessions and history? [y/N] ' "$TARGET"
    read -r reply
    case "$reply" in y|Y) ;; *) die "aborted" ;; esac
  fi
  # rm -rf on a symlink removes the link and keeps the directory: purge the
  # directory the target names, then the link that named it.
  real="$(canon_path "$TARGET/.")"
  rm -rf "$real"
  if [ -L "$TARGET" ]; then rm -f "$TARGET"; fi
  rm -f "$SHIM_PATH"
  log "purged $TARGET"
  exit 0
fi
```

- [ ] **Step 4: Run the whole suite**

Run: `sh tests/run_all.sh`
Expected: all green (`test_uninstall_purge`, `test_two_studios_independent` and `test_uninstall_refuses_empty_shim_name` still pass).

- [ ] **Step 5: Commit**

```bash
git add uninstall.sh tests/install_test.sh
git commit -m "fix: uninstall --purge refuses a root without a manifest and purges the physical directory" -m "Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01EXbiTV13oWT2MjvbFXAuB2"
```

---

### Task 4: Reinstall validates every input before removing the previous install; entries are read line by line

**Files:**
- Modify: `install.sh` (usage text line 25; after the `plugin.json` check at line 66; the `memory`/`bin` loop at lines 119–126; the `settings.json` block)
- Test: `tests/install_test.sh`

**Interfaces:**
- Produces: `install.sh` dies before `manifest_remove` when `studios/<studio>/CLAUDE.md` or `settings.json` is missing; a target path containing a space installs, records one manifest line per entry, and uninstalls fully.

- [ ] **Step 1: Write the failing tests**

Append to `tests/install_test.sh` before `run_tests`:

```sh
# A reinstall used to remove the previous install first and discover a
# missing studio file only while rendering — leaving a 0-byte manifest, a
# half-rendered CLAUDE.md nothing records, and no settings.json or shim.
test_reinstall_keeps_previous_install_when_studio_is_broken() {
  SB="$TMP/sandbox-atomic"
  mkdir -p "$SB"
  cp -R "$REPO_ROOT/lib" "$REPO_ROOT/shared" "$REPO_ROOT/studios" "$SB/"
  cp "$REPO_ROOT/install.sh" "$REPO_ROOT/uninstall.sh" "$REPO_ROOT/doctor.sh" "$SB/"
  sh "$SB/install.sh" general --target "$TMP/atomic" --shim-dir "$TMP/bin-atomic" >/dev/null 2>&1
  assert_file "$TMP/atomic/CLAUDE.md" "first install succeeds"
  rm "$SB/studios/general/CLAUDE.md"
  status=0
  sh "$SB/install.sh" general --target "$TMP/atomic" --shim-dir "$TMP/bin-atomic" > "$TMP/atomic.out" 2>&1 || status=$?
  assert_eq "1" "$status" "reinstall fails when the studio has no CLAUDE.md"
  assert_contains "$TMP/atomic.out" "has no CLAUDE.md" "the failure names the missing file"
  assert_file "$TMP/atomic/CLAUDE.md" "the previous CLAUDE.md is still installed"
  assert_file "$TMP/atomic/settings.json" "the previous settings.json is still installed"
  assert_file "$TMP/bin-atomic/claude-gen" "the previous shim is still installed"
  assert_contains "$TMP/atomic/.omega-ai-manifest" "CLAUDE.md" "the previous manifest is intact"
}

# install_entries' output used to be word-split, so a path with a space
# became two manifest lines that uninstall then skipped as out of scope.
test_install_path_with_space() {
  sh "$REPO_ROOT/install.sh" game-dev --target "$TMP/with space/root" --shim-dir "$TMP/with space/bin" >/dev/null 2>&1
  assert_symlink "$TMP/with space/root/memory/MEMORY.md" "a target with a space gets its links"
  assert_eq "1" "$(grep -c "^$TMP/with space/root/memory/MEMORY.md\$" "$TMP/with space/root/.omega-ai-manifest")" \
    "the manifest records the whole path on one line"
  sh "$REPO_ROOT/uninstall.sh" game-dev --target "$TMP/with space/root" --shim-dir "$TMP/with space/bin" >/dev/null 2>&1
  assert_missing "$TMP/with space/root/memory/MEMORY.md" "uninstall removes the link under a path with a space"
  assert_missing "$TMP/with space/root/bin/studio-state" "uninstall removes the bin link under a path with a space"
  assert_missing "$TMP/with space/bin/claude-gd" "uninstall removes the shim under a path with a space"
}
```

Add both to `run_tests`.

- [ ] **Step 2: Run them to see them fail**

Run: `sh tests/install_test.sh`
Expected: FAIL "the previous settings.json is still installed" and FAIL "the manifest records the whole path on one line" (expected 1, got 0).

- [ ] **Step 3: Validate inputs up front**

In `install.sh`, directly after line 66 (`[ -f "$STUDIO_DIR/.claude-plugin/plugin.json" ] || die …`):

```sh
# Everything the install reads is checked here, before the previous install
# is removed: a reinstall that dies half-way must leave the old one in place.
[ -f "$STUDIO_DIR/CLAUDE.md" ] || die "studio has no CLAUDE.md: $STUDIO"
[ -f "$STUDIO_DIR/settings.json" ] || die "studio has no settings.json: $STUDIO"
```

In the `settings.json` block, change `elif [ -f "$STUDIO_DIR/settings.json" ]; then` to `else` (the file is now guaranteed).

- [ ] **Step 4: Read entries line by line**

Replace the `memory`/`bin` loop (lines 119–126) with:

```sh
# Only memory/ and bin/ live in the config root; skills, agents and hooks are
# served by the plugin. Shared first, studio second so the studio wins. The
# entries are read line by line: a path with a space is one entry.
for dir in memory bin; do
  for src in "$REPO_ROOT/shared/$dir" "$STUDIO_DIR/$dir"; do
    install_entries "$src" "$TARGET/$dir" "$MODE" | while IFS= read -r installed; do
      manifest_add "$MANIFEST" "$installed"
    done
  done
done
```

Delete the usage line `Install paths must not contain spaces.` (line 25) and the blank line before it.

- [ ] **Step 5: Run the whole suite**

Run: `sh tests/run_all.sh`
Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add install.sh tests/install_test.sh
git commit -m "fix: install validates the studio before removing the previous install and keeps a spaced path whole" -m "Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01EXbiTV13oWT2MjvbFXAuB2"
```

---

### Task 5: The manifest records mode and shim; uninstall removes only a shim that launches this root

**Files:**
- Modify: `lib/common.sh` (`manifest_remove`; new `manifest_meta`, `shim_owned`)
- Modify: `install.sh` (the `: > "$MANIFEST"` line)
- Modify: `uninstall.sh` (shim resolution and removal)
- Test: `tests/lib_test.sh`, `tests/install_test.sh`

**Interfaces:**
- Produces: `manifest_meta MANIFEST KEY` prints the value of the header line `# KEY=value` (empty when absent); `shim_owned SHIM TARGET` succeeds when SHIM is a file containing `CLAUDE_CONFIG_DIR="<TARGET>"`. The manifest's first two lines are `# mode=<mode>` and `# shim=<abs path>`. Task 6 reads both keys.

- [ ] **Step 1: Write the failing lib test**

Append to `tests/lib_test.sh` before `run_tests`:

```sh
test_manifest_header() {
  mkdir -p "$TMP/mh/root"
  printf '# mode=copy\n# shim=/some where/claude-x\n%s\n' "$TMP/mh/root/file" > "$TMP/mh/root/.omega-ai-manifest"
  printf 'x\n' > "$TMP/mh/root/file"
  assert_eq "copy" "$(manifest_meta "$TMP/mh/root/.omega-ai-manifest" mode)" "manifest_meta reads the mode"
  assert_eq "/some where/claude-x" "$(manifest_meta "$TMP/mh/root/.omega-ai-manifest" shim)" \
    "manifest_meta reads a shim path with a space"
  assert_eq "" "$(manifest_meta "$TMP/mh/root/.omega-ai-manifest" nope)" "manifest_meta prints nothing for an absent key"
  assert_eq "" "$(manifest_meta "$TMP/mh/none" mode)" "manifest_meta prints nothing for a missing manifest"
  manifest_remove "$TMP/mh/root/.omega-ai-manifest" "$TMP/mh/root" "" 2> "$TMP/mh/warn.out"
  assert_missing "$TMP/mh/root/file" "manifest_remove still removes the entries"
  assert_not_contains "$TMP/mh/warn.out" "skipping" "manifest_remove does not treat header lines as entries"
  printf '#!/bin/sh\nCLAUDE_CONFIG_DIR="/roots/a" exec claude "$@"\n' > "$TMP/mh/shim"
  assert_status 0 "shim_owned accepts the shim of its root" -- shim_owned "$TMP/mh/shim" /roots/a
  assert_status 1 "shim_owned rejects the shim of another root" -- shim_owned "$TMP/mh/shim" /roots/b
  assert_status 1 "shim_owned rejects a missing shim" -- shim_owned "$TMP/mh/none" /roots/a
}
```

Add `test_manifest_header` to `run_tests`.

- [ ] **Step 2: Run it to see it fail**

Run: `sh tests/lib_test.sh`
Expected: FAIL "manifest_meta reads the mode" (not found).

- [ ] **Step 3: Add the helpers and skip header lines**

In `lib/common.sh`, before `manifest_remove`:

```sh
# manifest_meta MANIFEST KEY — the value of the header line "# KEY=value"
# the installer writes (mode, shim); empty when the manifest or the key is
# absent. One key per line, so a shim path with a space survives.
manifest_meta() {
  [ -f "$1" ] || return 0
  sed -n "s/^# $2=//p" "$1" | head -n 1
}

# shim_owned SHIM TARGET — SHIM launches Claude Code against TARGET. Two
# studios can share a shim directory and a root can be reinstalled at another
# target; a shim that points elsewhere is not this root's to delete.
shim_owned() {
  [ -f "$1" ] && grep -qF "CLAUDE_CONFIG_DIR=\"$2\"" "$1"
}
```

In `manifest_remove`, after `[ -n "$_entry" ] || continue`, add:

```sh
    case "$_entry" in '#'*) continue ;; esac
```

and extend the function comment with one line: `# Header lines ("# key=value") are metadata, never paths.`

- [ ] **Step 4: Run the lib test**

Run: `sh tests/lib_test.sh`
Expected: all pass.

- [ ] **Step 5: Write the failing install tests**

In `test_install_content`, after the `"writes a manifest"` assertion, add:

```sh
  assert_eq "# mode=symlink" "$(sed -n '1p' "$TMP/gd/.omega-ai-manifest")" "manifest starts with the mode"
  assert_eq "# shim=$TMP/bin/claude-gd" "$(sed -n '2p' "$TMP/gd/.omega-ai-manifest")" "manifest records the shim path"
```

In `test_install_copy_mode`, after the snapshot assertion, add:

```sh
  assert_eq "# mode=copy" "$(sed -n '1p' "$TMP/cp/.omega-ai-manifest")" "copy mode is recorded in the manifest"
```

Append before `run_tests`:

```sh
# Two roots can share a shim directory; the shim launches whichever was
# installed last. Uninstalling the other root used to delete it anyway.
test_uninstall_keeps_shim_of_another_root() {
  sh "$REPO_ROOT/install.sh" general --target "$TMP/shA" --shim-dir "$TMP/bin-shared" >/dev/null 2>&1
  sh "$REPO_ROOT/install.sh" general --target "$TMP/shB" --shim-dir "$TMP/bin-shared" >/dev/null 2>&1
  assert_contains "$TMP/bin-shared/claude-gen" "CLAUDE_CONFIG_DIR=\"$TMP/shB\"" "the shared shim launches the second root"
  sh "$REPO_ROOT/uninstall.sh" general --target "$TMP/shA" > "$TMP/shA.out" 2>&1
  assert_missing "$TMP/shA/CLAUDE.md" "the first root is uninstalled"
  assert_file "$TMP/bin-shared/claude-gen" "the shim that launches the second root survives"
  assert_contains "$TMP/shA.out" "keeping it" "uninstall says why the shim stays"
  sh "$REPO_ROOT/uninstall.sh" general --target "$TMP/shB" >/dev/null 2>&1
  assert_missing "$TMP/bin-shared/claude-gen" "uninstall without --shim-dir removes the recorded shim"
}
```

Add `test_uninstall_keeps_shim_of_another_root` to `run_tests`.

- [ ] **Step 6: Run them to see them fail**

Run: `sh tests/install_test.sh`
Expected: FAIL "manifest starts with the mode", FAIL "the shim that launches the second root survives".

- [ ] **Step 7: Write the header at install time**

In `install.sh`, replace `: > "$MANIFEST"` with:

```sh
  # The header tells uninstall and doctor what this install chose, so neither
  # has to be told --shim-dir or guess the mode.
  printf '# mode=%s\n# shim=%s\n' "$MODE" "$SHIM_PATH" > "$MANIFEST"
```

- [ ] **Step 8: Use the recorded shim in uninstall**

In `uninstall.sh`, replace the two lines `MANIFEST="$TARGET/.omega-ai-manifest"` and `SHIM_PATH="${SHIM_DIR%/}/$SHIM_NAME"` with:

```sh
MANIFEST="$TARGET/.omega-ai-manifest"
# The shim the install recorded wins over the derived path; a manifest from
# the previous installer records none, and --shim-dir is the fallback.
SHIM_PATH="$(manifest_meta "$MANIFEST" shim)"
if [ -n "$SHIM_PATH" ]; then
  guard_target "$(dirname "$SHIM_PATH")" "$REPO_ROOT"
else
  SHIM_PATH="${SHIM_DIR%/}/$SHIM_NAME"
fi
if [ -f "$SHIM_PATH" ] && ! shim_owned "$SHIM_PATH" "$TARGET"; then
  warn "shim $SHIM_PATH launches another config root; keeping it"
  SHIM_PATH=""
fi
```

Replace the final `rm -f "$SHIM_PATH"` (the non-purge path) with `[ -z "$SHIM_PATH" ] || rm -f "$SHIM_PATH"`, and in the purge branch replace `rm -f "$SHIM_PATH"` with the same line. Update the `--help` line to `Usage: uninstall.sh <studio> [--target DIR] [--shim-dir DIR] [--purge] [--yes]   (--shim-dir only for installs made before the manifest recorded the shim)`.

- [ ] **Step 9: Run the whole suite**

Run: `sh tests/run_all.sh`
Expected: all green. `test_uninstall_scopes_manifest_entries` still removes the shim (recorded and owned).

- [ ] **Step 10: Commit**

```bash
git add lib/common.sh install.sh uninstall.sh tests/lib_test.sh tests/install_test.sh
git commit -m "feat: manifest records mode and shim; uninstall removes only the shim that launches this root" -m "Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01EXbiTV13oWT2MjvbFXAuB2"
```

---

### Task 6: doctor reads the manifest — shim identity and the copy-mode plugin directory

**Files:**
- Modify: `doctor.sh` (plugin dir resolution at lines 22–24; the shim report at lines 100–105)
- Test: `tests/install_test.sh`

**Interfaces:**
- Consumes: `manifest_meta`, `shim_owned` (Task 5).
- Produces: doctor lines `plugin dir:   <dir>` and `shim:         ok|stale (…)|MISSING|not recorded …`; `failed=1` on anything but `ok`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/install_test.sh` before `run_tests`:

```sh
# "shim on PATH: yes" used to be `command -v <name>` — it reported the user's
# pre-plugin shim (no --plugin-dir, another root) as a working install.
test_doctor_shim_identity() {
  sh "$REPO_ROOT/install.sh" general --target "$TMP/dsi" --shim-dir "$TMP/bin-dsi" >/dev/null 2>&1
  sh "$REPO_ROOT/doctor.sh" general --target "$TMP/dsi" > "$TMP/dsi.out" 2>&1
  assert_contains "$TMP/dsi.out" "shim:         ok $TMP/bin-dsi/claude-gen" "doctor reports the recorded shim as ok"
  printf '#!/usr/bin/env sh\nCLAUDE_CONFIG_DIR="%s" exec claude "$@"\n' "$TMP/dsi" > "$TMP/bin-dsi/claude-gen"
  status=0
  sh "$REPO_ROOT/doctor.sh" general --target "$TMP/dsi" > "$TMP/dsi2.out" 2>&1 || status=$?
  assert_eq "1" "$status" "doctor fails on a shim without --plugin-dir"
  assert_contains "$TMP/dsi2.out" "shim:         stale (no --plugin-dir)" "doctor names the stale shim"
  printf '#!/usr/bin/env sh\nCLAUDE_CONFIG_DIR="/elsewhere" exec claude --plugin-dir x "$@"\n' > "$TMP/bin-dsi/claude-gen"
  status=0
  sh "$REPO_ROOT/doctor.sh" general --target "$TMP/dsi" > "$TMP/dsi3.out" 2>&1 || status=$?
  assert_eq "1" "$status" "doctor fails on a shim that launches another root"
  assert_contains "$TMP/dsi3.out" "shim:         stale (launches another root)" "doctor names the foreign shim"
  rm "$TMP/bin-dsi/claude-gen"
  status=0
  sh "$REPO_ROOT/doctor.sh" general --target "$TMP/dsi" > "$TMP/dsi4.out" 2>&1 || status=$?
  assert_eq "1" "$status" "doctor fails on a missing shim"
  assert_contains "$TMP/dsi4.out" "shim:         MISSING" "doctor reports the missing shim"
}

# Counts and the plugin manifest were read from the checkout even in copy
# mode, so a deleted snapshot still reported "skills 8 agents 3".
test_doctor_inspects_copy_mode_snapshot() {
  sh "$REPO_ROOT/install.sh" game-dev --target "$TMP/dcp" --shim-dir "$TMP/bin-dcp" --mode copy >/dev/null 2>&1
  sh "$REPO_ROOT/doctor.sh" game-dev --target "$TMP/dcp" > "$TMP/dcp.out" 2>&1
  assert_contains "$TMP/dcp.out" "plugin dir:   $TMP/dcp/studio" "doctor inspects the snapshot in copy mode"
  rm -rf "$TMP/dcp/studio"
  status=0
  sh "$REPO_ROOT/doctor.sh" game-dev --target "$TMP/dcp" > "$TMP/dcp2.out" 2>&1 || status=$?
  assert_eq "1" "$status" "doctor fails when the snapshot is gone"
  assert_contains "$TMP/dcp2.out" "no plugin manifest at $TMP/dcp/studio" "doctor names the missing snapshot manifest"
}
```

Add both to `run_tests`.

- [ ] **Step 2: Run them to see them fail**

Run: `sh tests/install_test.sh`
Expected: FAIL "doctor reports the recorded shim as ok", FAIL "doctor inspects the snapshot in copy mode".

- [ ] **Step 3: Resolve the plugin dir from the manifest**

In `doctor.sh`, replace lines 22–24 (`SHIM_NAME=…`, `PLUGIN_JSON=…`, `REQUIRES=…`) with:

```sh
SHIM_NAME="$(json_field "$STUDIO_DIR/studio.json" shim)"
MANIFEST="$TARGET/.omega-ai-manifest"
# What the shim actually loads: the snapshot in copy mode, the checkout
# otherwise. The manifest header says which; an older manifest says nothing
# and is treated as symlink mode.
MODE="$(manifest_meta "$MANIFEST" mode)"
if [ "$MODE" = "copy" ]; then PLUGIN_DIR="$TARGET/studio"; else PLUGIN_DIR="$STUDIO_DIR"; fi
PLUGIN_JSON="$PLUGIN_DIR/.claude-plugin/plugin.json"
REQUIRES="$STUDIO_DIR/requires.txt"
RECORDED_SHIM="$(manifest_meta "$MANIFEST" shim)"
```

After the `log "config root:  $TARGET"` line add `log "plugin dir:   $PLUGIN_DIR"`. In the plugin block replace the two `count_skills "$STUDIO_DIR"` / `count_agents "$STUDIO_DIR"` calls and `[ -f "$STUDIO_DIR/hooks/hooks.json" ]` with `"$PLUGIN_DIR"` / `"$PLUGIN_DIR/hooks/hooks.json"`. Rewrite the comment above `count_skills` to: `# Plugin content is counted where the shim loads it from (see PLUGIN_DIR).`

- [ ] **Step 4: Report the recorded shim**

Replace lines 100–105 (`log "launch: …"` through the `fi` of the `command -v` block) with:

```sh
log "launch:       $SHIM_NAME"
# The shim the manifest recorded is the one this install wrote; `command -v`
# would happily report an older shim of the same name on PATH.
if [ -z "$RECORDED_SHIM" ]; then
  log "shim:         not recorded — manifest predates this installer; run install.sh $STUDIO again"
  failed=1
elif [ ! -f "$RECORDED_SHIM" ]; then
  log "shim:         MISSING $RECORDED_SHIM — run install.sh $STUDIO"
  failed=1
elif ! shim_owned "$RECORDED_SHIM" "$TARGET"; then
  log "shim:         stale (launches another root) $RECORDED_SHIM — run install.sh $STUDIO"
  failed=1
elif ! grep -q -- '--plugin-dir' "$RECORDED_SHIM"; then
  log "shim:         stale (no --plugin-dir) $RECORDED_SHIM — run install.sh $STUDIO"
  failed=1
else
  log "shim:         ok $RECORDED_SHIM"
  shim_dir="$(dirname "$RECORDED_SHIM")"
  case ":$PATH:" in
    *":$shim_dir:"*) log "shim on PATH: yes" ;;
    *) log "shim on PATH: no — add $shim_dir to PATH" ;;
  esac
fi
```

- [ ] **Step 5: Run the whole suite**

Run: `sh tests/run_all.sh`
Expected: all green (`test_doctor_plugin_report` still matches `plugin:       game-dev 0.1.0`).

- [ ] **Step 6: Commit**

```bash
git add doctor.sh tests/install_test.sh
git commit -m "fix: doctor checks the recorded shim's identity and inspects the copy-mode snapshot" -m "Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01EXbiTV13oWT2MjvbFXAuB2"
```

---

### Task 7: doctor fails on missing files and a stale layout, judges leaks on canonical paths, matches plugin ids literally

**Files:**
- Modify: `doctor.sh` (lines 31–32, 75, 107–127; new stale-layout block)
- Test: `tests/install_test.sh`

**Interfaces:**
- Consumes: `canon_path`.
- Produces: exit 1 on `CLAUDE.md: MISSING` / `settings: MISSING`, on any symlink under `$TARGET/{skills,agents,commands,hooks}/` or any dangling symlink directly under `$TARGET`, and on a link whose canonical destination is inside the canonical `~/.claude`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/install_test.sh` before `run_tests`:

```sh
test_doctor_fails_on_missing_files() {
  sh "$REPO_ROOT/install.sh" general --target "$TMP/dmf" --shim-dir "$TMP/bin-dmf" >/dev/null 2>&1
  rm "$TMP/dmf/CLAUDE.md"
  status=0
  sh "$REPO_ROOT/doctor.sh" general --target "$TMP/dmf" > "$TMP/dmf.out" 2>&1 || status=$?
  assert_eq "1" "$status" "doctor fails when CLAUDE.md is missing"
  assert_contains "$TMP/dmf.out" "CLAUDE.md:    MISSING" "doctor reports the missing CLAUDE.md"
}

# ~/.claude itself can be a symlink (dotfiles), and a link destination can be
# spelled with '..'; the textual comparison used to miss both. Fake HOME only.
test_doctor_detects_leak_through_symlinked_dot_claude() {
  FAKE="$TMP/fakehome-dot"
  mkdir -p "$FAKE/dotfiles/claude"
  printf '{}\n' > "$FAKE/dotfiles/claude/settings.json"
  ln -s "$FAKE/dotfiles/claude" "$FAKE/.claude"
  ( HOME="$FAKE" sh "$REPO_ROOT/install.sh" general --target "$FAKE/root" --shim-dir "$FAKE/bin" ) >/dev/null 2>&1
  ln -s "$FAKE/dotfiles/claude/settings.json" "$FAKE/root/leak"
  status=0
  ( HOME="$FAKE" sh "$REPO_ROOT/doctor.sh" general --target "$FAKE/root" ) > "$TMP/dot.out" 2>&1 || status=$?
  assert_eq "1" "$status" "doctor exits 1 on a link into the directory ~/.claude points at"
  assert_contains "$TMP/dot.out" "leak" "doctor names the leaking link"
  rm "$FAKE/root/leak"
  ln -s "$FAKE/root/../.claude/settings.json" "$FAKE/root/leak2"
  status=0
  ( HOME="$FAKE" sh "$REPO_ROOT/doctor.sh" general --target "$FAKE/root" ) > "$TMP/dot2.out" 2>&1 || status=$?
  assert_eq "1" "$status" "doctor exits 1 on a '..'-spelled link into ~/.claude"
  rm "$FAKE/root/leak2"
  status=0
  ( HOME="$FAKE" sh "$REPO_ROOT/doctor.sh" general --target "$FAKE/root" ) > "$TMP/dot3.out" 2>&1 || status=$?
  assert_eq "0" "$status" "doctor passes again with the probes removed"
}

# A plugin id was interpolated into a grep pattern: "foo.bar@m" matched
# "fooXbar@m" and an unenabled plugin was reported enabled.
test_doctor_matches_plugin_ids_literally() {
  SB="$TMP/sandbox-ids"
  mkdir -p "$SB"
  cp -R "$REPO_ROOT/lib" "$REPO_ROOT/shared" "$REPO_ROOT/studios" "$SB/"
  cp "$REPO_ROOT/install.sh" "$REPO_ROOT/doctor.sh" "$SB/"
  printf 'plugin foo.bar@market\n' > "$SB/studios/general/requires.txt"
  printf '{ "enabledPlugins": { "fooXbar@market": true } }\n' > "$SB/studios/general/settings.json"
  sh "$SB/install.sh" general --target "$TMP/ids" --shim-dir "$TMP/bin-ids" >/dev/null 2>&1 || true
  status=0
  sh "$SB/doctor.sh" general --target "$TMP/ids" > "$TMP/ids.out" 2>&1 || status=$?
  assert_eq "1" "$status" "doctor fails when the enabled id only matches as a pattern"
  assert_contains "$TMP/ids.out" "foo.bar@market NOT ENABLED" "doctor names the plugin as not enabled"
}

# The pre-plugin installer linked skills/, agents/, commands/ and hooks/ into
# the root. After profiles/ disappeared those links dangle, and the doctor
# used to report such a root as healthy.
test_doctor_flags_stale_layout() {
  sh "$REPO_ROOT/install.sh" general --target "$TMP/stale" --shim-dir "$TMP/bin-stale" >/dev/null 2>&1
  mkdir -p "$TMP/stale/skills"
  ln -s "$TMP/gone/skill" "$TMP/stale/skills/old-skill"
  printf '%s\n' "$TMP/stale/skills/old-skill" >> "$TMP/stale/.omega-ai-manifest"
  status=0
  sh "$REPO_ROOT/doctor.sh" general --target "$TMP/stale" > "$TMP/stale.out" 2>&1 || status=$?
  assert_eq "1" "$status" "doctor fails on a skills/ link from the previous installer"
  assert_contains "$TMP/stale.out" "stale layout from a previous installer" "doctor explains the stale layout"
  assert_contains "$TMP/stale.out" "run install.sh general again" "doctor says how to fix it"
  sh "$REPO_ROOT/install.sh" general --target "$TMP/stale" --shim-dir "$TMP/bin-stale" >/dev/null 2>&1
  assert_missing "$TMP/stale/skills/old-skill" "reinstall removes the recorded stale link"
  status=0
  sh "$REPO_ROOT/doctor.sh" general --target "$TMP/stale" >/dev/null 2>&1 || status=$?
  assert_eq "0" "$status" "doctor passes after the reinstall"
}
```

Add all four to `run_tests`.

- [ ] **Step 2: Run them to see them fail**

Run: `sh tests/install_test.sh`
Expected: FAIL "doctor fails when CLAUDE.md is missing" (exit 0), FAIL "doctor exits 1 on a link into the directory ~/.claude points at", FAIL "doctor fails when the enabled id only matches as a pattern", FAIL "doctor fails on a skills/ link from the previous installer".

- [ ] **Step 3: Missing files fail**

Replace `doctor.sh` lines 31–32 with:

```sh
if [ -f "$TARGET/CLAUDE.md" ]; then log "CLAUDE.md:    present"; else log "CLAUDE.md:    MISSING"; failed=1; fi
if [ -f "$TARGET/settings.json" ]; then log "settings:     present"; else log "settings:     MISSING"; failed=1; fi
```

- [ ] **Step 4: Match plugin ids literally**

Replace line 75 with:

```sh
  # -F: a plugin id is data ('.' in it must not match any character).
  if grep -F "\"$req\"" "$TARGET/settings.json" 2>/dev/null | grep -q '"[[:space:]]*:[[:space:]]*true'; then
```

- [ ] **Step 5: Stale layout check**

Insert before the leakage comment block (before `# Leakage check: …`):

```sh
# The pre-plugin installer linked skills/, agents/, commands/ and hooks/ into
# the root; any symlink under those, or a dangling link directly under the
# root, is that layout left behind — a reinstall removes what its manifest
# recorded.
stale=""
for d in skills agents commands hooks; do
  for l in "$TARGET/$d"/*; do
    [ -L "$l" ] && stale="$stale $d/$(basename "$l")"
  done
done
for l in "$TARGET"/*; do
  if [ -L "$l" ] && [ ! -e "$l" ]; then stale="$stale $(basename "$l")"; fi
done
if [ -n "$stale" ]; then
  warn "stale layout from a previous installer:$stale — run install.sh $STUDIO again"
  failed=1
fi
```

- [ ] **Step 6: Canonical leak check**

Replace lines 107–127 (the leakage block through `log "leakage: none"`) with:

```sh
# Leakage check: nothing inside this root may resolve into ~/.claude, and the
# root itself may not be ~/.claude. Both sides are canonical: ~/.claude may
# itself be a symlink (dotfiles), and a link destination may be spelled with
# '..'. Only symlinks are inspected, to a depth of 3.
home_canon="$(canon_path "${HOME%/}/.")"
home_canon="${home_canon%/}"
claude_canon="$(canon_path "$home_canon/.claude/.")"
# is_leak CANONICAL_PATH — inside ~/.claude, as spelled or as resolved.
is_leak() {
  case "$1" in
    "$home_canon/.claude"|"$home_canon/.claude"/*|"$claude_canon"|"$claude_canon"/*) return 0 ;;
  esac
  return 1
}
leaks="$(find "$TARGET" -maxdepth 3 -type l -print 2>/dev/null | while IFS= read -r link; do
  dest="$(readlink "$link" 2>/dev/null || true)"
  case "$dest" in /*) ;; *) dest="$(dirname "$link")/$dest" ;; esac
  if is_leak "$(canon_path "$dest")"; then printf '%s -> %s\n' "$link" "$dest"; fi
done)"
if is_leak "$(canon_path "${TARGET%/}/.")"; then
  leaks="$leaks
config root is inside ~/.claude: $TARGET"
fi
if [ -n "$(printf '%s' "$leaks" | tr -d '[:space:]')" ]; then
  log "leakage:"
  printf '%s\n' "$leaks" | sed 's/^/  /'
  exit 1
fi
log "leakage: none"
```

- [ ] **Step 7: Run the whole suite**

Run: `sh tests/run_all.sh`
Expected: all green (`test_doctor_detects_leak` still passes; `test_install_reinstall_cleans_stale_entries` keeps `hooks/user-hook.sh`, a regular file, which is not stale).

- [ ] **Step 8: Commit**

```bash
git add doctor.sh tests/install_test.sh
git commit -m "fix: doctor fails on missing files and a stale layout, canonicalizes the leak check, matches plugin ids literally" -m "Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01EXbiTV13oWT2MjvbFXAuB2"
```

---

### Task 8: install reports the doctor result last; dry run previews the manifest cleanup

**Files:**
- Modify: `lib/common.sh` (`manifest_remove` honours `DRY_RUN`)
- Modify: `install.sh` (the manifest block; the final doctor call)
- Test: `tests/install_test.sh`

**Interfaces:**
- Produces: `--dry-run` over an existing root prints `DRY  rm -rf <entry>` per recorded entry and `DRY  rm -f <manifest>`; a wet install ends with `Installed. Launch with: <shim>` only when the doctor passed, otherwise `warning: installed, but doctor found problems …` and exit 1.

- [ ] **Step 1: Write the failing tests**

Append to `tests/install_test.sh` before `run_tests`:

```sh
# "--dry-run prints every action" was false on a reinstall: the removal of
# the previous install's entries was skipped silently.
test_install_dry_run_previews_removal() {
  sh "$REPO_ROOT/install.sh" general --target "$TMP/dryre" --shim-dir "$TMP/bin-dryre" >/dev/null 2>&1
  before="$(wc -l < "$TMP/dryre/.omega-ai-manifest" | tr -d ' ')"
  sh "$REPO_ROOT/install.sh" general --target "$TMP/dryre" --shim-dir "$TMP/bin-dryre" --dry-run > "$TMP/dryre.out" 2>&1
  assert_contains "$TMP/dryre.out" "DRY  rm -rf $TMP/dryre/CLAUDE.md" "dry run previews the removal of a recorded entry"
  assert_file "$TMP/dryre/CLAUDE.md" "dry run removes nothing"
  assert_eq "$before" "$(wc -l < "$TMP/dryre/.omega-ai-manifest" | tr -d ' ')" "dry run leaves the manifest alone"
  assert_file "$TMP/bin-dryre/claude-gen" "dry run keeps the shim"
}

# "Installed." used to print before the doctor ran, then the doctor failed.
test_install_reports_doctor_result_last() {
  sh "$REPO_ROOT/install.sh" general --target "$TMP/last" --shim-dir "$TMP/bin-last" > "$TMP/last.out" 2>&1
  assert_eq "Installed. Launch with: claude-gen" "$(tail -n 1 "$TMP/last.out")" "a clean install ends with the launch line"
  SB="$TMP/sandbox-last"
  mkdir -p "$SB"
  cp -R "$REPO_ROOT/lib" "$REPO_ROOT/shared" "$REPO_ROOT/studios" "$SB/"
  cp "$REPO_ROOT/install.sh" "$REPO_ROOT/doctor.sh" "$SB/"
  printf '{ "name": "wrong", "version": "0.1.0", "description": "x" }\n' > "$SB/studios/general/.claude-plugin/plugin.json"
  status=0
  sh "$SB/install.sh" general --target "$TMP/last2" --shim-dir "$TMP/bin-last2" > "$TMP/last2.out" 2>&1 || status=$?
  assert_eq "1" "$status" "an install whose doctor fails exits 1"
  assert_not_contains "$TMP/last2.out" "Installed. Launch with" "no launch line is printed when the doctor fails"
  assert_contains "$TMP/last2.out" "doctor found problems" "the failure is stated after the doctor report"
}
```

Add both to `run_tests`.

- [ ] **Step 2: Run them to see them fail**

Run: `sh tests/install_test.sh`
Expected: FAIL "dry run previews the removal of a recorded entry", FAIL "a clean install ends with the launch line".

- [ ] **Step 3: `manifest_remove` honours `DRY_RUN`**

In `lib/common.sh` `manifest_remove`, change `rm -rf "$_entry"` to `run rm -rf "$_entry"` and `rm -f "$_m"` to `run rm -f "$_m"`. Add to the function comment: `# Under DRY_RUN=1 every removal is printed, not performed.`

- [ ] **Step 4: Preview the cleanup in install**

In `install.sh`, restructure the manifest block so `manifest_remove` runs in both modes:

```sh
MANIFEST="$TARGET/.omega-ai-manifest"
if [ "$DRY_RUN" != "1" ]; then
  # settings.json is the one installed file Claude Code mutates in-session,
  # and the previous manifest records it — so a differing copy is preserved
  # before the old entries are removed, never silently discarded.
  if [ -f "$TARGET/settings.json" ] && ! cmp -s "$STUDIO_DIR/settings.json" "$TARGET/settings.json"; then
    backup="$TARGET/settings.json.bak-$(date +%Y%m%d%H%M%S)"
    cp "$TARGET/settings.json" "$backup"
    warn "existing settings.json differed; backed up to $backup"
  fi
fi
# A previous install of this studio leaves a manifest behind. Remove what it
# recorded before writing anything (printed, not performed, in a dry run).
manifest_remove "$MANIFEST" "$TARGET" "$SHIM_PATH"
if [ "$DRY_RUN" != "1" ]; then
  # The pre-plugin layout linked skills, agents, commands and hooks into the
  # root; removing those entries leaves their directories behind, empty.
  # rmdir takes only an empty directory, so one that still holds user files
  # stays.
  for d in agents skills commands hooks; do
    rmdir "$TARGET/$d" 2>/dev/null || true
  done
  # The header tells uninstall and doctor what this install chose, so neither
  # has to be told --shim-dir or guess the mode.
  printf '# mode=%s\n# shim=%s\n' "$MODE" "$SHIM_PATH" > "$MANIFEST"
fi
```

- [ ] **Step 5: Doctor result last**

Replace the tail of `install.sh` (from `log ""` / `log "Installed. …"` to the end) with:

```sh
if [ "$DRY_RUN" = "1" ]; then
  log ""
  log "(dry run complete)"
else
  log ""
  if sh "$REPO_ROOT/doctor.sh" "$STUDIO" --target "$TARGET"; then
    log ""
    log "Installed. Launch with: $SHIM_NAME"
  else
    warn "installed, but doctor found problems (see above) — fix them before launching $SHIM_NAME"
    exit 1
  fi
fi
```

- [ ] **Step 6: Run the whole suite**

Run: `sh tests/run_all.sh`
Expected: all green. `test_install_dry_run` still creates nothing (no manifest exists on a fresh target, so nothing is previewed).

- [ ] **Step 7: Commit**

```bash
git add lib/common.sh install.sh tests/install_test.sh
git commit -m "fix: install prints the launch line only after a clean doctor; dry run previews manifest cleanup" -m "Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01EXbiTV13oWT2MjvbFXAuB2"
```

---

### Task 9: Tests never touch the real home; version assertions accept any semver

**Files:**
- Modify: `tests/install_test.sh` (`test_studio_contract`, `test_install_guard`, `test_doctor_detects_leak`, `test_option_value_required`, `test_doctor_plugin_report`)

**Interfaces:** none.

- [ ] **Step 1: Semver, not a literal**

In `test_studio_contract`, replace the `assert_eq "0.1.0" …` assertion with:

```sh
    TESTS_RUN=$((TESTS_RUN + 1))
    if printf '%s' "$(json_field "$dir/.claude-plugin/plugin.json" version)" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
      _pass "$name plugin.json declares a semver version"
    else
      _fail "$name plugin.json declares a semver version"
    fi
```

In `test_doctor_plugin_report`, change the pattern `"plugin:       game-dev 0.1.0"` to `"plugin:       game-dev [0-9]"`.

- [ ] **Step 2: Fake HOME for the guard test**

Replace `test_install_guard` with:

```sh
# Runs under a fake $HOME: a guard_target regression must never write into
# the developer's live ~/.claude before the assertion fails.
test_install_guard() {
  FAKE="$TMP/fakehome-guard"
  mkdir -p "$FAKE/.claude"
  status=0
  ( HOME="$FAKE" sh "$REPO_ROOT/install.sh" general --target "$FAKE/.claude" --shim-dir "$TMP/bin" >/dev/null 2>&1 ) || status=$?
  assert_eq "1" "$status" "refuses ~/.claude as target"
  status=0
  ( HOME="$FAKE" sh "$REPO_ROOT/install.sh" general --target "$FAKE" --shim-dir "$TMP/bin" >/dev/null 2>&1 ) || status=$?
  assert_eq "1" "$status" "refuses home as target"
  assert_status 1 "refuses in-repo target" -- \
    sh "$REPO_ROOT/install.sh" general --target "$REPO_ROOT/studios" --shim-dir "$TMP/bin"
  assert_missing "$TMP/bin/claude-gen" "no shim written by a refused install"
  assert_missing "$FAKE/.claude/CLAUDE.md" "refused install writes nothing into ~/.claude"
}
```

- [ ] **Step 3: Fake HOME for the leak test**

In `test_doctor_detects_leak`, add at the top:

```sh
  FAKE="$TMP/fakehome-leak"
  mkdir -p "$FAKE/.claude"
  printf '{}\n' > "$FAKE/.claude/settings.json"
```

then replace every `$HOME` in the function with `$FAKE`, and run each `sh "$REPO_ROOT/doctor.sh" …` as `( HOME="$FAKE" sh "$REPO_ROOT/doctor.sh" … )` (keep the existing redirections and `|| status=$?`). Replace the comment above the function with: `# Runs under a fake $HOME; nothing under the real ~/.claude is read or touched.`

- [ ] **Step 4: Always pass `--shim-dir`**

In `test_option_value_required`, change the `--mode ""` call to:

```sh
  assert_status 1 "install refuses an empty --mode" -- \
    sh "$REPO_ROOT/install.sh" general --mode "" --target "$TMP/opt" --shim-dir "$TMP/bin-opt"
```

- [ ] **Step 5: Run the whole suite**

Run: `sh tests/run_all.sh`
Expected: all green; the assertion count is unchanged or higher.

- [ ] **Step 6: Commit**

```bash
git add tests/install_test.sh
git commit -m "test: guard and leak tests run under a fake HOME; version assertions accept any semver" -m "Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01EXbiTV13oWT2MjvbFXAuB2"
```

---

### Task 10: Studio memory is loaded through a `CLAUDE.md` import; README matches the installer

**Files:**
- Modify: `install.sh` (the `CLAUDE.md` render group)
- Modify: `README.md`
- Test: `tests/install_test.sh`

**Interfaces:**
- Produces: the rendered config-root `CLAUDE.md` ends with `@memory/MEMORY.md` when the studio (or `shared/`) ships a `memory/MEMORY.md`. Per the Claude Code memory reference (https://code.claude.com/docs/en/memory, "Import additional files"): "CLAUDE.md files can import additional files using `@path/to/import` syntax. Imported files are expanded and loaded into context at launch alongside the CLAUDE.md that references them." and "Relative paths resolve relative to the file containing the import, not the working directory." The config-root `CLAUDE.md` is user scope, so no external-import dialog applies. Auto memory is separate: "Each project gets its own memory directory at `~/.claude/projects/<project>/memory/`" (under `CLAUDE_CONFIG_DIR` when set).

- [ ] **Step 1: Write the failing test**

In `test_install_content`, after the `"rendered CLAUDE.md warns it is generated"` assertion, add:

```sh
  assert_contains "$TMP/gd/CLAUDE.md" "^@memory/MEMORY.md" "rendered CLAUDE.md imports the studio memory"
```

In `test_doctor` (which installs `general`, a studio with no `memory/`), after the first install line add:

```sh
  assert_not_contains "$TMP/gen/CLAUDE.md" "@memory/MEMORY.md" "a studio without memory/ imports nothing"
```

- [ ] **Step 2: Run it to see it fail**

Run: `sh tests/install_test.sh`
Expected: FAIL "rendered CLAUDE.md imports the studio memory".

- [ ] **Step 3: Emit the import**

In `install.sh`'s render group, after `cat "$STUDIO_DIR/CLAUDE.md"` and before the closing `} > "$TARGET/CLAUDE.md"`:

```sh
    # Studio memory: curated, cross-project decisions the retro stage writes.
    # An @import is how Claude Code loads it; the path is relative to this
    # file. Claude's own auto memory stays under projects/<project>/memory/.
    if [ -f "$STUDIO_DIR/memory/MEMORY.md" ] || [ -f "$REPO_ROOT/shared/memory/MEMORY.md" ]; then
      printf '\n## Studio memory\n\nDurable studio-wide decisions, kept in version control:\n\n@memory/MEMORY.md\n'
    fi
```

- [ ] **Step 4: Run the whole suite**

Run: `sh tests/run_all.sh`
Expected: all green.

- [ ] **Step 5: Rewrite the README sections**

In `README.md`:

Replace the paragraph at lines 21–27 with:

```markdown
This creates `~/.claude-gamedev` with a rendered `CLAUDE.md`, a copied
`settings.json`, and links to the studio's `memory/` and `bin/`; writes a shim
at `~/.local/bin/claude-gd`; records the mode and the shim path in
`~/.claude-gamedev/.omega-ai-manifest`; and runs `doctor.sh`. The shim
launches Claude Code with `CLAUDE_CONFIG_DIR` pointing at the config root, the
studio's `bin/` on `PATH`, and `--plugin-dir` pointing at `studios/game-dev/`,
so the studio's skills, agents and hooks load straight from this checkout —
edit a skill and it is live in the next session. The rendered `CLAUDE.md`
imports `memory/MEMORY.md`, the studio's own memory (see Memory below).
```

Replace lines 39–46 (`Options: …` through `Install paths must not contain spaces.`) with:

```markdown
Options: `--mode copy` for a frozen snapshot (the studio is copied to
`~/.claude-gamedev/studio/` and loaded from there), `--target DIR` for a
different config root, `--shim-dir DIR` for a different shim location,
`--no-mcp` (accepted now; MCP registration arrives with the engine toolkit
in Plan 2), and `--dry-run` to see every action — including the removal of
a previous install's entries — without performing it. Reinstalling checks
that the studio's files are all present, then removes everything the
previous install recorded before writing anew. The install exits non-zero
when the doctor finds a problem.

### Upgrading from `profiles/`

An install made by the earlier `profiles/` installer linked `skills/`,
`agents/`, `commands/` and `hooks/` into the config root and wrote a shim
without `--plugin-dir`. `doctor.sh` now reports that as a stale layout.
Run `./install.sh <studio>` again: the old manifest's entries are removed and
the new shim is written.
```

Replace lines 59–61 (`review`, `playtest` … `written only through studio-state.`) with:

```markdown
`review`, `playtest`, `ship`, `retro` and `scaffold` arrive in later releases;
the session bootstrap says so when one is missing. State lives in the
project's `.studio/`: `STATE.md` is the stage/task pointer — local, gitignored,
resolved to the project's main checkout from any worktree — and
`ledger/<feature>.md` is the feature's decision log, committed with the
feature. Both are written only through `studio-state`; a hook blocks direct
edits.
```

Replace the Check section body (lines 69–72) with:

```markdown
Reports the config root, the plugin directory the shim loads and its skill /
agent counts, every plugin `requires.txt` declares (enabled? fetched? which
version?), the shim the install recorded (present? launches this root?
loads the plugin?), whether that shim's directory is on `PATH`, any stale
layout from the earlier installer, and whether anything leaks back into
`~/.claude`. Exits non-zero on a missing `CLAUDE.md` or `settings.json`, a
name mismatch, a missing plugin, a stale or foreign shim, a stale layout, or
a leak. `--target DIR` checks a root installed elsewhere.
```

Replace the Uninstall section (lines 74–79) with:

```markdown
## Uninstall

```sh
./uninstall.sh game-dev            # remove installed content, keep sessions
./uninstall.sh game-dev --purge    # remove the config root entirely (asks; --yes skips)
```

Uninstall removes what the manifest recorded and the shim the manifest names
— unless that shim now launches a different config root, in which case it is
kept and said so. `--purge` refuses a directory that has no manifest.
`--target DIR` and `--shim-dir DIR` match the flags the install used;
`--shim-dir` is only needed for installs made before the manifest recorded
the shim.
```

Replace the Memory section (lines 81–92) with:

```markdown
## Memory

Two memories exist, and they do not mix.

**Studio memory** is `studios/<studio>/memory/MEMORY.md` — curated,
cross-project decisions the retro stage writes (design rulings, pipeline
conventions). It is linked into the config root and imported by the rendered
`CLAUDE.md`, so every `claude-gd` session loads it. It never reaches plain
`claude`. Pull in-session edits back into version control with:

```sh
./sync-memory.sh game-dev
```

**Claude's auto memory** is per project and per config root:
`~/.claude-gamedev/projects/<project>/memory/`. A game project and a business
project have different paths, and `claude-gd` and `claude` have different
config roots, so nothing crosses over. The installer does not touch it.

In copy mode the config root holds a copied `memory/`, and a reinstall or
uninstall removes that copy, in-session edits included — run
`./sync-memory.sh <studio>` first.
```

- [ ] **Step 6: Commit**

```bash
git add install.sh README.md tests/install_test.sh
git commit -m "feat: rendered CLAUDE.md imports studio memory; README documents the memory model and the upgrade path" -m "Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01EXbiTV13oWT2MjvbFXAuB2"
```

---

### Task 11: `studio-state` resolves the pointer to the main checkout; `init` writes `config.json`, `ledger/` and the gitignore line

**Files:**
- Modify: `studios/game-dev/bin/studio-state` (header comment, the `STATE=` line, `init`, new `root`)
- Test: `tests/state_test.sh`

**Interfaces:**
- Produces: `STATE_ROOT` (main checkout via `git rev-parse --path-format=absolute --git-common-dir`, else `pwd -P`), `WORK_ROOT` (`git rev-parse --show-toplevel`, else `pwd -P`), `STATE="$STATE_ROOT/.studio/STATE.md"`, `CONFIG="$WORK_ROOT/.studio/config.json"`, `LEDGER_DIR="$WORK_ROOT/.studio/ledger"`; `studio-state root` prints `STATE_ROOT`, `studio-state root --work` prints `WORK_ROOT`. Tasks 12–14 use these names.

- [ ] **Step 1: Write the failing tests**

In `tests/state_test.sh`, replace `TMP="$(mktemp -d)"` with:

```sh
# Physical path: git prints physical paths, and the tool's root resolution
# is compared against $TMP textually.
TMP="$(cd "$(mktemp -d)" && pwd -P)"
```

Append before `run_tests`:

```sh
# The pointer lives in the main checkout: a linked worktree of the project
# edits the same STATE.md, so execute on a feature branch and the router in
# main see one stage. The gitignore line keeps the pointer out of commits.
test_state_resolves_to_main_checkout() {
  P="$(fresh_project wt)"
  ( cd "$P" && git init -q && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init ) 2>/dev/null
  ( cd "$P" && sh "$STATE_BIN" init >/dev/null )
  ( cd "$P" && git worktree add -q "$TMP/wt-linked" -b feature ) >/dev/null 2>&1
  assert_eq "$P" "$(cd "$TMP/wt-linked" && sh "$STATE_BIN" root)" "root from a worktree is the main checkout"
  assert_eq "$TMP/wt-linked" "$(cd "$TMP/wt-linked" && sh "$STATE_BIN" root --work)" "root --work is the worktree"
  assert_eq "$P" "$(cd "$P" && sh "$STATE_BIN" root --work)" "root --work in main is main"
  assert_status 0 "set from a worktree succeeds" -- sh -c "cd '$TMP/wt-linked' && sh '$STATE_BIN' set stage execute"
  assert_eq "execute" "$(cd "$P" && sh "$STATE_BIN" get stage)" "the main checkout's STATE.md carries the change"
  assert_missing "$TMP/wt-linked/.studio/STATE.md" "the worktree holds no copy of the pointer"
  assert_contains "$P/.gitignore" "^\.studio/STATE\.md$" "init gitignores the pointer"
  P2="$(fresh_project nogit)"
  assert_eq "$P2" "$(cd "$P2" && sh "$STATE_BIN" root)" "outside git the root is the current directory"
}

test_state_init_writes_config_ledger_and_gitignore_once() {
  P="$(fresh_project gi)"
  ( cd "$P" && git init -q ) 2>/dev/null
  ( cd "$P" && sh "$STATE_BIN" init >/dev/null )
  assert_file "$P/.studio/config.json" "init writes config.json"
  assert_contains "$P/.studio/config.json" '"engine": "godot4"' "config.json carries the studio defaults"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -d "$P/.studio/ledger" ]; then _pass "init creates the ledger directory"; else _fail "init creates the ledger directory"; fi
  assert_status 1 "init refuses to overwrite an existing state" -- sh -c "cd '$P' && sh '$STATE_BIN' init"
  printf '{ "engine": "godot4", "tests": "gdunit4" }\n' > "$P/.studio/config.json"
  rm "$P/.studio/STATE.md"
  ( cd "$P" && sh "$STATE_BIN" init >/dev/null )
  assert_eq "1" "$(grep -c '^\.studio/STATE\.md$' "$P/.gitignore")" "the gitignore line is added once"
  assert_contains "$P/.studio/config.json" "gdunit4" "an existing config.json is kept"
  P3="$(fresh_project gi-nogit)"
  ( cd "$P3" && sh "$STATE_BIN" init >/dev/null )
  assert_missing "$P3/.gitignore" "outside git no .gitignore is written"
}
```

Add both to `run_tests`.

- [ ] **Step 2: Run them to see them fail**

Run: `sh tests/state_test.sh`
Expected: FAIL "root from a worktree is the main checkout" (usage error), FAIL "init writes config.json".

- [ ] **Step 3: Resolve the roots**

In `studios/game-dev/bin/studio-state`, replace the header comment block and the `STATE=".studio/STATE.md"` line with:

```sh
#!/bin/sh
# studio-state — read and write the studio's state the same way from every
# skill. Two roots: the stage/task pointer (.studio/STATE.md) lives in the
# project's main checkout, so a linked git worktree edits the same file and
# one project has one stage; the feature ledger, config.json and the spec and
# plan paths live in the checkout the command runs in, so they travel with
# the branch.
#
#   studio-state root [--work]   print the pointer's root, or the working root
#   studio-state init            create .studio/ (STATE.md, config.json, ledger/)
#   studio-state show            print STATE.md, then the current feature ledger
#   studio-state get KEY         print one field
#   studio-state set KEY VALUE   replace one field; '-' clears it
#   studio-state ledger TEXT     append a dated line to the feature ledger
#                                (.studio/ledger/<feature>.md when spec is set,
#                                else STATE.md's own ledger)
#   studio-state check [--rebuild]      verify state against files and ledger;
#                                       --rebuild sets task from the ledger
#   studio-state reset [--keep-ledger]  back to idle; drops the feature ledger
#                                       unless --keep-ledger
#
# Keys: stage spec plan task last_playtest milestone
# Exit: 0 ok · 1 no .studio/ (except init and root), bad key, bad value, bad
# usage, or a check that found a mismatch
set -eu

# --path-format=absolute needs git 2.31+. Outside a repository both roots are
# the current directory.
_common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
if [ -n "$_common" ]; then
  STATE_ROOT="$(dirname "$_common")"
  WORK_ROOT="$(git rev-parse --show-toplevel)"
else
  STATE_ROOT="$(pwd -P)"
  WORK_ROOT="$STATE_ROOT"
fi
STATE="$STATE_ROOT/.studio/STATE.md"
CONFIG="$WORK_ROOT/.studio/config.json"
LEDGER_DIR="$WORK_ROOT/.studio/ledger"
```

(`check` and `reset` are documented now and implemented in Task 13.) Update `usage()` to:

```sh
usage() {
  printf 'usage: studio-state root [--work] | init | show | get KEY | set KEY VALUE | ledger TEXT | check [--rebuild] | reset [--keep-ledger]\nkeys: %s\n' "$KEYS" >&2
  exit 1
}
```

- [ ] **Step 4: `root` and the richer `init`**

Add a `root)` case before `init)`:

```sh
  root)
    case "${2:-}" in
      '') printf '%s\n' "$STATE_ROOT" ;;
      --work) printf '%s\n' "$WORK_ROOT" ;;
      *) usage ;;
    esac
    ;;
```

Replace the `init)` case with:

```sh
  init)
    [ ! -f "$STATE" ] || fail "$STATE already exists"
    mkdir -p "$STATE_ROOT/.studio" "$LEDGER_DIR"
    cat > "$STATE" <<'EOF'
# Studio State

stage: idle
spec: -
plan: -
task: -
last_playtest: -
milestone: prototype

## Ledger

EOF
    # The studio defaults; the session hook reads this file for its identity
    # line and a project overrides keys here.
    if [ ! -f "$CONFIG" ]; then
      printf '{ "engine": "godot4", "dimension": "2d", "language": "gdscript", "tests": "gut" }\n' > "$CONFIG"
    fi
    # The pointer is local to this checkout: ignore it once, where it lives.
    if [ -e "$STATE_ROOT/.git" ]; then
      grep -qxF '.studio/STATE.md' "$STATE_ROOT/.gitignore" 2>/dev/null \
        || printf '.studio/STATE.md\n' >> "$STATE_ROOT/.gitignore"
    fi
    printf 'initialised %s\n' "$STATE"
    ;;
```

- [ ] **Step 5: Run the state tests**

Run: `sh tests/state_test.sh`
Expected: all pass (the pre-existing tests run in non-git directories and are unaffected).

- [ ] **Step 6: Run the whole suite**

Run: `sh tests/run_all.sh`
Expected: all green (the hook tests run the hook in non-git directories).

- [ ] **Step 7: Commit**

```bash
git add studios/game-dev/bin/studio-state tests/state_test.sh
git commit -m "feat(studio-state): resolve the pointer to the main checkout; init writes config.json, ledger/ and the gitignore line" -m "Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01EXbiTV13oWT2MjvbFXAuB2"
```

---

### Task 12: `set` fails on a damaged file, folds newlines, rejects extra arguments, validates `task`

**Files:**
- Modify: `studios/game-dev/bin/studio-state` (the `set)` case; new `write_field`)
- Test: `tests/state_test.sh`

**Interfaces:**
- Produces: `write_field KEY VALUE` — replaces the first `KEY: ` header line of `$STATE` (Task 13's `check --rebuild` and `reset` call it). `set` exits 1 with `no 'KEY:' line` when the header is absent.

- [ ] **Step 1: Write the failing tests**

Append to `tests/state_test.sh` before `run_tests`:

```sh
# set used to exit 0 and write nothing when the header line was gone, so a
# hand-edited STATE.md silently lost every later write.
test_state_set_hardening() {
  P="$(fresh_project harden)"
  ( cd "$P" && sh "$STATE_BIN" init >/dev/null )
  grep -v '^spec: ' "$P/.studio/STATE.md" > "$P/damaged" && mv "$P/damaged" "$P/.studio/STATE.md"
  status=0
  ( cd "$P" && sh "$STATE_BIN" set spec docs/x.md ) > /dev/null 2> "$P/set.err" || status=$?
  assert_eq "1" "$status" "set fails when the key's header line is absent"
  assert_contains "$P/set.err" "no 'spec:' line" "set names the missing header"

  P="$(fresh_project harden2)"
  ( cd "$P" && sh "$STATE_BIN" init >/dev/null )
  ( cd "$P" && sh "$STATE_BIN" set spec "$(printf 'a\nstage: hacked')" )
  assert_eq "1" "$(grep -c '^stage: ' "$P/.studio/STATE.md")" "a newline in a value cannot inject a header line"
  assert_eq "a stage: hacked" "$(cd "$P" && sh "$STATE_BIN" get spec)" "the newline is folded to a space"
  assert_status 1 "set rejects extra arguments" -- sh -c "cd '$P' && sh '$STATE_BIN' set spec docs/my spec.md"
  assert_eq "a stage: hacked" "$(cd "$P" && sh "$STATE_BIN" get spec)" "a rejected set changes nothing"
  assert_status 1 "set task rejects a value that is not n/N" -- sh -c "cd '$P' && sh '$STATE_BIN' set task three"
  assert_status 0 "set task accepts n/N" -- sh -c "cd '$P' && sh '$STATE_BIN' set task 2/5"
  assert_status 0 "set task accepts -" -- sh -c "cd '$P' && sh '$STATE_BIN' set task -"
}
```

Add `test_state_set_hardening` to `run_tests`.

- [ ] **Step 2: Run it to see it fail**

Run: `sh tests/state_test.sh`
Expected: FAIL "set fails when the key's header line is absent" (exit 0).

- [ ] **Step 3: Factor the write and harden `set`**

In `studio-state`, add after `need_state()`:

```sh
# write_field KEY VALUE — replace the first "KEY: " header line. Only that
# line is replaced; ledger lines start with "- " and can never match. The
# value travels through the environment, not `awk -v`, which would turn a
# "\n" in a path into a real newline and split the header.
write_field() {
  _tmp="$STATE.tmp.$$"
  STUDIO_STATE_VALUE="$2" awk -v k="$1" '
    BEGIN { done = 0 }
    !done && $0 ~ ("^" k ": ") { print k ": " ENVIRON["STUDIO_STATE_VALUE"]; done = 1; next }
    { print }
  ' "$STATE" > "$_tmp"
  mv "$_tmp" "$STATE"
}
```

Replace the `set)` case with:

```sh
  set)
    need_state
    [ $# -eq 3 ] || usage
    key="$2"
    # A real newline in a value would split the header into two lines.
    val="$(printf '%s' "$3" | tr '\n\r' '  ')"
    in_list "$key" "$KEYS" || usage
    [ -n "$val" ] || usage
    case "$key" in
      stage) in_list "$val" "$STAGES" || fail "stage must be one of: $STAGES" ;;
      milestone) in_list "$val" "$MILESTONES" || fail "milestone must be one of: $MILESTONES" ;;
      task)
        case "$val" in
          -) ;;
          *) printf '%s' "$val" | grep -qE '^[0-9]+/[0-9]+$' || fail "task must be n/N or -" ;;
        esac ;;
    esac
    grep -q "^$key: " "$STATE" || fail "no '$key:' line in $STATE — the file is damaged; restore the header"
    write_field "$key" "$val"
    ;;
```

- [ ] **Step 4: Run the whole suite**

Run: `sh tests/run_all.sh`
Expected: all green (`test_state_set_keeps_backslashes`, `test_state_validation` unchanged).

- [ ] **Step 5: Commit**

```bash
git add studios/game-dev/bin/studio-state tests/state_test.sh
git commit -m "fix(studio-state): set fails on a damaged file, folds newlines, rejects extra arguments, validates task" -m "Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01EXbiTV13oWT2MjvbFXAuB2"
```

---

### Task 13: Per-feature ledger, `check`, `reset`

**Files:**
- Modify: `studios/game-dev/bin/studio-state` (`show`, `ledger`; new `feature_slug`, `ledger_file`, `check`, `reset`)
- Test: `tests/state_test.sh`

**Interfaces:**
- Consumes: `write_field`, `STATE`, `WORK_ROOT`, `LEDGER_DIR` (Tasks 11–12).
- Produces: `ledger TEXT` appends to `$LEDGER_DIR/<slug>.md` when `spec` is set (slug = spec basename without `.md` and without a leading `YYYY-MM-DD-`), else to `STATE.md`; `show` prints `STATE.md` then `## Feature ledger: <slug>` and the ledger file; `check [--rebuild]` exits 1 on a missing spec/plan file, `n > N`, or a ledger ahead of `task` (with `--rebuild`: sets `task` instead); `reset [--keep-ledger]` writes `abandoned <spec>` to `STATE.md`'s ledger, removes the feature ledger unless kept, and sets `stage idle`, `spec -`, `plan -`, `task -`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/state_test.sh` before `run_tests`:

```sh
# Rulings belong to the feature, not to a single slot edited on every
# branch: one ledger file per spec, committed with the feature's branch.
test_state_feature_ledger() {
  P="$(fresh_project fl)"
  ( cd "$P" && sh "$STATE_BIN" init >/dev/null )
  today="$(date +%Y-%m-%d)"
  ( cd "$P" && sh "$STATE_BIN" ledger "idle note" )
  assert_contains "$P/.studio/STATE.md" "^- $today idle note" "with no spec the ledger line goes to STATE.md"
  ( cd "$P" && sh "$STATE_BIN" set spec docs/game-dev/specs/2026-09-13-player-dash.md )
  ( cd "$P" && sh "$STATE_BIN" ledger "spec written docs/game-dev/specs/2026-09-13-player-dash.md" )
  assert_file "$P/.studio/ledger/player-dash.md" "with a spec the ledger line goes to the feature file"
  assert_contains "$P/.studio/ledger/player-dash.md" "^- $today spec written" "the feature ledger line is dated"
  assert_contains "$P/.studio/ledger/player-dash.md" "^# Ledger — player-dash" "the feature ledger has a title"
  assert_not_contains "$P/.studio/STATE.md" "spec written" "STATE.md does not carry feature lines"
  ( cd "$P" && sh "$STATE_BIN" show ) > "$TMP/fl-show.out"
  assert_contains "$TMP/fl-show.out" "^stage: idle" "show prints the pointer"
  assert_contains "$TMP/fl-show.out" "^## Feature ledger: player-dash" "show names the feature ledger"
  assert_contains "$TMP/fl-show.out" "spec written" "show prints the feature ledger"
}

test_state_ledger_per_branch() {
  P="$(fresh_project fb)"
  ( cd "$P" && git init -q && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init ) 2>/dev/null
  ( cd "$P" && sh "$STATE_BIN" init >/dev/null )
  ( cd "$P" && sh "$STATE_BIN" set spec docs/game-dev/specs/2026-09-13-a.md && sh "$STATE_BIN" ledger "A1" )
  ( cd "$P" && git worktree add -q "$TMP/fb-linked" -b b ) >/dev/null 2>&1
  ( cd "$TMP/fb-linked" && sh "$STATE_BIN" set spec docs/game-dev/specs/2026-09-13-b.md && sh "$STATE_BIN" ledger "B1" )
  assert_file "$P/.studio/ledger/a.md" "feature a's ledger is in the main checkout"
  assert_file "$TMP/fb-linked/.studio/ledger/b.md" "feature b's ledger is in the worktree"
  assert_missing "$P/.studio/ledger/b.md" "feature b's ledger is not in the main checkout"
  assert_eq "docs/game-dev/specs/2026-09-13-b.md" "$(cd "$P" && sh "$STATE_BIN" get spec)" "the pointer is shared"
}

test_state_check() {
  P="$(fresh_project chk)"
  ( cd "$P" && sh "$STATE_BIN" init >/dev/null )
  assert_status 0 "check passes on a fresh state" -- sh -c "cd '$P' && sh '$STATE_BIN' check"
  ( cd "$P" && sh "$STATE_BIN" set spec docs/game-dev/specs/2026-09-13-dash.md )
  status=0
  ( cd "$P" && sh "$STATE_BIN" check ) > "$TMP/chk.out" 2>&1 || status=$?
  assert_eq "1" "$status" "check fails when the spec file is missing"
  assert_contains "$TMP/chk.out" "spec file missing: docs/game-dev/specs/2026-09-13-dash.md" "check names the missing spec"
  mkdir -p "$P/docs/game-dev/specs" "$P/docs/game-dev/plans"
  printf '# spec\n' > "$P/docs/game-dev/specs/2026-09-13-dash.md"
  printf '# plan\n' > "$P/docs/game-dev/plans/2026-09-13-dash.md"
  ( cd "$P" && sh "$STATE_BIN" set plan docs/game-dev/plans/2026-09-13-dash.md && sh "$STATE_BIN" set task 2/5 )
  assert_status 0 "check passes with files present and no ledger" -- sh -c "cd '$P' && sh '$STATE_BIN' check"
  ( cd "$P" && sh "$STATE_BIN" ledger "T1 complete abc..def" && sh "$STATE_BIN" ledger "T3 complete def..fed" )
  status=0
  ( cd "$P" && sh "$STATE_BIN" check ) > "$TMP/chk2.out" 2>&1 || status=$?
  assert_eq "1" "$status" "check fails when the ledger is ahead of task"
  assert_contains "$TMP/chk2.out" "ledger says T3 complete but task is 2/5" "check explains the mismatch"
  assert_status 0 "check --rebuild succeeds" -- sh -c "cd '$P' && sh '$STATE_BIN' check --rebuild"
  assert_eq "3/5" "$(cd "$P" && sh "$STATE_BIN" get task)" "check --rebuild sets task from the ledger"
  ( cd "$P" && sh "$STATE_BIN" set task 4/5 )
  ( cd "$P" && sh "$STATE_BIN" check ) > "$TMP/chk3.out" 2>&1
  assert_contains "$TMP/chk3.out" "note" "a ledger behind task is a note, not a failure"
  ( cd "$P" && sh "$STATE_BIN" set task 6/5 )
  assert_status 1 "check fails when n > N" -- sh -c "cd '$P' && sh '$STATE_BIN' check"
}

test_state_reset() {
  P="$(fresh_project rst)"
  ( cd "$P" && sh "$STATE_BIN" init >/dev/null )
  ( cd "$P" && sh "$STATE_BIN" set stage plan && sh "$STATE_BIN" set spec docs/s/2026-09-13-dash.md \
      && sh "$STATE_BIN" set plan docs/p/2026-09-13-dash.md && sh "$STATE_BIN" set task 1/3 \
      && sh "$STATE_BIN" ledger "T1 complete x" )
  assert_file "$P/.studio/ledger/dash.md" "the feature ledger exists before reset"
  assert_status 0 "reset succeeds" -- sh -c "cd '$P' && sh '$STATE_BIN' reset"
  assert_eq "idle" "$(cd "$P" && sh "$STATE_BIN" get stage)" "reset returns to idle"
  assert_eq "-" "$(cd "$P" && sh "$STATE_BIN" get spec)" "reset clears spec"
  assert_eq "-" "$(cd "$P" && sh "$STATE_BIN" get plan)" "reset clears plan"
  assert_eq "-" "$(cd "$P" && sh "$STATE_BIN" get task)" "reset clears task"
  assert_missing "$P/.studio/ledger/dash.md" "reset removes the feature ledger"
  assert_contains "$P/.studio/STATE.md" "abandoned docs/s/2026-09-13-dash.md" "reset records the abandoned spec"
  ( cd "$P" && sh "$STATE_BIN" set spec docs/s/2026-09-13-keep.md && sh "$STATE_BIN" ledger "K1" )
  ( cd "$P" && sh "$STATE_BIN" reset --keep-ledger )
  assert_file "$P/.studio/ledger/keep.md" "reset --keep-ledger keeps the feature ledger"
  assert_status 1 "reset rejects an unknown flag" -- sh -c "cd '$P' && sh '$STATE_BIN' reset --nope"
}
```

Add all four to `run_tests`.

- [ ] **Step 2: Run them to see them fail**

Run: `sh tests/state_test.sh`
Expected: FAIL "with a spec the ledger line goes to the feature file", FAIL "check passes on a fresh state" (usage), FAIL "reset succeeds".

- [ ] **Step 3: Slug and ledger-file helpers**

In `studio-state`, after `write_field`:

```sh
# field KEY — the current value of a header field.
field() { sed -n "s/^$1: //p" "$STATE" | head -n 1; }

# feature_slug — the ledger file stem for the current spec: its basename
# without .md and without a leading YYYY-MM-DD-; empty when no spec is set.
feature_slug() {
  _spec="$(field spec)"
  case "$_spec" in ''|-) return 0 ;; esac
  basename "$_spec" | sed -e 's/\.md$//' -e 's/^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}-//'
}

# ledger_file — where a ledger line goes: the feature ledger when a spec is
# set, else STATE.md's own ledger section.
ledger_file() {
  _slug="$(feature_slug)"
  if [ -n "$_slug" ]; then printf '%s\n' "$LEDGER_DIR/$_slug.md"; else printf '%s\n' "$STATE"; fi
}
```

Change the `get)` case body to use it: replace `sed -n "s/^$key: //p" "$STATE" | head -n 1` with `field "$key"`.

- [ ] **Step 4: `show` and `ledger`**

Replace the `show)` case with:

```sh
  show)
    need_state
    cat "$STATE"
    _lf="$(ledger_file)"
    if [ "$_lf" != "$STATE" ] && [ -f "$_lf" ]; then
      printf '\n## Feature ledger: %s\n\n' "$(basename "$_lf" .md)"
      cat "$_lf"
    fi
    ;;
```

Replace the `ledger)` case with:

```sh
  ledger)
    need_state
    shift
    # All remaining words form the entry, so an unquoted call keeps its text;
    # an embedded newline is folded to a space so an entry stays one line.
    text="$(printf '%s' "$*" | tr '\n' ' ')"
    [ -n "$text" ] || usage
    _lf="$(ledger_file)"
    if [ "$_lf" != "$STATE" ] && [ ! -f "$_lf" ]; then
      mkdir -p "$LEDGER_DIR"
      printf '# Ledger — %s\n\n' "$(basename "$_lf" .md)" > "$_lf"
    fi
    printf -- '- %s %s\n' "$(date +%Y-%m-%d)" "$text" >> "$_lf"
    ;;
```

- [ ] **Step 5: `check` and `reset`**

Add before the `*) usage ;;` case:

```sh
  check)
    need_state
    rebuild=0
    case "${2:-}" in '') ;; --rebuild) rebuild=1 ;; *) usage ;; esac
    problems=0
    for k in spec plan; do
      v="$(field "$k")"
      case "$v" in ''|-) continue ;; esac
      case "$v" in /*) f="$v" ;; *) f="$WORK_ROOT/$v" ;; esac
      if [ ! -f "$f" ]; then printf 'check: %s file missing: %s\n' "$k" "$v"; problems=1; fi
    done
    # The highest "T<n> complete" in the ledger is what has actually shipped.
    _lf="$(ledger_file)"
    done_n=0
    if [ -f "$_lf" ]; then
      done_n="$(sed -n 's/^- [0-9-]* T\([0-9]*\) complete.*/\1/p' "$_lf" | sort -n | tail -n 1)"
      done_n="${done_n:-0}"
    fi
    task="$(field task)"
    case "$task" in
      ''|-) ;;
      *)
        n="${task%%/*}"; N="${task#*/}"
        if [ "$n" -gt "$N" ]; then printf 'check: task %s has n > N\n' "$task"; problems=1; fi
        if [ "$done_n" -gt "$n" ]; then
          if [ "$rebuild" = "1" ]; then
            write_field task "$done_n/$N"
            printf 'check: task rebuilt to %s/%s from the ledger\n' "$done_n" "$N"
          else
            printf 'check: ledger says T%s complete but task is %s — run check --rebuild\n' "$done_n" "$task"
            problems=1
          fi
        elif [ "$done_n" -lt "$n" ]; then
          printf 'check: note — ledger has T%s complete, task is %s (execute may be on another branch)\n' "$done_n" "$task"
        fi ;;
    esac
    [ "$problems" = "0" ] && printf 'check: ok\n'
    exit "$problems"
    ;;
  reset)
    need_state
    keep=0
    case "${2:-}" in '') ;; --keep-ledger) keep=1 ;; *) usage ;; esac
    spec="$(field spec)"
    _lf="$(ledger_file)"
    if [ "$_lf" != "$STATE" ]; then
      if [ "$keep" = "0" ] && [ -f "$_lf" ]; then rm -f "$_lf"; fi
      printf -- '- %s abandoned %s\n' "$(date +%Y-%m-%d)" "$spec" >> "$STATE"
    fi
    write_field stage idle
    write_field spec -
    write_field plan -
    write_field task -
    printf 'reset to idle\n'
    ;;
```

- [ ] **Step 6: Run the whole suite**

Run: `sh tests/run_all.sh`
Expected: all green. `test_state_ledger` and `test_state_ledger_folds_newlines` still write to `STATE.md` (no spec set).

- [ ] **Step 7: Commit**

```bash
git add studios/game-dev/bin/studio-state tests/state_test.sh
git commit -m "feat(studio-state): per-feature ledger files, check --rebuild, reset --keep-ledger" -m "Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01EXbiTV13oWT2MjvbFXAuB2"
```

---

### Task 14: The session hook fails loud, strips control characters, and injects the stage line

**Files:**
- Modify: `studios/game-dev/hooks/session-start.sh`
- Modify: `studios/game-dev/hooks/bootstrap.md` (the `## State` paragraph)
- Test: `tests/hook_test.sh`

**Interfaces:**
- Consumes: `studio-state root --work`, `studio-state get stage` (Tasks 11–13).
- Produces: exit 1 with `no bootstrap.md` on stderr when `$ROOT/hooks/bootstrap.md` is absent; the injected context ends with `Studio state: stage <stage>` when `.studio/STATE.md` exists.

- [ ] **Step 1: Write the failing tests**

Append to `tests/hook_test.sh` before `run_tests`:

```sh
# A wrong CLAUDE_PLUGIN_ROOT used to emit an empty context with exit 0, so the
# studio was silently not loaded.
test_hook_fails_without_bootstrap() {
  mkdir -p "$TMP/noboot-root/hooks" "$TMP/noboot"
  cp "$STUDIO_DIR/studio.json" "$TMP/noboot-root/"
  status=0
  ( cd "$TMP/noboot" && CLAUDE_PLUGIN_ROOT="$TMP/noboot-root" sh "$HOOK" ) > "$TMP/noboot.out" 2> "$TMP/noboot.err" || status=$?
  assert_eq "1" "$status" "hook exits 1 when bootstrap.md is missing"
  assert_contains "$TMP/noboot.err" "bootstrap.md" "hook names the missing file"
  assert_not_contains "$TMP/noboot.out" "additionalContext" "hook emits no empty context"
}

test_hook_strips_control_characters() {
  mkdir -p "$TMP/ctl/.studio"
  printf '{ "engine": "god\fot4" }\n' > "$TMP/ctl/.studio/config.json"
  run_hook "$TMP/ctl"
  if command -v jq >/dev/null 2>&1; then
    assert_status 0 "a control character in config.json still yields valid JSON" -- jq -e . "$TMP/hook.out"
  fi
  assert_not_contains "$TMP/hook.out" '"additionalContext":""' "the context is not emptied"
  context "$TMP/hook.out" > "$TMP/ctx7.txt"
  assert_contains "$TMP/ctx7.txt" "godot4 · 2D" "the control character is dropped from the value"
}

test_hook_reports_stage() {
  mkdir -p "$TMP/staged"
  ( cd "$TMP/staged" && sh "$STUDIO_DIR/bin/studio-state" init >/dev/null && sh "$STUDIO_DIR/bin/studio-state" set stage plan )
  run_hook "$TMP/staged"
  context "$TMP/hook.out" > "$TMP/ctx8.txt"
  assert_contains "$TMP/ctx8.txt" "^Studio state: stage plan" "context reports the current stage"
  mkdir -p "$TMP/unstaged"
  run_hook "$TMP/unstaged"
  context "$TMP/hook.out" > "$TMP/ctx9.txt"
  assert_not_contains "$TMP/ctx9.txt" "Studio state:" "no stage line without state"
  assert_eq "" "$(cat "$TMP/hook.err")" "the hook is silent on stderr without state"
}
```

Add all three to `run_tests`.

- [ ] **Step 2: Run them to see them fail**

Run: `sh tests/hook_test.sh`
Expected: FAIL "hook exits 1 when bootstrap.md is missing" (exit 0), FAIL "a control character in config.json still yields valid JSON", FAIL "context reports the current stage".

- [ ] **Step 3: Fail loud, resolve the working root, read the stage**

In `session-start.sh`, replace the line `ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"` with:

```sh
ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
BOOTSTRAP="$ROOT/hooks/bootstrap.md"
# Exit 1 (not 2: on SessionStart that would reset the session's context).
[ -f "$BOOTSTRAP" ] || { printf 'game-dev session-start: no bootstrap.md at %s\n' "$ROOT/hooks" >&2; exit 1; }

# The project's config lives in the checkout the session runs in; the stage
# pointer lives in the main checkout. studio-state knows both. Both calls are
# best-effort: no state, no line.
STUDIO_STATE="$ROOT/bin/studio-state"
WORK_ROOT="$(sh "$STUDIO_STATE" root --work 2>/dev/null || pwd -P)"
STAGE="$(sh "$STUDIO_STATE" get stage 2>/dev/null || true)"
```

In `pick()`, change `field ".studio/config.json" "$1"` to `field "$WORK_ROOT/.studio/config.json" "$1"`.

- [ ] **Step 4: Append the stage line and strip control characters**

Replace the `escaped="$(… awk '…' "$ROOT/hooks/bootstrap.md" | tr -d '\r' | sed … | awk …)"` pipeline's source and first filter so that it reads:

```sh
escaped="$({ STUDIO_ENGINE="$ENGINE" STUDIO_DIMENSION="$DIMENSION" \
  STUDIO_LANGUAGE="$LANGUAGE" STUDIO_TESTS="$TESTS" awk '
  function fill(s, tok, val,    out, i) {
    out = ""
    while ((i = index(s, tok)) > 0) {
      out = out substr(s, 1, i - 1) val
      s = substr(s, i + length(tok))
    }
    return out s
  }
  {
    line = $0
    line = fill(line, "{{ENGINE}}", ENVIRON["STUDIO_ENGINE"])
    line = fill(line, "{{DIMENSION}}", ENVIRON["STUDIO_DIMENSION"])
    line = fill(line, "{{LANGUAGE}}", ENVIRON["STUDIO_LANGUAGE"])
    line = fill(line, "{{TESTS}}", ENVIRON["STUDIO_TESTS"])
    print line
  }' "$BOOTSTRAP"
  if [ -n "$STAGE" ]; then printf '\nStudio state: stage %s\n' "$STAGE"; fi
  } \
  | tr -d '\r' \
  | tr -d '\000-\010\013\014\016-\037' \
  | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e "s/$TAB/\\\\t/g" \
  | awk 'BEGIN { ORS = "" } NR > 1 { printf "\\n" } { printf "%s", $0 }')"
```

Extend the comment above it with: `# Control characters other than tab and newline are dropped: a form feed in a config value is invalid inside a JSON string and would void the whole context.`

- [ ] **Step 5: Bootstrap wording**

In `bootstrap.md`, replace the `## State` paragraph with:

```markdown
## State

When `.studio/STATE.md` exists, a `Studio state: stage <stage>` line follows this bootstrap; `/game-dev:studio` names the next step from it. When it does not exist and this is a Godot project (`project.godot` present), `/game-dev:studio` initialises it.
```

- [ ] **Step 6: Run the whole suite**

Run: `sh tests/run_all.sh`
Expected: all green (`test_hook_defaults_from_studio_json` still finds `.studio/STATE.md` in the context; `test_bin_syntax` still parses the hook).

- [ ] **Step 7: Commit**

```bash
git add studios/game-dev/hooks/session-start.sh studios/game-dev/hooks/bootstrap.md tests/hook_test.sh
git commit -m "fix(hook): fail loud without bootstrap.md, strip control characters, inject the stage line" -m "Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01EXbiTV13oWT2MjvbFXAuB2"
```

---

### Task 15: State files are written only through `studio-state` — a PreToolUse guard

**Files:**
- Create: `studios/game-dev/hooks/guard-state.sh`
- Modify: `studios/game-dev/hooks/hooks.json`
- Test: `tests/hook_test.sh`

**Interfaces:**
- Produces: a PreToolUse hook on `Edit|Write|MultiEdit` that exits 2 (blocking; stderr is the reason) when `tool_input.file_path` ends with `.studio/STATE.md` or matches `.studio/ledger/*.md`. Per the hooks reference: "Exit 2 … Blocks the tool call" and "The blocking message is … your stderr text".

- [ ] **Step 1: Write the failing tests**

In `tests/hook_test.sh`, after `HOOK=…` add `GUARD="$STUDIO_DIR/hooks/guard-state.sh"`. In `test_hook_files`, after the `CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh` assertion, add:

```sh
  assert_contains "$STUDIO_DIR/hooks/hooks.json" '"PreToolUse"' "hooks.json registers PreToolUse"
  assert_contains "$STUDIO_DIR/hooks/hooks.json" 'Edit|Write|MultiEdit' "the guard matches the file-writing tools"
  assert_contains "$STUDIO_DIR/hooks/hooks.json" 'CLAUDE_PLUGIN_ROOT}/hooks/guard-state.sh' \
    "hooks.json runs guard-state.sh from the plugin root"
```

Append before `run_tests`:

```sh
# "STATE.md is written only through studio-state" was a sentence in a skill;
# the harness enforces it now.
test_guard_state_blocks_direct_writes() {
  status=0
  printf '{"tool_name":"Edit","tool_input":{"file_path":"/p/game/.studio/STATE.md","old_string":"a","new_string":"b"}}' \
    | sh "$GUARD" > /dev/null 2> "$TMP/guard.err" || status=$?
  assert_eq "2" "$status" "guard blocks an Edit of .studio/STATE.md"
  assert_contains "$TMP/guard.err" "use studio-state" "guard says what to use instead"
  status=0
  printf '{"tool_name":"Write","tool_input":{"file_path":"/p/game/.studio/ledger/dash.md","content":"x"}}' \
    | sh "$GUARD" > /dev/null 2>&1 || status=$?
  assert_eq "2" "$status" "guard blocks a Write of a feature ledger"
  status=0
  printf '{"tool_name":"Write","tool_input":{"file_path":".studio/STATE.md","content":"x"}}' \
    | sh "$GUARD" > /dev/null 2>&1 || status=$?
  assert_eq "2" "$status" "guard blocks a relative path too"
  status=0
  printf '{"tool_name":"Write","tool_input":{"file_path":"/p/game/.studio/config.json","content":"x"}}' \
    | sh "$GUARD" > /dev/null 2>&1 || status=$?
  assert_eq "0" "$status" "guard lets config.json through"
  status=0
  printf '{"tool_name":"Edit","tool_input":{"file_path":"/p/game/src/player.gd"}}' | sh "$GUARD" >/dev/null 2>&1 || status=$?
  assert_eq "0" "$status" "guard lets ordinary files through"
  status=0
  printf '' | sh "$GUARD" >/dev/null 2>&1 || status=$?
  assert_eq "0" "$status" "guard exits 0 on empty input"
}
```

Add `test_guard_state_blocks_direct_writes` to `run_tests`.

- [ ] **Step 2: Run them to see them fail**

Run: `sh tests/hook_test.sh`
Expected: FAIL "hooks.json registers PreToolUse", FAIL "guard blocks an Edit of .studio/STATE.md" (no such file).

- [ ] **Step 3: Write the guard**

Create `studios/game-dev/hooks/guard-state.sh`:

```sh
#!/bin/sh
# PreToolUse hook (Edit|Write|MultiEdit): .studio/STATE.md and the feature
# ledgers are written only through studio-state. Exit 2 blocks the call and
# hands stderr back as the reason; exit 0 lets everything else through.
#
# Self-contained on purpose: in copy mode the plugin root has no lib/.
set -u

input="$(cat)"
path="$(printf '%s' "$input" \
  | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"

case "$path" in
  */.studio/STATE.md|.studio/STATE.md|*/.studio/ledger/*.md|.studio/ledger/*.md)
    printf 'use studio-state to change studio state (%s is written only through it)\n' "$path" >&2
    exit 2 ;;
esac
exit 0
```

Run `chmod +x studios/game-dev/hooks/guard-state.sh`.

- [ ] **Step 4: Register it**

Replace `hooks.json` with:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|clear|compact",
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh\""
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/guard-state.sh\""
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 5: Run the whole suite**

Run: `sh tests/run_all.sh`
Expected: all green (`test_bin_syntax` now also parses `guard-state.sh` and checks it is executable).

- [ ] **Step 6: Commit**

```bash
git add studios/game-dev/hooks/guard-state.sh studios/game-dev/hooks/hooks.json tests/hook_test.sh
git commit -m "feat(hooks): PreToolUse guard blocks direct edits of STATE.md and feature ledgers" -m "Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01EXbiTV13oWT2MjvbFXAuB2"
```

---

### Task 16: Agents renamed and wired; `requires.txt` declares what the stage skills will name

**Files:**
- Rename: `studios/game-dev/agents/game-feel-tuner.md` → `feel-tuner.md`, `agents/2d-art-pipeline.md` → `tech-artist.md`
- Modify: `studios/game-dev/agents/{feel-tuner,tech-artist,game-designer}.md`
- Modify: `studios/game-dev/requires.txt`
- Test: `tests/studio_test.sh`

**Interfaces:**
- Produces: agents `game-dev:feel-tuner` (tools include `Bash`), `game-dev:tech-artist`, `game-dev:game-designer` (states assumptions instead of asking). `requires.txt` lists every godot-prompter skill and agent Tasks 17–19 reference. `test_role_agents_exist` — every `` `game-dev:<role>` `` first cell in plan's and execute's `Role:` tables is an agent file, except the interim roles `gameplay-programmer architect ui-designer level-designer`.

- [ ] **Step 1: Write the failing lint**

Append to `tests/studio_test.sh` before `run_tests`:

```sh
# Every Role the plan and execute tables offer must be dispatchable: a
# shipped agent file, or one of the roles execute maps to a godot-prompter
# agent or general-purpose until Plan 2 ships the studio's own.
test_role_agents_exist() {
  interim=" gameplay-programmer architect ui-designer level-designer "
  for f in "$REPO_ROOT/studios/game-dev/skills/plan/SKILL.md" "$REPO_ROOT/studios/game-dev/skills/execute/SKILL.md"; do
    skill="$(basename "$(dirname "$f")")"
    for role in $(sed -n 's/^| `game-dev:\([a-z0-9-]*\)`.*/\1/p' "$f" | sort -u); do
      case "$interim" in *" $role "*) continue ;; esac
      assert_file "$REPO_ROOT/studios/game-dev/agents/$role.md" "$skill Role game-dev:$role is a shipped agent"
    done
  done
  assert_missing "$REPO_ROOT/studios/game-dev/agents/game-feel-tuner.md" "game-feel-tuner was renamed to feel-tuner"
  assert_missing "$REPO_ROOT/studios/game-dev/agents/2d-art-pipeline.md" "2d-art-pipeline was renamed to tech-artist"
  assert_contains "$REPO_ROOT/studios/game-dev/agents/feel-tuner.md" "^tools: .*Bash" "feel-tuner can run the game"
  assert_not_contains "$REPO_ROOT/studios/game-dev/agents/game-designer.md" "^Ask about" \
    "game-designer states assumptions instead of asking (a subagent cannot ask)"
}
```

Add `test_role_agents_exist` to `run_tests`.

- [ ] **Step 2: Run it to see it fail**

Run: `sh tests/studio_test.sh`
Expected: FAIL "plan Role game-dev:tech-artist is a shipped agent", FAIL "plan Role game-dev:feel-tuner is a shipped agent", FAIL "game-feel-tuner was renamed to feel-tuner".

- [ ] **Step 3: Rename and edit the agents**

```bash
git mv studios/game-dev/agents/game-feel-tuner.md studios/game-dev/agents/feel-tuner.md
git mv studios/game-dev/agents/2d-art-pipeline.md studios/game-dev/agents/tech-artist.md
```

`feel-tuner.md` frontmatter becomes:

```markdown
---
name: feel-tuner
description: Use when the game works but does not feel good — input response, animation timing, camera behavior, hit feedback, screen shake, and juice. Diagnoses feel problems before adding effects; measures in the running build.
tools: Read, Write, Edit, Grep, Glob, Bash
model: inherit
---
```

Append to the end of `feel-tuner.md`:

```markdown

Measure, do not guess: run the project headless or a single scene through
the engine (the command `godot-prompter:godot-testing` names) to count frames
between input and response, and quote the number in your report. Every value
you change lives in a Resource; state its old and new value.
```

`tech-artist.md` frontmatter: change `name: 2d-art-pipeline` to `name: tech-artist`; description unchanged.

`game-designer.md`: replace the line `Ask about the target player and the session length before proposing mechanics.` with:

```markdown
State your assumptions about the target player and the session length before
proposing mechanics, and list the questions the main session should put to
the user; you cannot ask them yourself.
```

- [ ] **Step 4: Declare the dependencies**

Append to `studios/game-dev/requires.txt`:

```
skill  godot-prompter:component-system
skill  godot-prompter:dependency-injection
skill  godot-prompter:player-controller
skill  godot-prompter:input-handling
skill  godot-prompter:physics-system
skill  godot-prompter:camera-system
skill  godot-prompter:tween-animation
skill  godot-prompter:animation-system
skill  godot-prompter:godot-ui
skill  godot-prompter:hud-system
skill  godot-prompter:responsive-ui
skill  godot-prompter:2d-essentials
skill  godot-prompter:assets-pipeline
agent  godot-prompter:godot-game-dev
agent  godot-prompter:godot-game-architect
agent  godot-prompter:godot-ui-designer
agent  godot-prompter:godot-code-reviewer
```

- [ ] **Step 5: Run the whole suite**

Run: `sh tests/run_all.sh`
Expected: all green (`test_agent_frontmatter` accepts the new names; `test_external_references_declared` finds `feel-tuner.md`'s `godot-prompter:godot-testing` declared).

- [ ] **Step 6: Commit**

```bash
git add -A studios/game-dev/agents studios/game-dev/requires.txt tests/studio_test.sh
git commit -m "refactor(agents): rename to feel-tuner and tech-artist, give the tuner Bash, declare the godot-prompter skills and agents the stages use" -m "Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01EXbiTV13oWT2MjvbFXAuB2"
```

---

### Task 17: `execute` — committed inputs, worktree after preconditions, role dispatch table, verify lists, smoke boot, no merge path

**Files:**
- Modify: `studios/game-dev/skills/execute/SKILL.md` (full rewrite of the body; frontmatter unchanged)
- Test: `tests/studio_test.sh`

**Interfaces:**
- Consumes: `studio-state` verbs (Tasks 11–13), agents (Task 16).
- Produces: the `Role:` dispatch table below; ledger phrases unchanged. `plan` (Task 18) uses the same `Verify:` wording.

- [ ] **Step 1: Write the failing contract test**

Append to `tests/studio_test.sh` before `run_tests`:

```sh
# Behaviour the review fixed, pinned as text contracts on the stage skills.
test_stage_skill_contracts() {
  S="$REPO_ROOT/studios/game-dev/skills"
  assert_not_contains "$S/execute/SKILL.md" "finishing-a-development-branch" "execute never offers a merge path"
  assert_contains "$S/execute/SKILL.md" "quit-after" "execute smoke-boots the project"
  assert_contains "$S/execute/SKILL.md" "git log -1" "execute requires a committed spec and plan"
  assert_contains "$S/execute/SKILL.md" "godot-prompter:godot-game-dev" "execute dispatches godot-prompter's game dev for gameplay tasks"
  assert_contains "$S/execute/SKILL.md" "game-dev:feel-tuner" "execute dispatches the studio's feel tuner"
  assert_contains "$S/execute/SKILL.md" "unverified" "execute lists unverified items"
  assert_not_contains "$S/execute/SKILL.md" "bypass the event bus" "execute's reviewer no longer mandates bus-for-everything"
}
```

Add `test_stage_skill_contracts` to `run_tests`.

- [ ] **Step 2: Run it to see it fail**

Run: `sh tests/studio_test.sh`
Expected: FAIL "execute never offers a merge path", FAIL "execute smoke-boots the project".

- [ ] **Step 3: Rewrite the skill body**

Replace everything in `studios/game-dev/skills/execute/SKILL.md` after the frontmatter with:

```markdown
# Execute

**Announce at start:** "Using game-dev:execute in subagent-driven mode." (or
"… in inline mode" when `--inline` was given).

## 0. Preconditions

Check these first, in the checkout you are in:

- `studio-state get plan` names a file that exists and `studio-state show`
  has a `plan approved` line for it; otherwise stop and point at
  `/game-dev:plan`.
- The spec and the plan are committed: `git log -1 --format=%h -- <spec path>`
  and the same for the plan path each print a hash. If either prints nothing,
  stop and say: "commit the spec and plan first —
  `git add <spec> <plan> .studio/ledger .studio/config.json && git commit -m 'docs: approve <topic>'`".
  A worktree is a checkout; an uncommitted spec does not travel into it.
- Read the plan once. Read the spec its header names; the spec is the
  authority the plan argues from.
- Run `studio-state set stage execute`. Read `task` to find where to resume:
  `3/6` means tasks 1–3 are complete; start at 4. `studio-state` keeps the
  pointer in the project's main checkout, so every call below works the same
  from inside a worktree.

Then isolate: note the current branch (`git branch --show-current`), invoke
`superpowers:using-git-worktrees`, and in the new worktree confirm the plan
file exists. If it does not, the worktree was cut from a base that lacks the
gate commits: run `git merge --ff-only <noted branch>`; if that fails, stop
and say so. Never implement on `main` without the user's explicit consent.

## 1. Mode

**Default — subagent-driven.** Invoke
`superpowers:subagent-driven-development` and follow its loop exactly:
fresh implementer per task, task review after each, fix rounds, final
whole-branch review, ledger. The studio rules in §2–§5 layer on top of it.

**`--inline`.** Only when the user passed it. Invoke
`superpowers:executing-plans` instead and implement tasks in this session in
batches, checking in with the user between batches. You are the implementer:
before each task read the skills its role's row in §2 lists. §3, §5 and §6
still apply; §2's dispatch and §4 do not.

## 2. Who implements (subagent-driven mode)

Dispatch the implementer named by the task's `Role:` line from this table.
The studio's own role agents arrive in Plan 2; until then a role with a
godot-prompter equivalent dispatches that agent, and `level-designer`
dispatches `general-purpose`. Open every brief with the persona line — a
godot-prompter agent knows the engine, not this studio's rules.

| `Role:` | Dispatch | Persona line | Skills the brief names |
|---------|----------|--------------|------------------------|
| `game-dev:gameplay-programmer` | `godot-prompter:godot-game-dev` | You are the studio's gameplay programmer: composition over inheritance, signals up and calls down, every tunable number in a Resource, tests first. | `godot-prompter:gdscript-patterns`, `godot-prompter:state-machine`, `godot-prompter:event-bus`, `godot-prompter:resource-pattern`, `godot-prompter:component-system`, `godot-prompter:player-controller`, `godot-prompter:input-handling`, `godot-prompter:physics-system`, `godot-prompter:camera-system`, `godot-prompter:godot-testing` |
| `game-dev:architect` | `godot-prompter:godot-game-architect` | You are the studio's architect: scene tree, state machines, signal topology, Resource schemas; you leave a decision and its reason, not just code. | `godot-prompter:scene-organization`, `godot-prompter:state-machine`, `godot-prompter:event-bus`, `godot-prompter:component-system`, `godot-prompter:dependency-injection`, `godot-prompter:resource-pattern` |
| `game-dev:ui-designer` | `godot-prompter:godot-ui-designer` | You are the studio's UI designer: Control nodes only, containers over manual positioning, one Theme resource. | `godot-prompter:godot-ui`, `godot-prompter:hud-system`, `godot-prompter:responsive-ui` |
| `game-dev:feel-tuner` | `game-dev:feel-tuner` | (the agent carries it) | `game-dev:game-feel`, `godot-prompter:tween-animation`, `godot-prompter:camera-system`, `godot-prompter:animation-system`, `godot-prompter:input-handling` |
| `game-dev:tech-artist` | `game-dev:tech-artist` | (the agent carries it) | `game-dev:2d-sprite-pipeline`, `godot-prompter:2d-essentials`, `godot-prompter:assets-pipeline` |
| `game-dev:level-designer` | `general-purpose` | You are the studio's level designer: layout teaches the mechanic before it tests it; collision is authored on the tileset, not per level. | `godot-prompter:2d-essentials` |

When `.studio/config.json` sets `language: csharp`, `gameplay-programmer`
dispatches `godot-prompter:godot-csharp-engineer` instead.

Every brief also carries: the task text (via the skill's task-brief script),
the spec sections the task cites, the project `CLAUDE.md` architecture
rules, and the skills column above as "read these before writing code". A
stuck implementer reads `superpowers:systematic-debugging`.

## 3. Verify rules (both modes)

`Verify:` is one kind or several joined with `+` (`unit+playtest`). Every
kind listed binds the implementer:

- `unit` — the implementer follows `superpowers:test-driven-development`:
  the test named in `Files:` is written and seen to fail before the
  implementation, then passes. The test framework is the project's (`tests`
  in `.studio/config.json`; default GUT). Before reporting, run the project's
  test suite: `studio-test` when it is on `PATH` (it arrives with the engine
  toolkit); otherwise the framework's command line from
  `godot-prompter:godot-testing`, headless, with the exit code checked.
- `playtest` — the implementer's report ends with the playtest item the task
  defined (action, expected perceptual result, what a failure looks like).
  Record it with `studio-state ledger "T<n> Playtest item: <text>"`.
- `visual` — the implementer reports what to look at and where. Record it as
  `studio-state ledger "T<n> Visual: <text>"`.

A task that introduces or changes a tunable value (a cooldown, a window, a
speed, a curve) always includes `unit`: the number is tested, the feel is
played.

## 4. Who reviews (subagent-driven mode)

The task reviewer from subagent-driven-development is dispatched as
`godot-prompter:godot-code-reviewer`, with the studio's checklist appended to
the global-constraints block it receives (Plan 2 of the studio replaces it
with the `game-dev:reviewer` agent):

- Spec compliance: every acceptance criterion the task claims is met, and
  nothing beyond the task was built.
- `godot-prompter:godot-code-review` findings.
- Composition, not inheritance, where the spec specified a component.
- Cross-system notification goes through signals; `EventBus` only where no
  ownership path exists. Parent→child calls and `@export` injection are
  correct, not violations.
- No tuning literal outside a Resource.
- No per-frame `instantiate()`, `new()`, Array/Dictionary/String building, or
  `get_node()` by string in `_process` / `_physics_process`; anything else
  is a profiler question, not a review finding.
- For `unit`: the test exists, fails without the change, passes with it.

Findings are one line each, severity-tagged. The fix loop is
subagent-driven-development's.

## 5. State (both modes)

- After each task's review is clean: `studio-state set task n/N` and
  `studio-state ledger "T<n> complete <short commit range>"`.
- Every judgment call: `studio-state ledger "T<n> Ruling: <decision> — <why> — <cost if wrong>"`.
  The SDD ledger under `.superpowers/sdd/` remains the recovery map for the
  loop; the feature ledger (`.studio/ledger/<feature>.md`) carries the rulings
  the user reads.
- Every review finding that changed the code: `studio-state ledger "T<n> Review: <one line>"`.
- Commit `.studio/ledger/` with each task's commits; it is part of the
  feature and merges with it.

Stop only for the four reasons subagent-driven-development names: an
irreversible or destructive operation, a security-sensitive action, a side
effect outside the worktree (merge, push, publish), or a plan too broken to
follow. Everything else is a ruling.

## 6. Finish

When the final whole-branch review is clean:

1. **Smoke boot.** From the project root run the engine headless and let it
   quit on its own: `godot --headless --quit-after 1` (or the binary
   `godot-prompter:godot-testing` resolves when `godot` is not on `PATH`),
   capturing the output. Require exit 0 and no line matching `SCRIPT ERROR`
   or `ERROR:`. A failure is a task: fix it through the loop above, re-run,
   then continue.
2. `studio-state set stage review`.
3. List every ruling you made, in order, with what it costs if wrong.
4. List every `Playtest item:` and `Visual:` line in `studio-state show`
   under **Unverified — check by hand before merging**. They were reviewed
   by reading code, not by playing; the playtest stage owns them.
5. Tell the user the next command is `/game-dev:review`. If that skill is
   not in your skill list yet, say that the review and playtest stages are
   not installed and that the branch must not be merged until the
   unverified items above are checked by hand. Do not merge, and do not
   name a merging skill.
```

- [ ] **Step 4: Run the whole suite**

Run: `sh tests/run_all.sh`
Expected: all green — `test_external_references_declared` finds every `godot-prompter:` name in `requires.txt` (Task 16); `test_role_agents_exist` resolves `feel-tuner` and `tech-artist` to files and skips the four interim roles.

- [ ] **Step 5: Commit**

```bash
git add studios/game-dev/skills/execute/SKILL.md tests/studio_test.sh
git commit -m "feat(execute): committed inputs before the worktree, role dispatch table, verify lists, smoke boot, no merge path" -m "Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01EXbiTV13oWT2MjvbFXAuB2"
```

---

### Task 18: `plan` — verify lists, the tunable rule, the configured framework, commit at the gate, gate criteria from the spec

**Files:**
- Modify: `studios/game-dev/skills/plan/SKILL.md` (§0, §3, §4, §5)
- Test: `tests/studio_test.sh`

**Interfaces:**
- Consumes: the `Verify:` wording from Task 17; the spec's `## Milestone gate` section (Task 19 adds it to brainstorm's template).
- Produces: on approval the plan's `Status:` line flips and the plan is committed before the `plan approved` ledger line.

- [ ] **Step 1: Extend the contract test**

In `test_stage_skill_contracts` (Task 17), append:

```sh
  assert_contains "$S/plan/SKILL.md" "unit+playtest" "plan allows combined verify kinds"
  assert_contains "$S/plan/SKILL.md" "git commit" "plan commits at the approval gate"
  assert_contains "$S/plan/SKILL.md" "Milestone gate" "plan reads gate criteria from the spec when PROGRESS.md is absent"
  assert_not_contains "$S/plan/SKILL.md" "a GUT test named" "plan does not hard-code GUT"
```

- [ ] **Step 2: Run it to see it fail**

Run: `sh tests/studio_test.sh`
Expected: FAIL "plan allows combined verify kinds".

- [ ] **Step 3: Edit the sections**

§0 — replace the second bullet (`- Read the spec in full, …`) with:

```markdown
- Read the spec in full and the project `CLAUDE.md`. The milestone gate and
  its exit criteria come from `docs/game-dev/PROGRESS.md` when the project has
  one, otherwise from the spec's **Milestone gate** section.
```

§1 — in the example task block, change `Verify: unit` to `Verify: unit+playtest` (a buffer window is a number and a feel), so the example reads:

```markdown
  ### Task 3: Input action and buffer window
  Role: game-dev:gameplay-programmer
  Verify: unit+playtest
  Files: src/player/dash_state.gd, tests/unit/test_dash_input.gd
```

§3 — replace the whole section with:

```markdown
## 3. Verify

`Verify:` names how the task's deliverable is checked, and binds the
implementer. It is one kind or several joined with `+` (`unit+playtest`):

- `unit` — a test named in `Files:` is written first and fails before the
  implementation exists (`superpowers:test-driven-development` is
  mandatory). The framework is the project's (`tests` in
  `.studio/config.json`; default GUT); test files go where
  `godot-prompter:godot-testing` says the runner finds them. Use it for
  numbers, state transitions, cooldowns, collisions, signal emission,
  Resource loading.
- `playtest` — the task states, in its own text, the playtest item it will
  produce: the action, the expected perceptual result, and what a failure
  looks like. Use it for snappiness, readability, timing, camera behaviour.
- `visual` — the user looks at it; no automated check. Use it for art
  placement, UI layout, particle look.

A task that introduces or changes a tunable value (a cooldown, a window, a
speed, a curve) always includes `unit`: the number is tested, the feel is
played. A task that mixes deliverables of different kinds is two tasks; a
task with one deliverable checked two ways is one task with two kinds.
```

§4 — replace the numbered question 1 with:

```markdown
1. Does the current milestone gate's exit criteria (from `PROGRESS.md`, or
   the spec's **Milestone gate** section) need this task?
```

§5 — replace the last paragraph (`On approval run …`) with:

```markdown
On approval: change the plan's `Status:` line to `Approved`, commit it so it
travels into the execution worktree —
`git add <plan path> .studio/ledger .studio/config.json && git commit -m "docs(plans): approve <topic>"` —
then run `studio-state ledger "plan approved <plan path>"` and tell the user
the next command is `/game-dev:execute` (subagent-driven by default;
`--inline` for checkpointed execution in this session). Do not invoke it
yourself.
```

Also add `Status: Draft (awaiting approval)` to the plan header rules: after the sentence `The plan header's **Spec:** line points at the approved spec, …` add: `The header also carries a \`Status:\` line, \`Draft (awaiting approval)\` until the gate.`

- [ ] **Step 4: Run the whole suite**

Run: `sh tests/run_all.sh`
Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add studios/game-dev/skills/plan/SKILL.md tests/studio_test.sh
git commit -m "feat(plan): verify lists with the tunable rule, configured framework, commit at the gate, gate criteria from the spec" -m "Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01EXbiTV13oWT2MjvbFXAuB2"
```

---

### Task 19: `brainstorm` — stage after classification, gate criteria, the designer agent, a fuller spec template, commit at the gate

**Files:**
- Modify: `studios/game-dev/skills/brainstorm/SKILL.md` (§0, §1, §2, §3, §4, §5, §7)
- Test: `tests/studio_test.sh`

**Interfaces:**
- Consumes: `game-dev:game-designer` (Task 16).
- Produces: spec template sections `Milestone gate`, `Design`, `Failure and recovery`, `Teaching`, `Input and platform`, `References`, `Tuning knobs`, `Assets and audio`, `Risks` (Task 18 reads `Milestone gate`).

- [ ] **Step 1: Extend the contract test**

In `test_stage_skill_contracts`, append:

```sh
  assert_contains "$S/brainstorm/SKILL.md" "## Tuning knobs" "brainstorm's spec template exposes tuning knobs"
  assert_contains "$S/brainstorm/SKILL.md" "## Milestone gate" "brainstorm's spec template carries the gate"
  assert_contains "$S/brainstorm/SKILL.md" "game-dev:game-designer" "brainstorm dispatches the game designer"
  assert_not_contains "$S/brainstorm/SKILL.md" "godot-brainstorming" "brainstorm does not hand a subagent an interactive skill"
  assert_contains "$S/brainstorm/SKILL.md" "docs(specs): approve" "brainstorm commits at the approval gate"
```

- [ ] **Step 2: Run it to see it fail**

Run: `sh tests/studio_test.sh`
Expected: FAIL "brainstorm's spec template exposes tuning knobs".

- [ ] **Step 3: Edit the sections**

§0 — delete the bullet `- Run \`studio-state set stage brainstorm\`.` (the stage is set after classification).

§1 — replace the section body with:

```markdown
Before the first question, read what exists: `docs/game-dev/PROGRESS.md`
when the project has one (the milestone gate and its exit criteria), the
newest files in `docs/game-dev/specs/` and `docs/game-dev/playtests/`, the
project `CLAUDE.md`, and the part of the scene tree or scripts the request
touches. When the request touches controls, movement, camera or feedback,
invoke `game-dev:game-feel`.
```

§2 — after the three classifications add:

```markdown
For **bounded** and **architectural** work run `studio-state set stage
brainstorm` now; a spike leaves the stage where it was.
```

§3 — replace question 4 with:

```markdown
4. **Scope** — what this must prove for the current milestone gate, and what
   is explicitly not being done. When the project has no `PROGRESS.md`, ask
   here which gate this is (prototype, vertical slice, alpha, beta, gold)
   and its two or three exit criteria; they go into the spec's **Milestone
   gate** section and the plan's scope pass cuts against them.
```

§4 — replace the second paragraph (`For the architectural path, dispatch …`) with:

```markdown
For the architectural path, dispatch two subagents with the draft spec:

- `game-dev:game-designer`, briefed: "Write the **Design** section: core
  loop, mechanics and what each adds to the loop, progression as new
  decisions, difficulty and how the player learns it. Use
  `game-dev:game-design-doc` and `game-dev:core-loop-design`. State your
  assumptions about the target player; list open questions for me; write no
  engine files."
- `general-purpose` (Plan 2 of the studio replaces it with
  `game-dev:architect`), briefed: "Write the **Architecture** section: scene
  tree, state machine changes, signals and event-bus topics, Resource
  schemas. Read `godot-prompter:scene-organization`,
  `godot-prompter:state-machine`, `godot-prompter:event-bus`,
  `godot-prompter:component-system` and `godot-prompter:resource-pattern`.
  Composition over inheritance; signals up, calls down, the event bus only
  where no ownership path exists; every tunable number in a Resource. Write
  the section only — no plan file."

Fold their sections into the spec; put the designer's open questions to the
user in the next batch.
```

§5 — replace the template with:

```markdown
# <Feature> — Spec

Date: YYYY-MM-DD
Status: Draft (awaiting approval)
Milestone: <gate name>
Classification: bounded | architectural

## Milestone gate
The gate this serves and its exit criteria — copied from `PROGRESS.md` when
the project has one, otherwise as answered in step 3.

## Purpose
One paragraph: what the player gets and why it serves the current gate.

## Core-loop delta
What changes in the ten-second loop. "None" is a valid answer; say it.

## Player verbs
- Added: …
- Changed: …
- Removed: …

## Design
Core loop, mechanics, progression, difficulty — from `game-dev:game-designer`
(architectural), or `n/a` (bounded).

## Failure and recovery
What failing looks like, what it costs the player, how they get back in.
"None" is a valid answer; say it.

## Teaching
How the player learns this: where it is first needed, what the level or UI
does to show it.

## Input and platform
Input device and target platform the feel targets assume (keyboard, gamepad,
touch; 60 fps desktop, Steam Deck, mobile).

## Feel targets
| Target | Value | How it is checked |
|--------|-------|-------------------|
| Dash distance | 3 tiles in 0.15 s | unit |
| Input latency | ≤ 2 frames at 60 fps | playtest |

## References
Games or scenes that do this well, and what to take from each. `n/a` when none.

## Acceptance criteria
Numbered, each one testable by a unit test or a playtest item.

## Architecture
Scene tree changes, state machine changes, signals / event-bus topics,
Resource schemas, files to create or modify.

## Tuning knobs
The Resource fields this feature exposes: name, unit, default, range. Every
number in Feel targets appears here.

## Assets and audio
Sprites, animations, sounds this needs, and who makes them. `n/a` when none.

## Test strategy
- Unit (the project's test framework): which behaviours, which test files.
- Playtest: which criteria, what a pass looks like, what a fail looks like.
- Visual: what the user looks at with no automated check.

## Risks
What could sink this and the cheapest way to find out early. `n/a` when none.

## Not doing
An explicit list. Anything cut in step 4 goes here with a one-line reason.
```

After the template, replace `Every section states a decision. …` with:

```markdown
Every section states a decision. A section that reads as a possibility is
not finished. A bounded spec writes `n/a` in a section that does not apply
rather than dropping it.
```

§7 — replace the last paragraph (`Revise on request …`) with:

```markdown
Revise on request and re-render. On approval: change the spec's `Status:` to
`Approved`, run `studio-state ledger "spec approved <spec path>"`, commit the
spec and the state that must travel with it —
`git add <spec path> .studio/ledger .studio/config.json && git commit -m "docs(specs): approve <topic>"` —
and tell the user the next command is `/game-dev:plan`. Do not invoke it
yourself.
```

- [ ] **Step 4: Run the whole suite**

Run: `sh tests/run_all.sh`
Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add studios/game-dev/skills/brainstorm/SKILL.md tests/studio_test.sh
git commit -m "feat(brainstorm): stage after classification, gate criteria without PROGRESS.md, designer dispatch, fuller spec template, commit at the gate" -m "Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01EXbiTV13oWT2MjvbFXAuB2"
```

---

### Task 20: `studio` router — reconcile with `check`, idle on an empty brainstorm, abandon route, bug route with a test first

**Files:**
- Modify: `studios/game-dev/skills/studio/SKILL.md` (§1, §2, §3, Rules)
- Test: `tests/studio_test.sh`

**Interfaces:**
- Consumes: `studio-state check`, `studio-state reset` (Task 13).

- [ ] **Step 1: Extend the contract test**

In `test_stage_skill_contracts`, append:

```sh
  assert_contains "$S/studio/SKILL.md" "studio-state check" "the router reconciles state with the repository"
  assert_contains "$S/studio/SKILL.md" "studio-state reset" "the router can abandon a feature"
  assert_contains "$S/studio/SKILL.md" "failing test" "the bug route starts from a failing test"
```

- [ ] **Step 2: Run it to see it fail**

Run: `sh tests/studio_test.sh`
Expected: FAIL "the router reconciles state with the repository".

- [ ] **Step 3: Edit the sections**

§1 — replace `- **Exit 0:** parse the header fields …` with:

```markdown
- **Exit 0:** parse the header fields (`stage`, `spec`, `plan`, `task`,
  `last_playtest`, `milestone`) and the ledger lines. Then run
  `studio-state check`: on exit 1 append its first line to the state line as
  `· check: <message>`; offer `studio-state check --rebuild` only when the
  message says so, and only after the user agrees.
```

§2 — in the transition table, replace the `brainstorm` row with:

```markdown
| `brainstorm` | `/game-dev:plan` | `spec` is `-` — then treat the stage as `idle` (a brainstorm that never reached a spec). Or the ledger has no `spec approved <path>` line for the current `spec` value — then: "spec awaiting approval; reply approve to `/game-dev:brainstorm` or re-run it" |
```

Add after the table:

```markdown
**Abandon / re-plan.** At any stage, when the user says the feature is
dropped or the plan is too broken to follow, confirm with one
`AskUserQuestion` (keep the ledger, or remove it), run `studio-state reset`
(`--keep-ledger` when asked), and name `/game-dev:brainstorm` as the next
command. The `abandoned <spec>` line stays in `STATE.md`'s ledger.
```

§3 — replace the bug row and add an abandon row:

```markdown
| a bug with a repro | `superpowers:using-git-worktrees`, then a failing test that reproduces it, then `superpowers:systematic-debugging`; note the fix with `studio-state ledger "Bug: <one line> — <commit>"` |
| "abandon / drop this / start over" | the abandon step in §2 |
```

Rules — replace the second bullet with:

```markdown
- Never write to `.studio/` except through `studio-state init` (after the
  user says yes), `studio-state reset` (after the user confirms), and the
  `studio-state ledger` line of the bug route.
```

- [ ] **Step 4: Run the whole suite**

Run: `sh tests/run_all.sh`
Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add studios/game-dev/skills/studio/SKILL.md tests/studio_test.sh
git commit -m "feat(studio): reconcile with check, idle on an empty brainstorm, abandon route, bug route starts from a failing test" -m "Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01EXbiTV13oWT2MjvbFXAuB2"
```

---

### Task 21: Bootstrap precedence and the studio `CLAUDE.md` rules

**Files:**
- Modify: `studios/game-dev/hooks/bootstrap.md` (the Precedence paragraph)
- Modify: `studios/game-dev/CLAUDE.md` (lines 11–12, 26)
- Test: `tests/hook_test.sh`

**Interfaces:** none new.

- [ ] **Step 1: Extend the hook file test**

In `test_hook_files`, after the `"bootstrap redirects superpowers' brainstorming"` assertion, add:

```sh
  assert_contains "$STUDIO_DIR/hooks/bootstrap.md" "--inline" "bootstrap says where godot-prompter skills run in inline mode"
```

A pattern starting with `-` would be read by `grep` as an option. In `tests/assert.sh`, change `grep -q "$2" "$1"` to `grep -q -- "$2" "$1"` in both `assert_contains` and `assert_not_contains` (behaviour for every existing pattern is unchanged).

- [ ] **Step 2: Run it to see it fail**

Run: `sh tests/hook_test.sh`
Expected: FAIL "bootstrap says where godot-prompter skills run in inline mode".

- [ ] **Step 3: Edit**

`bootstrap.md` Precedence paragraph becomes:

```markdown
`game-dev:*` stage skills own the workflow. superpowers skills run only when a stage skill names them. godot-prompter skills run inside role agents for engine work, or in the main session in `--inline` mode. If superpowers' own bootstrap says "invoke brainstorming", invoke `game-dev:brainstorm` instead.
```

`studios/game-dev/CLAUDE.md` — replace lines 11–12 with:

```markdown
- Decouple systems with signals: a child reports up with a signal, a parent
  calls down. The global `EventBus` carries only cross-cutting events that have
  no ownership path. A system should not hold a reference to another system
  just to notify it.
```

Replace line 26 with:

```markdown
- Write tests with the configured test framework (`tests` in
  `.studio/config.json`; GUT by default) for logic that is not visual.
```

- [ ] **Step 4: Run the whole suite**

Run: `sh tests/run_all.sh`
Expected: all green (`test_install_content` still finds `Game Development Studio`).

- [ ] **Step 5: Commit**

```bash
git add studios/game-dev/hooks/bootstrap.md studios/game-dev/CLAUDE.md tests/hook_test.sh tests/assert.sh
git commit -m "docs(studio): precedence covers --inline; event-bus and test-framework rules reworded" -m "Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01EXbiTV13oWT2MjvbFXAuB2"
```

---

### Task 22: Docs reconciled — spec, Plan 2/3 notes, PROGRESS.md

**Files:**
- Modify: `docs/game-dev/specs/2026-09-13-game-studio-design.md` (success criterion 8; "State and configuration"; "Agents" note; `/game-dev:execute`; "Docs layout and memory")
- Modify: `docs/game-dev/plans/2026-09-13-plan-2-quality-loop.md` (a reconciliation note after the header)
- Modify: `docs/game-dev/plans/2026-09-13-plan-3-content.md` (a reconciliation note after the header)
- Modify: `docs/game-dev/PROGRESS.md`

**Interfaces:** none. No tests.

- [ ] **Step 1: Spec — success criterion 8**

Replace criterion 8 with:

```markdown
8. Studio memory (`studios/game-dev/memory/MEMORY.md`) is linked into
   `~/.claude-gamedev/memory/` and imported by the rendered `CLAUDE.md`;
   `sync-memory.sh game-dev` copies it only into `studios/game-dev/memory/`.
   Claude's auto memory stays under `~/.claude-gamedev/projects/<project>/memory/`.
```

- [ ] **Step 2: Spec — "State and configuration"**

Replace the section's opening sentence and the `.studio/STATE.md` subsection's closing paragraph (`\`stage\` is one of … the ledger is append-only.`) with:

```markdown
Three files live in the game project under `.studio/`. `config.json` and
`ledger/` are committed; `STATE.md` is a local pointer that `studio-state
init` gitignores.
```

and, in place of the closing paragraph:

```markdown
`stage` is one of `idle`, `brainstorm`, `plan`, `execute`, `review`,
`playtest`, `ship`, `retro`. `milestone` is one of `prototype`,
`vertical-slice`, `alpha`, `beta`, `gold`. Empty values are written as `-`.

The pointer lives in the project's main checkout: `studio-state` resolves it
through `git rev-parse --git-common-dir`, so a linked worktree edits the same
file and a project has one stage at a time. It is gitignored; a fresh clone
rebuilds `task` from the ledger with `studio-state check --rebuild`.

### `.studio/ledger/<feature>.md`

The decision log is per feature: one file named from the spec's slug
(`2026-09-13-player-dash.md` → `ledger/player-dash.md`), append-only,
committed with the branch that works the feature, so two features on two
branches never touch the same file. Lines written while no spec is set (idle
rulings, bug fixes, `abandoned <spec>`) go to `STATE.md`'s own `## Ledger`.
The spec, the plan and the ledger are committed at each approval gate so a
worktree cut afterwards carries them. All writes go through `studio-state`;
a PreToolUse hook blocks direct edits.
```

- [ ] **Step 3: Spec — agents interim note and execute**

After the agents table (before `When \`.studio/config.json\` sets \`language: csharp\` …`) add:

```markdown
**Interim (Plan 1).** Until the ten agents ship, `execute` dispatches
`godot-prompter:godot-game-dev`, `godot-game-architect`, `godot-ui-designer`
and `godot-code-reviewer` for the matching roles with the studio persona
prepended, the shipped `game-dev:feel-tuner`, `tech-artist` and
`game-designer` as themselves, and `general-purpose` for `level-designer`.
```

In `### /game-dev:execute`, replace `- On completion sets \`stage: review\`.` with:

```markdown
- Requires the spec and plan to be committed before entering the worktree.
- Before setting `stage: review`, boots the project headless once
  (`godot --headless --quit-after 1`) and requires a clean log; lists every
  unverified playtest and visual item; never merges.
```

- [ ] **Step 4: Spec — memory paragraph**

Replace the `**Memory** is isolated by construction. …` paragraph with:

```markdown
**Memory.** Studio memory is `studios/game-dev/memory/MEMORY.md`: curated,
cross-project decisions the retro skill writes, linked into the config root
and imported by the rendered `CLAUDE.md`, synced back with
`sync-memory.sh game-dev`. Claude Code's auto memory is separate and stays
per project under `~/.claude-gamedev/projects/<project>/memory/` — a
different config root from `~/.claude`, so nothing crosses over.
```

- [ ] **Step 5: Plan 2 and Plan 3 notes**

In `plan-2-quality-loop.md`, after the `**Spec:**` paragraph, add:

```markdown
**Reconciled 2026-09-13 (review fixes, `plans/2026-09-13-plan-1-review-fixes.md`).** Already done, skip in the tasks below: the `git mv` of `2d-art-pipeline.md` → `tech-artist.md` and `game-feel-tuner.md` → `feel-tuner.md` (Task 2 steps 4–5 — keep only the appended sections); `execute`'s role table now maps to godot-prompter agents and must be replaced, not appended (Task 4); doctor shim identity and copy-mode inspection, canonical `--target`, dry-run preview of manifest cleanup, and `studio-state set` newline folding. New since Plan 1: the manifest header (`# mode=`, `# shim=`) — the `mcp godot` line of Task 9 must be skipped by `manifest_remove` the way header lines are; `.studio/ledger/<feature>.md` is where `T<n> Playtest item:` lines now live (Task 12 reads `studio-state show`); `studio-state check` and `reset` exist.
```

In `plan-3-content.md`, after the `**Spec:**` paragraph, add:

```markdown
**Reconciled 2026-09-13 (review fixes).** brainstorm still references `game-dev:game-design-doc` and `game-dev:core-loop-design` (Task 5's grep sweep renames them); brainstorm now dispatches `game-dev:game-designer` for the **Design** section and carries a **Milestone gate** section in its template — `milestone-gates` (Task 6) should read that section when `PROGRESS.md` is absent rather than requiring it.
```

- [ ] **Step 6: PROGRESS.md**

Change the Plan 1 row's status to `delivered — exit criterion (Task 12 manual run) pending`. Add a log entry above the existing "Plan 1 (Foundation) delivered" entry:

```markdown
### 2026-09-13 — Plan 1 review fixes

- Installer: input validation before reinstall, symlink-safe writes, purge
  requires a manifest, canonical target, manifest header (`mode`, `shim`),
  doctor shim identity / copy-mode inspection / stale-layout / canonical
  leak check.
- State: pointer local and resolved to the main checkout, per-feature
  ledgers committed with the branch, `studio-state check` / `reset`,
  PreToolUse guard.
- Skills: agents renamed and wired, godot-prompter agents interim, verify
  lists, smoke boot, no merge path from execute.
- Plan: `plans/2026-09-13-plan-1-review-fixes.md`. The Plan 1 exit
  criterion (spec §Success criteria 4) is a manual run from the main
  checkout after merge; it has not been run yet.
```

- [ ] **Step 7: Run the whole suite and commit**

Run: `sh tests/run_all.sh`
Expected: all green.

```bash
git add docs/game-dev/specs/2026-09-13-game-studio-design.md docs/game-dev/plans/2026-09-13-plan-2-quality-loop.md docs/game-dev/plans/2026-09-13-plan-3-content.md docs/game-dev/PROGRESS.md
git commit -m "docs(game-dev): reconcile the spec, Plan 2/3 and PROGRESS.md with the review fixes" -m "Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01EXbiTV13oWT2MjvbFXAuB2"
```

---

## Self-review

**Coverage of the curated scope.** Installer 1 → Task 2; 2 → Task 3; 3 → Task 1; 4 → Task 4; 5 → Tasks 5–6; 6 → Task 7; 7 → Task 8; 8 → Task 9; 9 → Task 10. State/hooks 10 → Task 11; 11 → Task 12; 12 → Task 13; 13 → Task 14; 14 → Task 15. Skills/docs 15 + 16 → Task 16; 17 → Task 17; 18 → Task 18; 19 → Task 19; 20 → Task 20; 21 → Task 21; 22 → Task 22.

**Name consistency.** `studio_arg`, `manifest_meta`, `shim_owned` (lib, Tasks 1/5, used in Tasks 5–6). Manifest header `# mode=` / `# shim=` (Tasks 5, 6, 8). `STATE_ROOT`, `WORK_ROOT`, `STATE`, `CONFIG`, `LEDGER_DIR`, `write_field`, `field`, `feature_slug`, `ledger_file` (Tasks 11–13); `root [--work]`, `check [--rebuild]`, `reset [--keep-ledger]` (Tasks 11, 13, 14, 20). `guard-state.sh` (Task 15). Agents `feel-tuner`, `tech-artist`, `game-designer` (Tasks 16, 17, 19). Spec sections `Milestone gate`, `Design`, `Tuning knobs` (Tasks 18–19, 22). Ledger phrases unchanged except the new `abandoned <spec>` and `Bug:`.

**Order.** Task 16 (rename, `requires.txt`) precedes Task 17 (execute references the new names and skills). Task 13 precedes Task 14 (hook calls `root --work`). Task 21's `assert_contains -- …` change to `tests/assert.sh` is local to that task and backwards compatible.

**Deliberately not in this plan** (the user asked for value, not churn): option-loop dedup across the four scripts, test-sandbox helper extraction, plugin-root `settings.json`/`CLAUDE.md` renames, `argument-hint`, `resume|fork` matcher, `ledger` whitespace trim, `SHIM_NAME=claude` guard, a `tune` stage, and the Plan 2/3 stages themselves.
