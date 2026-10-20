#!/bin/sh
# engines/godot/isolate.sh — per-worktree user:// (#71 D12): the override.cfg, the
# start-scrub, --check, --scrub, --leaks and the daily sweep, plus studio-dispatch --has
# and the studio-test call. No Godot runs. Every test points STUDIO_GODOT_USER_ROOT
# (isolate.sh's test-only data root) at its own dir under $TMP, so nothing is written to
# ~/Library/Application Support; test_isolate_user_root_production_default runs the
# unset path with HOME under $TMP.
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"

STUDIO="$REPO_ROOT/studios/game-dev"
BIN="$STUDIO/bin"
ISO="$STUDIO/engines/godot/isolate.sh"
unset STUDIO_START_DIR STUDIO_GATE_HELD STUDIO_GATE_LANE STUDIO_GATE_DEMOTE STUDIO_UNIT_TAG STUDIO_GATE_MINUTES STUDIO_GATE_SECONDS STUDIO_GODOT_USER_ROOT
mk_tmp isolate
trap 'rm_tmp "$TMP"' EXIT

MARKER='; omega-ai studio-test: per-worktree user:// (#71). Generated; never commit.'
USE='config/use_custom_user_dir=true'
NAMELINE='config/custom_user_dir_name="Foo-lanes-0badf00d/wt"'

g() { git -c user.name=t -c user.email=t@t.invalid -c commit.gpgsign=false "$@"; }

# iso_repo NAME — a main checkout with a committed project.godot and studio state.
iso_repo() {
  R="$TMP/$1"; mkdir -p "$R"
  ( cd "$R" && git init -q -b main . && printf '[application]\nconfig/name="Stub Game"\n' > project.godot \
      && git add project.godot && g commit -q -m init && sh "$BIN/studio-state" init ) >/dev/null 2>&1
  printf '%s\n' "$R"
}
# iso_wt REPO NAME [nokey] — a linked worktree; its config opts in unless nokey.
iso_wt() {
  W="$TMP/$2"
  g -C "$1" worktree add -q -b "br-$(printf %s "$2" | tr -c A-Za-z0-9 _)" "$W" >/dev/null 2>&1
  mkdir -p "$W/.studio"
  [ "${3:-}" = nokey ] || printf '{"engine": "godot4", "user_dir": "per-worktree"}\n' > "$W/.studio/config.json"
  printf '.studio/\n' >> "$(git -C "$W" rev-parse --path-format=absolute --git-common-dir)/info/exclude"
  printf '%s\n' "$W"
}
# iso DIR [ARG…] — isolate.sh in DIR with the test's data root $UR.
iso() { _d="$1"; shift; ( cd "$_d" && STUDIO_GODOT_USER_ROOT="$UR" OMEGA_STUDIO_ROOT="$STUDIO" sh "$ISO" "$@" ); }
# h8 DIR — the clone key isolate.sh derives.
h8() { printf '%s' "$(git -C "$1" rev-parse --path-format=absolute --git-common-dir)" | cksum | awk '{ printf "%08x", $1 }'; }
gid() { basename "$(git -C "$1" rev-parse --path-format=absolute --git-dir)"; }
want_cfg() { # DIR NAME — expected override.cfg into $TMP/want
  printf '%s\n[application]\n%s\nconfig/custom_user_dir_name="%s"\n' "$MARKER" "$USE" "$2" > "$TMP/want"
}

test_isolate_writes_in_opted_linked_worktree() {
  UR="$TMP/ud-writes"; R="$(iso_repo writes)"; W="$(iso_wt "$R" writes-wt)"
  iso "$W"; rc=$?
  assert_eq 0 "$rc" "ensure exits 0"
  want_cfg "$W" "StubGame-lanes-$(h8 "$W")/$(gid "$W")"
  assert_eq "" "$(diff "$TMP/want" "$W/override.cfg")" "override.cfg is the four lines with the project, clone key and worktree id"
  printf '%s' "$(h8 "$W")" | grep -Eq '^[0-9a-f]{8}$'; assert_eq 0 "$?" "the clone key is 8 hex digits"
  assert_eq "" "$(git -C "$W" status --porcelain)" "override.cfg is excluded"
}

test_isolate_never_in_main_checkout() {
  UR="$TMP/ud-main"; R="$(iso_repo main1)"
  mkdir -p "$R/.studio"; printf '{"engine": "godot4", "user_dir": "per-worktree"}\n' > "$R/.studio/config.json"
  iso "$R"
  assert_missing "$R/override.cfg" "no override.cfg in the main checkout"
}

test_isolate_needs_the_key() {
  UR="$TMP/ud-nokey"; R="$(iso_repo nokey)"; W="$(iso_wt "$R" nokey-wt nokey)"
  iso "$W"
  assert_missing "$W/override.cfg" "no key, no file"
}

test_isolate_run_fallback_key() {
  UR="$TMP/ud-fallback"; R="$(iso_repo fb)"; W="$(iso_wt "$R" fb-wt nokey)"
  mkdir -p "$TMP/fb-start/.studio"; printf '{"user_dir": "per-worktree"}\n' > "$TMP/fb-start/.studio/config.json"
  ( cd "$W" && STUDIO_START_DIR="$TMP/fb-start" STUDIO_GODOT_USER_ROOT="$UR" sh "$ISO" )
  assert_file "$W/override.cfg" "the run's config opts the story worktree in"
  rm -f "$W/override.cfg"
  iso "$W"
  assert_missing "$W/override.cfg" "without STUDIO_START_DIR it stays off"
}

