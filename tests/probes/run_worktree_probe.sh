#!/bin/sh
# run_worktree_probe.sh — does a headless session launched from a RUN worktree
# keep working under the overnight runner's flags and deny rules (#39)?
#
# Not part of tests/run_all.sh: it spends a real model call. The design of
# concurrent runs launches each run's sessions from a run worktree
# (<root>/.claude/worktrees/run-<story>, branch run/<story>), while the story's
# code lives in its own worktree (<root>/.claude/worktrees/<story>-b). This
# probe proves, in a throwaway offline fixture, that one such session can:
#   1. enter the story worktree (EnterWorktree path:, else cd), write a file and
#      `git add` + `git commit` there — the commit lands on the story branch,
#      not on run/<story> or main;
#   2. `STUDIO_STORY=x studio-state set task 1/3` from the run worktree — the
#      story file is written in the MAIN checkout (the state root), and no
#      .studio/stories/ appears in the run worktree;
#   3. run `studio-test` (a shim over studio-gate) — the gate lock is taken in
#      the main checkout's .studio/ and the command sees the main root;
# all with the runner's launch flags (stream-json, --permission-mode auto,
# --permission-prompts none, --disallowedTools <studio-overnight deny-rules>)
# and with no permission denial. Everything lives under $PROBE_DIR; the real
# HOME and any real project are never touched.
#
# Usage: run_worktree_probe.sh [LAUNCHER]
#   LAUNCHER the claude launcher (default claude-gd, the runner's)
#   PROBE_FIXTURE_ONLY=1 builds the fixture and the deny-rule list, prints the
#   fixture paths and stops before the model call (no launcher needed).
# Exit 0 PASS · 1 FAIL · 2 usage or a missing launcher.
# Logs: $PROBE_DIR (default a mktemp dir): session.jsonl, session.err, gate.seen.
set -u
[ "$#" -le 1 ] || { echo "usage: run_worktree_probe.sh [LAUNCHER]" >&2; exit 2; }
L="${1:-claude-gd}"
ONLY="${PROBE_FIXTURE_ONLY:-}"
[ -n "$ONLY" ] || command -v "$L" >/dev/null 2>&1 || { echo "probe: $L not on PATH" >&2; exit 2; }
HERE="$(cd "$(dirname "$0")" && pwd -P)"
REPO="$(cd "$HERE/../.." && pwd -P)"
BIN="$REPO/studios/game-dev/bin"
[ -f "$BIN/studio-overnight" ] || { echo "probe: $BIN/studio-overnight not found" >&2; exit 2; }
D="${PROBE_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/run-worktree-probe.XXXXXX")}"
mkdir -p "$D"
D="$(cd "$D" && pwd -P)"
die() { echo "probe: $*" >&2; exit 2; }

# ---- the fixture: a bare origin and a project p, offline ----
mkdir -p "$D/bin"
export PATH="$D/bin:$BIN:$PATH"
git init -q --bare -b main "$D/origin.git" || die "bare origin"
git init -q -b main "$D/p" || die "project init"
P_DIR="$D/p"
git -C "$P_DIR" config user.name probe
git -C "$P_DIR" config user.email probe@example.invalid
git -C "$P_DIR" config commit.gpgsign false
git -C "$P_DIR" remote add origin "$D/origin.git"
printf 'probe\n' > "$P_DIR/README.md"
git -C "$P_DIR" add README.md
git -C "$P_DIR" commit -q -m "init" || die "first commit"
git -C "$P_DIR" push -q -u origin main || die "push main"
git -C "$P_DIR" remote set-head origin main >/dev/null || die "set-head"
( cd "$P_DIR" && sh "$BIN/studio-state" init >/dev/null ) || die "studio-state init"
git -C "$P_DIR" add .studio/config.json .gitignore
git -C "$P_DIR" commit -q -m "studio config" || die "config commit"
git -C "$P_DIR" push -q origin main || die "push config"
( cd "$P_DIR" && STUDIO_STORY=x sh "$BIN/studio-state" init >/dev/null \
    && STUDIO_STORY=x sh "$BIN/studio-state" set task 0/3 >/dev/null ) || die "story state"
