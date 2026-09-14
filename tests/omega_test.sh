#!/bin/sh
# Tests for the omega global plugin: manifest, skill stubs, marketplace
# manifest, omega-mode, and the three hooks. Runs without a config root:
# omega-mode and the hooks are pointed at a temporary CLAUDE_CONFIG_DIR.
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
  for s in handoff parallel local-merge integration autopilot; do
    assert_file "$OMEGA/skills/$s/SKILL.md" "omega ships the $s skill"
  done
  assert_missing "$OMEGA/requires.txt" "omega declares no hard dependencies"
  assert_missing "$OMEGA/settings.json" "omega has no settings.json"
}

test_skill_stubs() {
  for s in handoff parallel local-merge integration autopilot; do
    f="$OMEGA/skills/$s/SKILL.md"
    assert_eq "---" "$(head -n 1 "$f")" "omega:$s starts with frontmatter"
    assert_eq "$s" "$(first_field "$f" name)" "omega:$s frontmatter name matches its directory"
    TESTS_RUN=$((TESTS_RUN + 1))
    case "$(first_field "$f" description)" in
      "Use when"*) _pass "omega:$s description starts with 'Use when'" ;;
      *) _fail "omega:$s description starts with 'Use when'" ;;
    esac
  done
  for s in parallel local-merge integration autopilot; do
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
}

test_mode_brief() {
  rm -rf "$CFG"
  assert_status 0 "brief exits 0 when no mode is set" -- mode --session t4 brief
  assert_eq "" "$(mode --session t4 brief)" "brief prints nothing when no mode is set"
  mode --session t4 set parallel max=3
  mode --session t4 set local-merge
  mode --session t4 set integration slug=ui-rework
  mode --session t4 set autopilot
  mode --session t4 brief > "$TMP/brief.txt"
  assert_eq "Omega modes: parallel max=3 · local-merge · integration slug=ui-rework · autopilot" \
    "$(head -n 1 "$TMP/brief.txt")" "brief's first line joins the modes with a middle dot"
  assert_contains "$TMP/brief.txt" "^  parallel: dispatch up to 3 ready tasks at once, each in its own worktree; review each; cherry-pick onto the feature branch; the invoking skill's bookkeeping is unchanged\.$" \
    "brief carries the parallel rule with its cap"
  assert_contains "$TMP/brief.txt" "^  local-merge: skip GitHub checks; run the project's local CI; merge through gh pr merge --admin only on exit 0; PR base is the integration branch when one is set\.$" \
    "brief carries the local-merge rule"
  assert_contains "$TMP/brief.txt" "^  integration: story branches PR into integration/ui-rework; docs/integrations/ui-rework\.md is the set; finish only when every row is merged\.$" \
    "brief carries the integration rule with its slug"
  assert_contains "$TMP/brief.txt" "^  autopilot: never AskUserQuestion — rule by the standards, log the ruling with its cost if wrong, continue; commit, push and open a PR, never merge; end with handoff\.$" \
    "brief carries the autopilot rule"
  assert_eq "5" "$(wc -l < "$TMP/brief.txt" | tr -d ' ')" "brief is the header plus one line per mode"
  mode --session t4 set parallel
  mode --session t4 brief > "$TMP/brief2.txt"
  assert_contains "$TMP/brief2.txt" "^  parallel: dispatch every ready task at once, each in its own worktree; review each; cherry-pick onto the feature branch; the invoking skill's bookkeeping is unchanged\.$" \
    "brief says every ready task when parallel has no cap"
  mode --session t4 set custom-mode key=value
  mode --session t4 brief > "$TMP/brief3.txt"
  assert_contains "$TMP/brief3.txt" "custom-mode key=value" "an unknown mode is listed in the header"
  assert_eq "5" "$(wc -l < "$TMP/brief3.txt" | tr -d ' ')" "an unknown mode gets no rule line"
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
  assert_contains "$TMP/ctx.txt" "Omega global skills: /omega:handoff, /omega:parallel \[N|off\], /omega:local-merge \[off\], /omega:integration <start|add|status|finish>, /omega:autopilot \[off\]\." \
    "context names the five skills"
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
  hook session-start.sh '{"session_id":"s2","hook_event_name":"SessionStart","source":"startup"}'
  assert_missing "$CFG/omega/modes/old" "a mode file older than seven days is pruned"
  assert_file "$CFG/omega/modes/fresh" "a fresh mode file survives"
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

  hook prompt-submit.sh '{"session_id":"p1","hook_event_name":"UserPromptSubmit","prompt":"<command-message>autopilot</command-message>\n<command-name>/omega:autopilot</command-name>"}'
  assert_contains "$CFG/omega/modes/p1" "^autopilot$" "an envelope without command-args sets the bare mode"

  hook prompt-submit.sh '{"session_id":"p1","hook_event_name":"UserPromptSubmit","prompt":"<command-name>/omega:parallel</command-name><command-args>  </command-args>"}'
  assert_contains "$CFG/omega/modes/p1" "^parallel$" "whitespace-only args set the bare mode"
  mode --session p1 clear parallel

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

run_tests test_plugin_files test_skill_stubs test_marketplace \
  test_mode_round_trip test_mode_validation test_mode_brief \
  test_hooks_json test_session_start test_session_start_prunes_old_files \
  test_prompt_submit test_session_end
