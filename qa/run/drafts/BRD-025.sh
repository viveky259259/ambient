#!/bin/zsh
# BRD-025 · `ambient task upsert` adds a task you wrote.
# needs-app: yes
# checks: part
# Left to a person: the card appearing in In progress at once.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/board-lib.sh"

out=$(ambient task upsert --title "Write release notes" --status inProgress --project site); code=$?
assert_eq "$code" 0 "step 1 exit code"
[[ $out == "✓ Task task-"[0-9a-f](#c8)": inProgress — Write release notes" ]] || fail "step 1 printed [$out]"
id=${${out#✓ Task }%%:*}
assert_eq "$(task_get "Write release notes" .id)" "$id" "the printed id is the task's"
assert_eq "$(task_get "Write release notes" .status)" inProgress "status"
assert_eq "$(task_get "Write release notes" .project)" site "project"

out=$(ambient task upsert --title "Bad" --status started 2>&1); code=$?
assert_eq "$code" 64 "step 2 exit code"
assert_eq "$(unmark "$out")" "Unknown status 'started'. Use backlog, inProgress, blocked, done or cancelled." "step 2"

out=$(ambient task upsert --status done 2>&1); code=$?
assert_eq "$code" 64 "step 3 exit code"
assert_eq "$(unmark "$out")" "Usage: ambient task upsert --title TEXT [--id ID] [--status STATUS] [--project NAME] [--session SID]" "step 3"
assert_eq "$(task_count)" 1 "tasks after the refused upserts"

ambient task upsert --title "No status" >/dev/null || fail "upsert without --status failed"
assert_eq "$(task_get "No status" .status)" backlog "status without --status"
