#!/bin/zsh
# BRD-006 · A task you added still turns Blocked when its session needs you.
# needs-app: yes
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/board-lib.sh"

ambient task upsert --title "Hand-made" --status backlog --session custom:qa-manual >/dev/null || fail "upsert failed"
assert_eq "$(task_get Hand-made .status)" backlog "status after upsert"
ambient emit waiting --session qa-manual --message "Pick a branch" || fail "emit waiting failed"
wait_for 5 test "$(task_get Hand-made .status)" = blocked
json=$(ambient tasks --json)
assert_eq "$(print -r -- $json | jq length)" 1 "tasks on the board (the session joined the task, no new one)"
assert_eq "$(print -r -- $json | jq -r '.[0].title')" Hand-made "title"
assert_eq "$(print -r -- $json | jq -r '.[0].manual')" true "manual"