test_isolate_leaves_foreign_override() {
  UR="$TMP/ud-foreign"; R="$(iso_repo foreign)"; W="$(iso_wt "$R" foreign-wt)"
  printf '[x]\n' > "$W/override.cfg"
  iso "$W" 2> "$TMP/err"
  assert_eq "[x]" "$(cat "$W/override.cfg")" "a foreign override.cfg is untouched"
  assert_contains "$TMP/err" "studio-test: override.cfg here is not studio-test's (or is tracked) — user:// stays shared; GUT short checks use the main lane" "the note is printed"
}

test_isolate_leaves_tracked_override() {
  UR="$TMP/ud-tracked"; R="$(iso_repo tracked)"
  printf '%s\n[application]\n%s\nconfig/custom_user_dir_name="Old-lanes/x"\n' "$MARKER" "$USE" > "$R/override.cfg"
  ( cd "$R" && git add override.cfg && g commit -q -m ov ) >/dev/null 2>&1
  W="$(iso_wt "$R" tracked-wt)"
  cp "$W/override.cfg" "$TMP/tracked.before"
  iso "$W" 2> "$TMP/err"
  assert_eq "" "$(diff "$TMP/tracked.before" "$W/override.cfg")" "a tracked override.cfg carrying the marker is untouched"
  assert_contains "$TMP/err" "is not studio-test's" "the note is printed"
}

test_isolate_rewrites_ours_on_rename() {
  UR="$TMP/ud-rename"; R="$(iso_repo rename)"; W="$(iso_wt "$R" rename-wt)"
  iso "$W"
  sed 's/Stub Game/Other Name/' "$W/project.godot" > "$TMP/pg" && cat "$TMP/pg" > "$W/project.godot"
  iso "$W"
  assert_contains "$W/override.cfg" "OtherName-lanes-$(h8 "$W")/$(gid "$W")" "the file follows config/name"
}

test_isolate_exclude_once() {
  UR="$TMP/ud-excl"; R="$(iso_repo excl)"; W="$(iso_wt "$R" excl-wt)"
  iso "$W"; iso "$W"; iso "$W"
  EX="$(git -C "$W" rev-parse --path-format=absolute --git-common-dir)/info/exclude"
  assert_eq 1 "$(grep -c '^/override.cfg$' "$EX")" "three runs add the exclude line once"
  mkdir -p "$W/game"; cp "$W/project.godot" "$W/game/project.godot"
  iso "$W/game"
  assert_contains "$EX" '^/game/override.cfg$' "a project in a subdir is excluded at its path"
  assert_file "$W/game/override.cfg" "the subdir project gets its file"
}

test_isolate_check() {
  UR="$TMP/ud-check"; R="$(iso_repo check)"; W="$(iso_wt "$R" check-wt)"
  iso "$W"
  assert_status 0 "--check passes after ensure" -- iso "$W" --check
  rm -f "$W/override.cfg"
  assert_status 1 "--check fails without the file" -- iso "$W" --check
  printf '[x]\n' > "$W/override.cfg"
  assert_status 1 "--check fails on a foreign file" -- iso "$W" --check
  printf '%s\n[application]\n%s\nconfig/custom_user_dir_name="StubGame-lanes-%s/other"\n' "$MARKER" "$USE" "$(h8 "$W")" > "$W/override.cfg"
  assert_status 1 "--check fails when it names another worktree" -- iso "$W" --check
  rm -f "$W/override.cfg"; iso "$W"
  printf '%s\n' "$USE" >> "$W/project.godot"
  assert_status 1 "--check fails when project.godot carries the use line" -- iso "$W" --check
  assert_status 1 "--check fails in the main checkout" -- iso "$R" --check
  assert_missing "$R/override.cfg" "--check writes nothing"
}

test_isolate_check_refuses_unknown_platform() {
  R="$(iso_repo unk)"; W="$(iso_wt "$R" unk-wt)"
  UR="$TMP/ud-unk"; iso "$W"
  mkdir -p "$TMP/unamebin"
  printf '#!/bin/sh\necho Linux\n' > "$TMP/unamebin/uname"; chmod +x "$TMP/unamebin/uname"
  rc=0; ( cd "$W" && env -u STUDIO_GODOT_USER_ROOT PATH="$TMP/unamebin:$PATH" OMEGA_STUDIO_ROOT="$STUDIO" sh "$ISO" --check ) || rc=$?
  assert_eq 1 "$rc" "an unknown platform without the seam is not isolated"
}

# mk_lanes DIR — the sweep fixture under data root $UR for worktree DIR.
mk_lanes() {
  LD="$UR/StubGame-lanes-$(h8 "$1")"
  mkdir -p "$LD/$(gid "$1")" "$LD/dead-old" "$LD/dead-new" "$TMP/ln-target"
  : > "$LD/f"
  ln -s "$TMP/ln-target" "$LD/ln"
  touch -t 202601010000 "$LD/dead-old" "$LD/$(gid "$1")" "$TMP/ln-target" "$LD/f"
}

