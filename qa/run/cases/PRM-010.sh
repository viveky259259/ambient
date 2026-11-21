#!/bin/zsh
# PRM-010 · Deny stops the call and tells the agent why.
# needs-app: no
# checks: part
# Left to a person: clicking Deny on the island card, the card closing, Claude Code reporting the denial and carrying on.
# A stand-in socket answers `deny` in place of the click; this checks what the hook prints and that it returns at once.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/prm-lib.sh"

prm_settings true 20
fake_island deny "$QA_ROOT/island.log"
P='{"session_id":"prm-010","transcript_path":"/tmp/t.jsonl","hook_event_name":"PermissionRequest","cwd":"'$QA_ROOT'","permission_mode":"default","tool_name":"Bash","tool_input":{"command":"rm -rf build"}}'

start=$EPOCHREALTIME
out=$(print -r -- "$P" | ambient hook claude --answer)
code=$?
ms=$(ms_since $start)
assert_eq "$code" 0 "hook exit code"
assert_eq "$out" '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"The user denied this from Ambient'"'"'s island."}}}' "hook output for a deny"
(( ms < 2000 )) || fail "the hook took $ms ms after the answer: the agent would hang"
note "deny printed in $ms ms"
