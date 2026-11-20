#!/bin/zsh
# PRM-026 · Turning it off takes effect even before the hook is rewritten.
# needs-app: yes
# Ambient starts with answering on; permissions.json is then set to "enabled": false by hand, leaving the --answer
# hook in place, and a recorded prompt goes through it. As a control, it is set back on and the next prompt waits.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/prm-lib.sh"

setup() { prm_settings true 20; }
own_app b setup
P='{"session_id":"prm-026","hook_event_name":"PermissionRequest","cwd":"'$QA_ROOT'/api","tool_name":"Bash","tool_input":{"command":"rm -rf build"}}'

prm_settings false 20
ask_detached "$QA_ROOT/off" "$P" hook claude --answer
ask_wait "$QA_ROOT/off" 25
assert_eq "$ASK_RC" 0 "hook exit code"
assert_eq "$(<"$QA_ROOT/off")" "" "hook output with answering off in the file"
(( ASK_MS < 1000 )) || fail "the --answer hook waited $ASK_MS ms though permissions.json says off"
note "off: handed back in $ASK_MS ms"

prm_settings true 20
ask_detached "$QA_ROOT/on" "${P/prm-026/prm-026-on}" hook claude --answer
sleep 2
ask_running "$QA_ROOT/on" || fail "control: with the file back on, the prompt did not wait for the card"
hook claude '{"session_id":"prm-026-on","hook_event_name":"Stop","cwd":"'$QA_ROOT'/api"}'
ask_wait "$QA_ROOT/on" 5
