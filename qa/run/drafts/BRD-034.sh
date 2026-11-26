#!/bin/zsh
# BRD-034 · A missing gateway keeps the board working with a calm status.
# needs-app: no
# timeout: 180
# checks: part
# Left to a person: the amber colour, no alert or dialog, the subtitle turning back to *Local LLM ready* on screen.
# Starts the QA app itself with summaries on and its gateway URL on a free loopback port (see qa/run/board-lib.sh);
# a fake gateway starts there later.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/board-lib.sh"

gw_config "[$(gw_model hf:mlx-community/Qwen2.5-0.5B-Instruct-4bit chat)]"
fake_gateway
PORT=$BOARD_GW_PORT
kill $BOARD_GW_PID; wait $BOARD_GW_PID 2>/dev/null; BOARD_GW_PID=""
rm -f $QA_ROOT/gw.log
board_app taskLLMEnabled=YES taskLLMMCPURL=http://127.0.0.1:$PORT/mcp

status=$(ambient task model --json | jq -r .status)
note "status: $status"
[[ $status == "Couldn't reach local-agent at 127.0.0.1: "?* ]] || fail "status with the gateway down: [$status]"

S='{"session_id":"brd034","cwd":"'$QA_ROOT'/qa-board-a"'
hook claude "$S"',"hook_event_name":"UserPromptSubmit","prompt":"go"}'
hook claude "$S"',"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls"}}'
wait_for 5 test "$(task_get qa-board-a .status)" = inProgress
hook claude "$S"',"hook_event_name":"Notification","message":"Claude needs your permission to use Bash","notification_type":"permission_prompt"}'
wait_for 5 test "$(task_get qa-board-a .status)" = blocked

# The gateway comes back: the app's own check finds it within 30 seconds, without anyone asking.
fake_gateway $PORT
start=$SECONDS
wait_for 35 grep -q '"tool": "list_models"' $QA_ROOT/gw.log
note "the app checked the gateway again $((SECONDS - start)) s after it came back"
assert_eq "$(ambient task model --json | jq -r .status)" "Local LLM ready" "status once the gateway is back"
