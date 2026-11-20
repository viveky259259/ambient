#!/bin/zsh
# BRD-001 · A new agent session becomes an In progress task.
# needs-app: yes
# checks: part
# Left to a person: the In progress column and its count on the board, the card's coral dot, *Claude*, mood dot and clock.
# Replays a Claude Code session in qa-board-a that runs a tool, in place of the real agent.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/board-lib.sh"

DIR=$QA_ROOT/qa-board-a
mkdir -p "$DIR"
S='{"session_id":"brd001-claude","cwd":"'$DIR'","transcript_path":"'$HOME'/.claude/projects/x/brd001-claude.jsonl"'
hook claude "$S"',"hook_event_name":"SessionStart","source":"startup"}'
hook claude "$S"',"hook_event_name":"UserPromptSubmit","prompt":"list the files"}'
start=$EPOCHREALTIME
hook claude "$S"',"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls"}}'
in_progress() { [[ $(ambient tasks --json | jq -r '[.[] | select(.status == "inProgress")] | length') == 1 ]]; }
wait_for 5 in_progress
ms=$(( (EPOCHREALTIME - start) * 1000 ))
(( ms < 1000 )) || fail "the task reached In progress ${ms%.*} ms after the first tool (want under 1000)"
note "In progress ${ms%.*} ms after the first tool"

json=$(ambient tasks --json)
assert_eq "$(print -r -- $json | jq length)" 1 "tasks on the board"
assert_eq "$(print -r -- $json | jq -r '.[0].status')" inProgress "status"
# No chat title in this home, so the title is the project name.
assert_eq "$(print -r -- $json | jq -r '.[0].title')" qa-board-a "title"
assert_eq "$(print -r -- $json | jq -r '.[0].project')" qa-board-a "project"
assert_eq "$(print -r -- $json | jq -r '.[0].agents | join(",")')" claude "agents"
assert_eq "$(print -r -- $json | jq -r '.[0].sessionIds | join(",")')" claude:brd001-claude "linked session"
