#!/bin/sh
# studio-docs-sync: checks out the run's docs revision into the story's branch
# and commits only when something changed. Every case builds its own temporary
# git repo under $TMP, never this checkout's.
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"
BIN="$REPO_ROOT/studios/game-dev/bin/studio-docs-sync"
STATE="$REPO_ROOT/studios/game-dev/bin/studio-state"
mk_tmp docs_sync_test
trap 'rm_tmp "$TMP"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# repo N — a repo whose branch `feat` holds v1 docs and whose commit
# $REV (on main) holds v2 docs, a v2 ledger and two Context files. Leaves
# $R checked out on feat with story a1 pointing at the spec and plan.
repo() {
  R="$TMP/r$1"; rm -rf "$R"; mkdir -p "$R"; cd "$R" || exit 9
  git init -q -b main; mkdir docs ctx .studio
  printf 'spec v1\n' > docs/s.md
  printf 'Context: ctx/one.md, ctx/two.md\n\n## Goal\nv1\n' > docs/p.md
  printf 'one v1\n' > ctx/one.md; printf 'two v1\n' > ctx/two.md
  git add -A; git commit -qm v1
  git branch feat
  printf 'spec v2\n' > docs/s.md
  printf 'Context: ctx/one.md, ctx/two.md\n\n## Goal\nv2\n' > docs/p.md
  printf 'one v2\n' > ctx/one.md; printf 'two v2\n' > ctx/two.md
  printf 'extra v2\n' > docs/extra.md
  mkdir -p .studio/ledger; printf 'ledger v2\n' > .studio/ledger/a1.md
  git add -A -f; git commit -qm v2
  REV="$(git rev-parse HEAD)"
  git checkout -q feat
  mkdir -p .studio/stories
  printf '# Studio State\n\nstage: execute\nspec: docs/s.md\nplan: docs/p.md\ntask: -\nbranch: -\nmilestone: prototype\n\n## Ledger\n' > .studio/stories/a1.md
  # the story file and .studio stay out of the index
  printf '.studio/stories/\n' >> .git/info/exclude
}
# sync ARGS — studio-docs-sync in $R; stdout sync.out, stderr sync.err, exit RC
sync() {
  RC=0
  ( cd "$R" && STUDIO_STORY=a1 STUDIO_DOCS_REV="$REV" sh "$BIN" "$@" ) > "$TMP/sync.out" 2> "$TMP/sync.err" || RC=$?
}
nhead() { git -C "$R" rev-list --count HEAD; }
subj() { git -C "$R" log -1 --format=%s; }

test_docs_sync_commits_on_change() {
  repo 1; n="$(nhead)"
  sync
  assert_eq "0" "$RC" "exit 0"
  assert_eq "$((n + 1))" "$(nhead)" "one new commit"
  assert_eq "docs(a1): plan at run docs $(printf '%.7s' "$REV")" "$(subj)" "the commit subject names the short rev"
  assert_eq "spec v2" "$(cat "$R/docs/s.md")" "the spec is the run's"
  assert_contains "$R/docs/p.md" "^v2$" "the plan is the run's"
  assert_missing "$R/.studio/ledger/a1.md" "the ledger is never touched without --new"
}
test_docs_sync_noop_when_same() {
  repo 2
  sync; n="$(nhead)"
  sync
  assert_eq "0" "$RC" "exit 0 on a second sync"
  assert_eq "$n" "$(nhead)" "no new commit when nothing differs"
}
test_docs_sync_new_adds_ledger() {
  repo 3
  sync --new
  assert_eq "0" "$RC" "exit 0"
  assert_eq "docs(a1): approved plan" "$(subj)" "the new-branch subject"
  assert_eq "ledger v2" "$(cat "$R/.studio/ledger/a1.md")" "the ledger comes from the docs revision"
}
test_docs_sync_context_paths() {
  repo 4
  sync docs/extra.md
  assert_eq "0" "$RC" "exit 0"
  assert_eq "one v2" "$(cat "$R/ctx/one.md")" "first Context file synced"
  assert_eq "two v2" "$(cat "$R/ctx/two.md")" "second Context file synced"
  assert_eq "extra v2" "$(cat "$R/docs/extra.md")" "an extra path is synced"
}
test_docs_sync_git_failure() {
  repo 5
  sync docs/no-such-file.md
  assert_eq "1" "$RC" "a git failure exits 1"
  assert_contains "$TMP/sync.err" "no-such-file" "git's stderr passes through"
}
test_docs_sync_usage() {
  repo 6
  RC=0; ( cd "$R" && STUDIO_STORY=a1 sh "$BIN" ) > /dev/null 2> "$TMP/sync.err" || RC=$?
  assert_eq "2" "$RC" "no STUDIO_DOCS_REV exits 2"
  RC=0; ( cd "$R" && STUDIO_DOCS_REV="$REV" sh "$BIN" ) > /dev/null 2> "$TMP/sync.err" || RC=$?
  assert_eq "2" "$RC" "no STUDIO_STORY exits 2"
  sync --bogus
  assert_eq "2" "$RC" "an unknown option exits 2"
}

run_tests test_docs_sync_commits_on_change test_docs_sync_noop_when_same \
  test_docs_sync_new_adds_ledger test_docs_sync_context_paths \
  test_docs_sync_git_failure test_docs_sync_usage
