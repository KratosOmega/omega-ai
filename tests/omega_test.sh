#!/bin/sh
# Tests for the omega global plugin: manifest, skill stubs, marketplace
# manifest, omega-mode, omega-caffeine, and the three hooks. Runs without a
# config root: omega-mode and the hooks are pointed at a temporary
# CLAUDE_CONFIG_DIR. omega-caffeine is run with a fake caffeinate first on
# PATH; every process it starts is killed on exit.
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"
. "$REPO_ROOT/lib/common.sh"

OMEGA="$REPO_ROOT/shared/omega"
MODE="$OMEGA/bin/omega-mode"
CAF="$OMEGA/bin/omega-caffeine"
TMP="$(mktemp -d)"
CAF_PIDS=""
# reap — kill every keep-awake process the tests started.
reap() { for _p in $CAF_PIDS; do kill "$_p" 2>/dev/null; done; CAF_PIDS=""; }
trap 'reap; rm -rf "$TMP"' EXIT
CFG="$TMP/cfg"

# A fake caffeinate that accepts any arguments and lives for a minute, and a
# PATH with only the utilities omega-caffeine itself needs — no caffeinate,
# no systemd-inhibit — for the unsupported case. The fake must not exec its
# sleep: omega-caffeine recognises its process by the argument list, which
# is `/bin/sh …/fakebin/caffeinate …` only while the script itself lives.
mkdir -p "$TMP/fakebin" "$TMP/nobin"
cat > "$TMP/fakebin/caffeinate" <<'FAKE'
#!/bin/sh
sleep 60 & c=$!
trap 'kill $c 2>/dev/null; exit 0' TERM INT
wait $c
FAKE
chmod +x "$TMP/fakebin/caffeinate"
for _u in sh awk sed dirname sleep nohup mkdir mv rm cat ps grep uname; do
  ln -s "$(command -v "$_u")" "$TMP/nobin/$_u"
done

# first_field FILE KEY — the value of a single-line "KEY: value" frontmatter
# field; empty when absent.
first_field() {
  sed -n "s/^$2:[[:space:]]*//p" "$1" | head -n 1
}

# valid_json FILE — jq when present, otherwise a shape check: first non-blank
# character '{', last '}'.
valid_json() {
  if command -v jq >/dev/null 2>&1; then
    jq -e . "$1" >/dev/null 2>&1
  else
    _first="$(tr -d '[:space:]' < "$1" | cut -c1)"
    _last="$(tr -d '[:space:]' < "$1" | tail -c 1)"
    [ "$_first" = "{" ] && [ "$_last" = "}" ]
  fi
}

test_plugin_files() {
  assert_file "$OMEGA/.claude-plugin/plugin.json" "omega has a plugin manifest"
  assert_status 0 "omega plugin.json is valid JSON" -- valid_json "$OMEGA/.claude-plugin/plugin.json"
  assert_eq "omega" "$(json_field "$OMEGA/.claude-plugin/plugin.json" name)" \
    "omega plugin.json names the omega namespace"
  assert_eq "0.1.0" "$(json_field "$OMEGA/.claude-plugin/plugin.json" version)" "omega plugin.json is version 0.1.0"
  for s in handoff parallel local-merge integration autopilot delegate; do
    assert_file "$OMEGA/skills/$s/SKILL.md" "omega ships the $s skill"
  done
  assert_contains "$OMEGA/.claude-plugin/plugin.json" "autopilot, delegate\." "omega plugin.json names the six skills"
  assert_missing "$OMEGA/requires.txt" "omega declares no hard dependencies"
  assert_missing "$OMEGA/settings.json" "omega has no settings.json"
}

test_skill_stubs() {
  for s in handoff parallel local-merge integration autopilot delegate; do
    f="$OMEGA/skills/$s/SKILL.md"
    assert_eq "---" "$(head -n 1 "$f")" "omega:$s starts with frontmatter"
    assert_eq "$s" "$(first_field "$f" name)" "omega:$s frontmatter name matches its directory"
    TESTS_RUN=$((TESTS_RUN + 1))
    case "$(first_field "$f" description)" in
      "Use when"*) _pass "omega:$s description starts with 'Use when'" ;;
      *) _fail "omega:$s description starts with 'Use when'" ;;
    esac
  done
  for s in parallel local-merge integration autopilot delegate; do
    assert_contains "$OMEGA/skills/$s/SKILL.md" "This mode changes how work is scheduled, saved, merged or stopped." \
      "omega:$s carries the precedence contract"
    assert_contains "$OMEGA/skills/$s/SKILL.md" "omega-mode" "omega:$s sets or clears its mode through omega-mode"
  done
}

test_marketplace() {
  m="$REPO_ROOT/.claude-plugin/marketplace.json"
  assert_file "$m" "the repository has a marketplace manifest"
  assert_status 0 "marketplace.json is valid JSON" -- valid_json "$m"
  assert_eq "omega-ai" "$(json_field "$m" name)" "the marketplace is named omega-ai"
  assert_contains "$m" '"name": "omega"' "the marketplace publishes the omega plugin"
  assert_contains "$m" 'autopilot, delegate\.' "the marketplace description names the six skills"
  src="$(sed -n 's/.*"source"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$m" | head -n 1)"
  assert_eq "./shared/omega" "$src" "the omega plugin's source is ./shared/omega"
  assert_file "$REPO_ROOT/${src#./}/.claude-plugin/plugin.json" "the marketplace source resolves to the plugin"
}

# mode ARGS... — omega-mode against the temporary config root.
mode() {
  CLAUDE_CONFIG_DIR="$CFG" sh "$MODE" "$@"
}

# caffeine ARGS... — omega-caffeine against the temporary config root, the
# fake caffeinate first on PATH.
caffeine() {
  CLAUDE_CONFIG_DIR="$CFG" PATH="$TMP/fakebin:$PATH" sh "$CAF" "$@"
}

# caffeine_pid SESSION — the pid recorded on the session's autopilot line;
# empty when none.
caffeine_pid() {
  mode --session "$1" show | awk '
    $1 == "autopilot" { for (i = 2; i <= NF; i++) if (sub(/^caffeine=/, "", $i)) print $i }'
}

# wait_dead PID — up to five seconds for PID to be gone; a kill is
# asynchronous and the process is no child of this shell.
wait_dead() {
  _i=0
  while kill -0 "$1" 2>/dev/null && [ "$_i" -lt 50 ]; do sleep 0.1; _i=$((_i + 1)); done
}

