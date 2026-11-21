#!/bin/zsh
# BRD-003 · A different project, machine or day starts a new task.
# needs-app: no
# checks: part
# Left to a person: another machine's sessions starting their own task (needs a paired Mac).
# Starts the QA app itself on a seeded tasks.json (see qa/run/board-lib.sh) holding yesterday's task for qa-board-a,
# then replays Claude Code sessions in qa-board-a, qa-board-b and qa-board-c.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/board-lib.sh"

midnight=$(( $(date -j -f %Y-%m-%d "$(date +%Y-%m-%d)" +%s) ))
yesterday=$(( midnight - 3600 - 978307200 ))
{
  # Yesterday's task for qa-board-a, the same title a new session gets.
  jq -nc --argjson at $yesterday --arg cwd "$QA_ROOT/qa-board-a" '{id: "task-yesterday", title: "qa-board-a", status: "done",
    summarySource: "heuristic", project: "qa-board-a", cwd: $cwd, agents: ["claude"], sessionIds: [], manual: false,
    createdAt: $at, updatedAt: $at}'
  # Today's task for qa-board-c, in other case, with spaces around and a longer title the new one is a prefix of.
  jq -nc --argjson at $(ref_date -60) '{id: "task-today-c", title: "  QA-Board-C Extended  ", status: "backlog",
    summarySource: "heuristic", project: "qa-board-c", agents: [], sessionIds: [], manual: false, createdAt: $at, updatedAt: $at}'
} | seed_tasks
board_app
assert_eq "$(task_count)" 2 "seeded tasks loaded"

session() { # name folder
  mkdir -p "$QA_ROOT/$2"
  local S='{"session_id":"'$1'","cwd":"'$QA_ROOT/$2'"'
  hook claude "$S"',"hook_event_name":"UserPromptSubmit","prompt":"go"}'
  hook claude "$S"',"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls"}}'
}
session brd003-a qa-board-a
session brd003-b qa-board-b
wait_for 5 test "$(task_count)" = 4
json=$(ambient tasks --json)
# One card per project, and today's qa-board-a session did not join yesterday's task.
assert_eq "$(print -r -- $json | jq -r '[.[] | select(.project == "qa-board-a")] | length')" 2 "qa-board-a tasks (yesterday's and today's)"
assert_eq "$(print -r -- $json | jq -r '.[] | select(.id == "task-yesterday") | .sessionIds | length')" 0 "sessions on yesterday's task"
assert_eq "$(print -r -- $json | jq -r '[.[] | select(.project == "qa-board-b")] | length')" 1 "qa-board-b tasks"

# Case, surrounding spaces and a prefix still join today's task.
session brd003-c qa-board-c
sleep 1
json=$(ambient tasks --json)
assert_eq "$(print -r -- $json | jq length)" 4 "tasks after the qa-board-c session"
assert_eq "$(print -r -- $json | jq -r '.[] | select(.id == "task-today-c") | .sessionIds | join(",")')" claude:brd003-c "the qa-board-c session joined today's task"
