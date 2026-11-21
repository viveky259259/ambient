#!/bin/zsh
# EVT-035 · Tool output never leaves the hook or reaches the disk.
# needs-app: yes
# Replays a recorded Claude Code turn whose tool output holds a canary, in place of a real agent.
source "$QA_REPO/qa/run/lib.sh"
export AMBIENT_DEBUG=1

S='{"session_id":"canary-run","cwd":"'$QA_ROOT'/api"'
hook claude "$S"',"hook_event_name":"UserPromptSubmit","prompt":"run it"}'
hook claude "$S"',"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"printf '"'"'canary-%s\\n'"'"' 9931"}}'
hook claude "$S"',"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"printf '"'"'canary-%s\\n'"'"' 9931"},"tool_response":{"stdout":"canary-9931\n","stderr":"","interrupted":false}}'
hook claude "$S"',"hook_event_name":"Stop","last_assistant_message":"finished"}'

wait_for 5 grep -q canary-run "$AMBIENT_HOME/state.json"
note "state: $(state_get '.sessions[] | select(.sessionId=="canary-run" or .id=="canary-run") | .activity | tostring' | head -1)"
hits=$(grep -rl 'canary-9931' "$AMBIENT_HOME" 2>/dev/null)
assert_eq "$hits" "" "files under AMBIENT_HOME holding the tool output"