test_isolate_sweep_dead_old_only() {
  UR="$TMP/ud-sweep"; R="$(iso_repo sweep)"; W="$(iso_wt "$R" sweep-wt)"
  mk_lanes "$W"
  iso "$W"
  assert_missing "$LD/dead-old" "a dead, old dir goes"
  assert_file "$LD/f" "a regular file stays"
  assert_eq "yes" "$([ -d "$LD/dead-new" ] && echo yes)" "a dead, new dir stays"
  assert_eq "yes" "$([ -d "$LD/$(gid "$W")" ] && echo yes)" "this worktree's own dir stays"
  assert_symlink "$LD/ln" "the symlink stays"
  assert_eq "yes" "$([ -d "$TMP/ln-target" ] && echo yes)" "the symlink target survives"
}

test_isolate_sweep_daily_stamp() {
  UR="$TMP/ud-daily"; R="$(iso_repo daily)"; W="$(iso_wt "$R" daily-wt)"
  mk_lanes "$W"
  touch "$R/.studio/gate.isolate-sweep"
  iso "$W"
  assert_eq "yes" "$([ -d "$LD/dead-old" ] && echo yes)" "a fresh stamp skips the sweep"
  touch -t 202601010000 "$R/.studio/gate.isolate-sweep"
  iso "$W"
  assert_missing "$LD/dead-old" "a two-day-old stamp sweeps"
  assert_eq "" "$(find "$R/.studio/gate.isolate-sweep" -mtime +0)" "and the stamp is touched"
}

test_isolate_sweep_paths_with_spaces() {
  UR="$TMP/App Support"; R="$(iso_repo spaces)"; W="$(iso_wt "$R" spaces-wt)"
  mkdir -p "$TMP/App"; : > "$TMP/App/keep"
  mk_lanes "$W"
  iso "$W"
  assert_file "$W/override.cfg" "the write works"
  assert_missing "$LD/dead-old" "the sweep works under a spaced root"
  assert_file "$LD/f" "nothing else under the root changes"
  assert_file "$TMP/App/keep" "a word-split rm would have taken the sibling sentinel"
  assert_eq "yes" "$([ -d "$TMP/ln-target" ] && echo yes)" "nothing outside it changes"
}

test_isolate_hash_keys_the_clone() {
  UR="$TMP/ud-clone"; R="$(iso_repo clonea)"
  git clone -q "$R" "$TMP/cloneb" >/dev/null 2>&1
  mkdir -p "$TMP/cloneb/.studio"
  WA="$(iso_wt "$R" clonea-wt)"
  g -C "$TMP/cloneb" worktree add -q -b br-b "$TMP/cloneb-wt" >/dev/null 2>&1
  mkdir -p "$TMP/cloneb-wt/.studio"; cp "$WA/.studio/config.json" "$TMP/cloneb-wt/.studio/config.json"
  (cd "$TMP/cloneb" && sh "$BIN/studio-state" init) >/dev/null 2>&1
  WB="$TMP/cloneb-wt"
  assert_eq "no" "$([ "$(h8 "$WA")" = "$(h8 "$WB")" ] && echo yes || echo no)" "two clones get different keys"
  mk_lanes "$WB"
  LB="$LD"
  iso "$WA"
  assert_eq "yes" "$([ -d "$LB/dead-old" ] && echo yes)" "clone A's sweep leaves clone B's lanes dir alone"
}

# Final review I4: the start scrub runs under the gate's lane
# (test_gate_start_scrub_under_the_lane), never in ensure, which runs before the
# gate and could rewrite project.godot beside a live Godot in the same worktree.
test_isolate_start_scrub() {
  UR="$TMP/ud-scrub"; R="$(iso_repo sscrub)"; W="$(iso_wt "$R" sscrub-wt)"
  printf '%s\n%s\n' "$USE" "$NAMELINE" >> "$W/project.godot"
  iso "$W" 2> "$TMP/err"; rc=$?
  assert_eq 0 "$rc" "ensure exits 0"
  assert_contains "$W/project.godot" "$USE" "ensure leaves project.godot alone: the start scrub is the gate's"
  assert_eq "" "$(cat "$TMP/err")" "and says nothing"
  assert_file "$W/override.cfg" "ensure still writes the override.cfg"
}

# Final review M6: a TMPDIR naming a missing dir (it happened on 10-08) never
# fails a scrub or a leak check: the temp files live in the git dir.
test_isolate_scrub_missing_tmpdir() {
  UR="$TMP/ud-notmp"; R="$(iso_repo notmp)"; W="$(iso_wt "$R" notmp-wt)"
  printf '%s\n%s\n' "$USE" "$NAMELINE" >> "$W/project.godot"
  out="$(export TMPDIR="$TMP/no-such-dir"; iso "$W" --scrub)"; rc=$?
  assert_eq 3 "$rc" "a missing TMPDIR: the scrub still removes (exit 3)"
  assert_eq "config/use_custom_user_dir, config/custom_user_dir_name" "$out" "and lists the keys"
  assert_eq "" "$(git -C "$W" diff -- project.godot)" "project.godot is back to HEAD"
  assert_eq 0 "$(ls -A "$(git -C "$W" rev-parse --path-format=absolute --git-dir)" | grep -c '^isolate-')" "no temp file is left in the git dir"
  R2="$(iso_repo notmp2)"
  printf '%s\n' "$NAMELINE" >> "$R2/project.godot"; git -C "$R2" add project.godot
  out="$(export TMPDIR="$TMP/no-such-dir"; iso "$TMP" --leaks "$R2")"; rc=$?
  assert_eq 3 "$rc" "a missing TMPDIR: the leak check still finds the leak (exit 3)"
  assert_eq "project.godot: config/custom_user_dir_name" "$out" "and names it"
  assert_eq 0 "$(ls -A "$(git -C "$R2" rev-parse --path-format=absolute --git-dir)" | grep -c '^isolate-')" "no temp file is left in the git dir"
  assert_missing "$TMP/no-such-dir" "the missing TMPDIR is not created"
}

