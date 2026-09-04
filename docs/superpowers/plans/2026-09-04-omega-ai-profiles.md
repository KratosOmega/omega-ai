# omega-ai Switchable Profiles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an installer that deploys any profile in this repository into its own Claude Code config directory, so a game-development AI and the user's existing AI coexist on one machine without either affecting the other.

**Architecture:** Each profile is a directory under `profiles/` describing its own install target in `profile.json`. `install.sh` links (or copies) that profile's content — merged over shared content — into a private config root such as `~/.claude-gamedev`, records what it created in a manifest, and drops a `PATH` shim that sets `CLAUDE_CONFIG_DIR` before exec'ing `claude`. `doctor.sh` verifies isolation on the real machine; `uninstall.sh` reverses the install using the manifest.

**Tech Stack:** POSIX shell (`/bin/sh`), Git, Claude Code. No jq, no Python, no Node — the installer must run on a clean macOS or Linux box.

**Spec:** `docs/superpowers/specs/2026-09-04-omega-ai-profiles-design.md`

## Global Constraints

- Every script targets POSIX `sh`. No bashisms (`[[`, arrays, `local`, `${x^^}`), no external tools beyond coreutils/`find`/`sed`/`grep`.
- Scripts begin with `#!/bin/sh` and `set -eu`.
- The installer must never read from, write to, or delete anything under `~/.claude`. Refusing to install there is a tested hard guard.
- Install target defaults come from `profile.json`; `--target` overrides it and is what tests use. Nothing in the test suite may touch a real config directory.
- Shim directory defaults to `~/.local/bin`, overridable with `--shim-dir`.
- Config roots: `game-dev` → `~/.claude-gamedev` (shim `claude-gd`); `general` → `~/.claude-general` (shim `claude-gen`).
- Third-party plugins are referenced in `settings.json`, never vendored into this repository.
- Every task ends with a commit.

---

## File Structure

| File | Responsibility |
|---|---|
| `lib/common.sh` | Sourced helpers: logging, `run` (dry-run aware), flat-JSON field read, tilde expansion, target guard, entry install, manifest append |
| `install.sh` | Argument parsing, profile resolution, orchestration of the seven install steps |
| `uninstall.sh` | Manifest-driven removal, shim removal, optional purge |
| `doctor.sh` | Read-only report: resolved paths, content counts, enabled plugins, shim/`PATH` state, leakage check |
| `sync-memory.sh` | Copy memory written during sessions back into the profile's `memory/` |
| `tests/assert.sh` | Assertion helpers plus the tiny test runner shared by both test files |
| `tests/lib_test.sh` | Unit tests for `lib/common.sh` pure helpers |
| `tests/install_test.sh` | End-to-end tests: install, guard, dry-run, doctor, uninstall, two-profile independence |
| `tests/run_all.sh` | Runs both test files, non-zero exit on any failure |
| `profiles/<name>/profile.json` | Install identity: name, description, target, shim |
| `profiles/<name>/CLAUDE.md` | Profile half of the rendered system prompt |
| `profiles/<name>/settings.json` | Model, marketplaces, enabled plugins |
| `profiles/<name>/{agents,skills,commands,hooks,memory}/` | Profile content, merged over `shared/` |
| `shared/CLAUDE.part.md` | Common half of the rendered system prompt |
| `shared/{skills,commands}/` | Content merged into every profile |

---

### Task 1: Shell helpers and test harness

**Files:**
- Create: `lib/common.sh`
- Create: `tests/assert.sh`
- Create: `tests/lib_test.sh`

**Interfaces:**
- Consumes: nothing.
- Produces, all sourced from `lib/common.sh` by later tasks:
  - `log MSG` / `warn MSG` / `die MSG` (die exits 1)
  - `run CMD...` — executes, or prints `DRY  CMD...` when `DRY_RUN=1`
  - `json_field FILE KEY` — prints the string value of a flat JSON key, empty if absent
  - `expand_path PATH` — expands a leading `~`
  - `guard_target TARGET REPO_ROOT` — exits 1 for home, `~/.claude`, empty, or in-repo targets
- `tests/assert.sh` produces: `assert_eq EXPECTED ACTUAL MSG`, `assert_file PATH MSG`, `assert_symlink PATH MSG`, `assert_missing PATH MSG`, `assert_status EXPECTED_CODE MSG -- CMD...`, `assert_contains HAYSTACK_FILE NEEDLE MSG`, and `run_tests TEST_NAMES...`.

- [ ] **Step 1: Write the assertion helpers**

Create `tests/assert.sh`:

```sh
#!/bin/sh
# Assertion helpers and a minimal test runner. Sourced by test files.

TESTS_RUN=0
TESTS_FAILED=0

_pass() { printf '  ok   %s\n' "$1"; }
_fail() { printf '  FAIL %s\n' "$1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }

assert_eq() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "$1" = "$2" ]; then
    _pass "$3"
  else
    _fail "$3 (expected '$1', got '$2')"
  fi
}

assert_file() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -f "$1" ]; then _pass "$2"; else _fail "$2 (no regular file at $1)"; fi
}

assert_symlink() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -L "$1" ]; then _pass "$2"; else _fail "$2 (not a symlink: $1)"; fi
}

assert_missing() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ ! -e "$1" ] && [ ! -L "$1" ]; then _pass "$2"; else _fail "$2 (still exists: $1)"; fi
}

# assert_status CODE MSG -- cmd...
assert_status() {
  expected="$1"; msg="$2"; shift 3
  TESTS_RUN=$((TESTS_RUN + 1))
  actual=0
  "$@" >/dev/null 2>&1 || actual=$?
  if [ "$actual" = "$expected" ]; then
    _pass "$msg"
  else
    _fail "$msg (expected exit $expected, got $actual)"
  fi
}

assert_contains() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -f "$1" ] && grep -q "$2" "$1"; then
    _pass "$3"
  else
    _fail "$3 (missing '$2' in $1)"
  fi
}

run_tests() {
  for _t in "$@"; do
    printf '%s\n' "$_t"
    "$_t"
  done
  printf '\n%s assertions, %s failed\n' "$TESTS_RUN" "$TESTS_FAILED"
  [ "$TESTS_FAILED" -eq 0 ]
}
```

- [ ] **Step 2: Write the failing unit tests**

Create `tests/lib_test.sh`:

```sh
#!/bin/sh
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"
. "$REPO_ROOT/lib/common.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

test_json_field() {
  cat > "$TMP/p.json" <<'JSON'
{
  "name": "game-dev",
  "description": "2D game development AI",
  "target": "~/.claude-gamedev",
  "shim": "claude-gd"
}
JSON
  assert_eq "game-dev" "$(json_field "$TMP/p.json" name)" "reads name"
  assert_eq "~/.claude-gamedev" "$(json_field "$TMP/p.json" target)" "reads target"
  assert_eq "claude-gd" "$(json_field "$TMP/p.json" shim)" "reads shim"
  assert_eq "" "$(json_field "$TMP/p.json" nope)" "absent key is empty"
}

test_expand_path() {
  assert_eq "$HOME/.claude-gamedev" "$(expand_path '~/.claude-gamedev')" "expands leading tilde"
  assert_eq "$HOME" "$(expand_path '~')" "expands bare tilde"
  assert_eq "/tmp/x" "$(expand_path '/tmp/x')" "leaves absolute path alone"
}

test_guard_target_rejects() {
  assert_status 1 "rejects home" -- guard_target "$HOME" "$REPO_ROOT"
  assert_status 1 "rejects ~/.claude" -- guard_target "$HOME/.claude" "$REPO_ROOT"
  assert_status 1 "rejects ~/.claude with slash" -- guard_target "$HOME/.claude/" "$REPO_ROOT"
  assert_status 1 "rejects empty target" -- guard_target "" "$REPO_ROOT"
  assert_status 1 "rejects in-repo target" -- guard_target "$REPO_ROOT/profiles" "$REPO_ROOT"
}

test_guard_target_accepts() {
  assert_status 0 "accepts private config root" -- guard_target "$HOME/.claude-gamedev" "$REPO_ROOT"
  assert_status 0 "accepts temp dir" -- guard_target "$TMP/cfg" "$REPO_ROOT"
}

test_run_dry() {
  DRY_RUN=1 run touch "$TMP/should-not-exist"
  assert_missing "$TMP/should-not-exist" "dry run creates nothing"
  DRY_RUN=0 run touch "$TMP/should-exist"
  assert_file "$TMP/should-exist" "wet run creates the file"
}

run_tests test_json_field test_expand_path test_guard_target_rejects test_guard_target_accepts test_run_dry
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `sh tests/lib_test.sh`
Expected: FAIL — `lib/common.sh: No such file or directory`.

- [ ] **Step 4: Implement `lib/common.sh`**

Create `lib/common.sh`:

```sh
#!/bin/sh
# Shared helpers for omega-ai scripts. Sourced, never executed.