test_mode_round_trip() {
  rm -rf "$CFG"
  assert_status 0 "set parallel max=3 succeeds" -- mode --session t1 set parallel max=3
  assert_status 0 "set local-merge succeeds" -- mode --session t1 set local-merge
  assert_eq "$(printf 'parallel max=3\nlocal-merge')" "$(mode --session t1 show)" "show prints both lines in order"
  assert_eq "$CFG/omega/modes/t1" "$(mode --session t1 path)" "path names the session's file"
  mode --session t1 set parallel
  assert_eq "$(printf 'parallel\nlocal-merge')" "$(mode --session t1 show)" "set replaces the mode's line in place"
  mode --session t1 set parallel max=2
  assert_eq "$(printf 'parallel max=2\nlocal-merge')" "$(mode --session t1 show)" "set replaces it again"
  mode --session t1 clear parallel
  assert_eq "local-merge" "$(mode --session t1 show)" "clear removes one mode"
  mode --session t1 clear local-merge
  assert_missing "$CFG/omega/modes/t1" "clearing the last mode deletes the file"
  mode --session t1 set autopilot
  mode --session t1 clear --all
  assert_missing "$CFG/omega/modes/t1" "clear --all deletes the file"
  assert_status 0 "show on a missing file exits 0" -- mode --session t1 show
  assert_eq "" "$(mode --session t1 show)" "show on a missing file prints nothing"
  assert_status 0 "clear on a missing file exits 0" -- mode --session t1 clear parallel
  mode set parallel max=3 --session t2
  assert_eq "parallel max=3" "$(mode --session t2 show)" "--session is accepted after the verb"
  env CLAUDE_CODE_SESSION_ID=t3 CLAUDE_CONFIG_DIR="$CFG" sh "$MODE" set local-merge
  assert_eq "local-merge" "$(mode --session t3 show)" "the session id falls back to CLAUDE_CODE_SESSION_ID"
  mode --session t3 set integration slug=ui-rework
  assert_eq "$(printf 'local-merge\nintegration slug=ui-rework')" "$(mode --session t3 show)" "a value with a dash round-trips"
  assert_eq "2" "$(ls "$CFG/omega/modes" | wc -l | tr -d ' ')" "no temporary file is left behind (t2 and t3 only)"
}

test_mode_validation() {
  rm -rf "$CFG"
  assert_status 1 "no session id exits 1" -- env CLAUDE_CODE_SESSION_ID= CLAUDE_CONFIG_DIR="$CFG" sh "$MODE" show
  assert_status 1 "a session id with a slash is refused" -- mode --session ../x show
  assert_status 1 "--session without a value exits 1" -- mode show --session
  assert_status 1 "no verb exits 1" -- mode --session t9
  assert_status 1 "an unknown verb exits 1" -- mode --session t9 frobnicate
  assert_status 1 "show with an argument exits 1" -- mode --session t9 show extra
  assert_status 1 "set without a mode exits 1" -- mode --session t9 set
  assert_status 1 "an uppercase mode name is refused" -- mode --session t9 set Parallel
  assert_status 1 "a mode name with a trailing dash is refused" -- mode --session t9 set parallel-
  assert_status 1 "a bare key without a value is refused" -- mode --session t9 set parallel max
  assert_status 1 "a value with whitespace is refused" -- mode --session t9 set parallel "max=3 4"
  assert_status 1 "a value with a backslash is refused" -- mode --session t9 set parallel 'max=3\4'
  assert_status 1 "clear without a mode exits 1" -- mode --session t9 clear
  assert_status 1 "clear with two modes exits 1" -- mode --session t9 clear parallel autopilot
  assert_missing "$CFG/omega/modes/t9" "a refused set writes nothing"
  assert_status 1 "HOME and CLAUDE_CONFIG_DIR both unset exits 1" -- \
    env -u HOME -u CLAUDE_CONFIG_DIR sh "$MODE" --session x show
  env -u HOME -u CLAUDE_CONFIG_DIR sh "$MODE" --session x show >/dev/null 2> "$TMP/nodir.err"
  assert_contains "$TMP/nodir.err" "no config dir" "the message names the config dir"
}

test_mode_brief() {
  rm -rf "$CFG"
  assert_status 0 "brief exits 0 when no mode is set" -- mode --session t4 brief
  assert_eq "" "$(mode --session t4 brief)" "brief prints nothing when no mode is set"
  mode --session t4 set parallel max=3
  mode --session t4 set local-merge
  mode --session t4 set integration slug=ui-rework
  mode --session t4 set autopilot
  mode --session t4 set delegate
  mode --session t4 brief > "$TMP/brief.txt"
  assert_eq "Omega modes: parallel max=3 · local-merge · integration slug=ui-rework · autopilot · delegate" \
    "$(head -n 1 "$TMP/brief.txt")" "brief's first line joins the modes with a middle dot"
  assert_contains "$TMP/brief.txt" "^  parallel: dispatch up to 3 ready tasks at once, each in its own worktree; review each; cherry-pick onto the feature branch; the invoking skill's bookkeeping is unchanged\.$" \
    "brief carries the parallel rule with its cap"
  assert_contains "$TMP/brief.txt" "^  local-merge: skip GitHub checks; run the project's local CI; merge through gh pr merge --admin only on exit 0; PR base is the integration branch when one is set\.$" \
    "brief carries the local-merge rule"
  assert_contains "$TMP/brief.txt" "^  integration: story branches PR into integration/ui-rework; docs/integrations/ui-rework\.md is the set; finish only when every row is merged\.$" \
    "brief carries the integration rule with its slug"
  assert_contains "$TMP/brief.txt" "^  autopilot: never AskUserQuestion — rule by the standards, log the ruling with its cost if wrong, continue; commit, push and open a PR, never merge; end with handoff\.$" \
    "brief carries the autopilot rule"
  assert_contains "$TMP/brief.txt" "^  delegate: the main session dispatches, reads reports and runs status commands; every edit, search and document goes to a subagent; never fix by hand\.$" \
    "brief carries the delegate rule"
  assert_eq "6" "$(wc -l < "$TMP/brief.txt" | tr -d ' ')" "brief is the header plus one line per mode"
  mode --session t4 set parallel
  mode --session t4 brief > "$TMP/brief2.txt"
  assert_contains "$TMP/brief2.txt" "^  parallel: dispatch every ready task at once, each in its own worktree; review each; cherry-pick onto the feature branch; the invoking skill's bookkeeping is unchanged\.$" \
    "brief says every ready task when parallel has no cap"
  mode --session t4 set custom-mode key=value
  mode --session t4 brief > "$TMP/brief3.txt"
  assert_contains "$TMP/brief3.txt" "custom-mode key=value" "an unknown mode is listed in the header"
  assert_eq "6" "$(wc -l < "$TMP/brief3.txt" | tr -d ' ')" "an unknown mode gets no rule line"
}

