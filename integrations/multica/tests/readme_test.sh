#!/bin/sh
# Contract test for integrations/multica/README.md (#28, Teaching): the sections, the
# teaching phrases, and that every documented flag and command exists in the code and
# every flag and command in the code is documented.
set -u
REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd -P)"
. "$REPO_ROOT/tests/assert.sh"
M="$REPO_ROOT/integrations/multica"
R="$M/README.md"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

test_readme_sections() {
  prev=0
  for name in "Modes" "Install" "File-access grants" "Commands" "What the board shows" \
      "Troubleshooting" "Known risks" "Uninstall and swapping Multica out"; do
    TESTS_RUN=$((TESTS_RUN + 1))
    n="$(grep -n -x -F -- "## $name" "$R" 2>/dev/null | sed -n 1p | cut -d: -f1)"
    if [ -n "$n" ] && [ "$n" -gt "$prev" ]; then _pass "section $name"; prev="$n"
    else _fail "section $name missing or out of order"; fi
  done
}

test_readme_teaching_phrases() {
  while IFS= read -r phrase; do
    [ -n "$phrase" ] || continue
    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -q -F -- "$phrase" "$R" 2>/dev/null; then _pass "phrase: $phrase"
    else _fail "phrase missing: $phrase"; fi
  done <<'PHRASES'
claude-gd
claude-multica
omega-multica-agent
install.sh --workspace-id
--new-token
--agent
--project
uninstall.sh --profiles
--purge
Files and Folders
Full Disk Access
Documents Folder
multica-bridge status
/say
/unit
/hold
/resume
/stop
/stop run
/unsay
/said
edited comments are not re-read
finished runs get no reply
assigned to an agent are ignored
studio-overnight start --detach
delete the integrations/multica folder
or point autopilot at an existing plan
PHRASES
}

# Every --flag in install.sh --help and uninstall.sh --help is in the README.
test_readme_flags_match_install() {
  sh "$M/install.sh" --help > "$TMP/ih" 2>&1
  sh "$M/uninstall.sh" --help > "$TMP/uh" 2>&1
  cat "$TMP/ih" "$TMP/uh" | grep -o -e '--[a-z][a-z-]*' | sort -u > "$TMP/flags"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -s "$TMP/flags" ]; then _pass "help output yields flags"; else _fail "no flags in help output"; fi
  while IFS= read -r f; do
    [ "$f" = "--help" ] && continue
    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -q -F -- "$f" "$R" 2>/dev/null; then _pass "flag documented: $f"
    else _fail "flag not in README: $f"; fi
  done < "$TMP/flags"
}

# Every --flag the README names exists in a help output (or is the core's --detach).
test_readme_flags_exist() {
  sh "$M/install.sh" --help > "$TMP/ih" 2>&1
  sh "$M/uninstall.sh" --help > "$TMP/uh" 2>&1
  grep -o -e '--[a-z][a-z-]*' "$R" 2>/dev/null | sort -u > "$TMP/rflags"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -s "$TMP/rflags" ]; then _pass "README names flags"; else _fail "README names no flags"; fi
  while IFS= read -r f; do
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$f" = "--detach" ] || grep -q -F -- "$f" "$TMP/ih" "$TMP/uh"; then _pass "flag exists: $f"
    else _fail "README names a flag no script has: $f"; fi
  done < "$TMP/rflags"
}

# Every command in bridge/commands.py is in the README, and every `/word` in the README
# is a command there.
test_readme_commands_match_code() {
  sed -n 's/^COMMANDS = (\(.*\))$/\1/p' "$M/bridge/commands.py" | tr ',' '\n' | tr -d '" ' | grep . > "$TMP/cmds"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "$(wc -l < "$TMP/cmds" | tr -d ' ')" -ge 7 ]; then _pass "code lists commands"; else _fail "no COMMANDS in commands.py"; fi
  while IFS= read -r c; do
    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -q -F -- "\`/$c" "$R" 2>/dev/null; then _pass "command documented: /$c"
    else _fail "command not in README: /$c"; fi
  done < "$TMP/cmds"
  # Claude Code commands are not bridge commands: namespaced skills (`/ns:name`) and `/clear`.
  grep -o '`/[a-z][a-z-]*:\{0,1\}' "$R" 2>/dev/null | cut -c3- | grep -v ':$' | grep -v -x clear | sort -u > "$TMP/rcmds"
  while IFS= read -r c; do
    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -q -x -F -- "$c" "$TMP/cmds"; then _pass "README command exists: /$c"
    else _fail "README names a command the bridge lacks: /$c"; fi
  done < "$TMP/rcmds"
}

# The status table names every state in mirror.STATUS with its board status.
test_readme_status_table_matches_code() {
  sed -n '/^STATUS = {/,/}/p' "$M/bridge/mirror.py" | grep -o '"[a-z-]*": "[a-z_]*"' | tr -d '" ' > "$TMP/st"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -s "$TMP/st" ]; then _pass "code lists story states"; else _fail "no STATUS in mirror.py"; fi
  while IFS=: read -r s b; do
    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -F -- "\`$s\`" "$R" 2>/dev/null | grep -q -F -- "\`$b\`"; then _pass "state row: $s -> $b"
    else _fail "state row missing or wrong: $s -> $b"; fi
  done < "$TMP/st"
}

# The README points at multica-deny.txt and never copies its rules.
test_readme_deny_list_by_reference() {
  assert_contains "$R" "multica-deny.txt" "README points at multica-deny.txt"
  assert_not_contains "$R" "Bash(" "README does not enumerate deny rules"
}

# The known risks the rulings require.
test_readme_known_risks() {
  assert_contains "$R" "deterrent, not a sandbox" "risk: deny list is a deterrent"
  assert_contains "$R" "bypassPermissions" "risk: agents run with bypassPermissions"
  assert_contains "$R" "outside a git checkout" "risk: deny-rules outside a git checkout"
  assert_contains "$R" "push-to-default" "risk: push-to-default rules dropped"
}

# The ~/Documents step text in the README is the text install.sh prints (one wording, two places).
test_readme_p5_text_matches_install() {
  sed -n "s/^P5_TEXT='\(.*\)'\$/\1/p" "$M/install.sh" > "$TMP/p5"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -s "$TMP/p5" ]; then _pass "install.sh has the P5 text"; else _fail "no P5_TEXT in install.sh"; fi
  TESTS_RUN=$((TESTS_RUN + 1))
  if grep -q -F -f "$TMP/p5" "$R"; then _pass "README quotes the install.sh P5 text"
  else _fail "README does not contain the P5 text of install.sh"; fi
}

# Every command install.sh links into ~/.local/bin is named in the README.
test_readme_names_every_linked_command() {
  for c in $(sed -n 's/^link_wrapper \([a-z-]*\).*/\1/p' "$M/install.sh"); do
    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -q -F -- "\`$c\`" "$R"; then _pass "README names $c"; else _fail "README does not name the linked command $c"; fi
  done
}

test_agent_instructions_adopted_line() {
  assert_contains "$M/agent-instructions.md" "^- For adopted stories, include the report's studio-adopt line in your summary\.$" "AC23"
}

run_tests test_agent_instructions_adopted_line test_readme_sections test_readme_teaching_phrases test_readme_flags_match_install \
  test_readme_flags_exist test_readme_commands_match_code test_readme_status_table_matches_code \
  test_readme_deny_list_by_reference test_readme_known_risks test_readme_p5_text_matches_install \
  test_readme_names_every_linked_command
