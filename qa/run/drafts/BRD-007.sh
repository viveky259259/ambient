#!/bin/zsh
# BRD-007 · A task whose session ends moves to Done and stays on the board.
# needs-app: yes
# checks: part
# Left to a person: the card without a mood dot or clock.
# Replays a Claude Code session that works and then ends (/exit sends SessionEnd).
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/board-lib.sh"

DIR=$QA_ROOT/qa-board-a
mkdir -p "$DIR"
S='{"session_id":"brd007-claude","cwd":"'$DIR'"'
hook claude "$S"',"hook_event_name":"UserPromptSubmit","prompt":"list files"}'
hook claude "$S"',"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls"}}'
wait_for 5 test "$(task_get qa-board-a .status)" = inProgress
hook claude "$S"',"hook_event_name":"SessionEnd","reason":"prompt_input_exit"}'
wait_for 5 test "$(task_get qa-board-a .status)" = done
json=$(ambient tasks --json)
assert_eq "$(print -r -- $json | jq length)" 1 "tasks on the board"
assert_eq "$(print -r -- $json | jq -r '.[0].title')" qa-board-a "title"
assert_eq "$(print -r -- $json | jq -r '.[0].project')" qa-board-a "project"
assert_eq "$(print -r -- $json | jq -r '.[0].agents | join(",")')" claude "agents"
# No live session linked, which is why the card has no mood dot or clock.
assert_eq "$(print -r -- $json | jq -r '.[0].sessionIds | length')" 0 "linked sessions"