test_isolate_scrub_modes() {
  UR="$TMP/ud-modes"; R="$(iso_repo modes)"; W="$(iso_wt "$R" modes-wt)"
  printf '%s\n%s\nconfig/icon="x"\n' "$USE" "$NAMELINE" >> "$W/project.godot"
  out="$(iso "$W" --scrub)"; rc=$?
  assert_eq 3 "$rc" "lines HEAD lacks: exit 3"
  assert_eq "config/use_custom_user_dir, config/custom_user_dir_name" "$out" "the keys are listed"
  assert_contains "$W/project.godot" 'config/icon="x"' "the other edits stay"
  assert_not_contains "$W/project.godot" 'use_custom_user_dir' "the use line is gone"
  # committed in HEAD: untouched
  R2="$(iso_repo modes2)"
  printf '%s\n%s\n' "$USE" "$NAMELINE" >> "$R2/project.godot"
  ( cd "$R2" && git add project.godot && g commit -q -m own ) >/dev/null 2>&1
  W2="$(iso_wt "$R2" modes2-wt)"
  cp "$W2/project.godot" "$TMP/pg2"
  iso "$W2" --scrub; rc=$?
  assert_eq 0 "$rc" "lines committed in HEAD: exit 0"
  assert_eq "" "$(diff "$TMP/pg2" "$W2/project.godot")" "and left untouched"
  # lane-off worktree, main checkout
  W3="$(iso_wt "$R" modes3-wt nokey)"
  printf '%s\n' "$USE" >> "$W3/project.godot"; cp "$W3/project.godot" "$TMP/pg3"
  iso "$W3" --scrub; rc=$?
  assert_eq 0 "$rc" "a lane-off worktree: exit 0"
  assert_eq "" "$(diff "$TMP/pg3" "$W3/project.godot")" "untouched"
  mkdir -p "$R/.studio"; printf '{"user_dir": "per-worktree"}\n' > "$R/.studio/config.json"
  printf '%s\n' "$USE" >> "$R/project.godot"; cp "$R/project.godot" "$TMP/pg4"
  iso "$R" --scrub; rc=$?
  assert_eq 0 "$rc" "the main checkout: exit 0"
  assert_eq "" "$(diff "$TMP/pg4" "$R/project.godot")" "untouched"
}

test_isolate_leaks_lists() {
  UR="$TMP/ud-leaks"; R="$(iso_repo leaks)"
  printf '%s\n' "$NAMELINE" >> "$R/project.godot"; git -C "$R" add project.godot
  out="$(iso "$TMP" --leaks "$R")"; rc=$?
  assert_eq 3 "$rc" "a staged name line is a leak"
  assert_eq "project.godot: config/custom_user_dir_name" "$out" "one <path>: <keys> per file"
  git -C "$R" reset -q; git -C "$R" checkout -q project.godot
  printf '%s\n' "$USE" >> "$R/project.godot"
  iso "$TMP" --leaks "$R" >/dev/null; rc=$?
  assert_eq 0 "$rc" "a use line without our override.cfg is the project's own"
  printf '%s\nx\n' "$MARKER" > "$R/override.cfg"
  iso "$TMP" --leaks "$R" >/dev/null; rc=$?
  assert_eq 3 "$rc" "a use line next to our override.cfg is a leak"
  R2="$(iso_repo leaks2)"
  printf '%s\n%s\n' "$USE" "$NAMELINE" >> "$R2/project.godot"
  ( cd "$R2" && git add project.godot && g commit -q -m own ) >/dev/null 2>&1
  printf '%s\nx\n' "$MARKER" > "$R2/override.cfg"
  iso "$TMP" --leaks "$R2" >/dev/null; rc=$?
  assert_eq 0 "$rc" "lines HEAD has are not leaks"
  # a project.godot new to HEAD (staged), then a repo with no commits at all
  R3="$(iso_repo leaks3)"
  mkdir -p "$R3/game"; printf '[application]\nconfig/name="G"\n%s\n' "$NAMELINE" > "$R3/game/project.godot"
  git -C "$R3" add game/project.godot
  out="$(iso "$TMP" --leaks "$R3")"; rc=$?
  assert_eq 3 "$rc" "a staged project.godot new to HEAD is a leak"
  assert_eq "game/project.godot: config/custom_user_dir_name" "$out" "and names its path"
  mkdir -p "$TMP/leaks4"; git -C "$TMP/leaks4" init -q -b main
  printf '[application]\n%s\n' "$NAMELINE" > "$TMP/leaks4/project.godot"; git -C "$TMP/leaks4" add project.godot
  iso "$TMP" --leaks "$TMP/leaks4" >/dev/null; rc=$?
  assert_eq 3 "$rc" "a repo with no commits: a staged name line is a leak"
  iso "$TMP" --leaks "$TMP/not-a-repo" >/dev/null 2>&1; rc=$?
  assert_eq 1 "$rc" "a non-repo is an error"
}

