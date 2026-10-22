# S2 Test Harness (exact floors, suite lock, load-flaky tests) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The merge gate's floors are exact counts kept by `--update-floors`. Full runs on one machine take turns on a built-in lock. Every load-flaky test the sweep touches asserts on work or events, not on wall time (#78, #76, #32, #64).
**Architecture:**
- `tests/run_all.sh` gets three new parts. A per-suite floor count, taken from the timing rows. A counts file in the worktree's git dir, guarded by HEAD and a content tree id. A `--update-floors` mode that rewrites only the heredoc table's floor column.
- A mkdir lock in the git common dir, with an atomic owner file, stale takeover under a mutex, and release on EXIT.
- `run_affected.sh` and run_all's own jobs carry `TEST_NO_LOCK=1`.
- The rest are local test rewrites, in the lanes, progress, harness, adopt and Multica suites.
**Tech Stack:** POSIX sh (dash-clean), awk, python3 where already used.
**Spec:** docs/game-dev/specs/2026-10-21-backlog-sweep.md §5 (with §2 G3/G4, §3, §10 #64 notes, §11, §12 F8/F13–F15)
**Story branch:** `issue-64-test-harness` off integration/backlog-2026-10-21

Line numbers are at 1cfca7f. For code that is identical to cfe29ff, the spec cites cfe29ff lines. Before each edit, find the line again with its `grep -n` anchor.

## Global Constraints

- POSIX sh only, clean under dash (`TEST_SH=dash`): no bashisms, no `local`, no `$BASHPID`. Function variables carry a per-function prefix (`_lk_`, `_uf_`, `_ti_` …).
- awk must run under macOS awk and gawk: no `{n}` intervals.
- Opt-in config keys default to today's behaviour (A1). The harness's exact floors and suite lock are the deliberate exceptions.
- After S2 merges, the run_all.sh floors are exact. Every later story runs `sh tests/run_all.sh --update-floors` after it rebases on the integration branch, and commits the table with its tests.
- Hand-run suites: a scratch cwd outside every repo, and an explicit, existing `TMPDIR`. Long suites run as one background run plus its notification, never as stacked poll shells.
- No reinstall. Landing is mode 2: merge into `integration/backlog-2026-10-21`.
- A2: no loosened bound sold as a flake fix. Each flaky test gets a deterministic assertion of the same property. The one exception is `status_per_story`'s hang guard (60 → 180, ruled).
- A3: no file outside this repo changes.
- `tests/run_all.sh` must never contain the word "probes" (`tests/hook_test.sh:775`).
- No phoenix change.

**Run commands.** `WT` is the story worktree. `S` is a scratch dir outside every git work tree, for example `/private/tmp/claude-501/-Users-xinli-GameDev-proj-omega-ai/5a98a755-7ca1-4ed6-b551-b3a3f4153b67/scratchpad/s2`. `mkdir -p "$S/tmp"` once. A suite run is:

```sh
cd "$S" && TMPDIR="$S/tmp" TESTS_ONLY="<names>" sh "$WT/tests/<suite>.sh"
cd "$S" && TMPDIR="$S/tmp" TESTS_ONLY="<names>" TEST_SH=dash dash "$WT/tests/<suite>.sh"   # dash pass
```

- Every `tests/*_test.sh` suite is in the dash set: run_all's `TEST_SH=dash` covers all of them. The Multica suite is not; it runs under sh only.
- The affected-suite lists below come from `sh tests/run_affected.sh --list`'s mapping. `tests/run_all.sh` maps to every suite, so a task that edits it lists the suites that exercise run_all. A full `run_all.sh` runs only in Task 11.

## For other stories (S1, S3, S4, S5, S6): the floors mechanism

The floor of a suite is its **floor count**. That is the sum, over the suite's listed tests, of each test's assertions (`T` row field 7). A `TESTS_FINAL` test counts once, not once per partition. Assertions outside test functions don't count. The count is therefore the same serial or parallel, and for any shard split.

**A run.** Any run_all run that reaches its checks (not `TESTS_ONLY`, not `RUN_ALL_TABLE`/`RUN_ALL_SUITES_DIR`) writes `$(git rev-parse --absolute-git-dir)/run-all-counts.tsv`. That covers a full run, a `TEST_SUITES=…` partial run and `run_affected.sh`. The file holds the last run's suites only.

**Each story's LAST task:**

1. Merge the latest `integration/backlog-2026-10-21` into the story branch.
2. Commit every code and test change. The counts file is keyed to HEAD plus the work tree's content, `tests/run_all.sh` aside.
3. Run the affected suites through run_all:
   ```sh
   cd "$S" && TMPDIR="$S/tmp" TEST_SUITES="<suites>" sh "$WT/tests/run_all.sh"
   ```
   or `sh "$WT/tests/run_affected.sh" --base integration/backlog-2026-10-21`.
   - Red **only** with `<s>: <n> assertions, floor <f> …` or `<s>: no floors row …` lines is expected.
   - Any other red is a real failure: fix it first.
4. `sh "$WT/tests/run_all.sh" --update-floors`. It runs no suites, prints `<suite>: <old> → <new>` per change and exits 0.
   - It exits 2 for no counts file, `counts are from another tree — re-run the suites`, or a red suite.
5. `git add tests/run_all.sh && git commit -m "test(run_all): floors for <story>"`.

**Rules:**
- Never hand-edit a floor.
- On a floors-table merge conflict, take the integration side, then repeat steps 3–5. A hand-merge of counts is never correct.
- A new suite gets its row from `--update-floors` (shards 1). A deleted suite's row is deleted by hand: run_all exits 2 on `table names a missing suite`.
- **The lock.** `sh tests/run_all.sh` takes `<git common dir>/heavy-suite.lock` itself, for full runs only. Never `mkdir` it by hand.
  - A session that still holds a hand-made lock runs `TEST_NO_LOCK=1 sh tests/run_all.sh`.
  - Partial runs (`TEST_SUITES`), `TESTS_ONLY` runs (the lock keys on `TEST_SUITES` only) and `run_affected.sh` never take it.

## Review Focus

1. **Lock owners that can't be checked, or that race.** These cases are never taken over:
   - a lock with no owner file, a legacy hand file, another host's pid, or another user's live pid (`ps`, not `kill -0`, which gives EPERM).
   Two waiters that judged the same owner stale must not both take it. Tests: T2 `test_run_all_lock_other_host_waits`, `test_run_all_lock_ownerless_waits`, `test_run_all_lock_legacy_owner_waits` and `test_run_all_lock_takeover_respects_mutex`.
2. **A stale counts file that looks fresh.** `git status --porcelain` shows the same thing after a second edit to a modified file, so the guard is a content tree id. Test: T1 `test_run_all_update_floors_refuses_stale_tree`. Its cases:
   - a tracked edit;
   - a second edit of an already-modified file;
   - a new untracked file;
   - an edit to `run_all.sh` alone, which is still accepted.
3. **Mode-dependent counts.** A final test runs in every partition, and a top-level assertion runs once per partition. Test: T1 `test_run_all_floor_count_mode_independent`, which checks that serial and parallel counts files are equal for a sharded fixture with a final test and a top-level assertion.
4. **Vacuous lock tests.** A parent full run exports `TEST_NO_LOCK=1`, so a child test that only checks "it ran" passes without the lock. Also, a fixture run must never touch the real repo's counts file or lock. Tests:
   - each T2 lock test sets `TEST_NO_LOCK=` and asserts a positive effect (the waiting line, the owner file);
   - T2 `test_run_affected_sets_no_lock` runs with `unset TEST_NO_LOCK`;
   - T1 `test_run_all_counts_file_written` checks its `RUN_ALL_TABLE` case: no file.
5. **A release in a subshell, or a heredoc that blinds the scan.**
   - `lk_release` keys on `pid=$$`, and `$$` is the same in a subshell, so no `$(…)` or job may release the lock early. Test: T2 `test_run_all_lock_owner_format`: the owner exists in a parallel job and in an exclusive job, and is gone after the run.
   - An unterminated `<<X` in the scan (from a quoted string) would silently skip the rest of the file. Test: T3 `test_exclusive_scan_heredoc_brace`: it emits a loud `H` row, and no real suite yields one.

## Dependency waves

- W1 (parallel): T1; T3; T4; T6; T9; T10; and the T-chain T5 → T7 → T8 (one file, so serial).
- W2: T2 (after T1: same files).
- W3: the final whole-branch review, then T11 (the controller's seed gate).

---

### Task 1: Exact floors, counts file, `--update-floors` — Risky

**Files:**
- Modify `tests/run_all.sh`:
  - header :1-23;
  - :28 (unset line);
  - table comment :40-41;
  - after `table()` :82 (dispatch and `update_floors`);
  - :113-127 (NOROW floors and note; counts setup before :116);
  - `checks` :260-283;
  - :326-331 (write counts).
- Modify `tests/run_all_test.sh`:
  - `fx` :16-29 (it writes its table row);
  - helpers after :58;
  - `test_run_all_below_floor_is_red` :98-103 (renamed `…_floor_exact_below`);
  - `test_run_all_test_helpers_hermetic` :315-323 (new message);
  - the ex/lx fixture tests :127-156 and :289-313 (table rows);
  - `run_tests` :382-393.
- Modify `tests/harness_test.sh:491-492`: widen `sed -n '1,30p'` to `'1,45p'` and add `--update-floors` to the run_all `_need` list.
- Modify `README.md:416-422` (red-if sentence) and `:446-447` (floors bullet).

**Interfaces:**
- Consumes: `T` rows `T suite part idx name secs asserts failed` (assert.sh:245-246); `L` rows (assert.sh:233); `summary.tsv` col 7 `green|red: …` (run_all.sh:199).
- Produces:
  - `sh tests/run_all.sh --update-floors`. Exit 0 on a change or none; 2 on usage, no file, another tree, red, or `RUN_ALL_TABLE` set. Any other argument exits 2 with `usage: sh tests/run_all.sh [--update-floors]`.
  - `tree_id`: a git tree sha, or `-`.
  - `counts_path`: `<absolute git dir>/run-all-counts.tsv`.
  - `$LOGDIR/counts.body`: `suite\tcount\tok|red`.
  - The counts file v1, below.
  - Check messages:
    - `<s>: <n> assertions, floor <f> (floors are exact — run sh tests/run_all.sh --update-floors after a deliberate change)`;
    - `<s>: no floors row — run --update-floors`, in full runs only.
    - The partial-run note becomes `run_all: <s> has no table row: one job, no floor check`.
  - Test helpers: `trow SUITE SHARDS FLOOR`, `ufrepo NAME` (sets `UR`), `ur_ra NAME [VAR=val…]`.

Counts file (written atomically: `$COUNTS.$$` then `mv`; body sorted):

```
# run-all-counts v1 head=<HEAD sha or -> tree=<tree_id> sh=<TEST_SH>
<suite>\t<floor count>\t<ok|red>
```

`red` means a job of the suite was not green, or a check other than the floor fired (no run_tests row, differing listed counts, a test that never ran or ran N times). A missing row and a floor mismatch are floor-class: the suite stays `ok`, so `--update-floors` can fix exactly those.

- [ ] **Step 1: Failing tests** in `tests/run_all_test.sh`.
  - Helpers:
    ```sh
    trow() { printf '%-29s%-8s%s\n' "$1" "$2" "$3"; }          # the heredoc's column layout
    # fx: after writing the suite, replace its own row: grep -v "^$1_test " table; trow "$1_test" 1 "$2" >> table
    # ufrepo NAME — $UR: a git repo (main, one commit) whose tests/ holds $SD's suites and the real
    # run_all.sh with its heredoc body replaced by the header comment plus $TMP/table.
    ufrepo() {
      UR="$TMP/ur-$1"; rm -rf "$UR"; mkdir -p "$UR/tests"; cp "$SD"/*_test.sh "$UR/tests/"
      awk -v t="$TMP/table" '
        /^table\(\) \{/ { intab = 1 }
        intab && !inh && /^  cat <<\047EOF\047$/ { print; print "# suite                      shards  floor"
          while ((getline l < t) > 0) print l; inh = 1; next }
        inh && /^EOF$/ { inh = 0; intab = 0 }
        !inh { print }' "$REPO_ROOT/tests/run_all.sh" > "$UR/tests/run_all.sh"
      ( cd "$UR" && git init -q -b main && git config user.email t@t && git config user.name t \
          && git add -A && git commit -qm init ) >/dev/null 2>&1
    }
    # ur_ra NAME [VAR=val …] — $UR's run_all (no RUN_ALL_TABLE/SUITES_DIR): output $TMP/NAME.out, RC.
    ur_ra() { _n="$1"; shift; RC=0
      env $HERMETIC TEST_LOG_DIR="$TMP/log-$_n" TEST_JOBS=3 "$@" ${TEST_SH:-sh} "$UR/tests/run_all.sh" \
        > "$TMP/$_n.out" 2>&1 || RC=$?; }
    ucf() { printf '%s/run-all-counts.tsv' "$(git -C "$UR" rev-parse --absolute-git-dir)"; }
    ```
  - Tests (new, or renamed where shown):
    ```sh
    test_run_all_floor_exact_below()      # fx bf 2; table "bf_test 1 5": RC 1, line "bf_test: 2 assertions, floor 5 (floors are exact"
    test_run_all_floor_exact_above()      # fx ba 3; table "ba_test 1 1": RC 1, line "ba_test: 3 assertions, floor 1 (floors are exact"
    test_run_all_norow_red_full() {       # fx nr 1 with its row deleted from the table
      ra nr; assert_eq 1 "$RC" "a suite with no row is red in a full run"
      assert_eq 1 "$(cnt "$TMP/nr.out" "nr_test: no floors row — run --update-floors")" "and says so"
      ra nrp TEST_SUITES=nr; assert_eq 0 "$RC" "a partial run: a note, not red"
      assert_eq 1 "$(cnt "$TMP/nrp.out" "nr_test has no table row: one job, no floor check")" "the note"; }
    test_run_all_counts_file_written() {  # fx ca 2; fx cb 1; ufrepo cw
      ur_ra cw; assert_eq 0 "$RC" "green"
      assert_eq 1 "$(sed -n 1p "$(ucf)" | grep -c "^# run-all-counts v1 head=$(git -C "$UR" rev-parse HEAD) tree=[0-9a-f]\{40\} sh=${TEST_SH:-sh}$")" "the header"
      assert_eq "ca_test	2	ok cb_test	1	ok" "$(sed 1d "$(ucf)" | tr '\n' ' ' | sed 's/ $//')" "one sorted row per suite"
      ur_ra cwp TEST_SUITES=cb; assert_eq "cb_test	1	ok" "$(sed 1d "$(ucf)")" "a partial run writes only its suites"
      cp "$(ucf)" "$TMP/cw.keep"; ur_ra cwo TESTS_ONLY=t1
      assert_eq "" "$(cmp "$TMP/cw.keep" "$(ucf)" 2>&1)" "a TESTS_ONLY run leaves the file alone"
      rm -f "$(ucf)"; ur_ra cwt RUN_ALL_TABLE="$TMP/table"; assert_missing "$(ucf)" "a RUN_ALL_TABLE run writes none"; }
    test_run_all_floor_count_mode_independent()   # a hand-written fixture "mi" with 2 shards, a final
        # test (L field 5 = 3) and one top-level assertion; T rows only for its partition's tests (the
        # final in every partition). Table "mi_test 2 <listed-count>". Serial run (TEST_JOBS=1) then
        # parallel (TEST_JOBS=3): both RC 0, and the two counts files' bodies are equal.
    test_run_all_update_floors_rewrites() {  # fx ua 2; fx ub 3; fx uc 1; table: trow ua_test 1 5; trow ub_test 1 3 (uc: no row)
      ufrepo uf; ur_ra uf1; assert_eq 1 "$RC" "floors red only"
      _rc=0; ( cd "$S0" && sh "$UR/tests/run_all.sh" --update-floors ) > "$TMP/uf.out" 2>&1 || _rc=$?
      assert_eq 0 "$_rc" "--update-floors exits 0"
      assert_eq "ua_test: 5 → 2|uc_test: none → 1" "$(tr '\n' '|' < "$TMP/uf.out" | sed 's/|$//')" "one line per change"
      assert_eq "-$(trow ua_test 1 5)|+$(trow ua_test 1 2)|+$(trow uc_test 1 1)" \
        "$(git -C "$UR" diff -U0 tests/run_all.sh | grep '^[-+][^-+]' | tr '\n' '|' | sed 's/|$//')" "only floor lines change; the new suite gets a row"
      ur_ra uf2; assert_eq 0 "$RC" "the next full run is green"
      ( sh "$UR/tests/run_all.sh" --update-floors ) > "$TMP/uf2.out" 2>&1
      assert_contains "$TMP/uf2.out" "floors already match" "a second update is a no-op"; }
    test_run_all_update_floors_refuses_stale_tree()  # after a run, each of: echo x >> tracked suite;
        # (run, then) a second append to the same modified file; an untracked tests/new.txt → exit 2 and
        # "counts are from another tree — re-run the suites", table unchanged (git diff empty).
        # An edit to tests/run_all.sh alone (a comment line) → exit 0.
    test_run_all_update_floors_refuses_red_suite()   # fx ur 1 'exit 1' in ufrepo; run; update → exit 2,
        # output names ur_test, git diff empty
    test_run_all_update_floors_refuses_no_file()     # fresh ufrepo, no run → exit 2 "no counts file";
        # RUN_ALL_TABLE=x → exit 2; an extra argument "--nope" → exit 2 "usage:"
    ```
    `S0` is the test's own start dir (`__rt_cwd0`'s value, or `$TMP`). Update the existing tests:
    - `test_run_all_test_helpers_hermetic` now expects `he_test: 1 assertions, floor 5 (floors are exact`.
    - Write table rows for the hand-made suites: `ex1_test`/`ex2_test` 2 each, `lx_test` 1. The `nl_test` fixture stays red.
- [ ] **Step 2: Run, expect FAIL.**
  ```sh
  TESTS_ONLY="test_run_all_floor_exact_below test_run_all_floor_exact_above test_run_all_norow_red_full test_run_all_counts_file_written test_run_all_floor_count_mode_independent test_run_all_update_floors_rewrites test_run_all_update_floors_refuses_stale_tree test_run_all_update_floors_refuses_red_suite test_run_all_update_floors_refuses_no_file"
  ```
  This uses the run commands above against `run_all_test.sh`.
- [ ] **Step 3: Implement.**
  - **Line 28.** Also `unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR`: run_all's own git calls use `git -C "$SELF_DIR"`.
  - **Header.** Describe `--update-floors` and the floor count. The red-if sentence becomes "or its floor count differs from its table floor (exact), or, in a full run, it has no table row".
  - **The table comment (:40-41).** "floor = the suite's exact floor count; rewrite with --update-floors".
  - **NOROW (:126-127).** `floors.tsv` gets `-` for a NOROW suite. The note at :127 prints in partial runs only, with the new text.
  - **Counts setup, just before :116.** When `RUN_ALL_TABLE`, `RUN_ALL_SUITES_DIR` and `TESTS_ONLY` are all empty and `counts_path` succeeds:
    - `RUN_TREE="$(tree_id)"`, and `RUN_HEAD`: `git rev-parse -q --verify HEAD`, else `-`.
    - A `-` tree means no counts file, and one note: `run_all: cannot read the work tree — no counts file`.
  - **After `checks` (:330).** `[ -z "$COUNTS" ] || write_counts`.
  - **Hard parts, in full:**
    ```sh
    counts_path() { _cp_g="$(git -C "$SELF_DIR" rev-parse --absolute-git-dir 2>/dev/null)" && [ -n "$_cp_g" ] \
      && printf '%s/run-all-counts.tsv\n' "$_cp_g"; }
    # tree_id — the work tree's content now (tracked, modified, untracked; ignored files aside),
    # tests/run_all.sh left out, as a git tree sha from a scratch index (never the real one). - on failure.
    tree_id() {
      _ti_top="$(git -C "$SELF_DIR" rev-parse --show-toplevel 2>/dev/null)" || { echo -; return 0; }
      _ti_self="${SELF_DIR#"$_ti_top"/}/$(basename "$0")"
      _ti_d="$(mktemp -d "${TMPDIR:-/tmp}/run_all.idx.XXXXXX" 2>/dev/null)" || { echo -; return 0; }
      _ti_t="$( GIT_INDEX_FILE="$_ti_d/index"; export GIT_INDEX_FILE
        git -C "$_ti_top" add -A -- . >/dev/null 2>&1 \
          && git -C "$_ti_top" rm -q --cached --ignore-unmatch -- "$_ti_self" >/dev/null 2>&1 \
          && git -C "$_ti_top" write-tree 2>/dev/null )" || _ti_t=""
      rm -rf "$_ti_d"; printf '%s\n' "${_ti_t:--}"
    }
    write_counts() {
      { printf '# run-all-counts v1 head=%s tree=%s sh=%s\n' "$RUN_HEAD" "$RUN_TREE" "$TEST_SH"
        sort "$LOGDIR/counts.body"; } > "$COUNTS.$$" && mv "$COUNTS.$$" "$COUNTS" || rm -f "$COUNTS.$$"
    }
    ```
    `checks` keeps every current line and adds the floor count, the exact compare and `counts.body`:
    ```sh
    checks() {
      : > "$LOGDIR/counts.body"
      awk -F'\t' -v partial="$PARTIAL" -v cf="$LOGDIR/counts.body" '
        FILENAME ~ /floors\.tsv$/ { floor[$1] = $2; next }
        FILENAME ~ /summary\.tsv$/ { ran[$1] = 1; if ($7 != "green") bad[$1] = 1; next }
        $1 == "L" { if (($2 in nl) && listed[$2] != $4) diff[$2] = 1
                    nl[$2]++; listed[$2] = $4; fin[$2] = $5; next }
        $1 == "T" { k = $2 SUBSEP $4; cnt[k]++; name[k] = $5
                    if (!(k in ta) || $7 + 0 > ta[k]) ta[k] = $7 + 0; next }
        END {
          for (s in ran) {
            n = 0
            if (!(s in nl)) { print s ": no run_tests row"; bad[s] = 1 }
            else {
              if (s in diff) { print s ": listed counts differ across partitions"; bad[s] = 1 }
              split("", isf)
              if (fin[s] != "-") { m = split(fin[s], fa, ","); for (i = 1; i <= m; i++) isf[fa[i]] = 1 }
              for (i = 1; i <= listed[s]; i++) {
                k = s SUBSEP i; want = (i in isf) ? nl[s] : 1; got = cnt[k] + 0; n += ta[k] + 0
                if (got == 0) { print s ": test " i " never ran"; bad[s] = 1 }
                else if (got != want) { print s ": test " i " (" name[k] ") ran " got " times"; bad[s] = 1 }
              }
            }
            if (floor[s] == "-") { if (partial == 0) print s ": no floors row — run --update-floors" }
            else if (n != floor[s] + 0) print s ": " n " assertions, floor " floor[s] " (floors are exact — run sh tests/run_all.sh --update-floors after a deliberate change)"
            printf "%s\t%d\t%s\n", s, n, ((s in bad) ? "red" : "ok") > cf
          }
        }' "$LOGDIR/floors.tsv" "$LOGDIR/summary.tsv" "$LOGDIR/timing.tsv" | sort
    }
    ```
    `update_floors` runs before the `TEST_JOBS`/perl checks, from `case "${1:-}"` right after `table()`:
    ```sh
    update_floors() {
      [ -z "${RUN_ALL_TABLE:-}" ] || die2 "--update-floors rewrites the built-in table; unset RUN_ALL_TABLE"
      _uf_c="$(counts_path)" || die2 "--update-floors needs a git work tree"
      [ -f "$_uf_c" ] || die2 "no counts file ($_uf_c) — run the suites first: sh tests/run_all.sh, or TEST_SUITES=…"
      _uf_hd="$(sed -n '1s/^# run-all-counts v1 head=\([^ ]*\) tree=\([^ ]*\) .*$/\1 \2/p' "$_uf_c")"
      [ -n "$_uf_hd" ] || die2 "$_uf_c is not a run-all-counts v1 file"
      _uf_t="$(tree_id)"; [ "$_uf_t" != - ] || die2 "cannot read the work tree"
      _uf_h="$(git -C "$SELF_DIR" rev-parse -q --verify HEAD 2>/dev/null)" || _uf_h=-
      [ "$_uf_hd" = "$_uf_h $_uf_t" ] || die2 "counts are from another tree — re-run the suites"
      _uf_red="$(awk -F'\t' 'NR > 1 && $3 != "ok" { printf " %s", $1 }' "$_uf_c")"
      [ -z "$_uf_red" ] || die2 "red in the last run:$_uf_red — fix and re-run before --update-floors"
      _uf_f="$SELF_DIR/$(basename "$0")"; _uf_n="$_uf_f.new.$$"; _uf_x="$_uf_f.chg.$$"
      # cp -p keeps the mode; mv swaps the inode, so the running shell keeps reading the old file
      cp -p "$_uf_f" "$_uf_n" && : > "$_uf_x" || die2 "cannot write next to $_uf_f"
      awk -v chg="$_uf_x" '
        NR == FNR { if (FNR > 1) { want[$1] = $2; ord[++n] = $1 }; next }
        /^table\(\) \{/ { intab = 1 }
        intab && !inh && /^  cat <<\047EOF\047$/ { inh = 1; print; next }
        inh && /^EOF$/ {
          for (i = 1; i <= n; i++) if (!(ord[i] in seen)) {
            printf "%-29s%-8s%s\n", ord[i], 1, want[ord[i]]; print ord[i] ": none → " want[ord[i]] > chg }
          inh = 0; intab = 0; print; next }
        inh && $0 !~ /^[ \t]*(#|$)/ {
          seen[$1] = 1
          if (($1 in want) && $3 != want[$1]) {
            l = $0; sub(/[0-9]+[ \t]*$/, want[$1], l); print $1 ": " $3 " → " want[$1] > chg; print l; next } }
        { print }' "$_uf_c" "$_uf_f" > "$_uf_n" || { rm -f "$_uf_n" "$_uf_x"; die2 "cannot rewrite the table"; }
      if [ ! -s "$_uf_x" ]; then rm -f "$_uf_n" "$_uf_x"; echo "run_all: floors already match the last run"; exit 0; fi
      cat "$_uf_x"; rm -f "$_uf_x"
      mv "$_uf_n" "$_uf_f" || die2 "cannot replace $_uf_f"
      exit 0
    }
    ```
  - **README.** The red-if sentence matches the header. The floors bullet becomes: "Floors in `tests/run_all.sh` are exact floor counts. After a deliberate change, run the affected suites through run_all, then `sh tests/run_all.sh --update-floors`, and commit the table."
- [ ] **Step 4: Run, expect PASS.** Run Step 2's names, then the whole `run_all_test.sh` (the fixture rows fix the existing tests), under sh and dash. Run `harness_test.sh` with `TESTS_ONLY="test_knobs_named_in_headers test_exclusive_scan_candidates_ruled"`. Then `hook_test.sh` with `TESTS_ONLY` set to the test holding :775 (`grep -n probes tests/hook_test.sh` to name it).
- [ ] **Step 5: Commit.** `test(run_all): exact floors, counts file and --update-floors (#64)`, ending with the two attribution lines.

### Task 2: The built-in heavy-suite lock — Risky

**Files:**
- Modify `tests/run_all.sh`:
  - header (new knobs);
  - the lock block, between the ORDER/NOROW lines (:113-114) and Task 1's counts setup / LOGDIR (:116).
- Modify `tests/run_affected.sh:174-180`: `TEST_NO_LOCK=1; export TEST_NO_LOCK` once, before the `if`, so both `exec`s carry it.
- Modify `tests/run_all_test.sh`:
  - `HERMETIC` :43 gets `TEST_NO_LOCK=1`;
  - lock helpers;
  - new tests and rulings :374-381;
  - `run_tests`.
- Modify `tests/run_affected_test.sh`: add a new test, and add it to `run_tests` :168-174.
- Modify `tests/harness_test.sh:491-492`: `_need` adds `TEST_NO_LOCK TEST_LOCK_LABEL RUN_ALL_LOCK_POLL RUN_ALL_LOCK_NOTE`.
- Modify `README.md:429`, replacing "Two gates on one machine slow each other's exclusive phase; lower `TEST_JOBS`."

**Interfaces:**
- Produces:
  - Env:
    - `TEST_NO_LOCK`: non-empty skips the lock. run_all exports `TEST_NO_LOCK=1` to every job, whether it holds the lock or not.
    - `TEST_LOCK_LABEL`.
    - Test-only `RUN_ALL_LOCK_POLL` (seconds, decimal ok, default 5) and `RUN_ALL_LOCK_NOTE` (seconds, default 300).
  - Path `<git common dir>/heavy-suite.lock/`, holding `owner` (`label= pid= started= host= cwd=`), plus the mutex dir `<git common dir>/heavy-suite.lock.takeover/`.
  - Lines:
    - `run_all: waiting for the heavy-suite lock — held by <label> (pid <p>, since <started>, host <h>)`;
    - `… — held by a lock with no owner file (rmdir <path> once its holder is done)`;
    - for a legacy file, `… — held by <owner:> (since <since:>, what: <what:>)`;
    - `run_all: still waiting (<n> min)`;
    - `run_all: took over a stale heavy-suite lock (pid <p> is not running run_all.sh)`;
    - `run_all: not in a git work tree — running without the heavy-suite lock`.
  - Functions: `lk_get KEY TEXT`, `lk_stale TEXT`, `lk_holder`, `lk_takeover TEXT`, `lk_acquire`, `lk_release`.

- [ ] **Step 1: Failing tests.** The fixtures use the `ufrepo` repos, never the real repo. `LK="$UR/.git/heavy-suite.lock"`. `HOSTN="$(hostname -s 2>/dev/null || uname -n)"`.
  - Helpers:
    ```sh
    # holder — a live process whose argv names run_all.sh (a symlink to sleep): pid in $_hp.
    holder() { mkdir -p "$TMP/holder"; ln -sf "$(command -v sleep)" "$TMP/holder/run_all.sh"
      "$TMP/holder/run_all.sh" 300 & _hp=$!; }
    # ur_bg NAME [VAR=val …] — ur_ra in a session of its own, in the background: pid in $_ra.
    # wait_out FILE TEXT [TICKS] — event wait (0.1 s ticks, default 300) for TEXT in FILE.
    ```
  - Tests. Each passes `TEST_NO_LOCK= RUN_ALL_LOCK_POLL=0.2` unless it says otherwise.
    ```sh
    test_run_all_lock_waits_and_names_holder() {   # fx wl 1 'touch "'"$TMP"'/wl.ran"'; ufrepo wl; holder
      mkdir -p "$LK"; printf 'label=other\npid=%s\nstarted=2026-10-21T01:00:00Z\nhost=%s\ncwd=/x\n' "$_hp" "$HOSTN" > "$LK/owner"
      ur_bg wl TEST_NO_LOCK= RUN_ALL_LOCK_POLL=0.2
      wait_out "$TMP/wl.out" "waiting for the heavy-suite lock — held by other (pid $_hp, since 2026-10-21T01:00:00Z, host $HOSTN)"
      assert_contains "$TMP/wl.out" "held by other (pid $_hp" "the holder line names the live owner"
      assert_missing "$TMP/wl.ran" "no suite starts while the lock is held"
      rm -f "$LK/owner"; rmdir "$LK"          # the holder releases
      _x=0; wait "$_ra" || _x=$?
      assert_eq 0 "$_x" "the run starts after the release and is green"; assert_file "$TMP/wl.ran" "the suite ran"
      assert_missing "$LK" "the run released its own lock"; kill "$_hp" 2>/dev/null; }
    test_run_all_lock_takes_over_dead_pid()   # owner pid of a reaped `sh -c 'exit 0' &` on $HOSTN, then
        # a live plain `sleep 300` pid (argv lacks run_all.sh): each run RC 0, "took over a stale heavy-suite
        # lock (pid <p>", no "waiting for" line, $LK gone after
    test_run_all_lock_other_host_waits()      # dead pid but host=elsewhere: waiting line with "host elsewhere";
        # after wait_out plus 5 more polls the owner file is byte-equal; test removes it → RC 0
    test_run_all_lock_ownerless_waits()       # mkdir $LK only, RUN_ALL_LOCK_NOTE=1: "held by a lock with no owner
        # file (rmdir $LK once its holder is done)", then "still waiting (0 min)"; rmdir → RC 0
    test_run_all_lock_legacy_owner_waits()    # owner = "owner: #66 t (omega-ai)\nsince: 2026-10-09T01:00:00Z\nwhat:
        # overnight_lanes_test": "held by #66 t (omega-ai) (since 2026-10-09T01:00:00Z, what: overnight_lanes_test)";
        # never taken over (file byte-equal after 5 polls); removal → RC 0
    test_run_all_lock_takeover_respects_mutex()  # stale owner (dead pid) plus a pre-made $LK.takeover: the run
        # waits (waiting line, owner unchanged) until 12 polls break the mutex, then takes over: RC 0,
        # exactly one "took over" line, $LK and $LK.takeover gone
    test_run_all_lock_released_on_signal()    # fx sg 1 'touch "'"$TMP"'/sg.ready"; '"$HANG"; ufrepo; ur_bg; wait ready;
        # owner pid == $_ra; kill -TERM "$_ra"; exit 143 within the ceiling; $LK gone
    test_run_all_lock_released_on_die()       # TEST_LOG_DIR=/dev/null/x: RC 2, $LK gone
    test_run_all_lock_owner_format()          # a parallel job and an exclusive job each copy $LK/owner aside:
        # both exist; label=${USER:-$(id -un)}@ur-of, pid numeric, started=YYYY-MM-DDTHH:MM:SSZ, host=$HOSTN,
        # cwd= the run's cwd; TEST_LOCK_LABEL=x → label=x; $LK gone after each run
    test_run_all_lock_skipped_partial_and_no_lock()  # holder lock live; TEST_SUITES=<s> run and a TEST_NO_LOCK=1
        # full run: RC 0, no "waiting" line, owner byte-equal after
    test_run_all_lock_skipped_outside_git()   # run_all.sh plus a fixture copied to $TMP/nogit/tests, GIT_CEILING_DIRECTORIES=$TMP:
        # RC 0, exactly one "not in a git work tree — running without the heavy-suite lock"
    test_run_all_jobs_inherit_no_lock()       # fixture writes ${TEST_NO_LOCK:-empty}: a full parallel, a full serial
        # (TEST_JOBS=1) and a partial run, all with TEST_NO_LOCK=: each records "1"
    ```
  - In `tests/run_affected_test.sh`:
    ```sh
    test_run_affected_sets_no_lock() {
      repo s14
      printf '%s\n' 'echo "NOLOCK=${TEST_NO_LOCK-unset} SUITES=${TEST_SUITES-unset}"' > "$R/tests/run_all.sh"
      ( cd "$R" && git add -A && git commit -qm fake && git push -q origin main && git fetch -q origin ) >/dev/null 2>&1
      echo more >> "$R/tests/b_test.sh"
      ( unset TEST_NO_LOCK; cd "$R" && ${TEST_SH:-sh} tests/run_affected.sh 2>/dev/null ) > "$TMP/o"
      assert_contains "$TMP/o" "NOLOCK=1 SUITES=b_test" "a subset run never takes the lock"
      echo m >> "$R/tests/assert.sh"
      ( unset TEST_NO_LOCK; cd "$R" && ${TEST_SH:-sh} tests/run_affected.sh 2>/dev/null ) > "$TMP/o"
      assert_contains "$TMP/o" "NOLOCK=1 SUITES=unset" "an all-suites run never takes it either"
    }
    ```
  - Rulings. Run `awk -f tests/exclusive_scan.awk tests/run_all_test.sh` and rule every new flag:
    - `test_run_all_lock_released_on_signal` is `in (b)`: TERM must end run_all and release the lock inside a fixed ceiling.
    - Others as flagged.
- [ ] **Step 2: Run, expect FAIL.** The new names in `run_all_test.sh`, plus `test_run_affected_sets_no_lock` in `run_affected_test.sh`.
- [ ] **Step 3: Implement.** Main flow, at the block position:
    ```sh
    LOCK=""; LOCK_HELD=0; LOCK_POLL="${RUN_ALL_LOCK_POLL:-5}"; LOCK_NOTE="${RUN_ALL_LOCK_NOTE:-300}"
    case "$LOCK_POLL" in ''|*[!0-9.]*|.*|*.|*.*.*) die2 "RUN_ALL_LOCK_POLL must be a positive number, got '$LOCK_POLL'" ;; esac
    posint "$LOCK_NOTE" || die2 "RUN_ALL_LOCK_NOTE must be a positive integer, got '$LOCK_NOTE'"
    HOST="$(hostname -s 2>/dev/null)"; [ -n "$HOST" ] || HOST="$(uname -n)"
    if [ "$PARTIAL" = 0 ] && [ -z "${TEST_NO_LOCK:-}" ]; then
      _lk_c="$(git -C "$SELF_DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
      if [ -n "$_lk_c" ] && [ -d "$_lk_c" ]; then
        LOCK="$_lk_c/heavy-suite.lock"
        _lk_top="$(git -C "$SELF_DIR" rev-parse --show-toplevel 2>/dev/null)"
        LOCK_LABEL="${TEST_LOCK_LABEL:-${USER:-$(id -un)}@$(basename "${_lk_top:-$SELF_DIR}")}"
        trap 'lk_release' EXIT      # every exit path: normal, die2, on_signal's exit
        lk_acquire
      else echo "run_all: not in a git work tree — running without the heavy-suite lock"; fi
    fi
    TEST_NO_LOCK=1; export TEST_NO_LOCK
    ```
    Functions, in full:
    ```sh
    lk_get() { printf '%s\n' "$2" | sed -n "s/^$1=//p" | head -n 1; }
    # lk_stale TEXT — an owner that can be checked and is gone: a pid= line, this host, and no process
    # with that pid whose argv names run_all.sh. ps, not kill -0 (EPERM on another user's live pid).
    lk_stale() {
      _ls_p="$(lk_get pid "$1")"; posint "$_ls_p" || return 1
      [ "$(lk_get host "$1")" = "$HOST" ] || return 1
      case "$(ps -o args= -p "$_ls_p" 2>/dev/null)" in *run_all.sh*) return 1 ;; esac
      return 0
    }
    lk_holder() {
      if [ ! -f "$LOCK/owner" ]; then printf 'a lock with no owner file (rmdir %s once its holder is done)' "$LOCK"; return 0; fi
      _lh_t="$(cat "$LOCK/owner" 2>/dev/null)"
      if [ -n "$(lk_get pid "$_lh_t")" ]; then
        printf '%s (pid %s, since %s, host %s)' "$(lk_get label "$_lh_t")" "$(lk_get pid "$_lh_t")" \
          "$(lk_get started "$_lh_t")" "$(lk_get host "$_lh_t")"
      else   # a hand-made owner file (the 10-09 and 10-19 plans): owner:/since:/what:
        printf '%s (since %s, what: %s)' "$(printf '%s\n' "$_lh_t" | sed -n 's/^owner: *//p' | head -n 1)" \
          "$(printf '%s\n' "$_lh_t" | sed -n 's/^since: *//p' | head -n 1)" "$(printf '%s\n' "$_lh_t" | sed -n 's/^what: *//p' | head -n 1)"
      fi
    }
    # lk_takeover TEXT — remove a stale lock whose owner still reads TEXT, under a mutex: a second
    # waiter that judged the same owner stale re-reads it, finds the winner's owner (or none), keeps it.
    lk_takeover() {
      mkdir "$LOCK.takeover" 2>/dev/null || return 1
      _lt_r=1
      if [ "$(cat "$LOCK/owner" 2>/dev/null)" = "$1" ]; then
        rm -f "$LOCK/owner" "$LOCK"/owner.*; rmdir "$LOCK" 2>/dev/null && _lt_r=0
      fi
      rmdir "$LOCK.takeover" 2>/dev/null; return "$_lt_r"
    }
    lk_acquire() {
      _la_said=0; _la_t0=$(date +%s); _la_nt=$_la_t0; _la_tk=0
      while ! mkdir "$LOCK" 2>/dev/null; do
        if [ ! -d "$LOCK" ]; then mkdir "$LOCK" 2>/dev/null && break; [ -d "$LOCK" ] || die2 "cannot create $LOCK"; fi
        _la_txt="$(cat "$LOCK/owner" 2>/dev/null)"
        if lk_stale "$_la_txt"; then
          if lk_takeover "$_la_txt"; then
            echo "run_all: took over a stale heavy-suite lock (pid $(lk_get pid "$_la_txt") is not running run_all.sh)"
            _la_tk=0; continue
          fi
          # a takeover mutex left for 12 polls belongs to a waiter that died inside it
          _la_tk=$((_la_tk + 1)); [ "$_la_tk" -lt 12 ] || { rmdir "$LOCK.takeover" 2>/dev/null; _la_tk=0; }
        fi
        [ "$_la_said" = 1 ] || { echo "run_all: waiting for the heavy-suite lock — held by $(lk_holder)"; _la_said=1; }
        if [ $(( $(date +%s) - _la_nt )) -ge "$LOCK_NOTE" ]; then
          echo "run_all: still waiting ($(( ($(date +%s) - _la_t0) / 60 )) min)"; _la_nt=$(date +%s)
        fi
        sleep "$LOCK_POLL"
      done
      printf 'label=%s\npid=%s\nstarted=%s\nhost=%s\ncwd=%s\n' "$LOCK_LABEL" "$$" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        "$HOST" "$(pwd -P)" > "$LOCK/owner.$$" && mv "$LOCK/owner.$$" "$LOCK/owner" \
        || { rm -f "$LOCK/owner.$$"; rmdir "$LOCK" 2>/dev/null; die2 "cannot write $LOCK/owner"; }
      LOCK_HELD=1
    }
    lk_release() {
      [ "$LOCK_HELD" = 1 ] || return 0; LOCK_HELD=0
      [ "$(lk_get pid "$(cat "$LOCK/owner" 2>/dev/null)")" = "$$" ] || return 0
      rm -f "$LOCK/owner"; rmdir "$LOCK" 2>/dev/null
    }
    ```
    - A signal while waiting kills run_all at once, since its traps are set later (:324), and nothing is held yet.
    - Header knobs: name all four.
    - README :429 becomes: "A full run takes `<git common dir>/heavy-suite.lock` itself. While another full run on this machine holds it, the run waits and prints the holder. Never `mkdir` it by hand. A session that still holds a hand-made lock runs `TEST_NO_LOCK=1 sh tests/run_all.sh`. Partial runs and `run_affected.sh` never take it."
- [ ] **Step 4: Run, expect PASS.**
  - The whole of `run_all_test.sh` and `run_affected_test.sh`, under sh and dash.
  - `harness_test.sh` with `TESTS_ONLY="test_knobs_named_in_headers test_exclusive_scan_candidates_ruled"`.
- [ ] **Step 5: Commit.** `test(run_all): built-in heavy-suite lock; jobs and run_affected carry TEST_NO_LOCK (#64)`.

### Task 3: exclusive_scan skips heredoc bodies (#64 item 1) — Mechanical

**Files:**
- Modify `tests/exclusive_scan.awk:5` (header), `:15` (`FNR == 1`), and add a rule before `:16`. Track openers in the main block (:23-31), and add `END` (:32).
- Modify `tests/harness_test.sh`: add a fixture generator after `gen_scan_fixture2` (:249-262), a new test, and the `run_tests` entry (:504-515).

**Interfaces:** the scan's output is unchanged, plus one new row kind: `suite\t<test> (unterminated heredoc <X>)\tH\t<line>`. The guard at harness_test:470-473 then reports it as "flagged test … has no ruling", so it is loud.

- [ ] **Step 1: Failing test.** Add `gen_scan_fixture3 FILE`, written with `sed 's/^|//'` like :249. Write the `<<-X` body lines with `printf '\t}\n\tX\n'` to get literal tabs.
  - `test_h`: `cat > x <<'EOF'`, then a column-0 `}`, then `EOF`, then `kill -TERM "$p"`, then `}`.
  - `test_i`: `<<-X` with tab-indented `}` and `X`, then `run --seconds 2`.
  - `test_j`: `<<Y` with `}` and `Y`, then `sleep 0.1`. This one is clean.
  - `test_k`: `cat <<'NEVER'`, then `kill -INT "$p"`, then `}`, at EOF with no delimiter.
  ```sh
  test_exclusive_scan_heredoc_brace() {
    gen_scan_fixture3 "$TMP/scan3_test.sh"
    assert_eq "test_h b|test_i d|test_k (unterminated heredoc NEVER) H" \
      "$(awk -f "$REPO_ROOT/tests/exclusive_scan.awk" "$TMP/scan3_test.sh" | awk -F'\t' '{ printf "%s%s %s", s, $2, $3; s = "|" }')" \
      "a column-0 } inside a heredoc does not end the test; <<'X', <<X and <<-X bodies are skipped; an unterminated one is loud"
    assert_eq 0 "$(awk -f "$REPO_ROOT/tests/exclusive_scan.awk" "$REPO_ROOT"/tests/*_test.sh | grep -c 'unterminated heredoc')" \
      "no real suite has an unterminated heredoc"
  }
  ```
- [ ] **Step 2: Run, expect FAIL.** `harness_test.sh`, `TESTS_ONLY=test_exclusive_scan_heredoc_brace`.
- [ ] **Step 3: Implement** (awk, in full):
  ```awk
  function hd_open() { if (hd != "") printf "%s\t%s (unterminated heredoc %s)\tH\t%d\n", suite, hdname, hd, hdl; hd = "" }
  FNR == 1 { flush(); hd_open(); suite = FILENAME; sub(/.*\//, "", suite); sub(/\.sh$/, "", suite) }
  # A heredoc body inside a test is text: skip it up to its delimiter line (<<-: leading tabs stripped).
  hd != "" { t = $0; if (hdt) sub(/^\t+/, "", t); if (t == hd) hd = ""; next }
  ```
  - At the end of the main `{ … }` block, after the flags, add:
    ```awk
    if (match(line, /<<-?[ \t]*["\047]?[A-Za-z_][A-Za-z0-9_]*/)) {
      d = substr(line, RSTART + 2, RLENGTH - 2); hdt = (substr(d, 1, 1) == "-"); if (hdt) d = substr(d, 2)
      gsub(/[ \t"\047]/, "", d); hd = d; hdname = name; hdl = FNR }
    ```
  - `END { flush(); hd_open() }`.
  - Update the header comment to name heredoc bodies and the `H` row.
  - `$((1<<2))` is not an opener, because a digit follows `<<`.
- [ ] **Step 4: Run, expect PASS.**
  - Run `test_exclusive_scan_heredoc_brace`, `test_exclusive_scan_flags_fixture`, `test_exclusive_scan_ignores_comments_and_top_level` and `test_exclusive_scan_candidates_ruled`.
  - Lines after a heredoc that used to end a test early may now raise new flags in real suites. If the last test reports any, add a ruling in that suite for each one.
  - Run under sh and dash.
- [ ] **Step 5: Commit.** `test(harness): exclusive scan skips heredoc bodies (#64 item 1)`.

### Task 4: studio-adopt's temp dir fails closed (#64 item 4) — Mechanical

**Files:** Modify `studios/game-dev/bin/studio-adopt:19`; modify `tests/studio_adopt_test.sh` (new test, and `run_tests` :1084ff).
**Interfaces:** studio-adopt exits 2 with `studio-adopt: cannot create a temp dir under <dir>` on stderr when `mktemp` fails. Everything else is unchanged. `adopt_lib` (studio_adopt_test:701) copies the line, and that is harmless because its TMPDIR exists.

- [ ] **Step 1: Failing test.**
  ```sh
  test_adopt_mktemp_fails_closed() {
    incident_repo mtf; _h0="$(git -C "$W" rev-parse HEAD)"
    _st=0; ( cd "$W" && TMPDIR="$TMP/no-such-dir" sh "$ADOPT" seed S1 ) > "$TMP/mtf.out" 2> "$TMP/mtf.err" || _st=$?
    assert_eq 2 "$_st" "a TMPDIR that does not exist: exit 2"
    assert_contains "$TMP/mtf.err" "studio-adopt: cannot create a temp dir under $TMP/no-such-dir" "names the dir"
    assert_missing "$TMP/no-such-dir" "creates nothing there"
    assert_eq "$_h0" "$(git -C "$W" rev-parse HEAD)" "no commit"
    assert_eq "" "$(git -C "$W" status --porcelain)" "no write in the worktree"
  }
  ```
  Use whichever fixture the seed tests use, if `incident_repo` doesn't fit (`grep -n '^incident_repo()' tests/studio_adopt_test.sh`).
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** the spec's line verbatim: `TMPD="$(mktemp -d "${TMPDIR:-/tmp}/studio-adopt.XXXXXX")" || { echo "studio-adopt: cannot create a temp dir under ${TMPDIR:-/tmp}" >&2; exit 2; }`.
- [ ] **Step 4: Run, expect PASS.** Run the whole `studio_adopt_test.sh` under sh and dash. That is the affected suite; `--list` maps studio-adopt to its closure.
- [ ] **Step 5: Commit.** `fix(adopt): temp dir under TMPDIR, fail closed (#64 item 4)`.

### Task 5: Two load-flaky lanes tests (#78) — Mechanical

**Files:** Modify `tests/overnight_lanes_test.sh`: `test_lanes_left_gate_reaped` :2637-2656 and `test_lanes_status_per_story` :2190-2215 (the wait at :2197).
**Interfaces:**
- Consumes the `gate.times` row `epoch who hold rc wait lane class tag`, which is space-separated (studio-gate:526 via gate-times.sh:12 `"$*"`), at `$P/.studio/gate.times`.
- The retry's tag ends in `-A-T1-retry` (studio-overnight:1348-1349, :1620).

- [ ] **Step 1: Rewrite the test** (it must fail before it passes: point the awk at field 6 first, run it, then fix it to field 5):
  ```sh
  # (in test_lanes_left_gate_reaped: drop _t0/_secs and the -lt 60 assertion)
  _rw="$(awk '$8 ~ /-A-T1-retry$/ && $4 == 0 { print $5 }' "$P/.studio/gate.times" 2>/dev/null)"
  assert_eq 1 "$(printf '%s\n' "$_rw" | grep -c .)" "exactly one green gate row of the retry"
  assert_eq 1 "$([ "${_rw:-x}" -lt 30 ] 2>/dev/null && echo 1 || echo 0)" "the retry's own gate queued below the 30-second bound (wait $_rw)"
  ```
  - Keep the reaped-message, lock-free and no-survivor assertions.
  - The message must not match the scan's `a` pattern (`exclusive_scan.awk:26`): no "under N s", "within N s" or "< N s".
  - In `test_lanes_status_per_story`, change `wait_pid_or_fail "$RPID" 60` to `180` (:2197). It is a hang guard: ruled.
- [ ] **Step 2: Run** with `TESTS_ONLY="test_lanes_left_gate_reaped test_lanes_status_per_story"`, under sh and dash.
  - The test stays in `TESTS_REAL_CLOCK` (:4853-4857). There is no `TESTS_EXCLUSIVE` entry to drop (see Falsified #11).
  - Confirm with `awk -f tests/exclusive_scan.awk tests/overnight_lanes_test.sh | grep left_gate_reaped`: no output.
- [ ] **Step 3: Commit.** `test(lanes): the reaped-gate retry asserts its own gate wait; status hang guard 180 s (#78)`.

### Task 6: `test_progress_scale_with_past_rows` counts spawns (#76) — Mechanical

**Files:** Modify `tests/overnight_progress_test.sh`: the test :167-185, and remove the ruling and `TESTS_EXCLUSIVE` lines :236-237.
**Interfaces:** `st` (P:59) is unchanged. Add a new helper, `mk_spawn_shim CMD…`.

- [ ] **Step 1: Measure at the base.**
  - Run `( cd "$P" && sh -x "$RUNNER" status ) 2>&1 | …` once, on a fixture copied from the test, to list the external commands `status` runs.
  - Write the shim (below), run the new test body against the unchanged runner, and record `N1 - N0`.
  - Then D = measured + 10. Write both into the test's comment, for example `# measured 1cfca7f: N1-N0 = 412; D = 422`.
- [ ] **Step 2: Rewrite the test.**
  ```sh
  # mk_spawn_shim CMD… — $TMP/shim/CMD for each: append one byte to $TMP/spawns, exec the real CMD.
  mk_spawn_shim() { mkdir -p "$TMP/shim"
    for _c in "$@"; do _r="$(command -v "$_c")" || continue
      printf '#!/bin/sh\nprintf x >> "%s/spawns"\nexec "%s" "$@"\n' "$TMP" "$_r" > "$TMP/shim/$_c"; chmod +x "$TMP/shim/$_c"; done; }
  st_spawns() { : > "$TMP/spawns"; ( PATH="$TMP/shim:$PATH"; export PATH; st ); wc -c < "$TMP/spawns" | tr -d ' '; }
  # … same 10 stories and live lock; _n0="$(st_spawns)"; the 30 × 100 rows as today; _n1="$(st_spawns)"
  assert_eq 1 "$([ $(( _n1 - _n0 )) -le <D> ] && echo 1 || echo "0 ($_n0 → $_n1)")" "3000 past rows add at most <D> spawns to status"
  assert_contains "$TMP/st.out" "rough: 2000 past units" "only the newest 20 runs' rows are read"
  ```
  Delete `_t0/_tb/_fast`, P:236 and P:237 (the only exclusive member, so the whole line goes).
- [ ] **Step 3: Check that it fails** on a per-row spawn. Temporarily add `| cat` to one per-row read in `bin/overnight-progress.sh`, run the test, and expect FAIL. Revert.
- [ ] **Step 4: Run, expect PASS.** Run the whole `overnight_progress_test.sh` under sh and dash. Then `harness_test.sh` with `TESTS_ONLY=test_exclusive_scan_candidates_ruled`.
- [ ] **Step 5: Commit.** `test(progress): count spawns, not seconds, for 3000 past rows (#76)`.

### Task 7: The lanes stub waits on an epoch deadline (#64 item 7) — Mechanical

**Files:** Modify `tests/overnight_lanes_test.sh`:
- the stub's header doc :84-88;
- the stub's waits: `waitfor`/`waitexist` :294-299, `bggate` :310 and `waitafter` :366-368 (inside the `<<'STUB'` heredoc :153-378);
- the callers in `test_stub_waitexist_and_run_token` :4696-4708.

**Interfaces:**
- `STUB_WAIT_SECONDS` (default 60) is the ceiling of every stub wait.
- `STUB_WAIT_TICKS` stays as an alias: `(ticks + 9) / 10` seconds, used only when `STUB_WAIT_SECONDS` is unset.
- On timeout, `$CALLS/wait.timeout` behaves as before.

- [ ] **Step 1: Test first.** In `test_stub_waitexist_and_run_token`, change three of the four `STUB_WAIT_TICKS=10` callers to `STUB_WAIT_SECONDS=1`. Keep one on `STUB_WAIT_TICKS=10`, which pins the alias. Run it: the `SECONDS` callers now wait 60 s, so expect FAIL (or a run past 60 s).
- [ ] **Step 2: Implement.**
  - Once, near the top of the stub:
    ```sh
    if [ -n "${STUB_WAIT_SECONDS:-}" ]; then _sws="$STUB_WAIT_SECONDS"
    elif [ -n "${STUB_WAIT_TICKS:-}" ]; then _sws=$(( (STUB_WAIT_TICKS + 9) / 10 )); else _sws=60; fi
    ```
  - Each wait becomes `_wd=$(( $(date +%s) + _sws )); while [ ! -s "$_wf" ] && [ "$(date +%s)" -le "$_wd" ]; do sleep 0.1; done`, with the existing `-e`/`-s` test per action. The bggate pid wait does the same with `-s "$CALLS/bggate.pid"`.
  - Update the header doc (:84-88).
- [ ] **Step 3: Run, expect PASS.** `test_stub_waitexist_and_run_token` and `test_lanes_left_gate_reaped` (bggate), under sh and dash.
- [ ] **Step 4: Commit.** `test(lanes): stub waits on an epoch deadline, STUB_WAIT_SECONDS (#64 item 7)`.

### Task 8: `lf_key` and the fixture edge cases (#64 items 8, 9) — Mechanical

**Files:** Modify `tests/overnight_lanes_test.sh`:
- `lanes_fixture` :555-577 (the key at :568-569);
- a new `lf_key` after `lf_pre_sum` (:579-583);
- `test_fixture_template_failed_build_not_reused` :4766-4796 (the hand key at :4781);
- new tests next to :4727;
- `run_tests` :4939.

**Interfaces:** `lf_key MODE ROW…` prints `<cksum>-<size>`, which is the exact key text after `l-`. It reads the same `LANES_*` vars and `$FAKE` that the key at :568-569 reads.

- [ ] **Step 1: Failing tests.**
  ```sh
  test_lanes_fixture_lf_key_names_template() {   # anti-vacuous: the helper is the key lanes_fixture used
    _lk_save="$LANES_FIXTURE_TEMPLATES"; LANES_FIXTURE_TEMPLATES=1
    LANES_CONFIG='{"lk": 1}'; export LANES_CONFIG; _lk="$(lf_key integration A:-)"
    lanes_fixture lk1 integration A:-; LANES_FIXTURE_TEMPLATES="$_lk_save"
    assert_file "$TMP/tpl/l-$_lk/ok" "lf_key names the template lanes_fixture built"
  }
  test_lanes_fixture_same_name_twice()   # TEMPLATES=1, same name and tuple twice; between calls: a stray file in $P,
      # a commit pushed to origin's run/demo, a new branch x on origin. After the 2nd call: no stray, no $P/<name>,
      # origin has no x, origin/run/demo == the template's run/demo, `git status --porcelain` empty, and one l-* dir for the key
  test_lanes_fixture_bare_origin_fresh() # TEMPLATES=0, same name twice; after the 1st, push branch x to $TMP/<name>.git.
      # After the 2nd: `git -C $TMP/<name>.git for-each-ref` lacks x; P's origin url is $TMP/<name>.git; clean tree
  ```
- [ ] **Step 2: Run, expect FAIL.** The first test fails because there is no `lf_key` yet. The other two may already pass. They pin today's behaviour (`rm -rf` at :562), so record that in the commit message.
- [ ] **Step 3: Implement.**
  ```sh
  # lf_key MODE ROW… — the template key: the whole tuple lf_build reads (date, mode, rows, every LANES_* input,
  # MAIN_PRE's file sums, the stub path).
  lf_key() {
    printf '%s|' "$(date +%Y-%m-%d)" "$@" "${LANES_CONFIG:-}" "${LANES_CELLS:-}" "${LANES_PROGRESS:-}" \
      "${LANES_MAIN_MOVES:-}" "${LANES_TASKS:-}" "${LANES_MAIN_PRE:-}" "$(lf_pre_sum)" "$FAKE" | cksum | tr ' ' -
  }
  ```
  - :568-569 becomes `_lf_t="$TMP/tpl/l-$(lf_key "$_lf_mode" "$@")"`.
  - :4781 sets `LANES_CONFIG="$_fb_cfg"; export LANES_CONFIG` before `_fb_key="$(lf_key integration A:-)"`, so the two lines swap order with :4783-4784.
  - The comment at :4780 goes.
- [ ] **Step 4: Run, expect PASS.**
  - Run the three new tests plus `test_lanes_fixture_copy_equals_build` and `test_fixture_template_failed_build_not_reused`.
  - Then a broad pass of `TESTS_ONLY` over 10 `lanes_fixture` users: the shard 1/8 subset via `TEST_PHASE=parallel TEST_SHARD=1/8`, as one background run.
  - Run under sh and dash.
- [ ] **Step 5: Commit.** `test(lanes): lf_key helper; same-name and bare-origin fixture tests (#64 items 8, 9)`.

### Task 9: Multica install self-test flake (#32) — Mechanical

**Files:** Modify `integrations/multica/tests/install_test.sh:340-354` (`test_install_selftest_sees_the_project_root`); modify `integrations/multica/tests/stub-launchctl:95`.
**Interfaces:** none new. This follows the `inst_env_wait` pattern (:391).

- [ ] **Step 1: Implement.**
  - In the test, set `OMEGA_MULTICA_SELFTEST_WAIT=30; export OMEGA_MULTICA_SELFTEST_WAIT` before the first `inst`, and restore it to `10` after the second.
  - The second `inst`'s assertion becomes `assert_eq 0 "$RC" "a re-run without --project keeps the root and now passes (stderr: $(cat "$TMP/err"))"`.
  - In stub-launchctl:95, change `timeout=20` to `timeout=120`.
  - This is not a red-first change: it is a flake fix. Prove it by the stress run in Step 2.
- [ ] **Step 2: Run.**
  - First run `cd "$S" && TMPDIR="$S/tmp" TESTS_ONLY=test_install_selftest_sees_the_project_root sh "$WT/integrations/multica/tests/install_test.sh"`.
  - Then the gate, `sh "$WT/integrations/multica/tests/run.sh"`.
  - Then the acceptance record: 10 rounds of 4 concurrent copies of `install_test.sh`, as one background script, all green. Paste the tally into the PR body.
- [ ] **Step 3: Commit.** `test(multica): self-test wait independent of wall time; name the failing step (#32)`.

### Task 10: run_affected hub files (#64 item 3) — Mechanical

**Files:** Maybe modify `tests/run_affected.sh:121-131` (the case) and `tests/run_affected_test.sh`. Expected: no change.

- [ ] **Step 1: Check each hub.**
  - `git clone -q "$WT" "$S/ra-clone"`.
  - For each hub `H` in `studios/game-dev/bin/studio-gate`, `studios/game-dev/bin/godot-cmd.awk` and `studios/game-dev/bin/overnight-lanes.sh`:
    1. Append a comment line to `H`.
    2. Run `sh tests/run_affected.sh --base HEAD --list | cut -f1 | sort`.
    3. Compare that against `grep -lF "$(basename H)" tests/*_test.sh | xargs -n1 basename | sed 's/\.sh$//' | sort`.
    4. `git checkout -- H`.
  - Write the three comparisons to `$S/hubs.txt`.
- [ ] **Step 2: Act on the result.**
  - No gap: no code change. Hand the §10 note (the "#64 item 3" text) to the controller, with `hubs.txt`.
  - A gap: add `<hub path>) add_suite <suite> "hub: <hub>"` arms before the closure fallthrough, plus a `test_affected_hub_<name>` asserting the suite is listed. Run `run_affected_test.sh` red then green, and commit `test(affected): explicit mapping for <hub> (#64 item 3)`.

### Task 11: Seed the exact floors — the controller's S2 gate (not an implementer task) — Risky

Run this after Tasks 1–10, their reviews and the final whole-branch review, on the S2 head. No phoenix final gate may be live. The lock is built in now, so don't take it by hand.

- [ ] Run `cd "$S" && TMPDIR="$S/tmp" TEST_LOG_DIR="$S/gate-sh" sh "$WT/tests/run_all.sh" > "$S/gate-sh.log" 2>&1` as one background run plus its notification.
  - Expect red only with `floor` / `no floors row` lines. The floor counts are new: finals count once, and top-level asserts are left out.
  - Any other red is a defect: fix it, then re-run.
- [ ] `sh "$WT/tests/run_all.sh" --update-floors`. Save the counts aside: `cp "$(git -C "$WT" rev-parse --absolute-git-dir)/run-all-counts.tsv" "$S/counts-sh.tsv"`. Commit `test(run_all): exact floors (#64)`.
- [ ] Run `TEST_SH=dash` the same way, into `$S/gate-dash`. It must be green, and `sed 1d` of the two counts files must be equal.
  - If a suite differs, its assertion count is conditional (F13). Make that suite's assertion unconditional, then re-run both shells.
- [ ] `--update-floors` now prints `floors already match the last run`. Keep both logs for the PR.
- [ ] The serial `TEST_JOBS=1` gate is the operator's quiet-window task (#64 item 6, §10), and it does not block the merge.
  - The floor count is the same in serial and parallel mode by construction (Task 1). Only a suite whose own count depends on the mode would differ.

The shard rebalance (#64 item 10) is not S2's work. It is the last commit on the integration branch, made from the sweep's final full gate. Run that gate with `TEST_LOG_DIR` set, so that `timing.tsv` survives a green run (run_all.sh:121-123, :334). A shard change does not change floor counts (Task 1), so it needs no floors update.

## Falsified assumptions (planner falsify clause)

Checked at 1cfca7f (code identical to cfe29ff):

| # | Assumption | Verdict | Evidence / fix |
|---|---|---|---|
| 1 | `checks()` is at run_all.sh:262-280, with `asum < floor` the compare | holds | :262-283; compare :280 |
| 2 | The table heredoc is :44-79 | holds ±2 | `cat <<'EOF'` :44, rows :46-80, `EOF` :81; the only heredoc in the file |
| 3 | The no-row note is :127, with "floor 1" from `row_of` | holds | :100 `row_of` defaults to 1; :126-127 |
| 4 | The log dir is temporary, so the counts must persist elsewhere (F14) | holds | :17-18, :121-123, :334 → counts in the git dir |
| 5 | run_affected execs run_all at :176/:180 (F15) | holds | :174-180 |
| 6 | `TEST_NO_LOCK`/`TEST_LOCK_LABEL` reach suites | holds | assert.sh:4-7, :17 keep `TEST_*` |
| 7 | Counts match serial vs parallel (F13) | **false** | A final runs once per partition (run_all.sh:274-276; assert.sh:216-232). Lanes has `TESTS_FINAL` (T:4851) across 9 partitions, and top-level asserts run per partition. **Fix:** the floor count sums each listed test's max `T` field-7 value (T1) |
| 8 | A cksum of `git status --porcelain` identifies the tree | **false** | porcelain prints status and path only, so a second edit of a modified file is invisible. **Fix:** `tree_id`, the write-tree of a scratch index (T1) |
| 9 | A stale takeover by rm owner, rmdir, mkdir can only lose a race benignly | **false** | B's late `rm owner` deletes A's fresh owner, then B's rmdir and mkdir succeed: two holders. **Fix:** `lk_takeover`'s mutex plus a compare (T2) |
| 10 | `kill -0` tells a dead pid | **partly false** | EPERM on another user's live pid. **Fix:** `ps -o args=` alone (T2) |
| 11 | `left_gate_reaped` is in `TESTS_EXCLUSIVE` at T:4855 | **false** | T:4855 is `TESTS_REAL_CLOCK` (:4853-4857). `TESTS_EXCLUSIVE` (:4842-4850) lacks it, and no ruling names it (the scan misses `-lt 60`: `date +%s` is on another line). **Fix:** no list edit; it stays real-clock (T5) |
| 12 | `gate.times` has wait = field 5 and tag = field 8, space-separated (F8) | holds | studio-gate:526; gate-times.sh:12 joins `"$*"` |
| 13 | The retry's tag ends in `-A-T1-retry`, and `gate.times` is at `$P/.studio` | holds | O:1348-1349, :1620; studio-gate:82 ROOT = state root; T:2824 |
| 14 | The stub waits are at T:295-300, :310, :368, and only T:4696-4708 set `STUB_WAIT_TICKS` | holds | waitfor :294-296, waitexist :297-299, bggate :310, waitafter :366-368; grep |
| 15 | `lf_key` belongs at T:568-569, with the hand key at T:4781 | holds | read |
| 16 | P's test is :167-188, with `rough` at P:189 | holds, shifted | test :167-185, `rough` :184, ruling :236, exclusive :237 (its only member) |
| 17 | #32 is at install_test.sh:340-354, the stub's timeout at :95, `inst_env_wait` at :391 | holds | read; install_test isn't in run_all (`integrations/multica/tests/run.sh`) |
| 18 | studio-adopt:19 is a bare `mktemp -d` | holds | :19-20; `adopt_lib` (test:701) copies it harmlessly |
| 19 | exclusive_scan ends a test at a column-0 `}`, and its `a` pattern includes `< N s` | holds | :19-20, :26 |
| 20 | The knob guard reads only run_all.sh lines 1-30 | holds | harness_test:491 → widen to 45 (T1) |
| 21 | Nothing forbids new words in run_all.sh | **false** | hook_test:775 asserts no "probes" → Global Constraints |
| 22 | Existing run_all_test green tests run without table rows | **false under exact mode** | `reset` empties the table (:39), so a no-row full run is red. **Fix:** `fx` writes its row; the hand fixtures get rows (T1) |
| 23 | `fx` is called once per name | **false** | `test_run_all_reused_log_dir_keeps_timeout` calls `fx rl` twice (:256-262) → `fx` replaces its row (no duplicate-row exit 2) |
| 24 | `--path-format=absolute` is available | holds | git 2.39.3 (needs ≥ 2.31) |
| 25 | `git add -A` in the main checkout doesn't embed `.claude/worktrees/*` | holds | .gitignore:4 |
| 26 | The run_affected hub arms are at :121-131 | holds | case :123-131 |
| 27 | No caller passes arguments to run_all.sh | holds | run_affected execs it bare (:176, :180); grep of tests/studios/lib |

## Manual acceptance

- **Multica stress record.** `install_test.sh` passes 10 rounds of 4 concurrent copies, all green (T9). The tally goes in the PR body.
- **The seed gate** (T11) runs under sh and dash, with `--update-floors` a no-op afterwards. Both logs go in the PR body.
- **Serial `TEST_JOBS=1` gate.** This is the operator's quiet-window task (§10 #64 item 6), and it is not blocking.
- **One real two-session lock check.** In two worktrees of this repo, start a full `sh tests/run_all.sh` in each, a minute apart. The second prints the holder line and starts when the first ends. Do it once, after the merge, in a quiet window. It is optional, because T2's tests cover the logic.