log()  { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

# run CMD... — execute, or print the command when DRY_RUN=1.
run() {
  if [ "${DRY_RUN:-0}" = "1" ]; then
    printf 'DRY  %s\n' "$*" >&2
  else
    "$@"
  fi
}

# json_field FILE KEY — value of a flat JSON string key; empty when absent.
json_field() {
  sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1" | head -n 1
}

# expand_path PATH — expand a leading tilde.
expand_path() {
  case "$1" in
    '~')   printf '%s\n' "$HOME" ;;
    '~/'*) printf '%s\n' "$HOME/${1#\~/}" ;;
    *)     printf '%s\n' "$1" ;;
  esac
}

# guard_target TARGET REPO_ROOT — refuse to install anywhere dangerous.
guard_target() {
  _t="${1%/}"
  _repo="${2%/}"
  [ -n "$_t" ] || die "install target is empty"
  [ "$_t" != "${HOME%/}" ] || die "refusing to install into your home directory"
  [ "$_t" != "${HOME%/}/.claude" ] || die "refusing to install into ~/.claude — that is your existing setup"
  case "$_t" in
    "$_repo"|"$_repo"/*) die "refusing to install into the repository itself: $_t" ;;
  esac
  return 0
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `sh tests/lib_test.sh`
Expected: PASS — `0 failed`.

- [ ] **Step 6: Commit**

```bash
git add lib/common.sh tests/assert.sh tests/lib_test.sh
git commit -m "feat: shell helpers and test harness"
```

---

### Task 2: The `general` profile as installable fixture

**Files:**
- Create: `profiles/general/profile.json`
- Create: `profiles/general/CLAUDE.md`
- Create: `profiles/general/settings.json`
- Create: `profiles/general/skills/repo-conventions/SKILL.md`
- Create: `tests/install_test.sh`
- Delete: `game_dev/`, `general/` (empty stubs)

**Interfaces:**
- Consumes: `tests/assert.sh` from Task 1.
- Produces: a real profile directory that Tasks 3–7 install in tests, and `tests/install_test.sh`, which later tasks extend with new `test_*` functions and new names in its `run_tests` line.

- [ ] **Step 1: Write the failing profile-contract test**

Create `tests/install_test.sh` with only the contract test for now:

```sh
#!/bin/sh
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"
. "$REPO_ROOT/lib/common.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

test_profile_contract() {
  for dir in "$REPO_ROOT"/profiles/*/; do
    name="$(basename "$dir")"
    assert_file "$dir/profile.json" "$name has profile.json"
    assert_file "$dir/CLAUDE.md" "$name has CLAUDE.md"
    assert_file "$dir/settings.json" "$name has settings.json"
    assert_eq "$name" "$(json_field "$dir/profile.json" name)" "$name profile.json name matches directory"
    target="$(json_field "$dir/profile.json" target)"
    shim="$(json_field "$dir/profile.json" shim)"
    assert_status 0 "$name declares a safe target" -- guard_target "$(expand_path "$target")" "$REPO_ROOT"
    if [ -n "$shim" ]; then
      _pass "$name declares a shim"
    else
      _fail "$name declares a shim"
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
  done
}

