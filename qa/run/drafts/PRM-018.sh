#!/bin/zsh
# PRM-018 · A ninth waiting prompt goes straight to the agent.
# needs-app: yes
# checks: part
# Left to a person: the card reading 1 of 8.
# Answering on, wait 20 s. Nine sessions raise prompts through the --answer hook before any is answered.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/prm-lib.sh"

setup() { prm_settings true 20; }
own_app b setup
P() { print -r -- '{"session_id":"prm-018-'$1'","hook_event_name":"PermissionRequest","cwd":"'$QA_ROOT'/p'$1'","tool_name":"Bash","tool_input":{"command":"make '$1'"}}'; }
for i in {1..8}; do ask_detached "$QA_ROOT/ask$i" "$(P $i)" hook claude --answer; done
sleep 1
for i in {1..8}; do ask_running "$QA_ROOT/ask$i" || fail "prompt $i was handed back before the queue was full"; done

ask_detached "$QA_ROOT/ask9" "$(P 9)" hook claude --answer
ask_wait "$QA_ROOT/ask9" 25
assert_eq "$(<"$QA_ROOT/ask9")" "" "ninth prompt: hook output"
(( ASK_MS < 1000 )) || fail "the ninth prompt waited $ASK_MS ms (want straight to the agent)"
note "ninth prompt handed back in $ASK_MS ms"
for i in {1..8}; do ask_running "$QA_ROOT/ask$i" || fail "prompt $i left the queue when the ninth arrived"; done

# Let the eight go.
for i in {1..8}; do hook claude '{"session_id":"prm-018-'$i'","hook_event_name":"Stop","cwd":"'$QA_ROOT'/p'$i'"}'; done
for i in {1..8}; do ask_wait "$QA_ROOT/ask$i" 5; done
