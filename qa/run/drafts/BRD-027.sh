#!/bin/zsh
# BRD-027 · `ambient task` without a known subcommand says what it takes.
# needs-app: no
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/board-lib.sh"

out=$(ambient task 2>&1); code=$?; out=$(unmark "$out")
assert_eq "$code" 64 "ambient task exit code"
assert_eq "$out" "Usage: ambient task upsert … | ambient task open ID | ambient task model [PATH] | ambient task skill-bootstrap" "ambient task"

out=$(ambient task frobnicate 2>&1); code=$?; out=$(unmark "$out")
assert_eq "$code" 64 "ambient task frobnicate exit code"
assert_eq "$out" "Unknown task command 'frobnicate'. Use upsert, open, model, skill-bootstrap or skill-status." "ambient task frobnicate"

out=$(ambient task open 2>&1); code=$?; out=$(unmark "$out")
assert_eq "$code" 64 "ambient task open exit code"
assert_eq "$out" "Usage: ambient task open ID" "ambient task open"