# hook NAME JSON — run a hook as Claude Code would: the JSON on stdin, the
# plugin root and the temporary config root in the environment, no session
# id in the environment so the one in the JSON is what counts. Output lands
# in $TMP/hook.out, stderr in $TMP/hook.err.
hook() {
  printf '%s' "$2" | CLAUDE_PLUGIN_ROOT="$OMEGA" CLAUDE_CONFIG_DIR="$CFG" CLAUDE_CODE_SESSION_ID= \
    sh "$OMEGA/hooks/$1" > "$TMP/hook.out" 2> "$TMP/hook.err"
}

# hook_status NAME JSON — the hook's exit status, for assert_status.
hook_status() {
  printf '%s' "$2" | CLAUDE_PLUGIN_ROOT="$OMEGA" CLAUDE_CONFIG_DIR="$CFG" CLAUDE_CODE_SESSION_ID= \
    sh "$OMEGA/hooks/$1" >/dev/null 2>&1
}

# context — the additionalContext string of $TMP/hook.out, unescaped via jq
# when present; otherwise the raw JSON (still greppable for plain fragments).
context() {
  if command -v jq >/dev/null 2>&1; then
    jq -r '.hookSpecificOutput.additionalContext' "$TMP/hook.out"
  else
    cat "$TMP/hook.out"
  fi
}

test_hooks_json() {
  h="$OMEGA/hooks/hooks.json"
  assert_file "$h" "omega has hooks.json"
  assert_status 0 "hooks.json is valid JSON" -- valid_json "$h"
  assert_contains "$h" '"SessionStart"' "hooks.json registers SessionStart"
  assert_contains "$h" 'startup|resume|clear|compact' "SessionStart matches startup, resume, clear and compact"
  assert_contains "$h" 'CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh' "SessionStart runs session-start.sh from the plugin root"
  assert_contains "$h" '"UserPromptSubmit"' "hooks.json registers UserPromptSubmit"
  assert_contains "$h" 'CLAUDE_PLUGIN_ROOT}/hooks/prompt-submit.sh' "UserPromptSubmit runs prompt-submit.sh from the plugin root"
  assert_contains "$h" '"SessionEnd"' "hooks.json registers SessionEnd"
  assert_contains "$h" 'CLAUDE_PLUGIN_ROOT}/hooks/session-end.sh' "SessionEnd runs session-end.sh from the plugin root"
  assert_contains "$h" '"PreToolUse"' "hooks.json registers PreToolUse"
  assert_contains "$h" '"matcher": "Edit|Write|NotebookEdit"' "PreToolUse matches Edit, Write and NotebookEdit"
  assert_contains "$h" 'CLAUDE_PLUGIN_ROOT}/hooks/pre-tool-use.sh' "PreToolUse runs pre-tool-use.sh from the plugin root"
}

test_session_start() {
  rm -rf "$CFG"
  assert_status 0 "session-start exits 0 with no mode file" -- \
    hook_status session-start.sh '{"session_id":"s1","hook_event_name":"SessionStart","source":"startup"}'
  hook session-start.sh '{"session_id":"s1","hook_event_name":"SessionStart","source":"startup"}'
  assert_status 0 "session-start output is valid JSON" -- valid_json "$TMP/hook.out"
  assert_eq "1" "$(wc -l < "$TMP/hook.out" | tr -d ' ')" "session-start output is a single line"
  assert_contains "$TMP/hook.out" '"hookEventName":"SessionStart"' "output names the SessionStart event"
  context > "$TMP/ctx.txt"
  assert_contains "$TMP/ctx.txt" "Omega global skills: /omega:handoff, /omega:parallel \[N|off\], /omega:local-merge \[off\], /omega:integration <start|add|status|finish>, /omega:autopilot \[off\], /omega:delegate \[off\]\." \
    "context names the six skills"
  assert_contains "$TMP/ctx.txt" "Mode tool: $OMEGA/bin/omega-mode (set | clear | show | path | brief)\." "context names the omega-mode path"
  assert_contains "$TMP/ctx.txt" "Keep-awake: $OMEGA/bin/omega-caffeine (start | stop | status)\." "context names the omega-caffeine path"
  assert_not_contains "$TMP/ctx.txt" "Omega modes:" "no modes block when no mode is set"
  mode --session s1 set parallel max=3
  mode --session s1 set local-merge
  hook session-start.sh '{"session_id":"s1","hook_event_name":"SessionStart","source":"compact"}'
  assert_status 0 "session-start output with modes is valid JSON" -- valid_json "$TMP/hook.out"
  context > "$TMP/ctx.txt"
  assert_contains "$TMP/ctx.txt" "Omega modes: parallel max=3 · local-merge" "the modes block names the active modes"
  assert_contains "$TMP/ctx.txt" "  parallel: dispatch up to 3 ready tasks" "the modes block carries the parallel rule"
  assert_contains "$TMP/ctx.txt" "  local-merge: skip GitHub checks" "the modes block carries the local-merge rule"
  assert_file "$CFG/omega/modes/s1" "session-start leaves the mode file alone"
  hook session-start.sh ''
  assert_status 0 "session-start exits 0 with empty stdin" -- hook_status session-start.sh ''
  assert_status 0 "session-start output with empty stdin is valid JSON" -- valid_json "$TMP/hook.out"
}

