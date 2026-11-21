#!/bin/zsh
# BRD-024 · `ambient tasks` lists the board.
# needs-app: no
# Starts the QA app itself (see qa/run/board-lib.sh) so step 3 can quit it.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/board-lib.sh"
board_app

out=$(ambient tasks)
assert_eq "$out" "Board · no tasks" "empty board"
ambient task upsert --title "Only one" --id task-qa000024 >/dev/null || fail "upsert failed"
assert_eq "$(ambient tasks | head -1)" "Board · 1 task" "one task"

LONG="A title that is much longer than forty characters in all"
ambient task upsert --title "$LONG" --project site --status inProgress --id task-qa000025 >/dev/null || fail "upsert failed"
ambient task upsert --title "Stuck" --status blocked --id task-qa000026 >/dev/null || fail "upsert failed"
S='{"session_id":"brd024-claude","cwd":"'$QA_ROOT'/api"'
hook claude "$S"',"hook_event_name":"UserPromptSubmit","prompt":"go"}'
hook claude "$S"',"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls"}}'
wait_for 5 test "$(task_count)" = 4
agent_id=$(task_get api .id)

# Step 1.
out=$(ambient tasks)
print -r -- "$out" | sed 's/^/    /'
lines=("${(@f)out}")
assert_eq "${#lines}" 5 "lines printed"
assert_eq "${lines[1]}" "Board · 4 tasks" "header"
row() { print -r -- "  ${(r:10:)1} ${(r:16:)2} $3  $4  $5"; }
# Board order: blocked, in progress (newest first), backlog.
assert_eq "${lines[2]}" "$(row blocked — Stuck — task-qa000026)" "blocked row"
assert_eq "${lines[3]}" "$(row inProgress api api claude $agent_id)" "agent task row"
assert_eq "${lines[4]}" "$(row inProgress site "${LONG:0:39}…" — task-qa000025)" "long-title row (cut to 40)"
assert_eq "${lines[5]}" "$(row backlog — "Only one" — task-qa000024)" "backlog row"

# Step 2: pretty, key-sorted JSON with ISO 8601 dates.
json=$(ambient tasks --json)
print -r -- "$json" | jq -e 'type == "array" and length == 4' >/dev/null || fail "--json is not an array of 4 tasks"
assert_eq "$json" "$(print -r -- $json | jq -S --indent 2 .)" "--json is pretty-printed with sorted keys"
date=$(print -r -- $json | jq -r '.[0].createdAt')
[[ $date == <->-<->-<->T<->:<->:<->Z ]] || fail "createdAt is not ISO 8601: $date"
assert_eq "$(print -r -- $json | jq -r 'map(.id) | join(",")')" "task-qa000026,$agent_id,task-qa000025,task-qa000024" "--json in board order"

# Step 3: Ambient quit.
board_stop
out=$(ambient tasks 2>&1); code=$?
assert_eq "$code" 1 "exit code with Ambient closed"
assert_eq "$(unmark "$out")" "Ambient isn't running. Open Ambient.app, then try again." "message with Ambient closed"
