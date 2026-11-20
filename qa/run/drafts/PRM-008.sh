#!/bin/zsh
# PRM-008 · The card names the agent, project and exactly what will run.
# needs-app: yes
# checks: part
# Left to a person: the card itself (amber hand, api, Claude tag, 20s countdown, wants to use Bash, rm -rf build in monospace, Answer in Terminal, Deny, Allow once), the menu bar and Dock showing needs you, hovering keeping the card.
# Checks that the prompt is held for the card and that the session counts as needs you meanwhile.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/prm-lib.sh"

setup() { prm_settings true 20; }
own_app b setup
mkdir -p "$QA_ROOT/api"
P='{"session_id":"prm-008","transcript_path":"/tmp/t.jsonl","hook_event_name":"PermissionRequest","cwd":"'$QA_ROOT'/api","permission_mode":"default","tool_name":"Bash","tool_input":{"command":"rm -rf build"}}'
ask_detached "$QA_ROOT/ask" "$P" hook claude --answer
wait_for 3 sess_is prm-008 .activity.waiting.reason command
assert_eq "$(sess prm-008 .activity.waiting.message)" "rm -rf build" "what the session needs"
assert_eq "$(sess prm-008 .acknowledged)" false "the session counts as needs you"
assert_eq "$(sess prm-008 .cwd)" "$QA_ROOT/api" "the project"
sleep 1
ask_running "$QA_ROOT/ask" || fail "the prompt was handed back instead of waiting on the card"

# Let it go: the turn ends, which withdraws the card.
hook claude '{"session_id":"prm-008","hook_event_name":"Stop","cwd":"'$QA_ROOT'/api","last_assistant_message":"ok"}'
ask_wait "$QA_ROOT/ask" 5
assert_eq "$(<"$QA_ROOT/ask")" "" "hook output after the card was withdrawn"
