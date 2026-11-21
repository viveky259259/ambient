#!/bin/zsh
# BRD-017 · A card with no chat to open can't be clicked.
# needs-app: yes
# checks: part
# Left to a person: the dimmed card, its tooltip *No chat to open*, clicking it doing nothing.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/board-lib.sh"

ambient task upsert --title "No chat" >/dev/null || fail "upsert failed"
id=$(task_get "No chat" .id)
out=$(ambient task open "$id" 2>&1); code=$?
assert_eq "$code" 1 "exit code"
assert_eq "$(unmark "$out")" "No chat to open for task '$id'." "message"