git -C "$P_DIR" branch x-b || die "branch x-b"
git -C "$P_DIR" branch run/x || die "branch run/x"
git -C "$P_DIR" push -q origin x-b run/x || die "push branches"
mkdir -p "$P_DIR/.claude/worktrees"
SW="$P_DIR/.claude/worktrees/x-b"; RW="$P_DIR/.claude/worktrees/run-x"
git -C "$P_DIR" worktree add -q "$SW" x-b || die "story worktree"
git -C "$P_DIR" worktree add -q "$RW" run/x || die "run worktree"
_gc="$(git -C "$P_DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || _gc="$P_DIR/.git"
mkdir -p "$_gc/info"
grep -qxF '.claude/worktrees/' "$_gc/info/exclude" 2>/dev/null || printf '.claude/worktrees/\n' >> "$_gc/info/exclude"

# The studio-test shim: runs under the gate, records what the command sees.
cat > "$D/bin/studio-test" <<SHIM
#!/bin/sh
exec studio-gate studio-test -- sh -c 'root=\$(studio-state root); if [ -d "\$root/.studio/gate.lock" ]; then l=yes; else l=no; fi; printf "root=%s\nlock=%s\n" "\$root" "\$l" > "$D/gate.seen"'
SHIM
chmod +x "$D/bin/studio-test"

# The runner's deny rules, one --disallowedTools argument per line, as
# with_launch_args builds them.
RULES_TXT="$(sh "$BIN/studio-overnight" deny-rules --dir "$RW" 2>"$D/deny-rules.err")" \
  || die "studio-overnight deny-rules failed (see $D/deny-rules.err)"
[ -n "$RULES_TXT" ] || die "no deny rules"

P="You are a probe in a throwaway fixture. Do exactly these three steps, in order, and nothing else.
1. Enter the story checkout $P_DIR/.claude/worktrees/x-b the way the execute skill's 'Enter the feature checkout' says: EnterWorktree with path: when that tool is offered, else cd. Then write a file probe.txt there (any one line of text), and run: git add probe.txt && git commit -m \"probe: story commit\"
2. Run: STUDIO_STORY=x studio-state set task 1/3
3. Run: studio-test
Then reply with exactly one line: 'PROBE: done' if all three steps ran, or 'PROBE: denied <step number>' for the first step a permission denial stopped."

if [ -n "$ONLY" ]; then
  echo "fixture only: project=$P_DIR run-worktree=$RW story-worktree=$SW"
  echo "deny rules: $(printf '%s\n' "$RULES_TXT" | grep -c .)"
  echo "logs: $D"
  exit 0
fi

# ---- the session, launched from the run worktree with the runner's flags ----
set -- "$P" --model sonnet --output-format stream-json --verbose \
  --permission-mode auto --permission-prompts none --max-budget-usd 2 --disallowedTools
while IFS= read -r _r || [ -n "$_r" ]; do
  [ -n "$_r" ] || continue
  set -- "$@" "$_r"
done <<EOF
$RULES_TXT
EOF
( cd "$RW" && env STUDIO_STORY=x "$L" -p "$@" ) \
  > "$D/session.jsonl" 2> "$D/session.err" < /dev/null

# ---- the verdict ----
fail() { echo "FAIL: $1"; echo "logs: $D (session.jsonl, session.err, gate.seen)"; exit 1; }
[ "$(git -C "$P_DIR" log x-b -1 --format=%s 2>/dev/null)" = "probe: story commit" ] \
  || fail "x-b has no 'probe: story commit' as its newest commit"
git -C "$P_DIR" log run/x --format=%s 2>/dev/null | grep -qx 'probe: story commit' \
  && fail "run/x holds the story commit (committed in the run worktree)"
git -C "$P_DIR" log main --format=%s 2>/dev/null | grep -qx 'probe: story commit' \
  && fail "main holds the story commit"
grep -qx 'task: 1/3' "$P_DIR/.studio/stories/x.md" 2>/dev/null \
  || fail "p/.studio/stories/x.md does not say 'task: 1/3'"
[ ! -e "$RW/.studio/stories" ] || fail "run-x/.studio/stories exists (state written in the run worktree)"
[ -f "$D/gate.seen" ] || fail "studio-test did not run (no gate.seen)"
grep -qx "root=$P_DIR" "$D/gate.seen" || fail "gate.seen root is not $P_DIR ($(tr '\n' ' ' < "$D/gate.seen"))"
grep -qx 'lock=yes' "$D/gate.seen" || fail "gate lock not held in the main checkout while the command ran"
if grep '"permission_denials"' "$D/session.jsonl" | grep -v '"permission_denials":\[\]' | grep -q .; then
  fail "the session reports a permission denial"
fi
grep '"type":"result"' "$D/session.jsonl" | grep -q 'PROBE: done' \
  || fail "the reply line is not 'PROBE: done'"
echo PASS
echo "logs: $D (session.jsonl, session.err, gate.seen)"
exit 0
