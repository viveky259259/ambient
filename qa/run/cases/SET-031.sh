#!/bin/zsh
# SET-031 · A removed Ambient never breaks the agent.
# needs-app: no
# checks: part
# Runs each installed hook command the way Claude Code does (sh -c with the payload on stdin), in place of a real
# Claude Code session. Left to a person: a real Claude Code session finishing with no hook error.
source "$QA_REPO/qa/run/lib.sh"
export AMBIENT_HOME="$HOME/.ambient"

fake_agent claude
ambient install claude >/dev/null || fail "install exited $?"
cmds=("${(@f)$(jq -r '[.hooks[][].hooks[].command] | unique[]' "$HOME/.claude/settings.json")}")
assert_eq "${#cmds}" 1 "distinct hook commands"
assert_eq "${cmds[1]}" '[ -x "$HOME/.ambient/bin/ambient" ] && "$HOME/.ambient/bin/ambient" hook claude || true' "the guarded command"
link="$AMBIENT_HOME/bin/ambient"
payload='{"session_id":"gone","hook_event_name":"PreToolUse","cwd":"/tmp","tool_name":"Bash","tool_input":{"command":"ls"}}'

run_hook() { # label
  local start=$EPOCHREALTIME out code ms
  out=$(print -r -- "$payload" | /bin/sh -c "${cmds[1]}" 2>&1); code=$?
  ms=$(( (EPOCHREALTIME - start) * 1000 ))
  assert_eq "$code" 0 "hook exit code ($1)"
  assert_eq "$out" "" "hook output ($1)"
  (( ms < 1000 )) || fail "hook took ${ms%.*} ms ($1)"
  note "$1: exit 0, no output, ${ms%.*} ms"
}
mv "$link" "$QA_ROOT/ambient.aside"
run_hook "link moved aside"
ln -s "$QA_ROOT/no-such-app/ambient" "$link"
run_hook "dangling link"
rm "$link"; mv "$QA_ROOT/ambient.aside" "$link"
run_hook "link back, app quit"
