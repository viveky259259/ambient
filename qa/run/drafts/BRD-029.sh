#!/bin/zsh
# BRD-029 · With summaries on, cards get a short local summary.
# needs-app: no
# timeout: 300
# checks: part
# Left to a person: the green *Local LLM ready* / *Summarizing…* subtitle, the summary cut to 60 characters on the card,
# the brain icon and its tooltip.
# Starts the QA app itself with summaries on and a fake local-agent gateway serving the default model id (see
# qa/run/board-lib.sh), and replays a Claude Code session that edits a file for a little under a minute.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/board-lib.sh"

gw_config "[$(gw_model hf:mlx-community/Qwen2.5-0.5B-Instruct-4bit chat)]"
fake_gateway
board_app taskLLMEnabled=YES
assert_eq "$(ambient task model --json | jq -r .status)" "Local LLM ready" "status"

DIR=$QA_ROOT/qa-board-a
mkdir -p $DIR
S='{"session_id":"brd029-claude","cwd":"'$DIR'"'
hook claude "$S"',"hook_event_name":"UserPromptSubmit","prompt":"fix the readme"}'
hook claude "$S"',"hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"'$DIR'/README.md"}}'
first=$SECONDS
wait_for 120 test "$(task_get "QA model title" .summary)" = "QA summary from the fake model"
note "summary after $((SECONDS - first)) s"
assert_eq "$(task_get "QA model title" .summarySource)" localLLM "summarySource (the brain icon)"
assert_eq "$(task_get "QA model title" .project)" qa-board-a "project"
prompt=$(jq -r 'select(.tool == "submit_inference") | .arguments.prompt' $QA_ROOT/gw.log | head -50)
assert_contains "$prompt" "project: qa-board-a" "the prompt sent to the gateway"

# Many events in the next 45 seconds: still one summary.
while (( SECONDS - first < 40 )); do
  hook claude "$S"',"hook_event_name":"PostToolUse","tool_name":"Edit","tool_input":{},"tool_response":{}}'
  hook claude "$S"',"hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"'$DIR'/README.md"}}'
  sleep 1
done
assert_eq "$(gw_calls submit_inference)" 1 "summaries in the first 40 seconds"
while (( SECONDS - first < 48 )); do sleep 1; done
hook claude "$S"',"hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"'$DIR'/README.md"}}'
wait_for 15 test "$(gw_calls submit_inference)" = 2
note "a second summary after 45 seconds"
