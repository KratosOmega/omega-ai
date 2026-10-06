# Reinstall keeps the user's `settings.json` keys — Spec

Story: #53 (GitHub issue). Status: Approved (2026-10-06). The operator ruled on
every open choice in the request (R1–R7 below); the plan records the few
details the rulings left to it.

## What happened

Every `./install.sh game-dev` replaced `~/.claude-gamedev/settings.json` with
the studio's template. Keys the user or Claude Code had added were lost; the
one that kept going missing was `"agentPushNotifEnabled": true`, Claude Code's
push-notification toggle, so `claude-gd` sessions and overnight runs stopped
notifying the user's phone. Seen on three reinstalls in a row (2026-10-05 after
#39/#41/#42, twice on 2026-10-06 after #49/#50); each time the key was restored
by hand from a backup. `~/.claude/settings.json` was unaffected.

Why: `install.sh:126-129` backs up a differing `settings.json` to
`settings.json.bak-<stamp>`, then `install.sh:200-201` does `rm -f` + `cp` of
the template. The backup keeps the data, but nothing carries the user's keys
forward. Eleven `settings.json.bak-*` files have piled up in
`~/.claude-gamedev/` this way.

## Goal

A reinstall updates the keys the studio template owns and keeps every other
top-level key already in the target `settings.json`.

## Requirements

- **R1. Merge tool.** python3's stdlib `json`; no `jq` (the core repo forbids
  it — "R19: no jq", `studios/game-dev/hooks/operator-inbox.sh`). Resolve
  python3 as `command -v python3`, else `/usr/bin/python3`, and check that the
  interpreter actually runs (macOS's `/usr/bin/python3` can be a stub that only
  offers to install the developer tools).
- **R2. Merge rule — top level only.** Every top-level key the template defines
  takes the template's whole value (no deep merge). Every top-level key in the
  existing file that the template does not define is kept with its existing
  value. Order: the template's keys in template order, then the kept keys in
  their existing order. 2-space indent, trailing newline, non-ASCII written as
  is (`ensure_ascii=False`).
- **R3. Fallbacks never fail the install.** No working python3, or an existing
  file that is not valid JSON or whose top level is not an object: install the
  template as today, with a warning naming the backup path.
- **R4. Reporting and backups.** When keys are kept, print one line naming them:
  `settings.json: kept your keys: <k1>, <k2>`. The backup step stays as a safety
  net. A fresh install (no existing file) is byte-identical to today. When the
  merged result equals what is already there, behave as today for identical
  files: no backup. Prefer no new `.bak` when the only difference is keys that
  are kept.
- **R5.** `--dry-run` prints which keys it would keep and writes nothing.
- **R6.** The manifest entry for `settings.json`, `uninstall.sh` and `doctor.sh`
  behave as today; a merged file must not fail any doctor check.
- **R7.** `install.sh` stays POSIX sh (macOS `/bin/sh` = bash 3.2, and dash).
  The python is small and inline (or a small script in the repo); the plan
  chooses and says why.

## Acceptance (from the issue, plus the operator's test list)

- An existing target `settings.json` with an extra key (`agentPushNotifEnabled`)
  and a stale template-owned key: after install the extra key is still there and
  the template-owned key holds the template's value.
- A fresh install is unchanged.
- An invalid-JSON target falls back with a warning; so does a missing or broken
  python3.
- `--dry-run` reports the kept keys and writes nothing.
- No new `.bak` when the only difference is kept keys.
- `doctor.sh` stays clean after a merged install; uninstall still removes
  `settings.json` through its manifest entry.

Out of scope: deep merges of template-owned objects (a user's own entry inside
`enabledPlugins` is still replaced, as today); `~/.claude` (never touched).
