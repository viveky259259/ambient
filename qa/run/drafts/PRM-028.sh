#!/bin/zsh
# PRM-028 · The hook never outlives the agent's patience.
# needs-app: yes
# timeout: 120
# checks: part
# Left to a person: the card showing ls counting down from 60s, and clicking Allow once (a stand-in socket gives the allow here).
# Answering on, wait 60 s: the exact payload from the case goes through `ambient hook claude --answer`.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/prm-lib.sh"

P='{"session_id":"t","hook_event_name":"PermissionRequest","cwd":"/tmp","tool_name":"Bash","tool_input":{"command":"ls"}}'
setup() { prm_settings true 60; }
own_app b setup
ask_detached "$QA_ROOT/ask" "$P" hook claude --answer
ask_wait "$QA_ROOT/ask" 75
assert_eq "$ASK_RC" 0 "exit code"
assert_eq "$(<"$QA_ROOT/ask")" "" "output with nobody answering"
note "handed back after $ASK_MS ms"
(( ASK_MS < 65000 )) || fail "the hook ran $ASK_MS ms, past 65 s"
(( ASK_MS >= 59500 && ASK_MS <= 60500 )) || fail "the hook ran $ASK_MS ms (want about 60 s)"
own_app_stop

export AMBIENT_HOME=$QA_ROOT/f
prm_settings true 60
fake_island allow "$QA_ROOT/island.log"
start=$EPOCHREALTIME
out=$(print -r -- "$P" | ambient hook claude --answer)
code=$?
assert_eq "$code" 0 "exit code after an allow"
assert_eq "$out" '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}' "output after an allow"
