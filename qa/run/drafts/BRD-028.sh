#!/bin/zsh
# BRD-028 · Summaries are off by default and nothing is called while they are.
# needs-app: no
# timeout: 300
# checks: part
# Left to a person: the switch, its grey subtitle and the greyed *Read your agent chats* in Settings › Board.
# Starts the QA app itself (see qa/run/board-lib.sh) leaving summaries to the app's default, with the gateway URL of a
# fake gateway that logs every connection, in place of a listener on 127.0.0.1:5051 (the real gateway's port).
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/board-lib.sh"

# The default only shows on a settings domain no earlier case left a value in (the runner clears it for app cases).
if defaults read com.viveky259259.Ambient.qa taskLLMEnabled >/dev/null 2>&1; then
  echo "an earlier case left taskLLMEnabled in the QA app's settings; run this case after an app case" >&2
  exit 2
fi
gw_config "[$(gw_model hf:mlx-community/Qwen2.5-0.5B-Instruct-4bit chat)]"
fake_gateway
fake_llama "$BOARD_BIN/llama-completion"
board_app taskLLMEnabled=- taskLLMReadTranscripts=-

# A few agent sessions over a little more than the app's 30-second status check.
for i in 1 2 3; do
  S='{"session_id":"brd028-'$i'","cwd":"'$QA_ROOT'/proj-'$i'"'
  hook claude "$S"',"hook_event_name":"UserPromptSubmit","prompt":"work"}'
  hook claude "$S"',"hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"'$QA_ROOT'/proj-'$i'/a.txt"}}'
done
end=$((SECONDS + 35))
while (( SECONDS < end )); do
  for i in 1 2 3; do
    hook claude '{"session_id":"brd028-'$i'","cwd":"'$QA_ROOT'/proj-'$i'","hook_event_name":"PostToolUse","tool_name":"Edit","tool_input":{},"tool_response":{}}'
  done
  children=$(ps -A -o ppid=,comm= | awk -v p=$BOARD_APP_PID '$1 == p {print $2}')
  [[ -z $children ]] || fail "the app started a process with summaries off: $children"
  sleep 2
done
assert_eq "$(cat $QA_ROOT/gw.log 2>/dev/null | wc -l | tr -d ' ')" 0 "requests the gateway received with summaries off"
assert_no_file "$QA_ROOT/fakepy.log"
assert_no_file "$QA_ROOT/llama.log"
assert_eq "$(task_count)" 3 "tasks"
assert_eq "$(ambient tasks --json | jq -r 'map(.summarySource) | unique | join(",")')" heuristic "where the cards' text came from (no brain icon)"
assert_eq "$(ambient tasks --json | jq -r 'map(.summary // "") | join("")')" "" "summaries on the cards"
# Only now ask the app, which reports summaries off (its report does reach the gateway).
assert_eq "$(ambient task model --json | jq -r .summaries)" off "summaries setting"
