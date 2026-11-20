#!/bin/zsh
# PRM-013 · The agent's app in front gets the prompt straight away.
# needs-app: yes
# Answering on. A recorded prompt comes from an agent whose host app (__CFBundleIdentifier, as Terminal and other apps
# set it) is the app in front, then, as a control, from one whose app is not.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/prm-lib.sh"

setup() { prm_settings true 20; }
own_app b setup
sleep 1
front=$(front_bundle)
[[ -n $front ]] || { echo "can't tell which app is in front" >&2; exit 2; }
P='{"session_id":"prm-013","hook_event_name":"PermissionRequest","cwd":"'$QA_ROOT'/api","tool_name":"Bash","tool_input":{"command":"rm -rf build"}}'
QA_ASK_ENV="__CFBundleIdentifier=$front" ask_detached "$QA_ROOT/front" "$P" hook claude --answer
ask_wait "$QA_ROOT/front" 25
[[ $(front_bundle) == $front ]] || { echo "the app in front changed during the check" >&2; exit 2; }
assert_eq "$ASK_RC" 0 "hook exit code"
assert_eq "$(<"$QA_ROOT/front")" "" "hook output: nothing answered"
(( ASK_MS < 1000 )) || fail "with $front in front the hook waited $ASK_MS ms (want at once, no card)"
note "host $front in front: handed back in $ASK_MS ms"

# Control: the same prompt from an app that isn't in front waits for the card.
P2=${P/prm-013/prm-013-bg}
ask_detached "$QA_ROOT/back" "$P2" hook claude --answer
sleep 2
ask_running "$QA_ROOT/back" || fail "control: a prompt from a background agent was handed back at once"
hook claude '{"session_id":"prm-013-bg","hook_event_name":"Stop","cwd":"'$QA_ROOT'/api"}'
ask_wait "$QA_ROOT/back" 5
