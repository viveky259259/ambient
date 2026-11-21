#!/bin/zsh
# WAL-023 · The clock, date and story text.
# needs-app: yes
# timeout: 150
# checks: part
# Left to a person: the clock and date at the top-left and their format; the clock turning within 2 seconds of the
# minute; the story line's wording, semibold numbers and plurals; long titles ending in an ellipsis.
# Replays a recorded Claude Code turn of just over a minute that uses three tools and asks permission once, in place
# of a real agent, and reads today's story in day.json, the numbers the bottom-left line is written from.
source "$QA_REPO/qa/run/lib.sh"
day=$AMBIENT_HOME/day.json
mkdir -p "$QA_ROOT/api"

ev() { hook claude '{"session_id":"wal023","cwd":"'$QA_ROOT'/api","hook_event_name":"'$1'"'${2:-}'}'; }

# Step 1: no activity yet, so nothing is counted ("A quiet day so far").
sleep 1.5
if [[ -f $day ]]; then
  assert_eq "$(jq -c '.log | [.tools, .turnsDone, .turnsFailed, .neededYou, (.projects|length), (.moments|length)]' "$day")" \
    '[0,0,0,0,0,0]' "today's story before any activity"
fi

# Step 2: one turn, longer than a minute.
ev UserPromptSubmit ',"prompt":"tidy the build"'
ev PreToolUse ',"tool_name":"Read","tool_input":{"file_path":"Package.swift"}'
ev PostToolUse ',"tool_name":"Read","tool_input":{"file_path":"Package.swift"},"tool_response":{}'
ev PreToolUse ',"tool_name":"Grep","tool_input":{"pattern":"target"}'
ev PostToolUse ',"tool_name":"Grep","tool_input":{"pattern":"target"},"tool_response":{}'
ev PermissionRequest ',"tool_name":"Bash","tool_input":{"command":"rm -rf build"}'
ev PreToolUse ',"tool_name":"Bash","tool_input":{"command":"rm -rf build"}'
ev PostToolUse ',"tool_name":"Bash","tool_input":{"command":"rm -rf build"},"tool_response":{"stdout":""}'
note "waiting 62 s so the turn runs over a minute"
sleep 62
ev Stop ',"last_assistant_message":"Removed the build folder."'

turns_done() { [[ $(jq -r '.log.turnsDone' "$day" 2>/dev/null) == "$1" ]]; }
wait_for 10 turns_done 1
note "story: $(jq -c '.log | del(.marks, .moments, .day)' "$day")"
assert_eq "$(jq -r '.log.tools' "$day")" 3 "tools"
assert_eq "$(jq -r '.log.turnsDone' "$day")" 1 "turns done"
assert_eq "$(jq -r '.log.turnsFailed' "$day")" 0 "failed turns"
assert_eq "$(jq -r '.log.neededYou' "$day")" 1 "calls for you"
assert_eq "$(jq -c '.log.projects' "$day")" '["api"]' "projects"
assert_eq "$(jq -r '.log.finishedSeconds >= 60 and .log.finishedSeconds < 90' "$day")" true "agent time is the turn's minute"
assert_eq "$(jq -r '.log.longestRun >= 60 and .log.longestRun < 90' "$day")" true "longest run is the turn's minute"
