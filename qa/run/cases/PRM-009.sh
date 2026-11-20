#!/bin/zsh
# PRM-009 · Allow once allows that one call and adds no rule.
# needs-app: no
# checks: part
# Left to a person: clicking Allow once on the island card, the card closing, Claude Code running the command and leaving needs you.
# A stand-in socket answers `allow` in place of the click; this checks what the hook does with that answer.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/prm-lib.sh"

mkdir -p "$QA_ROOT/api"
fake_agent claude
prm_settings true 20
fake_island allow "$QA_ROOT/island.log"
P='{"session_id":"prm-009","transcript_path":"/tmp/t.jsonl","hook_event_name":"PermissionRequest","cwd":"'$QA_ROOT'/api","permission_mode":"default","tool_name":"Bash","tool_input":{"command":"rm -rf build","description":"Remove build"}}'
want='{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'

for round in 1 2; do
  start=$EPOCHREALTIME
  out=$(cd "$QA_ROOT/api" && print -r -- "$P" | ambient hook claude --answer)
  code=$?
  ms=$(ms_since $start)
  assert_eq "$code" 0 "hook exit code (call $round)"
  assert_eq "$out" "$want" "hook output for an allow (call $round)"
  (( ms < 2000 )) || fail "the hook took $ms ms to print an answer it already had"
  note "call $round: allow printed in $ms ms"
done

# Each call asked the island anew: two requests with different ids.
requests=$(grep -c '"permissionRequest"' "$QA_ROOT/island.log")
assert_eq "$requests" 2 "permission requests sent to the island"
ids=$(jq -r '.permissionRequest._0.id' "$QA_ROOT/island.log" 2>/dev/null | sort -u | wc -l | tr -d ' ')
assert_eq "$ids" 2 "distinct prompt ids (the second call must ask again)"

# The allow is for this call only: no rule anywhere.
hits=$(grep -rl '"allow"' "$HOME" "$QA_ROOT/api" 2>/dev/null)
assert_eq "$hits" "" "files holding a permissions.allow rule"
assert_no_file "$QA_ROOT/api/.claude/settings.local.json"
