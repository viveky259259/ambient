#!/bin/zsh
# PRM-022 · A question is never put on the card.
# needs-app: no
# checks: part
# Left to a person: the island blooming needs you with no Allow/Deny card.
# Answering is on; a stand-in socket would answer `allow` to any permission request it got.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/prm-lib.sh"

prm_settings true 20
fake_island allow "$QA_ROOT/island.log"
P='{"session_id":"prm-022","transcript_path":"/tmp/t.jsonl","hook_event_name":"PermissionRequest","cwd":"'$QA_ROOT'/api","permission_mode":"default","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Which database should I use?","header":"Database","options":[{"label":"Postgres","description":"a"},{"label":"SQLite","description":"b"}],"multiSelect":false}]}}'

start=$EPOCHREALTIME
out=$(print -r -- "$P" | ambient hook claude --answer)
code=$?
ms=$(ms_since $start)
assert_eq "$code" 0 "hook exit code"
assert_eq "$out" "" "hook output: a question gets no decision"
(( ms < 1000 )) || fail "the hook held the question for $ms ms"
note "returned in $ms ms"

wait_for 3 test -s "$QA_ROOT/island.log"
log=$(<"$QA_ROOT/island.log")
assert_not_contains "$log" '"permissionRequest"' "a question reached the island as a permission request"
assert_eq "$(jq -r '.event._0.kind.needsInput.reason' "$QA_ROOT/island.log")" "question" "what the island hears: needs you, a question"
