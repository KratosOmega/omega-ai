# S6 execute: a default-branch run reviews its own commits Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A run made in place on the default branch records the commit it started from (a
`base-commit <sha>` ledger line). It uses that sha as `<merge-base>` in §4a and §5, so the final review,
the verify-prior-fixes list and the production-bug test cover the run's own commits, not an empty range
(#14, G8). The #6 doc errors in the Plan 2 plan are fixed in the same story.
**Architecture:** Skill text only (spec §1). The execute skill's §0 (c) writes the line, and a resume
without it rebuilds it. "The base" defines `<merge-base>` through it, and §4a/§5 use that term. The
review skill's scope uses the same rule. `tests/studio_test.sh` pins the text, and one contract test
pins that no `bin/`/`hooks/` pattern can read the new line by accident.
**Tech Stack:** POSIX sh (dash-clean), awk, python3 where already used.
**Spec:** docs/game-dev/specs/2026-10-21-backlog-sweep.md §9 (plus §10's #6 plan-doc fix)
**Story branch:** `issue-14-default-branch-base` off integration/backlog-2026-10-21

**Base and story.** Umbrella #83, story #14. Branch it off the integration head **after S2 merges**
(spec §11 step 2). It runs in parallel with S3 and S4. Its worktree is
`/Users/xinli/GameDev/proj/omega-ai/.claude/worktrees/issue-14-default-branch-base` (below: `$W`). Line
numbers are as of 1cfca7f. S2 does not touch X, R or `tests/studio_test.sh`, so they should still hold.
Relocate each one with its `grep -n` anchor before you edit.

Paths: `X` = `studios/game-dev/skills/execute/SKILL.md`, `R` = `studios/game-dev/skills/review/SKILL.md`,
`ST` = `tests/studio_test.sh`.

**Run recipe** (every "Run" below). Use a scratch cwd outside every work tree, with an existing TMPDIR:

```sh
S=/private/tmp/claude-501/-Users-xinli-GameDev-proj-omega-ai/5a98a755-7ca1-4ed6-b551-b3a3f4153b67/scratchpad/s6
mkdir -p "$S/tmp" && cd "$S" && export TMPDIR="$S/tmp"
TESTS_ONLY="<names>" sh "$W/tests/studio_test.sh"      # then the same with: dash "$W/tests/studio_test.sh"
```

## Global Constraints

- POSIX sh only, clean under dash (`TEST_SH=dash`): no bashisms, no `local`, no `$BASHPID`.
- No behaviour change without new config (A1). A run that is not in place on the default branch never
  writes or reads `base-commit`. Its `<merge-base>` stays `git merge-base <base> HEAD`, exactly as today.
- Ledger line format: `- <date> base-commit <40 or 64 hex>`. One per run; the last one wins.
- No phoenix change (A3). No reinstall.
- After S2 the floors are exact. Every new test has an **unconditional** assertion count (fixed literal
  lists, no per-hit asserts), so the count is the same under sh and dash (F13).
- Hand-run suites: scratch cwd plus an existing `TMPDIR` (the recipe above). Never the full `run_all`
  except where the floors task says so. One background run per long suite, never stacked pollers.
- **Every asserted literal sits on one line of the skill text.** `assert_contains` is a line grep, so
  don't wrap a pinned phrase across a markdown line break. Also never put bold `**` inside a pinned phrase (around it is fine when the literal excludes it).
- Keep the existing pinned literals in X: `ledger "base` (ST `test_execute_contract`), and
  `` any resume whose feature ledger has no `base `` and `main checkout's current branch`
  (`tests/pointer_skills_execute_test.sh:22-23`). Don't add a third `(see §8, Operator messages)` to §0
  (ST:730 asserts exactly 2).
- Commit messages end with:
  ```
  Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01HHd9n1KiKNE9YBptbSEgPL
  ```

## Review Focus

These are input classes that no behaviour test runs, because the change is skill text. Each one has a
pinning assertion in the task that owns it.

1. **Rewritten history.** The `base-commit` sha is no longer an ancestor of HEAD. The skill must stop
   with the exact message and never fall back silently to `git merge-base <base> HEAD`, which is HEAD on
   the default branch and gives an empty range. Pinned by T2 (the X literals
   `is not an ancestor of HEAD — fix the ledger line or restart` and `never review an empty range`) and
   T3 (the same literal in R).
2. **Lane and new-branch runs.** These have `base origin/<Target>` (X:116-131). They must never get a
   `base-commit` line. Pinned by T1: no `base-commit` before X's `**Isolation.**` paragraph.
3. **A resume left in the feature worktree** (base = the main checkout's branch, X:240-244). It is not in
   place on the default branch, so it must not rebuild a line. Pinned by T1: the in-place condition
   literal `` `git branch --show-current` is the default branch `` appears exactly twice in §0 (record and
   rebuild).
4. **An adopted story resumed in place.** The sync's `T<k+1> in progress` report exists only after
   `studio-adopt sync` runs, which happens after (c) (X:247-251). Fallback 2 must therefore wait for it.
   Pinned by T1: the literal ``after `studio-adopt sync` reports``.
5. **A future loose ledger reader.** For example `grep '^- [0-9-]* base'` would swallow `base-commit`
   lines. Pinned by T4's negative control: a loose fixture pattern is flagged, and a strict `base ` one
   is not.

## Tasks

| # | Task | Kind |
|---|---|---|
| 1 | §0 (c) records `base-commit`; a resume rebuilds it | Mechanical (spec §11: S6 folds into the final review) |
| 2 | "The base" defines `<merge-base>`; §4a and §5 use it | Mechanical |
| 3 | The review skill's scope uses the same rule | Mechanical |
| 4 | Contract: no `bin/`/`hooks/` pattern matches a `base-commit` line | Mechanical |
| 5 | #6: the Plan 2 plan's Task 16 doc errors | Mechanical |
| 6 | Rebase, affected suites, floors | Mechanical |

Per spec §11, S6 gets no per-task Opus review. Its tasks fold into the final whole-branch review. T1 and
T2 are sequential, because both edit X §0. T3, T4 and T5 are independent of them and of each other.

---

### Task 1: §0 (c) records `base-commit`; a resume rebuilds it — Mechanical

**Files:**
- Modify X :233-237 (the new-run base line) and :238-244 (the missing-`base` resume paragraph). Add the
  rebuild paragraph after :244 and before `Operator messages are recorded after this step` (:245).
- Test: ST, new `test_execute_default_branch_records_base_commit` and
  `test_execute_resume_rebuilds_base_commit` after `test_execute_task_brief_rewritten` (:834-845). Add
  both names to `run_tests` (:854-865).

**Interfaces:**
- Consumes: `studio-state ledger` (writes `- <date> <text>`, `bin/studio-state:891`); the
  **Default branch** procedure (X:278-281); the §6 `T<n> complete <a>..<b>` range format (X:559-565);
  `studio-adopt sync`'s `T<k+1> in progress: <first>..<last>` report (X:143, `bin/studio-adopt:490,922`).
- Produces: ledger line `base-commit <sha>`; the skill phrase "in place on the default branch".

- [ ] **Step 1: Write the failing tests** (ST):

```sh
# #14: a run in place on the default branch records the commit it started from.
test_execute_default_branch_records_base_commit() {
  E="$REPO_ROOT/studios/game-dev/skills/execute/SKILL.md"
  for lit in 'In place on the default branch' 'the noted branch is the default branch' \
             'capture `sha=[$](git rev-parse HEAD)` before that commit' \
             'studio-state ledger "base <noted branch>" && studio-state ledger "base-commit [$]sha" && git add .studio/ledger && git commit -m "chore(studio): ledger"' \
             '`- <date> base-commit <40 or 64 hex>`' 'one per run; the last one wins'; do
    assert_contains "$E" "$lit" "execute §0 (c) carries: $lit"
  done
  assert_eq 2 "$(section_count "$E" '^## 0[.] ' '`git branch --show-current` is the default branch')" \
    "the in-place condition gates both the record and the rebuild"
  assert_eq 0 "$(awk '/^\*\*Isolation\.\*\*/ { exit } /base-commit/ { n++ } END { print n + 0 }' "$E")" \
    "the lane and new-branch paths write no base-commit line"
}

test_execute_resume_rebuilds_base_commit() {
  E="$REPO_ROOT/studios/game-dev/skills/execute/SKILL.md"
  for lit in 'a run begun before the line existed' \
             '(`<a>` may be `<first>^1` or a short sha)' \
             'after `studio-adopt sync` reports' \
             'studio-state ledger "base-commit <sha>" && git add .studio/ledger && git commit -m "chore(studio): ledger"'; do
    assert_contains "$E" "$lit" "execute §0 (c) rebuild carries: $lit"
  done
  assert_eq ordered "$(awk -v a='`T<n> complete <a>..<b>` line: `git rev-parse "<a>"`' \
      -v b='in progress: <first>..<last>` line: `git rev-parse "<first>^1"`' -v c='else `git rev-parse HEAD`' '
    index($0, a) && !x { x = NR } index($0, b) && !y { y = NR } index($0, c) && !z { z = NR }
    END { print (x && y && z && x < y && y < z) ? "ordered" : "unordered" }' "$E")" \
    "the three rebuild fallbacks are present, in order"
}
```

- [ ] **Step 2: Run them and expect FAIL.**
  `TESTS_ONLY="test_execute_default_branch_records_base_commit test_execute_resume_rebuilds_base_commit"`
  with the recipe. Expected: FAIL on every new literal. (The `Isolation` count passes already, which is
  correct.)
- [ ] **Step 3: Edit X §0 (c).**
  - After the new-run command line (:236), add a sub-paragraph. It keeps :236 unchanged and holds these
    single-line literals:
    - **In place on the default branch**: the noted branch is the default branch (Feature-checkout
      procedures), and `git branch --show-current` is the default branch (the (b) consent path).
    - In that case, capture `sha=$(git rev-parse HEAD)` before that commit, and write both lines in it:
      `` `studio-state ledger "base <noted branch>" && studio-state ledger "base-commit $sha" && git add .studio/ledger && git commit -m "chore(studio): ledger"` ``.
    - The line reads `` `- <date> base-commit <40 or 64 hex>` ``, one per run; the last one wins.
    - One clause says `<sha>..HEAD` includes this chore commit, which is harmless: §5's list keeps only
      `fix(…)` commits.
  - After the missing-`base` resume paragraph (:238-244), add the rebuild paragraph. It says: in the
    same step, a resume in place on the default branch (its base, the line just written or the last
    `base <branch>` line, is the default branch, and `` `git branch --show-current` is the default branch``)
    whose feature ledger has no `base-commit` line (a run begun before the line existed) rebuilds it,
    first match wins:
    1. the first `` `T<n> complete <a>..<b>` line: `git rev-parse "<a>"` `` (`` (`<a>` may be `<first>^1` or a short sha) ``);
    2. else, for a story with an `adopted` line, the sync's
       `` `T<k+1> in progress: <first>..<last>` line: `git rev-parse "<first>^1"` ``. The sync runs
       after this step, so such a story writes the line ``after `studio-adopt sync` reports``, before
       *Where to start*;
    3. else `` `git rev-parse HEAD` ``.
  - It is written and committed as one line:
    `` `studio-state ledger "base-commit <sha>" && git add .studio/ledger && git commit -m "chore(studio): ledger"` ``.
  - Each numbered fallback is on its own line, so the order check reads its line numbers.
- [ ] **Step 4: Run and expect PASS.** Run the two tests, then the whole ST and
  `tests/pointer_skills_execute_test.sh` (both under sh and dash). Check
  `sh "$W/tests/run_affected.sh" --base integration/backlog-2026-10-21 --list`: it lists `studio_test`
  and `pointer_skills_execute_test` for X. Run whatever else it lists.
- [ ] **Step 5: Commit** `docs(T1): execute records base-commit for a run in place on the default branch (#14)`.

### Task 2: "The base" defines `<merge-base>`; §4a and §5 use it — Mechanical

**Files:**
- Modify X :253-259 ("The base"), :479 (§4a rule 3) and :505 (§5 step 2). §5 step 3 (:515-516)
  already says `<merge-base>`, so it stays.
- Test: ST, new `test_execute_merge_base_uses_base_commit`, plus its `run_tests` name.

**Interfaces:**
- Consumes: T1's `base-commit` line.
- Produces: the defined term `<merge-base>`, which X §4a/§5 and R (T3) reference.

- [ ] **Step 1: Write the failing test** (ST):

```sh
test_execute_merge_base_uses_base_commit() {
  E="$REPO_ROOT/studios/game-dev/skills/execute/SKILL.md"
  for lit in '`<merge-base>` — the start of this run' \
             'the sha of the last `base-commit` line of the feature ledger' \
             'otherwise `git merge-base <base> HEAD`' 'git merge-base --is-ancestor <sha> HEAD' \
             'base-commit <sha> is not an ancestor of HEAD — fix the ledger line or restart' \
             'never review an empty range'; do
    assert_contains "$E" "$lit" "execute defines <merge-base>: $lit"
  done
  for _sec in '^## 4a[.] ' '^## 5[.] ' '^## 7[.] '; do
    assert_eq 0 "$(section_count "$E" "$_sec" 'git merge-base <base> HEAD')" "$_sec uses <merge-base>, not a raw merge-base"
  done
  assert_eq yes "$( [ "$(section_count "$E" '^## 4a[.] ' '`<merge-base>`')" -ge 1 ] \
    && [ "$(section_count "$E" '^## 5[.] ' '`<merge-base>`')" -ge 2 ] && echo yes)" "§4a and §5 name <merge-base>"
}
```

- [ ] **Step 2: Run it and expect FAIL** (the literals; §4a's and §5's raw counts are 1 each today).
- [ ] **Step 3: Edit X.**
  - "The base" (:253-254): "the anchor for `git merge-base <base> HEAD` in §4a, §5 and §7" becomes "the
    anchor for `<merge-base>` (below) in §4a and §5". §7 has no merge-base use (falsified row 3).
  - Add a paragraph after :259:
    - `<merge-base>` — the start of this run's own commits — is the sha of the last `base-commit`
      line of the feature ledger when it has one (a run in place on the default branch, (c)); otherwise
      `git merge-base <base> HEAD`.
    - Before using a `base-commit` sha, run `git merge-base --is-ancestor <sha> HEAD`. On a failure (a
      rewritten history), stop and say: "base-commit <sha> is not an ancestor of HEAD — fix the ledger
      line or restart".
    - Never fall back to `git merge-base <base> HEAD`, which is HEAD itself on the default branch, and
      never review an empty range.
  - §4a rule 3 (:479): "at `git merge-base <base> HEAD`" becomes "at `<merge-base>` (§0, The base)".
  - §5 step 2 (:505): "With `<merge-base>` = `git merge-base <base> HEAD`, run" becomes "With
    `<merge-base>` as §0's **The base** defines it, run".
  - Leave X:125 (the lane path's "Every `git merge-base` in §4a, §5 and §7 uses `origin/<Target>`") as
    it is. It is true for lanes, which never have a `base-commit`.
- [ ] **Step 4: Run and expect PASS.** Run the test, then the whole ST and `pointer_skills_execute_test`
  (sh and dash).
- [ ] **Step 5: Commit** `docs(T2): <merge-base> is the base-commit sha in place on the default branch (#14)`.

### Task 3: The review skill's scope uses the same rule — Mechanical

**Files:**
- Modify R :75-79 (the scope bullet) and :100 (the verify-prior-fixes start). R :69-70 (report-only on
  the default branch) and :148 stay unchanged (falsified row 8).
- Test: ST, new `test_review_scope_uses_base_commit`, plus its `run_tests` name.

**Interfaces:**
- Consumes: T1's ledger line format (not T1's code: this task is independent).
- Produces: R's `<merge-base>` = the scope's start.

- [ ] **Step 1: Write the failing test:**

```sh
test_review_scope_uses_base_commit() {
  R="$REPO_ROOT/studios/game-dev/skills/review/SKILL.md"
  for lit in 'the sha of the last `base-commit` line of the feature ledger' \
             'base-commit <sha> is not an ancestor of HEAD — fix the ledger line or restart' \
             'report-only: no fix dispatch, no ledger line and no commit'; do
    assert_contains "$R" "$lit" "review carries: $lit"
  done
  assert_eq 1 "$(section_count "$R" '^## 0[.] ' '`<merge-base>` to `HEAD`')" "the whole-branch scope runs from <merge-base>"
  assert_eq 0 "$(section_count "$R" '^## 0[.] ' 'git merge-base <base> HEAD` to')" "the scope no longer starts at a raw merge-base"
  assert_contains "$R" '`<merge-base>` the scope.s start (§0)' "verify-prior-fixes starts at the scope's start"
}
```

- [ ] **Step 2: Run and expect FAIL.**
- [ ] **Step 3: Edit R.**
  - The scope (:75-79): "otherwise the whole branch, `<merge-base>` to `HEAD`, where `<base>` is …"
    (the base chain is unchanged). Then: "`<merge-base>` is the sha of the last `base-commit` line of
    the feature ledger when it has one (a run in place on the default branch), else
    `git merge-base <base> HEAD`. A `base-commit` sha that fails `git merge-base --is-ancestor <sha>
    HEAD` stops the review: "base-commit <sha> is not an ancestor of HEAD — fix the ledger line or
    restart"."
  - :100: "with `<merge-base>` the scope's start (§0), run …".
- [ ] **Step 4: Run and expect PASS.** Run the test and `test_review_contract`, then the whole ST (sh
  and dash).
- [ ] **Step 5: Commit** `docs(T3): review scope starts at the base-commit sha in place on the default branch (#14)`.

### Task 4: Contract — no `bin/`/`hooks/` pattern matches a `base-commit` line — Mechanical

**Files:**
- Test only: ST, a new helper `nr_scan` and `test_no_reader_matches_base_commit`, placed next to the T1
  tests, plus the `run_tests` name.

**Interfaces:**
- Consumes: the code under `studios/*/{bin,hooks}`, `shared/*/{bin,hooks}`, `integrations/*/bin` and
  `integrations/*/bridge`.
- Produces: `nr_scan ROOT...`. It prints `<file>: <pattern>` for every single-quoted or `/…/` literal that mentions
  `base` and matches a `base-commit` line, with or without its `- <date> ` prefix (studio-adopt's
  readers see the prefix stripped, `studio-adopt:564,820`).

- [ ] **Step 1: Write the test.** This is the hard part (a literal extractor), so here it is in full:

```sh
# nr_scan ROOT... — every single-quoted string or /…/ literal under ROOT that mentions "base"
# and, tried as an ERE and as a BRE, matches a base-commit ledger line: "<file>: <pattern>".
# (No double-quoted strings: they are messages and sed scripts, never ledger patterns here, and
# an unbalanced "…" span or an `s|a|b|` script false-positives — probe at 1cfca7f.)
nr_scan() {
  find "$@" -type f 2>/dev/null | while IFS= read -r _nr_f; do
    { grep -o "'[^']*base[^']*'" "$_nr_f" | sed "s/^'//; s/'\$//"
      grep -o '/[^/]*base[^/]*/' "$_nr_f" | sed 's|^/||; s|/$||'
    } 2>/dev/null | while IFS= read -r _nr_re; do
      for _nr_l in "- 2026-10-21 base-commit 0123456789abcdef0123456789abcdef01234567" \
                   "base-commit 0123456789abcdef0123456789abcdef01234567"; do
        if printf '%s\n' "$_nr_l" | grep -qE -e "$_nr_re" 2>/dev/null \
           || printf '%s\n' "$_nr_l" | grep -q -e "$_nr_re" 2>/dev/null; then
          printf '%s: %s\n' "${_nr_f#"$REPO_ROOT"/}" "$_nr_re"; break
        fi
      done
    done
  done
}

# #14: no code reads a base or base-commit ledger line; a future reader must not match base loosely.
test_no_reader_matches_base_commit() {
  mkdir -p "$TMP/nr/bin"
  printf '%s\n' "grep -q '^- [0-9-]* base' \"\$lf\"" > "$TMP/nr/bin/loose"
  printf '%s\n' "grep -q '^- [0-9-]* base ' \"\$lf\"" > "$TMP/nr/bin/strict"
  _nr_ctl="$(nr_scan "$TMP/nr/bin")"
  assert_eq yes "$(case "$_nr_ctl" in *loose*) echo yes ;; esac)" "the scan flags a loose base reader"
  assert_eq no "$(case "$_nr_ctl" in *strict*) echo yes ;; *) echo no ;; esac)" "and not a strict 'base ' reader"
  assert_eq yes "$( [ "$(grep -o "'[^']*base[^']*'" "$REPO_ROOT/studios/game-dev/bin/studio-state" | grep -c 'adopt-base')" -ge 1 ] && echo yes)" \
    "the extractor sees the real adopt-base reader (studio-state:583)"
  assert_eq "" "$(nr_scan "$REPO_ROOT"/studios/*/bin "$REPO_ROOT"/studios/*/hooks "$REPO_ROOT"/shared/*/bin \
    "$REPO_ROOT"/shared/*/hooks "$REPO_ROOT"/integrations/*/bin "$REPO_ROOT"/integrations/*/bridge)" \
    "no bin/ or hooks/ pattern matches a base-commit ledger line"
}
```

- [ ] **Step 2: Run it.** This is a contract over existing code, so it passes at once. Prove it can fail
  instead: temporarily add `grep -q '^- [0-9-]* base' x` to a scratch copy, which the loose control
  already covers. If the last assertion flags a non-reader at the story base (a message string, not a
  pattern), don't loosen the extractor. Add a literal `_nr_allow` case for that exact `<file>: <pattern>`
  line, with a comment naming why, and record it in the commit body.
- [ ] **Step 3: Time it.** The planner's probe at 1cfca7f (this exact extractor, run under sh and
  dash) found 17 candidates and 0 hits in about 1.2 s. The loose control was flagged and the strict one
  was not. If the test takes over 5 s, cut the candidates to the lines that mention `ledger`, `truth`
  or `grep`/`sed`/`awk`, and say so in the commit.
- [ ] **Step 4: Run** the whole ST (sh and dash). The four assertions count the same under both shells.
- [ ] **Step 5: Commit** `test(T4): no runner or hook pattern matches a base-commit ledger line (#14)`.

### Task 5: #6 — the Plan 2 plan's Task 16 doc errors — Mechanical

**Files:**
- Modify `docs/game-dev/plans/2026-09-13-plan-2-quality-loop.md`:
  - :3021: `skills 12` → `skills 11`;
  - :3025: Step 3's checkbox.
- Not here: PROGRESS.md (:12 row and :517). The controller does those.

**Interfaces:** none.

- [ ] **Step 1: The check fails first:** `grep -c 'skills 12' <plan>` → 1 and
  `grep -c '^- \[x\] \*\*Step 3: The toolkit against a real project' <plan>` → 0.
- [ ] **Step 2: Edit.**
  - :3021 now reads `skills 11` (brainstorm, plan, execute, review, playtest, retro, studio, and four
    domain skills: 11 dirs under `studios/game-dev/skills/`).
  - :3025 becomes `- [x] **Step 3: The toolkit against a real project**`, followed by one line: "Done
    2026-09-16 (PROGRESS.md:496-513)."
  - Nothing else in Task 16 changes. Steps 4–5 stay open: they become the whole-studio smoke test (#6).
- [ ] **Step 3: The check passes:** the two greps print 0 and 1. `sh "$W/tests/run_affected.sh" --base
  integration/backlog-2026-10-21 --list` selects no suite for this doc. If it selects one, run it.
- [ ] **Step 4: Commit** `docs(T5): Plan 2 Task 16 — Step 3 done, the doctor counts 11 skills (#6)`.

### Task 6: Rebase, affected suites, floors — Mechanical

This task follows S2's "For other stories" recipe exactly (preflight fix).

- [ ] Merge the latest `origin/integration/backlog-2026-10-21` into the story branch (after `git fetch`). On a
  `tests/run_all.sh` floors-table conflict, take the integration branch's whole file
  (`git checkout origin/integration/backlog-2026-10-21 -- tests/run_all.sh`), never a hand-merge of counts.
- [ ] Commit every code and test change. The tree must be clean before the runs.
- [ ] Write the counts: the affected suites `studio_test` and `pointer_skills_execute_test`, plus anything
  `sh "$W/tests/run_affected.sh" --base origin/integration/backlog-2026-10-21 --list` adds, plus
  `harness_test`, through run_all under sh and then dash:
  `TEST_SUITES="studio_test pointer_skills_execute_test harness_test <added>" sh "$W/tests/run_all.sh"`,
  then the same with `TEST_SH=dash`. These partial runs take no heavy-suite lock. Red only with
  `floor` / `no floors row` lines is expected; any other red: fix, commit, and re-run both.
- [ ] With no commit since the last run, `sh "$W/tests/run_all.sh" --update-floors`. Any commit after the
  run means a re-run first. Expected: one `studio_test: <current floor> → <current floor + new>` line,
  where the current floor is the post-S2 table's exact value, not the pre-S2 741 (preflight fix);
  `pointer_skills_execute_test` is unchanged.
- [ ] Commit `test(floors): S6 studio_test count` (only `tests/run_all.sh`).

### Merge notes (preflight fix)

Shared regions with other stories, and how each merge resolves them:
- **X:505 and R:100 belong to S6.** S6 merges before S5, which edits only the adjacent regex lines X:507
  and R:102. S6 does not touch those two lines. R:100 already reads "with `<merge-base>` the scope's
  start,"; S6's edit adds " (§0)" and nothing else on that line.
- **X elsewhere.** S1 edits X:703-704 and S5 edits :328-333, :573-579, :715-716 and later; all disjoint
  from S6's :233-259 and :479.
- **studio_test `run_tests` list (:854-865) and new tests after :834-845.** S5 appends here too. On a
  conflict, keep both sides; S6 adds its names on its own new continuation line.
- **`tests/run_all.sh` floors.** On a conflict, take the integration branch's `run_all.sh`, then redo
  this task from the commit step.
- **Order.** S6 builds in parallel with S4 and S3 and merges first of the three (S2's build order).

---

## Final review, gate, acceptance

- **Final whole-branch review (Opus, standalone):** this is the controller's job, run over the whole
  integration branch per spec §11. Focus for S6:
  - the Review Focus above;
  - A1: a run not in place on the default branch reads exactly as at 1cfca7f;
  - X's existing pinned literals are intact;
  - the line-wrap rule for the asserted literals.
- **Full gate:** the controller runs it once, at the end (sh and `TEST_SH=dash`; a full run, so run_all
  takes the heavy-suite lock itself: preflight fix).
- **Manual acceptance** (operator, not a builder task; it runs with #6's live check): one pressure
  scenario on the slim fixture (`tests/pressure/fixture.sh`), checked out on `main`, executed in place.
  - Its feature ledger has a `base-commit` line.
  - Its final-review brief lists a non-empty `<sha>..HEAD` range that holds the run's task commits.

## Falsified assumptions (planner falsify clause)

Checked against 1cfca7f:

| # | Assumption | Verdict | Evidence |
|---|---|---|---|
| 1 | §0 (c) writes the base with one single-line command | holds | X:233-237; the command is all on :236 |
| 2 | "The base" is X:253-259 and anchors `git merge-base <base> HEAD` | holds | X:253-259 |
| 3 | §7 uses `<merge-base>` (spec §9 "§4a, §5 and §7") | **false** | `grep -n merge-base` X → :125, :219, :254, :479, :505-506, :515-516; §7 (:582-740) has none. → T2 defines it for §4a/§5, rewrites :254, and pins §7's raw count at 0. X:125 is left alone |
| 4 | The rebuild can read the sync's `T<k+1> in progress` "in the same (c) step" | **false** | The sync runs after (c) and `studio-setup` (X:247-251); its report is stdout (`studio-adopt:490,922`), not the ledger. → T1 writes fallback 2 after `studio-adopt sync` reports |
| 5 | The `T<n> complete` range is `<a>..<b>`; `<a>` can be `<first>^1` or a short sha | holds | X:559-565 (full shas; "older short-sha lines still parse") |
| 6 | `studio-state ledger` writes `- <date> <text>` | holds | `studio-state:891` |
| 7 | No reader matches `base-commit` (spec F17) | holds, one more reader | `adopt-base ` only: studio-adopt:564,820; L:355; studio-state:583; **also `studio-brief:387`** (awk `/^- [0-9-]+ adopt-base /`), which the spec does not list. → T4's scan covers it |
| 8 | Review scope :76-79 and verify-prior-fixes :100 need the rule; report-only :69-70 stays | holds | R:69-70, :75-79, :100-102. R:148 (the production-bug test) is reachable only in a fix round, and fix rounds never happen on the default branch (report-only) → unchanged |
| 9 | `section_count FILE HEADING_RE PATTERN` exists; headings take the form `'^## 0[.] '` | holds | ST:708-711, :730-734 |
| 10 | §0 holds `(see §8, Operator messages)` exactly twice | holds | ST:730; T1 adds no such phrase |
| 11 | Existing pinned literals in X | holds | ST `test_execute_contract` `ledger "base`; `pointer_skills_execute_test.sh:22-23` |
| 12 | Affected suites for X/R are `studio_test` and `pointer_skills_execute_test` | holds (grep) | only those two suites name `execute/SKILL.md`/`review/SKILL.md`; confirmed by `--list` in T1 Step 4 |
| 13 | Plan 2 doc :3021 says `skills 12`; Step 3 is :3025; PROGRESS.md:496-513 records it done | holds | read; `studios/game-dev/skills/` has 11 dirs |
| 14 | Floors rows `studio_test 741`, `pointer_skills_execute_test 14` | holds | run_all.sh:58, :80 |
| 15 | `run_all.sh` takes a partial run via `TEST_SUITES` | holds | run_all.sh:15-16. `--update-floors` and the counts file arrive with S2 (spec §5.4) |
| 16 | `grep -o` and the BRE `[$]` work under BSD/GNU grep and dash | holds | POSIX `grep -o` is in both macOS and GNU grep; `[$]` is a literal `$` in BRE |
| 17 | Extracting every quoted string is a clean candidate set for T4 | **false** | Probe at 1cfca7f: double-quoted extraction flagged `studio-overnight` (`s\|{default_branch}\|…` ERE alternation) and an unbalanced span at `studio-brief:387`. Single-quoted + `/…/` only: 17 candidates, 0 hits, loose control flagged, strict not (sh and dash). → T4 drops double quotes |
| 18 | T1/T2/T3's new literals are absent from X/R today (so Step 2 fails) | holds | `grep` for each new phrase in X/R at 1cfca7f → no hits (the only `is the default branch` in X is :638, a different phrase) |

## Self-review

- **Spec coverage (§9):**
  - the record and its condition → T1;
  - the format and last-wins rule → T1;
  - the `<merge-base>` definition and its §4a/§5 uses → T2;
  - the review scope (:76-79) and verify-prior-fixes start (:100) → T3, with report-only :69-70 kept;
  - the three resume fallbacks → T1;
  - the readers contract → T4;
  - the failure mode (not an ancestor: stop, no silent fallback) → T2/T3;
  - the five acceptance tests → T1 (2), T2, T3, T4;
  - operator acceptance → Manual acceptance;
  - §10 #6 plan doc → T5 (PROGRESS.md left to the controller, per dispatch).
- **Names:** T1-T4 use the same literals, `base-commit <sha>`, `<merge-base>`, "in place on the default
  branch" and the not-an-ancestor message, in X, R and ST.
- **Proportion:** a few dozen lines of skill text and about 90 lines of tests. Full code appears only
  for the tests and the T4 extractor.