test_isolate_scrub_subdir_projects() {
  UR="$TMP/ud-subscrub"; R="$(iso_repo subscrub)"
  mkdir -p "$R/game"; printf '[application]\nconfig/name="G"\n' > "$R/game/project.godot"
  ( cd "$R" && git add game/project.godot && g commit -q -m game ) >/dev/null 2>&1
  W="$(iso_wt "$R" subscrub-wt)"
  printf '%s\n%s\n' "$USE" "$NAMELINE" >> "$W/game/project.godot"
  printf '%s\n' "$USE" >> "$W/project.godot"
  out="$(iso "$W" --scrub)"; rc=$?
  assert_eq 3 "$rc" "a subdir project is scrubbed too: exit 3"
  assert_eq "config/use_custom_user_dir, config/custom_user_dir_name" "$out" "the keys of both files, once each"
  assert_eq "" "$(git -C "$W" status --porcelain -- project.godot game/project.godot)" "both files are back to HEAD"
  iso "$W" --scrub >/dev/null; rc=$?
  assert_eq 0 "$rc" "a second scrub finds nothing"
}

test_isolate_exclude_with_spaces() {
  UR="$TMP/ud-exsp"; R="$(iso_repo exsp)"; W="$(iso_wt "$R" "exsp wt")"
  mkdir -p "$W/my game"; cp "$W/project.godot" "$W/my game/project.godot"
  iso "$W"; iso "$W/my game"
  assert_file "$W/override.cfg" "a worktree path with a space works"
  assert_file "$W/my game/override.cfg" "and a project dir with a space"
  assert_status 0 "the top override.cfg is ignored" -- git -C "$W" check-ignore -q override.cfg
  assert_status 0 "the spaced project's override.cfg is ignored" -- git -C "$W" check-ignore -q "my game/override.cfg"
  assert_contains "$(git -C "$W" rev-parse --path-format=absolute --git-common-dir)/info/exclude" '^/my game/override.cfg$' "the exclude line holds the spaced path"
}

test_studio_test_stderr_unchanged_when_not_opted() {
  UR="$TMP/ud-a5"; R="$(iso_repo a5)"; W="$(iso_wt "$R" a5-wt nokey)"
  mkdir -p "$TMP/a5-plain"; cp "$W/project.godot" "$TMP/a5-plain/project.godot"
  ( cd "$W" && STUDIO_GODOT_USER_ROOT="$UR" OMEGA_STUDIO_ROOT="$STUDIO" sh "$BIN/studio-test" ) > "$TMP/a5.out1" 2> "$TMP/a5.err1"; rc1=$?
  ( cd "$TMP/a5-plain" && STUDIO_GODOT_USER_ROOT="$UR" OMEGA_STUDIO_ROOT="$STUDIO" sh "$BIN/studio-test" ) > "$TMP/a5.out2" 2> "$TMP/a5.err2"; rc2=$?
  assert_eq "$rc2" "$rc1" "same exit status as a plain project"
  assert_eq "$(cat "$TMP/a5.err2")" "$(cat "$TMP/a5.err1")" "and equal to a plain project's"
  assert_missing "$W/override.cfg" "no file written"
}

test_isolate_user_root_production_default() {
  R="$(iso_repo prod)"; W="$(iso_wt "$R" prod-wt)"
  mkdir -p "$TMP/h"
  UR=""
  if [ "$(uname)" = Darwin ]; then
    LD="$TMP/h/Library/Application Support/StubGame-lanes-$(h8 "$W")"
    mkdir -p "$LD/dead-old"; touch -t 202601010000 "$LD/dead-old"
    ( cd "$W" && env -u STUDIO_GODOT_USER_ROOT HOME="$TMP/h" OMEGA_STUDIO_ROOT="$STUDIO" sh "$ISO" )
    assert_missing "$LD/dead-old" "unset, the sweep acts under \$HOME/Library/Application Support"
    assert_status 0 "--check passes with the production root" -- env -u STUDIO_GODOT_USER_ROOT HOME="$TMP/h" sh -c 'cd "$1" && sh "$2" --check' x "$W" "$ISO"
  else
    assert_status 1 "--check refuses a platform without the seam" -- env -u STUDIO_GODOT_USER_ROOT HOME="$TMP/h" sh -c 'cd "$1" && sh "$2" --check' x "$W" "$ISO"
  fi
}

