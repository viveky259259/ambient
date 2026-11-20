#!/bin/zsh
# WAL-024 · Latest moments, bottom-right.
# needs-app: yes
# checks: part
# Left to a person: the bottom-right of the scene shows the four newest, newest on top, each as a monospaced time and
# text such as "Claude needed you · api-server".
# Replays recorded Claude Code hooks in three projects, in place of real agents, and reads today's story in day.json,
# which the scene draws its moments from.
source "$QA_REPO/qa/run/lib.sh"
day=$AMBIENT_HOME/day.json
mkdir -p "$QA_ROOT"/{api-server,web,docs}

ev() { # project hook-event [extra json]
  hook claude '{"session_id":"wal024-'$1'","cwd":"'$QA_ROOT/$1'","hook_event_name":"'$2'"'${3:-}'}'
}
needs_you() { ev $1 Notification ',"notification_type":"agent_needs_input","message":"Which branch?"'; }

# Six moments: needed you, finished, failed, finished, failed, needed you.
ev api-server UserPromptSubmit; needs_you api-server
ev web UserPromptSubmit;        ev web Stop
ev docs UserPromptSubmit;       ev docs StopFailure ',"error_message":"Quota exceeded"'
ev api-server Stop
ev web UserPromptSubmit;        ev web StopFailure ',"error_message":"Quota exceeded"'
ev docs UserPromptSubmit;       needs_you docs

moments_are() { [[ $(jq -r '.log.moments | length' "$day" 2>/dev/null) == "$1" ]]; }
wait_for 10 moments_are 6
want='[["neededYou","docs"],["failed","web"],["done","api-server"],["failed","docs"],["done","web"],["neededYou","api-server"]]'
assert_eq "$(jq -c '[.log.moments[] | [.kind, .place]]' "$day")" "$want" "moments, newest first"
assert_eq "$(jq -c '[.log.moments[].agent] | unique' "$day")" '["claude"]' "moment agents"
assert_eq "$(jq -r '.log.neededYou' "$day")" 2 "calls for you after six moments"

# Step 2: the same session says it is waiting again, with no answer in between.
needs_you docs
sleep 2.5   # the story is saved a second after it changes
assert_eq "$(jq -r '.log.moments | length' "$day")" 6 "moments after a second waiting on the same prompt"
assert_eq "$(jq -r '.log.neededYou' "$day")" 2 "calls for you after a second waiting on the same prompt"