test_session_start_prunes_old_files() {
  rm -rf "$CFG"
  mkdir -p "$CFG/omega/modes"
  printf 'parallel\n' > "$CFG/omega/modes/old"
  touch -t 202001010000 "$CFG/omega/modes/old"
  printf 'parallel\n' > "$CFG/omega/modes/fresh"
  # The current session's own file, also older than seven days: a resumed or
  # compacted session must still find its modes, so prune never removes it.
  printf 'parallel\n' > "$CFG/omega/modes/s2"
  eight_days_ago="$(date -v-8d +%Y%m%d%H%M 2>/dev/null || date -d '-8 days' +%Y%m%d%H%M)"
  touch -t "$eight_days_ago" "$CFG/omega/modes/s2"
  hook session-start.sh '{"session_id":"s2","hook_event_name":"SessionStart","source":"startup"}'
  assert_missing "$CFG/omega/modes/old" "a mode file older than seven days is pruned"
  assert_file "$CFG/omega/modes/fresh" "a fresh mode file survives"
  assert_file "$CFG/omega/modes/s2" "the current session's file older than seven days survives"
  context > "$TMP/ctx-s2.txt"
  assert_contains "$TMP/ctx-s2.txt" "Omega modes:" "the surviving current-session file's Omega modes: block is printed"
}

