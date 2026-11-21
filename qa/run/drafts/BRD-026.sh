#!/bin/zsh
# BRD-026 · Upserting an existing id replaces that task.
# needs-app: yes
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/board-lib.sh"

ambient task upsert --id task-qa000001 --title "First" --project api --status blocked >/dev/null || fail "step 1 failed"
first=$(ambient tasks --json | jq -c '.[0]')
sleep 1.1
ambient task upsert --id task-qa000001 --title "Second" >/dev/null || fail "step 2 failed"
json=$(ambient tasks --json)
assert_eq "$(print -r -- $json | jq length)" 1 "tasks"
t=$(print -r -- $json | jq -c '.[0]')
assert_eq "$(print -r -- $t | jq -r .id)" task-qa000001 "id"
assert_eq "$(print -r -- $t | jq -r .title)" Second "title"
assert_eq "$(print -r -- $t | jq -r .status)" backlog "status"
assert_eq "$(print -r -- $t | jq -r '.project // "none"')" none "project"
assert_eq "$(print -r -- $t | jq -r .createdAt)" "$(print -r -- $first | jq -r .createdAt)" "createdAt (step 1's)"
assert_ne "$(print -r -- $t | jq -r .updatedAt)" "$(print -r -- $first | jq -r .updatedAt)" "updatedAt (step 2's)"
[[ $(print -r -- $t | jq -r .updatedAt) > $(print -r -- $first | jq -r .updatedAt) ]] || fail "updatedAt did not move forward"
assert_eq "$(print -r -- $t | jq -r .manual)" true "manual"
assert_eq "$(print -r -- $t | jq -r .summarySource)" manual "summarySource"
