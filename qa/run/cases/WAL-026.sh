#!/bin/zsh
# WAL-026 · Today's story never stores prompts, messages or commands.
# needs-app: yes
# timeout: 90
# Replays the case's three `ambient emit` lines, plus a Claude Code turn whose prompt and reply hold canaries, then
# `ambient demo`: the same Demo.tour the menu bar's Play Demo applies, sent through the socket instead.
source "$QA_REPO/qa/run/lib.sh"
day=$AMBIENT_HOME/day.json

ambient emit working --session priv --agent Build --tool bash --detail "echo TOPSECRET-1" || fail "emit working"
ambient emit waiting --session priv --message "TOPSECRET-2" || fail "emit waiting"
ambient emit done --session priv --message "TOPSECRET-3" || fail "emit done"

C='{"session_id":"wal026","cwd":"'$QA_ROOT'/api"'
hook claude "$C"',"hook_event_name":"UserPromptSubmit","prompt":"TOPSECRET-4 please"}'
hook claude "$C"',"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"echo TOPSECRET-5"}}'
hook claude "$C"',"hook_event_name":"Stop","last_assistant_message":"TOPSECRET-6 done"}'

# Both turns finished, so the story has two marks once it is saved.
turns_done() { [[ $(jq -r '.log.turnsDone' "$day" 2>/dev/null) == "$1" ]]; }
wait_for 10 turns_done 2
before=$(jq -cS '.log | del(.day)' "$day")
note "after the real sessions: $(jq -c '.log | {tools, turnsDone, neededYou, projects, moments: [.moments[].place]}' "$day")"

ambient demo >/dev/null || fail "ambient demo"
sleep 2

hits=$(grep -c TOPSECRET "$day")
assert_eq "$hits" 0 "lines of day.json holding a prompt, message or command"
assert_eq "$(jq -cS '.log | del(.day)' "$day")" "$before" "today's story after Play Demo (the demo must add nothing)"
