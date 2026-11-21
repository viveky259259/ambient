#!/bin/zsh
# BRD-022 · The board survives a quit and relaunch.
# needs-app: no
# checks: part
# Left to a person: ⌘Q writing tasks.json at once (this script stops the app by pid, which skips the quit path).
# Starts the QA app itself on a seeded tasks.json (see qa/run/board-lib.sh).
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/board-lib.sh"

now=$(ref_date 0)
{
  jq -nc --argjson at $now '{id: "task-a", title: "Write fixtures", status: "inProgress", summary: "Golden files",
    summarySource: "localLLM", summarizedAt: $at, project: "ambient", agents: ["claude", "codex"], sessionIds: [],
    manual: true, createdAt: $at, updatedAt: $at}'
  jq -nc --argjson at $(( now - 60 )) '{id: "task-b", title: "Plan phase 2", status: "backlog", summarySource: "manual",
    agents: [], sessionIds: [], manual: true, createdAt: $at, updatedAt: $at}'
  jq -nc --argjson at $(( now - 120 )) '{id: "task-c", title: "Shipped", status: "done", summary: "Released it",
    summarySource: "localLLM", agents: ["codex"], sessionIds: [], manual: false, createdAt: $at, updatedAt: $at}'
} | seed_tasks
board_app
view() { ambient tasks --json | jq -c 'map({id, title, status, summary, agents, project}) | sort_by(.id)'; }
before=$(view)
assert_eq "$(print -r -- $before | jq length)" 3 "seeded tasks loaded"

# A change reaches tasks.json about a second later.
ambient task upsert --id task-d --title "Blocked one" --status blocked >/dev/null || fail "upsert failed"
start=$EPOCHREALTIME
wait_for 5 grep -q task-d "$AMBIENT_HOME/tasks.json"
ms=$(( (EPOCHREALTIME - start) * 1000 ))
(( ms < 2000 )) || fail "tasks.json changed ${ms%.*} ms after the upsert (want about a second)"
note "tasks.json updated ${ms%.*} ms after the change"
before=$(view)

board_stop
board_app
assert_eq "$(view)" "$before" "tasks after relaunch (title, column, summary, agents)"

# A file that isn't JSON, or has another version, is an empty board, without an error.
v2=$(jq -nc --argjson at $now '{version: 2, tasks: [{id: "task-v2", title: "From version 2", status: "backlog",
  summarySource: "manual", agents: [], sessionIds: [], manual: true, createdAt: $at, updatedAt: $at}]}')
for bad in 'not json at all' "$v2"; do
  board_stop
  print -r -- "$bad" > "$AMBIENT_HOME/tasks.json"
  board_app
  assert_eq "$(ambient tasks)" "Board · no tasks" "board from a tasks.json holding [$bad]"
done
