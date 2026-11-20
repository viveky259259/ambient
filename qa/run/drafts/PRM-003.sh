#!/bin/zsh
# PRM-003 · The setting can't be turned on while the island is off.
# needs-app: yes
# checks: part
# Left to a person: step 2 (the toggle and wait menu disabled, the subtitle text) and that nothing appears at the notch.
# Step 3: Ambient starts with answering on and Show agent status off; a recorded prompt goes through the --answer hook
# from an agent whose app is not in front.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/prm-lib.sh"

setup() {
  prm_settings true 20
  defaults write com.viveky259259.Ambient.qa islandEnabled -bool false
}
own_app b setup
P='{"session_id":"prm-003","hook_event_name":"PermissionRequest","cwd":"'$QA_ROOT'/api","tool_name":"Bash","tool_input":{"command":"rm -rf build"}}'
ask_detached "$QA_ROOT/ask" "$P" hook claude --answer
ask_wait "$QA_ROOT/ask" 25
assert_eq "$ASK_RC" 0 "hook exit code"
assert_eq "$(<"$QA_ROOT/ask")" "" "hook output: nothing answered"
(( ASK_MS < 1000 )) || fail "the hook waited $ASK_MS ms with the island off (want at once)"
note "handed back in $ASK_MS ms"
