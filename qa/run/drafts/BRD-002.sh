#!/bin/zsh
# BRD-002 · Sessions in the same project with the same title on the same day share one task.
# needs-app: yes
# checks: part
# Left to a person: the card's coral and green dots and *Claude · Codex* on the board.
# Replays a Claude Code session and then a Codex session in the same folder, in place of the real agents.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/board-lib.sh"

DIR=$QA_ROOT/qa-board-a
mkdir -p "$DIR"
C='{"session_id":"brd002-claude","cwd":"'$DIR'"'
hook claude "$C"',"hook_event_name":"UserPromptSubmit","prompt":"look around"}'
hook claude "$C"',"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls"}}'
wait_for 5 test "$(task_count)" = 1

X='{"session_id":"019a0000-brd2-7000-8000-000000000002","cwd":"'$DIR'","transcript_path":"'$HOME'/.codex/sessions/rollout.jsonl","model":"gpt-5-codex"'
hook codex "$X"',"hook_event_name":"UserPromptSubmit","prompt":"run the tests"}'
hook codex "$X"',"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"make test"}}'
has_codex() { ambient tasks --json | jq -e 'any(.[]; .agents | index("codex"))' >/dev/null; }
wait_for 5 has_codex

json=$(ambient tasks --json)
assert_eq "$(print -r -- $json | jq length)" 1 "tasks on the board"
assert_eq "$(print -r -- $json | jq -r '.[0].title')" qa-board-a "title"
assert_eq "$(print -r -- $json | jq -r '.[0].agents | join(",")')" claude,codex "agents"
assert_eq "$(print -r -- $json | jq -r '.[0].sessionIds | length')" 2 "linked sessions"

line=$(ambient tasks | grep qa-board-a)
assert_eq "$(ambient tasks | grep -c qa-board-a)" 1 "lines for the project in ambient tasks"
assert_contains "$line" "claude,codex" "ambient tasks line"
