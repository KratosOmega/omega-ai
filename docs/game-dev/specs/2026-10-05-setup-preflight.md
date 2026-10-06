# Preflight `worktree_setup` in a linked worktree before start — Spec

Story: #49 (GitHub issue). Status: Approved (2026-10-05). The operator wrote
these requirements in the request; the plan records the one choice they left
open (R3, the dry run).

## What happened (phoenix, 2026-10-05)

`studio-overnight start --detach` passed every readiness check (dry run,
baseline studio-test, Godot binary) and the run launched at 23:00. At 23:09 the
first story's new worktree ran `worktree_setup` through studio-setup and exited
1: a project script (`tools/git-hooks/install.sh`) assumed `.git` is a
directory, and in a linked worktree it is a file. The story went held with
"worktree setup failed" while nobody was at the keyboard. Nothing before launch
had ever run `worktree_setup` in a linked worktree.

## Goal

A broken `worktree_setup` is refused at `studio-overnight start`, while the
operator is still there, not discovered by the first story at night.

## Requirements

- **R1.** When `worktree_setup` is set, `start` (detached or not) runs it once
  in a scratch **linked** worktree (`git worktree add`, not the main checkout —
  the case that hid this bug) off the run's first story base, through the same
  studio-setup path the runner uses, so it gets the same gate lock and timeout.
  On a non-zero exit, refuse to start: print the exit code and the log path, and
  remove the scratch worktree. On success, remove it too, and launch.
- **R2.** The setup can take minutes (npm ci + Godot import; phoenix caps it at
  30). Print one line saying it is running and how long it may take, so the
  operator does not think `start` hung.
- **R3.** Decide whether `--dry-run` runs it too, or only says it will run at
  start; state the choice and the reason in the plan. A cheap dry run is
  valuable (the operator leans towards not running it there).
- **R4.** Tests: a fixture repo whose `worktree_setup` passes in the main
  checkout but fails in a linked worktree (e.g. `[ -d .git ]`) is refused by
  start. A passing setup launches and leaves no scratch worktree. Unset
  `worktree_setup` skips the preflight silently.
- **R5.** Update the studio-overnight usage/config help text for
  `worktree_setup` to say it is preflighted.

Out of scope: phoenix's own `install.sh` bug (KAN-1292 in the phoenix project).
Phoenix itself is not changed.
