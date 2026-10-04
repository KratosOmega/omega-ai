#!/bin/sh
# Tests for the Multica runtime wrappers (claude-multica, omega-multica-agent):
# deny list, link file, context file, argv order. Offline: stub `claude` and
# `claude-gd` recorders first on PATH, a temp HOME, a minimal PATH (#28).
set -u
REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd -P)"
. "$REPO_ROOT/tests/assert.sh"

# A clean, minimal environment: nothing from the caller's Multica/omega session.
for _v in $(env | sed -n 's/^\(MULTICA_[A-Za-z0-9_]*\)=.*/\1/p; s/^\(OMEGA_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$_v"; done
unset STUDIO_RUN_ORIGIN GIT_DIR GIT_WORK_TREE

TMP="$(mktemp -d)"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
FAKE="$TMP/fake"; REC="$TMP/rec"; HOME="$TMP/home"
WS="$TMP/ws/omeg-4-6d25f8ec1ce3/workdir"
PROJ="$TMP/proj"
mkdir -p "$FAKE" "$REC" "$HOME" "$WS"
PATH="$FAKE:/usr/bin:/bin"
export REC HOME PATH
MULTICA_TOKEN=mat_fake_for_tests; KEEP_ME=keep
OMEGA_PROJECT="$PROJ"
export MULTICA_TOKEN KEEP_ME OMEGA_PROJECT
GIT_AUTHOR_NAME=t; GIT_AUTHOR_EMAIL=t@t; GIT_COMMITTER_NAME=t; GIT_COMMITTER_EMAIL=t@t
export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL

CM="$REPO_ROOT/integrations/multica/bin/claude-multica"
AG="$REPO_ROOT/integrations/multica/bin/omega-multica-agent"
SO="$REPO_ROOT/studios/game-dev/bin/studio-overnight"
STATE="$REPO_ROOT/studios/game-dev/bin/studio-state"
DENY="$REPO_ROOT/integrations/multica/multica-deny.txt"
CTXSRC="$REPO_ROOT/integrations/multica/agent-context.md"
TASK=01a102e8-d4ad-7157-ac66-6d25f8ec1ce3
MARGS="-p --output-format stream-json --input-format stream-json --verbose --permission-mode bypassPermissions --disallowedTools AskUserQuestion"

# The stub recorder (convention reused by install_test.sh).
for _n in claude claude-gd; do
  cat > "$FAKE/$_n" <<'EOF'
#!/bin/sh
name="$(basename "$0")"
n=$(( $(cat "$REC/count" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$REC/count"
if [ "${1:-}" = "--version" ]; then
  printf '%s\n' "$@" > "$REC/$name.$n.argv"
  echo '2.1.288 (Claude Code)'; exit 0
fi
printf '%s\n' "$@" > "$REC/$name.$n.argv"
pwd -P > "$REC/$name.$n.pwd"
env | grep -E '^(MULTICA_|OMEGA_|STUDIO_RUN_ORIGIN=|KEEP_ME=)' | sort > "$REC/$name.$n.env"
exit 0
EOF
  chmod 755 "$FAKE/$_n"
done

# The studio project: git with a bare origin whose HEAD is main, studio-state init, committed.
git init -q --bare "$TMP/origin.git"
git -C "$TMP/origin.git" symbolic-ref HEAD refs/heads/main
mkdir -p "$PROJ"
git -C "$PROJ" init -q
git -C "$PROJ" symbolic-ref HEAD refs/heads/main
( cd "$PROJ" && sh "$STATE" init >/dev/null )
git -C "$PROJ" add -A
git -C "$PROJ" commit -q -m init
git -C "$PROJ" remote add origin "$TMP/origin.git"
git -C "$PROJ" push -q origin main 2>/dev/null
git -C "$PROJ" remote set-head origin main >/dev/null 2>&1
printf 'MULTICA-CTX\n' > "$TMP/claude-md"

# mini_repo NAME — a copy of the wrappers' layout for the failure cases.
mini_repo() {
  mkdir -p "$TMP/$1/studios/game-dev" "$TMP/$1/integrations/multica"
  cp -R "$REPO_ROOT/studios/game-dev/bin" "$TMP/$1/studios/game-dev/bin"
  cp -R "$REPO_ROOT/integrations/multica/bin" "$TMP/$1/integrations/multica/bin"
  cp "$DENY" "$CTXSRC" "$TMP/$1/integrations/multica/"
}

reset() {
  rm -rf "$REC" "$HOME/.claude-gamedev" "$WS/.omega-context.md" "$WS/CLAUDE.md"
  mkdir -p "$REC"
  chmod 755 "$WS"
}
# go DIR CMD… — run CMD in DIR; stdout, stderr and exit code to $TMP/out, $TMP/err, $RC.
go() {
  _gd="$1"; shift
  ( cd "$_gd" && "$@" ) >"$TMP/out" 2>"$TMP/err"; RC=$?
  [ -z "${DEBUG_ERR:-}" ] || sed 's/^/    stderr: /' "$TMP/err" >&2
}
calls() { cat "$REC/count" 2>/dev/null || echo 0; }
# errlines — the wrapper's own stderr lines (deny-rules' notes about a project
# with no merge_command pass through and are not counted).
errlines() { grep . "$TMP/err" | grep -vc '^studio-overnight: deny-rules: no '; }

# multica_rules — multica-deny.txt's rules of FILE ($1), one per line.
multica_rules() { sed 's/^[[:space:]]*//; s/[[:space:]]*$//' "$1" | grep -Ev '^(#|$)'; }
# deny_pairs DIR [DENYFILE] — the expected --disallowedTools pairs.
deny_pairs() {
  { sh "$SO" deny-rules --dir "$1" 2>/dev/null; multica_rules "${2:-$DENY}"; } | while IFS= read -r _r; do
    printf '%s\n%s\n' --disallowedTools "$_r"
  done
}
# expected FILE ARGS… — write ARGS one per line to FILE.
words_to() { _wf="$1"; shift; printf '%s\n' "$@" > "$_wf"; }

test_cm_version_passthrough() {
  reset
  go "$WS" "$CM" --version --x
  assert_eq 0 "$RC" "cm --version exits 0"
  assert_eq 1 "$(calls)" "cm --version: one claude call"
  printf '%s\n' --version > "$TMP/exp"
  assert_eq "" "$(diff "$TMP/exp" "$REC/claude.1.argv")" "cm --version: argv exactly --version"
}

test_cm_argv_order() {
  reset
  go "$WS" "$CM" $MARGS
  assert_eq 0 "$RC" "cm exits 0"
  { deny_pairs "$WS"; printf '%s\n' $MARGS; } > "$TMP/exp"
  assert_eq "" "$(diff "$TMP/exp" "$REC/claude.1.argv")" "cm argv: deny pairs then Multica's argv"
  assert_eq "$WS" "$(cat "$REC/claude.1.pwd")" "cm cwd is the workdir"
  env | grep -E '^(MULTICA_|OMEGA_|STUDIO_RUN_ORIGIN=|KEEP_ME=)' | sort > "$TMP/expenv"
  assert_eq "" "$(diff "$TMP/expenv" "$REC/claude.1.env")" "cm env identical to the caller's"
  assert_contains "$REC/claude.1.env" '^KEEP_ME=keep$' "cm env keeps KEEP_ME"
}

test_agent_version_no_project() {
  reset
  go "$WS" env -u OMEGA_PROJECT "$AG" --version
  assert_eq 0 "$RC" "agent --version exits 0"
  printf '%s\n' --version > "$TMP/exp"
  assert_eq "" "$(diff "$TMP/exp" "$REC/claude-gd.1.argv")" "agent --version: claude-gd argv exactly --version"
  assert_missing "$HOME/.claude-gamedev" "agent --version: no link file"
  assert_missing "$WS/.omega-context.md" "agent --version: no context file"
}

agent_refuses() {
  assert_eq 1 "$RC" "$1: exit 1"
  assert_eq 1 "$(errlines)" "$1: exactly one stderr line"
  assert_eq 0 "$(calls)" "$1: no claude-gd call"
  assert_missing "$HOME/.claude-gamedev" "$1: no link file"
}
test_agent_project_unset() {
  reset
  go "$WS" env -u OMEGA_PROJECT MULTICA_TASK_ID=$TASK "$AG" $MARGS
  agent_refuses "project unset"
}
test_agent_project_missing() {
  reset
  go "$WS" env OMEGA_PROJECT="$TMP/nope" MULTICA_TASK_ID=$TASK "$AG" $MARGS
  agent_refuses "project missing"
}
test_agent_project_not_studio() {
  reset
  mkdir -p "$TMP/plain"
  go "$WS" env OMEGA_PROJECT="$TMP/plain" MULTICA_TASK_ID=$TASK "$AG" $MARGS
  agent_refuses "project not a studio"
}

test_agent_link_file() {
  reset
  go "$WS" env MULTICA_TASK_ID=$TASK MULTICA_AGENT_ID=0a1b2c3d-agent "$AG" $MARGS
  assert_eq 0 "$RC" "link: exit 0"
  L="$HOME/.claude-gamedev/multica/links/$TASK"
  assert_file "$L" "link: file written"
  assert_eq 5 "$(grep -c . "$L")" "link: five lines"
  assert_eq "root=$(cd "$PROJ" && sh "$STATE" root)" "$(sed -n 1p "$L")" "link: root= is studio-state root"
  assert_eq "task=$TASK" "$(sed -n 2p "$L")" "link: task="
  assert_eq "agent=0a1b2c3d-agent" "$(sed -n 3p "$L")" "link: agent="
  assert_eq "workdir=$WS" "$(sed -n 4p "$L")" "link: workdir= is pwd -P"
  assert_contains "$L" '^written=[0-9]\{4\}-[0-9][0-9]-[0-9][0-9]T[0-9:]\{8\}Z$' "link: written= format"
  assert_eq "" "$(ls -A "$HOME/.claude-gamedev/multica/links" | grep '^\.')" "link: no temp file left"
}

test_agent_link_write_fails_warns() {
  reset
  mkdir -p "$HOME/.claude-gamedev/multica"
  : > "$HOME/.claude-gamedev/multica/links"
  go "$WS" env MULTICA_TASK_ID=$TASK "$AG" $MARGS
  assert_eq 0 "$RC" "link fails: session still launches"
  assert_eq 1 "$(calls)" "link fails: claude-gd called"
  assert_eq 1 "$(grep -c 'warning:' "$TMP/err")" "link fails: one warning line"
  assert_eq 1 "$(errlines)" "link fails: nothing else on stderr"
}

test_agent_bad_task_id() {
  reset
  go "$WS" env MULTICA_TASK_ID='../x' "$AG" $MARGS
  assert_eq 0 "$RC" "bad task id: launches"
  assert_eq 1 "$(grep -c 'warning:' "$TMP/err")" "bad task id: warning"
  assert_eq "" "$(find "$HOME/.claude-gamedev" -type f 2>/dev/null)" "bad task id: no file under multica/"
  assert_not_contains "$REC/claude-gd.1.env" 'STUDIO_RUN_ORIGIN' "bad task id: no STUDIO_RUN_ORIGIN"
}

test_agent_exports_run_origin() {
  reset
  go "$WS" env MULTICA_TASK_ID=$TASK "$AG" $MARGS
  assert_eq 1 "$(grep -c '^STUDIO_RUN_ORIGIN=' "$REC/claude-gd.1.env")" "origin: one STUDIO_RUN_ORIGIN line"
  assert_contains "$REC/claude-gd.1.env" "^STUDIO_RUN_ORIGIN=multica:$TASK\$" "origin: value"
  reset
  go "$WS" "$AG" $MARGS
  assert_not_contains "$REC/claude-gd.1.env" 'STUDIO_RUN_ORIGIN' "origin: none without a task id"
  reset
  go "$WS" env MULTICA_TASK_ID=$TASK "$CM" $MARGS
  assert_not_contains "$REC/claude.1.env" 'STUDIO_RUN_ORIGIN' "origin: claude-multica sets none"
}

test_agent_context_with_claude_md() {
  reset
  cp "$TMP/claude-md" "$WS/CLAUDE.md"
  go "$WS" "$AG" $MARGS
  { cat "$WS/CLAUDE.md"; printf '\n'; cat "$CTXSRC"; printf '\nMultica workdir: %s\n' "$WS"; } > "$TMP/exp"
  assert_eq 0 "$(cmp "$TMP/exp" "$WS/.omega-context.md" >/dev/null 2>&1; echo $?)" "context with CLAUDE.md: exact content"
  assert_contains "$WS/.omega-context.md" '^MULTICA-CTX$' "context with CLAUDE.md: has the CLAUDE.md text"
}
test_agent_context_without_claude_md() {
  reset
  go "$WS" "$AG" $MARGS
  { cat "$CTXSRC"; printf '\nMultica workdir: %s\n' "$WS"; } > "$TMP/exp"
  assert_eq 0 "$(cmp "$TMP/exp" "$WS/.omega-context.md" >/dev/null 2>&1; echo $?)" "context without CLAUDE.md: exact content"
}
test_agent_context_write_fails() {
  reset
  chmod 555 "$WS"
  go "$WS" "$AG" $MARGS
  chmod 755 "$WS"
  assert_eq 1 "$RC" "context write fails: exit 1"
  assert_eq 1 "$(errlines)" "context write fails: one stderr line"
  assert_eq 0 "$(calls)" "context write fails: no launch"
}

test_agent_argv_order() {
  reset
  go "$WS" "$AG" $MARGS
  assert_eq 0 "$RC" "argv order: exit 0"
  # D1a: the PRIMARY form; the inline fallback swaps the two words below
  # (--append-system-prompt-file <ctx>) for --append-system-prompt <text>.
  { deny_pairs "$PROJ"; printf '%s\n' --append-system-prompt-file "$WS/.omega-context.md" --add-dir "$WS"; printf '%s\n' $MARGS; } > "$TMP/exp"
  assert_eq "" "$(diff "$TMP/exp" "$REC/claude-gd.1.argv")" "argv order: deny, context, add-dir, Multica's argv"
  assert_eq "$PROJ" "$(cat "$REC/claude-gd.1.pwd")" "argv order: cwd is the project"
}

test_agent_rules_for_project_not_workdir() {
  reset
  go "$WS" "$AG" $MARGS
  assert_eq 1 "$(grep -Fxc 'Bash(git push * main)' "$REC/claude-gd.1.argv")" "project rules: push-to-default rule present"
}

test_agent_keeps_multica_env() {
  reset
  go "$WS" env MULTICA_TASK_ID=$TASK MULTICA_AGENT_ID=0a1b2c3d-agent MULTICA_DAEMON_PORT=19514 MULTICA_SERVER_URL=https://api.example.test "$AG" $MARGS
  for _k in MULTICA_TOKEN=mat_fake_for_tests MULTICA_TASK_ID=$TASK MULTICA_AGENT_ID=0a1b2c3d-agent MULTICA_DAEMON_PORT=19514 MULTICA_SERVER_URL=https://api.example.test; do
    assert_contains "$REC/claude-gd.1.env" "^$_k\$" "env: $_k reaches claude-gd"
  done
}

test_deny_failure_blocks_launch() {
  reset
  mini_repo m1
  printf '# nothing\n' > "$TMP/m1/studios/game-dev/bin/overnight-deny.txt"
  for _w in claude-multica omega-multica-agent; do
    go "$WS" "$TMP/m1/integrations/multica/bin/$_w" $MARGS
    assert_eq 1 "$RC" "deny failure ($_w): exit 1"
    assert_eq 1 "$(errlines)" "deny failure ($_w): one stderr line"
    assert_contains "$TMP/err" 'deny-rules failed' "deny failure ($_w): names deny-rules failed"
    assert_eq 0 "$(calls)" "deny failure ($_w): no stub call"
  done
}

test_deny_empty_blocks_launch() {
  reset
  mini_repo m2
  printf '#!/bin/sh\nexit 0\n' > "$TMP/m2/studios/game-dev/bin/studio-overnight"
  for _w in claude-multica omega-multica-agent; do
    go "$WS" "$TMP/m2/integrations/multica/bin/$_w" $MARGS
    assert_eq 1 "$RC" "deny empty ($_w): exit 1"
    assert_contains "$TMP/err" 'printed no rules' "deny empty ($_w): printed no rules"
    assert_eq 1 "$(errlines)" "deny empty ($_w): one stderr line"
    assert_eq 0 "$(calls)" "deny empty ($_w): no stub call"
  done
}

test_started_through_symlink() {
  reset
  mkdir -p "$TMP/lbin"
  ln -sf "$AG" "$TMP/lbin/omega-multica-agent"; ln -sf "$TMP/lbin/omega-multica-agent" "$TMP/lbin/oma2"
  ln -sf "$CM" "$TMP/lbin/claude-multica";      ln -sf "$TMP/lbin/claude-multica" "$TMP/lbin/cm2"
  for _w in claude-multica cm2; do
    reset
    go "$WS" "$TMP/lbin/$_w" $MARGS
    assert_eq 0 "$RC" "symlink ($_w): exit 0"
    assert_eq 1 "$(calls)" "symlink ($_w): one claude call"
    { deny_pairs "$WS"; printf '%s\n' $MARGS; } > "$TMP/exp"
    assert_eq "" "$(diff "$TMP/exp" "$REC/claude.1.argv")" "symlink ($_w): full deny list"
  done
  for _w in omega-multica-agent oma2; do
    reset
    go "$WS" "$TMP/lbin/$_w" $MARGS
    assert_eq 0 "$RC" "symlink ($_w): exit 0"
    assert_eq 1 "$(calls)" "symlink ($_w): one claude-gd call"
    { deny_pairs "$PROJ"; printf '%s\n' --append-system-prompt-file "$WS/.omega-context.md" --add-dir "$WS"; printf '%s\n' $MARGS; } > "$TMP/exp"
    assert_eq "" "$(diff "$TMP/exp" "$REC/claude-gd.1.argv")" "symlink ($_w): full deny list"
  done
}

test_rule_quoting_survives() {
  reset
  mini_repo m3
  printf '%s\n' 'Bash(it'"'"'s $HOME `x` "q")' >> "$TMP/m3/integrations/multica/multica-deny.txt"
  go "$WS" "$TMP/m3/integrations/multica/bin/claude-multica" $MARGS
  assert_eq 0 "$RC" "quoting: exit 0"
  printf '%s\n' --disallowedTools 'Bash(it'"'"'s $HOME `x` "q")' > "$TMP/exp"
  grep -Fx -B1 -- 'Bash(it'"'"'s $HOME `x` "q")' "$REC/claude.1.argv" > "$TMP/got"
  assert_eq "" "$(diff "$TMP/exp" "$TMP/got")" "quoting: the rule arrives byte-exact as one element"
}

test_multica_deny_rules_ac5() {
  for _r in 'Read(~/.multica/**)' 'Bash(*.multica/profiles*)' 'Bash(*multica*--profile*)' 'Bash(*multica login*)' \
            'Bash(*multica auth*)' 'Bash(*multica setup*)' 'Bash(*multica config*)' 'Bash(*multica workspace switch*)' \
            'Bash(*MULTICA_TOKEN=*)' 'Bash(*multica*--server-url*)' 'Bash(*~/.multica*)' 'Bash(*$HOME/.multica*)' \
            'Bash(*${HOME}/.multica*)' 'Bash(*/Users/*/.multica*)'; do
    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -Fxq -- "$_r" "$DENY"; then _pass "deny file has $_r"; else _fail "deny file lacks $_r"; fi
  done
}

test_cm_rules_from_pwd() {
  reset
  go "$PROJ" "$CM" $MARGS
  assert_eq 0 "$RC" "cm rules from pwd: exit 0"
  assert_eq 1 "$(grep -Fxc 'Bash(git push * main)' "$REC/claude.1.argv")" "cm rules from pwd: project's push rule present"
  { deny_pairs "$PROJ"; printf '%s\n' $MARGS; } > "$TMP/exp"
  assert_eq "" "$(diff "$TMP/exp" "$REC/claude.1.argv")" "cm rules from pwd: argv"
}

test_multica_argv_survives_eval() {
  reset
  go "$WS" "$CM" -p --model 'a b*' --x "it's \$HOME"
  { deny_pairs "$WS"; printf '%s\n' -p --model 'a b*' --x "it's \$HOME"; } > "$TMP/exp"
  assert_eq "" "$(diff "$TMP/exp" "$REC/claude.1.argv")" "cm: Multica's argv elements stay whole"
  reset
  go "$WS" "$AG" -p --model 'a b*' --x "it's \$HOME"
  { deny_pairs "$PROJ"; printf '%s\n' --append-system-prompt-file "$WS/.omega-context.md" --add-dir "$WS" -p --model 'a b*' --x "it's \$HOME"; } > "$TMP/exp"
  assert_eq "" "$(diff "$TMP/exp" "$REC/claude-gd.1.argv")" "agent: Multica's argv elements stay whole"
}

test_home_multica_rules_literal() {
  reset
  go "$WS" "$CM" $MARGS
  for _r in 'Bash(*~/.multica*)' 'Bash(*$HOME/.multica*)' 'Bash(*${HOME}/.multica*)' 'Bash(*/Users/*/.multica*)'; do
    assert_eq 1 "$(grep -Fxc -- "$_r" "$REC/claude.1.argv")" "home rule arrives literal: $_r"
  done
}

test_deny_comment_only_blocks_launch() {
  reset
  mini_repo m4
  printf '# only a comment\n\n' > "$TMP/m4/integrations/multica/multica-deny.txt"
  for _w in claude-multica omega-multica-agent; do
    go "$WS" "$TMP/m4/integrations/multica/bin/$_w" $MARGS
    assert_eq 1 "$RC" "deny comment-only ($_w): exit 1"
    assert_eq 1 "$(errlines)" "deny comment-only ($_w): one stderr line"
    assert_eq 0 "$(calls)" "deny comment-only ($_w): no launch"
  done
}

test_agent_context_unreadable_dies() {
  reset
  mini_repo m5
  chmod 000 "$TMP/m5/integrations/multica/agent-context.md"
  go "$WS" "$TMP/m5/integrations/multica/bin/omega-multica-agent" $MARGS
  chmod 644 "$TMP/m5/integrations/multica/agent-context.md"
  assert_eq 1 "$RC" "agent-context unreadable: exit 1"
  assert_eq 1 "$(errlines)" "agent-context unreadable: one stderr line"
  assert_eq 0 "$(calls)" "agent-context unreadable: no launch"
  reset
  cp "$TMP/claude-md" "$WS/CLAUDE.md"; chmod 000 "$WS/CLAUDE.md"
  go "$WS" "$AG" $MARGS
  chmod 644 "$WS/CLAUDE.md"
  assert_eq 1 "$RC" "CLAUDE.md unreadable: exit 1"
  assert_eq 1 "$(errlines)" "CLAUDE.md unreadable: one stderr line"
  assert_eq 0 "$(calls)" "CLAUDE.md unreadable: no launch"
}

test_agent_id_newline_no_injection() {
  reset
  go "$WS" env MULTICA_TASK_ID=$TASK MULTICA_AGENT_ID='a1
workdir=/etc' "$AG" $MARGS
  L="$HOME/.claude-gamedev/multica/links/$TASK"
  assert_eq 5 "$(grep -c . "$L")" "agent id newline: still five lines"
  assert_eq 1 "$(grep -c '^workdir=' "$L")" "agent id newline: one workdir= line"
  assert_eq "workdir=$WS" "$(sed -n 4p "$L")" "agent id newline: workdir is the real one"
}

test_claude_md_symlink_outside_skipped() {
  reset
  printf 'SECRET-TOKEN\n' > "$TMP/outside"
  ln -s "$TMP/outside" "$WS/CLAUDE.md"
  go "$WS" "$AG" $MARGS
  assert_eq 0 "$RC" "CLAUDE.md symlink outside: launches"
  assert_not_contains "$WS/.omega-context.md" 'SECRET-TOKEN' "CLAUDE.md symlink outside: not copied"
  assert_eq 1 "$(grep -c 'warning:' "$TMP/err")" "CLAUDE.md symlink outside: one warning"
  reset
  printf 'INSIDE-MD\n' > "$WS/real.md"
  ln -s real.md "$WS/CLAUDE.md"
  go "$WS" "$AG" $MARGS
  assert_not_contains "$WS/.omega-context.md" 'INSIDE-MD' "CLAUDE.md symlink inside: skipped too (a CLAUDE.md is a plain file)"
  assert_eq 1 "$(grep -c 'symlink' "$TMP/err")" "CLAUDE.md symlink inside: one warning"
  rm -f "$WS/real.md"
}

# M1 (T3 N1): the two shapes that passed the old logical-path check.
test_claude_md_bypass_shapes_skipped() {
  reset
  mkdir -p "$TMP/outer/inner"
  printf 'SECRET-ABOVE\n' > "$TMP/outer/secret"
  ln -s "$TMP/outer/inner" "$WS/sub"
  ln -s sub/../secret "$WS/CLAUDE.md"
  go "$WS" "$AG" $MARGS
  assert_eq 0 "$RC" "CLAUDE.md via sub/../secret: launches"
  assert_not_contains "$WS/.omega-context.md" 'SECRET-ABOVE' "CLAUDE.md via sub/../secret: not copied"
  rm -f "$WS/sub"
  reset
  printf 'SECRET-HARD\n' > "$TMP/hardsrc"
  ln "$TMP/hardsrc" "$WS/CLAUDE.md"
  go "$WS" "$AG" $MARGS
  assert_eq 0 "$RC" "CLAUDE.md hard link: launches"
  assert_not_contains "$WS/.omega-context.md" 'SECRET-HARD' "CLAUDE.md hard link: not copied"
  assert_eq 1 "$(grep -c 'hard links' "$TMP/err")" "CLAUDE.md hard link: one warning"
  rm -f "$TMP/hardsrc"
}

# resolve_path follows a `..` physically (the defense under the symlink rule).
test_resolve_path_is_physical() {
  mkdir -p "$TMP/rp/outer/inner" "$TMP/rp/ws"
  : > "$TMP/rp/outer/secret"
  ln -s "$TMP/rp/outer/inner" "$TMP/rp/ws/sub"
  got="$( self="$AG"; WRAPPER=t; . "$REPO_ROOT/integrations/multica/bin/wrapper-lib.sh"; resolve_path "$TMP/rp/ws/sub/../secret" )"
  assert_eq "$TMP/rp/outer/secret" "$got" "resolve_path: .. after a symlinked dir is physical"
}

# M2: the context temp file has an unpredictable name (mktemp), inside the workdir.
test_context_temp_file_uses_mktemp() {
  reset
  mkdir -p "$TMP/mkstub"
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/mktemp.args"\nexec /usr/bin/mktemp "$@"\n' "$TMP" > "$TMP/mkstub/mktemp"
  chmod 755 "$TMP/mkstub/mktemp"
  rm -f "$TMP/mktemp.args"
  go "$WS" env PATH="$TMP/mkstub:$PATH" "$AG" $MARGS
  assert_eq 0 "$RC" "launches"
  assert_contains "$TMP/mktemp.args" "^$WS/.omega-context.[X]*\$" "the temp file comes from mktemp in the workdir"
  assert_eq "" "$(ls -A "$WS" | grep 'omega-context.md.tmp')" "no predictable temp name"
}

test_cm_drops_inherited_origin() {
  reset
  go "$WS" env STUDIO_RUN_ORIGIN=stale:1 "$CM" $MARGS
  assert_eq 0 "$RC" "cm exits 0"
  assert_not_contains "$REC/claude.1.env" 'STUDIO_RUN_ORIGIN' "cm drops an inherited origin"
  assert_contains "$REC/claude.1.env" '^KEEP_ME=keep$' "cm keeps the rest of the env"
}

test_context_path_planted() {
  reset
  mkdir -p "$TMP/planted"
  ln -s "$TMP/planted" "$WS/.omega-context.md"
  go "$WS" "$AG" $MARGS
  assert_eq 0 "$RC" "context symlink to dir: launches"
  assert_eq "" "$(ls -A "$TMP/planted")" "context symlink to dir: nothing written through it"
  assert_eq 1 "$(test -f "$WS/.omega-context.md" && test ! -L "$WS/.omega-context.md" && echo 1)" "context symlink to dir: replaced by a file"
  reset
  printf 'victim\n' > "$TMP/victim"
  ln -s "$TMP/victim" "$WS/.omega-context.md"
  go "$WS" "$AG" $MARGS
  assert_eq "victim" "$(cat "$TMP/victim")" "context symlink to file: target untouched"
  reset
  mkdir -p "$WS/.omega-context.md"
  go "$WS" "$AG" $MARGS
  assert_eq 1 "$RC" "context is a dir: exit 1"
  assert_eq 1 "$(errlines)" "context is a dir: one stderr line"
  assert_eq 0 "$(calls)" "context is a dir: no launch"
  rm -rf "$WS/.omega-context.md"
}

test_project_unsearchable_one_line() {
  reset
  mkdir -p "$TMP/locked"
  chmod 600 "$TMP/locked"
  go "$WS" env OMEGA_PROJECT="$TMP/locked" "$AG" $MARGS
  chmod 755 "$TMP/locked"
  assert_eq 1 "$RC" "project unsearchable: exit 1"
  assert_eq 1 "$(errlines)" "project unsearchable: one stderr line"
  assert_eq 0 "$(calls)" "project unsearchable: no launch"
}

test_agent_ignores_inherited_origin() {
  reset
  go "$WS" env STUDIO_RUN_ORIGIN=stale:1 "$AG" $MARGS
  assert_not_contains "$REC/claude-gd.1.env" 'STUDIO_RUN_ORIGIN' "inherited origin dropped (no task id)"
  reset
  go "$WS" env STUDIO_RUN_ORIGIN=stale:1 MULTICA_TASK_ID='../x' "$AG" $MARGS
  assert_not_contains "$REC/claude-gd.1.env" 'STUDIO_RUN_ORIGIN' "inherited origin dropped (bad task id)"
}

test_sq_non_utf8() {
  reset
  mini_repo m6
  printf 'Bash(caf\351 \377*)\n' >> "$TMP/m6/integrations/multica/multica-deny.txt"
  LC_ALL=en_US.UTF-8; export LC_ALL
  go "$WS" "$TMP/m6/integrations/multica/bin/claude-multica" $MARGS
  unset LC_ALL
  assert_eq 0 "$RC" "non-UTF-8 rule: exit 0"
  printf 'Bash(caf\351 \377*)\n' > "$TMP/exp"
  assert_eq 1 "$(LC_ALL=C grep -cF -- "$(cat "$TMP/exp")" "$REC/claude.1.argv")" "non-UTF-8 rule arrives byte-exact"
}

test_scripts_parse() {
  _m="$REPO_ROOT/integrations/multica"
  for _f in "$_m/bin/claude-multica" "$_m/bin/omega-multica-agent" "$_m/bin/wrapper-lib.sh" "$_m/tests/run.sh" \
            "$_m/install.sh" "$_m/uninstall.sh" "$_m/tests/install_test.sh" "$_m/tests/stub-security" \
            "$_m"/probes/*.sh "$_m/probes/p1-agent-wrapper"; do
    assert_status 0 "sh -n $(basename "$_f")" -- sh -n "$_f"
  done
  for _f in "$_m/bin/claude-multica" "$_m/bin/omega-multica-agent" "$_m/bin/multica-bridge" "$_m/tests/run.sh" "$_m"/probes/*.sh \
            "$_m/install.sh" "$_m/uninstall.sh" "$_m/tests/stub-launchctl" "$_m/tests/stub-security"; do
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ -x "$_f" ]; then _pass "$(basename "$_f") is executable"; else _fail "$(basename "$_f") is not executable"; fi
  done
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ ! -x "$_m/bin/wrapper-lib.sh" ]; then _pass "wrapper-lib.sh is not executable"; else _fail "wrapper-lib.sh is executable"; fi
}

run_tests test_cm_version_passthrough test_cm_argv_order \
  test_agent_version_no_project test_agent_project_unset test_agent_project_missing test_agent_project_not_studio \
  test_agent_link_file test_agent_link_write_fails_warns test_agent_bad_task_id test_agent_exports_run_origin \
  test_agent_context_with_claude_md test_agent_context_without_claude_md test_agent_context_write_fails \
  test_agent_argv_order test_agent_rules_for_project_not_workdir test_agent_keeps_multica_env \
  test_deny_failure_blocks_launch test_deny_empty_blocks_launch test_started_through_symlink \
  test_rule_quoting_survives test_multica_deny_rules_ac5 test_cm_rules_from_pwd test_multica_argv_survives_eval \
  test_home_multica_rules_literal test_deny_comment_only_blocks_launch test_agent_context_unreadable_dies \
  test_agent_id_newline_no_injection test_claude_md_symlink_outside_skipped test_claude_md_bypass_shapes_skipped test_resolve_path_is_physical \
  test_context_temp_file_uses_mktemp test_cm_drops_inherited_origin test_context_path_planted \
  test_project_unsearchable_one_line test_agent_ignores_inherited_origin test_sq_non_utf8 test_scripts_parse
