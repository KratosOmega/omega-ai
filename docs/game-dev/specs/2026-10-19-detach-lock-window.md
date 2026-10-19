# `start --detach` survives a slow start: one check, a real window, fast id checks (#70)

## Problem

`studio-overnight start --detach M` runs the checks in the foreground: `preflight manifest`, then
`lanes_start --check M`, which is `mf_check` plus the worktree_setup check. It then re-execs
`start M` as a setsid child, and gives that child 10 s (`10 * DETACH_TPS`) to answer `status --run`
and hold the run lock. A child that misses the window is TERMed and then KILLed. Before it takes
the lock, the child runs `preflight manifest` and `mf_check` again. On phoenix's
combat-vfx-library manifest (7 stories, 132 units) that takes ~21 s of CPU. So every `--detach`
of it is killed, and each attempt first costs a ~15 min worktree_setup check.

## Measured (profile, 2026-10-19; harness with fetch stubbed, load 30-65)

- `mf_check`: 24.5 s of a 26.6 s baseline. `preflight` itself: 2.0 s.
- `ids_check` → `ids_reasons` (overnight-ids.sh:61-105), once per story (overnight-lanes.sh:247):
  15.4 s, ~2.2 s per story.
  - Rule 2 (integration ledgers): one `git ls-tree` per `origin/integration/*` ref (16) per id.
  - Rule 3 (run records): ~48 ms per record per id (20 records). This is #57.
  - `ids_*` make 1,123 of the 1,802 process spawns.
- `studio-state` runs twice per story: `show` (lanes:251) and `get stage` (lanes:258). 4.3 s.
- Nothing is quadratic in stories or units. The cost is stories × (run records + integration refs),
  and both of those grow with every run (nothing is pruned). A taken id adds up to 18 more full
  checks through `ids_suggest`.
- A scratch prototype of an index built once (`ids-proto.sh`) matched the old output on 64/64
  id/slug/branch cases and 4/4 whole `ids_check` cases. It cut `ids_check` from 15.4 s to 1.4 s,
  and the whole path from ~21 s to ~10 s at equal load.

## What the child can and cannot skip (ruling)

The operator asked that the child skip the preflight its parent just ran, using a token tied to
what was checked, so a stale token can't skip a real check. Mapping the checks shows that most of
`mf_check`'s cost is in checks that read **mutable** state, not the manifest:
- ids_check reads run records and origin ledgers;
- mf_conflicts reads other runs' locks and records;
- fetch, Docs-on-`origin/run/SLUG`, and the integration branch existing all read the remote;
- the story file, ledger, stage and git status come from studio-state;
- `mf_ready`, plus gh auth and claude-gd in preflight.

The parent's worktree_setup check sits between the parent's checks and the child, and lasts up to
20 min. In that time another run can take an id or a branch. **A token keyed on the manifest alone
cannot vouch for those checks, so the child always re-runs them.** The token skips only the checks
whose result is a pure function of what it hashes. That is what "a stale token can't skip a real
check" requires. The time saved comes mainly from making the mutable checks cheap (the ids index,
one studio-state call per story) and from a window that waits for the lock.

Skippable (pure functions of the manifest bytes + the committed config + git objects at a fixed
sha). In mf_check:
- slug rules (lanes:166-172)
- row branch forms (176-183)
- Mode/Target/merge_command (187-195)
- Goal (196)
- rows non-empty (197)
- the row awk for ids, duplicates, `-` cells and deps (200-211)
- per story, the plan-at-Docs checks (276-297): the plan is present, has `## Decisions` and
  `Story:`, has a Spec per task, and its Context files exist. Docs is a sha, so the objects can't
  change.

Never skipped:
- all of `preflight` (2 s; it also sets the config variables later code reads);
- fetch and every remote check;
- `ids_default_branch` and `ids_check`;
- `mf_conflicts`;
- the story file, ledger, stage and git status checks;
- `mf_ready` and `mf_overlap_warn`.
Any side effect of a skipped check that later code reads must still happen. None of the skippable
checks above sets anything later code reads. Recheck this per check while implementing.

## Design

1. **Fast ids (#57).** `ids_index SLUG D` builds, once per (STATE_ROOT, SLUG, D) in the calling
   shell (shell variables, no file writes):
   - the main ledger list;
   - the plan lines;
   - the integration ledger lists;
   - all run-record rows.
   `ids_reasons` then answers each id with one awk, keeping the rule order, the message text, the
   own-slug skips, archived and legacy records, and the same-branch exception. `ids_suggest`
   candidates reuse the index. Output is byte-identical to today's for every input.
2. **One studio-state call per story.** mf_check takes the stage from the `show` output it already
   has (lanes:251), not from a second `get stage` (258). The same refusals and messages.
3. **The window waits for the lock.** detach_start polls until the child **holds the run lock and
   answers status** (success), or the child **exits** (the "did not start" path, unchanged), or a
   cap passes. The cap defaults to 120 s. Test hook: `STUDIO_OVERNIGHT_DETACH_WAIT_SECONDS`, a whole
   number from 1 to 3600, read before the strip like the other detach hooks. Any other value
   refuses with exit 2. At the cap:
   - a child that holds the lock gets the existing "is live … but did not answer status in N s"
     message, with N being the cap, and exit 1;
   - otherwise the child's group is TERMed and KILLed with the existing "never took the lock and
     was ended" message, and exit 1.
4. **Preflight token.** `STUDIO_OVERNIGHT_PREFLIGHT_CHECKED=<hex sha-256>` is computed by
   `pf_token MANIFEST_ABS` (studio-overnight). It hashes:
   - the literal `omega-pf-v1`;
   - the manifest's absolute path;
   - the manifest bytes;
   - `$START_DIR/.studio/config.json` bytes.
   Each part is length- or newline-delimited, so different inputs can't collide.
   - The parent takes the token **before** its foreground checks and again just **before**
     spawning the child. It passes the token only if the two are equal; a manifest edited during
     the setup check gets none.
   - The child reads the variable once and unsets it (before anything can pass it on), like
     `STUDIO_OVERNIGHT_SETUP_CHECKED`. It recomputes the token.
   - Equal: mf_check skips the skippable checks and says
     `manifest checks: done by start --detach at <first 7 hex> — re-checking ids, runs and the remote`.
   - Not equal: it says `manifest changed since start --detach checked it — checking it again` and
     runs the full check (no refusal: the full check is the safe fallback, and the window now
     waits for the lock).
   - The variable is never passed to unit sessions.

## Acceptance

- `--detach` with a stand-in child that takes the lock after ~15 s succeeds (exit 0, `detached:`).
- A child that never takes the lock is ended at the cap (exit 1, "never took the lock", no
  survivor).
- A child that holds the lock but doesn't answer status gets the "is live" message at the cap.
- A manifest changed between the parent's two token reads: the child's environment has no
  `STUDIO_OVERNIGHT_PREFLIGHT_CHECKED`.
- The child, given a matching token, logs the skip line and still runs ids_check and mf_conflicts.
  Given a stale token, it logs "changed" and runs the full check. The variable is never in a
  unit's environment.
- ids output is unchanged, including two new cases: several ids taken by different sources in one
  manifest, and a suggestion candidate taken by a run record.
- On phoenix's combat-vfx-library manifest, `mf_check` CPU drops from ~24 s to under ~10 s
  (measured the same way as the profile).
- The full gate (`tests/run_all.sh`) is green.
