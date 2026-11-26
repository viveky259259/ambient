#!/bin/zsh
# BRD-033 · Only a loopback gateway address is used.
# needs-app: no
# timeout: 180
# checks: part
# Left to a person: the subtitle's amber colour.
# Starts the QA app itself with each gateway URL (the setting is in Settings › Board), see qa/run/board-lib.sh. The
# non-loopback URL is http://0.0.0.0:<port of this case's fake gateway>/mcp: not loopback by name, so it must be
# refused, but a request that got through would land on the fake gateway here instead of on another machine.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/board-lib.sh"

gw_config "[$(gw_model hf:mlx-community/Qwen2.5-0.5B-Instruct-4bit chat)]"
fake_gateway
board_app taskLLMEnabled=YES taskLLMMCPURL=http://0.0.0.0:$BOARD_GW_PORT/mcp
assert_eq "$(ambient task model --json | jq -r .status)" "MCP URL must be loopback (127.0.0.1 / localhost). Session text stays on this Mac." "status"
S='{"session_id":"brd033","cwd":"'$QA_ROOT'/api"'
hook claude "$S"',"hook_event_name":"UserPromptSubmit","prompt":"go"}'
hook claude "$S"',"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls"}}'
sleep 5
assert_eq "$(cat $QA_ROOT/gw.log 2>/dev/null | wc -l | tr -d ' ')" 0 "requests that reached the non-loopback address"
board_stop

for host in localhost 127.0.0.1; do
  board_app taskLLMEnabled=YES taskLLMMCPURL=http://$host:$BOARD_GW_PORT/mcp
  assert_eq "$(ambient task model --json | jq -r .status)" "Local LLM ready" "status for http://$host:<port>/mcp"
  board_stop
done