run_tests test_profile_contract
```

- [ ] **Step 2: Run it to verify it fails**

Run: `sh tests/install_test.sh`
Expected: FAIL — `profiles/*/` does not exist yet, so `assert_file` reports missing `profile.json`.

- [ ] **Step 3: Create the `general` profile**

`profiles/general/profile.json`:

```json
{
  "name": "general",
  "description": "Minimal general-purpose profile — a clean room, isolated from ~/.claude",
  "target": "~/.claude-general",
  "shim": "claude-gen"
}
```

`profiles/general/CLAUDE.md`:

```markdown
# General Profile

This is a deliberately minimal, isolated Claude Code profile. It carries no
game-development context and no third-party plugins.

Use it when you want a clean assistant without the conventions of another
profile bleeding in.
```

`profiles/general/settings.json`:

```json
{
  "model": "opus"
}
```

`profiles/general/skills/repo-conventions/SKILL.md`:

```markdown
---
name: repo-conventions
description: Use when starting work in an unfamiliar repository — establishes how to read its conventions before writing code.
---

# Repo Conventions

Before writing code in a repository you have not worked in:

1. Read the README and any `CONTRIBUTING` file.
2. Read the last twenty commits (`git log --oneline -20`) to learn the commit
   message style and the size of a typical change.
3. Find the test command and run it once, unchanged, to see the baseline.
4. Open two files near the code you will change and match their naming,
   comment density, and error-handling style.

Match what is there. Do not introduce a new pattern without saying why.
```

- [ ] **Step 4: Remove the empty stub directories**

```bash
rmdir game_dev general 2>/dev/null || true
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `sh tests/install_test.sh`
Expected: PASS — `0 failed`.

- [ ] **Step 6: Commit**

```bash
git add profiles/general tests/install_test.sh
git rm -r --cached game_dev general 2>/dev/null || true
git commit -m "feat: general profile and profile contract test"
```

---

### Task 3: `install.sh` — argument parsing, profile resolution, guard, dry-run

**Files:**
- Create: `install.sh`
- Modify: `tests/install_test.sh` (add `test_install_guard`, `test_install_dry_run`, `test_install_unknown_profile`; extend the `run_tests` line)

**Interfaces:**
- Consumes: `guard_target`, `json_field`, `expand_path`, `run`, `die` from `lib/common.sh`; the `general` profile from Task 2.
- Produces: `install.sh` with flags `--mode symlink|copy`, `--target DIR`, `--shim-dir DIR`, `--dry-run`, `-h|--help`; exit code 1 on a refused target or unknown profile. Later tasks add install steps to the same script.

- [ ] **Step 1: Write the failing tests**

Add to `tests/install_test.sh`, above the `run_tests` line:

```sh
test_install_unknown_profile() {
  assert_status 1 "unknown profile is refused" -- \
    sh "$REPO_ROOT/install.sh" nope --target "$TMP/u" --shim-dir "$TMP/bin"
}

test_install_guard() {
  assert_status 1 "refuses ~/.claude as target" -- \
    sh "$REPO_ROOT/install.sh" general --target "$HOME/.claude" --shim-dir "$TMP/bin"
  assert_status 1 "refuses home as target" -- \
    sh "$REPO_ROOT/install.sh" general --target "$HOME" --shim-dir "$TMP/bin"
  assert_status 1 "refuses in-repo target" -- \
    sh "$REPO_ROOT/install.sh" general --target "$REPO_ROOT/profiles" --shim-dir "$TMP/bin"
  assert_missing "$TMP/bin/claude-gen" "no shim written by a refused install"
}

test_install_dry_run() {
  sh "$REPO_ROOT/install.sh" general --target "$TMP/dry" --shim-dir "$TMP/bin" --dry-run >/dev/null
  assert_missing "$TMP/dry" "dry run creates no config root"
  assert_missing "$TMP/bin/claude-gen" "dry run creates no shim"
}
```

Change the last line to:

```sh
run_tests test_profile_contract test_install_unknown_profile test_install_guard test_install_dry_run
```

- [ ] **Step 2: Run to verify they fail**

Run: `sh tests/install_test.sh`
Expected: FAIL — `install.sh` does not exist, so `sh install.sh` exits 127, not 1.

- [ ] **Step 3: Write `install.sh`**

Create `install.sh`:

```sh
#!/bin/sh
set -eu
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
. "$REPO_ROOT/lib/common.sh"

usage() {
  cat <<'USAGE'
Usage: install.sh <profile> [options]

Install a profile from this repository into its own Claude Code config root,
leaving ~/.claude untouched.

Options:
  --mode symlink|copy   symlink (default) keeps the repo as source of truth;
                        copy takes a frozen snapshot
  --target DIR          override the target from profile.json
  --shim-dir DIR        where to write the launch shim (default ~/.local/bin)
  --dry-run             print every action, change nothing
  -h, --help            show this help

Profiles: see profiles/ in this repository.
USAGE
}

PROFILE=""
MODE="symlink"
TARGET_OVERRIDE=""
SHIM_DIR="$HOME/.local/bin"
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --mode) MODE="${2:-}"; shift 2 ;;
    --target) TARGET_OVERRIDE="${2:-}"; shift 2 ;;
    --shim-dir) SHIM_DIR="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -*) die "unknown option: $1" ;;
    *) [ -z "$PROFILE" ] || die "only one profile at a time"; PROFILE="$1"; shift ;;
  esac
done
export DRY_RUN

[ -n "$PROFILE" ] || { usage; die "no profile given"; }
case "$MODE" in symlink|copy) ;; *) die "unknown mode: $MODE" ;; esac

PROFILE_DIR="$REPO_ROOT/profiles/$PROFILE"
[ -d "$PROFILE_DIR" ] || die "unknown profile: $PROFILE"
[ -f "$PROFILE_DIR/profile.json" ] || die "profile has no profile.json: $PROFILE"

if [ -n "$TARGET_OVERRIDE" ]; then
  TARGET="$(expand_path "$TARGET_OVERRIDE")"
else
  TARGET="$(expand_path "$(json_field "$PROFILE_DIR/profile.json" target)")"
fi
SHIM_NAME="$(json_field "$PROFILE_DIR/profile.json" shim)"
[ -n "$SHIM_NAME" ] || die "profile.json has no shim name"

guard_target "$TARGET" "$REPO_ROOT"

log "profile:  $PROFILE"
log "target:   $TARGET"
log "mode:     $MODE"
log "shim:     $SHIM_DIR/$SHIM_NAME"
if [ "$DRY_RUN" = "1" ]; then log "(dry run — nothing will change)"; fi

run mkdir -p "$TARGET"
```

Make it executable:

```bash
chmod +x install.sh
```

- [ ] **Step 4: Run to verify they pass**

Run: `sh tests/install_test.sh`
Expected: PASS — `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add install.sh tests/install_test.sh
git commit -m "feat: install.sh argument parsing, profile resolution, target guard"
```

---

### Task 4: `install.sh` — content install, rendered CLAUDE.md, settings copy, manifest

**Files:**
- Modify: `lib/common.sh` (add `install_entries`, `manifest_add`)
- Modify: `install.sh` (steps 3–5 of the install sequence)
- Modify: `tests/install_test.sh` (add `test_install_content`, `test_install_precedence`, `test_settings_backup`)
- Create: `shared/CLAUDE.part.md`
- Create: `shared/skills/.gitkeep`, `shared/commands/.gitkeep`

**Interfaces:**
- Consumes: everything from Task 3.
- Produces:
  - `install_entries SRC_DIR DEST_DIR MODE` — installs each child of `SRC_DIR` into `DEST_DIR`, replacing any existing entry of the same name; symlinks in `symlink` mode, `cp -R` in `copy` mode; no-op when `SRC_DIR` is absent. Echoes each installed destination path.
  - `manifest_add MANIFEST_FILE PATH` — appends a path, one per line.
  - Manifest at `$TARGET/.omega-ai-manifest`, consumed by Task 7's uninstaller.

- [ ] **Step 1: Write the failing tests**

Add to `tests/install_test.sh`:

```sh
test_install_content() {
  sh "$REPO_ROOT/install.sh" general --target "$TMP/gen" --shim-dir "$TMP/bin" >/dev/null
  assert_file "$TMP/gen/CLAUDE.md" "renders CLAUDE.md"
  assert_contains "$TMP/gen/CLAUDE.md" "General Profile" "rendered CLAUDE.md carries profile content"
  assert_contains "$TMP/gen/CLAUDE.md" "GENERATED" "rendered CLAUDE.md warns it is generated"
  assert_file "$TMP/gen/settings.json" "copies settings.json"
  assert_symlink "$TMP/gen/skills/repo-conventions" "links profile skill"
  assert_file "$TMP/gen/.omega-ai-manifest" "writes a manifest"
  assert_contains "$TMP/gen/.omega-ai-manifest" "skills/repo-conventions" "manifest records the skill"
}

test_install_precedence() {
  mkdir -p "$TMP/fixture/shared/skills/collide" "$TMP/fixture/profile/skills/collide"
  printf 'shared\n' > "$TMP/fixture/shared/skills/collide/SKILL.md"
  printf 'profile\n' > "$TMP/fixture/profile/skills/collide/SKILL.md"
  install_entries "$TMP/fixture/shared/skills" "$TMP/fixture/dest" copy >/dev/null
  install_entries "$TMP/fixture/profile/skills" "$TMP/fixture/dest" copy >/dev/null
  assert_eq "profile" "$(cat "$TMP/fixture/dest/collide/SKILL.md")" "profile entry wins the collision"
}

test_install_copy_mode() {
  sh "$REPO_ROOT/install.sh" general --target "$TMP/cp" --shim-dir "$TMP/bin" --mode copy >/dev/null
  assert_file "$TMP/cp/skills/repo-conventions/SKILL.md" "copy mode installs a real file"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -L "$TMP/cp/skills/repo-conventions" ]; then
    _fail "copy mode installs no symlink"
  else
    _pass "copy mode installs no symlink"
  fi
}

test_settings_backup() {
  printf '{"model":"stale"}\n' > "$TMP/gen/settings.json"
  sh "$REPO_ROOT/install.sh" general --target "$TMP/gen" --shim-dir "$TMP/bin" >/dev/null
  found=0
  for f in "$TMP/gen"/settings.json.bak-*; do
    [ -f "$f" ] && found=1
  done
  assert_eq "1" "$found" "backs up a differing settings.json"
}
```

Extend the runner line:

```sh
run_tests test_profile_contract test_install_unknown_profile test_install_guard \
  test_install_dry_run test_install_content test_install_precedence \\
  test_install_copy_mode test_settings_backup
```

- [ ] **Step 2: Run to verify they fail**

Run: `sh tests/install_test.sh`
Expected: FAIL — no `CLAUDE.md`, no `settings.json`, `install_entries: not found`.

- [ ] **Step 3: Add the helpers to `lib/common.sh`**

Append to `lib/common.sh`:

```sh
# install_entries SRC_DIR DEST_DIR MODE — install each child of SRC_DIR into
# DEST_DIR, replacing same-named entries. Prints each destination path.
install_entries() {
  _src="$1"; _dest="$2"; _mode="$3"
  [ -d "$_src" ] || return 0
  run mkdir -p "$_dest"
  for _entry in "$_src"/*; do
    [ -e "$_entry" ] || continue
    _name="$(basename "$_entry")"
    case "$_name" in .gitkeep) continue ;; esac
    run rm -rf "$_dest/$_name"
    if [ "$_mode" = "copy" ]; then
      run cp -R "$_entry" "$_dest/$_name"
    else
      run ln -s "$_entry" "$_dest/$_name"
    fi
    printf '%s\n' "$_dest/$_name"
  done
}

# manifest_add MANIFEST PATH — record an installed path, one per line.
manifest_add() {
  if [ "${DRY_RUN:-0}" = "1" ]; then
    return 0
  fi
  printf '%s\n' "$2" >> "$1"
}
```

- [ ] **Step 4: Create the shared content**

`shared/CLAUDE.part.md`:

```markdown
# Engineering Standards

Work to industry-standard engineering practice, and recommend it rather than
waiting to be asked.

- Favor composition over inheritance, and decoupled systems over shared state.
- Make data explicit: configuration and content belong in data files, not
  scattered through code.
- Profile before optimizing. Measure, then change one thing.
- Write tests for behavior you intend to keep.
- When a request would lead to an anti-pattern, say so and propose the standard
  alternative instead of silently implementing it.
```

```bash
mkdir -p shared/skills shared/commands
touch shared/skills/.gitkeep shared/commands/.gitkeep
```

- [ ] **Step 5: Add the install steps to `install.sh`**

Append to `install.sh`, after the `run mkdir -p "$TARGET"` line:

```sh
MANIFEST="$TARGET/.omega-ai-manifest"
[ "$DRY_RUN" = "1" ] || : > "$MANIFEST"

# Content directories: shared first, profile second so the profile wins.
for dir in agents skills commands hooks memory; do
  for installed in $(install_entries "$REPO_ROOT/shared/$dir" "$TARGET/$dir" "$MODE"); do
    manifest_add "$MANIFEST" "$installed"
  done
  for installed in $(install_entries "$PROFILE_DIR/$dir" "$TARGET/$dir" "$MODE"); do
    manifest_add "$MANIFEST" "$installed"
  done
done

# CLAUDE.md is generated, so it is always written as a real file.
if [ "$DRY_RUN" = "1" ]; then
  log "DRY  render $TARGET/CLAUDE.md"
else
  {
    printf '<!-- GENERATED by omega-ai install.sh from shared/CLAUDE.part.md\n'
    printf '     and profiles/%s/CLAUDE.md. Edits here are overwritten. -->\n\n' "$PROFILE"
    if [ -f "$REPO_ROOT/shared/CLAUDE.part.md" ]; then
      cat "$REPO_ROOT/shared/CLAUDE.part.md"
    fi
    printf '\n'
    cat "$PROFILE_DIR/CLAUDE.md"
  } > "$TARGET/CLAUDE.md"
  manifest_add "$MANIFEST" "$TARGET/CLAUDE.md"
fi

# settings.json is copied, never linked: Claude Code writes to it in-session.
if [ "$DRY_RUN" = "1" ]; then
  log "DRY  copy $TARGET/settings.json"
elif [ -f "$PROFILE_DIR/settings.json" ]; then
  if [ -f "$TARGET/settings.json" ] && ! cmp -s "$PROFILE_DIR/settings.json" "$TARGET/settings.json"; then
    backup="$TARGET/settings.json.bak-$(date +%Y%m%d%H%M%S)"
    cp "$TARGET/settings.json" "$backup"
    warn "existing settings.json differed; backed up to $backup"
  fi
  cp "$PROFILE_DIR/settings.json" "$TARGET/settings.json"
  manifest_add "$MANIFEST" "$TARGET/settings.json"
fi
```

- [ ] **Step 6: Run to verify they pass**

Run: `sh tests/install_test.sh`
Expected: PASS — `0 failed`.

- [ ] **Step 7: Commit**

```bash
git add lib/common.sh install.sh tests/install_test.sh shared
git commit -m "feat: install content, render CLAUDE.md, copy settings, write manifest"
```

---

### Task 5: `install.sh` — launch shim

**Files:**
- Modify: `install.sh` (shim step)
- Modify: `tests/install_test.sh` (add `test_shim`)

**Interfaces:**
- Consumes: `SHIM_DIR`, `SHIM_NAME`, `TARGET`, `MANIFEST` from Tasks 3–4.
- Produces: an executable shim at `$SHIM_DIR/$SHIM_NAME` that sets `CLAUDE_CONFIG_DIR` and execs `claude`; the shim path is appended to the manifest.

- [ ] **Step 1: Write the failing test**

Add to `tests/install_test.sh` and to the `run_tests` line:

```sh
test_shim() {
  sh "$REPO_ROOT/install.sh" general --target "$TMP/gen" --shim-dir "$TMP/bin" >/dev/null
  assert_file "$TMP/bin/claude-gen" "writes the shim"
  assert_contains "$TMP/bin/claude-gen" "CLAUDE_CONFIG_DIR" "shim sets CLAUDE_CONFIG_DIR"
  assert_contains "$TMP/bin/claude-gen" "$TMP/gen" "shim points at the target root"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -x "$TMP/bin/claude-gen" ]; then _pass "shim is executable"; else _fail "shim is executable"; fi
  assert_contains "$TMP/gen/.omega-ai-manifest" "bin/claude-gen" "manifest records the shim"
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `sh tests/install_test.sh`
Expected: FAIL — `no regular file at $TMP/bin/claude-gen`.

- [ ] **Step 3: Add the shim step to `install.sh`**

Append to `install.sh`:

```sh
if [ "$DRY_RUN" = "1" ]; then
  log "DRY  write shim $SHIM_DIR/$SHIM_NAME"
else
  mkdir -p "$SHIM_DIR"
  cat > "$SHIM_DIR/$SHIM_NAME" <<SHIM
#!/usr/bin/env sh
# Generated by omega-ai install.sh — launches Claude Code against the
# $PROFILE profile's isolated config root.
CLAUDE_CONFIG_DIR="$TARGET" exec claude "\$@"
SHIM
  chmod +x "$SHIM_DIR/$SHIM_NAME"
  manifest_add "$MANIFEST" "$SHIM_DIR/$SHIM_NAME"

  case ":$PATH:" in
    *":$SHIM_DIR:"*) ;;
    *) warn "$SHIM_DIR is not on your PATH. Add it:
    export PATH=\"$SHIM_DIR:\$PATH\"" ;;
  esac
fi

log ""
log "Installed. Launch with: $SHIM_NAME"
```

- [ ] **Step 4: Run to verify it passes**

Run: `sh tests/install_test.sh`
Expected: PASS — `0 failed`.

- [ ] **Step 5: Verify the shim by hand**

Run: `sh install.sh general --target "$(mktemp -d)/cfg" --shim-dir "$(mktemp -d)" --dry-run`
Expected: the dry-run output lists a `write shim` line and creates nothing.

- [ ] **Step 6: Commit**

```bash
git add install.sh tests/install_test.sh
git commit -m "feat: write CLAUDE_CONFIG_DIR launch shim"
```

---

### Task 6: `doctor.sh`

**Files:**
- Create: `doctor.sh`
- Modify: `install.sh` (final step invokes the doctor)
- Modify: `tests/install_test.sh` (add `test_doctor`)

**Interfaces:**
- Consumes: an installed target and its manifest.
- Produces: `doctor.sh <profile> [--target DIR]`, exit 0 when the install looks healthy, exit 1 when the config root is missing or a leak into `~/.claude` is found. Its report prints the literal strings `config root:`, `leakage:` and either `leakage: none` or one line per leaking path.

- [ ] **Step 1: Write the failing test**

Add to `tests/install_test.sh` and the `run_tests` line:

```sh
test_doctor() {
  sh "$REPO_ROOT/install.sh" general --target "$TMP/gen" --shim-dir "$TMP/bin" >/dev/null
  sh "$REPO_ROOT/doctor.sh" general --target "$TMP/gen" > "$TMP/doctor.out" 2>&1
  assert_contains "$TMP/doctor.out" "$TMP/gen" "doctor reports the resolved config root"
  assert_contains "$TMP/doctor.out" "leakage: none" "doctor finds no leak into ~/.claude"
  assert_status 1 "doctor fails on a missing root" -- \
    sh "$REPO_ROOT/doctor.sh" general --target "$TMP/absent"
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `sh tests/install_test.sh`
Expected: FAIL — `doctor.sh` does not exist.

- [ ] **Step 3: Write `doctor.sh`**

```sh
#!/bin/sh
set -eu
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
. "$REPO_ROOT/lib/common.sh"

PROFILE=""
TARGET_OVERRIDE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET_OVERRIDE="${2:-}"; shift 2 ;;
    -h|--help) log "Usage: doctor.sh <profile> [--target DIR]"; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) PROFILE="$1"; shift ;;
  esac
done
[ -n "$PROFILE" ] || die "no profile given"

PROFILE_DIR="$REPO_ROOT/profiles/$PROFILE"
[ -d "$PROFILE_DIR" ] || die "unknown profile: $PROFILE"

if [ -n "$TARGET_OVERRIDE" ]; then
  TARGET="$(expand_path "$TARGET_OVERRIDE")"
else
  TARGET="$(expand_path "$(json_field "$PROFILE_DIR/profile.json" target)")"
fi
SHIM_NAME="$(json_field "$PROFILE_DIR/profile.json" shim)"

log "profile:      $PROFILE"
log "config root:  $TARGET"
[ -d "$TARGET" ] || die "config root does not exist — run install.sh $PROFILE"

count() { [ -d "$1" ] && ls -1 "$1" 2>/dev/null | wc -l | tr -d ' ' || printf '0'; }
log "CLAUDE.md:    $([ -f "$TARGET/CLAUDE.md" ] && printf 'present' || printf 'MISSING')"
log "settings:     $([ -f "$TARGET/settings.json" ] && printf 'present' || printf 'MISSING')"
log "agents:       $(count "$TARGET/agents")"
log "skills:       $(count "$TARGET/skills")"
log "commands:     $(count "$TARGET/commands")"
log "hooks:        $(count "$TARGET/hooks")"

if [ -f "$TARGET/settings.json" ]; then
  log "plugins:"
  grep -o '"[^"]*@[^"]*"[[:space:]]*:[[:space:]]*true' "$TARGET/settings.json" 2>/dev/null \
    | sed 's/^/  /' || log "  (none)"
fi

log "launch:       $SHIM_NAME"
if command -v "$SHIM_NAME" >/dev/null 2>&1; then
  log "shim on PATH: yes ($(command -v "$SHIM_NAME"))"
else
  log "shim on PATH: no — add your shim directory to PATH"
fi

# Leakage check: nothing inside this root may resolve into ~/.claude.
leaks="$(find "$TARGET" -maxdepth 3 -type l -exec readlink {} \; 2>/dev/null \
  | grep -F "$HOME/.claude/" || true)"
case "${TARGET%/}" in
  "${HOME%/}/.claude") leaks="$leaks
target is ~/.claude" ;;
esac
if [ -n "$(printf '%s' "$leaks" | tr -d '[:space:]')" ]; then
  log "leakage:"
  printf '%s\n' "$leaks" | sed 's/^/  /'
  exit 1
fi
log "leakage: none"
```

```bash
chmod +x doctor.sh
```

- [ ] **Step 4: Have `install.sh` finish by running the doctor**

Append to `install.sh`:

```sh
if [ "$DRY_RUN" = "1" ]; then
  log "(dry run complete)"
else
  log ""
  sh "$REPO_ROOT/doctor.sh" "$PROFILE" --target "$TARGET"
fi
```

- [ ] **Step 5: Run to verify it passes**

Run: `sh tests/install_test.sh`
Expected: PASS — `0 failed`.

- [ ] **Step 6: Commit**

```bash
git add doctor.sh install.sh tests/install_test.sh
git commit -m "feat: doctor.sh isolation report, run at end of install"
```

---

### Task 7: `uninstall.sh`

**Files:**
- Create: `uninstall.sh`
- Modify: `tests/install_test.sh` (add `test_uninstall`, `test_uninstall_purge`, `test_two_profiles_independent`)

**Interfaces:**
- Consumes: `$TARGET/.omega-ai-manifest` written in Tasks 4–5.
- Produces: `uninstall.sh <profile> [--target DIR] [--purge] [--yes]`. Without `--purge` it removes only manifest entries, the manifest itself, and the shim, leaving session data. With `--purge --yes` it removes the whole config root without prompting.

- [ ] **Step 1: Write the failing tests**

Add to `tests/install_test.sh` and the `run_tests` line:

```sh
test_uninstall() {
  sh "$REPO_ROOT/install.sh" general --target "$TMP/un" --shim-dir "$TMP/bin" >/dev/null
  mkdir -p "$TMP/un/sessions"
  printf 'user data\n' > "$TMP/un/sessions/keep.txt"
  sh "$REPO_ROOT/uninstall.sh" general --target "$TMP/un" --shim-dir "$TMP/bin" >/dev/null
  assert_missing "$TMP/un/skills/repo-conventions" "removes installed skill"
  assert_missing "$TMP/un/CLAUDE.md" "removes rendered CLAUDE.md"
  assert_missing "$TMP/bin/claude-gen" "removes the shim"
  assert_missing "$TMP/un/.omega-ai-manifest" "removes the manifest"
  assert_file "$TMP/un/sessions/keep.txt" "keeps user data"
}

test_uninstall_purge() {
  sh "$REPO_ROOT/install.sh" general --target "$TMP/purge" --shim-dir "$TMP/bin" >/dev/null
  sh "$REPO_ROOT/uninstall.sh" general --target "$TMP/purge" --shim-dir "$TMP/bin" --purge --yes >/dev/null
  assert_missing "$TMP/purge" "purge removes the whole config root"
}

test_two_profiles_independent() {
  sh "$REPO_ROOT/install.sh" general --target "$TMP/a" --shim-dir "$TMP/bin" >/dev/null
  sh "$REPO_ROOT/install.sh" game-dev --target "$TMP/b" --shim-dir "$TMP/bin" >/dev/null
  assert_file "$TMP/a/CLAUDE.md" "first profile intact after second install"
  assert_file "$TMP/b/CLAUDE.md" "second profile installed"
  assert_contains "$TMP/a/CLAUDE.md" "General Profile" "first root keeps its own prompt"
  sh "$REPO_ROOT/uninstall.sh" game-dev --target "$TMP/b" --shim-dir "$TMP/bin" --purge --yes >/dev/null
  assert_file "$TMP/a/CLAUDE.md" "uninstalling one profile leaves the other alone"
  assert_file "$TMP/bin/claude-gen" "other profile's shim survives"
}
```

Note: `test_two_profiles_independent` needs the `game-dev` profile, created in Task 9. Until then it fails on the unknown profile — that is expected and is closed by Task 9.

- [ ] **Step 2: Run to verify they fail**

Run: `sh tests/install_test.sh`
Expected: FAIL — `uninstall.sh` does not exist.

- [ ] **Step 3: Write `uninstall.sh`**

```sh
#!/bin/sh
set -eu
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
. "$REPO_ROOT/lib/common.sh"

PROFILE=""
TARGET_OVERRIDE=""
SHIM_DIR="$HOME/.local/bin"
PURGE=0
ASSUME_YES=0

while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET_OVERRIDE="${2:-}"; shift 2 ;;
    --shim-dir) SHIM_DIR="${2:-}"; shift 2 ;;
    --purge) PURGE=1; shift ;;
    --yes) ASSUME_YES=1; shift ;;
    -h|--help) log "Usage: uninstall.sh <profile> [--target DIR] [--shim-dir DIR] [--purge] [--yes]"; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) PROFILE="$1"; shift ;;
  esac
done
[ -n "$PROFILE" ] || die "no profile given"

PROFILE_DIR="$REPO_ROOT/profiles/$PROFILE"
[ -d "$PROFILE_DIR" ] || die "unknown profile: $PROFILE"

if [ -n "$TARGET_OVERRIDE" ]; then
  TARGET="$(expand_path "$TARGET_OVERRIDE")"
else
  TARGET="$(expand_path "$(json_field "$PROFILE_DIR/profile.json" target)")"
fi
SHIM_NAME="$(json_field "$PROFILE_DIR/profile.json" shim)"

guard_target "$TARGET" "$REPO_ROOT"
[ -d "$TARGET" ] || die "nothing installed at $TARGET"

MANIFEST="$TARGET/.omega-ai-manifest"

if [ "$PURGE" = "1" ]; then
  if [ "$ASSUME_YES" != "1" ]; then
    printf 'Delete the entire config root %s, including sessions and history? [y/N] ' "$TARGET"
    read -r reply
    case "$reply" in y|Y) ;; *) die "aborted" ;; esac
  fi
  rm -rf "$TARGET"
  if [ -n "$SHIM_NAME" ]; then rm -f "$SHIM_DIR/$SHIM_NAME"; fi
  log "purged $TARGET"
  exit 0
fi

if [ -f "$MANIFEST" ]; then
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    rm -rf "$entry"
  done < "$MANIFEST"
  rm -f "$MANIFEST"
else
  warn "no manifest at $MANIFEST — removing nothing"
fi

if [ -n "$SHIM_NAME" ]; then rm -f "$SHIM_DIR/$SHIM_NAME"; fi
log "uninstalled $PROFILE from $TARGET (user data kept; use --purge to remove everything)"
```

```bash
chmod +x uninstall.sh
```

- [ ] **Step 4: Run the tests**

Run: `sh tests/install_test.sh`
Expected: every test passes except `test_two_profiles_independent`, which fails with `unknown profile: game-dev` until Task 9.

- [ ] **Step 5: Commit**

```bash
git add uninstall.sh tests/install_test.sh
git commit -m "feat: manifest-driven uninstall with optional purge"
```

---

### Task 8: `sync-memory.sh`

**Files:**
- Create: `sync-memory.sh`
- Create: `tests/sync_test.sh`
- Create: `tests/run_all.sh`

**Interfaces:**
- Consumes: `lib/common.sh`, an installed target.
- Produces: `sync-memory.sh <profile> [--target DIR] [--dry-run]` — copies every regular file under `$TARGET/memory/` that is not a symlink into `profiles/<profile>/memory/`, preserving relative paths, and prints one line per file copied. Symlinked entries already point at the repository and are skipped. Also produces `tests/run_all.sh`, the entry point for the whole suite.

- [ ] **Step 1: Write the failing test**

Create `tests/sync_test.sh`:

```sh
#!/bin/sh
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"
. "$REPO_ROOT/lib/common.sh"

TMP="$(mktemp -d)"
SANDBOX="$TMP/repo"
trap 'rm -rf "$TMP"' EXIT

setup_sandbox() {
  mkdir -p "$SANDBOX"
  cp -R "$REPO_ROOT/lib" "$REPO_ROOT/shared" "$REPO_ROOT/profiles" "$SANDBOX/"
  cp "$REPO_ROOT/sync-memory.sh" "$SANDBOX/"
  mkdir -p "$SANDBOX/profiles/general/memory"
}

test_sync_copies_new_memory() {
  setup_sandbox
  mkdir -p "$TMP/cfg/memory/notes"
  printf 'decided on tilemap chunking\n' > "$TMP/cfg/memory/notes/level-streaming.md"
  sh "$SANDBOX/sync-memory.sh" general --target "$TMP/cfg" >/dev/null
  assert_file "$SANDBOX/profiles/general/memory/notes/level-streaming.md" "copies new memory file into the profile"
  assert_contains "$SANDBOX/profiles/general/memory/notes/level-streaming.md" "tilemap chunking" "content preserved"
}

test_sync_skips_symlinks() {
  setup_sandbox
  mkdir -p "$TMP/cfg2/memory"
  printf 'repo copy\n' > "$SANDBOX/profiles/general/memory/MEMORY.md"
  ln -s "$SANDBOX/profiles/general/memory/MEMORY.md" "$TMP/cfg2/memory/MEMORY.md"
  sh "$SANDBOX/sync-memory.sh" general --target "$TMP/cfg2" > "$TMP/sync.out"
  assert_eq "repo copy" "$(cat "$SANDBOX/profiles/general/memory/MEMORY.md")" "symlinked memory left untouched"
}

test_sync_dry_run() {
  setup_sandbox
  mkdir -p "$TMP/cfg3/memory"
  printf 'x\n' > "$TMP/cfg3/memory/new.md"
  sh "$SANDBOX/sync-memory.sh" general --target "$TMP/cfg3" --dry-run >/dev/null
  assert_missing "$SANDBOX/profiles/general/memory/new.md" "dry run copies nothing"
}

run_tests test_sync_copies_new_memory test_sync_skips_symlinks test_sync_dry_run
```

- [ ] **Step 2: Run to verify it fails**

Run: `sh tests/sync_test.sh`
Expected: FAIL — `cp: sync-memory.sh: No such file or directory`.

- [ ] **Step 3: Write `sync-memory.sh`**

```sh
#!/bin/sh
set -eu
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
. "$REPO_ROOT/lib/common.sh"

PROFILE=""
TARGET_OVERRIDE=""
DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET_OVERRIDE="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) log "Usage: sync-memory.sh <profile> [--target DIR] [--dry-run]"; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) PROFILE="$1"; shift ;;
  esac
done
export DRY_RUN
[ -n "$PROFILE" ] || die "no profile given"

PROFILE_DIR="$REPO_ROOT/profiles/$PROFILE"
[ -d "$PROFILE_DIR" ] || die "unknown profile: $PROFILE"

if [ -n "$TARGET_OVERRIDE" ]; then
  TARGET="$(expand_path "$TARGET_OVERRIDE")"
else
  TARGET="$(expand_path "$(json_field "$PROFILE_DIR/profile.json" target)")"
fi

SRC="$TARGET/memory"
DEST="$PROFILE_DIR/memory"
[ -d "$SRC" ] || die "no memory directory at $SRC"

# -type f skips symlinks, which already point back into this repository.
find "$SRC" -type f -print | while IFS= read -r file; do
  rel="${file#"$SRC"/}"
  run mkdir -p "$DEST/$(dirname "$rel")"
  run cp "$file" "$DEST/$rel"
  log "synced $rel"
done

log "memory sync complete: $SRC -> $DEST"
```

```bash
chmod +x sync-memory.sh
```

- [ ] **Step 4: Write the suite entry point**

Create `tests/run_all.sh`:

```sh
#!/bin/sh
# Runs every test file. Non-zero exit if any file fails.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
status=0
for f in "$DIR"/lib_test.sh "$DIR"/install_test.sh "$DIR"/sync_test.sh; do
  printf '\n=== %s ===\n' "$(basename "$f")"
  sh "$f" || status=1
done
exit "$status"
```

```bash
chmod +x tests/run_all.sh
```

- [ ] **Step 5: Run to verify it passes**

Run: `sh tests/sync_test.sh`
Expected: PASS — `0 failed`.

- [ ] **Step 6: Commit**

```bash
git add sync-memory.sh tests/sync_test.sh tests/run_all.sh
git commit -m "feat: sync session-written memory back into the profile"
```

---

### Task 9: The `game-dev` profile

**Files:**
- Create: `profiles/game-dev/profile.json`
- Create: `profiles/game-dev/CLAUDE.md`
- Create: `profiles/game-dev/settings.json`
- Create: `profiles/game-dev/agents/game-designer.md`
- Create: `profiles/game-dev/agents/2d-art-pipeline.md`
- Create: `profiles/game-dev/agents/game-feel-tuner.md`
- Create: `profiles/game-dev/skills/game-design-doc/SKILL.md`
- Create: `profiles/game-dev/skills/core-loop-design/SKILL.md`
- Create: `profiles/game-dev/skills/2d-sprite-pipeline/SKILL.md`
- Create: `profiles/game-dev/skills/game-feel/SKILL.md`
- Create: `profiles/game-dev/memory/MEMORY.md`

**Interfaces:**
- Consumes: the installer from Tasks 3–7; the profile contract test from Task 2.
- Produces: the `game-dev` profile, which closes `test_two_profiles_independent` from Task 7.

- [ ] **Step 1: Run the suite to see the outstanding failure**

Run: `sh tests/run_all.sh`
Expected: `install_test.sh` fails only in `test_two_profiles_independent` with `unknown profile: game-dev`.

- [ ] **Step 2: Write `profile.json` and `settings.json`**

`profiles/game-dev/profile.json`:

```json
{
  "name": "game-dev",
  "description": "2D game development AI — Godot 4.x plus an engine-agnostic core",
  "target": "~/.claude-gamedev",
  "shim": "claude-gd"
}
```

`profiles/game-dev/settings.json`:

```json
{
  "model": "opus",
  "enabledPlugins": {
    "superpowers@claude-plugins-official": true,
    "godot-prompter@skillsmith": true
  },
  "extraKnownMarketplaces": {
    "skillsmith": {
      "source": {
        "source": "github",
        "repo": "jame581/skillsmith"
      }
    }
  }
}
```

- [ ] **Step 3: Write the profile `CLAUDE.md`**

`profiles/game-dev/CLAUDE.md`:

```markdown
# 2D Game Development Profile

This profile is for building 2D games. The default engine is Godot 4.x; design
and pipeline work that does not depend on an engine is engine-agnostic and
should stay that way.

## Architecture

- Composition over inheritance. A behavior belongs in its own node or component
  that can be attached, not in a deepening base class.
- Decouple systems with signals and a global event bus. A system should not hold
  a reference to another system just to notify it.
- Keep data in `Resource` files, not in code. Items, enemies, levels, and tuning
  values are data a designer can edit without a programmer.
- Model state explicitly with a state machine. Distinguish the gameplay state
  machine from the animation state machine; they are not the same object.
- Keep scenes cohesive. A scene that needs a comment to explain what it is
  should be split.

## Working method

- Reach for the `godot-prompter` skills before writing Godot code — they encode
  the engine's own conventions.
- Profile before optimizing. Godot's profiler names the frame cost; guesses do
  not.
- Write tests with GUT or gdUnit4 for logic that is not visual.
- When a request would lead to an anti-pattern, say so and propose the standard
  alternative instead of silently implementing it.

## 2D specifics

- Use a fixed base resolution and an explicit stretch mode; decide this before
  building UI, not after.
- Keep art on a consistent pixels-per-unit; mixing scales makes camera and
  physics tuning unrepeatable.
- Prefer TileMapLayer for level geometry, and keep collision authored on the
  tileset rather than hand-placed per level.
```

- [ ] **Step 4: Write the three agents**

`profiles/game-dev/agents/game-designer.md`:

```markdown
---
name: game-designer
description: Use when shaping what the game is — core loop, mechanics, progression, difficulty, and scope. Engine-agnostic. Produces design decisions and a design document, not code.
tools: Read, Write, Edit, Grep, Glob, WebSearch
model: opus
---

You are a game designer. Your output is decisions and documents, never code.

Method:

1. Establish the core loop before anything else: what the player does in ten
   seconds, in ten minutes, and in ten hours. If the ten-second loop is not fun
   on paper, nothing built on it will be.
2. For each mechanic, state what it adds to the loop and what it costs to build.
   Cut mechanics that do not change player decisions.
3. Define progression as a sequence of new decisions, not new numbers. A bigger
   number is not progression.
4. Set difficulty by naming the skill being tested and how the player learns it.
5. Scope ruthlessly. Name the smallest version that is still the game.

Ask about the target player and the session length before proposing mechanics.
Write findings to a design document; do not open engine files.
```

`profiles/game-dev/agents/2d-art-pipeline.md`:

```markdown
---
name: 2d-art-pipeline
description: Use for 2D art production and import — sprite authoring rules, atlases, pixels-per-unit, animation frame budgets, import settings, and keeping assets consistent across a project.
tools: Read, Write, Edit, Grep, Glob, Bash
model: opus
---

You own the path an image takes from an art tool to a running frame.

Rules you enforce:

- One pixels-per-unit for the whole project, written down and referenced.
  Mixed scales make camera, physics, and UI tuning unrepeatable.
- Pixel art uses nearest-neighbor filtering, no mipmaps, and integer scaling.
  Smooth art uses linear filtering. Never mix the two in one atlas.
- Sprites are packed into atlases by draw order and lifetime, not by folder
  convenience — a UI atlas and a level atlas should not share pages.
- Animation frame counts are a budget. State the budget per character before
  animation starts.
- Import settings live in version control and are reviewed like code.

When asked to add an asset, first check whether an existing atlas or naming
convention already covers it. Report the pipeline consequence of any exception
before making it.
```

`profiles/game-dev/agents/game-feel-tuner.md`:

```markdown
---
name: game-feel-tuner
description: Use when the game works but does not feel good — input response, animation timing, camera behavior, hit feedback, screen shake, and juice. Diagnoses feel problems before adding effects.
tools: Read, Write, Edit, Grep, Glob
model: opus
---

You diagnose feel before you add effects. Juice layered on a broken input model
hides the problem instead of fixing it.

Order of investigation:

1. **Input latency.** How many frames pass between the press and the first
   visible change? Anything over two frames is felt.
2. **Forgiveness.** Coyote time, input buffering, and edge assists. Most
   "unresponsive" controls are actually unforgiving ones.
3. **Acceleration curves.** Ramp times for start and stop, separately. Symmetric
   curves feel sluggish.
4. **Animation timing.** Anticipation, contact, and recovery frames. A hit needs
   a hold frame to read.
5. **Camera.** Follow lag, look-ahead, and deadzone before any shake.
6. **Feedback.** Only then: particles, shake, freeze frames, audio.

Change one variable at a time, and state the expected perceptual difference
before the change so it can be confirmed or refuted.
```

- [ ] **Step 5: Write the four skills**

`profiles/game-dev/skills/game-design-doc/SKILL.md`:

```markdown
---
name: game-design-doc
description: Use when starting a new game or a major feature — produces a short, decision-dense design document instead of an unread specification.
---

# Game Design Document

A design document exists to record decisions, not to describe dreams. Keep it
short enough that it is actually read.

Write these sections, in this order, and stop:

1. **Pitch** — one sentence. Genre, player fantasy, and the hook.
2. **Core loop** — ten seconds, ten minutes, ten hours.
3. **Player verbs** — the complete list of what the player can do. If a verb
   does not appear in the loop, cut it.
4. **Progression** — what new decision the player gains, and when.
5. **Failure** — what losing costs and how the player re-enters.
6. **Scope** — the smallest shippable version, and an explicit not-doing list.

Every section states a decision. If a section reads as a possibility rather than
a decision, it is not finished.
```

`profiles/game-dev/skills/core-loop-design/SKILL.md`:

```markdown
---
name: core-loop-design
description: Use when designing or repairing a game's core loop — the ten-second cycle everything else is built on.
---

# Core Loop Design

The core loop is the shortest cycle the player repeats voluntarily. Get it wrong
and no amount of content rescues the game.

Define it as: **perceive → decide → act → feedback → change in state.**

Test the loop against these questions:

- Is there a real decision, or only execution? A loop with no decision is a
  chore.
- Does the feedback arrive fast enough to teach? Feedback later than about 300ms
  is not felt as caused by the action.
- Does the state change alter the next decision? If the loop returns to an
  identical state, it is a treadmill.
- Would the player repeat it with no reward attached? If not, the reward is
  carrying the loop, and rewards run out.

Prototype the loop with placeholder art before any content is built. If the
grey-box version is not compelling, fix the loop, not the art.
```

`profiles/game-dev/skills/2d-sprite-pipeline/SKILL.md`:

```markdown
---
name: 2d-sprite-pipeline
description: Use when setting up or repairing 2D sprite import in Godot 4.x — pixels-per-unit, filtering, atlases, and animation import.
---

# 2D Sprite Pipeline

Decide these before importing the first asset, and record the decision in the
repository:

1. **Base resolution and stretch mode.** Set `display/window/size/viewport_width`
   and `height` to the design resolution. Use stretch mode `canvas_items` with
   aspect `keep` for most 2D games; use `viewport` for strict pixel art.
2. **Pixels per unit.** One value for the project. All art is authored to it.
3. **Filtering.** For pixel art, set the project default texture filter to
   Nearest (`rendering/textures/canvas_textures/default_texture_filter`), and
   never override it per-sprite without a written reason.
4. **Atlases.** Group by draw order and lifetime. UI, characters, and level
   tiles get separate atlases so one does not stall the other.
5. **Animation.** Import sprite sheets as `AtlasTexture` regions or use
   `SpriteFrames`. Keep frame rate a property of the animation resource, not of
   code.

When an asset does not fit these rules, change the rules deliberately and update
the record. Do not add a per-asset exception.
```

`profiles/game-dev/skills/game-feel/SKILL.md`:

```markdown
---
name: game-feel
description: Use when controls feel unresponsive, floaty, or unsatisfying — a diagnostic order for input, movement, camera, and feedback before adding effects.
---

# Game Feel

Feel problems are usually input problems wearing an effects costume. Work in
this order and change one variable at a time.

**1. Input latency.** Measure frames from press to first visible change. Handle
movement input in `_physics_process`, not in a signal chain that adds a frame.

**2. Forgiveness windows.** Add coyote time (roughly 0.1s of jump grace after
leaving a ledge) and input buffering (roughly 0.1s of remembered press before
landing). Most "unresponsive" jumps are unforgiving ones.

**3. Asymmetric acceleration.** Separate acceleration and deceleration values.
Fast stop with slower start reads as crisp; the reverse reads as ice.

**4. Gravity asymmetry.** Higher gravity on the way down than on the way up
makes a jump feel deliberate rather than floaty.

**5. Camera.** Deadzone, follow lag, and look-ahead in the direction of travel.
Tune these before adding shake — shake on a badly-tuned camera reads as noise.

**6. Feedback.** Hit-stop of two to four frames, particles, and audio last.

State the perceptual change you expect before each edit, then confirm it.
```

`profiles/game-dev/memory/MEMORY.md`:

```markdown
# Game Development Memory

Durable, project-independent decisions for 2D game work. One line per memory,
pointing at a file in this directory.

<!-- Add entries as: - [Title](file.md) — hook -->
```

- [ ] **Step 6: Run the full suite**

Run: `sh tests/run_all.sh`
Expected: PASS — every file reports `0 failed`, including `test_two_profiles_independent`.

- [ ] **Step 7: Commit**

```bash
git add profiles/game-dev
git commit -m "feat: game-dev profile with agents, skills, and 2D standards"
```

---

### Task 10: README, gitignore, and a real install

**Files:**
- Modify: `README.md`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: everything above.
- Produces: user-facing documentation and a verified real installation.

- [ ] **Step 1: Write the README**

`README.md`:

```markdown
# omega-ai

Version-controlled Claude Code profiles — agents, skills, commands, settings,
and seed memory — each installable into its own isolated config directory.

Installing a profile never touches `~/.claude`. Switching between assistants is
a matter of which command you type.

## Profiles

| Profile | Config root | Launch | Purpose |
|---|---|---|---|
| `game-dev` | `~/.claude-gamedev` | `claude-gd` | 2D game development, Godot 4.x plus engine-agnostic design |
| `general` | `~/.claude-general` | `claude-gen` | Minimal clean-room profile |

## Install

```sh
./install.sh game-dev
```

This creates `~/.claude-gamedev`, links the profile's content into it, writes a
shim at `~/.local/bin/claude-gd`, and runs `doctor.sh` to show what was
installed. Add `~/.local/bin` to your `PATH` if it is not there already.

Then:

```sh
claude       # your existing setup, unchanged
claude-gd    # the game-development profile
```

Options: `--mode copy` for a frozen snapshot instead of symlinks, `--target DIR`
for a different config root, `--shim-dir DIR` for a different shim location, and
`--dry-run` to see every action without performing it.

## Check

```sh
./doctor.sh game-dev
```

Reports the resolved config root, content counts, enabled plugins, whether the
shim is on `PATH`, and whether anything leaks back into `~/.claude`.

## Uninstall

```sh
./uninstall.sh game-dev            # remove installed content, keep sessions
./uninstall.sh game-dev --purge    # remove the config root entirely
```

## Memory

Memory written during a session lives in the profile's config root. Pull it back
into version control with:

```sh
./sync-memory.sh game-dev
```

## What is and is not isolated

Isolated per profile: `CLAUDE.md`, `settings.json`, agents, skills, commands,
hooks, plugins, sessions, history, and memory.

Not isolated, by design: a project's own `CLAUDE.md` and `.claude/` directory
load in every profile, because they describe the project rather than the
assistant. System- or enterprise-managed settings also still apply.

## Adding a profile

Create `profiles/<name>/` with `profile.json`, `CLAUDE.md`, and `settings.json`,
plus any `agents/`, `skills/`, `commands/`, `hooks/`, or `memory/` directories.
Content in `shared/` is merged into every profile, with profile entries winning
name collisions. Run `sh tests/run_all.sh` to check the profile contract.

## Tests

```sh
sh tests/run_all.sh
```
```

- [ ] **Step 2: Extend `.gitignore`**

```
.DS_Store
*.bak-*
```

- [ ] **Step 3: Run the full suite one more time**

Run: `sh tests/run_all.sh`
Expected: PASS — all three files report `0 failed`.

- [ ] **Step 4: Install for real and verify isolation**

```bash
./install.sh game-dev
./doctor.sh game-dev
ls ~/.claude/CLAUDE.md   # must still exist, unmodified
```

Expected: doctor reports `config root: /Users/<you>/.claude-gamedev` and
`leakage: none`; `~/.claude/CLAUDE.md` is untouched.

- [ ] **Step 5: Commit**

```bash
git add README.md .gitignore
git commit -m "docs: README and gitignore for omega-ai profiles"
```

---

## Verification

After Task 10, the following must all hold:

- `sh tests/run_all.sh` exits 0.
- `./doctor.sh game-dev` prints `leakage: none`.
- `claude-gd` starts a session whose skills and agents come from this repository.
- `claude` starts an unchanged session with the user's existing setup.
- `./uninstall.sh game-dev --purge` removes `~/.claude-gamedev` and the shim, and
  `~/.claude` is byte-identical to before any of this ran.