test_prompt_submit() {
  rm -rf "$CFG"
  hook prompt-submit.sh '{"session_id":"p1","hook_event_name":"UserPromptSubmit","prompt":"<command-message>parallel</command-message>\n<command-name>/omega:parallel</command-name>\n<command-args>3</command-args>"}'
  assert_eq "parallel max=3" "$(mode --session p1 show)" "/omega:parallel 3 sets parallel max=3"
  assert_status 0 "prompt-submit output with a mode is valid JSON" -- valid_json "$TMP/hook.out"
  assert_eq "1" "$(wc -l < "$TMP/hook.out" | tr -d ' ')" "prompt-submit output is a single line"
  assert_contains "$TMP/hook.out" '"hookEventName":"UserPromptSubmit"' "output names the UserPromptSubmit event"
  context > "$TMP/ctx.txt"
  assert_contains "$TMP/ctx.txt" "Omega modes: parallel max=3" "the turn's context carries the modes block"
  assert_contains "$TMP/ctx.txt" "  parallel: dispatch up to 3 ready tasks" "the turn's context carries the rule line"
  assert_not_contains "$TMP/ctx.txt" "Omega global skills:" "prompt-submit does not repeat the skills line"

  hook prompt-submit.sh '{"session_id":"p1","hook_event_name":"UserPromptSubmit","prompt":"<command-message>local-merge</command-message>\n<command-name>/omega:local-merge</command-name>\n<command-args></command-args>"}'
  assert_eq "$(printf 'parallel max=3\nlocal-merge')" "$(mode --session p1 show)" "/omega:local-merge with empty args sets local-merge"

  hook prompt-submit.sh '{"session_id":"p1","hook_event_name":"UserPromptSubmit","prompt":"<command-message>integration</command-message>\n<command-name>/omega:integration</command-name>\n<command-args>start ui-rework</command-args>"}'
  assert_contains "$CFG/omega/modes/p1" "^integration slug=ui-rework$" "/omega:integration start <slug> sets the slug"

  hook prompt-submit.sh '{"session_id":"p1","hook_event_name":"UserPromptSubmit","prompt":"<command-name>/omega:parallel</command-name><command-args>off</command-args>"}'
  assert_not_contains "$CFG/omega/modes/p1" "^parallel" "/omega:parallel off clears parallel"

  mode --session p1 clear local-merge
  hook prompt-submit.sh '{"session_id":"p1","hook_event_name":"UserPromptSubmit","prompt":"<command-message>local-merge</command-message>\n<command-name>/omega:local-merge</command-name>"}'
  assert_contains "$CFG/omega/modes/p1" "^local-merge$" "an envelope without command-args sets the bare mode"

  # A typed /omega:autopilot arms nothing; the skill sets the mode after
  # pre-flight. Session p3 has no file, so its absence is the proof.
  hook prompt-submit.sh '{"session_id":"p3","hook_event_name":"UserPromptSubmit","prompt":"<command-message>autopilot</command-message>\n<command-name>/omega:autopilot</command-name>"}'
  assert_missing "$CFG/omega/modes/p3" "a typed /omega:autopilot arms nothing; the skill sets the mode after pre-flight"
  hook prompt-submit.sh '{"session_id":"p3","hook_event_name":"UserPromptSubmit","prompt":"<command-name>/omega:autopilot</command-name><command-args></command-args>"}'
  assert_missing "$CFG/omega/modes/p3" "/omega:autopilot with empty command-args arms nothing either"

  hook prompt-submit.sh '{"session_id":"p1","hook_event_name":"UserPromptSubmit","prompt":"<command-name>/omega:parallel</command-name><command-args>  </command-args>"}'
  assert_contains "$CFG/omega/modes/p1" "^parallel$" "whitespace-only args set the bare mode"
  mode --session p1 clear parallel

  hook prompt-submit.sh '{"session_id":"p1","hook_event_name":"UserPromptSubmit","prompt":"<command-message>delegate</command-message>\n<command-name>/omega:delegate</command-name>\n<command-args></command-args>"}'
  assert_contains "$CFG/omega/modes/p1" "^delegate$" "/omega:delegate with empty args sets delegate"
  context > "$TMP/ctx-delegate.txt"
  assert_contains "$TMP/ctx-delegate.txt" "  delegate: the main session dispatches, reads reports and runs status commands; every edit, search and document goes to a subagent; never fix by hand\." \
    "the turn's context carries the delegate rule line"
  hook prompt-submit.sh '{"session_id":"p1","hook_event_name":"UserPromptSubmit","prompt":"<command-name>/omega:delegate</command-name><command-args>3</command-args>"}'
  assert_contains "$CFG/omega/modes/p1" "^delegate$" "/omega:delegate 3 changes nothing"
  hook prompt-submit.sh '{"session_id":"p1","hook_event_name":"UserPromptSubmit","prompt":"<command-name>/omega:delegate</command-name><command-args>off</command-args>"}'
  assert_not_contains "$CFG/omega/modes/p1" "^delegate" "/omega:delegate off clears delegate"

  before="$(mode --session p1 show)"
  hook prompt-submit.sh '{"session_id":"p1","hook_event_name":"UserPromptSubmit","prompt":"<command-message>caveman</command-message>\n<command-name>/caveman</command-name>\n<command-args>off</command-args>"}'
  assert_eq "$before" "$(mode --session p1 show)" "a foreign command envelope changes nothing"
  hook prompt-submit.sh '{"session_id":"p1","hook_event_name":"UserPromptSubmit","prompt":"<scheduled-task id=\"x\"><command-name>/omega:parallel</command-name><command-args>off</command-args></scheduled-task>"}'
  assert_eq "$before" "$(mode --session p1 show)" "a scheduled-task prompt changes nothing"
  hook prompt-submit.sh '{"session_id":"p1","hook_event_name":"UserPromptSubmit","prompt":"please run /omega:parallel 4 for me"}'
  assert_eq "$before" "$(mode --session p1 show)" "plain text naming a command changes nothing"
  hook prompt-submit.sh '{"session_id":"p1","hook_event_name":"UserPromptSubmit","prompt":"<command-name>/omega:parallel</command-name><command-args>lots</command-args>"}'
  assert_eq "$before" "$(mode --session p1 show)" "a non-numeric parallel argument changes nothing"
  hook prompt-submit.sh '{"session_id":"p1","hook_event_name":"UserPromptSubmit","prompt":"<command-name>/omega:integration</command-name><command-args>finish</command-args>"}'
  assert_eq "$before" "$(mode --session p1 show)" "/omega:integration finish leaves the mode to the skill"
  hook prompt-submit.sh '{"session_id":"p1","hook_event_name":"UserPromptSubmit","prompt":"<command-name>/omega:integration</command-name><command-args>start bad/slug</command-args>"}'
  assert_eq "$before" "$(mode --session p1 show)" "a slug with a slash changes nothing"
  hook prompt-submit.sh '{"session_id":"p1","hook_event_name":"UserPromptSubmit","prompt":"<command-name>/omega:handoff</command-name>"}'
  assert_eq "$before" "$(mode --session p1 show)" "/omega:handoff changes nothing"
  assert_status 0 "prompt-submit exits 0 on a foreign command" -- \
    hook_status prompt-submit.sh '{"session_id":"p1","hook_event_name":"UserPromptSubmit","prompt":"<command-name>/caveman</command-name>"}'

  mode --session p1 clear --all
  hook prompt-submit.sh '{"session_id":"p1","hook_event_name":"UserPromptSubmit","prompt":"hello"}'
  assert_eq "" "$(cat "$TMP/hook.out")" "no mode set: prompt-submit prints nothing"
  assert_status 0 "prompt-submit exits 0 with no mode" -- \
    hook_status prompt-submit.sh '{"session_id":"p1","hook_event_name":"UserPromptSubmit","prompt":"hi"}'
  assert_status 0 "prompt-submit exits 0 with empty stdin" -- hook_status prompt-submit.sh ''
  hook prompt-submit.sh ''
  assert_eq "" "$(cat "$TMP/hook.out")" "empty stdin: prompt-submit prints nothing"

  # --- Envelope anchored on the prompt value, not the flattened JSON: a
  # prompt that merely mentions a tag (pasted test fixture text) must not be
  # read as one. Session p2, fresh, so these do not depend on p1's history.
  mode --session p2 clear --all
  hook prompt-submit.sh '{"session_id":"p2","hook_event_name":"UserPromptSubmit","prompt":"this test fails: <command-name>/omega:local-merge</command-name>"}'
  assert_eq "" "$(mode --session p2 show)" "pasted text with the envelope not at the start sets nothing"

  hook prompt-submit.sh '{"session_id":"p2","hook_event_name":"UserPromptSubmit","prompt":"   <command-message>parallel</command-message>   <command-name>/omega:parallel</command-name>"}'
  assert_eq "parallel" "$(mode --session p2 show)" \
    "an envelope preceded by <command-message> and whitespace still sets the mode"
  mode --session p2 clear parallel

  hook prompt-submit.sh '{"session_id":"p2","hook_event_name":"UserPromptSubmit","prompt":"<command-name>/omega:parallel</command-name><command-args>0</command-args>"}'
  assert_eq "" "$(mode --session p2 show)" "/omega:parallel 0 sets nothing"
  hook prompt-submit.sh '{"session_id":"p2","hook_event_name":"UserPromptSubmit","prompt":"<command-name>/omega:parallel</command-name><command-args>007</command-args>"}'
  assert_eq "" "$(mode --session p2 show)" "/omega:parallel 007 sets nothing (leading zero)"

  mode --session p2 set local-merge
  mode --session p2 set autopilot
  hook prompt-submit.sh '{"session_id":"p2","hook_event_name":"UserPromptSubmit","prompt":"<command-name>/omega:local-merge</command-name><command-args>off</command-args>"}'
  assert_not_contains "$CFG/omega/modes/p2" "^local-merge$" "/omega:local-merge off clears local-merge"
  assert_contains "$CFG/omega/modes/p2" "^autopilot$" "/omega:local-merge off leaves autopilot alone"
  # A typed off clears the line that records the keep-awake pid, so the
  # hook must stop the process before the skill runs — the skill's own
  # `omega-caffeine stop` would find nothing.
  caffeine --session p2 start >/dev/null
  cp="$(caffeine_pid p2)"
  CAF_PIDS="$CAF_PIDS $cp"
  assert_status 0 "the keep-awake process is running before /omega:autopilot off" -- kill -0 "$cp"
  hook prompt-submit.sh '{"session_id":"p2","hook_event_name":"UserPromptSubmit","prompt":"<command-name>/omega:autopilot</command-name><command-args>off</command-args>"}'
  assert_missing "$CFG/omega/modes/p2" "/omega:autopilot off clears autopilot (the last mode)"
  wait_dead "$cp"
  assert_status 1 "/omega:autopilot off kills the keep-awake process" -- kill -0 "$cp"
  assert_eq "" "$(cat "$TMP/hook.err")" "/omega:autopilot off leaves stderr empty"

  hook prompt-submit.sh '{"session_id":"p2","hook_event_name":"UserPromptSubmit","prompt":"<command-name>/omega:integration</command-name><command-args>start ..</command-args>"}'
  assert_eq "" "$(mode --session p2 show)" "/omega:integration start .. sets nothing"

  # A <scheduled-task> prompt changes no mode but still gets the block.
  mode --session p2 set parallel
  hook prompt-submit.sh '{"session_id":"p2","hook_event_name":"UserPromptSubmit","prompt":"<scheduled-task id=\"y\"><command-name>/omega:parallel</command-name><command-args>off</command-args></scheduled-task>"}'
  assert_eq "parallel" "$(mode --session p2 show)" \
    "a scheduled-task prompt with parallel set leaves the mode unchanged"
  context > "$TMP/ctx-sched.txt"
  assert_contains "$TMP/ctx-sched.txt" "Omega modes:" "a scheduled-task prompt still receives the Omega modes: block"
  mode --session p2 clear --all

  # Happy path: no stray stderr.
  hook prompt-submit.sh '{"session_id":"p2","hook_event_name":"UserPromptSubmit","prompt":"<command-message>parallel</command-message>\n<command-name>/omega:parallel</command-name>\n<command-args>3</command-args>"}'
  assert_eq "" "$(cat "$TMP/hook.err")" "the happy path leaves stderr empty"
  mode --session p2 clear --all
}

