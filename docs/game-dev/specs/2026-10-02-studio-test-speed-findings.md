# studio-test speed: findings and verdicts (issue #22)

Measured 2026-10-02 23:00 – 2026-10-03 01:30 on phoenix, after its overnight run was stopped.
Every number below comes from a run made in this session through `studio-gate`, unless it is
marked as taken from an earlier report.

## Verdicts

| # | Candidate | Verdict | Deciding number |
|---|-----------|---------|-----------------|
| — | **Pass the project's GUT config** (found during measurement) | **BUILD — done** | full suite 4,485 s → **847 s** (5.3×) |
| 1 | `studio-test --shards N` | **DEFER** | 4 shards 2.9× faster with no swap, but shard-only failures in 2 of 4 runs |
| 2 | Fast/full tiers | **DROP** | fast tier = **51%** of full wall (rule: ≤ 15%) |
| 3 | `studio-test --slowest [N]` | **BUILD — done** | 1.3 s over a 19,504-test report |
| 4 | Import-cache readiness | **BUILD — done** | a half-built cache crashed the suite at 472 s; now re-imported or stopped in ~2 s |

The branch `worktree-issue-22-studio-test-speed` carries the three BUILD items and the config fix.

## The root cause: studio-test ran phoenix without its GUT config

phoenix keeps its GUT options in `tests/.gutconfig.json`. That config names a pre-run hook
(`tests/helpers/gut_pre_run_locale.gd`) which does three things for the whole run:

- keeps `resources/animations/humanoid.tres` loaded (KAN-919), plus 9 heavy tilesets and
  interiors;
- pins the locale to en;
- snapshots and restores the Inventory autoload around every file, and fails the run on a leak
  (KAN-1251, with the post-run hook).

GUT reads only `res://.gutconfig.json` unless `-gconfig` is passed. `test.sh` never passed it,
so under `studio-test` none of those hooks ran. The September agents ran Godot directly with
`-gconfig=res://tests/.gutconfig.json`, which is why their full runs were fast.

Without the hook, every test that builds an actor reparses the 7.9 MB, 356k-line rig. That
costs 3–4 s on this machine.

**Evidence:**

