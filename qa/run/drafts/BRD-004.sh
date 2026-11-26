#!/bin/zsh
# BRD-004 · A session that needs you moves its task to Blocked, the first column.
# needs-app: yes
# checks: part
# Left to a person: the card moving on the board and its amber mood dot; columns drawn left to right, empty ones hidden.
# Replays Claude Code's permission prompt (Notification permission_prompt) and the tool running after approval.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/board-lib.sh"

DIR=$QA_ROOT/qa-board-a
mkdir -p "$DIR"
S='{"session_id":"brd004-claude","cwd":"'$DIR'"'
hook claude "$S"',"hook_event_name":"UserPromptSubmit","prompt":"clean the build"}'
hook claude "$S"',"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"rm -rf build"}}'
wait_for 5 test "$(task_get qa-board-a .status)" = inProgress
# A task in another column, so the order of columns can be read from `ambient tasks`.
ambient task upsert --title "Later" >/dev/null || fail "upsert failed"
ambient task upsert --title "Finished" --status done >/dev/null || fail "upsert failed"

start=$EPOCHREALTIME
hook claude "$S"',"hook_event_name":"Notification","message":"Claude needs your permission to use Bash","notification_type":"permission_prompt"}'
wait_for 5 test "$(task_get qa-board-a .status)" = blocked
ms=$(( (EPOCHREALTIME - start) * 1000 ))
(( ms < 1000 )) || fail "the task reached Blocked ${ms%.*} ms after the prompt (want under 1000)"
note "Blocked ${ms%.*} ms after the prompt"
# Board order: Blocked first, then the other columns in their order.
assert_eq "$(ambient tasks --json | jq -r 'map(.status) | join(",")')" "blocked,backlog,done" "board order"
ambient tasks | sed 's/^/    /'

# Approved in the terminal: the tool runs.
hook claude "$S"',"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"rm -rf build"},"tool_response":{"stdout":"","stderr":"","interrupted":false}}'
wait_for 5 test "$(task_get qa-board-a .status)" = inProgress
assert_eq "$(ambient tasks --json | jq -r 'map(.status) | join(",")')" "inProgress,backlog,done" "board order after approving"