test_session_end() {
  rm -rf "$CFG"
  mode --session e1 set parallel
  hook session-end.sh '{"session_id":"e1","hook_event_name":"SessionEnd","reason":"exit"}'
  assert_missing "$CFG/omega/modes/e1" "session-end deletes the session's mode file"
  assert_eq "" "$(cat "$TMP/hook.out")" "session-end prints nothing"
  assert_status 0 "session-end exits 0 when there is no file" -- \
    hook_status session-end.sh '{"session_id":"e1","hook_event_name":"SessionEnd","reason":"exit"}'
  assert_status 0 "session-end exits 0 with empty stdin" -- hook_status session-end.sh ''
  mode --session e2 set parallel
  hook session-end.sh '{"session_id":"e1","hook_event_name":"SessionEnd","reason":"exit"}'
  assert_file "$CFG/omega/modes/e2" "session-end leaves other sessions' files alone"

  # A keep-awake process recorded for the ending session dies with it.
  mode --session e3 set autopilot
  caffeine --session e3 start >/dev/null
  p="$(caffeine_pid e3)"
  CAF_PIDS="$CAF_PIDS $p"
  assert_status 0 "the keep-awake process is running before session-end" -- kill -0 "$p"
  hook session-end.sh '{"session_id":"e3","hook_event_name":"SessionEnd","reason":"exit"}'
  wait_dead "$p"
  assert_status 1 "session-end kills the session's keep-awake process" -- kill -0 "$p"
  assert_missing "$CFG/omega/modes/e3" "session-end still deletes the mode file"
  assert_eq "" "$(cat "$TMP/hook.out")" "session-end prints nothing after killing the process"
}

# ptu TOOL KEY PATH TRANSCRIPT CWD SESSION [AGENT_ID] — one PreToolUse record
# as Claude Code sends it, single-line, for the guard hook. When AGENT_ID is
# given and non-empty, the record also carries "agent_id" and "agent_type"
# (before "tool_input") — a subagent's call.
ptu() {
  agent=""
  if [ -n "${7:-}" ]; then
    agent="\"agent_id\":\"$7\",\"agent_type\":\"general-purpose\","
  fi
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"PreToolUse",%s"tool_name":"%s","tool_input":{"%s":"%s","content":"x"}}' \
    "$6" "$4" "$5" "$agent" "$1" "$2" "$3"
}

test_pre_tool_use() {
  rm -rf "$CFG"
  repo="$TMP/ptu-repo"; rm -rf "$repo"; mkdir -p "$repo/src"
  git -C "$repo" init -q
  outside="$TMP/ptu-outside"; rm -rf "$outside"; mkdir -p "$outside"
  main_t="$TMP/x/d1.jsonl"
  sub_t="$TMP/x/d1/subagents/agent-a1.jsonl"
  mode --session d1 set delegate

  hook pre-tool-use.sh "$(ptu Write file_path "$repo/src/a.gd" "$main_t" "$repo" d1)"
  assert_status 0 "a main-session Write under the repository exits 0" -- \
    hook_status pre-tool-use.sh "$(ptu Write file_path "$repo/src/a.gd" "$main_t" "$repo" d1)"
  assert_status 0 "the deny output is valid JSON" -- valid_json "$TMP/hook.out"
  assert_contains "$TMP/hook.out" '"permissionDecision":"deny"' "a main-session Write under the repository is denied"
  assert_contains "$TMP/hook.out" 'omega:delegate' "the reason names the mode"
  assert_contains "$TMP/hook.out" '"hookEventName":"PreToolUse"' "the output names the PreToolUse event"
  assert_eq "1" "$(wc -l < "$TMP/hook.out" | tr -d ' ')" "the deny output is a single line"
  assert_eq "" "$(cat "$TMP/hook.err")" "the deny path leaves stderr empty"

  hook pre-tool-use.sh "$(ptu Write file_path "$repo/src/a.gd" "$main_t" "$repo" d1 a1)"
  assert_eq "" "$(cat "$TMP/hook.out")" "a subagent's Write is allowed by its agent_id"

  hook pre-tool-use.sh "$(ptu Write file_path "$repo/src/a.gd" "$sub_t" "$repo" d1)"
  assert_eq "" "$(cat "$TMP/hook.out")" "a subagents transcript path alone still allows"

  hook pre-tool-use.sh '{"session_id":"d1","transcript_path":"'"$main_t"'","cwd":"'"$repo"'","hook_event_name":"PreToolUse","agent_id":"","tool_name":"Write","tool_input":{"file_path":"'"$repo"'/src/a.gd","content":"x"}}'
  assert_contains "$TMP/hook.out" '"permissionDecision":"deny"' "an empty agent_id is not a subagent"

  hook pre-tool-use.sh "$(ptu Write file_path "$outside/a.gd" "$main_t" "$repo" d1)"
  assert_eq "" "$(cat "$TMP/hook.out")" "a Write outside the repository is allowed"
  hook pre-tool-use.sh "$(ptu Edit file_path "src/a.gd" "$main_t" "$repo" d1)"
  assert_contains "$TMP/hook.out" '"permissionDecision":"deny"' "a relative path that resolves inside the repository is denied"
  hook pre-tool-use.sh "$(ptu Edit file_path "src/new/dir/a.gd" "$main_t" "$repo" d1)"
  assert_contains "$TMP/hook.out" '"permissionDecision":"deny"' "a path in a directory that does not exist yet is still under the repository"
  hook pre-tool-use.sh "$(ptu NotebookEdit notebook_path "$repo/n.ipynb" "$main_t" "$repo" d1)"
  assert_contains "$TMP/hook.out" '"permissionDecision":"deny"' "NotebookEdit inside the repository is denied"
  hook pre-tool-use.sh "$(ptu Read file_path "$repo/src/a.gd" "$main_t" "$repo" d1)"
  assert_eq "" "$(cat "$TMP/hook.out")" "a Read is never denied"
  hook pre-tool-use.sh "$(ptu Write file_path "$repo/src/a.gd" "$main_t" "$outside" d1)"
  assert_eq "" "$(cat "$TMP/hook.out")" "a cwd outside any git repository allows"
  hook pre-tool-use.sh "$(ptu Write file_path "$repo/src/a.gd" "$main_t" "$repo" d2)"
  assert_eq "" "$(cat "$TMP/hook.out")" "a session with no mode file allows"
  hook pre-tool-use.sh '{"session_id":"d1","transcript_path":"'"$main_t"'","cwd":"'"$repo"'","hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"content":"x"}}'
  assert_eq "" "$(cat "$TMP/hook.out")" "a Write with no file_path allows"

  mode --session d1 clear delegate
  mode --session d1 set parallel max=2
  hook pre-tool-use.sh "$(ptu Write file_path "$repo/src/a.gd" "$main_t" "$repo" d1)"
  assert_eq "" "$(cat "$TMP/hook.out")" "parallel without delegate allows"
  mode --session d1 clear --all
  hook pre-tool-use.sh "$(ptu Write file_path "$repo/src/a.gd" "$main_t" "$repo" d1)"
  assert_eq "" "$(cat "$TMP/hook.out")" "with the mode cleared the same Write allows"

  assert_status 0 "empty stdin exits 0" -- hook_status pre-tool-use.sh ''
  hook pre-tool-use.sh ''
  assert_eq "" "$(cat "$TMP/hook.out")" "empty stdin prints nothing"
  assert_status 0 "garbage stdin exits 0" -- hook_status pre-tool-use.sh '{garbage'
  hook pre-tool-use.sh '{garbage'
  assert_eq "" "$(cat "$TMP/hook.out")" "garbage stdin prints nothing"
  assert_eq "" "$(cat "$TMP/hook.err")" "garbage stdin leaves stderr empty"
}