1. **The Sep 23 commit 391e2d379, run today under the old `studio-test`, took 3,123 s.** The
   same suite took 608 s of test time on Sep 23 with its config (report taken from an earlier
   session's scratchpad `gut_full.xml`). We compared the 17,302 tests common to both runs,
   bucketed by today's time:

   | today's time per test | tests | time today | time Sep 23 |
   |---|---|---|---|
   | under 2 s | 16,515 | 373 s | 359 s |
   | 2–8 s | 782 | 2,523 s | 204 s |

   Tests under 2 s ran at the same speed in both, so the machine is not the cause. On Sep 23,
   even the first test in run order that needs the rig (#219) took 0.02 s, so the rig was
   already loaded before any test built an actor: that is the pre-run hook.
2. **Holding the rig fixes it.** `test_passive_stat_readers.gd` took 89 s alone and 2.4 s with
   the rig held (plus a one-time 4 s load).
3. **The Oct 2 suite (4,416 s of test time) has 893 tests at 3.5–6 s each.** Together they are
   3,575 s, or 81% of the suite, which is the reparse signature.
4. **After the fix, the current suite runs in 847 s wall (710 s test time).** In that run
   `test_player_menu.gd` takes 22.4 s for 108 tests; on Oct 2 it took 441 s.

**Fix** (commit 72f6ccb): `test.sh` passes the project's config. It looks for
`.gutconfig.json` at the root, then under `tests/`.

- With no PATH, the config's `dirs` are the suite.
- A file target passes `-gdir= -gtest=<file>`, because GUT runs the config's dirs as well as
  any `-gtest`.
- A directory target replaces the dirs.

Each shape was verified on phoenix with GUT's `-gpo`.

**Correctness gained too.** The config-less run of the Sep 23 code had 3 order-dependent
"delivery" failures that did not appear with the hook (Inventory isolation restored). Under the
old `studio-test`, locale pinning and the leak watchdog were also off.

## Measurement conditions

| | |
|---|---|
| Machine | macOS 13 (Darwin 22.6), 16 GB RAM, 4 physical / 8 logical cores |
| Engine | Godot 4.6.3 mono, GUT 9.6.0 |
| Project | phoenix at 240f835ce, copied to `~/godot-measure/phoenix` (a complete import cache, no `.git`) |
| Overnight | `studio-overnight status` exited 1 before every run |
| Load | load average 3.2–5.0 during the config runs |
| Swap | 3.6 of 5.1 GB used, unchanged. Swap-outs stayed at 897,000,993 from the first config run to the last |
| Other load | iCloud's `bird` near 95% of a core throughout |

All 19 failures in every run are in 8 files that check git state (`git ls-files` and similar),
which the copy does not have. They are identical in serial and sharded runs, so the pass/fail
comparison is unaffected.

## 1. Sharding: DEFER

Shards were split by LPT over the serial report's per-file times, with `-gconfig -gdir=
-gtest=<list>` and a separate empty HOME per shard. All shards ran in one copy of the project.

| Run | Wall | Speed-up | Peak RSS per process | Shard-only failures | Merged = serial? |
|---|---|---|---|---|---|
| serial | 846.7 s | 1.0× | 2,535 MB | — | — |
| 2 shards | 508.1 s | 1.67× | 1,884 / 1,712 MB | 3 | no |
| 4 shards, run 1 | 291.7 s | 2.90× | 1,068–1,312 MB | 1 | no |
| 4 shards, run 2 | 287.0 s | 2.95× | 1,075–1,312 MB | 0 | yes (19,504 tests, 19 fail) |
| 4 shards, run 3 | 287.7 s | 2.94× | 1,068–1,296 MB | 0 | yes |

- **Speed and memory pass.** The speed-up is 2.9× against the 2.5× target. Four shards peak at
  about 4.8 GB together, with no swap-outs. The longest shard sets the wall: predicted 178 s
  each, actual test times 178–245 s.
- **Isolation fails.** Two shard-only failures:
  - **`test_objective_tracker_offset.gd`** (3 tests, 2-shard run). The tracker reserves 176 px
    where 90 is expected, so an objective panel is showing.
    - It passes alone, after the four files that preceded it in the shard, and with an empty
      HOME.
    - The whole 637-file prefix of that shard reproduces the failure. Bisecting it over 11
      halvings leaves one file: **`test_mission_service.gd`**.
    - That file calls `MissionService.reset()` in `before_each` but not in `after_each`, so its
      last test leaves a mission deployed in the autoload.
    - In serial order, `test_objective_tracker_hud.gd`, which resets in `after_each`, runs
      between the two and hides the leak.
  - **`test_nav_region_baker.gd :: test_rebuild_is_the_world_change_seam`** (4 shards, run 1
    only). "after rebuild() the ground path is straight — hole gone" failed. The same shard,
    with the same files before it, passed in runs 2 and 3, and the file passed 5 of 5 alone.
    It is a flake under parallel load, not an order dependency.
- **Blocker:** phoenix tests that rely on what ran before them, or on an unloaded machine.
  Sharding changes both.
- **The finish gate no longer needs sharding to fit.** With the config fix, the full suite is
  about 14 min against `session_minutes` 90. The overnight preflight warns when the slowest
  `studio-test` × 1.2 + 10 min exceeds 90 min; 847 s gives about 27 min.
- **Re-measure when** phoenix fixes the two tests above, or the finish gate grows past about 45
  minutes.

## 2. Fast/full tiers: DROP

- **The fast tier is too big.** It is the 1,745 of 1,861 files where every test runs under
  0.5 s. Its real run took **436.1 s** wall (305 s of test time), **51%** of the 846.7 s full
  run. The rule needs 15% or less. Startup and per-file overhead dominate the small files, so
  taking out the slow files saves less than their test time suggests.
- **Per-task gates do run the full suite.** The execute skill has implementers run `studio-test`
  with no PATH before handing back (`skills/execute/SKILL.md:262`) and after a fix wave (`:330`).
  October's `studio-test` calls were all full suites. In September, agents ran about 4.8k
  targeted `-gtest` runs against about 94 full ones.

  So the second half of the rule holds, but the first fails. Tiers would not shorten the finish
  in any case.
- **Recommended instead (not built; a workflow decision).** A per-task gate could run the task's
  own test files, `studio-test <the Verify: unit files>`, with the full suite left to the final
  review and the finish. That cuts each task's gate from about 14 min to under a minute. It
  trades away catching a cross-file regression at the task that caused it; the final review
  still catches it.

## 3. `studio-test --slowest [N]`: BUILD, done

`studio-test --slowest [N]` reads the newest `.studio/reports/test-*.xml` without taking the
gate. It prints:

- the N slowest files and the N slowest tests;
- the share of the time in the top N files;
- the share of the time in tests of 0.5 s or more.

It takes 1.3 s on a 19,504-test report. Commit 0b6f381.

On the fixed suite, the top 12 files are 21% of the time. Tests of 0.5 s or more are 237 of
19,504, but 46% of the time.

## 4. Import-cache readiness: BUILD, done

**What failed.** The overnight runs at 19:18 and 21:30 used a fresh worktree,
`KAN-1499-mob-composer-no-presets`.

1. At 19:21 its first import was cut off at "Creating autoload scripts". Unit S1-T1 ended at
   that moment, and the import process was killed with it.
2. `test.sh` imported only when `.godot/` was absent, so the next runs trusted the half-built
   cache. Their logs carry about 30,800 "Cannot open file .godot/imported/…" errors: fonts,
   the theme and tileset textures.
3. Scripts that depend on them failed to compile.
4. `test_creator_diorama.gd` built a tile map with no tileset texture, and Godot segfaulted in
   `TileMapLayer::get_cell_tile_data`.

The 21:31 run is the gate's `studio-test 472 1`: 21:31:14 + 472 s = 21:39:06, the crash time.

**Reproduced** on a fresh worktree:

- A full import takes 130.5 s (peak 1.7 GB). A no-op import over a complete cache takes 24.3 s.
- A killed import leaves `.godot/` with 4,739 products missing. The old `test.sh` then ran the
  suite on it.

**Fixed** (commits f22dfc8 and f3abf49). Before the engine runs, `studio-test` and
`studio-run` check every `*.import` product and its `.md5` sidecar, plus the class cache.

- Godot 4.6's `_reimport_file` writes the `.md5` after the importer finishes and after the
  `.import` file. `_test_for_reimport` re-imports any file without one. So a product with no
  `.md5` was cut short, and re-running the import resumes rather than restarts.
- If the cache is incomplete, the import runs. If it still cannot finish, the run stops with the
  missing products named, rather than running into a crash.
- The check takes 2–3 s on phoenix and finds 0 missing on two complete caches.
- A crash is now reported as `Godot crashed (signal 11) while running <script>`, including a
  crash at shutdown after a passing report.

"Prebuild the cache earlier" is **DROPPED**. It would move the same 130 s, and the gate now
handles a partial cache itself.

## phoenix's own test fixes (from the profile)

1. **Keep `tests/.gutconfig.json` as the source of the suite's hooks.** It now runs under
   `studio-test`. The KAN-919 pin already does what the profile asked for, so nothing to rebuild.
2. **`test_creator_diorama.gd` should fail, not segfault, when its tileset is missing:** assert
   the tileset and its atlas before the terrain calls. The segfault is in Godot's terrain code,
   but the test can stop first.
3. **`test_mission_service.gd` leaks a deployed mission.** Add `MissionService.reset()` to its
   `after_each`, and to `test_objective_tracker_offset.gd`'s `before_each`, which assumes no
   mission. Better still, a MissionService snapshot/compare in the pre-run hook, like the
   KAN-1251 Inventory watchdog, would catch the whole class at once.
4. **`test_nav_region_baker.gd :: test_rebuild_is_the_world_change_seam` is flaky under load.**
   It likely waits a fixed number of frames for a navigation bake.
5. **Leave the KAN-1174 real-time waits alone.** Profiled: the close fade is 11–26 ms per
   build. The 4 s per build was the rig reparse, and `test_player_menu.gd` is now 0.21 s per
   test.
6. **The rig itself.** `humanoid.tres` grew from 6.1 MB (Sep 23) to 7.9 MB (Oct 2). The test
   pin hides its parse cost; the game does not. SceneLoader holds it only after the first scene
   change, so the title, character creator and player preview reparse it about 4 s at a time,
   and rig hot-reload reparses it on purpose. A binary `.res`, a per-family split, or one owner
   that holds it are the options. A binary `.res` was not measured here.

## Evidence levels

- **Measured this session:**
  - every wall time, RSS, swap and pass/fail number above;
  - the 89 s → 2.4 s rig pin;
  - the 3,123 s config-less Sep 23 run;
  - the import timings;
  - the crash timeline from the lane's logs and `gate.times`.
- **From earlier reports (not re-run):**
  - the Sep 23 report: 608 s of test time;
  - the Oct 2 report: 4,416 s of test time;
  - the 4,485 s Oct 2 gate time;
  - transcript counts of targeted against full runs.
- **Inferred, not proven:**
  - that unit S1-T1's teardown killed the 19:21 import. The timing matches, but no log names the
    killer;
  - that the nav failure is a load flake (one failure in three 4-shard runs, 0 in 5 alone);
  - the rig's cost in the running game and editor. The parse cost was measured in tests only.
