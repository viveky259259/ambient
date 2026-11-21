#!/bin/zsh
# PRM-023 · Other agents' prompts stay in their own windows.
# needs-app: no
# checks: part
# Left to a person: the island showing needs you for these agents with no buttons, and each agent's own prompt.
# Answering is on and a stand-in socket would answer `allow`. Recorded permission prompts from Gemini CLI, Copilot
# CLI and OpenCode go through their hooks (with and without --answer); none may ask the island or get a decision.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/prm-lib.sh"

prm_settings true 20
for a in gemini copilot opencode cursor antigravity; do fake_agent $a; done
mkdir -p "$HOME/.gemini/antigravity"
ambient install gemini copilot opencode cursor antigravity >/dev/null || fail "ambient install failed"
for f in .gemini/settings.json .copilot/hooks/ambient.json .config/opencode/plugins/ambient.js .cursor/hooks.json .gemini/config/hooks.json; do
  assert_file "$HOME/$f"
  assert_not_contains "$(<"$HOME/$f")" "--answer" "$f: no agent but Claude Code and Codex gets a waiting hook"
done

fake_island allow "$QA_ROOT/island.log"
ts=$(( int(EPOCHREALTIME * 1000) ))
run() { # label expected-output agent [args...] <<< json
  local label=$1 want=$2 json=$3; shift 3
  local start=$EPOCHREALTIME out code ms
  out=$(print -r -- "$json" | ambient hook "$@")
  code=$?
  ms=$(ms_since $start)
  assert_eq "$code" 0 "$label exit code"
  assert_eq "$out" "$want" "$label output"
  (( ms < 1000 )) || fail "$label: the hook held the agent for $ms ms"
  note "$label: returned in $ms ms"
}
G='{"session_id":"prm-023-g","hook_event_name":"Notification","cwd":"'$QA_ROOT'","notification_type":"ToolPermission","message":"Tool Shell requires execution","details":{"type":"exec","title":"Confirm Shell Command","command":"rm -rf build","rootCommand":"rm"}}'
C='{"sessionId":"prm-023-c","cwd":"'$QA_ROOT'","hook_event_name":"Notification","notification_type":"permission_prompt","message":"Allow shell command: rm -rf build?"}'
O='{"session_id":"prm-023-o","hook_event_name":"Permission","cwd":"'$QA_ROOT'","ts":'$ts',"permission":"bash","patterns":["rm -rf build"],"metadata":{"command":"rm -rf build"}}'
# OpenCode speaks Claude's format; even a PermissionRequest from it must not ask.
O2='{"session_id":"prm-023-o2","hook_event_name":"PermissionRequest","cwd":"'$QA_ROOT'","ts":'$((ts + 1))',"tool_name":"Bash","tool_input":{"command":"rm -rf build"}}'
for flag in "" --answer; do
  run "gemini $flag" '{}' "$G" gemini $flag
  run "copilot $flag" '' "$C" copilot notification $flag
  run "opencode $flag" '' "$O" opencode $flag
  run "opencode PermissionRequest $flag" '' "$O2" opencode $flag
done

sleep 0.3
log=$(<"$QA_ROOT/island.log")
assert_not_contains "$log" '"permissionRequest"' "another agent's prompt reached the island as a permission request"
waiting=$(jq -r 'select(.event._0.kind.needsInput) | .event._0.agent' "$QA_ROOT/island.log" | sort -u | tr '\n' ' ')
assert_eq "$waiting" "copilot gemini opencode " "agents the island hears needing you"
