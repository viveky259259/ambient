#!/bin/zsh
# BRD-023 · The board file is readable only by you.
# needs-app: yes
# Replays a Claude Code turn whose prompt and tool output hold canaries, then checks tasks.json.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/board-lib.sh"

ambient task upsert --title "Mode check" >/dev/null || fail "upsert failed"
S='{"session_id":"brd023-claude","cwd":"'$QA_ROOT'/api"'
hook claude "$S"',"hook_event_name":"UserPromptSubmit","prompt":"prompt-canary-5521 do it"}'
hook claude "$S"',"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"printf out"}}'
hook claude "$S"',"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"printf out"},"tool_response":{"stdout":"output-canary-7713\n","stderr":"","interrupted":false}}'
hook claude "$S"',"hook_event_name":"Stop","last_assistant_message":"done"}'
sleep 2
F=$AMBIENT_HOME/tasks.json
assert_file "$F"
assert_mode "$F" 600
assert_eq "$(stat -f %Su "$F")" "$USER" "owner of tasks.json"
assert_mode "$AMBIENT_HOME" 700
assert_contains "$(cat $F)" "Mode check" "tasks.json"
assert_contains "$(cat $F)" '"project":"api"' "tasks.json"
assert_not_contains "$(cat $F)" "prompt-canary-5521" "the prompt in tasks.json"
assert_not_contains "$(cat $F)" "output-canary-7713" "tool output in tasks.json"
