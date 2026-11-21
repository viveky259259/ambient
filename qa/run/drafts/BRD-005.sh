#!/bin/zsh
# BRD-005 · A failed turn also blocks the task.
# needs-app: yes
# checks: part
# Left to a person: the red mood dot on the card.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/board-lib.sh"

mkdir -p "$QA_ROOT/qa-err"
ambient emit start --session qa-err --agent Build --cwd "$QA_ROOT/qa-err" || fail "emit start failed"
ambient emit working --session qa-err --tool make --detail "make all" || fail "emit working failed"
wait_for 5 test "$(task_get qa-err .status)" = inProgress
note "after working: $(task_get qa-err .status)"
ambient emit error --session qa-err --message "make failed" || fail "emit error failed"
wait_for 5 test "$(task_get qa-err .status)" = blocked
assert_eq "$(task_count)" 1 "tasks on the board"
