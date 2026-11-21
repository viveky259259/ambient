#!/bin/zsh
# BRD-030 · A model's reply never clears Blocked while you're needed.
# needs-app: no
# timeout: 240
# Starts the QA app itself with summaries on and a fake local-agent gateway (see qa/run/board-lib.sh) whose model
# always answers status inProgress or done, and replays the sessions the tests named in the case set up.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/board-lib.sh"

ID=hf:mlx-community/Qwen2.5-0.5B-Instruct-4bit
gw_config "[$(gw_model $ID chat)]" "" '{"title":"Model title","summary":"Model says it is working","status":"inProgress"}'
fake_gateway
board_app taskLLMEnabled=YES

# 1. A live waiting session: the reply says inProgress, the task stays Blocked.
S='{"session_id":"brd030-wait","cwd":"'$QA_ROOT'/waiting"'
hook claude "$S"',"hook_event_name":"Notification","message":"Claude needs your permission to use Bash","notification_type":"permission_prompt"}'
wait_for 30 test "$(ambient tasks --json | jq -r '.[] | select(.project == "waiting") | .summarySource')" = localLLM
assert_eq "$(ambient tasks --json | jq -r '.[] | select(.project == "waiting") | .status')" blocked "status after an inProgress reply while waiting"

# 2. A task you wrote: the reply changes neither its status nor its title.
gw_config "[$(gw_model $ID chat)]" "" '{"title":"Model title","summary":"Model says it is done","status":"done"}'
ambient task upsert --title "Hand-made" --status backlog --session custom:brd030-manual >/dev/null || fail "upsert failed"
ambient emit working --session brd030-manual --tool make --detail "make all" --cwd "$QA_ROOT/manual" || fail "emit failed"
wait_for 30 test "$(ambient tasks --json | jq -r '.[] | select(.sessionIds | index("custom:brd030-manual")) | .summarySource')" = localLLM
t=$(ambient tasks --json | jq -c '.[] | select(.sessionIds | index("custom:brd030-manual"))')
assert_eq "$(print -r -- $t | jq -r .summary)" "Model says it is done" "the summary applied"
assert_eq "$(print -r -- $t | jq -r .title)" Hand-made "title of a task you wrote"
assert_eq "$(print -r -- $t | jq -r .status)" backlog "status of a task you wrote"

# 3. A reply that lands after the session ended doesn't reopen the task.
GW_JOB_SECONDS=6 gw_config "[$(gw_model $ID chat)]" "" '{"title":"Late title","summary":"Late summary","status":"inProgress"}'
L='{"session_id":"brd030-late","cwd":"'$QA_ROOT'/late"'
hook claude "$L"',"hook_event_name":"UserPromptSubmit","prompt":"go"}'
wait_for 10 test "$(gw_calls submit_inference)" = 3
hook claude "$L"',"hook_event_name":"SessionEnd","reason":"prompt_input_exit"}'
wait_for 5 test "$(ambient tasks --json | jq -r '.[] | select(.project == "late") | .status')" = done
wait_for 30 test "$(ambient tasks --json | jq -r '.[] | select(.project == "late") | .summary')" = "Late summary"
assert_eq "$(ambient tasks --json | jq -r '.[] | select(.project == "late") | .status')" done "status after a late inProgress reply"
