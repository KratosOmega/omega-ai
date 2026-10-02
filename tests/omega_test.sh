#!/bin/sh
# Tests for the omega global plugin: manifest, skill stubs, marketplace
# manifest, omega-mode, and the three hooks. Runs without a
# config root: omega-mode and the hooks are pointed at a temporary
# CLAUDE_CONFIG_DIR. The suite needs `git` on
# PATH: test_pre_tool_use creates a temporary git repository as `cwd`.
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"
. "$REPO_ROOT/lib/common.sh"

OMEGA="$REPO_ROOT/shared/omega"
MODE="$OMEGA/bin/omega-mode"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
CFG="$TMP/cfg"

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
  for s in handoff parallel local-merge integration autopilot delegate reply; do
    assert_file "$OMEGA/skills/$s/SKILL.md" "omega ships the $s skill"
  done
  assert_contains "$OMEGA/.claude-plugin/plugin.json" "delegate, reply\." "omega plugin.json names the seven skills"
  assert_missing "$OMEGA/requires.txt" "omega declares no hard dependencies"
  assert_missing "$OMEGA/settings.json" "omega has no settings.json"
}

test_skill_stubs() {
  for s in handoff parallel local-merge integration autopilot delegate reply; do
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
  # reply shapes prose, not scheduling, so it carries its own precedence
  # block instead of the five-mode sentence above; reply_contract.sh asserts
  # that block's wording.
  assert_contains "$OMEGA/skills/reply/SKILL.md" "This mode changes how the session explains itself to the user." \
    "omega:reply carries its own precedence contract"
  assert_contains "$OMEGA/skills/reply/SKILL.md" "omega-mode" "omega:reply sets or clears its mode through omega-mode"
}

test_marketplace() {
  m="$REPO_ROOT/.claude-plugin/marketplace.json"
  assert_file "$m" "the repository has a marketplace manifest"
  assert_status 0 "marketplace.json is valid JSON" -- valid_json "$m"
  assert_eq "omega-ai" "$(json_field "$m" name)" "the marketplace is named omega-ai"
  assert_contains "$m" '"name": "omega"' "the marketplace publishes the omega plugin"
  assert_contains "$m" 'delegate, reply\.' "the marketplace description names the seven skills"
  src="$(sed -n 's/.*"source"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$m" | head -n 1)"
  assert_eq "./shared/omega" "$src" "the omega plugin's source is ./shared/omega"
  assert_file "$REPO_ROOT/${src#./}/.claude-plugin/plugin.json" "the marketplace source resolves to the plugin"
}

# mode ARGS... — omega-mode against the temporary config root.
mode() {
  CLAUDE_CONFIG_DIR="$CFG" sh "$MODE" "$@"
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
  mode --session t4 set reply
  mode --session t4 brief > "$TMP/brief.txt"
  assert_eq "Omega modes: parallel max=3 · local-merge · integration slug=ui-rework · autopilot · delegate · reply" \
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
  assert_contains "$TMP/brief.txt" "^  reply: explain and decide in one concrete scenario from the project's world, five lines at most; no paths, symbols, config keys or raw values in the prose; code, commands, exact errors, test results and warnings stay verbatim\.$" \
    "brief carries the reply rule"
  assert_eq "7" "$(wc -l < "$TMP/brief.txt" | tr -d ' ')" "brief is the header plus one line per mode"
  mode --session t4 set parallel
  mode --session t4 brief > "$TMP/brief2.txt"
  assert_contains "$TMP/brief2.txt" "^  parallel: dispatch every ready task at once, each in its own worktree; review each; cherry-pick onto the feature branch; the invoking skill's bookkeeping is unchanged\.$" \
    "brief says every ready task when parallel has no cap"
  mode --session t4 set custom-mode key=value
  mode --session t4 brief > "$TMP/brief3.txt"
  assert_contains "$TMP/brief3.txt" "custom-mode key=value" "an unknown mode is listed in the header"
  assert_eq "7" "$(wc -l < "$TMP/brief3.txt" | tr -d ' ')" "an unknown mode gets no rule line"
}