test_caffeine() {
  rm -rf "$CFG"
  assert_file "$CAF" "omega ships bin/omega-caffeine"
  assert_status 0 "omega-caffeine is executable" -- test -x "$CAF"

  # start needs autopilot: it never sets a mode as a side effect.
  assert_status 1 "start without autopilot set exits 1" -- caffeine --session c1 start
  assert_missing "$CFG/omega/modes/c1" "a refused start sets no mode"
  caffeine --session c1 start >/dev/null 2> "$TMP/caf.err"
  assert_contains "$TMP/caf.err" "autopilot is not set" "the refusal names the missing mode"
  mode --session c1 set parallel max=2
  assert_status 1 "start with another mode but not autopilot exits 1" -- caffeine --session c1 start
  assert_eq "parallel max=2" "$(mode --session c1 show)" "the refusal leaves the other mode alone"

  mode --session c1 set autopilot
  out="$(caffeine --session c1 start)"
  pid="$(caffeine_pid c1)"
  CAF_PIDS="$CAF_PIDS $pid"
  TESTS_RUN=$((TESTS_RUN + 1))
  case "$pid" in
    ''|*[!0-9]*) _fail "start records a numeric pid (got '$pid')" ;;
    *) _pass "start records a numeric pid" ;;
  esac
  assert_eq "running $pid" "$out" "start prints running <pid>"
  assert_status 0 "the recorded pid is alive" -- kill -0 "$pid"
  assert_eq "$(printf 'parallel max=2\nautopilot caffeine=%s' "$pid")" "$(mode --session c1 show)" \
    "the pid rides on the autopilot line; the other mode is untouched"
  assert_eq "running $pid" "$(caffeine --session c1 start)" "a second start is a no-op that reports the same pid"
  assert_eq "$pid" "$(caffeine_pid c1)" "a second start starts nothing new"
  assert_eq "running $pid" "$(caffeine status --session c1)" "status prints running <pid>; --session is accepted after the verb"
  assert_status 0 "status exits 0 while running" -- caffeine --session c1 status

  # A recorded pid that is no longer alive is replaced, not trusted.
  kill "$pid"
  wait_dead "$pid"
  assert_eq "stopped" "$(caffeine --session c1 status)" "status prints stopped when the recorded pid is dead"
  assert_status 1 "status exits 1 when stopped" -- caffeine --session c1 status
  out="$(caffeine --session c1 start)"
  pid2="$(caffeine_pid c1)"
  CAF_PIDS="$CAF_PIDS $pid2"
  assert_eq "running $pid2" "$out" "start replaces a dead recorded pid"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -n "$pid2" ] && [ "$pid2" != "$pid" ]; then _pass "the replacement is a new pid"; else _fail "the replacement is a new pid (got '$pid2')"; fi
  assert_status 0 "the replacement pid is alive" -- kill -0 "$pid2"

  assert_eq "stopped" "$(caffeine --session c1 stop)" "stop prints stopped"
  wait_dead "$pid2"
  assert_status 1 "stop kills the recorded process" -- kill -0 "$pid2"
  assert_eq "$(printf 'parallel max=2\nautopilot')" "$(mode --session c1 show)" "stop drops the key and keeps the mode"
  assert_status 0 "stop with nothing running exits 0" -- caffeine --session c1 stop
  assert_eq "stopped" "$(caffeine --session c1 stop)" "stop with nothing running still prints stopped"
  assert_eq "stopped" "$(caffeine --session c1 status)" "status prints stopped after stop"

  # Existing pairs on the autopilot line survive start and stop.
  mode --session c2 set autopilot foo=bar
  caffeine --session c2 start >/dev/null
  pid3="$(caffeine_pid c2)"
  CAF_PIDS="$CAF_PIDS $pid3"
  assert_eq "autopilot foo=bar caffeine=$pid3" "$(mode --session c2 show)" "start keeps the line's other pairs"
  caffeine --session c2 stop >/dev/null
  assert_eq "autopilot foo=bar" "$(mode --session c2 show)" "stop keeps the line's other pairs"
  mode --session c2 clear autopilot
  assert_status 0 "stop exits 0 when autopilot is not set" -- caffeine --session c2 stop
  assert_missing "$CFG/omega/modes/c2" "stop without autopilot writes nothing"

  # The timeout argument.
  mode --session c4 set autopilot
  assert_status 1 "start 0 is refused" -- caffeine --session c4 start 0
  assert_status 1 "start 169 is refused (a week is the cap)" -- caffeine --session c4 start 169
  assert_status 1 "start with a non-numeric timeout is refused" -- caffeine --session c4 start soon
  assert_status 1 "start with two arguments is refused" -- caffeine --session c4 start 1 2
  assert_eq "autopilot" "$(mode --session c4 show)" "a refused start records nothing"
  caffeine --session c4 start 1 >/dev/null
  pid4="$(caffeine_pid c4)"
  CAF_PIDS="$CAF_PIDS $pid4"
  assert_status 0 "start with an hour count runs" -- kill -0 "$pid4"
  caffeine --session c4 stop >/dev/null
  assert_status 1 "no session id exits 1" -- env CLAUDE_CODE_SESSION_ID= CLAUDE_CONFIG_DIR="$CFG" sh "$CAF" status
  assert_status 1 "an unknown verb exits 1" -- caffeine --session c4 brew
  st=0
  caffeine --session ../x start >/dev/null 2> "$TMP/caf.err" || st=$?
  assert_eq 1 "$st" "an omega-mode failure is fatal, not read as autopilot unset"
  assert_contains "$TMP/caf.err" "invalid session id" "omega-mode's own message is shown"
  assert_not_contains "$TMP/caf.err" "autopilot is not set" "the failure is not reported as autopilot unset"

  # A recorded pid that now belongs to some other process — a long session
  # outlives the keep-awake timeout and the number is reused — is neither
  # trusted nor killed: identity is checked, not just liveness.
  sleep 60 &
  fp=$!
  CAF_PIDS="$CAF_PIDS $fp"
  mode --session c5 set autopilot "caffeine=$fp"
  assert_eq "stopped" "$(caffeine --session c5 status)" "status treats a live pid that is not the tool as stopped"
  assert_status 1 "status exits 1 for a foreign pid" -- caffeine --session c5 status
  assert_eq "stopped" "$(caffeine --session c5 stop)" "stop prints stopped for a foreign pid"
  assert_status 0 "stop does not kill a foreign pid" -- kill -0 "$fp"
  assert_eq "autopilot" "$(mode --session c5 show)" "stop drops the stale key"
  mode --session c5 set autopilot "caffeine=$fp"
  caffeine --session c5 start >/dev/null
  pid5="$(caffeine_pid c5)"
  CAF_PIDS="$CAF_PIDS $pid5"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -n "$pid5" ] && [ "$pid5" != "$fp" ]; then _pass "start replaces a foreign pid"; else _fail "start replaces a foreign pid (got '$pid5')"; fi
  assert_status 0 "start leaves the foreign process alive" -- kill -0 "$fp"
  caffeine --session c5 stop >/dev/null
  kill "$fp" 2>/dev/null

  # No keep-awake tool on PATH: a warning, never a failure.
  mode --session c3 set autopilot
  st=0
  CLAUDE_CONFIG_DIR="$CFG" PATH="$TMP/nobin" sh "$CAF" --session c3 start > "$TMP/caf.out" 2> "$TMP/caf.err" || st=$?
  assert_eq 0 "$st" "start without a keep-awake tool exits 0"
  assert_eq "unsupported" "$(cat "$TMP/caf.out")" "start without a tool prints unsupported"
  assert_contains "$TMP/caf.err" "no keep-awake tool" "start without a tool warns on stderr"
  assert_eq "autopilot" "$(mode --session c3 show)" "start without a tool records no pid"
  assert_eq "unsupported" "$(CLAUDE_CONFIG_DIR="$CFG" PATH="$TMP/nobin" sh "$CAF" --session c3 status)" \
    "status without a tool prints unsupported"
  assert_status 1 "status without a tool exits 1" -- \
    env CLAUDE_CONFIG_DIR="$CFG" PATH="$TMP/nobin" sh "$CAF" --session c3 status
  assert_status 0 "stop without a tool exits 0" -- \
    env CLAUDE_CONFIG_DIR="$CFG" PATH="$TMP/nobin" sh "$CAF" --session c3 stop
  reap

  # A pid that cannot be recorded is not left running: the process is
  # killed and start fails, or a process nobody knows about outlives the run.
  mode --session c6 set autopilot
  chmod 555 "$CFG/omega/modes"
  st=0
  caffeine --session c6 start > "$TMP/caf.out" 2> "$TMP/caf.err" || st=$?
  chmod 755 "$CFG/omega/modes"
  assert_eq 1 "$st" "start exits 1 when the pid cannot be recorded"
  assert_contains "$TMP/caf.err" "cannot record" "the failure says the pid was not recorded"
  assert_not_contains "$TMP/caf.out" "running" "a failed start does not claim to be running"
  assert_eq "autopilot" "$(mode --session c6 show)" "a failed start records no pid"
  _i=0
  while pgrep -f "$TMP/fakebin/caffeinate" >/dev/null 2>&1 && [ "$_i" -lt 50 ]; do sleep 0.1; _i=$((_i + 1)); done
  assert_status 1 "a failed start kills the process it started" -- pgrep -f "$TMP/fakebin/caffeinate"
}

# Text contracts on the omega skills, one file per skill under
# tests/omega_contracts/, each defining test_<skill>_contract. One file per
# skill so five skill tasks can add theirs without editing the same file.
test_skill_contracts() {
  ran=0
  for c in "$REPO_ROOT"/tests/omega_contracts/*_contract.sh; do
    [ -f "$c" ] || continue
    . "$c"
    # local-merge_contract.sh defines test_local_merge_contract: a POSIX
    # function name has no hyphen (dash rejects one).
    fn="test_$(basename "$c" _contract.sh | tr - _)_contract"
    command -v "$fn" >/dev/null 2>&1 || { _fail "$c defines $fn"; continue; }
    "$fn"
    ran=$((ran + 1))
  done
  # Bump when a skill is added.
  assert_eq 5 "$ran" "five skill contracts ran"
}

run_tests test_plugin_files test_skill_stubs test_marketplace \
  test_mode_round_trip test_mode_validation test_mode_brief \
  test_hooks_json test_session_start test_session_start_prunes_old_files \
  test_prompt_submit test_session_end test_pre_tool_use test_caffeine test_skill_contracts