test_dispatch_has_verb() {
  P="$TMP/has"; mkdir -p "$P/.studio"; printf '{"engine": "godot4"}\n' > "$P/.studio/config.json"
  assert_status 0 "--has isolate: the godot adapter has it" -- sh -c 'cd "$1" && OMEGA_STUDIO_ROOT="$2" sh "$3" --has isolate' x "$P" "$STUDIO" "$BIN/studio-dispatch"
  out="$( cd "$P" && OMEGA_STUDIO_ROOT="$STUDIO" sh "$BIN/studio-dispatch" --has nosuch 2>&1 )"; rc=$?
  assert_eq 1 "$rc" "--has nosuch exits 1"
  assert_eq "" "$out" "and says nothing"
  printf '{"engine": "nosuchengine"}\n' > "$P/.studio/config.json"
  out="$( cd "$P" && OMEGA_STUDIO_ROOT="$STUDIO" sh "$BIN/studio-dispatch" --has isolate 2>&1 )"; rc=$?
  assert_eq 1 "$rc" "an unknown engine exits 1"
  assert_eq "" "$out" "silently"
  out="$( cd "$P" && OMEGA_STUDIO_ROOT="$TMP/no-studio" sh "$BIN/studio-dispatch" --has isolate 2>&1 )"; rc=$?
  assert_eq 1 "$rc" "no studio root exits 1"
  assert_eq "" "$out" "silently"
}

test_studio_test_calls_isolate() {
  UR="$TMP/ud-st"; R="$(iso_repo st)"; W="$(iso_wt "$R" st-wt)"
  rc=0; ( cd "$W" && STUDIO_GODOT_USER_ROOT="$UR" OMEGA_STUDIO_ROOT="$STUDIO" sh "$BIN/studio-test" ) > "$TMP/out" 2>&1 || rc=$?
  assert_eq 3 "$rc" "no GUT: studio-test exits 3"
  assert_file "$W/override.cfg" "and the override.cfg was written first"
}

test_cfg_parity() {
  if [ ! -f "$BIN/gate-class.sh" ]; then
    TESTS_RUN=$((TESTS_RUN + 1)); _fail "bin/gate-class.sh exists (T1) to compare cfg blocks"
    return
  fi
  a="$(awk '/^# cfg-begin/,/^# cfg-end/' "$BIN/gate-class.sh")"
  b="$(awk '/^# cfg-begin/,/^# cfg-end/' "$STUDIO/engines/godot/cfg.sh")"
  assert_eq "$a" "$b" "the cfg block is byte-identical in gate-class.sh and cfg.sh"
  assert_eq "no" "$([ -z "$a" ] && echo yes || echo no)" "the block is not empty"
}

# ---- leak scrub in the gate (T10) ----
GATE="$BIN/studio-gate"
LEAK='printf "config/use_custom_user_dir=true\nconfig/custom_user_dir_name=\"StubGame-lanes-0badf00d/x\"\n" >> project.godot'
LEAKMSG='gate: project.godot gained the per-worktree user:// setting (config/use_custom_user_dir, config/custom_user_dir_name) — removed; this run is not trusted'
# gs_run DIR CMD — the exclusive form in DIR; $TMP/gs.err gets stderr, rc in $rc.
gs_run() {
  _gd="$1"; shift
  rc=0; ( cd "$_gd" && STUDIO_GATE_LOADAVG=0 OMEGA_STUDIO_ROOT="${GS_ROOT:-$STUDIO}" STUDIO_GODOT_USER_ROOT="$UR" sh "$GATE" x -- sh -c "$1" ) > /dev/null 2> "$TMP/gs.err" || rc=$?
}

# Final review I4: lines left before the run are removed under the lane, after
# admission and before the command, and do not fail it; a node run is not scrubbed.
test_gate_start_scrub_under_the_lane() {
  UR="$TMP/ud-gss"; R="$(iso_repo gss)"; W="$(iso_wt "$R" gss-wt)"
  printf '%s\n%s\n' "$USE" "$NAMELINE" >> "$W/project.godot"
  gs_run "$W" "grep -c custom_user_dir project.godot > '$TMP/gss.seen'; true"
  assert_eq 0 "$rc" "lines left before the run do not fail it"
  assert_eq 0 "$(cat "$TMP/gss.seen" 2>/dev/null)" "they are removed before the command runs"
  assert_eq "studio-test: project.godot carried the per-worktree user:// setting (config/use_custom_user_dir, config/custom_user_dir_name) — removed before the run" \
    "$(cat "$TMP/gs.err")" "the removal is announced with today's copy"
  assert_eq "" "$(git -C "$W" diff -- project.godot)" "project.godot is back to HEAD"
  mkdir -p "$W/web-tools/node_modules/.bin" "$W/web-tools/tests"
  printf 'test("a", () => {})\n' > "$W/web-tools/tests/a.test.ts"
  printf '#!/bin/sh\ngrep -c custom_user_dir ../project.godot > "%s"; exit 0\n' "$TMP/gss.node" > "$W/web-tools/node_modules/.bin/vitest"
  chmod +x "$W/web-tools/node_modules/.bin/vitest"
  printf '%s\n' "$USE" >> "$W/project.godot"
  rc=0; ( cd "$W/web-tools" && STUDIO_GATE_LOADAVG=0 OMEGA_STUDIO_ROOT="$STUDIO" STUDIO_GODOT_USER_ROOT="$UR" \
      sh "$GATE" vitest -- node_modules/.bin/vitest run --minWorkers=1 --maxWorkers=2 tests/a.test.ts ) > /dev/null 2> "$TMP/gs.err" || rc=$?
  assert_eq 0 "$rc" "a node run exits 0"
  assert_eq 1 "$(cat "$TMP/gss.node" 2>/dev/null)" "a node run is not scrubbed before it runs"
  assert_eq "" "$(cat "$TMP/gs.err")" "and nothing is said"
}

