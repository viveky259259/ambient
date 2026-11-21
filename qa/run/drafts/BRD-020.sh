#!/bin/zsh
# BRD-020 · Tasks you add yourself never expire.
# needs-app: no
# timeout: 180
# Starts the QA app itself on a seeded tasks.json (see qa/run/board-lib.sh): one task you wrote 30 days ago and 4,999
# agent-made tasks, a full board of 5,000; then one more agent session needs room.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/board-lib.sh"

now=$(ref_date 0)
{
  seed_task task-manual "Written by me" backlog $(( now - 30 * 86400 )) "" true
  jq -nc --argjson now $now 'range(1; 5000) | {id: ("task-agent-" + (tostring)), title: ("Agent work " + (tostring)),
    status: "done", summarySource: "heuristic", project: ("p" + (tostring)), agents: ["claude"], sessionIds: [],
    manual: false, createdAt: ($now - 86400 + .), updatedAt: ($now - 86400 + .)}'
} | seed_tasks
board_app
assert_eq "$(task_count)" 5000 "tasks after launch"
assert_eq "$(ambient tasks --json | jq -r '.[] | select(.id == "task-manual") | .title')" "Written by me" "the 30-day-old task you wrote"

S='{"session_id":"brd020-claude","cwd":"'$QA_ROOT'/fresh-project"'
hook claude "$S"',"hook_event_name":"UserPromptSubmit","prompt":"go"}'
hook claude "$S"',"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls"}}'
wait_for 10 test "$(ambient tasks --json | jq -r '[.[] | select(.project == "fresh-project")] | length')" = 1
json=$(ambient tasks --json)
assert_eq "$(print -r -- $json | jq length)" 5000 "tasks on a full board"
assert_eq "$(print -r -- $json | jq -r '[.[] | select(.id == "task-manual")] | length')" 1 "the task you wrote (the oldest) stays"
assert_eq "$(print -r -- $json | jq -r '[.[] | select(.id == "task-agent-1")] | length')" 0 "the oldest agent-made task made room"
assert_eq "$(print -r -- $json | jq -r '[.[] | select(.id == "task-agent-2")] | length')" 1 "the next oldest agent-made task"
