#!/bin/zsh
# BRD-019 · A task the agents made leaves the board three days after its last session ends.
# needs-app: no
# checks: part
# Left to a person: the check repeating every 10 minutes while Ambient runs.
# Starts the QA app itself on a seeded tasks.json (see qa/run/board-lib.sh).
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/board-lib.sh"

{
  seed_task task-old "Three days and an hour" done $(ref_date $(( -3 * 86400 - 3600 ))) api
  seed_task task-recent "Two days" done $(ref_date $(( -2 * 86400 ))) api
} | seed_tasks
board_app
json=$(ambient tasks --json)
assert_eq "$(print -r -- $json | jq -r 'map(.id) | join(",")')" task-recent "tasks after launch"
wait_for 5 grep -q task-recent "$AMBIENT_HOME/tasks.json"
sleep 1.5
assert_not_contains "$(cat $AMBIENT_HOME/tasks.json)" task-old "tasks.json after launch"