test_mode_env_autopilot() {
  # No session id at all: the env line alone, exit 0.
  out="$(env -u CLAUDE_CODE_SESSION_ID OMEGA_AUTOPILOT=1 CLAUDE_CONFIG_DIR="$TMP/cfg-env" sh "$MODE" show)"; st=$?
  assert_eq 0 "$st" "show with OMEGA_AUTOPILOT=1 and no session id exits 0"
  assert_eq "autopilot source=env" "$out" "show prints the env line"
  out="$(env -u CLAUDE_CODE_SESSION_ID OMEGA_AUTOPILOT=1 CLAUDE_CONFIG_DIR="$TMP/cfg-env" sh "$MODE" brief)"
  printf '%s\n' "$out" > "$TMP/env-brief.txt"
  assert_contains "$TMP/env-brief.txt" "^Omega modes: autopilot source=env$" "brief heads with the env line"
  assert_contains "$TMP/env-brief.txt" "autopilot (overnight runner): never AskUserQuestion — rule by the standards, log the ruling with its cost if wrong, continue; commit, push and open a draft PR, never merge; on a hard stop write Stop: <reason> to the ledger and end; no handoff — the runner starts the next session\." "brief carries the runner's rule text"
  # A session file with reply: both lines, file first.
  CLAUDE_CONFIG_DIR="$TMP/cfg-env" sh "$MODE" --session envs set reply
  out="$(OMEGA_AUTOPILOT=1 CLAUDE_CONFIG_DIR="$TMP/cfg-env" sh "$MODE" --session envs show)"
  assert_eq "reply
autopilot source=env" "$out" "the file's lines, then the env line"
  # A session-file autopilot line wins: no duplicate, today's text.
  CLAUDE_CONFIG_DIR="$TMP/cfg-env" sh "$MODE" --session envs set autopilot
  assert_eq 1 "$(OMEGA_AUTOPILOT=1 CLAUDE_CONFIG_DIR="$TMP/cfg-env" sh "$MODE" --session envs show | grep -c '^autopilot')" "no env line when the file lists autopilot"
  OMEGA_AUTOPILOT=1 CLAUDE_CONFIG_DIR="$TMP/cfg-env" sh "$MODE" --session envs brief > "$TMP/env-brief2.txt"
  assert_contains "$TMP/env-brief2.txt" "end with handoff" "a session-file autopilot keeps today's text"
  # Unset or not 1: nothing.
  assert_eq "" "$(env -u OMEGA_AUTOPILOT CLAUDE_CONFIG_DIR="$TMP/cfg-env" sh "$MODE" --session none show)" "no env, no file: nothing"
  assert_status 1 "without the env, a missing session id still dies" -- env -u CLAUDE_CODE_SESSION_ID -u OMEGA_AUTOPILOT sh "$MODE" show
  assert_status 1 "set still needs a session id under the env" -- env -u CLAUDE_CODE_SESSION_ID OMEGA_AUTOPILOT=1 sh "$MODE" set reply
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
  assert_contains "$TMP/ctx.txt" "Omega global skills: /omega:handoff, /omega:parallel \[N|off\], /omega:local-merge \[off\], /omega:integration <start|add|status|finish>, /omega:autopilot \[off\], /omega:delegate \[off\], /omega:reply \[off\]\." \
    "context names the seven skills"
  assert_contains "$TMP/ctx.txt" "Mode tool: $OMEGA/bin/omega-mode (set | clear | show | path | brief)\." "context names the omega-mode path"
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

  hook prompt-submit.sh '{"session_id":"p1","hook_event_name":"UserPromptSubmit","prompt":"<command-message>reply</command-message>\n<command-name>/omega:reply</command-name>\n<command-args></command-args>"}'
  assert_contains "$CFG/omega/modes/p1" "^reply$" "/omega:reply with empty args sets reply"
  context > "$TMP/ctx-reply.txt"
  assert_contains "$TMP/ctx-reply.txt" "  reply: explain and decide in one concrete scenario from the project's world, five lines at most; no paths, symbols, config keys or raw values in the prose; code, commands, exact errors, test results and warnings stay verbatim\." \
    "the turn's context carries the reply rule line"
  hook prompt-submit.sh '{"session_id":"p1","hook_event_name":"UserPromptSubmit","prompt":"<command-name>/omega:reply</command-name><command-args>3</command-args>"}'
  assert_contains "$CFG/omega/modes/p1" "^reply$" "/omega:reply 3 changes nothing"
  hook prompt-submit.sh '{"session_id":"p1","hook_event_name":"UserPromptSubmit","prompt":"<command-name>/omega:reply</command-name><command-args>off</command-args>"}'
  assert_not_contains "$CFG/omega/modes/p1" "^reply" "/omega:reply off clears reply"

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
  hook prompt-submit.sh '{"session_id":"p2","hook_event_name":"UserPromptSubmit","prompt":"<command-name>/omega:autopilot</command-name><command-args>off</command-args>"}'
  assert_missing "$CFG/omega/modes/p2" "/omega:autopilot off clears autopilot (the last mode)"
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

# The raw shape (#11): Claude Code 2.1.286 sends a typed command as the text
# as typed, "prompt":"/omega:<mode> <args>", with no envelope. Session r1,
# fresh, so these do not depend on test_prompt_submit's history.
test_prompt_submit_raw_shape() {
  mode --session r1 clear --all
  hook prompt-submit.sh '{"session_id":"r1","hook_event_name":"UserPromptSubmit","prompt":"/omega:parallel 3"}'
  assert_eq "parallel max=3" "$(mode --session r1 show)" "raw /omega:parallel 3 sets parallel max=3"
  context > "$TMP/ctx-raw.txt"
  assert_contains "$TMP/ctx-raw.txt" "Omega modes: parallel max=3" "raw: the turn's context carries the modes block"
  hook prompt-submit.sh '{"session_id":"r1","hook_event_name":"UserPromptSubmit","prompt":"/omega:parallel off"}'
  assert_eq "" "$(mode --session r1 show)" "raw /omega:parallel off clears parallel"

  hook prompt-submit.sh '{"session_id":"r1","hook_event_name":"UserPromptSubmit","prompt":"/omega:reply"}'
  assert_eq "reply" "$(mode --session r1 show)" "raw /omega:reply with no args sets reply"
  hook prompt-submit.sh '{"session_id":"r1","hook_event_name":"UserPromptSubmit","prompt":"  /omega:delegate  "}'
  assert_contains "$CFG/omega/modes/r1" "^delegate$" "raw: surrounding whitespace is ignored"
  hook prompt-submit.sh '{"session_id":"r1","hook_event_name":"UserPromptSubmit","prompt":"/omega:integration start ui-rework"}'
  assert_contains "$CFG/omega/modes/r1" "^integration slug=ui-rework$" "raw /omega:integration start <slug> sets the slug"
  mode --session r1 clear --all

  hook prompt-submit.sh '{"session_id":"r1","hook_event_name":"UserPromptSubmit","prompt":"/omega:autopilot"}'
  assert_eq "" "$(mode --session r1 show)" "raw /omega:autopilot arms nothing"
  mode --session r1 set autopilot
  hook prompt-submit.sh '{"session_id":"r1","hook_event_name":"UserPromptSubmit","prompt":"/omega:autopilot off"}'
  assert_eq "" "$(mode --session r1 show)" "raw /omega:autopilot off clears autopilot"

  hook prompt-submit.sh '{"session_id":"r1","hook_event_name":"UserPromptSubmit","prompt":"/omega:replyx"}'
  assert_eq "" "$(mode --session r1 show)" "raw: a longer name is not the mode"
  hook prompt-submit.sh '{"session_id":"r1","hook_event_name":"UserPromptSubmit","prompt":"/omega:parallel lots"}'
  assert_eq "" "$(mode --session r1 show)" "raw: a non-numeric parallel argument changes nothing"
  hook prompt-submit.sh '{"session_id":"r1","hook_event_name":"UserPromptSubmit","prompt":"/omega:reply 3"}'
  assert_eq "" "$(mode --session r1 show)" "raw /omega:reply 3 changes nothing"
  hook prompt-submit.sh '{"session_id":"r1","hook_event_name":"UserPromptSubmit","prompt":"/omega:handoff"}'
  assert_eq "" "$(mode --session r1 show)" "raw /omega:handoff changes nothing"
  hook prompt-submit.sh '{"session_id":"r1","hook_event_name":"UserPromptSubmit","prompt":"/caveman off"}'
  assert_eq "" "$(mode --session r1 show)" "raw: a foreign command changes nothing"
  hook prompt-submit.sh '{"session_id":"r1","hook_event_name":"UserPromptSubmit","prompt":"see /omega:reply"}'
  assert_eq "" "$(mode --session r1 show)" "raw: a command not at the start changes nothing"
  # The command is at the prompt's start, so only the scheduled-task guard
  # stops it.
  hook prompt-submit.sh '{"session_id":"r1","hook_event_name":"UserPromptSubmit","prompt":"/omega:reply <scheduled-task id=\"z\">"}'
  assert_eq "" "$(mode --session r1 show)" "raw: a scheduled-task prompt changes nothing"

  hook prompt-submit.sh '{"session_id":"r1","hook_event_name":"UserPromptSubmit","prompt":"/omega:reply\r\n"}'
  assert_eq "reply" "$(mode --session r1 show)" "raw: a CRLF ends the name"
  hook prompt-submit.sh '{"session_id":"r1","hook_event_name":"UserPromptSubmit","prompt":"/omega:parallel\t2"}'
  assert_contains "$CFG/omega/modes/r1" "^parallel max=2$" "raw: a tab separates the name from its args"
  hook prompt-submit.sh '{"session_id":"r1","hook_event_name":"UserPromptSubmit","prompt":"/omega:parallel\n3"}'
  assert_contains "$CFG/omega/modes/r1" "^parallel max=3$" "raw: a newline separates the name from its args"
  hook prompt-submit.sh '{"session_id":"r1","hook_event_name":"UserPromptSubmit","prompt":"/omega:local-merge"}'
  assert_contains "$CFG/omega/modes/r1" "^local-merge$" "raw /omega:local-merge sets local-merge"
  mode --session r1 clear --all
  hook prompt-submit.sh '{"session_id":"r1","hook_event_name":"UserPromptSubmit","prompt":"/omega:parallel 3\nfix the menu"}'
  assert_eq "" "$(mode --session r1 show)" "raw: a command followed by more lines of text changes nothing"
  hook prompt-submit.sh '{"session_id":"r1","hook_event_name":"UserPromptSubmit","prompt":"/omega:parallel 0"}'
  assert_eq "" "$(mode --session r1 show)" "raw /omega:parallel 0 sets nothing"
  hook prompt-submit.sh '{"session_id":"r1","hook_event_name":"UserPromptSubmit","prompt":"/omega:integration finish"}'
  assert_eq "" "$(mode --session r1 show)" "raw /omega:integration finish leaves the mode to the skill"
  hook prompt-submit.sh '{"session_id":"r1","hook_event_name":"UserPromptSubmit","prompt":"/omega:integration start bad/slug"}'
  assert_eq "" "$(mode --session r1 show)" "raw: a slug with a slash changes nothing"
  hook prompt-submit.sh '{"session_id":"r1","hook_event_name":"UserPromptSubmit","prompt":"/omega:delegate \"now\""}'
  assert_eq "" "$(mode --session r1 show)" "raw: args with a quote change nothing"
  assert_eq "" "$(cat "$TMP/hook.err")" "raw: stderr stays empty"
  mode --session r1 clear --all
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

  hook pre-tool-use.sh '{"session_id":"d1","transcript_path":"'"$main_t"'","cwd":"'"$repo"'","hook_event_name":"PreToolUse","agent_type":"general-purpose","tool_name":"Write","tool_input":{"file_path":"'"$repo"'/src/a.gd","content":"x"}}'
  assert_eq "" "$(cat "$TMP/hook.out")" "a subagent's Write is allowed by agent_type alone"

  # A path git ignores is scratch, not the repository — the SDD workspace
  # under .superpowers/ must stay writable from the main session even
  # though it resolves under the repository root.
  echo ".superpowers/" > "$repo/.gitignore"
  hook pre-tool-use.sh "$(ptu Write file_path "$repo/.superpowers/sdd/p/progress.md" "$main_t" "$repo" d1)"
  assert_eq "" "$(cat "$TMP/hook.out")" "a Write under a path git ignores is scratch, not the repository"
  hook pre-tool-use.sh "$(ptu Write file_path "$repo/src/a.gd" "$main_t" "$repo" d1)"
  assert_contains "$TMP/hook.out" '"permissionDecision":"deny"' "a tracked path still denies after the ignore check"
  rm -f "$repo/.gitignore"

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


# AC15: no shipped path names the retired keep-awake tool or the in-session
# scheduler. The names are spelled split here, so this file is scanned too.
test_no_keepawake_or_cron() {
  pat="omega-""caffeine|Cron""Create"
  hits="$(cd "$REPO_ROOT" && grep -rlE "$pat" shared studios tests README.md install.sh 2>/dev/null)"
  assert_eq "" "$hits" "no shipped path names the retired tools"
  assert_missing "$REPO_ROOT/shared/omega/bin/omega-""caffeine" "the keep-awake tool is deleted"
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
  assert_eq 7 "$ran" "seven skill contracts ran"
}

run_tests test_plugin_files test_skill_stubs test_marketplace \
  test_mode_round_trip test_mode_validation test_mode_brief test_mode_env_autopilot \
  test_hooks_json test_session_start test_session_start_prunes_old_files \
  test_prompt_submit test_prompt_submit_raw_shape test_session_end test_pre_tool_use \
  test_no_keepawake_or_cron test_skill_contracts
