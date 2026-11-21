#!/bin/zsh
# PRM-027 · A damaged or hand-edited setting falls back safely.
# needs-app: no
# checks: part
# Left to a person: what Settings › Alerts shows for each file (the toggle off; 60 seconds; 30 seconds).
# The hook and `ambient doctor` read the file the same way the app does (PermissionSettings.load).
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/prm-lib.sh"

fake_island allow "$QA_ROOT/island.log"
P='{"session_id":"prm-027","hook_event_name":"PermissionRequest","cwd":"'$QA_ROOT'","tool_name":"Bash","tool_input":{"command":"rm -rf build"}}'

# 1: unreadable means off, so no hook waits or asks.
print -r -- '{ nope' > "$AMBIENT_HOME/permissions.json"
start=$EPOCHREALTIME
out=$(print -r -- "$P" | ambient hook claude --answer)
ms=$(ms_since $start)
assert_eq "$out" "" "hook output with a damaged permissions.json"
(( ms < 1000 )) || fail "the hook waited $ms ms with a damaged permissions.json"
sleep 0.2
assert_not_contains "$(<"$QA_ROOT/island.log")" '"permissionRequest"' "a damaged setting made the hook ask the island"
assert_not_contains "$(ambient doctor 2>&1)" "Permission prompts" "doctor with a damaged setting (must read as off)"

# 2 and 3: an out-of-range wait snaps to the nearest offered one.
print -r -- '{"enabled": true, "wait": 9999}' > "$AMBIENT_HOME/permissions.json"
assert_contains "$(ambient doctor 2>&1)" "waiting 60s before the agent asks" "wait 9999"
print -r -- '{"enabled": true, "wait": 26}' > "$AMBIENT_HOME/permissions.json"
assert_contains "$(ambient doctor 2>&1)" "waiting 30s before the agent asks" "wait 26"