test_gate_scrub_removes_and_fails() {
  UR="$TMP/ud-gs1"; R="$(iso_repo gs1)"; W="$(iso_wt "$R" gs1-wt)"
  gs_run "$W" "$LEAK"
  assert_eq 1 "$rc" "a leak with a passing command exits 1"
  assert_eq "$LEAKMSG" "$(cat "$TMP/gs.err")" "the exact copy"
  assert_eq "" "$(git -C "$W" diff -- project.godot)" "the lines are removed"
  _sr="$(cd "$W" && sh "$BIN/studio-state" root 2>/dev/null)"
  assert_eq "1" "$(tail -n 1 "$_sr/.studio/gate.times" 2>/dev/null | awk '{ print $4 }')" "the row rc is 1"
}

test_gate_scrub_keeps_failing_status() {
  UR="$TMP/ud-gs2"; R="$(iso_repo gs2)"; W="$(iso_wt "$R" gs2-wt)"
  gs_run "$W" "$LEAK; exit 5"
  assert_eq 5 "$rc" "a failing status is kept"
  assert_eq "" "$(git -C "$W" diff -- project.godot)" "and the lines are removed"
  assert_eq "$LEAKMSG" "$(cat "$TMP/gs.err")" "with the stderr copy"
  _sr="$(cd "$W" && sh "$BIN/studio-state" root 2>/dev/null)"
  assert_eq "5" "$(tail -n 1 "$_sr/.studio/gate.times" 2>/dev/null | awk '{ print $4 }')" "and the row rc stays 5"
}

# gs_ended CMD ENV… — a leaking CMD ended by the cap (124) or TERM (143): still scrubbed, rc kept.
test_gate_scrub_signal_and_cap_ended() {
  UR="$TMP/ud-gs7"; R="$(iso_repo gs7)"; W="$(iso_wt "$R" gs7-wt)"
  rc=0; ( cd "$W" && STUDIO_GATE_MINUTES=1 STUDIO_GATE_SECONDS=6 STUDIO_GATE_LOADAVG=0 OMEGA_STUDIO_ROOT="$STUDIO" STUDIO_GODOT_USER_ROOT="$UR" \
      sh "$GATE" x -- sh -c "$LEAK; sleep 30" ) > /dev/null 2> "$TMP/gs.err" || rc=$?
  assert_eq 124 "$rc" "a cap-ended run keeps 124"
  assert_eq "" "$(git -C "$W" diff -- project.godot)" "and its lines are removed"
  assert_contains "$TMP/gs.err" "this run is not trusted" "and the copy is said"
  UR="$TMP/ud-gs8"; R="$(iso_repo gs8)"; W="$(iso_wt "$R" gs8-wt)"
  rm -f "$TMP/gs8.pid"
  ( cd "$W" && STUDIO_GATE_LOADAVG=0 OMEGA_STUDIO_ROOT="$STUDIO" STUDIO_GODOT_USER_ROOT="$UR" \
      sh -c 'echo $$ > "$0"; exec "$@"' "$TMP/gs8.pid" sh "$GATE" x -- sh -c "$LEAK; sleep 30" > /dev/null 2> "$TMP/gs.err"; echo $? > "$TMP/gs8.rc" ) &
  _i=0
  while [ "$_i" -lt 300 ] && ! grep -q "$USE" "$W/project.godot" 2>/dev/null; do sleep 0.1; _i=$((_i + 1)); done
  kill -TERM "$(cat "$TMP/gs8.pid")" 2>/dev/null
  _i=0
  while [ "$_i" -lt 300 ] && [ ! -s "$TMP/gs8.rc" ]; do sleep 0.1; _i=$((_i + 1)); done
  assert_eq 143 "$(cat "$TMP/gs8.rc" 2>/dev/null)" "a TERM-ended run keeps 143"
  assert_eq "" "$(git -C "$W" diff -- project.godot)" "and its lines are removed"
}

test_gate_scrub_skips_node_not_short() {
  UR="$TMP/ud-gs9"; R="$(iso_repo gs9)"; W="$(iso_wt "$R" gs9-wt)"
  mkdir -p "$W/web-tools/node_modules/.bin" "$W/web-tools/tests"
  printf 'test("a", () => {})\n' > "$W/web-tools/tests/a.test.ts"
  printf '#!/bin/sh\ncd .. && %s\n' "$LEAK" > "$W/web-tools/node_modules/.bin/vitest"
  chmod +x "$W/web-tools/node_modules/.bin/vitest"
  rc=0; ( cd "$W/web-tools" && STUDIO_GATE_LOADAVG=0 OMEGA_STUDIO_ROOT="$STUDIO" STUDIO_GODOT_USER_ROOT="$UR" \
      sh "$GATE" vitest -- node_modules/.bin/vitest run --minWorkers=1 --maxWorkers=2 tests/a.test.ts ) > /dev/null 2> "$TMP/gs.err" || rc=$?
  assert_eq 0 "$rc" "a node run in the main class (lane off) is not scrubbed: exit 0"
  assert_contains "$W/project.godot" "$USE" "the lines remain"
  assert_eq "" "$(cat "$TMP/gs.err")" "and nothing is said"
}

