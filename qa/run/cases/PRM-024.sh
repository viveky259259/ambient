#!/bin/zsh
# PRM-024 · Codex gets only the decision fields it accepts.
# needs-app: no
# checks: part
# Left to a person: clicking Allow once and Deny, and Codex running the first tool and refusing the second with no hook error.
# A stand-in socket answers allow, then deny, in place of the clicks.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/prm-lib.sh"

prm_settings true 20
P='{"session_id":"prm-024","transcript_path":"/tmp/rollout.jsonl","hook_event_name":"PermissionRequest","cwd":"'$QA_ROOT'","model":"gpt-5","tool_name":"apply_patch","tool_input":{"input":"*** Begin Patch\n*** Update File: src/main.rs\n*** End Patch"}}'
for answer in allow deny; do
  fake_island $answer "$QA_ROOT/island-$answer.log"
  out=$(print -r -- "$P" | ambient hook codex --answer)
  assert_eq "$?" 0 "codex hook exit code ($answer)"
  kill $QA_ISLAND_PID; wait $QA_ISLAND_PID 2>/dev/null; rm -f "$AMBIENT_HOME/ambient.sock"
  [[ -n $out ]] || fail "$answer: the hook printed nothing"
  assert_eq "$(print -r -- "$out" | jq -r '.hookSpecificOutput.hookEventName')" PermissionRequest "$answer: hookEventName"
  assert_eq "$(print -r -- "$out" | jq -r '.hookSpecificOutput.decision.behavior')" $answer "$answer: behavior"
  keys=$(print -r -- "$out" | jq -r '.hookSpecificOutput.decision | keys | join(",")')
  top=$(print -r -- "$out" | jq -r '(keys | join(",")), (.hookSpecificOutput | keys | join(","))' | tr '\n' ' ')
  assert_eq "$top" "hookSpecificOutput decision,hookEventName " "$answer: fields around the decision"
  case $answer in
    allow) assert_eq "$keys" behavior "allow: decision fields" ;;
    deny) assert_eq "$keys" behavior,message "deny: decision fields" ;;
  esac
  note "$answer: $out"
done
