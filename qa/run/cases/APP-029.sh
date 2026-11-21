#!/bin/zsh
# APP-029 · An unknown command says so and exits 64.
source "$QA_REPO/qa/run/lib.sh"

err=$(ambient frobnicate 2>&1 >/dev/null)
ambient frobnicate >$QA_ROOT/out 2>/dev/null
code=$?
assert_eq "$code" 64 "exit code"
assert_contains "$err" "Unknown command 'frobnicate'." "the error"
assert_contains "$(<$QA_ROOT/out)" "Usage" "the usage after the error"