test_gate_scrub_leaves_head_keys() {
  UR="$TMP/ud-gs3"; R="$(iso_repo gs3)"
  ( cd "$R" && printf '%s\n%s\n' "$USE" "$NAMELINE" >> project.godot && git add project.godot && g commit -q -m keys )
  W="$(iso_wt "$R" gs3-wt)"
  gs_run "$W" 'true'
  assert_eq 0 "$rc" "HEAD has both lines: exit 0"
  assert_eq "" "$(git -C "$W" diff -- project.godot)" "untouched"
  assert_eq "" "$(cat "$TMP/gs.err")" "and no message"
}

test_gate_scrub_lane_off_and_main_untouched() {
  UR="$TMP/ud-gs4"; R="$(iso_repo gs4)"; W="$(iso_wt "$R" gs4-wt nokey)"
  gs_run "$W" "$LEAK"
  assert_eq 0 "$rc" "no user_dir key: exit 0"
  assert_contains "$W/project.godot" "$USE" "lines kept"
  assert_eq "" "$(cat "$TMP/gs.err")" "and nothing is said (A5)"
  mkdir -p "$R/.studio"; printf '{"engine": "godot4", "user_dir": "per-worktree"}\n' > "$R/.studio/config.json"
  gs_run "$R" "$LEAK"
  assert_eq 0 "$rc" "the main checkout: exit 0"
  assert_contains "$R/project.godot" "$USE" "and its lines are kept"
}

test_gate_scrub_skips_node_short() {
  UR="$TMP/ud-gs5"; R="$(iso_repo gs5)"; W="$(iso_wt "$R" gs5-wt)"
  printf '{"engine": "godot4", "user_dir": "per-worktree", "gate_short_lane": "on"}\n' > "$W/.studio/config.json"
  mkdir -p "$W/web-tools/node_modules/.bin" "$W/web-tools/tests"
  printf 'test("a", () => {})\n' > "$W/web-tools/tests/a.test.ts"
  printf '#!/bin/sh\ncd .. && %s\n' "$LEAK" > "$W/web-tools/node_modules/.bin/vitest"
  chmod +x "$W/web-tools/node_modules/.bin/vitest"
  rc=0; ( cd "$W/web-tools" && STUDIO_GATE_LOADAVG=0 OMEGA_STUDIO_ROOT="$STUDIO" STUDIO_GODOT_USER_ROOT="$UR" \
      sh "$GATE" vitest -- node_modules/.bin/vitest run --minWorkers=1 --maxWorkers=2 tests/a.test.ts ) > /dev/null 2> "$TMP/gs.err" || rc=$?
  assert_eq 0 "$rc" "a node short check is not scrubbed: exit 0"
  assert_contains "$W/project.godot" "$USE" "the lines remain (the commit guard covers it)"
}

test_gate_scrub_error_fails_closed() {
  UR="$TMP/ud-gs6"; R="$(iso_repo gs6)"; W="$(iso_wt "$R" gs6-wt)"
  SS="$TMP/gs-stub-studio"; mkdir -p "$SS/engines/godot"
  printf '{"engine": "godot4"}\n' > "$SS/studio.json"
  printf '#!/bin/sh\ncase "${1:-}" in --scrub) exit 1 ;; *) exit 0 ;; esac\n' > "$SS/engines/godot/isolate.sh"
  GS_ROOT="$SS" gs_run "$W" 'true'
  assert_eq 1 "$rc" "a scrub error fails closed"
  assert_eq "gate: the project.godot leak check failed (isolate --scrub exit 1) — this run is not trusted" "$(cat "$TMP/gs.err")" "with the exact copy"
}

# exclusive-scan: test_gate_scrub_signal_and_cap_ended out (static) a 6 s cap on a 30 s run (the leak is written long before it) and 30 s event polls on a file, no load-bound timing
# exclusive-scan: test_isolate_sweep_dead_old_only out (static) no clock; mtimes are set with touch -t
# exclusive-scan: test_isolate_sweep_daily_stamp out (static) no clock; mtimes are set with touch -t
run_tests test_isolate_writes_in_opted_linked_worktree test_isolate_never_in_main_checkout \
  test_isolate_needs_the_key test_isolate_run_fallback_key test_isolate_leaves_foreign_override \
  test_isolate_leaves_tracked_override test_isolate_rewrites_ours_on_rename test_isolate_exclude_once \
  test_isolate_check test_isolate_check_refuses_unknown_platform test_isolate_sweep_dead_old_only \
  test_isolate_sweep_daily_stamp test_isolate_sweep_paths_with_spaces test_isolate_hash_keys_the_clone \
  test_isolate_start_scrub test_isolate_scrub_modes test_isolate_leaks_lists \
  test_isolate_user_root_production_default test_dispatch_has_verb test_studio_test_calls_isolate test_cfg_parity \
  test_isolate_scrub_subdir_projects test_isolate_exclude_with_spaces test_studio_test_stderr_unchanged_when_not_opted \
  test_gate_scrub_removes_and_fails test_gate_scrub_keeps_failing_status test_gate_scrub_leaves_head_keys \
  test_gate_scrub_lane_off_and_main_untouched test_gate_scrub_skips_node_short test_gate_scrub_error_fails_closed \
  test_gate_scrub_signal_and_cap_ended test_gate_scrub_skips_node_not_short \
  test_isolate_scrub_missing_tmpdir test_gate_start_scrub_under_the_lane
